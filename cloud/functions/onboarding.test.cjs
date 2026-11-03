const {test, after} = require('node:test');
const assert = require('node:assert/strict');
const {initializeApp, deleteApp} = require('firebase-admin/app');
const {getFirestore, Timestamp} = require('firebase-admin/firestore');
const {provisionHotel, DEFAULT_ROOM_NUMBERS} = require('./onboarding');

if (process.env.FIRESTORE_EMULATOR_HOST !== '127.0.0.1:18080') throw Error('Local emulator only');
const app = initializeApp({projectId: 'demo-hotel-pro-sync'}, 'onboarding-tests');
const db = getFirestore(app);
after(() => deleteApp(app));

async function identity(uid, phone, business) {
  await db.doc(`users/${uid}`).set({businessId: uid, phoneNumber: phone, role: 'owner'});
  await db.doc(`businesses/${uid}`).set({ownerUid: uid, phoneNumber: phone, ...business});
}

test('a new owner gets exactly twelve standard rooms and one server trial', async () => {
  const uid = `new${Date.now()}`;
  const now = Date.parse('2026-10-23T06:00:00.000Z');
  await identity(uid, uid, {onboardingStatus: 'pending', newOwnerSetup: true, createdAt: Timestamp.fromMillis(now)});
  const first = await provisionHotel(db, uid, uid, now);
  assert.equal(first.provisioned, true);
  assert.equal(first.roomsAdded, 12);
  const second = await provisionHotel(db, uid, uid, now + 86400000);
  assert.equal(second.reason, 'already-complete');
  assert.equal(second.roomsAdded, 0);
  const license = (await db.doc(`businesses/${uid}/settings/license`).get()).data();
  assert.equal(license.trialStart.toMillis(), now);
  assert.equal(license.trialEndsAt.toMillis(), now + 10 * 24 * 60 * 60 * 1000);
  assert.equal(license.activated, false);
  const rooms = await db.collection(`businesses/${uid}/rooms`).get();
  assert.equal(rooms.size, 12);
  assert.deepEqual(rooms.docs.map(doc => doc.data().roomNumber).sort((a,b)=>a-b), DEFAULT_ROOM_NUMBERS);
  for (const room of rooms.docs) {
    assert.equal(room.id, `room_${room.data().roomNumber}`);
    assert.equal(room.data().schemaVersion, 3);
    assert.equal(room.data().status, 'EMPTY');
    assert.equal(room.data().normalRent, 0);
    assert.equal(room.data().floorId, undefined);
  }

});

test('reinstall does not duplicate rooms or restart the trial', async () => {
  const uid = `reinstall${Date.now()}`;
  const now = Date.parse('2026-10-23T07:00:00.000Z');
  await identity(uid, uid, {onboardingStatus: 'pending', newOwnerSetup: true, createdAt: Timestamp.fromMillis(now)});
  await provisionHotel(db, uid, uid, now);
  await db.doc(`businesses/${uid}`).set({onboardingStatus: 'pending'}, {merge: true});
  await db.doc(`businesses/${uid}/settings/onboarding`).delete();
  const again = await provisionHotel(db, uid, uid, now + 1000);
  assert.equal(again.roomsAdded, 0);
  assert.equal((await db.collection(`businesses/${uid}/rooms`).get()).size, 12);
  assert.equal((await db.doc(`businesses/${uid}/settings/license`).get()).data().trialStart.toMillis(), now);
});

test('incomplete new account preserves existing rooms without seeding defaults', async () => {
  const uid = `partial${Date.now()}`;
  const now = Date.parse('2026-10-23T08:00:00.000Z');
  await identity(uid, uid, {createdAt: Timestamp.fromMillis(now), newOwnerSetup: true, onboardingStatus: 'pending'});
  await db.doc(`businesses/${uid}/rooms/room_108`).set({
    roomNumber: 108,
    roomType: 'Suite',
    normalRent: 9999,
    status: 'EMPTY',
    deleted: false,
  });
  await db.doc(`businesses/${uid}/rooms/room_101`).set({
    roomNumber: 101,
    roomType: 'Deluxe',
    normalRent: 1500,
    status: 'BOOKED',
    deleted: true,
  });
  const result = await provisionHotel(db, uid, uid, now);
  assert.equal(result.roomsAdded, 0);
  const kept = (await db.doc(`businesses/${uid}/rooms/room_108`).get()).data();
  assert.equal(kept.normalRent, 9999);
  const keptDeleted = (await db.doc(`businesses/${uid}/rooms/room_101`).get()).data();
  assert.equal(keptDeleted.deleted, true);
  assert.equal(keptDeleted.status, 'BOOKED');
  assert.equal((await db.collection(`businesses/${uid}/rooms`).get()).size, 2);
});

