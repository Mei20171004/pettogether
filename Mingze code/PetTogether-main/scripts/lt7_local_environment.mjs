import { isIP } from "node:net";
import { createHmac, timingSafeEqual } from "node:crypto";
import { readFile, stat, writeFile } from "node:fs/promises";
import { isAbsolute, resolve } from "node:path";
import { spawn, spawnSync } from "node:child_process";
import { fileURLToPath, pathToFileURL } from "node:url";

export const LT7_NODE_VERSION = "22.23.2";
export const LT7_PROJECT_ID = "demo-copaw";
export const LT7_CONFIG_FILE = "firebase.lt7.json";

const requiredEmulators = ["auth", "firestore", "functions", "hub", "logging"];
const reservedMainPorts = new Set([
  4000, 4400, 4500, 5001, 8080, 9099, 9150, 9299,
]);

export function parseJavaMajor(output) {
  if (typeof output !== "string") return null;
  const match = output.match(/version\s+"(\d+)(?:\.(\d+))?/i);
  if (match == null) return null;
  const first = Number(match[1]);
  return first === 1 ? Number(match[2]) : first;
}

export function assertLt7Environment({
  nodeVersion,
  javaVersionOutput,
  projectID,
  hosts,
}) {
  if (nodeVersion !== `v${LT7_NODE_VERSION}`) {
    throw new Error(`Repository Node ${LT7_NODE_VERSION} is required.`);
  }
  const javaMajor = parseJavaMajor(javaVersionOutput);
  if (!Number.isInteger(javaMajor) || javaMajor < 21) {
    throw new Error("Java 21 or later is required before opening Emulator ports.");
  }
  if (projectID !== LT7_PROJECT_ID) {
    throw new Error(`LT7 accepts only the explicit ${LT7_PROJECT_ID} project.`);
  }
  for (const name of requiredEmulators) {
    if (!isLoopbackHost(hosts?.[name])) {
      throw new Error(`LT7 ${name} host must be an explicit loopback host.`);
    }
  }
}

export function buildFirebaseArguments(operation, snapshotPath, config) {
  assertIsolatedPorts(config);
  const suffix = ["--config", LT7_CONFIG_FILE, "--project", LT7_PROJECT_ID];
  switch (operation) {
    case "emulators":
      return [
        "emulators:start", "--only", "auth,firestore,functions", ...suffix,
      ];
    case "rules":
      return [
        "emulators:exec", "--only", "firestore", ...suffix,
        "./scripts/node22_exec.sh --test tests/firestore.rules.test.mjs",
      ];
    case "functions":
      return [
        "emulators:exec", "--only", "auth,firestore,functions", ...suffix,
        "./scripts/node22_exec.sh --test --test-concurrency=1 functions/test/*.test.mjs",
      ];
    case "timezone":
      return [
        "emulators:exec", "--only", "auth,firestore,functions", ...suffix,
        "./scripts/node22_exec.sh --test functions/test/lt7_timezone.acceptance.mjs",
      ];
    case "migration-test":
      return [
        "emulators:exec", "--only", "firestore", ...suffix,
        "./scripts/node22_exec.sh --test tests/lt7.migration_emulator.test.mjs",
      ];
    case "snapshot":
      // Auth plus Firestore only: the preservation snapshot never needs the
      // Functions runtime and must not open a provider-capable surface.
      return ["emulators:start", "--only", "auth,firestore", ...suffix];
    case "restore":
      assertSnapshotPath(snapshotPath);
      return [
        "emulators:start", "--only", "auth,firestore",
        "--import", snapshotPath, ...suffix,
      ];
    default:
      throw new Error(`Unsupported LT7 operation: ${operation ?? "missing"}.`);
  }
}

export function lt7FirebaseEnvironment(config, baseEnvironment = {}) {
  assertIsolatedPorts(config);
  return {
    ...baseEnvironment,
    GCLOUD_PROJECT: LT7_PROJECT_ID,
    FIREBASE_CONFIG: JSON.stringify({ projectId: LT7_PROJECT_ID }),
    FIREBASE_EMULATOR_HUB: `${formatHost(config.hub.host)}:${config.hub.port}`,
    FIRESTORE_EMULATOR_HOST:
      `${formatHost(config.firestore.host)}:${config.firestore.port}`,
    FIREBASE_AUTH_EMULATOR_HOST:
      `${formatHost(config.auth.host)}:${config.auth.port}`,
    COPAW_FIRESTORE_TEST_PORT: String(config.firestore.port),
    COPAW_AUTH_TEST_PORT: String(config.auth.port),
    COPAW_FUNCTIONS_TEST_PORT: String(config.functions.port),
  };
}

export function isolatedHubOrigin(config) {
  assertIsolatedPorts(config);
  return `http://${formatHost(config.hub.host)}:${config.hub.port}`;
}

export function assertIsolatedHubInventory(config, status, emulators) {
  const expectedOrigin = isolatedHubOrigin(config);
  if (status?.host !== config.hub.host || status?.port !== config.hub.port ||
      !Array.isArray(status.origins) || !status.origins.includes(expectedOrigin)) {
    throw new Error("LT7 export refused an unexpected Emulator hub.");
  }
  for (const name of ["auth", "firestore"]) {
    const actual = emulators?.[name];
    const expected = config[name];
    if (actual?.host !== expected.host || actual?.port !== expected.port) {
      throw new Error(`LT7 export refused an unexpected ${name} Emulator.`);
    }
  }
}

export function createSignedExportManifest(config, status, key) {
  assertReceiptKey(key);
  const body = {
    schemaVersion: 1,
    environment: "emulator",
    projectID: LT7_PROJECT_ID,
    firebaseToolsVersion: status.version,
    source: {
      hubHost: config.hub.host,
      hubPort: config.hub.port,
      authHost: config.auth.host,
      authPort: config.auth.port,
      firestoreHost: config.firestore.host,
      firestorePort: config.firestore.port,
    },
  };
  return { ...body, signature: signManifest(body, key) };
}

export function assertSignedExportManifest(manifest, config, key) {
  assertReceiptKey(key);
  const expectedBody = {
    schemaVersion: 1,
    environment: "emulator",
    projectID: LT7_PROJECT_ID,
    firebaseToolsVersion: manifest?.firebaseToolsVersion,
    source: {
      hubHost: config.hub.host,
      hubPort: config.hub.port,
      authHost: config.auth.host,
      authPort: config.auth.port,
      firestoreHost: config.firestore.host,
      firestorePort: config.firestore.port,
    },
  };
  if (typeof manifest?.firebaseToolsVersion !== "string" ||
      manifest.firebaseToolsVersion.length === 0 ||
      typeof manifest.signature !== "string" || manifest.signature.length !== 64) {
    throw new Error("LT7 restore requires a signed local export manifest.");
  }
  const expectedSignature = signManifest(expectedBody, key);
  const actual = Buffer.from(manifest.signature, "hex");
  const expected = Buffer.from(expectedSignature, "hex");
  if (actual.length !== expected.length || !timingSafeEqual(actual, expected) ||
      stableStringify({ ...manifest, signature: undefined }) !==
        stableStringify({ ...expectedBody, signature: undefined })) {
    throw new Error("LT7 restore rejected an untrusted export manifest.");
  }
}

export async function loadLt7Config(repositoryRoot) {
  const raw = JSON.parse(await readFile(
    resolve(repositoryRoot, LT7_CONFIG_FILE),
    "utf8",
  ));
  const config = raw?.emulators;
  if (config == null || config.singleProjectMode !== true) {
    throw new Error("LT7 Firebase config must enable singleProjectMode.");
  }
  return Object.fromEntries(requiredEmulators.map((name) => [
    name,
    config[name],
  ]));
}

export async function runLt7Firebase(operation, snapshotPath, options = {}) {
  const repositoryRoot = options.repositoryRoot ??
    resolve(fileURLToPath(new URL("..", import.meta.url)));
  const config = await loadLt7Config(repositoryRoot);
  const java = javaVersion(options.javaExecutable);
  assertLt7Environment({
    nodeVersion: process.version,
    javaVersionOutput: java,
    projectID: LT7_PROJECT_ID,
    hosts: Object.fromEntries(requiredEmulators.map((name) => [
      name,
      config[name]?.host,
    ])),
  });
  if (operation === "export") {
    assertSnapshotPath(snapshotPath);
    const existing = await stat(snapshotPath).catch(() => null);
    if (existing != null) {
      throw new Error("LT7 export target must not already exist.");
    }
    await exportFromIsolatedHub(
      config,
      snapshotPath,
      options.fetchImpl ?? fetch,
      process.env.COPAW_SNAPSHOT_RECEIPT_KEY,
    );
    return 0;
  }
  const args = buildFirebaseArguments(operation, snapshotPath, config);
  if (operation === "restore") {
    const snapshot = await stat(snapshotPath).catch(() => null);
    if (snapshot == null || !snapshot.isDirectory()) {
      throw new Error("LT7 restore input must be an existing export directory.");
    }
    await validateRestoreDirectory(
      snapshotPath,
      config,
      process.env.COPAW_SNAPSHOT_RECEIPT_KEY,
    );
  }
  const firebaseCLI = await resolveFirebaseCLI(
    options.firebaseCLIPath ?? process.env.COPAW_FIREBASE_CLI_PATH ?? resolve(
      repositoryRoot,
      "node_modules/firebase-tools/lib/bin/firebase.js",
    ),
  );
  return await spawnAndWait(process.execPath, [firebaseCLI, ...args], {
    cwd: repositoryRoot,
    env: lt7FirebaseEnvironment(config, process.env),
  });
}

async function resolveFirebaseCLI(value) {
  if (typeof value !== "string" || !isAbsolute(value)) {
    throw new Error("LT7 Firebase CLI path must be absolute.");
  }
  const [script, packageText] = await Promise.all([
    stat(value).catch(() => null),
    readFile(resolve(value, "../../../package.json"), "utf8").catch(() => null),
  ]);
  if (script == null || !script.isFile() || packageText == null) {
    throw new Error("LT7 Firebase CLI installation is incomplete.");
  }
  const packageJSON = JSON.parse(packageText);
  if (packageJSON.name !== "firebase-tools" || packageJSON.version !== "15.26.0") {
    throw new Error("LT7 requires Firebase CLI 15.26.0.");
  }
  return value;
}

export async function exportFromIsolatedHub(
  config,
  snapshotPath,
  fetchImpl,
  receiptKey,
) {
  assertReceiptKey(receiptKey);
  const origin = isolatedHubOrigin(config);
  const [statusResponse, emulatorsResponse] = await Promise.all([
    fetchImpl(`${origin}/`, { signal: AbortSignal.timeout(5000) }),
    fetchImpl(`${origin}/emulators`, { signal: AbortSignal.timeout(5000) }),
  ]);
  if (!statusResponse.ok || !emulatorsResponse.ok) {
    throw new Error("LT7 isolated Emulator hub is unavailable.");
  }
  const status = await statusResponse.json();
  assertIsolatedHubInventory(config, status, await emulatorsResponse.json());
  const response = await fetchImpl(`${origin}/_admin/export`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      path: snapshotPath,
      initiatedBy: "lt7-guarded-export",
      targets: ["auth", "firestore"],
    }),
    signal: AbortSignal.timeout(30000),
  });
  if (!response.ok) {
    throw new Error("LT7 isolated Emulator export failed.");
  }
  await writeFile(
    resolve(snapshotPath, "copaw-lt7-export-manifest.json"),
    `${JSON.stringify(createSignedExportManifest(config, status, receiptKey), null, 2)}\n`,
    { encoding: "utf8", flag: "wx" },
  );
}

