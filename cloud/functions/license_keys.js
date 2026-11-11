const {createHmac} = require('node:crypto');
const {Timestamp, FieldValue} = require('firebase-admin/firestore');
const {addCalendarMonths} = require('./calendar');
const {requireAdmin} = require('./admin');

function normalizeKey(raw) {
  if (typeof raw !== 'string') throw Error('INVALID_KEY');
  const key = raw.toUpperCase().replace(/[\s-]/g, '');
  if (!/^HP[A-F0-9]{32}$/.test(key)) throw Error('INVALID_KEY');
  return key;
}
function hashKey(raw, secret) {
  if (!secret) throw Error('MISSING_SECRET');
  return createHmac('sha256', secret).update('license-key-v2:' + normalizeKey(raw)).digest('hex');
}
// Membership plans sold by the admin. Prices are fixed server-side so the
// amount recorded for revenue cannot be changed by the client.
const PLANS = Object.freeze({
  '1m': {months: 1, amount: 1000, label: '1 month'},
  '3m': {months: 3, amount: 2500, label: '3 months'},
  '6m': {months: 6, amount: 5000, label: '6 months'},
  '12m': {months: 12, amount: 10000, label: '12 months'},
});
function planFor(id) {
  if (typeof id !== 'string' || !Object.hasOwn(PLANS, id)) throw Error('INVALID_PLAN');
  return PLANS[id];
}
function durationMonths(value, unit) {
  if (!Number.isInteger(value) || value < 1 || !['months', 'years'].includes(unit)) throw Error('INVALID_DURATION');
  const months = value * (unit === 'years' ? 12 : 1);
  if (months > 1200) throw Error('INVALID_DURATION');
  return months;
}
async function issueKey(db, actor, input, secret) {
  requireAdmin(actor);
  const plan = planFor(input.planId);
  if (input.paymentReceived !== true) throw Error('PAYMENT_REQUIRED');
  const months = plan.months;
  const hotelId = input.hotelId || null;
  if (hotelId !== null && (typeof hotelId !== 'string' || hotelId.includes('/') || hotelId.length > 150)) throw Error('INVALID_HOTEL');
  if (typeof input.requestId !== 'string' || !/^[a-zA-Z0-9_-]{20,100}$/.test(input.requestId)) throw Error('INVALID_REQUEST');
  // A server-secret-derived random-looking key makes a retried issuance idempotent.
  const hex = createHmac('sha256', secret).update(`issue-v2:${actor.uid}:${input.requestId}`).digest('hex').slice(0, 32).toUpperCase();
  const key = 'HP-' + hex.match(/.{4}/g).join('-');
  const id = hashKey(key, secret), ref = db.doc(`licenseKeys/${id}`);
  const audit = db.collection('adminAuditLogs').doc();
  await db.runTransaction(async tx => {
    const prior = await tx.get(ref);
    const hotel = hotelId ? await tx.get(db.doc(`businesses/${hotelId}`)) : null;
    if (hotelId && !hotel.exists) throw Error('HOTEL_NOT_FOUND');
    if (prior.exists) {
      const p = prior.data();
      if (p.issuedBy !== actor.uid || p.planId !== input.planId || p.reservedBusinessId !== hotelId) throw Error('REQUEST_REUSED');
      return;
    }
    tx.create(ref, {version: 2, status: 'issued', disabled: false, plan: input.planId,
      planId: input.planId, planLabel: plan.label, amount: plan.amount, currency: 'INR',
      paymentReceived: true, paymentConfirmedBy: actor.uid, paymentConfirmedAt: FieldValue.serverTimestamp(),
      durationMonths: months, duration: months, durationUnit: 'months',
      reservedBusinessId: hotelId, issuedBy: actor.uid, keyHint: hex.slice(-4),
      createdAt: FieldValue.serverTimestamp()});
    tx.create(audit, {actorUid: actor.uid, action: 'license-key-issued', hotelId,
      keyId: id, durationMonths: months, planId: input.planId, amount: plan.amount,
      createdAt: FieldValue.serverTimestamp()});
  });
  return {key, keyId: id, durationMonths: months, hotelId, planId: input.planId,
    planLabel: plan.label, amount: plan.amount};
}
async function redeemKey(db, uid, identity, raw, secret, now = Date.now()) {
  const id = hashKey(raw, secret);
  return db.runTransaction(async tx => {
    const user = (await tx.get(db.doc(`users/${uid}`))).data();
    if (!user || (identity.includes('@') ? user.email !== identity : user.phoneNumber !== identity)) throw Error('OWNER_REQUIRED');
    const bid = user.businessId;
    if (typeof bid !== 'string' || !bid || bid.includes('/')) throw Error('INVALID_HOTEL');
    const biz = db.doc(`businesses/${bid}`), licenseRef = biz.collection('settings').doc('license');
    const keyRef = db.doc(`licenseKeys/${id}`), attemptRef = db.doc(`licenseAttempts/${uid}`);
    const [hotel, licenseSnap, keySnap, attempts] = await Promise.all([tx.get(biz), tx.get(licenseRef), tx.get(keyRef), tx.get(attemptRef)]);
    if (hotel.data()?.ownerUid !== uid || hotel.data()?.enabled === false) throw Error('OWNER_REQUIRED');
    const license = licenseSnap.data() || {}, issued = keySnap.data(), prior = attempts.data() || {};
    if (prior.lockedUntil > now) return {error: 'rate-limited'};
    if (issued?.version === 2 && issued.status === 'redeemed' && issued.businessId === bid) {
      return {activated: true, businessId: bid, expiresAt: license.expiresAt?.toDate().toISOString(), idempotent: true};
    }
    const months = issued?.durationMonths;
    if (!issued || issued.version !== 2 || issued.status !== 'issued' || issued.disabled ||
        (issued.reservedBusinessId && issued.reservedBusinessId !== bid) || !Number.isInteger(months) || months < 1 || months > 1200) {
      const same = prior.windowStart && now - prior.windowStart < 3600000;
      const count = (same ? prior.count || 0 : 0) + 1;
      tx.set(attemptRef, {windowStart: same ? prior.windowStart : now, count: count >= 5 ? 0 : count,
        lockedUntil: count >= 5 ? now + 900000 : 0}, {merge: true});
      return {error: 'invalid-key'};
    }
    if (!licenseSnap.exists) throw Error('LICENSE_MISSING');
    // Preserve remaining trial/subscription days when renewing early.
    const base = Math.max(now, license.expiresAt?.toMillis() || 0,
      license.activated ? 0 : license.trialEndsAt?.toMillis() || (license.trialStart?.toMillis() || 0) + 864000000);
    const expiry = addCalendarMonths(new Date(base), months);
    tx.set(keyRef, {status: 'redeemed', businessId: bid, ownerUid: uid, redeemedAt: Timestamp.fromMillis(now),
      resultExpiresAt: Timestamp.fromDate(expiry)}, {merge: true});
    tx.set(licenseRef, {activated: true, issuer: 'hotelpro-license-server-v2', plan: issued.planId || 'custom',
      planLabel: issued.planLabel || `${months} months`, durationMonths: months,
      expiresAt: Timestamp.fromDate(expiry), lastRedemptionId: id, activationId: id,
      activatedAt: license.activatedAt || Timestamp.fromMillis(now), renewedAt: Timestamp.fromMillis(now)}, {merge: true});
    tx.set(attemptRef, {windowStart: now, count: 0, lockedUntil: 0});
    tx.create(db.collection('adminAuditLogs').doc(), {actorUid: uid, action: 'license-key-redeemed', hotelId: bid,
      keyId: id, durationMonths: months, createdAt: Timestamp.fromMillis(now)});
    return {activated: true, businessId: bid, expiresAt: expiry.toISOString(), idempotent: false};
  });
}
async function listKeys(db, actor, input = {}) {
  requireAdmin(actor);
  const limit = input.limit ?? 50;
  if (!Number.isInteger(limit) || limit < 1 || limit > 100) throw Error('INVALID_LIMIT');
  let q = db.collection('licenseKeys').orderBy('createdAt', 'desc').limit(limit);
  if (input.after) {
    if (typeof input.after !== 'string' || !/^[a-f0-9]{64}$/.test(input.after)) throw Error('INVALID_CURSOR');
    const cursor = await db.doc(`licenseKeys/${input.after}`).get();
    if (!cursor.exists) throw Error('INVALID_CURSOR');
    q = q.startAfter(cursor);
  }
  const snap = await q.get();
  return {items: snap.docs.map(d => {const p=d.data();return {keyId:d.id, hint:p.keyHint || 'Legacy PIN',
    status:p.disabled ? 'revoked' : p.status, durationMonths:p.durationMonths || (p.plan === 'annual' ? 12 : 0),
    hotelId:p.businessId || p.reservedBusinessId || null, createdAt:p.createdAt?.toMillis() || null,
    redeemedAt:p.redeemedAt?.toMillis() || null, expiresAt:p.resultExpiresAt?.toMillis() || null,
    planId:p.planId || null, planLabel:p.planLabel || null, amount:p.amount || 0,
    paymentReceived:p.paymentReceived === true};}),
    nextCursor:snap.size === limit ? snap.docs.at(-1).id : null};
}
async function revokeKey(db, actor, keyId) {
  requireAdmin(actor);
  if (typeof keyId !== 'string' || !/^[a-f0-9]{64}$/.test(keyId)) throw Error('INVALID_KEY');
  const ref=db.doc(`licenseKeys/${keyId}`);
  await db.runTransaction(async tx => {
    const key=await tx.get(ref);
    if (!key.exists || key.data().status !== 'issued') throw Error('KEY_NOT_UNUSED');
    tx.update(ref,{disabled:true,status:'revoked',revokedAt:FieldValue.serverTimestamp(),revokedBy:actor.uid});
    tx.create(db.collection('adminAuditLogs').doc(), {actorUid:actor.uid,action:'license-key-revoked',keyId,
      hotelId:key.data().reservedBusinessId || null,createdAt:FieldValue.serverTimestamp()});
  });
  return {revoked:true};
}
// India-time month key, e.g. "2026-11".
function istMonth(ms) {
  return new Date(ms + 19800000).toISOString().slice(0, 7);
}
// Membership revenue from paid keys. Revoked keys are excluded.
async function revenue(db, actor, input = {}, now = Date.now()) {
  requireAdmin(actor);
  const snap = await db.collection('licenseKeys').where('paymentReceived', '==', true).get();
  const plans = Object.entries(PLANS).map(([planId, p]) =>
    ({planId, label: p.label, price: p.amount, count: 0, amount: 0}));
  const months = new Map();
  for (let i = 5; i >= 0; i--) {
    const d = new Date(now + 19800000);
    d.setUTCDate(1);d.setUTCMonth(d.getUTCMonth() - i);
    months.set(d.toISOString().slice(0, 7), 0);
  }
  const current = istMonth(now);
  let total = 0, thisMonth = 0, count = 0;
  for (const doc of snap.docs) {
    const k = doc.data();
    if (k.disabled || k.status === 'revoked') continue;
    const amount = Number(k.amount) || 0, at = k.paymentConfirmedAt?.toMillis?.() ?? k.createdAt?.toMillis?.() ?? now;
    total += amount;count++;
    const month = istMonth(at);
    if (month === current) thisMonth += amount;
    if (months.has(month)) months.set(month, months.get(month) + amount);
    const plan = plans.find(p => p.planId === k.planId);
    if (plan) {plan.count++;plan.amount += amount;}
  }
  return {total, thisMonth, count, plans, months: [...months].map(([month, amount]) => ({month, amount}))};
}
module.exports={PLANS,planFor,normalizeKey,hashKey,durationMonths,issueKey,redeemKey,listKeys,revokeKey,revenue};
