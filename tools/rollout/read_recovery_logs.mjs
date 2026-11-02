// Cloud Logging entries:list is a READ operation (HTTP POST query), not a deployment/write.
// Never prints raw logs or credentials. Filter restricted to this verified owner's business paths.
import fs from 'node:fs';
import path from 'node:path';
import {createRequire} from 'node:module';
const require=createRequire(import.meta.url);
const root=path.resolve(import.meta.dirname,'../..');
const dir=path.join(root,'.checkpoints/rollout-20261010',`recovery-logs-${Date.now()}`);
fs.mkdirSync(dir,{recursive:true,mode:0o700});
const project='yankees-hotel-pro';
const filter='resource.type="firestore_database" AND protoPayload.serviceName="firestore.googleapis.com" AND timestamp>="2026-09-16T00:00:00Z" AND timestamp<="2026-10-10T23:59:59Z" AND ("biz_xehC63jAFQWvlgKRwabV" OR "biz_Wu3CTkZ2KAAH4mijEqND")';
const summary={project,filter,productionWrites:false,checkedAt:new Date().toISOString()};
try {
  const auth=require('/opt/homebrew/Cellar/firebase-cli/15.30.1/libexec/lib/node_modules/firebase-tools/lib/auth.js');
  const account=auth.getProjectDefaultAccount(root);
  const token=(await auth.getAccessToken(account?.tokens.refresh_token,['https://www.googleapis.com/auth/cloud-platform'])).access_token;
  const entries=[];let nextPageToken;
  do {
    const r=await fetch('https://logging.googleapis.com/v2/entries:list',{method:'POST',headers:{Authorization:`Bearer ${token}`,'Content-Type':'application/json'},body:JSON.stringify({resourceNames:[`projects/${project}`],filter,pageSize:100,orderBy:'timestamp asc',...(nextPageToken?{pageToken:nextPageToken}:{})}),signal:AbortSignal.timeout(30000)});
    if(!r.ok) throw new Error(`HTTP ${r.status}`);
    const d=await r.json();entries.push(...(d.entries ?? []));nextPageToken=d.nextPageToken;
  } while(nextPageToken);
  fs.writeFileSync(path.join(dir,'entries.json'),JSON.stringify(entries,null,2),{mode:0o600});
  summary.access=true;summary.matchingEntries=entries.length;
  summary.events=entries.map(e=>({timestamp:e.timestamp,method:e.protoPayload?.methodName,principal:e.protoPayload?.authenticationInfo?.principalEmail,statusCode:e.protoPayload?.status?.code ?? 0}));
  summary.intentProven=false;
} catch(e) {summary.access=false;summary.error=/^HTTP \d+$/.test(e.message)?e.message:'Authentication/network/access unavailable';summary.intentProven=false;}
fs.writeFileSync(path.join(dir,'summary.json'),JSON.stringify(summary,null,2),{mode:0o600});
console.log(JSON.stringify({access:summary.access,matchingEntries:summary.matchingEntries,error:summary.error,intentProven:summary.intentProven,privateEvidence:dir}));