async function validateRestoreDirectory(snapshotPath, config, key) {
  const [manifestText, firebaseMetadataText] = await Promise.all([
    readFile(resolve(snapshotPath, "copaw-lt7-export-manifest.json"), "utf8"),
    readFile(resolve(snapshotPath, "firebase-export-metadata.json"), "utf8"),
  ]).catch(() => {
    throw new Error("LT7 restore requires a complete signed local export.");
  });
  const manifest = JSON.parse(manifestText);
  assertSignedExportManifest(manifest, config, key);
  const metadata = JSON.parse(firebaseMetadataText);
  const keys = Object.keys(metadata).sort();
  if (stableStringify(keys) !== stableStringify(["auth", "firestore", "version"]) ||
      metadata.auth?.path !== "auth_export" ||
      metadata.firestore?.path !== "firestore_export" ||
      typeof metadata.firestore?.metadata_file !== "string") {
    throw new Error("LT7 restore rejected unexpected export metadata.");
  }
}

function javaVersion(javaExecutable) {
  const executable = javaExecutable ??
    (process.env.JAVA_HOME == null
      ? "java"
      : resolve(process.env.JAVA_HOME, "bin/java"));
  const result = spawnSync(executable, ["-version"], {
    encoding: "utf8",
    timeout: 5000,
  });
  if (result.error != null) return "";
  return `${result.stderr ?? ""}\n${result.stdout ?? ""}`;
}

