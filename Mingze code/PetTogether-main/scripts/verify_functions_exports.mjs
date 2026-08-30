#!/usr/bin/env node

import { readFile } from "node:fs/promises";
import { resolve } from "node:path";
import { spawn } from "node:child_process";
import { fileURLToPath, pathToFileURL } from "node:url";

const manifestURL = new URL(
  "../tests/fixtures/lt7-functions-exports.json",
  import.meta.url,
);
const manifest = JSON.parse(await readFile(manifestURL, "utf8"));

export const EXPECTED_FUNCTION_EXPORTS = Object.freeze([...manifest.exports]);

export function verifyFunctionExports(source) {
  const actual = Object.keys(source).sort();
  const expected = [...EXPECTED_FUNCTION_EXPORTS].sort();
  const missing = expected.filter((name) => !actual.includes(name));
  const unexpected = actual.filter((name) => !expected.includes(name));
  if (missing.length > 0 || unexpected.length > 0) {
    throw new Error(
      `Functions export mismatch; missing=${missing.join(",") || "none"}; ` +
      `unexpected=${unexpected.join(",") || "none"}.`,
    );
  }
  for (const name of expected) {
    if (typeof source[name] !== "function") {
      throw new Error(`Functions export ${name} is not callable.`);
    }
  }
  return expected;
}

async function main() {
  if (process.argv[2] === "--worker") {
    await discoverInWorker();
    return;
  }
  await runDiscoveryWorker();
}

async function discoverInWorker() {
  const sourceRoot = process.env.COPAW_FUNCTIONS_SOURCE_ROOT ??
    fileURLToPath(new URL("../functions", import.meta.url));
  const source = await import(pathToFileURL(resolve(sourceRoot, "index.js")).href);
  const verified = verifyFunctionExports(source);
  process.stdout.write(`${JSON.stringify({
    schemaVersion: 1,
    nodeVersion: process.version,
    exportCount: verified.length,
    exports: verified,
  })}\n`);
}

async function runDiscoveryWorker() {
  await new Promise((resolvePromise, reject) => {
    const child = spawn(process.execPath, [process.argv[1], "--worker"], {
      env: process.env,
      stdio: ["ignore", "pipe", "pipe"],
    });
    let stdout = "";
    let stderr = "";
    child.stdout.on("data", (chunk) => { stdout += chunk; });
    child.stderr.on("data", (chunk) => { stderr += chunk; });
    const timeout = setTimeout(() => {
      child.kill("SIGKILL");
      reject(new Error("Functions source discovery exceeded 10 seconds."));
    }, 10000);
    child.once("error", (error) => {
      clearTimeout(timeout);
      reject(error);
    });
    child.once("exit", (code, signal) => {
      clearTimeout(timeout);
      if (code !== 0) {
        reject(new Error(
          stderr.trim() || `Functions discovery failed (${signal ?? `exit ${code}`}).`,
        ));
        return;
      }
      process.stdout.write(stdout);
      resolvePromise();
    });
  });
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  main().then(
    () => process.exit(0),
    (error) => {
      process.stderr.write(`${error.message}\n`);
      process.exit(1);
    },
  );
}
