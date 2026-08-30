import assert from "node:assert/strict";
import { after, test } from "node:test";

import { deleteApp, initializeApp } from "firebase-admin/app";
import { Timestamp, getFirestore } from "firebase-admin/firestore";

import {
  mutateTaskResponsibilityAt,
} from "../task_responsibility.js";
import {
  mutateHandoffSessionAt,
} from "../handoff_sessions.js";
import { leaveHouseholdAt } from "../membership.js";

const projectId = process.env.COPAW_TEST_PROJECT_ID ?? "demo-copaw";
const app = initializeApp({ projectId }, "lt5-tests-admin");
const db = getFirestore(app);
let sequence = 0;

after(() => deleteApp(app));

test("release is assignee-only, idempotent, and writes one redacted v2 fact", async () => {
  const householdID = unique("release-home");
  await seedHousehold(householdID);
  await seedTask(householdID, { category: "medication", title: "Secret 5 mg" });
  const input = taskInput(householdID, "release", { mutation: unique("release") });

  const first = await mutateTaskResponsibilityAt(db, request("owner-a", input));
  const retry = await mutateTaskResponsibilityAt(db, request("owner-a", input));

  assert.equal(first.taskStatus, "unclaimed");
  assert.equal(first.taskRevision, 2);
  assert.equal(first.existing, false);
  assert.equal(retry.existing, true);
  const task = await taskRef(householdID).get();
  assert.equal(task.data().assigneeID, null);
  const events = await eventsRef(householdID).get();
  assert.equal(events.size, 1);
  assert.equal(events.docs[0].data().schemaVersion, 2);
  assert.equal(events.docs[0].data().action, "taskReleased");
  assert.equal(events.docs[0].data().taskTitle, "Medication care");
  assert.equal(JSON.stringify(events.docs[0].data()).includes("Secret"), false);

  await assert.rejects(
    mutateTaskResponsibilityAt(db, request("member-b", {
      ...taskInput(householdID, "release", { mutation: unique("forged") }),
      expectedTaskRevision: 2,
    })),
    hasCode("failed-precondition"),
  );
});

test("reassign and takeover require the documented consent actor", async () => {
  const reassignHome = unique("reassign-home");
  await seedHousehold(reassignHome);
  await seedTask(reassignHome);
  const proposed = await mutateTaskResponsibilityAt(db, request("owner-a", {
    ...taskInput(reassignHome, "requestReassign", { mutation: unique("proposal") }),
    targetMemberID: "member-b",
  }));
  assert.equal(proposed.transferStatus, "pending");
  assert.equal((await taskRef(reassignHome).get()).data().assigneeID, "owner-a");
  await assert.rejects(
    mutateTaskResponsibilityAt(db, request("member-c", transferInput({
      householdID: reassignHome,
      action: "acceptTransfer",
      transferID: proposed.transferID,
      mutation: unique("third-party"),
    }))),
    hasCode("permission-denied"),
  );
  const accepted = await mutateTaskResponsibilityAt(db, request("member-b", transferInput({
    householdID: reassignHome,
    action: "acceptTransfer",
    transferID: proposed.transferID,
    mutation: unique("accept"),
  })));
  assert.equal(accepted.taskRevision, 2);
  assert.equal(accepted.assigneeID, "member-b");
  assert.equal(accepted.transferStatus, "accepted");
  assert.equal((await eventsRef(reassignHome).get()).size, 2);

  const takeoverHome = unique("takeover-home");
  await seedHousehold(takeoverHome);
  await seedTask(takeoverHome);
  const takeover = await mutateTaskResponsibilityAt(db, request("member-b", taskInput(
    takeoverHome,
    "requestTakeover",
    { mutation: unique("takeover") },
  )));
  await assert.rejects(
    mutateTaskResponsibilityAt(db, request("member-b", transferInput({
      householdID: takeoverHome,
      action: "acceptTransfer",
      transferID: takeover.transferID,
      mutation: unique("self-accept"),
    }))),
    hasCode("permission-denied"),
  );
  const approved = await mutateTaskResponsibilityAt(db, request("owner-a", transferInput({
    householdID: takeoverHome,
    action: "acceptTransfer",
    transferID: takeover.transferID,
    mutation: unique("approve"),
  })));
  assert.equal(approved.assigneeID, "member-b");
  const terminalEvent = (await eventsRef(takeoverHome)
    .where("action", "==", "taskTakenOver").get()).docs[0].data();
  assert.equal(terminalEvent.actorID, "owner-a");
  assert.equal(terminalEvent.responsibilityFromID, "owner-a");
  assert.equal(terminalEvent.responsibilityToID, "member-b");
});

