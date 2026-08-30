#!/usr/bin/env node

import { isDirectExecution, runLt7Firebase } from "./lt7_local_environment.mjs";

export async function main(argv = process.argv.slice(2)) {
  if (argv.length !== 1) {
    throw new Error("Usage: lt7_restore.mjs /absolute/existing/export-directory");
  }
  await runLt7Firebase("restore", argv[0]);
}

if (isDirectExecution(import.meta.url)) {
  main().catch((error) => {
    process.stderr.write(`${error.message}\n`);
    process.exitCode = 1;
  });
}
