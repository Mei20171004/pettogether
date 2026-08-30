import fs from "node:fs";
import { after, before, beforeEach, test } from "node:test";
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from "@firebase/rules-unit-testing";
import {
  Timestamp,
  collection,
  deleteDoc,
  doc,
  documentId,
  getDoc,
  getDocs,
  limit,
  orderBy,
  query,
  serverTimestamp,
  setDoc,
  updateDoc,
  where,
  writeBatch,
} from "firebase/firestore";

const projectId = process.env.COPAW_TEST_PROJECT_ID ?? "demo-copaw";
const householdId = "household-1";
const caregiverA = "caregiver-a";
const caregiverB = "caregiver-b";
const caregiverC = "caregiver-c";
const firestorePort = Number(process.env.COPAW_FIRESTORE_TEST_PORT ?? "8080");
let testEnvironment;

before(async () => {
  testEnvironment = await initializeTestEnvironment({
    projectId,
    firestore: {
      rules: fs.readFileSync("firestore.rules", "utf8"),
      host: "127.0.0.1",
      port: firestorePort,
    },
  });
});

after(async () => {
  await testEnvironment.cleanup();
});

beforeEach(async () => {
  await testEnvironment.clearFirestore();
  await testEnvironment.withSecurityRulesDisabled(async (context) => {
    const database = context.firestore();
    await setDoc(doc(database, "households", householdId), {
      id: householdId,
      name: "Mochi Family",
      petName: "Mochi",
      inviteCode: "PAW123",
      timeZoneIdentifier: "Asia/Tokyo",
      ownerID: caregiverA,
      createdAt: Timestamp.now(),
    });
    await setDoc(doc(database, "households", householdId, "members", caregiverA), {
      id: caregiverA,
      displayName: "Mingze",
      inviteCode: "PAW123",
      joinedAt: Timestamp.now(),
    });
    await setDoc(doc(database, "households", householdId, "members", caregiverB), {
      id: caregiverB,
      displayName: "Alex",
      inviteCode: "PAW123",
      joinedAt: Timestamp.now(),
    });
    await setDoc(doc(database, "households", householdId, "members", caregiverC), {
      id: caregiverC,
      displayName: "Sam",
      inviteCode: "PAW123",
      joinedAt: Timestamp.now(),
    });
    await setDoc(
      doc(database, "households", householdId, "pets", "legacy-primary"),
      {
        id: "legacy-primary",
        name: "Mochi",
        species: null,
        isArchived: false,
        createdAt: Timestamp.now(),
        updatedAt: Timestamp.now(),
      },
    );
    await setDoc(doc(database, "inviteCodes", "PAW123"), {
      householdID: householdId,
      createdBy: caregiverA,
      createdAt: Timestamp.now(),
      active: true,
    });
  });
});

test("non-members cannot read household tasks", async () => {
  await seedTask("private-task");
  const outsider = testEnvironment.authenticatedContext("outsider").firestore();
  await assertFails(
    getDoc(doc(outsider, "households", householdId, "tasks", "private-task")),
  );
});

test("a member can update the shared household profile and their own name", async () => {
  const database = testEnvironment.authenticatedContext(caregiverA).firestore();

  await assertSucceeds(
    updateDoc(doc(database, "households", householdId), {
      name: "Mochi & Mugi Family",
      petName: "Mugi",
      updatedAt: serverTimestamp(),
    }),
  );
  await assertSucceeds(
    updateDoc(doc(database, "households", householdId, "members", caregiverA), {
      displayName: "Jing",
      updatedAt: serverTimestamp(),
    }),
  );
});

test("profile updates accept exact maximum lengths", async () => {
  const database = testEnvironment.authenticatedContext(caregiverA).firestore();

  await assertSucceeds(
    updateDoc(doc(database, "households", householdId), {
      name: "H".repeat(60),
      petName: "P".repeat(60),
      updatedAt: serverTimestamp(),
    }),
  );
  await assertSucceeds(
    updateDoc(doc(database, "households", householdId, "members", caregiverA), {
      displayName: "C".repeat(50),
      updatedAt: serverTimestamp(),
    }),
  );
});

test("household profile rejects empty and over-limit values", async () => {
  const database = testEnvironment.authenticatedContext(caregiverA).firestore();
  const reference = doc(database, "households", householdId);

  await assertFails(
    updateDoc(reference, { name: "", updatedAt: serverTimestamp() }),
  );
  await assertFails(
    updateDoc(reference, { name: "H".repeat(61), updatedAt: serverTimestamp() }),
  );
  await assertFails(
    updateDoc(reference, { petName: "", updatedAt: serverTimestamp() }),
  );
  await assertFails(
    updateDoc(reference, { petName: "P".repeat(61), updatedAt: serverTimestamp() }),
  );
});

test("member profile rejects empty and over-limit display names", async () => {
  const database = testEnvironment.authenticatedContext(caregiverA).firestore();
  const reference = doc(database, "households", householdId, "members", caregiverA);

  await assertFails(
    updateDoc(reference, { displayName: "", updatedAt: serverTimestamp() }),
  );
  await assertFails(
    updateDoc(reference, {
      displayName: "C".repeat(51),
      updatedAt: serverTimestamp(),
    }),
  );
});

test("an existing member can inspect and refresh their own membership", async () => {
  const database = testEnvironment.authenticatedContext(caregiverB).firestore();
  const reference = doc(database, "households", householdId, "members", caregiverB);

  await assertSucceeds(getDoc(reference));
  await assertSucceeds(
    updateDoc(reference, {
      displayName: "Alex Rejoined",
      updatedAt: serverTimestamp(),
    }),
  );
});

test("a new caregiver can inspect their own empty membership and join", async () => {
  const newcomer = "new-caregiver";
  const database = testEnvironment.authenticatedContext(newcomer).firestore();
  const reference = doc(database, "households", householdId, "members", newcomer);

  const membership = await assertSucceeds(getDoc(reference));
  if (membership.exists()) {
    throw new Error("Expected the new caregiver membership to be empty");
  }
  await assertSucceeds(
    setDoc(reference, {
      id: newcomer,
      displayName: "New caregiver",
      inviteCode: "PAW123",
      joinedAt: serverTimestamp(),
    }),
  );
  await assertSucceeds(
    setDoc(doc(database, "households", householdId, "pets", "luna"), {
      id: "luna",
      name: "Luna",
      species: "rabbit",
      isArchived: false,
      createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    }),
  );
  await assertSucceeds(getDoc(doc(database, "households", householdId)));
});

test("a legacy invite without active remains joinable, but false is rejected", async () => {
  const legacyCode = "I0O1A2";
  await testEnvironment.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), "inviteCodes", legacyCode), {
      householdID: householdId,
      createdBy: caregiverA,
      createdAt: Timestamp.now(),
    });
    await updateDoc(doc(context.firestore(), "households", householdId), {
      inviteCode: legacyCode,
    });
  });
  const legacyUser = "legacy-caregiver";
  const database = testEnvironment.authenticatedContext(legacyUser).firestore();
  await assertSucceeds(
    setDoc(doc(database, "households", householdId, "members", legacyUser), {
      id: legacyUser,
      displayName: "Legacy caregiver",
      inviteCode: legacyCode,
      joinedAt: serverTimestamp(),
    }),
  );

  await testEnvironment.withSecurityRulesDisabled(async (context) => {
    await updateDoc(doc(context.firestore(), "inviteCodes", legacyCode), {
      active: false,
    });
  });
  const blockedUser = "blocked-caregiver";
  const blockedDatabase = testEnvironment
    .authenticatedContext(blockedUser)
    .firestore();
  await assertFails(
    setDoc(
      doc(blockedDatabase, "households", householdId, "members", blockedUser),
      {
        id: blockedUser,
        displayName: "Blocked caregiver",
        inviteCode: legacyCode,
        joinedAt: serverTimestamp(),
      },
    ),
  );
});

test("household creation requires the mutually bound household, owner, and invite", async () => {
  const creator = "new-owner";
  const newHousehold = "new-household";
  const code = "NEW234";
  const database = testEnvironment.authenticatedContext(creator).firestore();
  const batch = writeBatch(database);
  batch.set(doc(database, "households", newHousehold), {
    id: newHousehold,
    name: "New family",
    petName: "New pet",
    inviteCode: code,
    timeZoneIdentifier: "Asia/Tokyo",
    ownerID: creator,
    createdAt: serverTimestamp(),
  });
  batch.set(doc(database, "households", newHousehold, "members", creator), {
    id: creator,
    displayName: "New owner",
    inviteCode: code,
    joinedAt: serverTimestamp(),
  });
  batch.set(doc(database, "households", newHousehold, "pets", "legacy-primary"), {
    id: "legacy-primary",
    name: "New pet",
    species: null,
    isArchived: false,
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  });
  batch.set(doc(database, "inviteCodes", code), {
    householdID: newHousehold,
    createdBy: creator,
    createdAt: serverTimestamp(),
    active: true,
  });
  await assertSucceeds(batch.commit());

  const legacyCreator = "legacy-new-owner";
  const legacyHousehold = "legacy-new-household";
  const legacyCode = "QWE234";
  const legacyDatabase = testEnvironment
    .authenticatedContext(legacyCreator)
    .firestore();
  const legacyBatch = writeBatch(legacyDatabase);
  legacyBatch.set(doc(legacyDatabase, "households", legacyHousehold), {
    id: legacyHousehold,
    name: "Legacy family",
    petName: "Legacy pet",
    inviteCode: legacyCode,
    timeZoneIdentifier: "Asia/Tokyo",
    ownerID: legacyCreator,
    createdAt: serverTimestamp(),
  });
  legacyBatch.set(
    doc(legacyDatabase, "households", legacyHousehold, "members", legacyCreator),
    {
      id: legacyCreator,
      displayName: "Legacy owner",
      inviteCode: legacyCode,
      joinedAt: serverTimestamp(),
    },
  );
  legacyBatch.set(doc(legacyDatabase, "inviteCodes", legacyCode), {
    householdID: legacyHousehold,
    createdBy: legacyCreator,
    createdAt: serverTimestamp(),
    active: true,
  });
  await assertSucceeds(legacyBatch.commit());

  const invalidOwner = "invalid-owner";
  const invalidDatabase = testEnvironment
    .authenticatedContext(invalidOwner)
    .firestore();
  await assertFails(
    setDoc(doc(invalidDatabase, "households", "invalid-household"), {
      id: "invalid-household",
      name: "Unbound family",
      petName: "Pet",
      inviteCode: "BAD234",
      timeZoneIdentifier: "Asia/Tokyo",
      ownerID: invalidOwner,
      createdAt: serverTimestamp(),
    }),
  );
});

test("household creation accepts exact profile maximums", async () => {
  const creator = "boundary-owner";
  const database = testEnvironment.authenticatedContext(creator).firestore();

  await assertSucceeds(
    householdTripletBatch(database, {
      creator,
      householdID: "boundary-household",
      code: "MAX234",
      householdName: "H".repeat(60),
      petName: "P".repeat(60),
      displayName: "C".repeat(50),
    }).commit(),
  );
});

test("household creation accepts canonical UTC and GMT timezones", async () => {
  for (const [index, timeZoneIdentifier] of ["UTC", "GMT"].entries()) {
    const creator = `timezone-owner-${index}`;
    const database = testEnvironment.authenticatedContext(creator).firestore();
    await assertSucceeds(
      householdTripletBatch(database, {
        creator,
        householdID: `timezone-household-${index}`,
        code: `TZ234${index + 2}`,
        timeZoneIdentifier,
      }).commit(),
    );
  }
});