test("completion and transfer acceptance race to one authoritative result", async () => {
  const householdID = unique("task-race-home");
  await seedHousehold(householdID);
  await seedTask(householdID);
  const proposal = await mutateTaskResponsibilityAt(db, request("owner-a", {
    ...taskInput(householdID, "requestReassign", { mutation: unique("proposal") }),
    targetMemberID: "member-b",
  }));
  const results = await Promise.allSettled([
    mutateTaskResponsibilityAt(db, request("member-b", transferInput({
      householdID,
      action: "acceptTransfer",
      transferID: proposal.transferID,
      mutation: unique("accept"),
    }))),
    mutateTaskResponsibilityAt(db, request("owner-a", {
      ...taskInput(householdID, "complete", { mutation: unique("complete") }),
      expectedTaskRevision: 1,
    })),
  ]);
  assert.equal(results.filter((result) => result.status === "fulfilled").length, 1);
  const task = (await taskRef(householdID).get()).data();
  const transfer = (await transferRef(householdID, proposal.transferID).get()).data();
  assert.equal((await stateRef(householdID).get()).exists, false);
  if (task.status === "completed") {
    assert.equal(transfer.status, "superseded");
  } else {
    assert.equal(task.assigneeID, "member-b");
    assert.equal(transfer.status, "accepted");
  }
});

test("handoff offer snapshots one version and authorized actors drive lifecycle", async () => {
  const householdID = unique("handoff-home");
  await seedHousehold(householdID);
  await seedHandoff(householdID, { revision: 1, careInstructions: "Private care" });
  const start = Date.now() + 60_000;
  const offerInput = {
    householdID,
    action: "offer",
    recipientID: "member-b",
    expectedHandoffRevision: 1,
    plannedStartMilliseconds: start,
    plannedEndMilliseconds: start + 86_400_000,
    clientMutationID: unique("offer"),
  };
  const offered = await mutateHandoffSessionAt(db, request("owner-a", offerInput));
  assert.equal(offered.sessionStatus, "offered");
  assert.equal(offered.versionID, "v000001");
  await handoffRef(householdID).update({
    careInstructions: "Changed later",
    revision: 2,
    updatedAt: Timestamp.now(),
  });
  const version = await versionRef(householdID, "v000001").get();
  assert.equal(version.data().careInstructions, "Private care");
  await assert.rejects(
    mutateHandoffSessionAt(db, request("member-c", sessionInput({
      householdID,
      action: "accept",
      sessionID: offered.sessionID,
      mutation: unique("third-party"),
    }))),
    hasCode("permission-denied"),
  );
  const accepted = await mutateHandoffSessionAt(db, request("member-b", sessionInput({
    householdID,
    action: "accept",
    sessionID: offered.sessionID,
    mutation: unique("accept"),
  })), new Date(start + 1_000));
  assert.equal(accepted.sessionStatus, "accepted");
  assert.equal(accepted.sessionRevision, 2);
  const acceptedSession = await sessionRef(householdID, offered.sessionID).get();
  assert.equal(
    acceptedSession.data().acceptedAt.toMillis(),
    start + 1_000,
  );
  assert.ok(
    acceptedSession.data().acceptedAt.toMillis() <
      acceptedSession.data().plannedEndAt.toMillis(),
  );
  const closed = await mutateHandoffSessionAt(db, request("owner-a", sessionInput({
    householdID,
    action: "close",
    sessionID: offered.sessionID,
    expectedSessionRevision: 2,
    mutation: unique("close"),
  })));
  assert.equal(closed.sessionStatus, "closed");
  assert.equal(closed.activeSessionID, null);
  assert.equal((await sessionStateRef(householdID).get()).exists, false);
  const serializedEvents = JSON.stringify(
    (await eventsRef(householdID).get()).docs.map((item) => item.data()),
  );
  assert.equal(serializedEvents.includes("Private care"), false);
});

