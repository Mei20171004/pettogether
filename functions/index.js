// Cloud Functions for pettogether (merged build).
//
// Adapted from the Kate/care-paw implementation onto the main app's Firestore
// schema: task docs use `dueTime`/`routineID`/`assigneeID`+`assigneeName`/
// `completedByID`+`completedBy`/`createdByID`+`createdBy`, households carry
// `ownerID` and `timeZoneIdentifier`, and routine occurrences use the id
// format `<routineID>_yyyy-MM-dd`.
const { onDocumentCreated, onDocumentWritten } = require("firebase-functions/v2/firestore");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { onRequest } = require("firebase-functions/v2/https");
const { defineSecret } = require("firebase-functions/params");
const logger = require("firebase-functions/logger");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore, FieldValue, Timestamp } = require("firebase-admin/firestore");
const { getMessaging } = require("firebase-admin/messaging");
const crypto = require("crypto");

initializeApp();

const db = getFirestore();
const region = "asia-northeast1";
const defaultTimeZone = "Asia/Tokyo";
const invalidTokenErrors = new Set([
  "messaging/invalid-registration-token",
  "messaging/registration-token-not-registered",
]);

/// The shared secret RevenueCat sends verbatim in the `Authorization` header
/// of every webhook call. Set it with
/// `firebase functions:secrets:set REVENUECAT_WEBHOOK_SECRET`.
const revenuecatWebhookSecret = defineSecret("REVENUECAT_WEBHOOK_SECRET");

/// Only this RevenueCat entitlement unlocks Pro. Events that carry a
/// non-empty `entitlement_ids` without it belong to some other product.
const proEntitlementId = "pet_together_pro";

/// Event types that grant access. `expiration_at_ms`, when present, still has
/// to be in the future.
const grantingEventTypes = new Set([
  "INITIAL_PURCHASE",
  "RENEWAL",
  "PRODUCT_CHANGE",
  "UNCANCELLATION",
  "NON_RENEWING_PURCHASE",
  "SUBSCRIPTION_EXTENDED",
  "TEMPORARY_ENTITLEMENT_GRANT",
]);

/// Event types that revoke access — but only once the paid period is over.
/// CANCELLATION means "will not renew", not "lost access now".
const revokingEventTypes = new Set([
  "CANCELLATION",
  "EXPIRATION",
  "SUBSCRIPTION_PAUSED",
  "REFUND",
  "BILLING_ISSUE",
]);

/// Deliberately ignored: TRANSFER moves an entitlement between anonymous ids
/// (both sides are recomputed by the RENEWAL/EXPIRATION that follows) and TEST
/// is the dashboard's "send test event" button.
const ignoredEventTypes = new Set(["TRANSFER", "TEST"]);

exports.notifyTaskChange = onDocumentWritten(
  {
    document: "households/{householdId}/tasks/{taskId}",
    region,
    maxInstances: 10,
  },
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    const payload = taskNotification(before, after);
    if (!payload) return;

    const householdId = event.params.householdId;
    const eventId = `task-${event.id}`;
    if (!(await claimNotificationEvent(householdId, eventId))) return;

    await sendToHousehold({
      householdId,
      taskId: event.params.taskId,
      ...payload,
    });
  },
);

exports.notifyJoinRequest = onDocumentCreated(
  {
    document: "households/{householdId}/joinRequests/{caregiverId}",
    region,
    maxInstances: 10,
  },
  async (event) => {
    const request = event.data?.data();
    if (!request) return;
    const householdId = event.params.householdId;
    const household = (await db.collection("households").doc(householdId).get()).data();
    const ownerId = household?.ownerID;
    if (typeof ownerId !== "string" || ownerId.length === 0) return;
    if (!(await claimNotificationEvent(householdId, `join-${event.id}`))) return;

    await sendToHousehold({
      householdId,
      taskId: "",
      type: "join_request",
      title: "New caregiver request",
      body: `${request.name || "Someone"} wants to join your care household.`,
      recipientIds: [ownerId],
    });
  },
);

