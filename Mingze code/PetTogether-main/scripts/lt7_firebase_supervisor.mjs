#!/usr/bin/env node

// Long-running LT7 Emulator entry point for the acceptance driver. It applies
// the same guards as lt7_firebase.mjs and lt7_restore.mjs but keeps a single
// terminable process in the foreground so the driver can stop the suite.

import { isDirectExecution, runLt7Firebase } from "./lt7_local_environment.mjs";

export async function main(argv = process.argv.slice(2)) {
  const operation = argv[0];
  if (operation === "snapshot" && argv.length === 1) {
    return await runLt7Firebase("snapshot");
  }
  if (operation === "restore" && argv.length === 2) {
    return await runLt7Firebase("restore", argv[1]);
  }
  throw new Error(
    "Usage: lt7_firebase_supervisor.mjs snapshot | restore EXPORT_DIRECTORY",
  );
}

if (isDirectExecution(import.meta.url)) {
  main().catch((error) => {
    process.stderr.write(`${error.message}\n`);
    process.exitCode = 1;
  });
}