test("household creation rejects ambiguous or malformed invite codes", async () => {
  const codes = ["ZERO10", "INDIA2", "OSAKA2", "lower2", "SHORT"];

  for (const [index, code] of codes.entries()) {
    const creator = `invalid-code-owner-${index}`;
    const database = testEnvironment.authenticatedContext(creator).firestore();
    await assertFails(
      householdTripletBatch(database, {
        creator,
        householdID: `invalid-code-household-${index}`,
        code,
      }).commit(),
    );
  }
});

test("household creation rejects empty or non-canonical timezone identifiers", async () => {
  const timezones = ["", "Tokyo", "/Tokyo", "Asia/"];

  for (const [index, timeZoneIdentifier] of timezones.entries()) {
    const creator = `invalid-timezone-owner-${index}`;
    const database = testEnvironment.authenticatedContext(creator).firestore();
    await assertFails(
      householdTripletBatch(database, {
        creator,
        householdID: `invalid-timezone-household-${index}`,
        code: `TM234${index + 2}`,
        timeZoneIdentifier,
      }).commit(),
    );
  }
});

test("household creation rejects invalid profile boundaries", async () => {
  const cases = [
    { suffix: "empty-name", householdName: "" },
    { suffix: "long-name", householdName: "H".repeat(61) },
    { suffix: "empty-pet", petName: "" },
    { suffix: "long-pet", petName: "P".repeat(61) },
    { suffix: "empty-member", displayName: "" },
    { suffix: "long-member", displayName: "C".repeat(51) },
  ];

  for (const [index, values] of cases.entries()) {
    const creator = `invalid-boundary-owner-${index}`;
    const database = testEnvironment.authenticatedContext(creator).firestore();
    await assertFails(
      householdTripletBatch(database, {
        creator,
        householdID: `invalid-boundary-household-${index}`,
        code: `BDY23${index + 2}`,
        ...values,
      }).commit(),
    );
  }
});

test("household creation rejects mismatched member and invite bindings", async () => {
  const memberOwner = "wrong-member-binding-owner";
  const memberDatabase = testEnvironment
    .authenticatedContext(memberOwner)
    .firestore();
  await assertFails(
    householdTripletBatch(memberDatabase, {
      creator: memberOwner,
      householdID: "wrong-member-binding-household",
      code: "MEM234",
      memberCode: "BAD234",
    }).commit(),
  );

  const inviteOwner = "wrong-invite-binding-owner";
  const inviteDatabase = testEnvironment
    .authenticatedContext(inviteOwner)
    .firestore();
  await assertFails(
    householdTripletBatch(inviteDatabase, {
      creator: inviteOwner,
      householdID: "wrong-invite-binding-household",
      code: "INV234",
      inviteDocumentID: "BAD235",
    }).commit(),
  );
});

test("an invite cannot create a member under a missing household", async () => {
  const missingHousehold = "missing-household";
  const newcomer = "orphan-caregiver";
  await testEnvironment.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), "inviteCodes", "ORPHAN"), {
      householdID: missingHousehold,
      createdBy: caregiverA,
      createdAt: Timestamp.now(),
      active: true,
    });
  });

  const database = testEnvironment.authenticatedContext(newcomer).firestore();
  await assertFails(
    setDoc(
      doc(database, "households", missingHousehold, "members", newcomer),
      {
        id: newcomer,
        displayName: "Orphan caregiver",
        inviteCode: "ORPHAN",
        joinedAt: serverTimestamp(),
      },
    ),
  );
});

test("caregivers cannot inspect another household member unless they belong", async () => {
  const outsider = testEnvironment.authenticatedContext("outsider").firestore();
  await assertFails(
    getDoc(doc(outsider, "households", householdId, "members", caregiverA)),
  );
});

test("household members can still list caregivers", async () => {
  const database = testEnvironment.authenticatedContext(caregiverA).firestore();
  await assertSucceeds(
    getDocs(collection(database, "households", householdId, "members")),
  );
});

test("members cannot rename another caregiver", async () => {
  const database = testEnvironment.authenticatedContext(caregiverA).firestore();
  await assertFails(
    updateDoc(doc(database, "households", householdId, "members", caregiverB), {
      displayName: "Not Alex",
      updatedAt: serverTimestamp(),
    }),
  );
});

test("outsiders cannot edit household profile fields", async () => {
  const database = testEnvironment.authenticatedContext("outsider").firestore();
  await assertFails(
    updateDoc(doc(database, "households", householdId), {
      name: "Taken over",
      petName: "Unknown",
      updatedAt: serverTimestamp(),
    }),
  );
});

test("members cannot change protected household fields", async () => {
  const database = testEnvironment.authenticatedContext(caregiverA).firestore();
  await assertFails(
    updateDoc(doc(database, "households", householdId), {
      inviteCode: "HACKED",
      updatedAt: serverTimestamp(),
    }),
  );
});

test("a member can create an unclaimed one-time urgent task", async () => {
  const database = testEnvironment.authenticatedContext(caregiverA).firestore();
  await assertSucceeds(
    setDoc(
      doc(database, "households", householdId, "tasks", "urgent-task"),
      taskData({
        id: "urgent-task",
        priority: "urgent",
        createdAt: serverTimestamp(),
      }),
    ),
  );
});

test("current task writers can attach trusted collaboration markers", async () => {
  const database = testEnvironment.authenticatedContext(caregiverA).firestore();
  const databaseB = testEnvironment.authenticatedContext(caregiverB).firestore();
  const created = doc(
    database,
    "households",
    householdId,
    "tasks",
    "marked-task",
  );
  await assertSucceeds(
    setDoc(
      created,
      taskData({
        id: "marked-task",
        createdAt: serverTimestamp(),
        ...collaborationMarkerData({ action: "taskCreated" }),
      }),
    ),
  );
  await assertSucceeds(
    updateDoc(created, {
      ...assignmentRequestData({ revision: 1 }),
      ...collaborationMarkerData({
        action: "taskRequested",
        targetID: caregiverB,
        targetName: "Alex",
        requestID: "request-boundary",
      }),
    }),
  );
  const recipientTask = doc(
    databaseB,
    "households",
    householdId,
    "tasks",
    "marked-task",
  );
  await assertSucceeds(
    updateDoc(recipientTask, {
      status: "claimed",
      ...clearedAssignmentRequestData(),
      assigneeID: caregiverB,
      assigneeName: "Alex",
      claimedAt: serverTimestamp(),
      revision: 2,
      ...collaborationMarkerData({
        action: "taskAccepted",
        actorID: caregiverB,
        actorName: "Alex",
        targetID: caregiverA,
        targetName: "Mingze",
        requestID: "request-boundary",
      }),
    }),
  );
  await assertSucceeds(
    updateDoc(recipientTask, {
      status: "completed",
      completedByID: caregiverB,
      completedBy: "Alex",
      completedAt: serverTimestamp(),
      revision: 3,
      ...collaborationMarkerData({
        action: "taskCompleted",
        actorID: caregiverB,
        actorName: "Alex",
      }),
    }),
  );
});

test("marked self-claim decline and cancel retain legacy task transitions", async () => {
  await seedTask("marked-claim");
  await seedTask("marked-decline");
  await seedTask("marked-cancel");
  const databaseA = testEnvironment.authenticatedContext(caregiverA).firestore();
  const databaseB = testEnvironment.authenticatedContext(caregiverB).firestore();
  await assertSucceeds(
    updateDoc(
      doc(databaseA, "households", householdId, "tasks", "marked-claim"),
      {
        status: "claimed",
        ...clearedAssignmentRequestData(),
        assigneeID: caregiverA,
        assigneeName: "Mingze",
        claimedAt: serverTimestamp(),
        revision: 1,
        ...collaborationMarkerData({ action: "taskClaimed" }),
      },
    ),
  );
  for (const taskID of ["marked-decline", "marked-cancel"]) {
    await assertSucceeds(
      updateDoc(
        doc(databaseA, "households", householdId, "tasks", taskID),
        {
          ...assignmentRequestData({ revision: 1 }),
          ...collaborationMarkerData({
            action: "taskRequested",
            targetID: caregiverB,
            targetName: "Alex",
            requestID: "request-boundary",
          }),
        },
      ),
    );
  }
  await assertSucceeds(
    updateDoc(
      doc(databaseB, "households", householdId, "tasks", "marked-decline"),
      {
        ...clearedAssignmentRequestData({ revision: 2 }),
        ...collaborationMarkerData({
          action: "taskDeclined",
          actorID: caregiverB,
          actorName: "Alex",
          targetID: caregiverA,
          targetName: "Mingze",
          requestID: "request-boundary",
        }),
      },
    ),
  );
  await assertSucceeds(
    updateDoc(
      doc(databaseA, "households", householdId, "tasks", "marked-cancel"),
      {
        ...clearedAssignmentRequestData({ revision: 2 }),
        ...collaborationMarkerData({
          action: "taskCancelled",
          targetID: caregiverB,
          targetName: "Alex",
          requestID: "request-boundary",
        }),
      },
    ),
  );
});

test("collaboration markers reject forged actor snapshots", async () => {
  await seedTask("forged-marker");
  const database = testEnvironment.authenticatedContext(caregiverA).firestore();
  await assertFails(
    updateDoc(
      doc(database, "households", householdId, "tasks", "forged-marker"),
      {
        ...assignmentRequestData({ revision: 1 }),
        ...collaborationMarkerData({
          action: "taskRequested",
          actorID: caregiverB,
          actorName: "Alex",
          targetID: caregiverB,
          targetName: "Alex",
          requestID: "request-boundary",
        }),
      },
    ),
  );
});

test("immutable partial and terminal task shapes cannot bypass transition dispatch", async () => {
  await seedTask("immutable-transition");
  await seedTask("pet-transition");
  await testEnvironment.withSecurityRulesDisabled(async (context) => {
    const database = context.firestore();
    const partial = taskData({
      id: "partial-transition",
      assignmentRequestID: "partial-request",
      assignmentMode: "direct",
      requestedByID: caregiverA,
      requestedToID: caregiverB,
      requestedToName: "Alex",
      assignmentRequestedAt: Timestamp.now(),
      createdAt: Timestamp.now(),
      revision: 1,
    });
    delete partial.requestedByName;
    await setDoc(
      doc(
        database,
        "households",
        householdId,
        "tasks",
        "partial-transition",
      ),
      partial,
    );
    await setDoc(
      doc(
        database,
        "households",
        householdId,
        "tasks",
        "terminal-transition",
      ),
      taskData({
        id: "terminal-transition",
        status: "completed",
        completedByID: caregiverA,
        completedBy: "Mingze",
        completedAt: Timestamp.now(),
        revision: 2,
      }),
    );
  });
  const database = testEnvironment.authenticatedContext(caregiverA).firestore();

  await assertFails(
    updateDoc(
      doc(
        database,
        "households",
        householdId,
        "tasks",
        "immutable-transition",
      ),
      {
        title: "Forged title",
        ...assignmentRequestData({ revision: 1 }),
      },
    ),
  );
  await assertFails(
    updateDoc(
      doc(database, "households", householdId, "tasks", "pet-transition"),
      {
        status: "claimed",
        petID: "other-pet",
        petName: "Other pet",
        assigneeID: caregiverA,
        assigneeName: "Mingze",
        claimedAt: serverTimestamp(),
        revision: 1,
      },
    ),
  );
  await assertFails(
    updateDoc(
      doc(
        database,
        "households",
        householdId,
        "tasks",
        "partial-transition",
      ),
      clearedAssignmentRequestData({ revision: 2 }),
    ),
  );
  await assertFails(
    updateDoc(
      doc(
        database,
        "households",
        householdId,
        "tasks",
        "terminal-transition",
      ),
      { revision: 3 },
    ),
  );
});

