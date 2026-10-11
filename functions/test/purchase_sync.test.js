const assert = require("node:assert/strict");
const test = require("node:test");
const { syncPurchases } = require("../purchase_sync");

const now = Date.now();
const timestamp = (ms) => ({ toMillis: () => ms });
function harness(subscriber, checkedAt = now) {
  let stored = null;
  const db = {
    collection: () => ({ doc: (uid) => ({ uid }) }),
    runTransaction: async (run) => run({
      get: async () => ({ data: () => stored }),
      set: (ref, data) => { stored = { ...stored, ...data }; },
    }),
  };
  const options = {
    uid: "fixture-user", key: "fixture-sdk-key", db,
    Timestamp: { fromMillis: timestamp }, FieldValue: { serverTimestamp: () => "server-time" },
    fetchImpl: async () => ({ ok: true, json: async () => ({ request_date_ms: checkedAt, subscriber }) }),
    now: () => now,
  };
  return { options, read: () => stored, set: (data) => { stored = data; } };
}
const record = (product, expiry) => ({ product_identifier: product, expires_date: expiry });
const future = new Date(now + 60000).toISOString();
const past = new Date(now - 60000).toISOString();

test("server read repairs a missed multi-pet webhook without granting other plans", async () => {
  const h = harness({ entitlements: { pet_together_multi_pet: record("pettogether_multi_pet_monthly", future) } });
  const result = await syncPurchases(h.options);
  assert.equal(result.pet_together_multi_pet.active, true);
  assert.equal(result.pet_together_pro.active, false);
  assert.equal(result.pet_together_ai.active, false);
  assert.equal(h.read().active, false);
});
test("expired or absent subscriptions revoke stale local grants", async () => {
  const h = harness({ entitlements: { pet_together_multi_pet: record("pettogether_multi_pet_monthly", past) } });
  assert.equal((await syncPurchases(h.options)).pet_together_multi_pet.active, false);
});
test("a valid billing grace period retains access", async () => {
  const h = harness({ entitlements: { pet_together_pro: { ...record("pettogether_pro_monthly", past), grace_period_expires_date: future } } });
  assert.equal((await syncPurchases(h.options)).pet_together_pro.active, true);
});
test("an old provider response cannot overwrite a newer active grant", async () => {
  const h = harness({ entitlements: {} }, now - 1000);
  h.set({ revenuecatCheckedAt: timestamp(now), entitlements: { pet_together_multi_pet: { active: true } } });
  assert.equal((await syncPurchases(h.options)).pet_together_multi_pet.active, true);
  assert.equal(h.read().revenuecatCheckedAt.toMillis(), now);
});
for (const kind of ["http", "network", "invalid-json", "invalid-response", "invalid-expiry"]) {
  test(`${kind} failure preserves existing access and surfaces a diagnostic code`, async () => {
    const h = harness({ entitlements: {} });
    if (kind === "http") h.options.fetchImpl = async () => ({ ok: false, status: 503 });
    if (kind === "network") h.options.fetchImpl = async () => { throw new Error("fixture network outage"); };
    if (kind === "invalid-json") h.options.fetchImpl = async () => ({ ok: true, json: async () => { throw new SyntaxError("Fixture invalid JSON"); } });
    if (kind === "invalid-response") h.options.fetchImpl = async () => ({ ok: true, json: async () => ({}) });
    if (kind === "invalid-expiry") h.options.fetchImpl = async () => ({ ok: true, json: async () => ({ request_date_ms: now, subscriber: { entitlements: { pet_together_pro: record("pettogether_pro_monthly", "invalid") } } }) });
    await assert.rejects(syncPurchases(h.options), (e) => typeof e.code === "string");
    assert.equal(h.read(), null);
  });
}
