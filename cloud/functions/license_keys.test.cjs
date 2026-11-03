const {test,after}=require('node:test');
const assert=require('node:assert/strict');
const {initializeApp,deleteApp}=require('firebase-admin/app');
const {getFirestore,Timestamp}=require('firebase-admin/firestore');
const {addCalendarMonths}=require('./calendar');
const {issueKey,redeemKey,revokeKey,listKeys}=require('./license_keys');
const {analytics}=require('./admin_data');
if(process.env.FIRESTORE_EMULATOR_HOST!=='127.0.0.1:18080')throw Error('Emulator only');
const app=initializeApp({projectId:'demo-hotel-pro-sync'},'new-key-tests'),db=getFirestore(app);
after(()=>deleteApp(app));
const secret='only-emulator-test-secret',admin={uid:'key-admin',admin:true};
let seq=0;
async function owner(){const uid=`key-owner-${Date.now()}-${++seq}`,email=`${uid}@example.test`;
 await db.doc(`users/${uid}`).set({businessId:uid,email});
 await db.doc(`businesses/${uid}`).set({ownerUid:uid,enabled:true,businessName:'Test'});
 await db.doc(`businesses/${uid}/settings/license`).set({activated:false,trialStart:Timestamp.fromMillis(0)});
 return {uid,email};}
const input=(extra={})=>({duration:3,unit:'months',requestId:`test-request-${Date.now()}-${++seq}`, ...extra});
test('calendar months clamp month ends and leap years',()=>{
 assert.equal(addCalendarMonths(new Date('2024-01-31T12:34:56Z'),1).toISOString(),'2024-02-29T12:34:56.000Z');
 assert.equal(addCalendarMonths(new Date('2024-02-29T12:34:56Z'),12).toISOString(),'2025-02-28T12:34:56.000Z');
 assert.throws(()=>addCalendarMonths(new Date(),0),/INVALID_DURATION/);
});
test('only admins issue keys, with valid duration and idempotent request',async()=>{
 await assert.rejects(issueKey(db,{uid:'owner'},input(),secret),/ADMIN_REQUIRED/);
 await assert.rejects(issueKey(db,admin,input({duration:0}),secret),/INVALID_DURATION/);
 await assert.rejects(issueKey(db,admin,input({duration:101,unit:'years'}),secret),/INVALID_DURATION/);
 const i=input(),a=await issueKey(db,admin,i,secret),b=await issueKey(db,admin,i,secret);
 assert.equal(a.key,b.key);assert.match(a.key,/^HP-(?:[A-F0-9]{4}-){7}[A-F0-9]{4}$/);
 await assert.rejects(issueKey(db,admin,{...i,duration:4},secret),/REQUEST_REUSED/);
 const stored=(await db.doc(`licenseKeys/${a.keyId}`).get()).data();
 assert.equal(JSON.stringify(stored).includes(a.key),false);
});
test('hotel-bound monthly key extends existing membership and cannot be replayed or shared',async()=>{
 const a=await owner(),b=await owner(),now=Date.parse('2026-01-31T10:00:00Z');
 const key=await issueKey(db,admin,input({duration:1,hotelId:a.uid}),secret);
 assert.equal((await redeemKey(db,b.uid,b.email,key.key,secret,now)).error,'invalid-key');
 const first=await redeemKey(db,a.uid,a.email,key.key,secret,now);
 assert.equal(first.expiresAt,'2026-02-28T10:00:00.000Z');
 const renew=await issueKey(db,admin,input({duration:2,unit:'years',hotelId:a.uid}),secret);
 const renewal=await redeemKey(db,a.uid,a.email,renew.key,secret,now+1000);
 assert.equal(renewal.expiresAt,'2028-02-28T10:00:00.000Z');
 const again=await redeemKey(db,a.uid,a.email,key.key,secret,now+2000);
 assert.equal(again.idempotent,true);assert.equal(again.expiresAt,renewal.expiresAt);
 await assert.rejects(revokeKey(db,admin,key.keyId),/KEY_NOT_UNUSED/);
});
test('unused revocation and simultaneous redemption protect a key',async()=>{
 const a=await owner(),b=await owner();
 const revoked=await issueKey(db,admin,input(),secret);await revokeKey(db,admin,revoked.keyId);
 assert.equal((await redeemKey(db,a.uid,a.email,revoked.key,secret)).error,'invalid-key');
 const key=await issueKey(db,admin,input(),secret);
 const results=await Promise.all([redeemKey(db,a.uid,a.email,key.key,secret),redeemKey(db,b.uid,b.email,key.key,secret)]);
 assert.equal(results.filter(r=>r.activated).length,1);
 assert.equal(results.filter(r=>r.error==='invalid-key').length,1);
 const listed=await listKeys(db,admin,{limit:100});
 assert.ok(listed.items.some(k=>k.keyId===key.keyId&&k.status==='redeemed'));
 assert.equal(JSON.stringify(listed).includes(key.key),false);
});
test('early activation retains unused trial time',async()=>{
 const o=await owner(),now=Date.parse('2026-06-01T00:00:00Z');
 await db.doc(`businesses/${o.uid}/settings/license`).set({trialStart:Timestamp.fromMillis(now),activated:false});
 const key=await issueKey(db,admin,input({duration:1,hotelId:o.uid}),secret);
 assert.equal((await redeemKey(db,o.uid,o.email,key.key,secret,now)).expiresAt,'2026-07-11T00:00:00.000Z');
});
test('analytics sums completed bills once and excludes tombstones and out-of-range records',()=>{
 const result=analytics([{totalBill:1000,checkoutTime:'2026-01-02',stayDurationMinutes:120},
 {totalBill:500,checkoutTime:'2026-01-03',deleted:true},{totalBill:999,checkoutTime:'2025-01-01'}],
 [{amount:200,dateTime:'2026-01-05'}],Date.parse('2026-01-01'),Date.parse('2026-02-01'));
 assert.equal(result.billed,1000);assert.equal(result.expenses,200);assert.equal(result.net,800);assert.equal(result.completedStays,1);
 assert.equal(result.stayMinutes,120);
});
