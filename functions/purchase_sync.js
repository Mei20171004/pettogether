const entitlementIds = ["pet_together_pro", "pet_together_multi_pet", "pet_together_ai"];

function syncError(code, status) {
  return Object.assign(new Error("Subscription verification failed."), { code, status });
}

// Read current provider state instead of replaying a possibly stale purchase event.
async function syncPurchases({ uid, key, db, Timestamp, FieldValue, fetchImpl = fetch, now = Date.now }) {
  let response;
  try {
    response = await fetchImpl(
      `https://api.revenuecat.com/v1/subscribers/${encodeURIComponent(uid)}`,
      { headers: { Authorization: `Bearer ${key}` }, signal: AbortSignal.timeout(20000) },
    );
    if (!response.ok) throw syncError("provider-http", response.status);
  } catch (error) {
    if (error.code === "provider-http") throw error;
    throw syncError("provider-network");
  }
  let payload;
  try {
    payload = await response.json();
  } catch (_) {
    throw syncError("provider-response");
  }
  const source = payload?.subscriber?.entitlements;
  if (!source || typeof source !== "object" || Array.isArray(source) ||
      !Number.isFinite(payload.request_date_ms) || payload.request_date_ms <= 0) {
    throw syncError("provider-response");
  }
  const records = {};
  for (const id of entitlementIds) {
    const record = source[id];
    const expires = record?.grace_period_expires_date || record?.expires_date;
    const expiryMs = expires == null ? null : Date.parse(expires);
    if (record && (typeof record.product_identifier !== "string" ||
        record.expires_date === undefined || expiryMs !== null && !Number.isFinite(expiryMs))) {
      throw syncError("provider-expiry");
    }
    const productId = record?.product_identifier || null;
    records[id] = {
      active: !!record && (expiryMs === null || expiryMs > now()),
      expiresAt: expiryMs === null ? null : Timestamp.fromMillis(expiryMs),
      productId,
      store: payload.subscriber.subscriptions?.[productId]?.store || null,
      updatedAt: FieldValue.serverTimestamp(),
    };
  }
  const checkedAt = Timestamp.fromMillis(payload.request_date_ms);
  const reference = db.collection("entitlements").doc(uid);
  return db.runTransaction(async (tx) => {
    const existing = (await tx.get(reference)).data();
    if (existing?.revenuecatCheckedAt?.toMillis() > checkedAt.toMillis()) {
      return existing.entitlements;
    }
    tx.set(reference, {
      ...records.pet_together_pro,
      entitlements: records,
      revenuecatCheckedAt: checkedAt,
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });
    return records;
  });
}

module.exports = { syncPurchases };
