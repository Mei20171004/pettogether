// Cloud Functions for copaw (merged build).
//
// Adapted from the Kate/care-paw implementation onto the main app's Firestore
// schema: task docs use `dueTime`/`routineID`/`assigneeID`+`assigneeName`/
// `completedByID`+`completedBy`/`createdByID`+`createdBy`, households carry
// `ownerID` and `timeZoneIdentifier`, and routine occurrences use the id
// format `<routineID>_yyyy-MM-dd`.
const { onDocumentCreated, onDocumentWritten } = require("firebase-functions/v2/firestore");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const logger = require("firebase-functions/logger");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore } = require("firebase-admin/firestore");
const { getMessaging } = require("firebase-admin/messaging");

initializeApp();

const db = getFirestore();
const region = "asia-northeast1";
const defaultTimeZone = "Asia/Tokyo";
const invalidTokenErrors = new Set([
  "messaging/invalid-registration-token",
  "messaging/registration-token-not-registered",
]);

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
      return {
        type: "task_completed",
        title: "Care task completed",
        body: `${caregiverName(after.completedBy)} completed “${after.title || "a care task"}”.`,
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
        notification: { channelId: "copaw_care" },
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
  return dateKey;
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

function weekdayForDate(dateKey) {
  const [year, month, day] = dateKey.split("-").map(Number);
  const weekday = new Date(Date.UTC(year, month - 1, day)).getUTCDay();
  return weekday === 0 ? 7 : weekday;
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