test("handoff races keep one active session and owner recovery is explicit", async () => {
  const householdID = unique("handoff-race-home");
  await seedHousehold(householdID);
  await seedHandoff(householdID);
  const start = Date.now() + 60_000;
  const offer = (mutation, recipientID) => mutateHandoffSessionAt(db, request("member-b", {
    householdID,
    action: "offer",
    recipientID,
    expectedHandoffRevision: 1,
    plannedStartMilliseconds: start,
    plannedEndMilliseconds: start + 3_600_000,
    clientMutationID: mutation,
  }));
  const raced = await Promise.allSettled([
    offer(unique("first"), "owner-a"),
    offer(unique("second"), "member-c"),
  ]);
  assert.equal(raced.filter((result) => result.status === "fulfilled").length, 1);
  const winner = raced.find((result) => result.status === "fulfilled").value;
  const recovered = await mutateHandoffSessionAt(db, request("owner-a", sessionInput({
    householdID,
    action: "cancel",
    sessionID: winner.sessionID,
    mutation: unique("owner-recovery"),
  })));
  assert.equal(recovered.sessionStatus, "cancelled");
  const session = await sessionRef(householdID, winner.sessionID).get();
  assert.equal(session.data().resolutionReason, "ownerRecovery");
});

test("true leave blocks owners and obligations, then revokes membership and tokens", async () => {
  const householdID = unique("leave-home");
  await seedHousehold(householdID);
  await assert.rejects(
    leaveHouseholdAt(db, request("owner-a", {
      householdID,
      clientMutationID: unique("owner-leave"),
    })),
    hasCode("failed-precondition", "owner"),
  );
  await seedTask(householdID, { taskID: "member-task", assigneeID: "member-b" });
  await assert.rejects(
    leaveHouseholdAt(db, request("member-b", {
      householdID,
      clientMutationID: unique("blocked-leave"),
    })),
    hasCode("failed-precondition", "assignedTask"),
  );
  await taskRef(householdID, "member-task").delete();
  await tokenRef("member-b", "phone-1").set(token("member-b", householdID));
  await tokenRef("member-b", "phone-2").set(token("member-b", "another-home"));
  const input = { householdID, clientMutationID: unique("leave") };
  const left = await leaveHouseholdAt(db, request("member-b", input));
  const retry = await leaveHouseholdAt(db, request("member-b", input));
  assert.equal(left.left, true);
  assert.equal(left.disabledInstallationCount, 1);
  assert.equal(retry.existing, true);
  assert.equal((await memberRef(householdID, "member-b").get()).exists, false);
  assert.equal((await tokenRef("member-b", "phone-1").get()).data().enabled, false);
  assert.equal((await tokenRef("member-b", "phone-2").get()).data().enabled, true);

  await memberRef(householdID, "member-b").set({
    id: "member-b",
    displayName: "Caregiver",
    inviteCode: "ABC234",
    joinedAt: Timestamp.now(),
  });
  await tokenRef("member-b", "phone-3").set(token("member-b", householdID));
  const secondLeave = await leaveHouseholdAt(db, request("member-b", {
    householdID,
    clientMutationID: unique("leave-after-rejoin"),
  }));
  assert.equal(secondLeave.left, true);
  assert.equal(secondLeave.disabledInstallationCount, 1);
  assert.equal((await memberRef(householdID, "member-b").get()).exists, false);
});

