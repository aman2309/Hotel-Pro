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
