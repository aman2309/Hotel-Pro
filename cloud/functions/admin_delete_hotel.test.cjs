const {test, after} = require('node:test');
const assert = require('node:assert/strict');
const {initializeApp, deleteApp} = require('firebase-admin/app');
const {getFirestore} = require('firebase-admin/firestore');
const {deleteHotel} = require('./admin_delete_hotel');

if (process.env.FIRESTORE_EMULATOR_HOST !== '127.0.0.1:18080') throw Error('Local emulator only');
const app = initializeApp({projectId: 'demo-hotel-pro-sync'}, 'delete-hotel-tests');
const db = getFirestore(app);
after(() => deleteApp(app));
const admin = {uid: 'admin1', admin: true};

async function hotel(id) {
  const uid = `owner_${id}`;
  await db.doc(`businesses/${id}`).set({ownerUid: uid, businessName: 'Lake View', phoneNumber: '+919800000000'});
  await db.doc(`businesses/${id}/rooms/room_101`).set({roomNumber: 101});
  await db.doc(`businesses/${id}/bookings/b1`).set({room: 101});
  await db.doc(`businesses/${id}/settings/license`).set({activated: false});
  await db.doc(`users/${uid}`).set({businessId: id, role: 'owner'});
  await db.doc(`phoneIndex/91${id.length}${Date.now()}`).set({businessId: id, ownerUid: uid});
  return uid;
}

test('delete removes the hotel, its records, owner mapping and photos permanently', async () => {
  const id = `del${Date.now()}`;
  const uid = await hotel(id);
  const prefixes = [];
  const result = await deleteHotel(db, admin, {hotelId: id, confirmHotelId: id}, async p => prefixes.push(p));
  assert.deepEqual(result, {hotelId: id, deleted: true});
  assert.deepEqual(prefixes, [`businesses/${id}/`]);
  assert.equal((await db.doc(`businesses/${id}`).get()).exists, false);
  assert.equal((await db.collection(`businesses/${id}/rooms`).get()).size, 0);
  assert.equal((await db.collection(`businesses/${id}/settings`).get()).size, 0);
  assert.equal((await db.doc(`users/${uid}`).get()).exists, false);
  assert.equal((await db.collection('phoneIndex').where('businessId', '==', id).get()).size, 0);
  const audit = await db.collection('adminAuditLogs').where('hotelId', '==', id).get();
  assert.equal(audit.size, 1);
  assert.equal(audit.docs[0].get('action'), 'hotel-deleted');
});

test('a hotel left half-deleted by an earlier failure can be finished', async () => {
  const id = `half${Date.now()}`;
  await hotel(id);
  await assert.rejects(deleteHotel(db, admin, {hotelId: id, confirmHotelId: id}, async () => { throw Error('storage down'); }));
  const half = (await db.doc(`businesses/${id}`).get()).data();
  assert.equal(half.ownerUid, null);
  assert.equal(half.enabled, false);
  await deleteHotel(db, admin, {hotelId: id, confirmHotelId: id}, async () => {});
  assert.equal((await db.doc(`businesses/${id}`).get()).exists, false);
});

test('non-admins, mismatched confirmation and unknown hotels are refused', async () => {
  const id = `keep${Date.now()}`;
  await hotel(id);
  await assert.rejects(deleteHotel(db, {uid: 'x', admin: false}, {hotelId: id, confirmHotelId: id}, async () => {}));
  await assert.rejects(deleteHotel(db, admin, {hotelId: id, confirmHotelId: 'other'}, async () => {}));
  assert.equal((await db.doc(`businesses/${id}`).get()).exists, true);
  const missing = `missing${Date.now()}`;
  await assert.rejects(deleteHotel(db, admin, {hotelId: missing, confirmHotelId: missing}, async () => {}), /Hotel not found/);
});