/// Sends a reminder 10–25 minutes before an eligible recurring routine.
/// The dedupe document prevents repeats when Cloud Scheduler retries a run.
exports.sendRoutineReminders = onSchedule(
  {
    schedule: "every 10 minutes",
    timeZone: defaultTimeZone,
    region,
    maxInstances: 1,
  },
  async () => {
    const routines = await db.collectionGroup("routines").get();
    const households = new Map();

    // Day-specific routine overrides carry their own due time. Processing
    // them separately keeps reminders aligned when someone changes only
    // today's time, while skipped/completed occurrences stay silent.
    const reminderStart = new Date(Date.now() + 10 * 60 * 1000);
    const reminderEnd = new Date(Date.now() + 25 * 60 * 1000);
    const overrides = await db
      .collectionGroup("tasks")
      .where("dueTime", ">=", reminderStart)
      .where("dueTime", "<=", reminderEnd)
      .get();

    for (const overrideDocument of overrides.docs) {
      const task = overrideDocument.data();
      if (
        typeof task.routineID !== "string" ||
        task.routineID.length === 0 ||
        task.status === "skipped" ||
        task.status === "completed"
      ) {
        continue;
      }
      const householdId = overrideDocument.ref.parent.parent.id;
      let household = households.get(householdId);
      if (household === undefined) {
        household = (await db.collection("households").doc(householdId).get()).data() || null;
        households.set(householdId, household);
      }
      if (!household) continue;

      const eventId = `routine-${overrideDocument.id}`;
      if (!(await claimNotificationEvent(householdId, eventId))) continue;
      await sendToHousehold({
        householdId,
        taskId: overrideDocument.id,
        type: "routine_reminder",
        title: "Care reminder",
        body: `${task.title || "A care task"} is coming up soon.`,
      });
    }

    for (const routineDocument of routines.docs) {
      const householdId = routineDocument.ref.parent.parent.id;
      let household = households.get(householdId);
      if (household === undefined) {
        household = (await db.collection("households").doc(householdId).get()).data() || null;
        households.set(householdId, household);
      }
      if (!household) continue;

      const routine = routineDocument.data();
      const dateKey = routineReminderDateKey(
        routine,
        household.timeZoneIdentifier || household.timeZone || defaultTimeZone,
        new Date(),
      );
      if (!dateKey) continue;

      const taskId = `${routineDocument.id}_${dateKey}`;
      const occurrence = await db
        .collection("households")
        .doc(householdId)
        .collection("tasks")
        .doc(taskId)
        .get();
      if (occurrence.exists) continue;

      const eventId = `routine-${taskId}`;
      if (!(await claimNotificationEvent(householdId, eventId))) continue;

      await sendToHousehold({
        householdId,
        taskId,
        type: "routine_reminder",
        title: "Care reminder",
        body: `${routine.title || "A care task"} is coming up soon.`,
      });
    }
  },
);

/// Nudges the household about vaccinations and dewormings coming due, a week
/// ahead and again on the day.
exports.sendHealthDueReminders = onSchedule(
  {
    schedule: "0 9 * * *",
    timeZone: defaultTimeZone,
    region,
    maxInstances: 1,
  },
  async () => {
    const records = await db.collectionGroup("healthRecords").get();
    const now = new Date();

    for (const recordDocument of records.docs) {
      const record = recordDocument.data();
      if (record.type !== "vaccination" && record.type !== "deworming") continue;
      const dueAt = record.nextDueAt?.toDate ? record.nextDueAt.toDate() : null;
      if (!dueAt) continue;

      const days = Math.round((dueAt.getTime() - now.getTime()) / 86400000);
      if (days !== 7 && days !== 0) continue;

      const householdId = recordDocument.ref.parent.parent.id;
      const eventId = `health-due-${recordDocument.id}-${days}`;
      if (!(await claimNotificationEvent(householdId, eventId))) continue;

      const subject = record.petNameSnapshot
        ? `${record.petNameSnapshot}'s ${record.title || "next dose"}`
        : record.title || "A vaccination";
      await sendToHousehold({
        householdId,
        taskId: recordDocument.id,
        type: "health_due",
        title: days === 0 ? "Due today" : "Due next week",
        body:
          days === 0
            ? `${subject} is due today.`
            : `${subject} is due in a week.`,
      });
    }
  },
);