test("collaboration events are member-readable and client immutable", async () => {
  const eventID = "a".repeat(64);
  await testEnvironment.withSecurityRulesDisabled(async (context) => {
    await setDoc(
      doc(
        context.firestore(),
        "households",
        householdId,
        "collaborationEvents",
        eventID,
      ),
      { action: "taskCreated" },
    );
  });
  const member = testEnvironment.authenticatedContext(caregiverA).firestore();
  const outsider = testEnvironment.authenticatedContext("outsider").firestore();
  const memberEvent = doc(
    member,
    "households",
    householdId,
    "collaborationEvents",
    eventID,
  );

  await assertSucceeds(getDoc(memberEvent));
  await assertSucceeds(
    getDocs(collection(member, "households", householdId, "collaborationEvents")),
  );
  await assertFails(
    getDoc(
      doc(
        outsider,
        "households",
        householdId,
        "collaborationEvents",
        eventID,
      ),
    ),
  );
  await assertFails(setDoc(memberEvent, { action: "taskAccepted" }));
  await assertFails(updateDoc(memberEvent, { action: "taskAccepted" }));
  await assertFails(deleteDoc(memberEvent));
});

test("collaboration read cursors are private valid and monotonic per member", async () => {
  const firstEventID = "a".repeat(64);
  const secondEventID = "b".repeat(64);
  const occurredAt = Timestamp.fromDate(new Date("2026-08-17T01:00:00.000Z"));
  await testEnvironment.withSecurityRulesDisabled(async (context) => {
    const database = context.firestore();
    for (const eventID of [firstEventID, secondEventID]) {
      await setDoc(
        doc(
          database,
          "households",
          householdId,
          "collaborationEvents",
          eventID,
        ),
        { occurredAt },
      );
    }
  });
  const databaseA = testEnvironment.authenticatedContext(caregiverA).firestore();
  const databaseB = testEnvironment.authenticatedContext(caregiverB).firestore();
  const cursorA = doc(
    databaseA,
    "households",
    householdId,
    "members",
    caregiverA,
    "updateState",
    "collaboration",
  );
  const cursorB = doc(
    databaseB,
    "households",
    householdId,
    "members",
    caregiverB,
    "updateState",
    "collaboration",
  );

  await assertSucceeds(
    setDoc(cursorA, collaborationReadCursorData(firstEventID, occurredAt)),
  );
  await assertSucceeds(
    setDoc(cursorB, collaborationReadCursorData(secondEventID, occurredAt)),
  );
  await assertSucceeds(getDoc(cursorA));
  await assertSucceeds(getDoc(cursorB));
  await assertFails(
    getDoc(
      doc(
        databaseA,
        "households",
        householdId,
        "members",
        caregiverB,
        "updateState",
        "collaboration",
      ),
    ),
  );
  await assertFails(
    getDocs(
      collection(
        databaseA,
        "households",
        householdId,
        "members",
        caregiverA,
        "updateState",
      ),
    ),
  );
  await assertFails(
    setDoc(
      doc(
        databaseA,
        "households",
        householdId,
        "members",
        caregiverB,
        "updateState",
        "collaboration",
      ),
      collaborationReadCursorData(firstEventID, occurredAt),
    ),
  );

  await assertSucceeds(
    setDoc(cursorA, collaborationReadCursorData(secondEventID, occurredAt)),
  );
  await assertSucceeds(
    setDoc(cursorA, collaborationReadCursorData(secondEventID, occurredAt)),
  );
  await assertFails(
    setDoc(cursorA, collaborationReadCursorData(firstEventID, occurredAt)),
  );
  await assertFails(
    setDoc(
      cursorA,
      collaborationReadCursorData("c".repeat(64), occurredAt),
    ),
  );
  await assertFails(
    setDoc(
      cursorA,
      collaborationReadCursorData(
        secondEventID,
        Timestamp.fromMillis(occurredAt.toMillis() + 1),
      ),
    ),
  );
  await assertFails(
    setDoc(cursorA, {
      ...collaborationReadCursorData(secondEventID, occurredAt),
      injected: true,
    }),
  );
  await assertFails(deleteDoc(cursorA));
});

test("members can create and rename pets but archive state is server-only", async () => {
  const database = testEnvironment.authenticatedContext(caregiverA).firestore();
  const reference = doc(database, "households", householdId, "pets", "mugi");
  await assertSucceeds(
    setDoc(reference, {
      id: "mugi",
      name: "Mugi",
      species: "dog",
      isArchived: false,
      createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    }),
  );
  await assertSucceeds(
    updateDoc(reference, { name: "Mugi II", updatedAt: serverTimestamp() }),
  );
  await assertFails(
    updateDoc(reference, { isArchived: true, updatedAt: serverTimestamp() }),
  );
  await testEnvironment.withSecurityRulesDisabled(async (context) => {
    await updateDoc(
      doc(context.firestore(), "households", householdId, "pets", "mugi"),
      { isArchived: true, updatedAt: Timestamp.now() },
    );
  });
  await assertFails(
    updateDoc(reference, { isArchived: false, updatedAt: serverTimestamp() }),
  );
});

test("new care cannot target an archived or cross-household pet", async () => {
  const database = testEnvironment.authenticatedContext(caregiverA).firestore();
  await testEnvironment.withSecurityRulesDisabled(async (context) => {
    const seed = context.firestore();
    await setDoc(doc(seed, "households", householdId, "pets", "archived-pet"), {
      id: "archived-pet",
      name: "Old pet",
      species: "cat",
      isArchived: true,
      createdAt: Timestamp.now(),
      updatedAt: Timestamp.now(),
    });
    await setDoc(doc(seed, "households", "other-home", "pets", "other-pet"), {
      id: "other-pet",
      name: "Other pet",
      species: "dog",
      isArchived: false,
      createdAt: Timestamp.now(),
      updatedAt: Timestamp.now(),
    });
  });

  await assertFails(
    setDoc(
      doc(database, "households", householdId, "tasks", "archived-care"),
      taskData({
        id: "archived-care",
        petID: "archived-pet",
        petName: "Old pet",
        createdAt: serverTimestamp(),
      }),
    ),
  );
  await assertFails(
    setDoc(
      doc(database, "households", householdId, "tasks", "cross-home-care"),
      taskData({
        id: "cross-home-care",
        petID: "other-pet",
        petName: "Other pet",
        createdAt: serverTimestamp(),
      }),
    ),
  );
});

test("members can read canonical medication data but receipts stay server-only", async () => {
  await seedMedicationDocuments();
  const database = testEnvironment.authenticatedContext(caregiverA).firestore();
  const medication = doc(database, "households", householdId, "medications", "med-1");
  const version = doc(medication, "scheduleVersions", "v000001");
  const occurrence = doc(
    database,
    "households",
    householdId,
    "medicationOccurrences",
    "med-1_v000001_2026-08-13_0800",
  );
  const receipt = doc(
    database,
    "households",
    householdId,
    "medicationMutationReceipts",
    "receipt-1",
  );

  await assertSucceeds(getDoc(medication));
  await assertSucceeds(getDocs(collection(database, "households", householdId, "medications")));
  await assertSucceeds(getDoc(version));
  await assertSucceeds(getDocs(collection(medication, "scheduleVersions")));
  await assertSucceeds(getDoc(occurrence));
  await assertSucceeds(
    getDocs(collection(database, "households", householdId, "medicationOccurrences")),
  );
  await assertFails(getDoc(receipt));
  await assertFails(
    getDocs(collection(database, "households", householdId, "medicationMutationReceipts")),
  );
});

test("outsiders cannot get or list any medication data", async () => {
  await seedMedicationDocuments();
  const database = testEnvironment.authenticatedContext("outsider").firestore();
  const medication = doc(database, "households", householdId, "medications", "med-1");

  await assertFails(getDoc(medication));
  await assertFails(getDocs(collection(database, "households", householdId, "medications")));
  await assertFails(getDoc(doc(medication, "scheduleVersions", "v000001")));
  await assertFails(getDocs(collection(medication, "scheduleVersions")));
  await assertFails(getDoc(doc(
    database,
    "households",
    householdId,
    "medicationOccurrences",
    "med-1_v000001_2026-08-13_0800",
  )));
  await assertFails(
    getDocs(collection(database, "households", householdId, "medicationOccurrences")),
  );
});

test("clients cannot create update or delete medication authority documents", async () => {
  await seedMedicationDocuments();
  const database = testEnvironment.authenticatedContext(caregiverA).firestore();
  const paths = [
    ["medications", "med-1"],
    ["medications", "med-1", "scheduleVersions", "v000001"],
    ["medicationOccurrences", "med-1_v000001_2026-08-13_0800"],
    ["medicationMutationReceipts", "receipt-1"],
  ];
  for (const path of paths) {
    const existing = doc(database, "households", householdId, ...path);
    const created = doc(database, "households", householdId, ...path.slice(0, -1), "client-new");
    await assertFails(setDoc(created, { injected: true }));
    await assertFails(updateDoc(existing, { injected: true }));
    await assertFails(deleteDoc(existing));
  }
});

test("members own private notification tokens and cannot register for another household", async () => {
  const owner = testEnvironment.authenticatedContext(caregiverA).firestore();
  const otherMember = testEnvironment.authenticatedContext(caregiverB).firestore();
  const outsider = testEnvironment.authenticatedContext("outsider").firestore();
  const tokenPath = ["users", caregiverA, "notificationTokens", "a".repeat(64)];
  const token = {
    token: "private-device-token",
    householdID: householdId,
    platform: "ios",
    enabled: true,
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  };

  await assertSucceeds(setDoc(doc(owner, ...tokenPath), token));
  await assertSucceeds(getDoc(doc(owner, ...tokenPath)));
  await assertSucceeds(getDocs(collection(owner, "users", caregiverA, "notificationTokens")));
  await assertFails(getDoc(doc(otherMember, ...tokenPath)));
  await assertFails(getDocs(collection(otherMember, "users", caregiverA, "notificationTokens")));
  await assertFails(setDoc(doc(otherMember, ...tokenPath), token));
  await assertFails(setDoc(
    doc(outsider, "users", "outsider", "notificationTokens", "b".repeat(64)),
    { ...token, householdID: "missing-household" },
  ));
  await assertFails(updateDoc(doc(owner, ...tokenPath), { token: "", updatedAt: serverTimestamp() }));
  await assertSucceeds(updateDoc(doc(owner, ...tokenPath), {
    enabled: false,
    updatedAt: serverTimestamp(),
  }));
  await assertSucceeds(deleteDoc(doc(owner, ...tokenPath)));
});

test("new notification token IDs are canonical while legacy IDs remain update compatible", async () => {
  const now = Timestamp.now();
  await testEnvironment.withSecurityRulesDisabled(async (context) => {
    await setDoc(
      doc(context.firestore(), "users", caregiverA, "notificationTokens", "legacy-token-id"),
      {
        token: "legacy-private-device-token",
        householdID: householdId,
        platform: "ios",
        enabled: true,
        createdAt: now,
        updatedAt: now,
      },
    );
  });

  const owner = testEnvironment.authenticatedContext(caregiverA).firestore();
  const canonical = {
    token: "new-private-device-token",
    householdID: householdId,
    platform: "ios",
    enabled: true,
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  };

  await assertFails(setDoc(
    doc(owner, "users", caregiverA, "notificationTokens", "legacy-token-id-2"),
    canonical,
  ));
  await assertFails(setDoc(
    doc(owner, "users", caregiverA, "notificationTokens", "A".repeat(64)),
    canonical,
  ));
  await assertSucceeds(updateDoc(
    doc(owner, "users", caregiverA, "notificationTokens", "legacy-token-id"),
    { enabled: false, updatedAt: serverTimestamp() },
  ));
});

