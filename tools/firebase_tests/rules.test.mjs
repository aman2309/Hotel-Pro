import {readFileSync} from 'node:fs';
import {before,after,test} from 'node:test';
import assert from 'node:assert/strict';
import {initializeTestEnvironment,assertFails,assertSucceeds} from '@firebase/rules-unit-testing';
import {doc,getDoc,setDoc,runTransaction,collection,query,where,getDocs,onSnapshot,Timestamp,deleteDoc,disableNetwork,enableNetwork,serverTimestamp} from 'firebase/firestore';
import {ref,uploadBytes,getBytes,deleteObject} from 'firebase/storage';
let env;
const phone='+919999999991', phoneB='+919999999992';
const pinHash='f203a2505f0425a5e37c72ae41f46deb85fa511f29553ee92256562543aa925a';
const owner=()=>env.authenticatedContext('ownerA',{phone_number:phone});
before(async()=>{
  env=await initializeTestEnvironment({projectId:'demo-hotel-pro-sync',
    firestore:{host:'127.0.0.1',port:18080,rules:readFileSync('../../firestore.rules','utf8')},
    storage:{host:'127.0.0.1',port:19199,rules:readFileSync('../../storage.rules','utf8')}});
  await env.withSecurityRulesDisabled(async c=>{
    for(const [uid,number,biz] of [['ownerA',phone,'old-hotel'],['ownerB',phoneB,'hotel-B']]){
      await setDoc(doc(c.firestore(),`businesses/${biz}`),{ownerUid:uid,phoneNumber:number,businessName:biz,createdAt:Timestamp.fromMillis(Date.now()-11*86400000)});
      await setDoc(doc(c.firestore(),`businesses/${biz}/settings/license`),{trialStart:Timestamp.now(),activated:false,pinHash:null});
      await setDoc(doc(c.firestore(),`users/${uid}`),{businessId:biz,role:'owner',phoneNumber:number});
      await setDoc(doc(c.firestore(),`phoneIndex/${number.slice(1)}`),{businessId:biz,ownerUid:uid,phoneNumber:number});
    }
    await setDoc(doc(c.firestore(),'businesses/old-hotel/rooms/room_101'),{schemaVersion:3,status:'EMPTY'});
  });
});
after(async()=>{await env?.cleanup();});
test('owner cannot forge or remove administrator reset approval',async()=>{
  const db=owner().firestore(),business=doc(db,'businesses/old-hotel');
  await assertFails(setDoc(business,{dataResetAt:Timestamp.fromMillis(Date.now()-11*86400000)},{merge:true}));
  await env.withSecurityRulesDisabled(async c=>{
    await setDoc(doc(c.firestore(),'businesses/old-hotel'),{dataResetAt:Timestamp.fromMillis(Date.now()-11*86400000)},{merge:true});
  });
  await assertFails(setDoc(business,{ownerUid:'ownerA',phoneNumber:phone,businessName:'forged reset'}));
  await assertSucceeds(setDoc(business,{businessName:'New hotel name'},{merge:true}));
});
test('same UID on two devices restores existing business mapping',async()=>{
  const a=owner().firestore(),b=owner().firestore();
  assert.equal((await getDoc(doc(a,'users/ownerA'))).data().businessId,'old-hotel');
  assert.equal((await getDoc(doc(b,'users/ownerA'))).data().businessId,'old-hotel');
  assert.equal((await getDoc(doc(b,'businesses/old-hotel/rooms/room_101'))).data().status,'EMPTY');
});
test('different owners/public cannot access or claim another hotel',async()=>{
  const b=env.authenticatedContext('ownerB',{phone_number:phoneB}).firestore();
  await assertFails(getDoc(doc(b,'businesses/old-hotel/rooms/room_101')));
  await assertFails(setDoc(doc(b,'businesses/old-hotel/bills/stolen'),{schemaVersion:3,amount:1}));
  await assertFails(setDoc(doc(b,'users/ownerB'),{businessId:'old-hotel',role:'owner',phoneNumber:phoneB}));
  await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(),'businesses/old-hotel/rooms/room_101')));
  const n=env.authenticatedContext('newOwner',{phone_number:'+919999999993'}).firestore();
  await assertFails(setDoc(doc(n,'users/newOwner'),{businessId:'old-hotel',role:'owner',phoneNumber:'+919999999993'}));
});
test('legacy owner lookup allowed, global listing and foreign phone index denied',async()=>{
  const db=owner().firestore();
  assert.equal((await getDocs(query(collection(db,'businesses'),where('ownerUid','==','ownerA')))).docs[0].id,'old-hotel');
  await assertFails(getDocs(collection(db,'businesses')));
  await assertFails(getDoc(doc(db,`phoneIndex/${phoneB.slice(1)}`)));
});
test('user/business/phone mapping created atomically, takeover denied',async()=>{
  const number='+919999999994',uid='newHotel',db=env.authenticatedContext(uid,{phone_number:number}).firestore();
  await assertSucceeds(runTransaction(db,async tx=>{
    const u=doc(db,`users/${uid}`),b=doc(db,'businesses/new-hotel'),p=doc(db,`phoneIndex/${number.slice(1)}`);
    await tx.get(u);await tx.get(b);await tx.get(p);
    tx.set(b,{ownerUid:uid,phoneNumber:number,businessName:'New',createdAt:serverTimestamp()});
    tx.set(u,{businessId:'new-hotel',role:'owner',phoneNumber:number});
    tx.set(p,{businessId:'new-hotel',ownerUid:uid,phoneNumber:number});
  }));
  await assertFails(setDoc(doc(db,'businesses/new-hotel'),{ownerUid:'ownerA',phoneNumber:number,businessName:'New'}));
});
test('listener on device B receives device A change',async()=>{
  const a=owner().firestore(),b=owner().firestore();let stop;
  const seen=new Promise((resolve,reject)=>{stop=onSnapshot(doc(b,'businesses/old-hotel/rooms/listener-room'),snap=>{if(snap.data()?.guestName==='Shared')resolve();},reject);});
  await setDoc(doc(a,'businesses/old-hotel/rooms/listener-room'),{schemaVersion:3,guestName:'Shared'});
  const timer=setTimeout(()=>{},10000);
  await seen;clearTimeout(timer);stop();
});
async function book(db,id){return runTransaction(db,async tx=>{
  const r=doc(db,'businesses/old-hotel/rooms/concurrent'),p=doc(db,`businesses/old-hotel/payments/${id}`);
  const room=await tx.get(r),payment=await tx.get(p);
  if(payment.exists())return;
  if(room.data()?.status!=='EMPTY')throw Error('conflict');
  tx.set(r,{schemaVersion:3,status:'BOOKED',operationId:id});
  tx.set(p,{schemaVersion:3,amount:500,operationId:id});
});}
test('concurrent booking/payment has one atomic winner and retry is idempotent',async()=>{
  const a=owner().firestore(),b=owner().firestore();
  await setDoc(doc(a,'businesses/old-hotel/rooms/concurrent'),{schemaVersion:3,status:'EMPTY'});
  const results=await Promise.allSettled([book(a,'attempt-A'),book(b,'attempt-B')]);
  assert.equal(results.filter(r=>r.status==='fulfilled').length,1);
  const payments=await getDocs(collection(a,'businesses/old-hotel/payments'));assert.equal(payments.size,1);
  await book(b,payments.docs[0].id);
  assert.equal((await getDocs(collection(a,'businesses/old-hotel/payments'))).size,1);
});
test('offline write stays pending, reconnect and payment retry commit once',async()=>{
  const db=owner().firestore();
  await setDoc(doc(db,'businesses/old-hotel/rooms/concurrent'),{schemaVersion:3,status:'EMPTY'});
  await disableNetwork(db);
  let settled=false;
  const pending=setDoc(doc(db,'businesses/old-hotel/rooms/offline-display'),{schemaVersion:3,status:'EMPTY'}).then(()=>{settled=true;});
  await new Promise(resolve=>setTimeout(resolve,50));assert.equal(settled,false);
  assert.equal((await getDoc(doc(owner().firestore(),'businesses/old-hotel/rooms/offline-display'))).exists(),false);
  await enableNetwork(db);await pending;
  await book(db,'offline-attempt');await book(db,'offline-attempt');
  assert.equal((await getDoc(doc(db,'businesses/old-hotel/payments/offline-attempt'))).data().amount,500);
});
test('reinstall restores trial/activation; trial reset, revoke and delete denied',async()=>{
  const db=owner().firestore(),license=doc(db,'businesses/old-hotel/settings/license');
  const business=(await getDoc(doc(db,'businesses/old-hotel'))).data();
  const start=business.dataResetAt??business.createdAt;
  await env.withSecurityRulesDisabled(async c=>{await deleteDoc(doc(c.firestore(),'businesses/old-hotel/settings/license'));});
  await assertFails(setDoc(license,{trialStart:Timestamp.now(),activated:false,pinHash:null}));
  await assertSucceeds(setDoc(license,{trialStart:start,activated:false,pinHash:null}));
  await assertFails(setDoc(license,{activated:true,pinHash},{merge:true}));
  await env.withSecurityRulesDisabled(async c=>{await setDoc(doc(c.firestore(),'businesses/old-hotel/settings/license'),{activated:true,pinHash},{merge:true});});
  const data=(await getDoc(doc(owner().firestore(),'businesses/old-hotel/settings/license'))).data();
  assert.equal(data.activated,true);assert.equal(data.trialStart.toMillis(),start.toMillis());
  await assertFails(setDoc(license,{trialStart:Timestamp.now()},{merge:true}));
  await assertFails(setDoc(license,{activated:false},{merge:true}));await assertFails(deleteDoc(license));
});
test('ID photo restores on fresh device; public/foreign access and deletion denied',async()=>{
  const path=`businesses/old-hotel/guests/CUST-0001/versions/${'a'.repeat(64)}/id_front.jpg`;
  const a=owner().storage(),fresh=owner().storage(),bytes=Uint8Array.from([255,216,255,217]);
  await assertSucceeds(uploadBytes(ref(a,path),bytes,{contentType:'image/jpeg'}));
  assert.deepEqual(new Uint8Array(await getBytes(ref(fresh,path))),bytes);
  await assertFails(getBytes(ref(env.authenticatedContext('ownerB',{phone_number:phoneB}).storage(),path)));
  await assertFails(getBytes(ref(env.unauthenticatedContext().storage(),path)));
  await assertFails(deleteObject(ref(a,path)));
  await assertFails(uploadBytes(ref(a,path.replace('id_front','invalid')),bytes,{contentType:'image/jpeg'}));
});