test('restored owner with missing license is not onboarded again', async () => {
  const uid = `old${Date.now()}`;
  const now = Date.parse('2026-10-23T09:00:00.000Z');
  await identity(uid, uid, {dataResetAt: Timestamp.fromMillis(Date.parse('2026-10-11T20:19:32.151Z'))});
  await db.doc(`businesses/${uid}/rooms/room_101`).set({roomNumber: 101, status: 'BOOKED', deleted: false, normalRent: 1500});
  await db.doc(`businesses/${uid}/bookings/bkg_room_101`).set({bookingId: 'bkg_room_101', deleted: false});
  await db.doc(`businesses/${uid}/guests/CUST-0001`).set({customerId: 'CUST-0001', idFrontStoragePath: 'kept/id_front.jpg', deleted: false});
  await db.doc(`businesses/${uid}/payments/pay_adv_room_102`).set({deleted: true});
  const before = (await db.collection(`businesses/${uid}/rooms`).get()).docs.map((doc) => doc.data());
  const result = await provisionHotel(db, uid, uid, now);
  assert.equal(result.reason, 'existing-hotel');
  assert.equal((await db.doc(`businesses/${uid}/settings/license`).get()).exists, false);
  assert.deepEqual((await db.collection(`businesses/${uid}/rooms`).get()).docs.map((doc) => doc.data()), before);
  assert.equal((await db.doc(`businesses/${uid}/guests/CUST-0001`).get()).data().idFrontStoragePath, 'kept/id_front.jpg');
  assert.equal((await db.doc(`businesses/${uid}/payments/pay_adv_room_102`).get()).data().deleted, true);
});

test('email owner initializes twelve rooms and foreign email is rejected', async () => {
  const uid = `email${Date.now()}`, email = 'owner@example.test';
  await identity(uid, '+919999999980', {onboardingStatus: 'pending', newOwnerSetup: true, createdAt: Timestamp.now()});
  await db.doc(`users/${uid}`).set({email}, {merge: true});
  await assert.rejects(provisionHotel(db, uid, 'other@example.test'), /Verified owner required/);
  const result = await provisionHotel(db, uid, email);
  assert.equal(result.provisioned, true);
  assert.equal(result.roomsAdded, 12);
  assert.equal((await db.collection(`businesses/${uid}/rooms`).get()).size, 12);
  assert.equal((await provisionHotel(db, uid, email)).provisioned, false);
});

test('two devices onboarding concurrently seed a single shared template', async () => {
  const uid=`concurrent${Date.now()}`;
  await identity(uid,uid,{onboardingStatus:'pending',newOwnerSetup:true,createdAt:Timestamp.now()});
  const results=await Promise.all([provisionHotel(db,uid,uid),provisionHotel(db,uid,uid)]);
  assert.equal(results.filter(result=>result.provisioned).length,1);
  assert.equal(results.reduce((sum,result)=>sum+result.roomsAdded,0),12);
  assert.equal((await db.collection(`businesses/${uid}/rooms`).get()).size,12);
});

test('returning login preserves edited and deleted default rooms', async () => {
  const uid=`edited${Date.now()}`;
  await identity(uid,uid,{onboardingStatus:'pending',newOwnerSetup:true,createdAt:Timestamp.now()});
  await provisionHotel(db,uid,uid);
  await db.doc(`businesses/${uid}/rooms/room_101`).update({normalRent:2300,status:'BOOKED',guestName:'Saved guest'});
  await db.doc(`businesses/${uid}/rooms/room_102`).update({deleted:true});
  assert.equal((await provisionHotel(db,uid,uid)).roomsAdded,0);
  const room=(await db.doc(`businesses/${uid}/rooms/room_101`).get()).data();
  assert.equal(room.normalRent,2300);assert.equal(room.status,'BOOKED');
  assert.equal((await db.doc(`businesses/${uid}/rooms/room_102`).get()).data().deleted,true);
});
