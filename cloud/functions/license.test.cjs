const {test, after} = require('node:test');
const assert = require('node:assert/strict');
const {writeFileSync, rmSync, readFileSync} = require('node:fs');
const {join} = require('node:path');
const {tmpdir} = require('node:os');
const {initializeApp, deleteApp} = require('firebase-admin/app');
const {getFirestore, Timestamp} = require('firebase-admin/firestore');
const {pinKey, activateLicense, issueAnnualPins, csvFromRows, addOneCalendarYear, ISSUER} = require('./license');

if (process.env.FIRESTORE_EMULATOR_HOST !== '127.0.0.1:18080') throw Error('Local emulator only');
const app = initializeApp({projectId: 'demo-hotel-pro-sync'}, 'license-tests');
const db = getFirestore(app);
const secret = 'test-secret-only';
const pin = '12345678';
after(() => deleteApp(app));

async function hotel(uid, phone, extra = {}) {
  await db.doc(`users/${uid}`).set({businessId: uid, phoneNumber: phone, role: 'owner'});
  await db.doc(`businesses/${uid}`).set({ownerUid: uid, phoneNumber: phone, ...extra.business});
  if (extra.license) await db.doc(`businesses/${uid}/settings/license`).set(extra.license);
}

async function snapshot(id) {
  const out = {};
  for (const name of ['rooms', 'bookings', 'guests', 'bills', 'payments']) {
    const snap = await db.collection(`businesses/${id}/${name}`).get();
    out[name] = snap.docs
      .map((doc) => ({id: doc.id, data: doc.data()}))
      .sort((a, b) => a.id.localeCompare(b.id));
  }
  const biz = await db.doc(`businesses/${id}`).get();
  out.businessId = biz.id;
  out.ownerUid = biz.data().ownerUid;
  return out;
}

test('one annual PIN activates one hotel and a retry does not add another year', async () => {
  const suffix = Date.now();
  const a = `saleA${suffix}`;
  const b = `saleB${suffix}`;
  const now = Date.parse('2026-03-15T10:00:00.000Z');
  for (const uid of [a, b]) {
    await hotel(uid, uid, {license: {activated: false, trialStart: Timestamp.fromMillis(now - 86400000)}});
    await db.doc(`businesses/${uid}/rooms/room_101`).set({roomNumber: 101, status: 'BOOKED', deleted: false});
    await db.doc(`businesses/${uid}/guests/CUST-1`).set({customerId: 'CUST-1', idFrontStoragePath: 'businesses/x/id_front.jpg', deleted: false});
  }
  await db.doc(`licenseKeys/${pinKey(pin, secret)}`).set({status: 'issued', plan: 'annual', serial: 1});
  const beforeA = await snapshot(a);
  const beforeB = await snapshot(b);
  const results = await Promise.all([
    activateLicense(db, a, a, pin, secret, now),
    activateLicense(db, b, b, pin, secret, now),
  ]);
  assert.equal(results.filter((item) => item.activated).length, 1);
  const winner = results.find((item) => item.activated).businessId;
  const firstExpiry = (await db.doc(`businesses/${winner}/settings/license`).get()).data().expiresAt.toDate().toISOString();
  const again = await activateLicense(db, winner, winner, pin, secret, now + 60000);
  assert.equal(again.idempotent, true);
  assert.equal(again.expiresAt, firstExpiry);
  assert.equal((await db.doc(`businesses/${winner}/settings/license`).get()).data().issuer, ISSUER);
  const before = winner === a ? beforeA : beforeB;
  assert.deepEqual(await snapshot(winner), before);
  const loser = winner === a ? b : a;
  assert.equal((await db.doc(`businesses/${loser}/settings/license`).get()).data().activated, false);
  const winnerSnap = await snapshot(winner);
  assert.equal(winnerSnap.rooms[0].data.status, 'BOOKED');
  assert.equal(winnerSnap.guests[0].data.idFrontStoragePath, 'businesses/x/id_front.jpg');
  assert.equal(winnerSnap.ownerUid, winner);
});

test('active license extends from expiresAt and 29 February rolls to 28 February', async () => {
  const uid = `renew${Date.now()}`;
  const code = '24681357';
  const current = Timestamp.fromDate(new Date(Date.UTC(2028, 1, 29, 8, 30, 0)));
  await hotel(uid, uid, {license: {activated: true, expiresAt: current, issuer: ISSUER, plan: 'annual'}});
  await db.doc(`businesses/${uid}/rooms/room_102`).set({roomNumber: 102, status: 'BOOKED', deleted: false, normalRent: 2000});
  await db.doc(`businesses/${uid}/bookings/bkg_room_102`).set({bookingId: 'bkg_room_102', deleted: false});
  await db.doc(`businesses/${uid}/guests/CUST-9`).set({customerId: 'CUST-9', idFrontStoragePath: 'kept/front.jpg', idBackStoragePath: 'kept/back.jpg', deleted: false});
  await db.doc(`businesses/${uid}/payments/pay_1`).set({paymentId: 'pay_1', deleted: false});
  await db.doc(`licenseKeys/${pinKey(code, secret)}`).set({status: 'issued', plan: 'annual', serial: 2});
  const before = JSON.stringify(await snapshot(uid));
  const now = Date.parse('2026-01-01T00:00:00.000Z');
  const result = await activateLicense(db, uid, uid, code, secret, now);
  assert.equal(result.expiresAt, addOneCalendarYear(current.toDate()).toISOString());
  assert.equal(result.expiresAt, '2029-02-28T08:30:00.000Z');
  assert.equal(JSON.stringify(await snapshot(uid)), before);
  assert.equal((await db.doc(`businesses/${uid}`).get()).id, uid);
});

