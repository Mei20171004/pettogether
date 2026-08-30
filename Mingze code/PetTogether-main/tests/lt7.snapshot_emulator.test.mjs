import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { test } from "node:test";

const seed = JSON.parse(await readFile(
  new URL("./fixtures/lt7-preservation-sentinels.json", import.meta.url),
  "utf8",
));
const firestoreHost = process.env.FIRESTORE_EMULATOR_HOST;
const authHost = process.env.FIREBASE_AUTH_EMULATOR_HOST;
const action = process.env.LT7_SNAPSHOT_ACTION;

test(`LT7-AC04 synthetic snapshot ${action}`, async () => {
  assert.equal(firestoreHost, "127.0.0.1:8280");
  assert.equal(authHost, "127.0.0.1:9399");
  if (action === "seed") {
    await seedAuth();
    for (const document of seed.supportDocuments ?? []) {
      await writeSentinel(document);
    }
    for (const sentinel of seed.sentinels) await writeSentinel(sentinel);
  } else if (action === "probe") {
    // Out-of-schema drift: the receipt must refuse it instead of fingerprinting it.
    const sentinel = structuredClone(seed.sentinels[0]);
    sentinel.data.mutationProbe = "must-disappear-after-restore";
    await writeSentinel(sentinel);
  } else if (action === "mutate") {
    // In-schema drift: the receipt stays valid but must not reconcile.
    const sentinel = structuredClone(seed.sentinels[0]);
    sentinel.data.name = "Mutated synthetic household";
    await writeSentinel(sentinel);
  } else {
    throw new Error("LT7_SNAPSHOT_ACTION must be seed, probe, or mutate.");
  }
});

async function seedAuth() {
  const response = await fetch(
    `http://${authHost}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=local`,
    {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        email: "synthetic-caregiver@example.invalid",
        password: "local-only-password-22",
        returnSecureToken: false,
      }),
    },
  );
  if (!response.ok) {
    const body = await response.text();
    assert.match(body, /EMAIL_EXISTS/, `Auth seed failed with ${response.status}`);
  }
}

async function writeSentinel(sentinel) {
  const path = sentinel.path.split("/").map(encodeURIComponent).join("/");
  const response = await fetch(
    `http://${firestoreHost}/v1/projects/demo-copaw/` +
      `databases/(default)/documents/${path}`,
    {
      method: "PATCH",
      headers: {
        authorization: "Bearer owner",
        "content-type": "application/json",
      },
      body: JSON.stringify({ fields: encodeMap(sentinel.data) }),
    },
  );
  assert.equal(response.ok, true, `sentinel seed failed with ${response.status}`);
}

function encodeMap(data) {
  return Object.fromEntries(Object.entries(data).map(([key, value]) => [
    key,
    encodeValue(value),
  ]));
}

function encodeValue(value) {
  if (value == null) return { nullValue: null };
  if (typeof value === "boolean") return { booleanValue: value };
  if (Number.isInteger(value)) return { integerValue: String(value) };
  if (typeof value === "number") return { doubleValue: value };
  if (typeof value === "string") return { stringValue: value };
  if (Array.isArray(value)) return { arrayValue: { values: value.map(encodeValue) } };
  if (typeof value === "object") {
    // Sentinel instants are seeded as real Firestore timestamps so the corpus
    // is schema-faithful rather than a portable marker map.
    return value.__type === "timestamp"
      ? { timestampValue: value.value }
      : { mapValue: { fields: encodeMap(value) } };
  }
  throw new Error("Unsupported sentinel value.");
}
