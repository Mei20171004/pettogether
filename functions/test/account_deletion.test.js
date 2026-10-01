const assert = require("node:assert/strict");
const test = require("node:test");

const {
  AccountDeletionError,
  anonymizationUpdate,
  resolveNewOwner,
} = require("../account_deletion");

test("a sole owner can delete without transferring ownership", () => {
  assert.equal(
    resolveNewOwner("owner", [{ id: "owner", displayName: "Owner" }], null),
    null,
  );
});

test("an owner with other members must choose a valid successor", () => {
  const members = [
    { id: "owner", displayName: "Owner" },
    { id: "caregiver", displayName: "Caregiver" },
  ];
  assert.throws(
    () => resolveNewOwner("owner", members, null),
    (error) => error instanceof AccountDeletionError &&
      error.code === "owner-transfer-required" &&
      error.details.candidates[0].id === "caregiver",
  );
  assert.equal(
    resolveNewOwner("owner", members, "caregiver").id,
    "caregiver",
  );
});

test("shared care history keeps the event but removes deleted identity", () => {
  assert.deepEqual(
    anonymizationUpdate({
      createdByID: "deleted-user",
      createdBy: "Private Name",
      completedByID: "deleted-user",
      completedBy: "Private Name",
    }, "deleted-user"),
    {
      createdByID: "",
      createdBy: "Deleted user",
      completedByID: null,
      completedBy: "Deleted user",
    },
  );
});

test("claimed work returns to unclaimed when its assignee deletes account", () => {
  assert.deepEqual(
    anonymizationUpdate({
      status: "claimed",
      assigneeID: "deleted-user",
      assigneeName: "Private Name",
      claimedAt: "timestamp",
    }, "deleted-user"),
    {
      assigneeID: null,
      assigneeName: null,
      claimedAt: null,
      status: "unclaimed",
    },
  );
});

test("assignment requests involving the deleted user are cleared", () => {
  assert.deepEqual(
    anonymizationUpdate({
      requestedByID: "someone-else",
      requestedToID: "deleted-user",
      assignmentRequestID: "request-1",
    }, "deleted-user"),
    {
      assignmentRequestID: null,
      assignmentMode: null,
      requestedByID: null,
      requestedByName: null,
      requestedToID: null,
      requestedToName: null,
      assignmentRequestedAt: null,
    },
  );
});