test("true leave deletes that membership's notification records", async () => {
  const householdID = unique("leave-purge-home");
  const otherHouseholdID = unique("leave-keep-home");
  await seedHousehold(householdID);
  const collections = [
    "notificationInbox",
    "notificationDeliveries",
    "notificationDigests",
    "notificationDeliveryManifests",
  ];
  // Only the first collection crosses a page boundary, which is what exercises
  // the cursor; seeding every collection that deep just slows the suite down.
  for (const name of collections) {
    const perCollection = name === collections[0] ? 305 : 3;
    let batch = db.batch();
    for (let index = 0; index < perCollection; index += 1) {
      batch.set(
        db.doc(`users/member-b/${name}/${name}-${String(index).padStart(4, "0")}`),
        { householdID, recipientID: "member-b" },
      );
      if ((index + 1) % 200 === 0) {
        await batch.commit();
        batch = db.batch();
      }
    }
    batch.set(
      db.doc(`users/member-b/${name}/${name}-other-household`),
      { householdID: otherHouseholdID, recipientID: "member-b" },
    );
    await batch.commit();
  }
  await db.doc(`users/member-b/householdNotificationPreferences/${householdID}`)
    .set({ householdID, uid: "member-b" });
  await db.doc(`users/member-b/notificationInboxState/${householdID}`)
    .set({ householdID });

  const left = await leaveHouseholdAt(db, request("member-b", {
    householdID,
    clientMutationID: unique("leave-purge"),
  }));
  assert.equal(left.left, true);

  for (const name of collections) {
    const remaining = await db.collection(`users/member-b/${name}`)
      .where("householdID", "==", householdID).get();
    assert.equal(remaining.size, 0, `${name} was not purged`);
    const preserved = await db.collection(`users/member-b/${name}`)
      .where("householdID", "==", otherHouseholdID).get();
    assert.equal(preserved.size, 1, `${name} lost another household's records`);
  }
  assert.equal(
    (await db.doc(
      `users/member-b/householdNotificationPreferences/${householdID}`,
    ).get()).exists,
    false,
  );
  assert.equal(
    (await db.doc(`users/member-b/notificationInboxState/${householdID}`).get())
      .exists,
    false,
  );
});

test("task and handoff mutation IDs are idempotent and payload-bound", async () => {
  const householdID = unique("receipt-home");
  await seedHousehold(householdID);
  await seedTask(householdID);
  const releaseInput = taskInput(householdID, "release", {
    mutation: unique("release-receipt"),
  });
  const released = await mutateTaskResponsibilityAt(db, request("owner-a", releaseInput));
  const releaseRetry = await mutateTaskResponsibilityAt(db, request("owner-a", releaseInput));
  assert.equal(released.existing, false);
  assert.equal(releaseRetry.existing, true);
  await assert.rejects(
    mutateTaskResponsibilityAt(db, request("owner-a", {
      ...releaseInput,
      expectedTaskRevision: 2,
    })),
    hasCode("invalid-argument"),
  );

  await seedHandoff(householdID);
  const start = Date.now() + 60_000;
  const offerInput = {
    householdID,
    action: "offer",
    recipientID: "member-b",
    expectedHandoffRevision: 1,
    plannedStartMilliseconds: start,
    plannedEndMilliseconds: start + 3_600_000,
    clientMutationID: unique("offer-receipt"),
  };
  const offered = await mutateHandoffSessionAt(
    db,
    request("owner-a", offerInput),
    new Date(start - 1_000),
  );
  const offerRetry = await mutateHandoffSessionAt(
    db,
    request("owner-a", offerInput),
    new Date(offerInput.plannedEndMilliseconds + 1),
  );
  assert.equal(offered.existing, false);
  assert.equal(offerRetry.existing, true);
  await assert.rejects(
    mutateHandoffSessionAt(db, request("owner-a", {
      ...offerInput,
      plannedEndMilliseconds: offerInput.plannedEndMilliseconds + 1,
    })),
    hasCode("invalid-argument"),
  );
});

test("expired handoff offers require an explicit terminal transition", async () => {
  const householdID = unique("expired-handoff-home");
  await seedHousehold(householdID);
  await seedHandoff(householdID);
  const start = Date.now() + 1_000;
  const end = start + 60_000;
  const offered = await mutateHandoffSessionAt(db, request("owner-a", {
    householdID,
    action: "offer",
    recipientID: "member-b",
    expectedHandoffRevision: 1,
    plannedStartMilliseconds: start,
    plannedEndMilliseconds: end,
    clientMutationID: unique("expiring-offer"),
  }), new Date(start));
  await assert.rejects(
    mutateHandoffSessionAt(db, request("member-b", sessionInput({
      householdID,
      action: "accept",
      sessionID: offered.sessionID,
      mutation: unique("late-accept"),
    })), new Date(end)),
    hasCode("failed-precondition"),
  );
  assert.equal((await sessionStateRef(householdID).get()).data().sessionStatus, "offered");
  const cancelled = await mutateHandoffSessionAt(db, request("owner-a", sessionInput({
    householdID,
    action: "cancel",
    sessionID: offered.sessionID,
    mutation: unique("explicit-cancel"),
  })), new Date(end));
  assert.equal(cancelled.sessionStatus, "cancelled");
});

