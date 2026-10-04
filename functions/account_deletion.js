class AccountDeletionError extends Error {
  constructor(code, message, details = undefined) {
    super(message);
    this.code = code;
    this.details = details;
  }
}

function resolveNewOwner(uid, members, requestedUid) {
  const candidates = members.filter((member) => member.id !== uid);
  if (candidates.length === 0) return null;
  const selected = candidates.find((member) => member.id === requestedUid);
  if (!selected) {
    throw new AccountDeletionError(
      "owner-transfer-required",
      "Choose another household member as the new owner before deleting this account.",
      { candidates },
    );
  }
  return selected;
}

function anonymizationUpdate(data, uid) {
  const update = {};
  const anonymize = (idField, nameField, emptyId = null) => {
    if (data[idField] !== uid) return;
    update[idField] = emptyId;
    if (nameField) update[nameField] = "Deleted user";
  };

  anonymize("createdByID", data.createdBy !== undefined ? "createdBy" : "createdByName", "");
  anonymize("completedByID", "completedBy");
  anonymize("updatedByID", "updatedByName");

  if (data.assigneeID === uid) {
    update.assigneeID = null;
    update.assigneeName = null;
    update.claimedAt = null;
    if (data.status === "claimed") update.status = "unclaimed";
  }

  if (data.requestedByID === uid || data.requestedToID === uid) {
    update.assignmentRequestID = null;
    update.assignmentMode = null;
    update.requestedByID = null;
    update.requestedByName = null;
    update.requestedToID = null;
    update.requestedToName = null;
    update.assignmentRequestedAt = null;
  }

  return update;
}

async function deleteAccountData({
  db,
  auth,
  bucket,
  uid,
  newOwnerUid,
  deleteRevenueCatCustomer,
  recomputeHouseholdPro,
  logger,
}) {
  const memberships = await db
    .collectionGroup("members")
    .where("id", "==", uid)
    .get();

  const households = [];
  for (const membership of memberships.docs) {
    const householdRef = membership.ref.parent.parent;
    if (!householdRef) continue;
    const [household, members] = await Promise.all([
      householdRef.get(),
      householdRef.collection("members").get(),
    ]);
    if (!household.exists) continue;
    const memberRecords = members.docs.map((member) => ({
      id: member.id,
      displayName: member.data().displayName || "Household member",
      ref: member.ref,
    }));
    const isOwner = household.data().ownerID === uid;
    households.push({
      ref: householdRef,
      membershipRef: membership.ref,
      isOwner,
      newOwner: isOwner
        ? resolveNewOwner(uid, memberRecords, newOwnerUid)
        : null,
    });
  }

  await deleteRevenueCatCustomer(uid);

  await Promise.all([
    db.collection("userinfo").doc(uid).delete(),
    db.collection("entitlements").doc(uid).delete(),
    db.collection("aiUsage").doc(uid).delete(),
    db.collection("freeCouponRedemptions").doc(uid).delete(),
  ]);

  const retainedHouseholds = [];
  for (const household of households) {
    if (household.isOwner && household.newOwner === null) {
      await bucket.deleteFiles({ prefix: `${household.ref.path}/` });
      await db.recursiveDelete(household.ref);
      continue;
    }

    if (household.newOwner) {
      await db.runTransaction(async (transaction) => {
        transaction.update(household.ref, {
          ownerID: household.newOwner.id,
        });
        transaction.update(household.newOwner.ref, { role: "owner" });
      });
    }

    await anonymizeHousehold(db, household.ref, uid);
    await db.recursiveDelete(household.membershipRef);
    retainedHouseholds.push(household.ref);
  }

  await deleteMatchingDocuments(db, "joinRequests", "userId", uid);
  await deleteMatchingDocuments(db, "invitations", "invitedBy", uid, false);
  await deleteMatchingDocuments(db, "invitations", "claimedBy", uid, false);

  for (const householdRef of retainedHouseholds) {
    await recomputeHouseholdPro(householdRef);
  }

  await auth.deleteUser(uid);
  logger.info("Account permanently deleted", {
    uid,
    householdsRemovedOrLeft: households.length,
  });
}

async function anonymizeHousehold(db, householdRef, uid) {
  for (const collectionName of [
    "routines",
    "tasks",
    "medicationPlans",
    "healthRecords",
  ]) {
    const snapshot = await householdRef.collection(collectionName).get();
    for (let offset = 0; offset < snapshot.docs.length; offset += 400) {
      const batch = db.batch();
      let writes = 0;
      for (const document of snapshot.docs.slice(offset, offset + 400)) {
        const update = anonymizationUpdate(document.data(), uid);
        if (Object.keys(update).length === 0) continue;
        batch.update(document.ref, update);
        writes += 1;
      }
      if (writes > 0) await batch.commit();
    }
  }
}

async function deleteMatchingDocuments(
  db,
  collectionName,
  field,
  uid,
  collectionGroup = true,
) {
  const base = collectionGroup
    ? db.collectionGroup(collectionName)
    : db.collection(collectionName);
  const snapshot = await base.where(field, "==", uid).get();
  for (const document of snapshot.docs) {
    await db.recursiveDelete(document.ref);
  }
}

module.exports = {
  AccountDeletionError,
  anonymizationUpdate,
  deleteAccountData,
  resolveNewOwner,
};