test("medication reminder delivery records are server-only", async () => {
  await testEnvironment.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(
      context.firestore(),
      "households", householdId,
      "medicationReminderDeliveries", "delivery-a",
    ), { status: "sent" });
  });
  const member = testEnvironment.authenticatedContext(caregiverA).firestore();
  const reference = doc(
    member,
    "households", householdId,
    "medicationReminderDeliveries", "delivery-a",
  );

  await assertFails(getDoc(reference));
  await assertFails(setDoc(reference, { status: "sent" }));
});

test("notification dispatch configuration is server-only", async () => {
  await testEnvironment.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(
      context.firestore(),
      "systemConfig", "notificationDispatch",
    ), {
      enabled: false,
      projectID: projectId,
      updatedBy: "local-test",
      updatedAt: Timestamp.now(),
    });
  });
  const member = testEnvironment.authenticatedContext(caregiverA).firestore();
  const reference = doc(member, "systemConfig", "notificationDispatch");

  await assertFails(getDoc(reference));
  await assertFails(updateDoc(reference, {
    enabled: true,
    updatedAt: serverTimestamp(),
  }));
});

test("LT6 notification gates are server-only", async () => {
  await testEnvironment.withSecurityRulesDisabled(async (context) => {
    const database = context.firestore();
    for (const configID of [
      "notificationIntentGenerationV2",
      "notificationDispatchV2",
    ]) {
      await setDoc(doc(database, "systemConfig", configID), {
        schemaVersion: 1,
        enabled: false,
        projectID: projectId,
        cutoverAt: Timestamp.now(),
        updatedBy: "local-test",
        updatedAt: Timestamp.now(),
      });
    }
  });

  const member = testEnvironment.authenticatedContext(caregiverA).firestore();
  for (const configID of [
    "notificationIntentGenerationV2",
    "notificationDispatchV2",
  ]) {
    const reference = doc(member, "systemConfig", configID);
    await assertFails(getDoc(reference));
    await assertFails(setDoc(reference, { enabled: true }));
  }
});

test("notification preferences are own current-epoch get-only documents", async () => {
  const { joinedAt } = await seedLT6NotificationDocuments();
  const owner = testEnvironment.authenticatedContext(caregiverA).firestore();
  const otherMember = testEnvironment.authenticatedContext(caregiverB).firestore();
  const reference = doc(
    owner,
    "users", caregiverA,
    "householdNotificationPreferences", householdId,
  );

  await assertSucceeds(getDoc(reference));
  await assertFails(getDocs(collection(
    owner,
    "users", caregiverA,
    "householdNotificationPreferences",
  )));
  await assertFails(getDoc(doc(
    otherMember,
    "users", caregiverA,
    "householdNotificationPreferences", householdId,
  )));
  await assertFails(updateDoc(reference, { pushEnabled: true }));
  await assertFails(deleteDoc(reference));

  await testEnvironment.withSecurityRulesDisabled(async (context) => {
    await updateDoc(
      doc(context.firestore(), "households", householdId, "members", caregiverA),
      { joinedAt: Timestamp.fromMillis(joinedAt.toMillis() + 1_000) },
    );
  });
  await assertFails(getDoc(reference));
  await testEnvironment.withSecurityRulesDisabled(async (context) => {
    const database = context.firestore();
    await updateDoc(
      doc(database, "households", householdId, "members", caregiverA),
      { joinedAt },
    );
    await deleteDoc(doc(
      database,
      "users", caregiverA,
      "householdNotificationPreferences", householdId,
    ));
  });
  await assertFails(setDoc(reference, notificationPreferenceData(joinedAt)));
});

test("LT6 receipts digests manifests and endpoint bindings are server-only", async () => {
  await seedLT6NotificationDocuments();
  const member = testEnvironment.authenticatedContext(caregiverA).firestore();
  const paths = [
    ["users", caregiverA, "notificationPreferenceMutationReceipts", "receipt-1"],
    ["users", caregiverA, "notificationDigests", "digest-1"],
    ["users", caregiverA, "notificationDeliveryManifests", "c".repeat(64)],
    ["households", householdId, "notificationEndpointBindings", "e".repeat(64)],
  ];

  for (const path of paths) {
    const reference = doc(member, ...path);
    await assertFails(getDoc(reference));
    await assertFails(getDocs(collection(member, ...path.slice(0, -1))));
    await assertFails(setDoc(reference, { forged: true }));
    await assertFails(updateDoc(reference, { forged: true }));
    await assertFails(deleteDoc(reference));
  }
});

test("notification inbox reads require owner current epoch and bounded exact query shape", async () => {
  const { joinedAt, intentID, staleIntentID, installationHash } =
    await seedLT6NotificationDocuments();
  const owner = testEnvironment.authenticatedContext(caregiverA).firestore();
  const otherMember = testEnvironment.authenticatedContext(caregiverB).firestore();
  const inbox = collection(owner, "users", caregiverA, "notificationInbox");
  const exactQuery = query(
    inbox,
    where("householdID", "==", householdId),
    where("recipientJoinedAtSnapshot", "==", joinedAt),
    orderBy("createdAt", "desc"),
    orderBy(documentId(), "desc"),
    limit(21),
  );

  await assertSucceeds(getDoc(doc(inbox, intentID)));
  await assertFails(getDoc(doc(inbox, staleIntentID)));
  await assertSucceeds(getDocs(exactQuery));
  // List authority is the private path plus a bounded query. A member may list
  // their own notifications without the exact filter shape; per-document epoch
  // authority still applies to every get, and leaving a household deletes that
  // membership's records.
  await assertSucceeds(getDocs(query(inbox, limit(21))));
  await assertFails(getDocs(query(
    collection(
      testEnvironment.authenticatedContext(caregiverB).firestore(),
      "users", caregiverA, "notificationInbox",
    ),
    limit(21),
  )));
  await assertFails(getDocs(query(
    inbox,
    where("householdID", "==", householdId),
    where("recipientJoinedAtSnapshot", "==", joinedAt),
    orderBy("createdAt", "desc"),
    orderBy(documentId(), "desc"),
    limit(22),
  )));
  await assertFails(getDoc(doc(
    otherMember,
    "users", caregiverA,
    "notificationInbox", intentID,
  )));
  await assertFails(setDoc(doc(inbox, "c".repeat(64)), { forged: true }));
  await assertFails(updateDoc(doc(inbox, intentID), { installationHash }));
});

test("notification inbox cursor is exact monotonic and references an active unexpired item", async () => {
  const {
    joinedAt,
    intentID,
    olderIntentID,
    expiredIntentID,
    createdAt,
    olderCreatedAt,
    expiredCreatedAt,
  } =
    await seedLT6NotificationDocuments();
  const owner = testEnvironment.authenticatedContext(caregiverA).firestore();
  const otherMember = testEnvironment.authenticatedContext(caregiverB).firestore();
  const reference = doc(
    owner,
    "users", caregiverA,
    "notificationInboxState", householdId,
  );

  await assertSucceeds(setDoc(reference, notificationCursorData({
    joinedAt,
    intentID,
    createdAt,
  })));
  await assertSucceeds(setDoc(reference, notificationCursorData({
    joinedAt,
    intentID,
    createdAt,
  })));
  await assertFails(setDoc(reference, notificationCursorData({
    joinedAt,
    intentID: olderIntentID,
    createdAt: olderCreatedAt,
  })));
  await assertFails(setDoc(reference, notificationCursorData({
    joinedAt,
    intentID,
    createdAt: olderCreatedAt,
  })));
  await assertFails(setDoc(reference, notificationCursorData({
    joinedAt,
    intentID: expiredIntentID,
    createdAt: expiredCreatedAt,
  })));
  await assertFails(setDoc(reference, {
    ...notificationCursorData({ joinedAt, intentID, createdAt }),
    extra: true,
  }));
  await assertFails(getDocs(collection(
    owner,
    "users", caregiverA,
    "notificationInboxState",
  )));
  await assertFails(getDoc(doc(
    otherMember,
    "users", caregiverA,
    "notificationInboxState", householdId,
  )));
  await assertFails(deleteDoc(reference));
});

test("notification delivery reads require owner current epoch installation and bounded query", async () => {
  const {
    joinedAt,
    deliveryID,
    staleDeliveryID,
    unboundDeliveryID,
    installationHash,
  } = await seedLT6NotificationDocuments();
  const owner = testEnvironment.authenticatedContext(caregiverA).firestore();
  const otherMember = testEnvironment.authenticatedContext(caregiverB).firestore();
  const deliveries = collection(owner, "users", caregiverA, "notificationDeliveries");
  const exactQuery = query(
    deliveries,
    where("householdID", "==", householdId),
    where("recipientJoinedAtSnapshot", "==", joinedAt),
    where("installationHash", "==", installationHash),
    orderBy("updatedAt", "desc"),
    orderBy(documentId(), "desc"),
    limit(21),
  );

  await assertSucceeds(getDoc(doc(deliveries, deliveryID)));
  await assertFails(getDoc(doc(deliveries, staleDeliveryID)));
  await assertSucceeds(getDoc(doc(deliveries, unboundDeliveryID)));
  await assertSucceeds(getDocs(exactQuery));
  await assertSucceeds(getDocs(query(deliveries, limit(21))));
  await assertFails(getDocs(query(
    collection(
      testEnvironment.authenticatedContext(caregiverB).firestore(),
      "users", caregiverA, "notificationDeliveries",
    ),
    limit(21),
  )));
  await assertFails(getDocs(query(
    deliveries,
    where("householdID", "==", householdId),
    where("recipientJoinedAtSnapshot", "==", joinedAt),
    where("installationHash", "==", installationHash),
    orderBy("updatedAt", "desc"),
    orderBy(documentId(), "desc"),
    limit(22),
  )));
  await assertFails(getDoc(doc(
    otherMember,
    "users", caregiverA,
    "notificationDeliveries", deliveryID,
  )));
  await assertFails(updateDoc(doc(deliveries, deliveryID), { status: "providerAccepted" }));
  await assertFails(deleteDoc(doc(deliveries, deliveryID)));
});

// Regression for the defect the LT7 two-process run found: a member who has
// never received a notification must be able to open an empty inbox instead of
// being denied by a rule that cannot be evaluated without a document.
test("empty notification list queries are allowed instead of erroring", async () => {
  const { joinedAt, installationHash } = await seedLT6NotificationDocuments();
  const owner = testEnvironment.authenticatedContext(caregiverA).firestore();
  const emptyHouseholdId = "household-with-no-notifications";
  await assertSucceeds(getDocs(query(
    collection(owner, "users", caregiverA, "notificationDeliveries"),
    where("householdID", "==", emptyHouseholdId),
    where("recipientJoinedAtSnapshot", "==", joinedAt),
    where("installationHash", "==", installationHash),
    orderBy("updatedAt", "desc"),
    orderBy(documentId(), "desc"),
    limit(21),
  )));
  await assertSucceeds(getDocs(query(
    collection(owner, "users", caregiverA, "notificationInbox"),
    where("householdID", "==", emptyHouseholdId),
    where("recipientJoinedAtSnapshot", "==", joinedAt),
    orderBy("createdAt", "desc"),
    orderBy(documentId(), "desc"),
    limit(21),
  )));
});