test('expired license and in-trial first PIN both start one year from redemption time', async () => {
  const now = Date.parse('2026-06-01T12:00:00.000Z');
  const expired = `expired${now}`;
  const trial = `trial${now}`;
  await hotel(expired, expired, {license: {activated: true, expiresAt: Timestamp.fromMillis(now - 1000), plan: 'annual'}});
  await hotel(trial, trial, {license: {activated: false, trialStart: Timestamp.fromMillis(now - 86400000), trialEndsAt: Timestamp.fromMillis(now + 5 * 86400000)}});
  for (const [uid, code] of [[expired, '11112222'], [trial, '33334444']]) {
    await db.doc(`licenseKeys/${pinKey(code, secret)}`).set({status: 'issued', plan: 'annual', serial: 3});
    const result = await activateLicense(db, uid, uid, code, secret, now);
    assert.equal(result.expiresAt, addOneCalendarYear(new Date(now)).toISOString());
    assert.equal((await db.doc(`businesses/${uid}/settings/license`).get()).data().trialStart == null, uid === expired);
  }
});

test('missing license can be activated without inventing a trial', async () => {
  const uid = `missing${Date.now()}`;
  const code = '55556666';
  const now = Date.parse('2026-04-02T00:00:00.000Z');
  await hotel(uid, uid);
  await db.doc(`businesses/${uid}/rooms/room_102`).set({roomNumber: 102, deleted: true, status: 'BOOKED'});
  const before = await snapshot(uid);
  await db.doc(`licenseKeys/${pinKey(code, secret)}`).set({status: 'issued', plan: 'annual', serial: 4});
  const result = await activateLicense(db, uid, uid, code, secret, now);
  assert.equal(result.expiresAt, '2027-04-02T00:00:00.000Z');
  const license = (await db.doc(`businesses/${uid}/settings/license`).get()).data();
  assert.equal(license.trialStart, undefined);
  assert.equal(license.activated, true);
  const after = await snapshot(uid);
  assert.deepEqual(after.rooms, before.rooms);
  assert.equal(after.rooms[0].data.deleted, true);
});

test('bad PIN attempts lock and do not consume a later valid PIN during the lock', async () => {
  const uid = `limited${Date.now()}`;
  const good = '88889999';
  const now = Date.parse('2026-05-01T00:00:00.000Z');
  await hotel(uid, uid);
  await db.doc(`licenseKeys/${pinKey(good, secret)}`).set({status: 'issued', plan: 'annual', serial: 5});
  await assert.rejects(activateLicense(db, uid, 'foreign-phone', good, secret, now));
  for (let i = 0; i < 5; i += 1) {
    assert.equal((await activateLicense(db, uid, uid, '87654321', secret, now + i)).error, 'invalid-pin');
  }
  assert.equal((await activateLicense(db, uid, uid, good, secret, now + 10)).error, 'rate-limited');
  assert.equal((await db.doc(`licenseKeys/${pinKey(good, secret)}`).get()).data().status, 'issued');
  const afterLock = await activateLicense(db, uid, uid, good, secret, now + 15 * 60 * 1000 + 10);
  assert.equal(afterLock.activated, true);
});

test('another verified owner cannot claim a reserved or redeemed PIN', async () => {
  const uid = `reserved${Date.now()}`;
  const other = `buyer${Date.now()}`;
  const code = '13572468';
  await hotel(uid, uid);
  await db.doc(`licenseKeys/${pinKey(code, secret)}`).set({status: 'issued', plan: 'annual', reservedOwnerUid: other, serial: 6});
  assert.equal((await activateLicense(db, uid, uid, code, secret)).error, 'invalid-pin');
  assert.equal((await db.doc(`licenseKeys/${pinKey(code, secret)}`).get()).data().status, 'issued');
});

test('100 annual PINs issue once and one redemption is recorded without printing the PIN', async () => {
  const rows = await issueAnnualPins(db, secret, 100);
  assert.equal(rows.length, 100);
  assert.equal(new Set(rows.map((row) => row.pin)).size, 100);
  assert.equal(rows.every((row) => row.status === 'issued' && row.pin.length === 8), true);
  const issued = await db.collection('licenseKeys').where('plan', '==', 'annual').where('status', '==', 'issued').get();
  assert.equal(issued.size >= 100, true);
  const csvPath = join(tmpdir(), `hotelpro-test-pins-${Date.now()}.csv`);
  writeFileSync(csvPath, csvFromRows(rows), {mode: 0o600});
  const csv = readFileSync(csvPath, 'utf8');
  assert.equal(csv.startsWith('Serial,PIN,Status,Assigned businessId,Redeemed at\n'), true);
  assert.equal(csv.trim().split('\n').length, 101);
  rmSync(csvPath);
  const sample = rows[0];
  const uid = `batch${Date.now()}`;
  await hotel(uid, uid, {business: {businessName: 'Kept'}});
  await db.doc(`businesses/${uid}/rooms/room_101`).set({roomNumber: 101, normalRent: 1500, deleted: false});
  const before = JSON.stringify(await snapshot(uid));
  const result = await activateLicense(db, uid, uid, sample.pin, secret, Date.parse('2026-08-01T00:00:00.000Z'));
  assert.equal(result.activated, true);
  assert.equal(result.businessId, uid);
  assert.equal(JSON.stringify(await snapshot(uid)), before);
  const key = (await db.doc(`licenseKeys/${pinKey(sample.pin, secret)}`).get()).data();
  assert.equal(key.status, 'redeemed');
  assert.equal(key.businessId, uid);
});
