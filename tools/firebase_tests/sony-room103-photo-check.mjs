// Read-only check of the isolated Sony test account; never targets production.
import {initializeTestEnvironment} from '@firebase/rules-unit-testing';
import {getDoc,getDocs,doc,collection} from 'firebase/firestore';
import {ref,getBytes} from 'firebase/storage';
import {createHash} from 'node:crypto';
const e=await initializeTestEnvironment({projectId:'demo-hotel-pro-sync',firestore:{host:'127.0.0.1',port:18080},storage:{host:'127.0.0.1',port:19199}});
try {
  const c=e.authenticatedContext('SNzxI9YKyt9oo3j34KVprQvfkeTZ',{phone_number:'+919999999995'});
  const root='businesses/biz_dSTe8zIERdCHRfUZ4CoW',db=c.firestore();
  const room=(await getDoc(doc(db,`${root}/rooms/room_103`))).data();
  const guests=(await getDocs(collection(db,`${root}/guests`))).docs.filter(g=>!g.data().deleted && room.mobile && g.data().mobile===room.mobile && g.data().idNumber===room.idNumber);
  const result={room103Status:room.status,matchingGuestCount:guests.length,photos:[],productionChanged:false};
  if(guests.length===1) for(const side of ['Front','Back']) {
    const g=guests[0].data(),path=g[`id${side}StoragePath`],sha=g[`id${side}Sha256`];
    if(!path || !sha){result.photos.push({side,status:'missing-cloud-reference'});continue;}
    try {const b=await getBytes(ref(c.storage('gs://demo-hotel-pro-sync.appspot.com'),path));result.photos.push({side,status:createHash('sha256').update(Buffer.from(b)).digest('hex')===sha?'verified':'checksum-mismatch',bytes:b.byteLength});}
    catch(error){result.photos.push({side,status:'read-failed',code:error.code});}
  }
  console.log(JSON.stringify(result));
} finally {await e.cleanup();}
