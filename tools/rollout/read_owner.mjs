// Owner-specific READ ONLY audit. No OTP, account creation, imports or deploys.
// Usage: node tools/rollout/read_owner.mjs --phone +<countrycode><number>
//    or: node tools/rollout/read_owner.mjs --uid <Firebase UID>
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {createRequire} from 'node:module';
const require = createRequire(import.meta.url);
const args = process.argv.slice(2);
if (args.length !== 2 || !['--phone', '--uid'].includes(args[0])) {
  console.error('Supply exactly --phone E.164 or --uid FirebaseUID; never infer an owner.');
  process.exit(2);
}
const project = 'yankees-hotel-pro';
const bucket = `${project}.firebasestorage.app`;
const root = path.resolve(import.meta.dirname, '../..');
const dir = path.join(root, '.checkpoints/rollout-20261010', `owner-${Date.now()}`);
fs.mkdirSync(dir, {recursive: true, mode: 0o700});
const save = (name, data) => fs.writeFileSync(path.join(dir, name), JSON.stringify(data, null, 2), {mode: 0o600});
function savePhoto(bytes) {
  const folder=path.join(dir,'photos');
  fs.mkdirSync(folder,{recursive:true,mode:0o700});
  const hash=crypto.createHash('sha256').update(bytes).digest('hex');
  fs.writeFileSync(path.join(folder,`${hash}.jpg`),bytes,{mode:0o600});
  return hash;
}
const report = {project, auditedAt: new Date().toISOString(), productionWrites: false, localAndPhpCompared: false};
let token;
function decode(v) {
  if (v == null) return null;
  if ('mapValue' in v) return Object.fromEntries(Object.entries(v.mapValue.fields ?? {}).map(([k,x]) => [k,decode(x)]));
  if ('arrayValue' in v) return (v.arrayValue.values ?? []).map(decode);
  return v.stringValue ?? v.booleanValue ?? (v.integerValue == null ? undefined : Number(v.integerValue)) ?? v.doubleValue ?? v.timestampValue ?? null;
}
const doc = d => ({id: d.name.split('/').at(-1), ...decode({mapValue: {fields:d.fields}}),
  _firestoreMeta:{createTime:d.createTime,updateTime:d.updateTime}});