test("archiving a pet preserves mutations on its historical tasks", async () => {
  await seedTask("historical-care");
  await testEnvironment.withSecurityRulesDisabled(async (context) => {
    await updateDoc(
      doc(context.firestore(), "households", householdId, "pets", "legacy-primary"),
      { isArchived: true, updatedAt: Timestamp.now() },
    );
  });
  const database = testEnvironment.authenticatedContext(caregiverA).firestore();
  await assertSucceeds(
    updateDoc(
      doc(database, "households", householdId, "tasks", "historical-care"),
      {
        status: "claimed",
        assigneeID: caregiverA,
        assigneeName: "Mingze",
        claimedAt: serverTimestamp(),
        revision: 1,
      },
    ),
  );
});

test("legacy Swift care remains writable only while the primary pet is active", async () => {
  const database = testEnvironment.authenticatedContext(caregiverA).firestore();
  const activeTask = taskData({
    id: "legacy-active-task",
    createdAt: serverTimestamp(),
  });
  delete activeTask.petID;
  delete activeTask.petName;
  const activeRoutine = routineData({ id: "legacy-active-routine" });
  delete activeRoutine.petID;
  delete activeRoutine.petName;
  await assertSucceeds(
    setDoc(
      doc(database, "households", householdId, "tasks", "legacy-active-task"),
      activeTask,
    ),
  );
  await assertSucceeds(
    setDoc(
      doc(database, "households", householdId, "routines", "legacy-active-routine"),
      activeRoutine,
    ),
  );

  await testEnvironment.withSecurityRulesDisabled(async (context) => {
    await updateDoc(
      doc(context.firestore(), "households", householdId, "pets", "legacy-primary"),
      { isArchived: true, updatedAt: Timestamp.now() },
    );
  });
  const archivedTask = taskData({
    id: "legacy-archived-task",
    createdAt: serverTimestamp(),
  });
  delete archivedTask.petID;
  delete archivedTask.petName;
  const archivedRoutine = routineData({ id: "legacy-archived-routine" });
  delete archivedRoutine.petID;
  delete archivedRoutine.petName;
  await assertFails(
    setDoc(
      doc(database, "households", householdId, "tasks", "legacy-archived-task"),
      archivedTask,
    ),
  );
  await assertFails(
    setDoc(
      doc(database, "households", householdId, "routines", "legacy-archived-routine"),
      archivedRoutine,
    ),
  );
});

test("one-time task creation rejects oversized title and creator snapshots", async () => {
  const database = testEnvironment.authenticatedContext(caregiverA).firestore();
  await assertFails(
    setDoc(
      doc(database, "households", householdId, "tasks", "long-title-task"),
      taskData({ id: "long-title-task", title: "x".repeat(121) }),
    ),
  );
  await assertFails(
    setDoc(
      doc(database, "households", householdId, "tasks", "long-creator-task"),
      taskData({ id: "long-creator-task", createdBy: "x".repeat(51) }),
    ),
  );
});

test("assignment target must be a household member", async () => {
  await seedTask("bad-request");
  const database = testEnvironment.authenticatedContext(caregiverA).firestore();
  await assertFails(
    updateDoc(doc(database, "households", householdId, "tasks", "bad-request"), {
      assignmentRequestID: "request-1",
      requestedByID: caregiverA,
      requestedByName: "Mingze",
      assignmentMode: "direct",
      requestedToID: "outsider",
      requestedToName: "Outsider",
      assignmentRequestedAt: serverTimestamp(),
      revision: 1,
    }),
  );
});

test("assignment requests must use the trusted server time", async () => {
  await seedTask("forged-request-time");
  const database = testEnvironment.authenticatedContext(caregiverA).firestore();

  await assertFails(
    updateDoc(
      doc(database, "households", householdId, "tasks", "forged-request-time"),
      assignmentRequestData({
        assignmentRequestedAt: Timestamp.fromMillis(1),
        revision: 1,
      }),
    ),
  );
});

test("claims must use the trusted server time", async () => {
  await seedTask("forged-claim-time");
  const database = testEnvironment.authenticatedContext(caregiverA).firestore();

  await assertFails(
    updateDoc(doc(database, "households", householdId, "tasks", "forged-claim-time"), {
      status: "claimed",
      assigneeID: caregiverA,
      assigneeName: "Mingze",
      claimedAt: Timestamp.fromMillis(1),
      revision: 1,
    }),
  );
});

test("completion must use the trusted server time", async () => {
  await seedTask("forged-completion-time");
  const database = testEnvironment.authenticatedContext(caregiverA).firestore();
  const reference = doc(
    database,
    "households",
    householdId,
    "tasks",
    "forged-completion-time",
  );

  await assertSucceeds(
    updateDoc(reference, {
      status: "claimed",
      assigneeID: caregiverA,
      assigneeName: "Mingze",
      claimedAt: serverTimestamp(),
      revision: 1,
    }),
  );
  await assertFails(
    updateDoc(reference, {
      status: "completed",
      completedByID: caregiverA,
      completedBy: "Mingze",
      completedAt: Timestamp.fromMillis(1),
      revision: 2,
    }),
  );
});

test("recipient can accept and only the assignee can complete", async () => {
  await seedTask("handoff-task");
  const databaseA = testEnvironment.authenticatedContext(caregiverA).firestore();
  const databaseB = testEnvironment.authenticatedContext(caregiverB).firestore();
  const taskA = doc(databaseA, "households", householdId, "tasks", "handoff-task");
  const taskB = doc(databaseB, "households", householdId, "tasks", "handoff-task");

  await assertSucceeds(
    updateDoc(taskA, {
      assignmentRequestID: "request-2",
      requestedByID: caregiverA,
      requestedByName: "Mingze",
      assignmentMode: "direct",
      requestedToID: caregiverB,
      requestedToName: "Alex",
      assignmentRequestedAt: serverTimestamp(),
      revision: 1,
    }),
  );

  await assertSucceeds(
    updateDoc(taskB, {
      status: "claimed",
      assignmentRequestID: null,
      assignmentMode: null,
      requestedByID: null,
      requestedByName: null,
      requestedToID: null,
      requestedToName: null,
      assignmentRequestedAt: null,
      assigneeID: caregiverB,
      assigneeName: "Alex",
      claimedAt: serverTimestamp(),
      revision: 2,
    }),
  );

  await assertFails(
    updateDoc(taskA, {
      status: "completed",
      completedByID: caregiverA,
      completedBy: "Mingze",
      completedAt: serverTimestamp(),
      revision: 3,
    }),
  );

  await assertSucceeds(
    updateDoc(taskB, {
      status: "completed",
      completedByID: caregiverB,
      completedBy: "Alex",
      completedAt: serverTimestamp(),
      revision: 3,
    }),
  );
});

test("an open assignment can be claimed by any household member", async () => {
  await seedTask("open-task");
  const databaseA = testEnvironment.authenticatedContext(caregiverA).firestore();
  const databaseC = testEnvironment.authenticatedContext(caregiverC).firestore();
  const taskA = doc(databaseA, "households", householdId, "tasks", "open-task");
  const taskC = doc(databaseC, "households", householdId, "tasks", "open-task");

  await assertSucceeds(
    updateDoc(taskA, {
      assignmentRequestID: "open-request",
      assignmentMode: "open",
      requestedByID: caregiverA,
      requestedByName: "Mingze",
      requestedToID: null,
      requestedToName: null,
      assignmentRequestedAt: serverTimestamp(),
      revision: 1,
    }),
  );

  await assertSucceeds(
    updateDoc(taskC, {
      status: "claimed",
      assignmentRequestID: null,
      assignmentMode: null,
      requestedByID: null,
      requestedByName: null,
      requestedToID: null,
      requestedToName: null,
      assignmentRequestedAt: null,
      assigneeID: caregiverC,
      assigneeName: "Sam",
      claimedAt: serverTimestamp(),
      revision: 2,
    }),
  );
});

test("the requester can cancel but an unrelated member cannot clear the request", async () => {
  await seedTask("cancel-request");
  const databaseA = testEnvironment.authenticatedContext(caregiverA).firestore();
  const databaseC = testEnvironment.authenticatedContext(caregiverC).firestore();
  const taskA = doc(databaseA, "households", householdId, "tasks", "cancel-request");
  const taskC = doc(databaseC, "households", householdId, "tasks", "cancel-request");

  await assertSucceeds(updateDoc(taskA, assignmentRequestData({ revision: 1 })));
  await assertFails(updateDoc(taskC, clearedAssignmentRequestData({ revision: 2 })));
  await assertSucceeds(updateDoc(taskA, clearedAssignmentRequestData({ revision: 2 })));
});

test("the recipient can decline an assignment request", async () => {
  await seedTask("decline-request");
  const databaseA = testEnvironment.authenticatedContext(caregiverA).firestore();
  const databaseB = testEnvironment.authenticatedContext(caregiverB).firestore();
  const taskB = doc(databaseB, "households", householdId, "tasks", "decline-request");

  await assertSucceeds(
    updateDoc(
      doc(databaseA, "households", householdId, "tasks", "decline-request"),
      assignmentRequestData({ revision: 1 }),
    ),
  );
  await assertSucceeds(updateDoc(taskB, clearedAssignmentRequestData({ revision: 2 })));
});

test("profile renames do not invalidate historical assignment snapshots", async () => {
  await seedTask("rename-cancel");
  await seedTask("rename-decline");
  const databaseA = testEnvironment.authenticatedContext(caregiverA).firestore();
  const databaseB = testEnvironment.authenticatedContext(caregiverB).firestore();
  const cancelTask = doc(databaseA, "households", householdId, "tasks", "rename-cancel");
  const declineTaskA = doc(databaseA, "households", householdId, "tasks", "rename-decline");
  const declineTaskB = doc(databaseB, "households", householdId, "tasks", "rename-decline");

  await assertSucceeds(updateDoc(cancelTask, assignmentRequestData({ revision: 1 })));
  await assertSucceeds(updateDoc(declineTaskA, assignmentRequestData({ revision: 1 })));
  await assertSucceeds(
    updateDoc(doc(databaseA, "households", householdId, "members", caregiverA), {
      displayName: "Mingze Renamed",
      updatedAt: serverTimestamp(),
    }),
  );
  await assertSucceeds(
    updateDoc(doc(databaseB, "households", householdId, "members", caregiverB), {
      displayName: "Alex Renamed",
      updatedAt: serverTimestamp(),
    }),
  );

  await assertSucceeds(updateDoc(cancelTask, clearedAssignmentRequestData({ revision: 2 })));
  await assertSucceeds(updateDoc(declineTaskB, clearedAssignmentRequestData({ revision: 2 })));
});

test("stale revisions cannot overwrite a newer task state", async () => {
  await seedTask("stale-task");
  const database = testEnvironment.authenticatedContext(caregiverA).firestore();
  const reference = doc(database, "households", householdId, "tasks", "stale-task");

  await assertSucceeds(updateDoc(reference, assignmentRequestData({ revision: 1 })));
  await assertFails(updateDoc(reference, clearedAssignmentRequestData({ revision: 1 })));
});

test("a member can create a canonical care routine", async () => {
  const database = testEnvironment.authenticatedContext(caregiverA).firestore();
  await assertSucceeds(
    setDoc(
      doc(database, "households", householdId, "routines", "evening-walk"),
      routineData({ id: "evening-walk" }),
    ),
  );
});

test("routine creation rejects invalid title, weekdays, and timezone", async () => {
  const database = testEnvironment.authenticatedContext(caregiverA).firestore();
  const invalidRoutines = [
    { id: "empty-title", title: "" },
    { id: "long-title", title: "x".repeat(121) },
    { id: "duplicate-days", weekdays: [2, 2] },
    { id: "out-of-range-day", weekdays: [0, 2] },
    { id: "invalid-timezone", timeZoneIdentifier: "Tokyo" },
  ];

  for (const invalid of invalidRoutines) {
    await assertFails(
      setDoc(
        doc(database, "households", householdId, "routines", invalid.id),
        routineData(invalid),
      ),
    );
  }
});