/// RevenueCat server-to-server webhook.
///
/// The contract, end to end:
///   * RevenueCat POSTs `{ "event": { ... } }` with the shared secret in the
///     `Authorization` header. `event.app_user_id` is the Firebase uid, which
///     the client sets via `Purchases.logIn(uid)`.
///   * This function is the ONLY writer of `entitlements/{uid}` and of
///     `households/{householdId}/private/pro`; Security Rules deny both to
///     every client, so purchase state can never be forged from the app.
///   * `entitlements/{uid}` is the per-user truth. The household mirror is
///     derived from it: a household is Pro when ANY of its members is, which
///     is what lets one paying caregiver cover the whole family. `sponsorUid`
///     records who is paying so the UI can say so.
///   * The mirror is written with merge because `legacy` on that doc belongs
///     to scripts/backfill_legacy_pro.js and must survive every webhook write.
///
/// Anything we deliberately skip answers 200 so RevenueCat stops retrying it;
/// only a failed Firestore write answers 500 and earns a retry.
exports.revenuecatWebhook = onRequest(
  {
    region,
    secrets: [revenuecatWebhookSecret],
    maxInstances: 10,
    cors: false,
    // RevenueCat calls this from its own servers, so Google's IAM check has to
    // be open; the Authorization secret above is what actually authenticates.
    invoker: "public",
  },
  async (request, response) => {
    if (request.method !== "POST") {
      response.status(405).send("Method Not Allowed");
      return;
    }
    if (!authorizedWebhook(request.get("Authorization"))) {
      // Nothing from the request is logged here: the header is the secret.
      logger.warn("RevenueCat webhook rejected: bad authorization");
      response.status(401).send("Unauthorized");
      return;
    }

    const event = webhookEvent(request.body);
    if (!event) {
      logger.warn("RevenueCat webhook ignored: no event payload");
      response.status(200).send("ignored");
      return;
    }

    const eventType = typeof event.type === "string" ? event.type : "";
    const uid = typeof event.app_user_id === "string" ? event.app_user_id.trim() : "";
    if (uid.length === 0) {
      logger.warn("RevenueCat webhook ignored: missing app_user_id", { eventType });
      response.status(200).send("ignored");
      return;
    }
    // An anonymous id means the purchase happened before the app called
    // Purchases.logIn(uid). The TRANSFER/RENEWAL that follows the login
    // carries the real uid, so there is nothing to store yet.
    if (uid.startsWith("$RCAnonymousID:")) {
      logger.info("RevenueCat webhook ignored: anonymous app_user_id", { eventType });
      response.status(200).send("ignored");
      return;
    }
    if (ignoredEventTypes.has(eventType)) {
      logger.info("RevenueCat webhook ignored by type", { eventType, uid });
      response.status(200).send("ignored");
      return;
    }

    const entitlementIds = Array.isArray(event.entitlement_ids)
      ? event.entitlement_ids.filter((id) => typeof id === "string")
      : null;
    if (entitlementIds && entitlementIds.length > 0 &&
        !entitlementIds.includes(proEntitlementId)) {
      logger.info("RevenueCat webhook ignored: not the pro entitlement", {
        eventType,
        uid,
        entitlementIds,
      });
      response.status(200).send("ignored");
      return;
    }

    const expiresAt = expirationTimestamp(event.expiration_at_ms);
    const active = entitlementActive(eventType, expiresAt);
    if (active === null) {
      logger.info("RevenueCat webhook ignored: unhandled type", { eventType, uid });
      response.status(200).send("ignored");
      return;
    }

    try {
      await db.collection("entitlements").doc(uid).set(
        {
          active,
          expiresAt,
          productId: typeof event.product_id === "string" ? event.product_id : null,
          store: typeof event.store === "string" ? event.store : null,
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
      const households = await recomputeHouseholdsForMember(uid);
      logger.info("RevenueCat entitlement stored", {
        eventType,
        uid,
        active,
        households,
      });
      response.status(200).send("ok");
    } catch (error) {
      logger.error("RevenueCat webhook write failed", {
        eventType,
        uid,
        message: error.message,
      });
      response.status(500).send("Internal Server Error");
    }
  },
);

/// Constant-time comparison of the `Authorization` header with the configured
/// secret. Buffers of different lengths are rejected before timingSafeEqual,
/// which throws on a length mismatch.
function authorizedWebhook(headerValue) {
  const provided = Buffer.from(
    typeof headerValue === "string" ? headerValue : "",
    "utf8",
  );
  const expected = Buffer.from(revenuecatWebhookSecret.value() || "", "utf8");
  if (expected.length === 0 || provided.length !== expected.length) return false;
  return crypto.timingSafeEqual(provided, expected);
}

/// RevenueCat posts JSON, but a misconfigured content type arrives as a raw
/// body, so parse defensively rather than throwing inside the handler.
function webhookEvent(body) {
  let payload = body;
  if (Buffer.isBuffer(payload)) payload = payload.toString("utf8");
  if (typeof payload === "string") {
    if (payload.length === 0) return null;
    try {
      payload = JSON.parse(payload);
    } catch (_) {
      return null;
    }
  }
  const event = payload?.event;
  return event && typeof event === "object" ? event : null;
}

function expirationTimestamp(value) {
  const millis = Number(value);
  if (!Number.isFinite(millis) || millis <= 0) return null;
  return Timestamp.fromMillis(millis);
}

/// true = grant, false = revoke, null = an event type we do not act on.
function entitlementActive(eventType, expiresAt) {
  const expired = expiresAt !== null && expiresAt.toMillis() <= Date.now();
  if (grantingEventTypes.has(eventType)) return !expired;
  // A cancellation or billing issue leaves the paid period intact; access
  // only ends once that period has passed.
  if (revokingEventTypes.has(eventType)) return !expired && expiresAt !== null;
  return null;
}

/// Recomputes the Pro mirror of every household the user belongs to and
/// returns how many were touched.
async function recomputeHouseholdsForMember(uid) {
  const memberships = await db.collectionGroup("members").where("id", "==", uid).get();
  const households = new Map();
  for (const membership of memberships.docs) {
    const householdReference = membership.ref.parent.parent;
    if (householdReference) households.set(householdReference.path, householdReference);
  }
  for (const householdReference of households.values()) {
    await recomputeHouseholdPro(householdReference);
  }
  return households.size;
}

/// A household is Pro when any of its members has an active entitlement. The
/// mirror exists so Security Rules and the UI can answer "is this household
/// Pro?" with a single document read instead of a fan-out over members.
async function recomputeHouseholdPro(householdReference) {
  const members = await householdReference.collection("members").get();
  const memberIds = [];
  for (const member of members.docs) {
    const id = typeof member.data().id === "string" && member.data().id.length > 0
      ? member.data().id
      : member.id;
    if (!memberIds.includes(id)) memberIds.push(id);
  }

  let active = false;
  let sponsorUid = null;
  let expiresAt = null;
  // A non-expiring active entitlement (lifetime, or a grant with no
  // expiration) outranks every dated one, so the mirror keeps a null expiry.
  let unbounded = false;

  for (const group of chunks(memberIds, 300)) {
    if (group.length === 0) continue;
    const entitlements = await db.getAll(
      ...group.map((id) => db.collection("entitlements").doc(id)),
    );
    for (const entitlement of entitlements) {
      if (!entitlement.exists || entitlement.data().active !== true) continue;
      if (!active) {
        active = true;
        sponsorUid = entitlement.id;
      }
      const memberExpiry = entitlement.data().expiresAt || null;
      if (!memberExpiry) {
        unbounded = true;
      } else if (!unbounded &&
          (expiresAt === null || memberExpiry.toMillis() > expiresAt.toMillis())) {
        expiresAt = memberExpiry;
      }
    }
  }
  if (unbounded) expiresAt = null;

  // Merge: `legacy` is owned by scripts/backfill_legacy_pro.js.
  await householdReference.collection("private").doc("pro").set(
    {
      active,
      sponsorUid,
      expiresAt,
      updatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
}

function taskNotification(before, after) {
  if (!before && !after) return null;
  if (!before && after) {
    return {
      type: "task_created",
      title: "New care task",
      body: `${caregiverName(after.createdBy)} added “${after.title || "a care task"}”.`,
      excludedIds: [caregiverId(after.createdByID)],
    };
  }
  if (!after) return null;

  if (before.status !== after.status) {
    if (after.status === "claimed") {
      return {
        type: "task_claimed",
        title: "Task claimed",
        body: `${caregiverName(after.assigneeName)} will take care of “${after.title || "a care task"}”.`,
        excludedIds: [caregiverId(after.assigneeID)],
      };
    }
    if (after.status === "completed") {
      // Telling everyone else a dose was given is what stops a second person
      // giving it again, so medication gets its own wording.
      const isMedication = after.category === "medication";
      return {
        type: "task_completed",
        title: isMedication ? "Medication given" : "Care task completed",
        body: isMedication
          ? `${caregiverName(after.completedBy)} gave “${after.title || "the medication"}”.`
          : `${caregiverName(after.completedBy)} completed “${after.title || "a care task"}”.`,
        excludedIds: [caregiverId(after.completedByID)],
      };
    }
  }

  const previousRequest = JSON.stringify(before.assignmentRequest || null);
  const nextRequest = after.assignmentRequest;
  if (nextRequest && previousRequest !== JSON.stringify(nextRequest)) {
    const sender = caregiverId(nextRequest.requestedByID);
    if (nextRequest.mode === "direct" && caregiverId(nextRequest.requestedToID)) {
      return {
        type: "direct_assignment",
        title: "A task was assigned to you",
        body: `${caregiverName(nextRequest.requestedByName)} asked you to take “${after.title || "a care task"}”.`,
        recipientIds: [caregiverId(nextRequest.requestedToID)],
      };
    }
    return {
      type: "open_assignment",
      title: "Caregiver needed",
      body: `${caregiverName(nextRequest.requestedByName)} needs help with “${after.title || "a care task"}”.`,
      excludedIds: [sender],
    };
  }
  return null;
}

async function sendToHousehold({
  householdId,
  taskId,
  type,
  title,
  body,
  recipientIds = null,
  excludedIds = [],
}) {
  const targets = await deviceTargets(householdId, recipientIds, excludedIds);
  if (targets.length === 0) return;

  for (const group of chunks(targets, 500)) {
    const response = await getMessaging().sendEachForMulticast({
      tokens: group.map((target) => target.token),
      notification: { title, body },
      data: { householdId, taskId, type, title, body },
      android: {
        priority: "high",
        notification: { channelId: "pettogether_care" },
      },
      apns: { payload: { aps: { sound: "default" } } },
    });
    await removeInvalidTokens(group, response.responses);
    logger.info("Care notification delivered", {
      householdId,
      type,
      sent: response.successCount,
      failed: response.failureCount,
    });
  }
}

async function deviceTargets(householdId, recipientIds, excludedIds) {
  const excluded = new Set(excludedIds.filter(Boolean));
  const members = recipientIds
    ? await Promise.all(
        [...new Set(recipientIds.filter(Boolean))].map((id) =>
          db.collection("households").doc(householdId).collection("members").doc(id).get(),
        ),
      )
    : (await db.collection("households").doc(householdId).collection("members").get()).docs;

  const targets = [];
  for (const member of members) {
    if (!member.exists || excluded.has(member.id)) continue;
    if (member.data().notificationsEnabled !== true) continue;
    const devices = await member.ref.collection("devices").get();
    for (const device of devices.docs) {
      const token = device.data().token;
      if (typeof token === "string" && token.length > 0) {
        targets.push({ token, reference: device.ref });
      }
    }
  }
  return targets;
}

async function removeInvalidTokens(targets, responses) {
  const stale = responses
    .map((response, index) => ({ response, target: targets[index] }))
    .filter(({ response }) => invalidTokenErrors.has(response.error?.code))
    .map(({ target }) => target.reference);
  if (stale.length === 0) return;

  const batch = db.batch();
  stale.forEach((reference) => batch.delete(reference));
  await batch.commit();
}

async function claimNotificationEvent(householdId, eventId) {
  try {
    await db
      .collection("households")
      .doc(householdId)
      .collection("notificationEvents")
      .doc(eventId)
      .create({ createdAt: new Date() });
    return true;
  } catch (error) {
    if (error.code === 6 || error.code === "already-exists") return false;
    throw error;
  }
}

function routineReminderDateKey(routine, timeZone, now) {
  const local = timeParts(timeZone, now);
  const dueMinute = Number(routine.hour) * 60 + Number(routine.minute);
  if (!Number.isFinite(dueMinute)) return null;
  const nowMinute = local.hour * 60 + local.minute;
  const delta = (dueMinute - nowMinute + 1440) % 1440;
  if (delta < 10 || delta > 25) return null;

  const dateKey = addDays(local.dateKey, dueMinute < nowMinute ? 1 : 0);
  const weekday = weekdayForDate(dateKey);
  if (!Array.isArray(routine.weekdays) || !routine.weekdays.includes(weekday)) {
    return null;
  }
  const startDateKey = routineStartDateKey(routine, timeZone);
  if (startDateKey && dateKey < startDateKey) return null;
  // A finished course must not keep nagging. endDate is inclusive, matching
  // routineRunsOn in lib/utils/care_calendar.dart.
  const endDateKey = localDateKey(routine.endDate, timeZone);
  if (endDateKey && dateKey > endDateKey) return null;
  return dateKey;
}

function localDateKey(value, timeZone) {
  if (!value) return null;
  const date = value.toDate ? value.toDate() : new Date(value);
  if (Number.isNaN(date.getTime())) return null;
  return timeParts(timeZone, date).dateKey;
}

function routineStartDateKey(routine, timeZone) {
  const startDate = routine.startDate;
  if (!startDate) return null;
  const date = startDate.toDate ? startDate.toDate() : new Date(startDate);
  const parts = timeParts(timeZone, date);
  return parts.dateKey;
}

function timeParts(timeZone, now) {
  let formatter;
  try {
    formatter = new Intl.DateTimeFormat("en-US", {
      timeZone,
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
      hour: "2-digit",
      minute: "2-digit",
      hourCycle: "h23",
    });
  } catch (_) {
    return timeParts(defaultTimeZone, now);
  }
  const values = Object.fromEntries(
    formatter.formatToParts(now).map((part) => [part.type, part.value]),
  );
  return {
    year: Number(values.year),
    month: Number(values.month),
    day: Number(values.day),
    hour: Number(values.hour),
    minute: Number(values.minute),
    dateKey: `${values.year}-${values.month}-${values.day}`,
  };
}

function addDays(dateKey, days) {
  const [year, month, day] = dateKey.split("-").map(Number);
  const date = new Date(Date.UTC(year, month - 1, day + days));
  return date.toISOString().slice(0, 10);
}

/// Weekday in the app's convention: 1 = Sunday through 7 = Saturday, matching
/// `swiftWeekday` in lib/utils/care_calendar.dart and the `weekdays` arrays
/// stored on routines and medication plans.
///
/// getUTCDay() is 0 = Sunday, so this is a straight +1 rather than the
/// Monday-first shift it used to do — that mismatch made reminders for
/// weekday-limited routines fire on the wrong day.
function weekdayForDate(dateKey) {
  const [year, month, day] = dateKey.split("-").map(Number);
  return new Date(Date.UTC(year, month - 1, day)).getUTCDay() + 1;
}

function caregiverId(value) {
  return value && typeof value === "string" ? value : "";
}

function caregiverName(value) {
  return value && typeof value === "string" ? value : "A caregiver";
}

function chunks(items, size) {
  const result = [];
  for (let index = 0; index < items.length; index += size) {
    result.push(items.slice(index, index + size));
  }
  return result;
}