test('older snapshot writers and physical financial deletes are rejected',async()=>{
  const db=owner().firestore();
  await assertFails(setDoc(doc(db,'businesses/old-hotel/rooms/room_101'),{schemaVersion:2,status:'EMPTY'}));
  await assertFails(deleteDoc(doc(db,'businesses/old-hotel/payments/offline-attempt')));
});

test('expired trial preserves reads but blocks hotel writes until server activation',async()=>{
  await env.withSecurityRulesDisabled(async c=>{
    await setDoc(doc(c.firestore(),'businesses/expired-hotel'),{ownerUid:'expired-owner'});
    await setDoc(doc(c.firestore(),'businesses/expired-hotel/settings/license'),{trialStart:Timestamp.fromMillis(Date.now()-11*86400000),activated:false});
  });
  const db=env.authenticatedContext('expired-owner',{phone_number:'+919999999993'}).firestore();
  const room=doc(db,'businesses/expired-hotel/rooms/room_101');
  await assertSucceeds(getDoc(room));
  await assertFails(setDoc(room,{schemaVersion:3,status:'EMPTY'}));
  const storage=env.authenticatedContext('expired-owner',{phone_number:'+919999999993'}).storage();
  const photo=ref(storage,`businesses/expired-hotel/guests/test/versions/${'e'.repeat(64)}/id_front.jpg`);
  await assertFails(uploadBytes(photo,new Uint8Array([255,216,255,217]),{contentType:'image/jpeg'}));
  await env.withSecurityRulesDisabled(async c=>{await setDoc(doc(c.firestore(),'businesses/expired-hotel/settings/license'),{activated:true},{merge:true});});
  await assertSucceeds(setDoc(room,{schemaVersion:3,status:'EMPTY'}));
  await assertSucceeds(uploadBytes(photo,new Uint8Array([255,216,255,217]),{contentType:'image/jpeg'}));
});