function isLoopbackHost(value) {
  if (typeof value !== "string" || value.length === 0) return false;
  const host = value.startsWith("[") && value.endsWith("]")
    ? value.slice(1, -1)
    : value;
  return host === "localhost" || host === "::1" ||
    (isIP(host) === 4 && host.startsWith("127."));
}

function formatHost(host) {
  return isIP(host) === 6 ? `[${host}]` : host;
}

function assertIsolatedPorts(config) {
  const seen = new Set();
  for (const name of requiredEmulators) {
    const entry = config?.[name];
    if (!isLoopbackHost(entry?.host)) {
      throw new Error(`LT7 ${name} host must be an explicit loopback host.`);
    }
    if (!Number.isInteger(entry?.port) || entry.port < 1024 || entry.port > 65535) {
      throw new Error(`LT7 ${name} port is invalid.`);
    }
    if (reservedMainPorts.has(entry.port)) {
      throw new Error(`LT7 ${name} uses a reserved main Emulator port.`);
    }
    if (seen.has(entry.port)) {
      throw new Error("LT7 Emulator ports must be unique.");
    }
    seen.add(entry.port);
  }
}

function assertSnapshotPath(value) {
  if (typeof value !== "string" || !isAbsolute(value) || value === "/tmp") {
    throw new Error("LT7 snapshot path must be a specific absolute path.");
  }
}

