#!/usr/bin/env node

import { isDirectExecution, runLt7Firebase } from "./lt7_local_environment.mjs";

export async function main(argv = process.argv.slice(2)) {
  const operation = argv[0];
  if (!["emulators", "snapshot", "rules", "functions", "timezone", "migration-test"]
        .includes(operation) ||
      argv.length !== 1) {
    throw new Error(
      "Usage: lt7_firebase.mjs emulators|snapshot|rules|functions|timezone|migration-test",
    );
  }
  await runLt7Firebase(operation);
}

if (isDirectExecution(import.meta.url)) {
  main().catch((error) => {
    process.stderr.write(`${error.message}\n`);
    process.exitCode = 1;
  });
}
