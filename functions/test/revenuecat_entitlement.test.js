const assert = require("node:assert/strict");
const { readFileSync } = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const vm = require("node:vm");

const dashboardEntitlements = {
  health: "pet_together_pro",
  multiPet: "pet_together_multi_pet",
  ai: "pet_together_ai",
};

function webhookHarness() {
  const writes = [];
  let provider;
  let status = 200;
  let lastRequestUid;
  const stored = new Map();
  let members = [];
  const household = {
    path: 'households/fixture-household',
    collection: (name) => name === 'members' ? { membersQuery: true } : {
      doc: () => ({ uid: 'fixture-household', collection: 'household-pro' }),
    },
  };
  const db = {
    collection: (collection) => ({
      doc: (uid) => ({ uid, set: async (data) => writes.push({ collection, uid, data }) }),
    }),
    runTransaction: async (run) => run({
      get: async (ref) => ref.membersQuery
        ? { docs: members.map((id) => ({ id, data: () => ({ id }) })) }
        : { data: () => stored.get(ref.uid) },
      getAll: async (...refs) => refs.map((ref) => ({ id: ref.uid, exists: stored.has(ref.uid), data: () => stored.get(ref.uid) })),
      set: (ref, data) => {
        writes.push({ collection: ref.collection || "entitlements", uid: ref.uid, data });
        stored.set(ref.uid, data);
      },
    }),
    collectionGroup: () => ({ where: () => ({ get: async () => ({ docs: members.length ? [{ ref: { parent: { parent: household } } }] : [] }) }) }),
  };
  const trigger = (_, handler) => handler;
  const modules = {
    "firebase-functions/v2/firestore": { onDocumentCreated: trigger, onDocumentWritten: trigger },
    "firebase-functions/v2/scheduler": { onSchedule: trigger },
    "firebase-functions/v2/https": {
      HttpsError: class HttpsError extends Error {},
      onCall: trigger,
      onRequest: trigger,
    },
    "firebase-functions/params": { defineSecret: () => ({ value: () => "fixture-auth" }) },
    "firebase-functions/logger": { info() {}, warn() {}, error() {} },
    "firebase-admin/app": { initializeApp() {} },
    "firebase-admin/firestore": {
      getFirestore: () => db,
      FieldValue: { serverTimestamp: () => "server-time" },
      Timestamp: { fromMillis: (millis) => ({ toMillis: () => millis }) },
    },
    "firebase-admin/messaging": { getMessaging() {} },
    "firebase-admin/auth": {
      getAuth: () => ({ getUser: async () => ({ uid: "fixture-user" }) }),
    },
    "firebase-admin/storage": { getStorage: () => ({ bucket() {} }) },
    "./purchase_sync": { syncPurchases: (options) => require("../purchase_sync").syncPurchases({
      ...options, fetchImpl: async (url) => {
        lastRequestUid = decodeURIComponent(url.split("/").pop());
        return { ok: status === 200, status, json: async () => provider };
      },
    }) },
    "./web_sign_in": { issueWebSignInToken() {} },
    "./account_deletion": require("../account_deletion"),
    crypto: require("node:crypto"),
  };
  const context = { exports: {}, require: (id) => {
    assert.ok(Object.hasOwn(modules, id), `Unexpected dependency: ${id}`);
    return modules[id];
  }, Buffer, Date };
  vm.runInNewContext(readFileSync(path.join(__dirname, "../index.js"), "utf8"), context);
  return {
    writes,
    setHousehold: (ids) => { members = ids; },
    setMemberAccess: (uid, value) => stored.set(uid, value),
    lastUid: () => lastRequestUid,
    setProvider: (value) => { provider = value; },
    setStatus: (value) => { status = value; },
    callable: context.exports.syncPurchaseEntitlements,
    async send(productId, entitlementId, type = "INITIAL_PURCHASE", expiration = Date.now() + 60000, extra = {}) {
      provider ||= { request_date_ms: Date.now(), subscriber: { entitlements: { [entitlementId]: { product_identifier: productId, expires_date: new Date(expiration).toISOString() } } } };
      const response = { statusCode: null, body: null,
        status(code) { this.statusCode = code; return this; },
        send(body) { this.body = body; },
      };
      await context.exports.revenuecatWebhook({
        method: "POST", get: () => extra.header || "fixture-auth",
        body: { event: { type, app_user_id: "fixture-user", product_id: productId,
          entitlement_ids: [entitlementId], expiration_at_ms: expiration, ...extra } },
      }, response);
      return response;
    },
  };
}

test("client checks the three RevenueCat entitlements", () => {
  const config = readFileSync(path.join(__dirname, "../../lib/config/app_config.dart"), "utf8");
  assert.equal(config.match(/proEntitlementId\s*=\s*'([^']+)'/)[1], dashboardEntitlements.health);
  assert.equal(config.match(/multiPetEntitlementId\s*=\s*'([^']+)'/)[1], dashboardEntitlements.multiPet);
  assert.equal(config.match(/aiEntitlementId\s*=\s*'([^']+)'/)[1], dashboardEntitlements.ai);
});