function assertReceiptKey(key) {
  if (typeof key !== "string" || key.length < 16) {
    throw new Error("COPAW_SNAPSHOT_RECEIPT_KEY must contain at least 16 characters.");
  }
}

function signManifest(body, key) {
  return createHmac("sha256", key).update(stableStringify(body)).digest("hex");
}

function stableStringify(value) {
  if (Array.isArray(value)) return `[${value.map(stableStringify).join(",")}]`;
  if (value != null && typeof value === "object") {
    return `{${Object.keys(value).filter((key) => value[key] !== undefined).sort()
      .map((key) => `${JSON.stringify(key)}:${stableStringify(value[key])}`)
      .join(",")}}`;
  }
  return JSON.stringify(value);
}

async function spawnAndWait(command, args, options) {
  return await new Promise((resolvePromise, reject) => {
    const child = spawn(command, args, { ...options, stdio: "inherit" });
    // A stopped wrapper must never leave an orphan Emulator holding the
    // isolated ports, so termination is forwarded to the Firebase process.
    const forward = (signal) => {
      if (child.exitCode == null && child.signalCode == null) {
        child.kill(signal);
      }
    };
    const stop = () => forward("SIGTERM");
    const interrupt = () => forward("SIGINT");
    process.once("SIGTERM", stop);
    process.once("SIGINT", interrupt);
    const release = () => {
      process.removeListener("SIGTERM", stop);
      process.removeListener("SIGINT", interrupt);
    };
    child.once("error", (error) => {
      release();
      reject(error);
    });
    child.once("exit", (code, signal) => {
      release();
      if (code === 0 || signal === "SIGTERM" || signal === "SIGINT") {
        resolvePromise(0);
      } else {
        reject(new Error(
          `LT7 Firebase command failed (${signal ?? `exit ${code}`}).`,
        ));
      }
    });
  });
}

export function isDirectExecution(metaURL, argv = process.argv) {
  return metaURL === pathToFileURL(argv[1] ?? "").href;
}