test("true leave reports pending transfer and active handoff blockers safely", async () => {
  const householdID = unique("leave-obligation-home");
  await seedHousehold(householdID);
  await seedTask(householdID);
  const transfer = await mutateTaskResponsibilityAt(db, request("owner-a", {
    ...taskInput(householdID, "requestReassign", { mutation: unique("proposal") }),
    targetMemberID: "member-b",
  }));
  await assert.rejects(
    leaveHouseholdAt(db, request("member-b", {
      householdID,
      clientMutationID: unique("pending-transfer-leave"),
    })),
    hasCode("failed-precondition", "pendingTransfer"),
  );
  await mutateTaskResponsibilityAt(db, request("owner-a", transferInput({
    householdID,
    action: "cancelTransfer",
    transferID: transfer.transferID,
    mutation: unique("cancel-transfer"),
  })));
  await seedHandoff(householdID);
  const start = Date.now() + 60_000;
  await mutateHandoffSessionAt(db, request("owner-a", {
    householdID,
    action: "offer",
    recipientID: "member-b",
    expectedHandoffRevision: 1,
    plannedStartMilliseconds: start,
    plannedEndMilliseconds: start + 3_600_000,
    clientMutationID: unique("offer"),
  }));
  await assert.rejects(
    leaveHouseholdAt(db, request("member-b", {
      householdID,
      clientMutationID: unique("active-handoff-leave"),
    })),
    hasCode("failed-precondition", "activeHandoff"),
  );
});

test("malformed transfer and handoff sidecar semantics block mutation", async () => {
  const transferHome = unique("malformed-transfer-home");
  await seedHousehold(transferHome);
  await seedTask(transferHome);
  const transfer = await mutateTaskResponsibilityAt(db, request("owner-a", {
    ...taskInput(transferHome, "requestReassign", { mutation: unique("proposal") }),
    targetMemberID: "member-b",
  }));
  await transferRef(transferHome, transfer.transferID).update({
    consentByID: "member-c",
    consentByName: "Helper",
  });
  await assert.rejects(
    mutateTaskResponsibilityAt(db, request("member-c", transferInput({
      householdID: transferHome,
      action: "acceptTransfer",
      transferID: transfer.transferID,
      mutation: unique("malformed-accept"),
    }))),
    hasCode("failed-precondition"),
  );

  const handoffHome = unique("malformed-handoff-home");
  await seedHousehold(handoffHome);
  await seedHandoff(handoffHome);
  const start = Date.now() + 60_000;
  const offered = await mutateHandoffSessionAt(db, request("member-b", {
    householdID: handoffHome,
    action: "offer",
    recipientID: "member-c",
    expectedHandoffRevision: 1,
    plannedStartMilliseconds: start,
    plannedEndMilliseconds: start + 3_600_000,
    clientMutationID: unique("offer"),
  }));
  await sessionRef(handoffHome, offered.sessionID).update({
    recipientID: "member-b",
    recipientName: "Caregiver",
  });
  await assert.rejects(
    mutateHandoffSessionAt(db, request("member-b", sessionInput({
      householdID: handoffHome,
      action: "cancel",
      sessionID: offered.sessionID,
      mutation: unique("malformed-cancel"),
    }))),
    hasCode("failed-precondition"),
  );
});

test("true leave disables more tokens than one Firestore transaction can write", async () => {
  const householdID = unique("large-token-leave-home");
  await seedHousehold(householdID);
  const references = Array.from({ length: 501 }, (_, index) =>
    tokenRef("member-b", `phone-${String(index).padStart(3, "0")}`));
  for (let offset = 0; offset < references.length; offset += 450) {
    const batch = db.batch();
    for (const reference of references.slice(offset, offset + 450)) {
      batch.set(reference, token(reference.id, householdID));
    }
    await batch.commit();
  }

  const result = await leaveHouseholdAt(db, request("member-b", {
    householdID,
    clientMutationID: unique("large-token-leave"),
  }));

  assert.equal(result.left, true);
  assert.equal(result.disabledInstallationCount, 501);
  assert.equal((await memberRef(householdID, "member-b").get()).exists, false);
  const enabled = await db.collection("users").doc("member-b")
    .collection("notificationTokens")
    .where("householdID", "==", householdID)
    .where("enabled", "==", true)
    .get();
  assert.equal(enabled.empty, true);
});

