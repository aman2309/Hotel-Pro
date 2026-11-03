const {createHmac, randomInt} = require('node:crypto');
const {FieldValue, Timestamp} = require('firebase-admin/firestore');
const {addOneCalendarYear} = require('./calendar');

const MAX_FAILED = 5;
const LOCK_MS = 15 * 60 * 1000;
const ISSUER = 'hotelpro-license-server-v1';

function pinKey(pin, secret) {
  if (typeof pin !== 'string' || !/^\d{8}$/.test(pin) || !secret) {
    throw Error('Invalid activation input');
  }
  return createHmac('sha256', secret).update(pin).digest('hex');
}

function nextExpiry(license, nowMs) {
  const expires = license && license.expiresAt && license.expiresAt.toDate
    ? license.expiresAt.toDate()
    : null;
  if (expires && expires.getTime() > nowMs) return addOneCalendarYear(expires);
  return addOneCalendarYear(new Date(nowMs));
}

function csvFromRows(rows) {
  const header = 'Serial,PIN,Status,Assigned businessId,Redeemed at';
  const lines = rows.map((row) => [
    row.serial,
    row.pin,
    row.status,
    row.businessId || '',
    row.redeemedAt || '',
  ].join(','));
  return `${header}\n${lines.join('\n')}\n`;
}

async function issueAnnualPins(db, secret, count = 100) {
  if (count !== 100) throw Error('This batch is 100 annual PINs');
  const pins = new Set();
  while (pins.size < count) {
    pins.add(String(randomInt(0, 100000000)).padStart(8, '0'));
  }
  const rows = [];
  const batch = db.batch();
  let serial = 1;
  for (const pin of pins) {
    const key = pinKey(pin, secret);
    const ref = db.doc(`licenseKeys/${key}`);
    const existing = await ref.get();
    if (existing.exists) throw Error('Issuance stopped: key already exists');
    batch.create(ref, {
      status: 'issued',
      plan: 'annual',
      serial,
      createdAt: FieldValue.serverTimestamp(),
    });
    rows.push({
      serial,
      pin,
      status: 'issued',
      businessId: '',
      redeemedAt: '',
    });
    serial += 1;
  }
  await batch.commit();
  return rows;
}

async function activateLicense(db, uid, phone, pin, secret, now = Date.now()) {
  const key = pinKey(pin, secret);
  const userRef = db.doc(`users/${uid}`);
  return db.runTransaction(async (tx) => {
    const user = (await tx.get(userRef)).data();
    if (!user || (phone.includes('@') ? user.email !== phone : user.phoneNumber !== phone)) throw Error('Verified owner required');
    const id = user.businessId;
    if (typeof id !== 'string' || !id || id.includes('/')) throw Error('Invalid mapping');
    const bizRef = db.doc(`businesses/${id}`);
    const licenseRef = db.doc(`businesses/${id}/settings/license`);
    const codeRef = db.doc(`licenseKeys/${key}`);
    const attemptRef = db.doc(`licenseAttempts/${uid}`);
    const [bizSnap, licenseSnap, codeSnap, attemptSnap] = await Promise.all([
      tx.get(bizRef),
      tx.get(licenseRef),
      tx.get(codeRef),
      tx.get(attemptRef),
    ]);
    if (bizSnap.data()?.ownerUid !== uid) throw Error('Hotel owner mismatch');
    const license = licenseSnap.data() || {};
    const issued = codeSnap.data();
    const prior = attemptSnap.data() || {};
    if (prior.lockedUntil && prior.lockedUntil > now) return {error: 'rate-limited'};
    if (issued && issued.status === 'redeemed' && issued.businessId === id && license.lastRedemptionId === key) {
      const expires = license.expiresAt && license.expiresAt.toDate ? license.expiresAt.toDate() : null;
      return {
        activated: true,
        idempotent: true,
        businessId: id,
        expiresAt: expires ? expires.toISOString() : null,
      };
    }
    const sameWindow = Boolean(prior.windowStart) && now - prior.windowStart < 3600000;
    const count = sameWindow ? (prior.count || 0) : 0;
    if (count >= MAX_FAILED) {
      tx.set(attemptRef, {windowStart: now, count: 0, lockedUntil: now + LOCK_MS}, {merge: true});
      return {error: 'rate-limited'};
    }
    const usable = Boolean(issued)
      && issued.disabled !== true
      && issued.status === 'issued'
      && issued.plan === 'annual'
      && (!issued.reservedOwnerUid || issued.reservedOwnerUid === uid);
    if (!usable) {
      const failed = count + 1;
      tx.set(attemptRef, {
        windowStart: sameWindow ? prior.windowStart : now,
        count: failed >= MAX_FAILED ? 0 : failed,
        lockedUntil: failed >= MAX_FAILED ? now + LOCK_MS : 0,
      }, {merge: true});
      return {error: 'invalid-pin'};
    }
    const expiry = nextExpiry(license, now);
    tx.set(codeRef, {
      status: 'redeemed',
      businessId: id,
      ownerUid: uid,
      plan: 'annual',
      redeemedAt: Timestamp.fromMillis(now),
    }, {merge: true});
    tx.set(licenseRef, {
      activated: true,
      issuer: ISSUER,
      plan: 'annual',
      expiresAt: Timestamp.fromMillis(expiry.getTime()),
      lastRedemptionId: key,
      activationId: key,
      activatedAt: license.activatedAt || Timestamp.fromMillis(now),
    }, {merge: true});
    tx.set(attemptRef, {windowStart: now, count: 0, lockedUntil: 0}, {merge: true});
    return {
      activated: true,
      idempotent: false,
      businessId: id,
      expiresAt: expiry.toISOString(),
    };
  });
}

module.exports = {
  pinKey,
  activateLicense,
  issueAnnualPins,
  csvFromRows,
  addOneCalendarYear,
  MAX_FAILED,
  LOCK_MS,
  ISSUER,
};