test("clients cannot directly materialize a routine occurrence", async () => {
  await testEnvironment.withSecurityRulesDisabled(async (context) => {
    await setDoc(
      doc(context.firestore(), "households", householdId, "routines", "morning-meal"),
      {
        id: "morning-meal",
        title: "Morning meal",
        category: "feeding",
        priority: "normal",
        frequency: "daily",
        weekdays: [1, 2, 3, 4, 5, 6, 7],
        hour: 8,
        minute: 0,
        startDate: Timestamp.now(),
        timeZoneIdentifier: "Asia/Tokyo",
        createdByID: caregiverA,
        createdByName: "Mingze",
        isActive: true,
        createdAt: Timestamp.now(),
      },
    );
  });

  const database = testEnvironment.authenticatedContext(caregiverA).firestore();
  await assertFails(
    setDoc(
      doc(database, "households", householdId, "tasks", "morning-meal_2026-08-08"),
      taskData({
        id: "morning-meal_2026-08-08",
        title: "Morning meal",
        category: "feeding",
        kind: "routine",
        routineID: "morning-meal",
        status: "claimed",
        assigneeID: caregiverA,
        assigneeName: "Mingze",
        claimedAt: serverTimestamp(),
        createdAt: Timestamp.now(),
        revision: 1,
      }),
    ),
  );
});

test("health records are pet-scoped, immutable, and member-only", async () => {
  const member = testEnvironment.authenticatedContext(caregiverA).firestore();
  const outsider = testEnvironment.authenticatedContext("outsider").firestore();
  const reference = doc(member, "households", householdId, "healthRecords", "health-1");
  const record = healthRecordData();

  await testEnvironment.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(
      context.firestore(),
      "households",
      householdId,
      "healthRecords",
      "health-1",
    ), record);
  });
  await assertSucceeds(getDoc(reference));
  await assertFails(updateDoc(reference, { detail: "rewritten" }));
  await assertFails(deleteDoc(reference));
  await assertFails(getDoc(doc(
    outsider,
    "households",
    householdId,
    "healthRecords",
    "health-1",
  )));
  await assertFails(setDoc(
    doc(outsider, "households", householdId, "healthRecords", "health-2"),
    { ...record, createdByID: "outsider", createdByName: "Outsider" },
  ));
});

test("health records reject cross-pet snapshots and invalid structured values", async () => {
  const database = testEnvironment.authenticatedContext(caregiverA).firestore();
  const records = collection(database, "households", householdId, "healthRecords");

  await assertFails(setDoc(doc(records, "wrong-name"), healthRecordData({
    petName: "Another pet",
  })));
  await assertFails(setDoc(doc(records, "bad-weight"), healthRecordData({
    weightKilograms: -1,
  })));
  await assertFails(setDoc(doc(records, "spoofed-actor"), healthRecordData({
    createdByName: "Alex",
  })));
  await assertFails(setDoc(doc(records, "symptom"), healthRecordData({
    type: "symptom",
    detail: "Observed cough",
    weightKilograms: null,
  })));
  await assertFails(setDoc(doc(records, "water"), healthRecordData({
    type: "waterIntake",
    detail: "Daily total",
    weightKilograms: null,
    waterMilliliters: 420,
  })));
  await assertFails(setDoc(doc(records, "bad-water"), healthRecordData({
    type: "waterIntake",
    detail: null,
    weightKilograms: null,
    waterMilliliters: 10001,
  })));
});

test("legacy v1 health remains readable but all client health writes are closed", async () => {
  const database = testEnvironment.authenticatedContext(caregiverA).firestore();
  const records = collection(database, "households", householdId, "healthRecords");
  await assertFails(setDoc(doc(records, "legacy-weight-exact"), {
    schemaVersion: 1,
    petID: "legacy-primary",
    petName: "Mochi",
    type: "weight",
    recordedAt: Timestamp.now(),
    detail: null,
    weightKilograms: 4.2,
    createdByID: caregiverA,
    createdByName: "Mingze",
    createdAt: serverTimestamp(),
  }));
  await assertFails(setDoc(doc(records, "legacy-note-exact"), {
    schemaVersion: 1,
    petID: "legacy-primary",
    petName: "Mochi",
    type: "note",
    recordedAt: Timestamp.now(),
    detail: "Observed after dinner",
    weightKilograms: null,
    createdByID: caregiverA,
    createdByName: "Mingze",
    createdAt: serverTimestamp(),
  }));
});

test("canonical v2 health records cannot bypass the callable", async () => {
  const database = testEnvironment.authenticatedContext(caregiverA).firestore();
  const records = collection(database, "households", householdId, "healthRecords");
  await assertFails(setDoc(doc(records, "v2-water"), canonicalHealthRecordData()));
  await assertFails(setDoc(doc(records, "v2-wrong-zone"), canonicalHealthRecordData({
    recordedTimeZoneIdentifier: "America/Los_Angeles",
  })));
  await assertFails(setDoc(doc(records, "v2-no-date"), canonicalHealthRecordData({
    recordedLocalDate: null,
  })));
  await assertFails(setDoc(doc(records, "v2-wrong-basis"), canonicalHealthRecordData({
    waterMeasurementBasis: "localDayToDate",
  })));
  await assertFails(setDoc(doc(records, "v2-daily-client-write"), canonicalHealthRecordData({
    type: "dailyCheckIn",
    waterMeasurementBasis: "localDayToDate",
  })));
});

test("health record lists and archived history stay household scoped", async () => {
  await testEnvironment.withSecurityRulesDisabled(async (context) => {
    const database = context.firestore();
    await setDoc(doc(database, "households", householdId, "healthRecords", "historic"), {
      ...healthRecordData(),
      createdAt: Timestamp.now(),
    });
    await updateDoc(doc(database, "households", householdId, "pets", "legacy-primary"), {
      isArchived: true,
    });
  });
  const member = testEnvironment.authenticatedContext(caregiverA).firestore();
  const outsider = testEnvironment.authenticatedContext("outsider").firestore();

  await assertSucceeds(getDocs(collection(
    member,
    "households",
    householdId,
    "healthRecords",
  )));
  await assertFails(getDocs(collection(
    outsider,
    "households",
    householdId,
    "healthRecords",
  )));
  await assertSucceeds(getDoc(doc(
    member,
    "households",
    householdId,
    "healthRecords",
    "historic",
  )));
  await assertFails(setDoc(doc(
    member,
    "households",
    householdId,
    "healthRecords",
    "after-archive",
  ), healthRecordData()));
});

test("health record direct writes stay denied for every type and boundary", async () => {
  const database = testEnvironment.authenticatedContext(caregiverA).firestore();
  const records = collection(database, "households", householdId, "healthRecords");
  for (const type of [
    "appetite", "energy", "mood", "stoolObservation", "symptom", "visit", "vaccine", "note",
  ]) {
    await assertFails(setDoc(doc(records, `valid-${type}`), healthRecordData({
      type,
      detail: "x".repeat(500),
      weightKilograms: null,
    })));
  }
  await assertFails(setDoc(doc(records, "clock-skew"), healthRecordData({
    recordedAt: Timestamp.fromMillis(Date.now() + 1_000),
  })));
  await assertFails(setDoc(doc(records, "future"), healthRecordData({
    recordedAt: Timestamp.fromMillis(Date.now() + 60_000),
  })));
  await assertFails(setDoc(doc(records, "too-long"), healthRecordData({
    type: "note",
    detail: "x".repeat(501),
    weightKilograms: null,
  })));
  await assertFails(setDoc(doc(records, "unknown-field"), healthRecordData({
    diagnosis: "not allowed",
  })));
  await assertFails(setDoc(doc(records, "unknown-type"), healthRecordData({
    type: "diagnosis",
    detail: "not allowed",
    weightKilograms: null,
  })));
});

test("daily health check-in cannot bypass the canonical callable", async () => {
  const database = testEnvironment.authenticatedContext(caregiverA).firestore();
  const records = collection(database, "households", householdId, "healthRecords");
  const daily = healthRecordData({
    type: "dailyCheckIn",
    detail: "Quieter after the walk",
    weightKilograms: null,
    waterMilliliters: 510,
    waterLevel: "usual",
    appetiteLevel: "lessThanUsual",
    urinationLevel: "usual",
    stoolStatus: "changed",
    energyLevel: "lessThanUsual",
    moodStatus: "usual",
  });

  await assertFails(setDoc(doc(records, "daily-valid"), daily));
  await assertFails(setDoc(doc(records, "daily-missing-stool"), {
    ...daily,
    stoolStatus: null,
  }));
  await assertFails(setDoc(doc(records, "daily-medical-claim"), {
    ...daily,
    moodStatus: "healthy",
  }));
  await assertFails(setDoc(doc(records, "daily-bad-water"), {
    ...daily,
    waterMilliliters: 10001,
  }));
  await assertFails(setDoc(doc(records, "note-with-daily-fields"), {
    ...daily,
    type: "note",
  }));
});

test("health records cannot reference another household pet", async () => {
  await testEnvironment.withSecurityRulesDisabled(async (context) => {
    const database = context.firestore();
    await setDoc(doc(database, "households", "other-home"), {
      id: "other-home",
      petName: "Other",
    });
    await setDoc(doc(database, "households", "other-home", "pets", "other-pet"), {
      id: "other-pet",
      name: "Other",
      isArchived: false,
    });
  });
  const database = testEnvironment.authenticatedContext(caregiverA).firestore();
  await assertFails(setDoc(doc(
    database,
    "households",
    householdId,
    "healthRecords",
    "cross-household-pet",
  ), healthRecordData({ petID: "other-pet", petName: "Other" })));
});

test("household handoff is current, revisioned, and member-only", async () => {
  const memberA = testEnvironment.authenticatedContext(caregiverA).firestore();
  const memberB = testEnvironment.authenticatedContext(caregiverB).firestore();
  const outsider = testEnvironment.authenticatedContext("outsider").firestore();
  const currentA = doc(memberA, "households", householdId, "handoff", "current");
  const currentB = doc(memberB, "households", householdId, "handoff", "current");

  await assertSucceeds(setDoc(currentA, handoffData()));
  await assertSucceeds(getDoc(currentB));
  await assertSucceeds(setDoc(currentB, handoffData({
    careInstructions: "Dinner at 18:30",
    revision: 2,
    updatedByID: caregiverB,
    updatedByName: "Alex",
  })));
  await assertFails(getDoc(doc(
    outsider,
    "households",
    householdId,
    "handoff",
    "current",
  )));
  await assertFails(setDoc(doc(
    outsider,
    "households",
    householdId,
    "handoff",
    "current",
  ), handoffData({ updatedByID: "outsider", updatedByName: "Outsider" })));
  await assertFails(deleteDoc(currentA));
  await assertFails(setDoc(doc(
    memberA,
    "households",
    householdId,
    "handoff",
    "archive",
  ), handoffData()));
});

test("household handoff rejects stale revisions and untrusted fields", async () => {
  const database = testEnvironment.authenticatedContext(caregiverA).firestore();
  const current = doc(database, "households", householdId, "handoff", "current");
  await assertSucceeds(setDoc(current, handoffData()));

  await assertFails(setDoc(current, handoffData({ revision: 1 })));
  await assertFails(setDoc(current, handoffData({
    revision: 2,
    updatedByName: "Alex",
  })));
  await assertFails(setDoc(current, handoffData({
    revision: 2,
    careInstructions: "x".repeat(1001),
  })));
  await assertFails(setDoc(current, handoffData({
    revision: 2,
    privateDiagnosis: "not allowed",
  })));
});

