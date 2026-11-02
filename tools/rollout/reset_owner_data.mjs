// Explicitly authorized hotel-data reset. Fixed owner; no rules/Auth deletion.
// --prepare produces a private, generation/version-checked recovery checkpoint.
// --execute <checkpoint> deletes only the previously backed-up hotel contents.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {createRequire} from 'node:module';
const require=createRequire(import.meta.url);
const project='yankees-hotel-pro',bucket=`${project}.firebasestorage.app`;
const uid='P0HqzHUpMUdwUJMjnWOPirunAvV2',phone='+919893281818';
const ids=['biz_xehC63jAFQWvlgKRwabV','biz_Wu3CTkZ2KAAH4mijEqND'];
const root=path.resolve(import.meta.dirname,'../..');
const base=`https://firestore.googleapis.com/v1/projects/${project}/databases/(default)/documents`;
const prefix=`projects/${project}/databases/(default)/documents/`;
const args=process.argv.slice(2);
if(!(args.length===1&&args[0]==='--prepare')&&!(args.length===2&&args[0]==='--execute'))throw Error('Use --prepare or --execute checkpoint');
let token;
const sha=b=>crypto.createHash('sha256').update(b).digest('hex');
const save=(folder,name,data)=>fs.writeFileSync(path.join(folder,name),JSON.stringify(data,null,2),{mode:0o600});
async function req(url,{method='GET',body,bytes=false}={}){
 const r=await fetch(url,{method,headers:{Authorization:`Bearer ${token}`,...(body?{'Content-Type':'application/json'}:{})},...(body?{body:JSON.stringify(body)}:{}),signal:AbortSignal.timeout(45000)});
 if(!r.ok)throw Error(`HTTP ${r.status} (${method})`);
 if(r.status===204)return null;
 return bytes?Buffer.from(await r.arrayBuffer()):r.json();
}
async function list(url,field){let out=[],page;do{const u=new URL(url);u.searchParams.set('pageSize','100');if(page)u.searchParams.set('pageToken',page);const d=await req(u);out.push(...(d[field]??[]));page=d.nextPageToken;}while(page);return out;}
async function identity(){
 const user=await req(`${base}/users/${uid}`),index=await req(`${base}/phoneIndex/${phone.slice(1)}`);
 if(user.fields?.businessId?.stringValue!==ids[0]||user.fields?.phoneNumber?.stringValue!==phone||index.fields?.ownerUid?.stringValue!==uid||index.fields?.businessId?.stringValue!==ids[0])throw Error('Owner mapping changed; stopped');
 const roots=[];for(const id of ids){const d=await req(`${base}/businesses/${id}`);if(d.fields?.ownerUid?.stringValue!==uid)throw Error('Foreign business; stopped');roots.push(d);}
 return {user,index,roots};
}
async function descendants(parent){
 let collections=[],page;do{const d=await req(`${base}/${parent}:listCollectionIds`,{method:'POST',body:{pageSize:100,...(page?{pageToken:page}:{})}});collections.push(...(d.collectionIds??[]));page=d.nextPageToken;}while(page);
 const out=[];
 for(const col of collections){const docs=await list(`${base}/${parent}/${encodeURIComponent(col)}?showMissing=true`,'documents');for(const d of docs){if(d.fields&&d.updateTime)out.push(d);out.push(...await descendants(d.name.slice(prefix.length)));}}
 return out;
}
async function objects(id){let out=[],page;do{const u=new URL(`https://storage.googleapis.com/storage/v1/b/${bucket}/o`);u.searchParams.set('prefix',`businesses/${id}/`);u.searchParams.set('maxResults','100');if(page)u.searchParams.set('pageToken',page);const d=await req(u);out.push(...(d.items??[]));page=d.nextPageToken;}while(page);return out;}
function assertScope(d){if(!ids.some(id=>d.name.startsWith(`${prefix}businesses/${id}/`)))throw Error('Out-of-scope document');}
try{
 const auth=require('/opt/homebrew/Cellar/firebase-cli/15.30.1/libexec/lib/node_modules/firebase-tools/lib/auth.js');
 const a=auth.getProjectDefaultAccount(root);token=(await auth.getAccessToken(a?.tokens.refresh_token,['https://www.googleapis.com/auth/cloud-platform','https://www.googleapis.com/auth/firebase'])).access_token;
 if(!token)throw Error('Authentication unavailable');
 const current=await identity();
 if(args[0]==='--prepare'){
  const folder=path.join(root,'.checkpoints',`owner-reset-${Date.now()}`);fs.mkdirSync(folder,{recursive:true,mode:0o700});
  const docs=[],photos=[];
  for(const id of ids){docs.push(...await descendants(`businesses/${id}`));for(const o of await objects(id)){
   const b=await req(`https://storage.googleapis.com/storage/v1/b/${bucket}/o/${encodeURIComponent(o.name)}?alt=media&generation=${o.generation}`,{bytes:true});
   if(b.length!==Number(o.size))throw Error('Photo backup length mismatch');const hash=sha(b),file=`photo-${hash}.bin`;fs.writeFileSync(path.join(folder,file),b,{mode:0o600});photos.push({name:o.name,generation:o.generation,size:o.size,sha256:hash,file});
  }}
  docs.forEach(assertScope);save(folder,'identity.json',current);save(folder,'documents.json',docs);save(folder,'photos.json',photos);
  const plan={project,bucket,uid,ids,preparedAt:new Date().toISOString(),documentCount:docs.length,photoCount:photos.length,hashes:Object.fromEntries(['identity.json','documents.json','photos.json'].map(f=>[f,sha(fs.readFileSync(path.join(folder,f)))])),keepAuthAndOwnerMapping:true,phpAccessVerified:false};save(folder,'plan.json',plan);
  console.log(JSON.stringify({checkpoint:folder,documentCount:docs.length,photoCount:photos.length,productionWrites:false}));
 }else{
  const folder=path.resolve(args[1]);if(!folder.startsWith(path.join(root,'.checkpoints/owner-reset-')))throw Error('Invalid checkpoint location');
  const plan=JSON.parse(fs.readFileSync(path.join(folder,'plan.json')));if(plan.project!==project||plan.uid!==uid||JSON.stringify(plan.ids)!==JSON.stringify(ids))throw Error('Plan scope mismatch');
  for(const [f,h]of Object.entries(plan.hashes))if(sha(fs.readFileSync(path.join(folder,f)))!==h)throw Error('Backup checksum mismatch');
  const saved=JSON.parse(fs.readFileSync(path.join(folder,'identity.json'))),docs=JSON.parse(fs.readFileSync(path.join(folder,'documents.json'))),photos=JSON.parse(fs.readFileSync(path.join(folder,'photos.json')));
  docs.forEach(assertScope);if(docs.length+ids.length>450)throw Error('Too large for atomic reset; reviewed batch plan needed');
  for(const p of photos){if(!ids.some(id=>p.name.startsWith(`businesses/${id}/`))||sha(fs.readFileSync(path.join(folder,p.file)))!==p.sha256)throw Error('Photo scope/checksum mismatch');}
  const fresh=[];for(const id of ids)fresh.push(...await descendants(`businesses/${id}`));
  const fingerprint=a=>JSON.stringify(a.map(d=>[d.name,d.updateTime]).sort());if(fingerprint(fresh)!==fingerprint(docs))throw Error('Hotel changed after backup; prepare again');
  for(const d of current.roots)if(saved.roots.find(x=>x.name===d.name)?.updateTime!==d.updateTime)throw Error('Business identity changed after backup');
  const result={startedAt:new Date().toISOString(),deletedDocuments:0,deletedPhotos:0,phoneDataCleared:false,phpDeleted:false,authIdentityDeleted:false,rulesDeployed:false};
  save(folder,'result.json',result);
  try{
   // Atomic Firestore deletion; all versions must still match this backup.
   const writes=docs.map(d=>({delete:d.name,currentDocument:{updateTime:d.updateTime}}));
   // Retain only owner routing identity. Remove hotel names/settings on roots.
   for(const d of current.roots)writes.push({update:{name:d.name,fields:{ownerUid:{stringValue:uid},phoneNumber:{stringValue:phone},dataResetAt:{timestampValue:new Date().toISOString()}}},currentDocument:{updateTime:d.updateTime}});
   await req(`https://firestore.googleapis.com/v1/projects/${project}/databases/(default)/documents:commit`,{method:'POST',body:{writes}});result.deletedDocuments=docs.length;save(folder,'result.json',result);
   for(const p of photos){await req(`https://storage.googleapis.com/storage/v1/b/${bucket}/o/${encodeURIComponent(p.name)}?ifGenerationMatch=${p.generation}`,{method:'DELETE'});result.deletedPhotos++;save(folder,'result.json',result);}
   const leftovers=[];for(const id of ids){leftovers.push(...await descendants(`businesses/${id}`));if((await objects(id)).length)throw Error('Storage still has records');}
   if(leftovers.length)throw Error('Firestore still has records');
   result.verifiedEmptyCloudHotel=true;result.completedAt=new Date().toISOString();save(folder,'result.json',result);console.log(JSON.stringify(result));
  }catch(e){result.error=e.message;save(folder,'result.json',result);throw e;}
 }
}catch(e){console.error(JSON.stringify({stopped:true,error:e.message}));process.exitCode=1;}
