import assert from "node:assert/strict";
import { after, test } from "node:test";

import { deleteApp, initializeApp } from "firebase-admin/app";
import { Timestamp, getFirestore } from "firebase-admin/firestore";

import {
  appendTaskCollaborationEventAt,
  collaborationEventID,
} from "../collaboration.js";

const projectId = process.env.COPAW_TEST_PROJECT_ID ?? "demo-copaw";
const app = initializeApp({ projectId }, "collaboration-tests-admin");
const db = getFirestore(app);
let sequence = 0;

after(() => deleteApp(app));

test("accepted task revision appends once and trigger replay is idempotent", async () => {
  const householdID = unique("ledger-home");
  const taskID = "evening-meal";
  const taskData = task({ revision: 2, action: "taskAccepted" });

  const first = await appendTaskCollaborationEventAt(db, {
    householdID,
    taskID,
    taskData,
  });
  const replay = await appendTaskCollaborationEventAt(db, {
    householdID,
    taskID,
    taskData,
  });

  assert.equal(first.created, true);
  assert.equal(replay.created, false);
  assert.equal(
    first.eventID,
    collaborationEventID({
      sourceID: taskID,
      sourceRevision: 2,
      action: "taskAccepted",
    }),
  );
  const events = await db.collection("households").doc(householdID)
    .collection("collaborationEvents").get();
  assert.equal(events.size, 1);
  assert.equal(events.docs[0].data().actorName, "Alex");
  assert.equal(events.docs[0].data().petName, "Mochi");
  assert.equal(events.docs[0].data().taskTitle, "Evening meal");
  assert.ok(events.docs[0].data().recordedAt instanceof Timestamp);
});

test("Firestore onWrite trigger appends an accepted task marker", async () => {
  const householdID = unique("trigger-home");
  const taskID = "morning-walk";
  const taskData = task({ revision: 1, action: "taskClaimed" });
  await db.collection("households").doc(householdID)
    .collection("tasks").doc(taskID).set({ ...taskData, id: taskID });

  const eventID = collaborationEventID({
    sourceID: taskID,
    sourceRevision: 1,
    action: "taskClaimed",
  });
  const event = await waitForDocument(
    db.collection("households").doc(householdID)
      .collection("collaborationEvents").doc(eventID),
  );

  assert.equal(event.data().sourceID, taskID);
  assert.equal(event.data().action, "taskClaimed");
  assert.equal(event.data().actorID, "user-b");
});

test("same source revision and transition cannot overwrite stored history", async () => {
  const householdID = unique("conflict-home");
  const taskID = "evening-meal";
  const accepted = task({ revision: 2, action: "taskAccepted" });
  await appendTaskCollaborationEventAt(db, { householdID, taskID, taskData: accepted });

  await assert.rejects(
    appendTaskCollaborationEventAt(db, {
      householdID,
      taskID,
      taskData: { ...accepted, lastCollaborationActorName: "Forged" },
    }),
    /conflicts with stored history/,
  );
  const events = await db.collection("households").doc(householdID)
    .collection("collaborationEvents").get();
  assert.equal(events.size, 1);
  assert.equal(events.docs[0].data().actorName, "Alex");
});

test("legacy or unchanged markers do not fabricate actor or time", async () => {
  const householdID = unique("legacy-home");
  const legacy = task({ revision: 1, action: null });
  delete legacy.lastCollaborationAction;
  delete legacy.lastCollaborationActorID;
  delete legacy.lastCollaborationActorName;
  delete legacy.lastCollaborationTargetID;
  delete legacy.lastCollaborationTargetName;
  delete legacy.lastCollaborationRequestID;
  delete legacy.lastCollaborationAt;
  assert.deepEqual(
    await appendTaskCollaborationEventAt(db, {
      householdID,
      taskID: "legacy-task",
      taskData: legacy,
    }),
    { created: false, skippedLegacy: true },
  );

  const prior = task({ revision: 1, action: "taskRequested" });
  const after = { ...prior, revision: 2 };
  assert.deepEqual(
    await appendTaskCollaborationEventAt(db, {
      householdID,
      taskID: "retained-writer-task",
      previousTaskData: prior,
      taskData: after,
    }),
    { created: false, skippedLegacy: true },
  );
  assert.equal(
    (await db.collection("households").doc(householdID)
      .collection("collaborationEvents").get()).size,
    0,
  );
});

test("different revisions remain distinct and malformed facts write zero", async () => {
  const householdID = unique("revision-home");
  const taskID = "evening-meal";
  await appendTaskCollaborationEventAt(db, {
    householdID,
    taskID,
    taskData: task({ revision: 1, action: "taskRequested", state: "unclaimed" }),
  });
  await appendTaskCollaborationEventAt(db, {
    householdID,
    taskID,
    taskData: task({ revision: 2, action: "taskAccepted" }),
  });
  await assert.rejects(
    appendTaskCollaborationEventAt(db, {
      householdID,
      taskID,
      taskData: task({ revision: 3, action: "taskCompleted", state: "claimed" }),
    }),
    /marker is malformed/,
  );
  assert.equal(
    (await db.collection("households").doc(householdID)
      .collection("collaborationEvents").get()).size,
    2,
  );
});

test("medication task events do not copy medicine or dose text", async () => {
  const householdID = unique("private-title-home");
  const taskData = {
    ...task({ revision: 1, action: "taskClaimed" }),
    category: "medication",
    title: "Sensitive medicine 5 mg",
  };
  const result = await appendTaskCollaborationEventAt(db, {
    householdID,
    taskID: "medicine-task",
    taskData,
  });
  const stored = await db.collection("households").doc(householdID)
    .collection("collaborationEvents").doc(result.eventID).get();

  assert.equal(stored.data().taskTitle, "Medication care");
  assert.equal(JSON.stringify(stored.data()).includes("Sensitive medicine"), false);
  assert.equal(JSON.stringify(stored.data()).includes("5 mg"), false);
});

function task({ revision, action, state = "claimed" }) {
  const at = Timestamp.fromDate(new Date("2026-08-17T01:00:00.000Z"));
  return {
    id: "evening-meal",
    title: "Evening meal",
    category: "feeding",
    dueTime: at,
    priority: "normal",
    status: state,
    assignmentMode: action === "taskRequested" ? "direct" : null,
    petID: "pet-1",
    petName: "Mochi",
    revision,
    lastCollaborationAction: action,
    lastCollaborationActorID: "user-b",
    lastCollaborationActorName: "Alex",
    lastCollaborationTargetID: "user-a",
    lastCollaborationTargetName: "Mingze",
    lastCollaborationRequestID: "request-1",
    lastCollaborationAt: at,
  };
}

function unique(prefix) {
  sequence += 1;
  return `${prefix}-${Date.now()}-${sequence}`;
}

async function waitForDocument(reference) {
  const deadline = Date.now() + 5000;
  while (Date.now() < deadline) {
    const snapshot = await reference.get();
    if (snapshot.exists) return snapshot;
    await new Promise((resolve) => setTimeout(resolve, 50));
  }
  throw new Error(`Timed out waiting for ${reference.path}`);
}