test("true leave drains trusted notification leases and resumes with a new mutation", async () => {
  const householdID = unique("leased-leave-home");
  await seedHousehold(householdID);
  const now = Date.now();
  const claim = memberRevocationRef(householdID, "member-b")
    .collection("notificationClaims").doc("delivery-1");
  await claim.set({
    schemaVersion: 1,
    deliveryID: "delivery-1",
    recipientID: "member-b",
    tokenDocumentID: "phone-1",
    leaseUntil: Timestamp.fromMillis(now + 60_000),
    createdAt: Timestamp.fromMillis(now),
  });

  await assert.rejects(
    leaveHouseholdAt(db, request("member-b", {
      householdID,
      clientMutationID: unique("start-leave"),
    }), new Date(now)),
    hasCode("aborted"),
  );
  assert.equal((await memberRef(householdID, "member-b").get()).exists, true);
  assert.equal(
    (await memberRevocationRef(householdID, "member-b").get()).data().status,
    "draining",
  );

  const resumed = await leaveHouseholdAt(db, request("member-b", {
    householdID,
    clientMutationID: unique("resume-with-new-id"),
  }), new Date(now + 60_001));
  assert.equal(resumed.left, true);
  assert.equal(resumed.existing, true);
  assert.equal((await memberRef(householdID, "member-b").get()).exists, false);
  assert.equal((await claim.get()).exists, false);
  assert.equal(
    (await memberRevocationRef(householdID, "member-b").get()).exists,
    false,
  );
});

test("true leave blocks recent medication responsibility and fails closed on malformed rows", async () => {
  const recentHome = unique("medication-leave-home");
  await seedHousehold(recentHome);
  await medicationOccurrenceRef(recentHome, "recent-dose").set(
    medicationOccurrence("recent-dose", "member-b", Date.now() - 10 * 60_000),
  );
  await assert.rejects(
    leaveHouseholdAt(db, request("member-b", {
      householdID: recentHome,
      clientMutationID: unique("recent-dose-leave"),
    })),
    hasCode("failed-precondition", "unresolvedMedicationResponsibility"),
  );
  assert.equal((await memberRef(recentHome, "member-b").get()).exists, true);

  const malformedHome = unique("malformed-medication-leave-home");
  await seedHousehold(malformedHome);
  await medicationOccurrenceRef(malformedHome, "malformed-dose").set({
    responsibleByID: "member-b",
    responsibilityStatus: "claimed",
    outcomeStatus: "unresolved",
  });
  await assert.rejects(
    leaveHouseholdAt(db, request("member-b", {
      householdID: malformedHome,
      clientMutationID: unique("malformed-dose-leave"),
    })),
    hasCode("failed-precondition", "medicationResponsibilityNeedsRepair"),
  );
});

test("true leave removes notification preference and inbox cursor then permits rejoin", async () => {
  const householdID = unique("notification-state-leave-home");
  await seedHousehold(householdID);
  const preference = db.doc(
    `users/member-b/householdNotificationPreferences/${householdID}`,
  );
  const cursor = db.doc(`users/member-b/notificationInboxState/${householdID}`);
  await preference.set({ stale: true });
  await cursor.set({ stale: true });

  const result = await leaveHouseholdAt(db, request("member-b", {
    householdID,
    clientMutationID: unique("notification-state-leave"),
  }));
  assert.equal(result.left, true);
  assert.equal((await preference.get()).exists, false);
  assert.equal((await cursor.get()).exists, false);

  await memberRef(householdID, "member-b").set({
    id: "member-b", displayName: "Caregiver", inviteCode: "ABC234",
    joinedAt: Timestamp.now(),
  });
  assert.equal((await memberRef(householdID, "member-b").get()).exists, true);
});

