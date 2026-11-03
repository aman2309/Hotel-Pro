import {readFileSync} from 'node:fs';
import {before,after,test} from 'node:test';
import assert from 'node:assert/strict';
import {initializeTestEnvironment,assertFails,assertSucceeds} from '@firebase/rules-unit-testing';
import {doc,getDoc,getDocs,collection,setDoc,Timestamp,serverTimestamp,runTransaction} from 'firebase/firestore';
const projectId='demo-hotel-pro-sync';
let env;
before(async()=>{
  env=await initializeTestEnvironment({projectId,firestore:{host:'127.0.0.1',port:18080,rules:readFileSync('../../firestore.rules','utf8')}});
  await env.withSecurityRulesDisabled(async c=>{
    const db=c.firestore();
    await setDoc(doc(db,'businesses/cloud-test'),{ownerUid:'cloud-owner',phoneNumber:'+919999999990',businessName:'Cloud Test'});
    await setDoc(doc(db,'users/cloud-owner'),{businessId:'cloud-test',role:'owner',phoneNumber:'+919999999990'});
    await setDoc(doc(db,'businesses/cloud-test/settings/license'),{trialStart:Timestamp.now(),activated:false});
  });
});
after(async()=>{await env?.cleanup();});
const owner=()=>env.authenticatedContext('cloud-owner',{phone_number:'+919999999990'}).firestore();
test('new hotel has no floors or pre-created rooms',async()=>{
  for(const name of ['floors','rooms']) assert.equal((await getDocs(collection(owner(),`businesses/cloud-test/${name}`))).size,0);
});
test('same account on two devices reads the same room without creating a floor',async()=>{
  const a=owner(),b=owner();
  await assertSucceeds(setDoc(doc(a,'businesses/cloud-test/rooms/room_101'),{roomNumber:101,roomType:'Deluxe',normalRent:1000,status:'EMPTY',schemaVersion:3}));
  assert.equal((await getDoc(doc(b,'businesses/cloud-test/rooms/room_101'))).data().roomNumber,101);
  assert.equal((await getDocs(collection(b,'businesses/cloud-test/floors'))).size,0);
  await assertSucceeds(getDoc(doc(a,'businesses/cloud-test/rooms/room_101')));
});
test('different accounts/public cannot access floors or rooms',async()=>{
  for(const c of [env.authenticatedContext('other-owner',{phone_number:'+919999999989'}),env.unauthenticatedContext()]){
    await assertFails(getDocs(collection(c.firestore(),'businesses/cloud-test/floors')));
    await assertFails(setDoc(doc(c.firestore(),'businesses/cloud-test/floors/stolen'),{name:'Stolen',schemaVersion:3,deleted:false,createdAt:serverTimestamp()}));
    await assertFails(getDoc(doc(c.firestore(),'businesses/cloud-test/rooms/room_101')));
  }
});
test('floor creation is disabled and room writes need no floor',async()=>{
  const db=owner();
  await assertFails(setDoc(doc(db,'businesses/cloud-test/floors/new'),{name:'Ground',schemaVersion:3,deleted:false,createdAt:serverTimestamp()}));
  await assertSucceeds(setDoc(doc(db,'businesses/cloud-test/rooms/no-floor'),{schemaVersion:3,roomNumber:102}));
  await assertSucceeds(setDoc(doc(db,'businesses/cloud-test/rooms/empty-floor'),{schemaVersion:3,roomNumber:103,floorId:''}));
  await assertFails(setDoc(doc(db,'businesses/cloud-test/rooms/invalid-schema'),{schemaVersion:2}));
  await env.withSecurityRulesDisabled(async c=>{
    await setDoc(doc(c.firestore(),'businesses/cloud-test/rooms/legacy-floor'),{schemaVersion:3,floorId:'old-floor',status:'EMPTY'});
  });
  await assertSucceeds(setDoc(doc(db,'businesses/cloud-test/rooms/legacy-floor'),{status:'CLEANING'},{merge:true}));
});
test('stale second-device edits cannot replace the first booking',async()=>{
  const path='businesses/cloud-test/rooms/room_101';
  const commit=(db,next)=>runTransaction(db,async tx=>{
    const ref=doc(db,path),snapshot=await tx.get(ref);
    if(snapshot.data().status!=='EMPTY') throw Error('Room changed on another device');
    tx.update(ref,{status:next});
  });
  await commit(owner(),'BOOKED');
  await assert.rejects(commit(owner(),'CLOSED'),/another device/);
  assert.equal((await getDoc(doc(owner(),path))).data().status,'BOOKED');
});
test('OTP login on second device preserves first device token',async()=>{
  const host=process.env.FIREBASE_AUTH_EMULATOR_HOST;
  assert.ok(host?.startsWith('127.0.0.1:'),'Auth emulator required');
  const post=async(method,body)=>{
    const response=await fetch(`http://${host}/identitytoolkit.googleapis.com/v1/${method}?key=emulator-key`,{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify(body)});
    const json=await response.json();assert.equal(response.ok,true,JSON.stringify(json.error));return json;
  };
  const login=async()=>{
    const sent=await post('accounts:sendVerificationCode',{phoneNumber:'+919999999988',recaptchaToken:'emulator'});
    const list=await(await fetch(`http://${host}/emulator/v1/projects/${projectId}/verificationCodes`)).json();
    const code=list.verificationCodes.find(v=>v.sessionInfo===sent.sessionInfo);
    return post('accounts:signInWithPhoneNumber',{sessionInfo:sent.sessionInfo,code:code.code});
  };
  const first=await login(),second=await login();
  assert.equal(first.localId,second.localId);
  const retained=await post('accounts:lookup',{idToken:first.idToken});
  assert.equal(retained.users[0].localId,first.localId);
});