function handoffData(overrides = {}) {
  return {
    schemaVersion: 1,
    careInstructions: "Dinner at 18:00",
    emergencyContactName: "Alex",
    emergencyContactPhone: "+81 00 0000 0000",
    veterinaryHospitalName: "Central Animal Hospital",
    veterinaryHospitalPhone: "+81 00 1111 1111",
    revision: 1,
    updatedByID: caregiverA,
    updatedByName: "Mingze",
    updatedAt: serverTimestamp(),
    ...overrides,
  };
}

function healthRecordData(overrides = {}) {
  return {
    schemaVersion: 1,
    petID: "legacy-primary",
    petName: "Mochi",
    type: "weight",
    recordedAt: Timestamp.now(),
    detail: null,
    weightKilograms: 4.2,
    waterMilliliters: null,
    createdByID: caregiverA,
    createdByName: "Mingze",
    createdAt: serverTimestamp(),
    ...overrides,
  };
}

function canonicalHealthRecordData(overrides = {}) {
  return {
    schemaVersion: 2,
    petID: "legacy-primary",
    petName: "Mochi",
    type: "waterIntake",
    recordedAt: Timestamp.now(),
    recordedLocalDate: "2026-08-17",
    recordedTimeZoneIdentifier: "Asia/Tokyo",
    detail: null,
    weightKilograms: null,
    waterMilliliters: 120,
    waterMeasurementBasis: "singleIntake",
    waterLevel: null,
    appetiteLevel: null,
    urinationLevel: null,
    stoolStatus: null,
    energyLevel: null,
    moodStatus: null,
    createdByID: caregiverA,
    createdByName: "Mingze",
    createdAt: serverTimestamp(),
    ...overrides,
  };
}

async function seedTask(id) {
  await testEnvironment.withSecurityRulesDisabled(async (context) => {
    await setDoc(
      doc(context.firestore(), "households", householdId, "tasks", id),
      taskData({ id, createdAt: Timestamp.now() }),
    );
  });
}

test("LT5 sidecars and handoff sessions are member-readable and server-written", async () => {
  const now = Timestamp.now();
  await testEnvironment.withSecurityRulesDisabled(async (context) => {
    const database = context.firestore();
    await setDoc(
      doc(database, "households", householdId, "taskResponsibilityTransfers", "transfer-1"),
      lt5TransferData(now),
    );
    await setDoc(
      doc(database, "households", householdId, "taskResponsibilityState", "task-1"),
      {
        schemaVersion: 1,
        taskID: "task-1",
        transferID: "transfer-1",
        taskRevisionAtProposal: 1,
        createdAt: now,
      },
    );
    await setDoc(
      doc(database, "households", householdId, "handoffVersions", "v000001"),
      lt5HandoffVersionData(now),
    );
    await setDoc(
      doc(database, "households", householdId, "handoffSessions", "session-1"),
      lt5HandoffSessionData(now),
    );
    await setDoc(
      doc(database, "households", householdId, "handoff", "sessionState"),
      {
        schemaVersion: 1,
        sessionID: "session-1",
        sessionStatus: "offered",
        plannedEndAt: Timestamp.fromMillis(now.toMillis() + 3600000),
        updatedAt: now,
      },
    );
  });

  const member = testEnvironment.authenticatedContext(caregiverA).firestore();
  const outsider = testEnvironment.authenticatedContext("outsider").firestore();
  const paths = [
    ["taskResponsibilityTransfers", "transfer-1"],
    ["taskResponsibilityState", "task-1"],
    ["handoffVersions", "v000001"],
    ["handoffSessions", "session-1"],
    ["handoff", "sessionState"],
  ];
  for (const [collectionID, documentID] of paths) {
    const memberRef = doc(member, "households", householdId, collectionID, documentID);
    const outsiderRef = doc(outsider, "households", householdId, collectionID, documentID);
    await assertSucceeds(getDoc(memberRef));
    await assertFails(getDoc(outsiderRef));
    await assertFails(updateDoc(memberRef, { revision: 99 }));
    await assertFails(deleteDoc(memberRef));
  }

  await assertFails(setDoc(
    doc(member, "households", householdId, "taskResponsibilityTransfers", "forged"),
    lt5TransferData(now),
  ));
  await assertFails(setDoc(
    doc(member, "households", householdId, "handoffSessions", "forged"),
    lt5HandoffSessionData(now),
  ));
});

test("LT5 receipts remain private and pending state blocks retained direct task writes", async () => {
  const now = Timestamp.now();
  await testEnvironment.withSecurityRulesDisabled(async (context) => {
    const database = context.firestore();
    await setDoc(
      doc(database, "households", householdId, "tasks", "task-1"),
      taskData({
        status: "claimed",
        assigneeID: caregiverB,
        assigneeName: "Alex",
        claimedAt: now,
        revision: 1,
      }),
    );
    await setDoc(
      doc(database, "households", householdId, "taskResponsibilityState", "task-1"),
      {
        schemaVersion: 1,
        taskID: "task-1",
        transferID: "transfer-1",
        taskRevisionAtProposal: 1,
        createdAt: now,
      },
    );
    for (const collectionID of [
      "taskResponsibilityReceipts",
      "handoffSessionReceipts",
      "membershipMutationReceipts",
    ]) {
      await setDoc(
        doc(database, "households", householdId, collectionID, "receipt-1"),
        { schemaVersion: 1, uid: caregiverB, fingerprint: "private", result: {} },
      );
    }
    const revocation = doc(
      database,
      "households",
      householdId,
      "membershipRevocations",
      caregiverB,
    );
    await setDoc(revocation, {
      schemaVersion: 1,
      uid: caregiverB,
      status: "draining",
      initiatingMutationID: "mutation-1",
      initiatingFingerprint: "a".repeat(64),
      receiptID: "b".repeat(64),
      tokenCursor: null,
      disabledInstallationCount: 0,
      result: null,
      createdAt: now,
      updatedAt: now,
    });
    await setDoc(doc(revocation, "notificationClaims", "delivery-1"), {
      schemaVersion: 1,
      deliveryID: "delivery-1",
      recipientID: caregiverB,
      tokenDocumentID: "token-1",
      leaseUntil: now,
      createdAt: now,
    });
  });

  const member = testEnvironment.authenticatedContext(caregiverB).firestore();
  await assertFails(updateDoc(
    doc(member, "households", householdId, "tasks", "task-1"),
    {
      status: "completed",
      completedByID: caregiverB,
      completedBy: "Alex",
      completedAt: serverTimestamp(),
      revision: 2,
    },
  ));
  for (const collectionID of [
    "taskResponsibilityReceipts",
    "handoffSessionReceipts",
    "membershipMutationReceipts",
  ]) {
    const reference = doc(member, "households", householdId, collectionID, "receipt-1");
    await assertFails(getDoc(reference));
    await assertFails(updateDoc(reference, { fingerprint: "forged" }));
  }
  const revocation = doc(
    member,
    "households",
    householdId,
    "membershipRevocations",
    caregiverB,
  );
  const claim = doc(revocation, "notificationClaims", "delivery-1");
  await assertFails(getDoc(revocation));
  await assertFails(updateDoc(revocation, { status: "complete" }));
  await assertFails(getDoc(claim));
  await assertFails(deleteDoc(claim));
  await assertFails(deleteDoc(
    doc(member, "households", householdId, "members", caregiverB),
  ));
});

test("LT5 draining revocation blocks rejoin until the server removes its pointer", async () => {
  const now = Timestamp.now();
  await testEnvironment.withSecurityRulesDisabled(async (context) => {
    const database = context.firestore();
    await deleteDoc(doc(database, "households", householdId, "members", caregiverB));
    await setDoc(
      doc(database, "households", householdId, "membershipRevocations", caregiverB),
      {
        schemaVersion: 1,
        uid: caregiverB,
        status: "revokingTokens",
        initiatingMutationID: "mutation-1",
        initiatingFingerprint: "a".repeat(64),
        receiptID: "b".repeat(64),
        tokenCursor: null,
        disabledInstallationCount: 0,
        result: null,
        createdAt: now,
        updatedAt: now,
      },
    );
  });
  const member = testEnvironment.authenticatedContext(caregiverB).firestore();
  const reference = doc(member, "households", householdId, "members", caregiverB);
  const payload = {
    id: caregiverB,
    displayName: "Alex",
    inviteCode: "PAW123",
    joinedAt: serverTimestamp(),
  };
  await assertFails(setDoc(reference, payload));
  await testEnvironment.withSecurityRulesDisabled(async (context) => {
    await deleteDoc(doc(
      context.firestore(),
      "households",
      householdId,
      "membershipRevocations",
      caregiverB,
    ));
  });
  await assertSucceeds(setDoc(reference, payload));
});

function lt5TransferData(now) {
  return {
    schemaVersion: 1,
    id: "transfer-1",
    taskID: "task-1",
    kind: "reassign",
    status: "pending",
    requestedByID: caregiverA,
    requestedByName: "Caregiver A",
    consentByID: caregiverB,
    consentByName: "Alex",
    responsibilityFromID: caregiverA,
    responsibilityFromName: "Caregiver A",
    responsibilityToID: caregiverB,
    responsibilityToName: "Alex",
    taskRevisionAtProposal: 1,
    createdAt: now,
    resolvedByID: null,
    resolvedByName: null,
    resolvedAt: null,
    resultingTaskRevision: null,
    revision: 1,
  };
}

function lt5HandoffVersionData(now) {
  return {
    schemaVersion: 1,
    id: "v000001",
    sourceHandoffRevision: 1,
    careInstructions: "Private care",
    emergencyContactName: "Emergency",
    emergencyContactPhone: "090-0000",
    veterinaryHospitalName: "Vet",
    veterinaryHospitalPhone: "03-0000",
    updatedByID: caregiverA,
    updatedByName: "Caregiver A",
    updatedAt: now,
    materializedAt: now,
  };
}

function lt5HandoffSessionData(now) {
  return {
    schemaVersion: 1,
    id: "session-1",
    versionID: "v000001",
    handoffRevisionSnapshot: 1,
    creatorID: caregiverA,
    creatorName: "Caregiver A",
    recipientID: caregiverB,
    recipientName: "Alex",
    timeZoneIdentifierSnapshot: "Asia/Tokyo",
    plannedStartAt: Timestamp.fromMillis(now.toMillis() + 60000),
    plannedEndAt: Timestamp.fromMillis(now.toMillis() + 3600000),
    status: "offered",
    offeredAt: now,
    acceptedByID: null,
    acceptedByName: null,
    acceptedAt: null,
    declinedByID: null,
    declinedByName: null,
    declinedAt: null,
    cancelledByID: null,
    cancelledByName: null,
    cancelledAt: null,
    closedByID: null,
    closedByName: null,
    closedAt: null,
    resolutionReason: null,
    revision: 1,
  };
}

