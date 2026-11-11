const {test, after} = require('node:test');
const assert = require('node:assert/strict');
const {initializeApp, deleteApp} = require('firebase-admin/app');
const {getFirestore} = require('firebase-admin/firestore');
const {claimHotelByPhone} = require('./phone_claim');

if (process.env.FIRESTORE_EMULATOR_HOST !== '127.0.0.1:18080') throw Error('Local emulator only');
const app = initializeApp({projectId: 'demo-hotel-pro-sync'}, 'phone-claim-tests');
const db = getFirestore(app);
after(() => deleteApp(app));

let seq = 0;
function phone() {
  return `+9197${String(Date.now()).slice(-6)}${String(seq++ % 100).padStart(2, '0')}`;
}
async function emailHotel(phoneNumber, ownerUid = `email${Date.now()}${seq++}`) {
  const businessId = `biz_${ownerUid}`;
  await db.doc(`users/${ownerUid}`).set({businessId, phoneNumber, email: `${ownerUid}@example.test`, ownerName: 'Asha', role: 'owner'});
  await db.doc(`businesses/${businessId}`).set({ownerUid, phoneNumber, businessName: 'Old Hotel'});
  return {ownerUid, businessId};
}
const emailOnly = async () => ({uid: 'x', email: 'a@example.test'});

test('an email-era hotel moves to the verified mobile login', async () => {
  const p = phone();
  const {ownerUid, businessId} = await emailHotel(p);
  const uid = `phone${Date.now()}`;
  const result = await claimHotelByPhone(db, uid, p, emailOnly);
  assert.deepEqual(result, {claimed: true, businessId});
  assert.equal((await db.doc(`businesses/${businessId}`).get()).data().ownerUid, uid);
  const user = (await db.doc(`users/${uid}`).get()).data();
  assert.equal(user.businessId, businessId);
  assert.equal(user.phoneNumber, p);
  assert.equal(user.ownerName, 'Asha');
  assert.equal((await db.doc(`phoneIndex/${p.slice(1)}`).get()).data().ownerUid, uid);
  assert.equal((await db.doc(`users/${ownerUid}`).get()).data().migratedToUid, uid);
  const again = await claimHotelByPhone(db, uid, p, emailOnly);
  assert.equal(again.claimed, false);
  assert.equal(again.reason, 'already-mapped');
});

test('a hotel whose owner already logs in by mobile is never moved', async () => {
  const p = phone();
  const {businessId, ownerUid} = await emailHotel(p);
  const result = await claimHotelByPhone(db, `other${Date.now()}`, p, async () => ({uid: ownerUid, phoneNumber: p}));
  assert.equal(result.claimed, false);
  assert.equal(result.reason, 'owner-has-phone-login');
  assert.equal((await db.doc(`businesses/${businessId}`).get()).data().ownerUid, ownerUid);
});

test('two hotels with the same mobile are ambiguous and stay unchanged', async () => {
  const p = phone();
  const first = await emailHotel(p);
  await emailHotel(p);
  const result = await claimHotelByPhone(db, `amb${Date.now()}`, p, emailOnly);
  assert.equal(result.reason, 'ambiguous');
  assert.equal((await db.doc(`businesses/${first.businessId}`).get()).data().ownerUid, first.ownerUid);
});

test('no matching hotel or no verified phone claims nothing', async () => {
  assert.equal((await claimHotelByPhone(db, `none${Date.now()}`, '+919000000001', emailOnly)).reason, 'no-match');
  assert.equal((await claimHotelByPhone(db, 'u1', '', emailOnly)).reason, 'phone-login-required');
});