test('trusted admin claims can read shared hotels; profile fields cannot grant admin',async()=>{
  const admin=env.authenticatedContext('panel-admin',{admin:true}).firestore();
  await assertSucceeds(getDocs(collection(admin,'businesses')));
  await assertSucceeds(getDocs(collection(admin,'businesses/cloud-test/rooms')));
  await assertFails(setDoc(doc(admin,'adminAuditLogs/forged'),{action:'forged'}));
  await env.withSecurityRulesDisabled(async c=>{await setDoc(doc(c.firestore(),'users/not-admin'),{admin:true,role:'admin'});});
  await assertFails(getDocs(collection(env.authenticatedContext('not-admin').firestore(),'businesses')));
});
test('suspended hotels keep reads but cannot write operational data',async()=>{
  await env.withSecurityRulesDisabled(async c=>{await setDoc(doc(c.firestore(),'businesses/cloud-test'),{enabled:false},{merge:true});});
  await assertSucceeds(getDoc(doc(owner(),'businesses/cloud-test/rooms/room_101')));
  await assertFails(setDoc(doc(owner(),'businesses/cloud-test/expenses/blocked'),{schemaVersion:3,amount:100}));
});

test('password signup, explicit login and two devices preserve the same UID',async()=>{
  const host=process.env.FIREBASE_AUTH_EMULATOR_HOST;
  const post=async(method,body)=>{
    const response=await fetch(`http://${host}/identitytoolkit.googleapis.com/v1/${method}?key=emulator-key`,{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify(body)});
    return {ok:response.ok,...await response.json()};
  };
  const email=`owner-${Date.now()}@example.test`,password='HotelStrong123!';
  const signup=await post('accounts:signUp',{email,password,returnSecureToken:true});
  assert.equal(signup.ok,true);
  const a=await post('accounts:signInWithPassword',{email,password,returnSecureToken:true});
  const b=await post('accounts:signInWithPassword',{email,password,returnSecureToken:true});
  assert.equal(a.localId,signup.localId);assert.equal(b.localId,a.localId);
  const stillValid=await post('accounts:lookup',{idToken:a.idToken});
  assert.equal(stillValid.users[0].localId,a.localId);
  assert.equal((await post('accounts:signInWithPassword',{email,password:'WrongPassword',returnSecureToken:true})).ok,false);
  assert.equal((await post('accounts:signInWithPassword',{email:'unregistered@example.test',password,returnSecureToken:true})).ok,false);
});

test('email owner mapping is atomic and cannot claim a verified phone index or another hotel',async()=>{
  const uid='email-owner',email='owner@example.test';
  const db=env.authenticatedContext(uid,{email}).firestore();
  await assertSucceeds(runTransaction(db,async tx=>{
    tx.set(doc(db,`users/${uid}`),{businessId:'email-hotel',role:'owner',email,phoneNumber:'+919999999980'});
    tx.set(doc(db,'businesses/email-hotel'),{ownerUid:uid,businessName:'Email Hotel',phoneNumber:'+919999999980',createdAt:serverTimestamp()});
  }));
  await assertSucceeds(setDoc(doc(db,`users/${uid}`),{ownerName:'Owner'},{merge:true}));
  await assertSucceeds(setDoc(doc(db,'businesses/email-hotel'),{updatedAt:serverTimestamp()},{merge:true}));
  await assertFails(setDoc(doc(db,'phoneIndex/919999999980'),{businessId:'email-hotel',ownerUid:uid,phoneNumber:'+919999999980'}));
  await assertFails(setDoc(doc(db,`users/${uid}`),{businessId:'cloud-test'},{merge:true}));
  await assertFails(setDoc(doc(db,`users/${uid}`),{email:'victim@example.test'},{merge:true}));
});
