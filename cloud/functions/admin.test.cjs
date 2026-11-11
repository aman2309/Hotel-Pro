const {test,after} = require('node:test');
const assert = require('node:assert/strict');
const {initializeApp,deleteApp} = require('firebase-admin/app');
const {getFirestore} = require('firebase-admin/firestore');
const {listHotels,setHotelEnabled} = require('./admin');
if(process.env.FIRESTORE_EMULATOR_HOST !== '127.0.0.1:18080') throw Error('Local emulator only');
const app=initializeApp({projectId:'demo-hotel-pro-sync'},'admin-panel-tests'),db=getFirestore(app);
after(()=>deleteApp(app));
test('an ordinary owner cannot access admin endpoints or use a profile role',async()=>{
  await assert.rejects(listHotels(db,{uid:'owner',admin:false}),/ADMIN_REQUIRED/);
  await assert.rejects(setHotelEnabled(db,{uid:'owner',role:'admin'},'some-hotel',false),/ADMIN_REQUIRED/);
});
test('admin panel uses shared hotel data and records status changes atomically',async()=>{
  const id=`admin-test-${Date.now()}`,actor={uid:'trusted-admin',admin:true};
  await db.doc(`businesses/${id}`).set({ownerUid:'hotel-owner',businessName:'Shared hotel',phoneNumber:'+919999999980'});
  const result=await listHotels(db,actor,{limit:100});
  assert.equal(result.items.find(h=>h.hotelId===id).hotelName,'Shared hotel');
  await setHotelEnabled(db,actor,id,false);
  assert.equal((await db.doc(`businesses/${id}`).get()).data().enabled,false);
  const logs=await db.collection('adminAuditLogs').where('hotelId','==',id).get();
  assert.equal(logs.size,1);assert.equal(logs.docs[0].data().actorUid,actor.uid);
  await setHotelEnabled(db,actor,id,true);
  assert.equal((await db.doc(`businesses/${id}`).get()).data().enabled,true);
});

test('newest hotels page first and deletion is authorized, scoped and retryable', async () => {
  const {Timestamp} = require('firebase-admin/firestore');
  const {listHotels: listRecent} = require('./admin_data');
  const {deleteHotel} = require('./admin_delete_hotel');
  const actor = {uid: 'trusted-admin', admin: true};
  const old = db.doc('businesses/recent-test-old');
  const latest = db.doc('businesses/recent-test-new');
  await old.set({ownerUid: 'old-owner', createdAt: Timestamp.fromMillis(2000000000000)});
  await latest.set({ownerUid: 'new-owner', createdAt: Timestamp.fromMillis(2000000001000)});
  await latest.collection('rooms').doc('101').set({status: 'EMPTY'});
  await db.doc('users/new-owner').set({businessId: latest.id});
  const first = await listRecent(db, actor, {limit: 1});
  assert.equal(first.items[0].hotelId, latest.id);
  const next = await listRecent(db, actor, {limit: 1, after: first.nextCursor});
  assert.equal(next.items[0].hotelId, old.id);

  const request = {hotelId: latest.id, confirmHotelId: latest.id};
  const prefixes = [];
  const removePhotos = async prefix => { prefixes.push(prefix); };
  await assert.rejects(deleteHotel(db, {uid: 'new-owner'}, request, removePhotos), /ADMIN_REQUIRED/);
  await assert.rejects(deleteHotel(db, actor, {...request, confirmHotelId: old.id}, removePhotos), /Confirm/);
  await assert.rejects(deleteHotel(db, actor, request, async () => { throw Error('temporary failure'); }), /Retry deletion/);
  assert.equal((await latest.get()).get('ownerUid'), null);
  await assert.rejects(setHotelEnabled(db, actor, latest.id, true), /DELETION_IN_PROGRESS/);
  await deleteHotel(db, actor, request, removePhotos);
  await deleteHotel(db, actor, request, removePhotos);
  assert.deepEqual(prefixes, [`businesses/${latest.id}/`]);
  assert.equal((await latest.collection('rooms').get()).size, 0);
  assert.equal((await db.doc('users/new-owner').get()).exists, true);
  assert.equal((await listRecent(db, actor, {limit: 1})).items[0].hotelId, old.id);
});