for (const product of ["pettogether_pro_monthly", "pettogether_pro_yearly"]) {
  test(`${product} purchase grants Pro`, async () => {
    const harness = webhookHarness();
    const response = await harness.send(product, dashboardEntitlements.health);
    assert.equal(response.statusCode, 200);
    assert.equal(response.body, "ok");
    assert.equal(harness.writes.length, 1);
    assert.equal(harness.writes[0].collection, "entitlements");
    assert.equal(harness.writes[0].data.active, true);
    assert.equal(harness.writes[0].data.productId, product);
  });
}

for (const [product, entitlement] of [
  ["pettogether_multi_pet_monthly", dashboardEntitlements.multiPet],
  ["pettogether_ai_monthly", dashboardEntitlements.ai],
]) {
  test(`${product} grants only its own add-on`, async () => {
    const harness = webhookHarness();
    const response = await harness.send(product, entitlement);
    assert.equal(response.statusCode, 200);
    assert.equal(response.body, "ok");
    assert.equal(harness.writes.length, 1);
    assert.equal(harness.writes[0].collection, "entitlements");
    assert.equal(harness.writes[0].data.entitlements[entitlement].active, true);
    assert.equal(harness.writes[0].data.entitlements[entitlement].productId, product);
    assert.equal(harness.writes[0].data.active, false);
  });
}

test("an unrelated entitlement does not grant Pro", async () => {
  const harness = webhookHarness();
  const response = await harness.send("other-product", "other-entitlement");
  assert.equal(response.body, "ok");
  assert.equal(harness.writes[0].data.active, false);
});

test("expiration of the configured entitlement revokes Pro", async () => {
  const harness = webhookHarness();
  const response = await harness.send("pettogether_pro_monthly", dashboardEntitlements.health, "EXPIRATION", Date.now() - 1);
  assert.equal(response.body, "ok");
  assert.equal(harness.writes.length, 1);
  assert.equal(harness.writes[0].data.active, false);
});

test("expiration revokes only the matching add-on", async () => {
  const harness = webhookHarness();
  const response = await harness.send(
    "pettogether_ai_monthly",
    dashboardEntitlements.ai,
    "EXPIRATION",
    Date.now() - 1,
  );
  assert.equal(response.body, "ok");
  assert.equal(
    harness.writes[0].data.entitlements[dashboardEntitlements.ai].active,
    false,
  );
  assert.equal(harness.writes[0].data.active, false);
});


test("unauthorized webhook cannot read provider state or grant access", async () => {
  const h = webhookHarness();
  assert.equal((await h.send("fixture", "fixture", "RENEWAL", Date.now(), { header: "wrong" })).statusCode, 401);
  assert.equal(h.writes.length, 0);
  assert.equal(h.lastUid(), undefined);
});
test("historical expiration events read current access rather than revoking a renewed purchase", async () => {
  const h = webhookHarness();
  h.setProvider({ request_date_ms: Date.now(), subscriber: { entitlements: {
    pet_together_multi_pet: { product_identifier: "pettogether_multi_pet_monthly", expires_date: new Date(Date.now() + 60000).toISOString() },
  } } });
  await h.send("pettogether_multi_pet_monthly", dashboardEntitlements.multiPet, "EXPIRATION", Date.now() - 1000);
  assert.equal(h.writes[0].data.entitlements.pet_together_multi_pet.active, true);
});
test("anonymous purchase aliases synchronize the identified Firebase account", async () => {
  const h = webhookHarness();
  await h.send("pettogether_multi_pet_monthly", dashboardEntitlements.multiPet, "INITIAL_PURCHASE", Date.now() + 60000,
    { app_user_id: "$RCAnonymousID:fixture", aliases: ["$RCAnonymousID:fixture", "fixture-user"] });
  assert.equal(h.lastUid(), "fixture-user");
  assert.equal(h.writes.length, 1);
});
test("provider failure is retried rather than marked as successfully synchronized", async () => {
  const h = webhookHarness(); h.setStatus(503);
  assert.equal((await h.send("fixture", "fixture")).statusCode, 500);
  assert.equal(h.writes.length, 0);
});
test("callable rejects signed-out requests", async () => {
  await assert.rejects(webhookHarness().callable({ data: { uid: "other-user" } }));
});
test("callable synchronizes only the authenticated uid", async () => {
  const h = webhookHarness();
  h.setProvider({ request_date_ms: Date.now(), subscriber: { entitlements: {} } });
  assert.equal((await h.callable({ auth: { uid: "fixture-user" }, data: { uid: "other-user", active: true } })).synced, true);
  assert.equal(h.lastUid(), "fixture-user");
  assert.equal(h.writes[0].data.active, false);
});

test("verified user purchase reaches the household mirror and preserves another member's add-on", async () => {
  const h = webhookHarness();
  h.setHousehold(["fixture-user", "fixture-other"]);
  const expiry = { toMillis: () => Date.now() + 60000 };
  h.setMemberAccess("fixture-other", { entitlements: {
    pet_together_ai: { active: true, expiresAt: expiry },
    pet_together_pro: { active: true, expiresAt: { toMillis: () => Date.now() - 1000 } },
  } });
  const response = await h.send("pettogether_multi_pet_monthly", dashboardEntitlements.multiPet);
  assert.equal(response.statusCode, 200);
  const mirror = h.writes.find((write) => write.collection === "household-pro").data;
  assert.equal(mirror.multiPetActive, true);
  assert.equal(mirror.aiActive, true);
  assert.equal(mirror.active, false);
});