async function request(url, bytes=false) {
  const r = await fetch(url, {headers:{Authorization:`Bearer ${token}`}, signal:AbortSignal.timeout(30000)});
  if (!r.ok) throw new Error(`HTTP ${r.status}`);
  return bytes ? Buffer.from(await r.arrayBuffer()) : r.json();
}
async function list(url, field, pageSizeKey='pageSize', pageKey='pageToken') {
  let results=[], page;
  do {
    const u = new URL(url); u.searchParams.set(pageSizeKey,'100');
    if (page) u.searchParams.set(pageKey,page);
    const d = await request(u); results.push(...(d[field] ?? [])); page=d.nextPageToken;
  } while(page);
  return results;
}
try {
  const auth = require('/opt/homebrew/Cellar/firebase-cli/15.30.1/libexec/lib/node_modules/firebase-tools/lib/auth.js');
  const account = auth.getProjectDefaultAccount(root);
  token = (await auth.getAccessToken(account?.tokens.refresh_token, ['https://www.googleapis.com/auth/cloud-platform','https://www.googleapis.com/auth/firebase'])).access_token;
  if (!token) throw new Error('Authentication unavailable');
  const base=`https://firestore.googleapis.com/v1/projects/${project}/databases/(default)/documents`;
  const users=(await list(`${base}/users`,'documents')).map(doc);
  const phones=(await list(`${base}/phoneIndex`,'documents')).map(doc);
  const businesses=(await list(`${base}/businesses`,'documents')).map(doc);
  const matches=users.filter(u => args[0]==='--uid' ? u.id===args[1] : u.phoneNumber===args[1]);
  report.matchingUserCount=matches.length;
  const authUsers=await list(`https://identitytoolkit.googleapis.com/v1/projects/${project}/accounts:batchGet`,'users','maxResults','nextPageToken');
  const authMatches=authUsers.filter(a => args[0]==='--uid' ? a.localId===args[1] : a.phoneNumber===args[1]);
  report.matchingAuthCount=authMatches.length;
  save('matching-mappings.json',matches);
  if(authMatches.length!==1) throw new Error('Owner identity is missing or ambiguous in Firebase Auth; no owner data queried');
  const a=authMatches[0];
  const user=users.find(u => u.id===a.localId);
  if(!user) throw new Error('Owner identity has no UID mapping; no owner data queried');
  const business=businesses.find(b => b.id===user.businessId);
  const phone=phones.find(p => p.id===(user.phoneNumber ?? '').replace(/^\+/,''));
  report.identity={uid:user.id,businessId:user.businessId,role:user.role,phoneIndexPresent:!!phone,
    userOwnerMatches:business?.ownerUid===user.id,
    phoneIndexMatches:!!phone && phone.businessId===user.businessId && phone.ownerUid===user.id && phone.phoneNumber===user.phoneNumber,
    ownedBusinessIds:businesses.filter(b => b.ownerUid===user.id).map(b => b.id)};
  save('identity.json',{user,business,phone});
    report.auth={recordPresent:!!a,phoneMatches:!!a && a.phoneNumber===user.phoneNumber,disabled:a?.disabled===true};
    save('auth-owner.json', a ? {uid:a.localId,phoneNumber:a.phoneNumber,disabled:a.disabled,createdAt:a.createdAt,lastLoginAt:a.lastLoginAt} : null);
  if(!report.identity.userOwnerMatches) throw new Error('User mapping targets a foreign/missing business; no hotel/photo reads performed');
  const collections=['rooms','bookings','guests','bills','payments','futureBookings','expenses','settings','closedRooms','extraCharges'];
  const data={};
  for (const name of collections) {
    data[name]=(await list(`${base}/businesses/${encodeURIComponent(user.businessId)}/${name}`,'documents')).map(doc);
  }
  save('hotel-documents.json',data);
  report.collections=Object.fromEntries(collections.map(name => [name,{total:data[name].length,active:data[name].filter(d=>d.deleted!==true).length}]));
  const license=data.settings.find(d=>d.id==='license');
  const licenseSource=fs.readFileSync(path.join(root,'lib/data/pin_hash_set.dart'),'utf8');
  const validPinHashes=new Set(licenseSource.match(/[a-f0-9]{64}/g) ?? []);
  report.license={present:!!license,trialStart:license?.trialStart ?? null,activated:license?.activated===true,
    activatedPinRecognized:license?.activated===true ? validPinHashes.has(license.pinHash) : null};
  report.migrationMarker=data.settings.find(d=>d.id==='sync')?.migrationInProgress===true;
  const refs=new Map();
  let photosFlaggedWithoutReference=0;
  function photoRefs(g, container=g) {
    for(const side of ['Front','Back']) {
      const meta=container[`id${side}PhotoPath`];
      const p=container[`id${side}StoragePath`] ?? (typeof meta==='object' ? meta?.storagePath : null);
      if(typeof p==='string' && p.length) refs.set(p,{sha256:container[`id${side}Sha256`] ?? meta?.sha256 ?? null,guest:g.id});
      else if(container[`has${side}Photo`]===true || meta?.hasPhoto===true) photosFlaggedWithoutReference++;
    }
    if(container===g) for(const extra of Object.values(g.additionalPhotos ?? {})) photoRefs(g,extra);
  }
  for(const g of data.guests.filter(g=>g.deleted!==true)) photoRefs(g);
  const checks=[];
  for(const [p,ref] of refs) {
    if(!p.startsWith(`businesses/${user.businessId}/guests/`)) {checks.push({path:p,error:'Foreign/invalid photo path'});continue;}
    try {
      const url=`https://storage.googleapis.com/storage/v1/b/${encodeURIComponent(bucket)}/o/${encodeURIComponent(p)}`;
      const m=await request(url);
      if(Number(m.size)>5*1024*1024) throw new Error('Photo exceeds supported size');
      const bytes=await request(`${url}?alt=media&generation=${encodeURIComponent(m.generation)}`,true);
      const hash=savePhoto(bytes);
      checks.push({path:p,size:bytes.length,contentType:m.contentType,generation:m.generation,downloadVerified:true,
        shaMatches:ref.sha256 ? hash===ref.sha256 : null,jpeg:bytes[0]===255 && bytes[1]===216});
    } catch(e) {checks.push({path:p,error:/^HTTP \d+$/.test(e.message)?e.message:'Photo read failed'});}
  }
  save('photo-checks.json',checks);
  report.photos={referenced:refs.size,flaggedWithoutReference:photosFlaggedWithoutReference,
    downloadVerified:checks.filter(c=>c.downloadVerified).length,failed:checks.filter(c=>c.error).length,shaMismatch:checks.filter(c=>c.shaMatches===false).length};
  try {
    const objects=await list(`https://storage.googleapis.com/storage/v1/b/${encodeURIComponent(bucket)}/o?prefix=${encodeURIComponent(`businesses/${user.businessId}/guests/`)}`,'items','maxResults');
    save('storage-object-inventory.json',objects.map(o=>({name:o.name,size:o.size,generation:o.generation,updated:o.updated,contentType:o.contentType})));
    report.photos.storedObjects=objects.length;
    report.photos.objectsNotReferenced=objects.filter(o=>!refs.has(o.name)).length;
    const unreferenced=[];
    for(const o of objects.filter(o=>!refs.has(o.name))) {
      try {
        if(Number(o.size)>5*1024*1024) throw new Error('Unsupported size');
        const bytes=await request(`https://storage.googleapis.com/storage/v1/b/${encodeURIComponent(bucket)}/o/${encodeURIComponent(o.name)}?alt=media&generation=${encodeURIComponent(o.generation)}`,true);
        unreferenced.push({name:o.name,size:bytes.length,jpeg:bytes[0]===255 && bytes[1]===216,sha256:savePhoto(bytes),generation:o.generation,downloadVerified:true,privateBytesBackup:true});
      } catch(e) {unreferenced.push({name:o.name,error:/^HTTP \d+$/.test(e.message)?e.message:'Read failed'});}
    }
    save('unreferenced-photo-checks.json',unreferenced);
    report.photos.unreferencedDownloadsVerified=unreferenced.filter(o=>o.downloadVerified).length;
  } catch(e) {report.photos.objectListingError=/^HTTP \d+$/.test(e.message)?e.message:'Storage listing unavailable';}
  report.otherOwnedBusinesses=[];
  for(const old of businesses.filter(b=>b.ownerUid===user.id && b.id!==user.businessId)) {
    const oldData={};
    const oldReport={businessId:old.id,collections:{}};
    for(const name of collections) {
      oldData[name]=(await list(`${base}/businesses/${encodeURIComponent(old.id)}/${name}`,'documents')).map(doc);
      oldReport.collections[name]={total:oldData[name].length,active:oldData[name].filter(d=>d.deleted!==true).length};
    }
    save(`legacy-${old.id}.json`,oldData);
    oldReport.licensePresent=oldData.settings.some(d=>d.id==='license');
    try {
      const oldObjects=await list(`https://storage.googleapis.com/storage/v1/b/${encodeURIComponent(bucket)}/o?prefix=${encodeURIComponent(`businesses/${old.id}/guests/`)}`,'items','maxResults');
      save(`legacy-storage-${old.id}.json`,oldObjects.map(o=>({name:o.name,size:o.size,generation:o.generation})));
      oldReport.storedPhotoObjects=oldObjects.length;
    } catch(e) {oldReport.storageError=/^HTTP \d+$/.test(e.message)?e.message:'Storage listing unavailable';}
    report.otherOwnedBusinesses.push(oldReport);
  }
  report.completeness='Cloud snapshot only. Requires both phone local exports and a READ ONLY PHP database export for completeness.';
} catch(e) {
  report.error=/^(HTTP \d+|Owner identity|User mapping)/.test(e.message)?e.message:'Authentication/network/access unavailable';
}
save('owner-audit-summary.json',report);
// No phone numbers, hashes, guest data or auth tokens printed.
console.log(JSON.stringify(report,null,2));
console.log(`Private audit: ${dir}`);