async function seedLT6NotificationDocuments() {
  const now = Timestamp.now();
  const createdAt = Timestamp.fromMillis(now.toMillis() - 60_000);
  const olderCreatedAt = Timestamp.fromMillis(now.toMillis() - 120_000);
  const expiredCreatedAt = Timestamp.fromMillis(now.toMillis() - 30_000);
  const expiredAt = Timestamp.fromMillis(now.toMillis() - 10_000);
  const expiresAt = Timestamp.fromMillis(now.toMillis() + 3_600_000);
  const intentID = "c".repeat(64);
  const olderIntentID = "b".repeat(64);
  const staleIntentID = "f".repeat(64);
  const expiredIntentID = "8".repeat(64);
  const installationHash = "a".repeat(64);
  const deliveryID = "d".repeat(64);
  const staleDeliveryID = "6".repeat(64);
  const unboundDeliveryID = "7".repeat(64);
  const unboundInstallationHash = "9".repeat(64);
  let joinedAt;

  await testEnvironment.withSecurityRulesDisabled(async (context) => {
    const database = context.firestore();
    const memberSnapshot = await getDoc(doc(
      database,
      "households", householdId,
      "members", caregiverA,
    ));
    joinedAt = memberSnapshot.data().joinedAt;

    await setDoc(doc(
      database,
      "users", caregiverA,
      "householdNotificationPreferences", householdId,
    ), {
      schemaVersion: 1,
      uid: caregiverA,
      householdID: householdId,
      memberJoinedAtSnapshot: joinedAt,
      medicationRemindersEnabled: false,
      assignmentAlertsEnabled: false,
      urgentAlertsEnabled: false,
      pushEnabled: false,
      backupForMemberIDs: [],
      quietHoursEnabled: false,
      quietStartMinute: 1320,
      quietEndMinute: 420,
      summaryEnabled: false,
      summaryMinute: 1080,
      timeZoneIdentifierSnapshot: "Asia/Tokyo",
      revision: 1,
      createdAt: now,
      updatedAt: now,
    });
    await setDoc(doc(
      database,
      "users", caregiverA,
      "notificationPreferenceMutationReceipts", "receipt-1",
    ), { schemaVersion: 1, uid: caregiverA, householdID: householdId });
    await setDoc(doc(
      database,
      "users", caregiverA,
      "notificationDigests", "digest-1",
    ), { schemaVersion: 1, recipientID: caregiverA, householdID: householdId });
    await setDoc(doc(
      database,
      "users", caregiverA,
      "notificationDeliveryManifests", intentID,
    ), { schemaVersion: 1, recipientID: caregiverA, householdID: householdId });
    await setDoc(doc(
      database,
      "households", householdId,
      "notificationEndpointBindings", "e".repeat(64),
    ), { schemaVersion: 1, recipientID: caregiverA, householdID: householdId });
    await setDoc(doc(
      database,
      "users", caregiverA,
      "notificationTokens", installationHash,
    ), {
      token: "private-device-token",
      householdID: householdId,
      platform: "ios",
      enabled: true,
      createdAt: now,
      updatedAt: now,
    });

    const staleJoinedAt = Timestamp.fromMillis(joinedAt.toMillis() - 86_400_000);
    for (const [id, itemCreatedAt, itemJoinedAt, itemExpiresAt] of [
      [intentID, createdAt, joinedAt, expiresAt],
      [olderIntentID, olderCreatedAt, joinedAt, expiresAt],
      [staleIntentID, olderCreatedAt, staleJoinedAt, expiresAt],
      [expiredIntentID, expiredCreatedAt, joinedAt, expiredAt],
    ]) {
      await setDoc(doc(
        database,
        "users", caregiverA,
        "notificationInbox", id,
      ), {
        schemaVersion: 1,
        id,
        householdID: householdId,
        recipientID: caregiverA,
        recipientJoinedAtSnapshot: itemJoinedAt,
        category: "medication",
        level: "due",
        routeReason: "responsible",
        sourceType: "medicationOccurrence",
        sourceID: "occurrence-1",
        sourcePath: "medicationOccurrences/occurrence-1",
        sourceRevision: 0,
        preferenceRevision: null,
        status: "active",
        availableAt: itemCreatedAt,
        expiresAt: itemExpiresAt,
        nextDispatchAt: null,
        coalescingKey: null,
        cancelReason: null,
        cancelledAt: null,
        createdAt: itemCreatedAt,
        updatedAt: itemCreatedAt,
      });
    }
    for (const [id, deliveryJoinedAt, deliveryInstallationHash] of [
      [deliveryID, joinedAt, installationHash],
      [staleDeliveryID, staleJoinedAt, installationHash],
      [unboundDeliveryID, joinedAt, unboundInstallationHash],
    ]) {
      await setDoc(doc(
        database,
        "users", caregiverA,
        "notificationDeliveries", id,
      ), {
        schemaVersion: 2,
        id,
        intentID,
        householdID: householdId,
        recipientID: caregiverA,
        recipientJoinedAtSnapshot: deliveryJoinedAt,
        installationHash: deliveryInstallationHash,
        status: "queued",
        attemptCount: 0,
        nextAttemptAt: now,
        leaseID: null,
        leaseExpiresAt: null,
        providerRequestStartedAt: null,
        providerAcceptedAt: null,
        providerUnknownAt: null,
        terminalAt: null,
        safeErrorCode: null,
        createdAt,
        updatedAt: now,
      });
    }
  });

  return {
    joinedAt,
    intentID,
    olderIntentID,
    staleIntentID,
    expiredIntentID,
    installationHash,
    deliveryID,
    staleDeliveryID,
    unboundDeliveryID,
    createdAt,
    olderCreatedAt,
    expiredCreatedAt,
  };
}

function notificationPreferenceData(joinedAt) {
  return {
    schemaVersion: 1,
    uid: caregiverA,
    householdID: householdId,
    memberJoinedAtSnapshot: joinedAt,
    medicationRemindersEnabled: false,
    assignmentAlertsEnabled: false,
    urgentAlertsEnabled: false,
    pushEnabled: false,
    backupForMemberIDs: [],
    quietHoursEnabled: false,
    quietStartMinute: 1320,
    quietEndMinute: 420,
    summaryEnabled: false,
    summaryMinute: 1080,
    timeZoneIdentifierSnapshot: "Asia/Tokyo",
    revision: 1,
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  };
}

function notificationCursorData({ joinedAt, intentID, createdAt }) {
  return {
    schemaVersion: 1,
    householdID: householdId,
    recipientJoinedAtSnapshot: joinedAt,
    createdAt,
    intentID,
    updatedAt: serverTimestamp(),
  };
}

function householdTripletBatch(
  database,
  {
    creator,
    householdID,
    code,
    householdName = "New family",
    petName = "New pet",
    displayName = "New owner",
    timeZoneIdentifier = "Asia/Tokyo",
    memberCode = code,
    inviteDocumentID = code,
  },
) {
  const batch = writeBatch(database);
  batch.set(doc(database, "households", householdID), {
    id: householdID,
    name: householdName,
    petName,
    inviteCode: code,
    timeZoneIdentifier,
    ownerID: creator,
    createdAt: serverTimestamp(),
  });
  batch.set(doc(database, "households", householdID, "members", creator), {
    id: creator,
    displayName,
    inviteCode: memberCode,
    joinedAt: serverTimestamp(),
  });
  batch.set(doc(database, "households", householdID, "pets", "legacy-primary"), {
    id: "legacy-primary",
    name: petName,
    species: null,
    isArchived: false,
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  });
  batch.set(doc(database, "inviteCodes", inviteDocumentID), {
    householdID,
    createdBy: creator,
    createdAt: serverTimestamp(),
    active: true,
  });
  return batch;
}

function taskData(overrides = {}) {
  return {
    id: "task-1",
    title: "Call the vet",
    category: "medication",
    dueTime: Timestamp.now(),
    kind: "oneOff",
    priority: "normal",
    routineID: null,
    petID: "legacy-primary",
    petName: "Mochi",
    status: "unclaimed",
    assignmentRequestID: null,
    assignmentMode: null,
    requestedByID: null,
    requestedByName: null,
    requestedToID: null,
    requestedToName: null,
    assignmentRequestedAt: null,
    assigneeID: null,
    assigneeName: null,
    claimedAt: null,
    createdByID: caregiverA,
    createdBy: "Mingze",
    createdAt: Timestamp.now(),
    completedByID: null,
    completedBy: null,
    completedAt: null,
    revision: 0,
    ...overrides,
  };
}

async function seedMedicationDocuments() {
  await testEnvironment.withSecurityRulesDisabled(async (context) => {
    const database = context.firestore();
    const medication = doc(database, "households", householdId, "medications", "med-1");
    await setDoc(medication, {
      schemaVersion: 1,
      id: "med-1",
      petID: "legacy-primary",
      displayName: "Tablet A",
      isActive: true,
      currentScheduleVersion: 1,
      currentScheduleVersionID: "v000001",
      revision: 0,
      createdAt: Timestamp.now(),
      createdByID: caregiverA,
      createdByName: "Mingze",
      updatedAt: Timestamp.now(),
      updatedByID: caregiverA,
    });
    await setDoc(doc(medication, "scheduleVersions", "v000001"), {
      schemaVersion: 1,
      id: "v000001",
      medicationID: "med-1",
      version: 1,
      petID: "legacy-primary",
      petName: "Mochi",
      medicationName: "Tablet A",
      weekdays: [5],
      slots: [{ slotID: "0800", hour: 8, minute: 0, doseText: "1 tablet" }],
      timeZoneIdentifier: "Asia/Tokyo",
      dstPolicy: "reject",
      effectiveFromLocalDate: "2026-08-13",
      effectiveUntilLocalDate: null,
    });
    await setDoc(
      doc(
        database,
        "households",
        householdId,
        "medicationOccurrences",
        "med-1_v000001_2026-08-13_0800",
      ),
      {
        schemaVersion: 1,
        id: "med-1_v000001_2026-08-13_0800",
        medicationID: "med-1",
        scheduleVersionID: "v000001",
        outcomeStatus: "administered",
      },
    );
    await setDoc(
      doc(
        database,
        "households",
        householdId,
        "medicationMutationReceipts",
        "receipt-1",
      ),
      { uid: caregiverA, fingerprint: "private", result: {} },
    );
  });
}

function routineData(overrides = {}) {
  return {
    id: "routine-1",
    title: "Evening walk",
    category: "walking",
    priority: "normal",
    frequency: "selectedDays",
    weekdays: [2, 4, 6],
    hour: 18,
    minute: 30,
    startDate: Timestamp.now(),
    timeZoneIdentifier: "Asia/Tokyo",
    createdByID: caregiverA,
    createdByName: "Mingze",
    petID: "legacy-primary",
    petName: "Mochi",
    isActive: true,
    createdAt: serverTimestamp(),
    ...overrides,
  };
}

function assignmentRequestData(overrides = {}) {
  return {
    assignmentRequestID: "request-boundary",
    assignmentMode: "direct",
    requestedByID: caregiverA,
    requestedByName: "Mingze",
    requestedToID: caregiverB,
    requestedToName: "Alex",
    assignmentRequestedAt: serverTimestamp(),
    ...overrides,
  };
}

function clearedAssignmentRequestData(overrides = {}) {
  return {
    assignmentRequestID: null,
    assignmentMode: null,
    requestedByID: null,
    requestedByName: null,
    requestedToID: null,
    requestedToName: null,
    assignmentRequestedAt: null,
    ...overrides,
  };
}

function collaborationMarkerData({
  action,
  actorID = caregiverA,
  actorName = "Mingze",
  targetID = null,
  targetName = null,
  requestID = null,
}) {
  return {
    lastCollaborationAction: action,
    lastCollaborationActorID: actorID,
    lastCollaborationActorName: actorName,
    lastCollaborationTargetID: targetID,
    lastCollaborationTargetName: targetName,
    lastCollaborationRequestID: requestID,
    lastCollaborationAt: serverTimestamp(),
  };
}

function collaborationReadCursorData(eventID, occurredAt) {
  return {
    schemaVersion: 1,
    occurredAt,
    eventID,
    updatedAt: serverTimestamp(),
  };
}
