// Seller-only preparation tool. Never execute without issuance approval.
// PIN and HMAC key come from private environment variables, never arguments/logs.
import {createRequire} from 'node:module';
const require=createRequire(import.meta.url);
const {pinKey}=require('./license.js');
const [project,ownerUid]=process.argv.slice(2);
if(project!=='yankees-hotel-pro'||!ownerUid||ownerUid.includes('/'))throw Error('Explicit production project and verified purchaser UID required');
const key=pinKey(process.env.HOTELPRO_ISSUE_PIN,process.env.HOTELPRO_PIN_HMAC_KEY);
const root=new URL('../../',import.meta.url).pathname;
const auth=require('/opt/homebrew/Cellar/firebase-cli/15.30.1/libexec/lib/node_modules/firebase-tools/lib/auth.js');
const account=auth.getProjectDefaultAccount(root);
const token=(await auth.getAccessToken(account?.tokens.refresh_token,['https://www.googleapis.com/auth/cloud-platform'])).access_token;
const base=`https://firestore.googleapis.com/v1/projects/${project}/databases/(default)/documents`;
const user=await fetch(`${base}/users/${ownerUid}`,{headers:{Authorization:`Bearer ${token}`}});
if(!user.ok)throw Error('Purchaser mapping unavailable');
const data=await user.json();if(data.fields?.role?.stringValue!=='owner')throw Error('Verified owner required');
const r=await fetch(`${base}/licenseKeys?documentId=${key}`,{method:'POST',headers:{Authorization:`Bearer ${token}`,'Content-Type':'application/json'},body:JSON.stringify({fields:{status:{stringValue:'issued'},reservedOwnerUid:{stringValue:ownerUid},createdAt:{timestampValue:new Date().toISOString()}}})});
if(!r.ok)throw Error(`Issuance stopped: HTTP ${r.status}; existing key never overwritten`);
console.log('One purchaser-bound license key issued. PIN not printed.');