test("orphan responsibility and handoff sources fail closed", async () => {
  const taskHome = unique("orphan-task-home");
  await seedHousehold(taskHome);
  await seedTask(taskHome);
  const transfer = await mutateTaskResponsibilityAt(db, request("owner-a", {
    ...taskInput(taskHome, "requestReassign", { mutation: unique("proposal") }),
    targetMemberID: "member-b",
  }));
  await stateRef(taskHome).update({ taskRevisionAtProposal: 99 });
  await assert.rejects(
    leaveHouseholdAt(db, request("member-c", {
      householdID: taskHome,
      clientMutationID: unique("malformed-transfer-pointer-leave"),
    })),
    hasCode("failed-precondition", "pendingTransfer"),
  );
  await stateRef(taskHome).delete();
  await assert.rejects(
    mutateTaskResponsibilityAt(db, request("owner-a", taskInput(
      taskHome,
      "complete",
      { mutation: unique("orphan-complete") },
    ))),
    hasCode("failed-precondition"),
  );
  await assert.rejects(
    leaveHouseholdAt(db, request("member-c", {
      householdID: taskHome,
      clientMutationID: unique("orphan-transfer-leave"),
    })),
    hasCode("failed-precondition", "pendingTransfer"),
  );
  assert.equal((await transferRef(taskHome, transfer.transferID).get()).data().status, "pending");

  const handoffHome = unique("orphan-session-home");
  await seedHousehold(handoffHome);
  await seedHandoff(handoffHome);
  const start = Date.now() + 60_000;
  await mutateHandoffSessionAt(db, request("owner-a", {
    householdID: handoffHome,
    action: "offer",
    recipientID: "member-b",
    expectedHandoffRevision: 1,
    plannedStartMilliseconds: start,
    plannedEndMilliseconds: start + 3_600_000,
    clientMutationID: unique("offer"),
  }));
  await sessionStateRef(handoffHome).update({ sessionStatus: "accepted" });
  await assert.rejects(
    leaveHouseholdAt(db, request("member-c", {
      householdID: handoffHome,
      clientMutationID: unique("malformed-handoff-pointer-leave"),
    })),
    hasCode("failed-precondition", "activeHandoff"),
  );
  await sessionStateRef(handoffHome).delete();
  await assert.rejects(
    mutateHandoffSessionAt(db, request("member-c", {
      householdID: handoffHome,
      action: "offer",
      recipientID: "member-b",
      expectedHandoffRevision: 1,
      plannedStartMilliseconds: start,
      plannedEndMilliseconds: start + 3_600_000,
      clientMutationID: unique("orphan-offer"),
    })),
    hasCode("failed-precondition"),
  );
  await assert.rejects(
    leaveHouseholdAt(db, request("member-c", {
      householdID: handoffHome,
      clientMutationID: unique("orphan-handoff-leave"),
    })),
    hasCode("failed-precondition", "activeHandoff"),
  );
});

async function seedHousehold(householdID) {
  const household = db.collection("households").doc(householdID);
  await household.set({
    id: householdID,
    name: "LT5 home",
    petName: "Mochi",
    inviteCode: "ABC234",
    timeZoneIdentifier: "Asia/Tokyo",
    ownerID: "owner-a",
    createdAt: Timestamp.now(),
  });
  for (const [id, name] of [["owner-a", "Owner"], ["member-b", "Caregiver"], ["member-c", "Helper"]]) {
    await memberRef(householdID, id).set({
      id,
      displayName: name,
      inviteCode: "ABC234",
      joinedAt: Timestamp.now(),
    });
  }
}

async function seedTask(householdID, {
  taskID = "task-1",
  assigneeID = "owner-a",
  category = "feeding",
  title = "Evening care",
} = {}) {
  const name = assigneeID === "owner-a" ? "Owner" : "Caregiver";
  await taskRef(householdID, taskID).set({
    id: taskID,
    title,
    category,
    dueTime: Timestamp.fromDate(new Date(Date.now() + 60_000)),
    kind: "oneOff",
    priority: "normal",
    routineID: null,
    petID: "legacy-primary",
    petName: "Mochi",
    status: "claimed",
    assignmentRequestID: null,
    assignmentMode: null,
    requestedByID: null,
    requestedByName: null,
    requestedToID: null,
    requestedToName: null,
    assignmentRequestedAt: null,
    assigneeID,
    assigneeName: name,
    claimedAt: Timestamp.now(),
    createdByID: "owner-a",
    createdBy: "Owner",
    createdAt: Timestamp.now(),
    completedByID: null,
    completedBy: null,
    completedAt: null,
    revision: 1,
  });
}

