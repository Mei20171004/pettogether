const assert = require("node:assert/strict");
const { readFileSync } = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const vm = require("node:vm");

// Matches the entitlement attached to both products in RevenueCat.
const dashboardEntitlement = "pet_together_pro";

function webhookHarness() {
  const writes = [];
  const db = {
    collection: (collection) => ({
      doc: (uid) => ({ set: async (data) => writes.push({ collection, uid, data }) }),
    }),
    collectionGroup: () => ({ where: () => ({ get: async () => ({ docs: [] }) }) }),
  };
  const trigger = (_, handler) => handler;
  const modules = {
    "firebase-functions/v2/firestore": { onDocumentCreated: trigger, onDocumentWritten: trigger },
    "firebase-functions/v2/scheduler": { onSchedule: trigger },
    "firebase-functions/v2/https": { onRequest: trigger },
    "firebase-functions/params": { defineSecret: () => ({ value: () => "fixture-auth" }) },
    "firebase-functions/logger": { info() {}, warn() {}, error() {} },
    "firebase-admin/app": { initializeApp() {} },
    "firebase-admin/firestore": {
      getFirestore: () => db,
      FieldValue: { serverTimestamp: () => "server-time" },
      Timestamp: { fromMillis: (millis) => ({ toMillis: () => millis }) },
    },
    "firebase-admin/messaging": { getMessaging() {} },
    crypto: require("node:crypto"),
  };
  const context = { exports: {}, require: (id) => {
    assert.ok(Object.hasOwn(modules, id), `Unexpected dependency: ${id}`);
    return modules[id];
  }, Buffer, Date };
  vm.runInNewContext(readFileSync(path.join(__dirname, "../index.js"), "utf8"), context);
  return {
    writes,
    async send(productId, entitlementId, type = "INITIAL_PURCHASE", expiration = Date.now() + 60000) {
      const response = { statusCode: null, body: null,
        status(code) { this.statusCode = code; return this; },
        send(body) { this.body = body; },
      };
      await context.exports.revenuecatWebhook({
        method: "POST", get: () => "fixture-auth",
        body: { event: { type, app_user_id: "fixture-user", product_id: productId,
          entitlement_ids: [entitlementId], expiration_at_ms: expiration } },
      }, response);
      return response;
    },
  };
}

test("client checks the entitlement attached to the RevenueCat products", () => {
  const config = readFileSync(path.join(__dirname, "../../lib/config/app_config.dart"), "utf8");
  const identifier = config.match(/proEntitlementId\s*=\s*'([^']+)'/)[1];
  assert.equal(identifier, dashboardEntitlement);
});

for (const product of ["pettogether_pro_monthly", "pettogether_pro_yearly"]) {
  test(`${product} purchase grants Pro`, async () => {
    const harness = webhookHarness();
    const response = await harness.send(product, dashboardEntitlement);
    assert.equal(response.statusCode, 200);
    assert.equal(response.body, "ok");
    assert.equal(harness.writes.length, 1);
    assert.equal(harness.writes[0].collection, "entitlements");
    assert.equal(harness.writes[0].data.active, true);
    assert.equal(harness.writes[0].data.productId, product);
  });
}

test("an unrelated entitlement does not grant Pro", async () => {
  const harness = webhookHarness();
  const response = await harness.send("other-product", "other-entitlement");
  assert.equal(response.body, "ignored");
  assert.equal(harness.writes.length, 0);
});

test("expiration of the configured entitlement revokes Pro", async () => {
  const harness = webhookHarness();
  const response = await harness.send("pettogether_pro_monthly", dashboardEntitlement, "EXPIRATION", Date.now() - 1);
  assert.equal(response.body, "ok");
  assert.equal(harness.writes.length, 1);
  assert.equal(harness.writes[0].data.active, false);
});
