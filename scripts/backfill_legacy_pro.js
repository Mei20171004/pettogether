#!/usr/bin/env node
// Marks households that existed before the paywall as `legacy: true` in
// households/{householdId}/private/pro, so today's users keep the features
// they already have (health-record attachments above all) without paying.
//
// `legacy` belongs to this script alone. exports.revenuecatWebhook writes the
// same document with merge and never touches `legacy`, so a later purchase or
// expiration cannot clear a grandfathered household.
//
// On the creation timestamp: households do carry `createdAt` (a server
// timestamp written by _householdData in lib/services/firebase_care_service.dart
// at creation, and never rewritten — later edits use update() on single
// fields). It is therefore used as the cutoff key. A household whose
// `createdAt` is missing or unreadable predates or bypassed that write, so it
// is ALSO treated as legacy — being generous here is safe, being strict would
// silently take a paid-for feature away from an existing user. The run prints
// how many households were marked that way.
//
// Run (dry run first, then commit):
//
//   cd /Users/sunmingze/Documents/GitHub/pettogether && \
//   GOOGLE_CLOUD_PROJECT=pettogether-76452 \
//   GOOGLE_APPLICATION_CREDENTIALS=$HOME/.config/gcloud/application_default_credentials.json \
//   node scripts/backfill_legacy_pro.js --cutoff=2026-09-12
//
//   cd /Users/sunmingze/Documents/GitHub/pettogether && \
//   GOOGLE_CLOUD_PROJECT=pettogether-76452 \
//   GOOGLE_APPLICATION_CREDENTIALS=$HOME/.config/gcloud/application_default_credentials.json \
//   node scripts/backfill_legacy_pro.js --cutoff=2026-09-12 --commit
//
// `firebase-admin` is resolved from functions/node_modules, so run
// `npm install` inside functions/ once before the first run.

// eslint-disable-next-line import/no-unresolved
const admin = requireAdmin();

const pageSize = 500;
const batchSize = 400;

main().catch((error) => {
  console.error(error.stack || String(error));
  process.exitCode = 1;
});

async function main() {
  const options = parseArguments(process.argv.slice(2));

  admin.initializeApp({ credential: admin.credential.applicationDefault() });
  const db = admin.firestore();

  console.log(`cutoff        : ${options.cutoff.toISOString()} (households created before this are legacy)`);
  console.log(`mode          : ${options.commit ? "COMMIT (writing)" : "DRY RUN (no writes)"}`);

  const targets = [];
  let scanned = 0;
  let missingCreatedAt = 0;
  let skipped = 0;

  for await (const household of households(db)) {
    scanned += 1;
    const createdAt = toDate(household.get("createdAt"));
    if (createdAt === null) {
      // No usable creation timestamp: grandfather it rather than risk
      // revoking a feature an existing household already relies on.
      missingCreatedAt += 1;
      targets.push(household.ref);
      continue;
    }
    if (createdAt < options.cutoff) {
      targets.push(household.ref);
      continue;
    }
    skipped += 1;
  }

  console.log(`scanned       : ${scanned} households`);
  console.log(`to mark legacy: ${targets.length}`);
  console.log(`  of which no createdAt (marked anyway): ${missingCreatedAt}`);
  console.log(`after cutoff  : ${skipped} (left alone)`);

  if (targets.length === 0) {
    console.log("nothing to do");
    return;
  }
  if (!options.commit) {
    console.log("dry run: pass --commit to write households/{id}/private/pro { legacy: true }");
    return;
  }

  let written = 0;
  for (const group of chunks(targets, batchSize)) {
    const batch = db.batch();
    for (const householdReference of group) {
      // Merge so the webhook's active/sponsorUid/expiresAt fields survive.
      batch.set(
        householdReference.collection("private").doc("pro"),
        {
          legacy: true,
          legacyBackfilledAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
    }
    await batch.commit();
    written += group.length;
    console.log(`committed     : ${written}/${targets.length}`);
  }
  console.log("done");
}

/// Pages through /households by document id so a large project does not have
/// to fit in one query result.
async function* households(db) {
  let cursor = null;
  for (;;) {
    let query = db
      .collection("households")
      .orderBy(admin.firestore.FieldPath.documentId())
      .limit(pageSize);
    if (cursor) query = query.startAfter(cursor);

    const page = await query.get();
    if (page.empty) return;
    for (const document of page.docs) yield document;
    if (page.size < pageSize) return;
    cursor = page.docs[page.size - 1].id;
  }
}

function parseArguments(argv) {
  let cutoff = null;
  let commit = false;

  for (const argument of argv) {
    if (argument.startsWith("--cutoff=")) {
      cutoff = argument.slice("--cutoff=".length);
      continue;
    }
    if (argument === "--commit") {
      commit = true;
      continue;
    }
    // --dry-run is the default; accepting it explicitly keeps the command
    // readable in a runbook.
    if (argument === "--dry-run") {
      continue;
    }
    usage(`unknown argument: ${argument}`);
  }

  if (!cutoff) usage("--cutoff=YYYY-MM-DD is required");
  if (!/^\d{4}-\d{2}-\d{2}$/.test(cutoff)) usage(`--cutoff must be YYYY-MM-DD, got: ${cutoff}`);
  const parsed = new Date(`${cutoff}T00:00:00Z`);
  if (Number.isNaN(parsed.getTime())) usage(`--cutoff is not a real date: ${cutoff}`);

  return { cutoff: parsed, commit };
}

function usage(message) {
  console.error(`error: ${message}`);
  console.error("usage: node scripts/backfill_legacy_pro.js --cutoff=YYYY-MM-DD [--dry-run|--commit]");
  process.exit(2);
}

function toDate(value) {
  if (!value) return null;
  if (typeof value.toDate === "function") return value.toDate();
  if (value instanceof Date) return value;
  const parsed = new Date(value);
  return Number.isNaN(parsed.getTime()) ? null : parsed;
}

function chunks(items, size) {
  const result = [];
  for (let index = 0; index < items.length; index += size) {
    result.push(items.slice(index, index + size));
  }
  return result;
}

/// The repo keeps its Node dependencies under functions/, so fall back to that
/// copy when the script is run from the repo root.
function requireAdmin() {
  try {
    return require("firebase-admin");
  } catch (_) {
    return require("../functions/node_modules/firebase-admin");
  }
}