async function seedHandoff(householdID, {
  revision = 1,
  careInstructions = "Feed after walking",
} = {}) {
  await handoffRef(householdID).set({
    schemaVersion: 1,
    careInstructions,
    emergencyContactName: "Emergency person",
    emergencyContactPhone: "090-SECRET",
    veterinaryHospitalName: "Vet",
    veterinaryHospitalPhone: "03-SECRET",
    revision,
    updatedByID: "owner-a",
    updatedByName: "Owner",
    updatedAt: Timestamp.now(),
  });
}

function request(uid, data) {
  return { auth: { uid }, data };
}

function taskInput(householdID, action, { mutation }) {
  return {
    householdID,
    taskID: "task-1",
    action,
    expectedTaskRevision: 1,
    clientMutationID: mutation,
  };
}

function transferInput({ householdID, action, transferID, mutation }) {
  return {
    householdID,
    taskID: "task-1",
    action,
    expectedTaskRevision: 1,
    transferID,
    expectedTransferRevision: 1,
    clientMutationID: mutation,
  };
}

function sessionInput({
  householdID,
  action,
  sessionID,
  mutation,
  expectedSessionRevision = 1,
}) {
  return {
    householdID,
    action,
    sessionID,
    expectedSessionRevision,
    clientMutationID: mutation,
  };
}

function token(value, householdID) {
  return {
    token: value,
    householdID,
    platform: "ios",
    enabled: true,
    createdAt: Timestamp.now(),
    updatedAt: Timestamp.now(),
  };
}

function taskRef(householdID, taskID = "task-1") {
  return db.collection("households").doc(householdID).collection("tasks").doc(taskID);
}

function memberRef(householdID, uid) {
  return db.collection("households").doc(householdID).collection("members").doc(uid);
}

function transferRef(householdID, transferID) {
  return db.collection("households").doc(householdID)
    .collection("taskResponsibilityTransfers").doc(transferID);
}

function stateRef(householdID, taskID = "task-1") {
  return db.collection("households").doc(householdID)
    .collection("taskResponsibilityState").doc(taskID);
}

function handoffRef(householdID) {
  return db.collection("households").doc(householdID).collection("handoff").doc("current");
}

function versionRef(householdID, versionID) {
  return db.collection("households").doc(householdID)
    .collection("handoffVersions").doc(versionID);
}

function sessionRef(householdID, sessionID) {
  return db.collection("households").doc(householdID)
    .collection("handoffSessions").doc(sessionID);
}

function sessionStateRef(householdID) {
  return db.collection("households").doc(householdID).collection("handoff").doc("sessionState");
}

function eventsRef(householdID) {
  return db.collection("households").doc(householdID).collection("collaborationEvents");
}

function tokenRef(uid, tokenID) {
  return db.collection("users").doc(uid).collection("notificationTokens").doc(tokenID);
}

function memberRevocationRef(householdID, uid) {
  return db.collection("households").doc(householdID)
    .collection("membershipRevocations").doc(uid);
}

function medicationOccurrenceRef(householdID, occurrenceID) {
  return db.collection("households").doc(householdID)
    .collection("medicationOccurrences").doc(occurrenceID);
}

function medicationOccurrence(id, responsibleByID, dueAtMilliseconds) {
  return {
    schemaVersion: 1,
    id,
    medicationID: "medication-1",
    scheduleVersionID: "v000001",
    scheduleVersion: 1,
    slotID: "morning",
    localDate: "2026-08-17",
    dueAt: Timestamp.fromMillis(dueAtMilliseconds),
    timeZoneIdentifier: "Asia/Tokyo",
    petID: "legacy-primary",
    petName: "Mochi",
    medicationName: "Private medicine",
    doseText: "Private dose",
    instructions: null,
    responsibilityStatus: "claimed",
    responsibleByID,
    responsibleByName: "Caregiver",
    claimedAt: Timestamp.fromMillis(dueAtMilliseconds - 1_000),
    outcomeStatus: "unresolved",
    outcomeByID: null,
    outcomeByName: null,
    outcomeAt: null,
    skippedReasonCode: null,
    skippedReasonNote: null,
    materializedAt: Timestamp.fromMillis(dueAtMilliseconds - 2_000),
    revision: 1,
  };
}

function hasCode(code, blockerCode) {
  return (error) => error?.code === code &&
    (blockerCode == null || error?.details?.blockerCode === blockerCode);
}

function unique(prefix) {
  sequence += 1;
  return `${prefix}-${Date.now()}-${sequence}`;
}
