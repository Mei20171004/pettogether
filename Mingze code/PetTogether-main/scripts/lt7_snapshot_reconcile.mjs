#!/usr/bin/env node

import { readFile } from "node:fs/promises";

import { isDirectExecution } from "./lt7_local_environment.mjs";
import {
  reconcilePreservationManifests,
} from "./lt7_preservation_manifest.mjs";

export async function main(argv = process.argv.slice(2)) {
  if (argv.length !== 3) {
    throw new Error(
      "Usage: lt7_snapshot_reconcile.mjs BEFORE MUTATED AFTER",
    );
  }
  const [before, mutated, after] = await Promise.all(
    argv.map(async (path) => JSON.parse(await readFile(path, "utf8"))),
  );
  let mutationDetected = false;
  try {
    reconcilePreservationManifests(before.firestore, mutated.firestore);
  } catch {
    mutationDetected = true;
  }
  if (!mutationDetected) {
    throw new Error("LT7 in-schema drift reconciled with the baseline.");
  }
  reconcilePreservationManifests(before.firestore, after.firestore);
  if (before.snapshotFingerprint !== after.snapshotFingerprint ||
      before.auth.accountCount !== after.auth.accountCount) {
    throw new Error("LT7 restored snapshot does not match the baseline.");
  }
  const projection = before.firestore.semanticProjection;
  process.stdout.write(
    `LT7_SNAPSHOT checkpoint=reconciled sentinels=${before.firestore.sentinelCount} ` +
      `accounts=${before.auth.accountCount} ` +
      `mutationDetected=true ` +
      `taskCompleted=${projection.report.taskCompletedCount} ` +
      `medicationAdministered=${projection.report.medicationAdministeredCount} ` +
      `ledgerExcluded=${projection.report.ledgerExcludedCount} ` +
      `notificationExcluded=${projection.report.notificationExcludedCount} ` +
      `healthRecords=${projection.health.recordCount}\n`,
  );
  return 0;
}

if (isDirectExecution(import.meta.url)) {
  main().catch((error) => {
    process.stderr.write(`${error.message}\n`);
    process.exitCode = 1;
  });
}
