import {initializeTestEnvironment} from '@firebase/rules-unit-testing';
import {getDocs,collection,updateDoc,doc} from 'firebase/firestore';
import {ref,getBytes} from 'firebase/storage';
import {createHash} from 'node:crypto';
import assert from 'node:assert/strict';
const e=await initializeTestEnvironment({projectId:'demo-hotel-pro-sync',firestore:{host:'127.0.0.1',port:18080},storage:{host:'127.0.0.1',port:19199}});
try{const c=e.authenticatedContext('SNzxI9YKyt9oo3j34KVprQvfkeTZ',{phone_number:'+919999999995'}),root='businesses/biz_dSTe8zIERdCHRfUZ4CoW';let n=0;for(const g of (await getDocs(collection(c.firestore(),`${root}/guests`))).docs){const d=g.data();for(const side of ['Front','Back']){const b=await getBytes(ref(c.storage("gs://demo-hotel-pro-sync.appspot.com"),d[`id${side}StoragePath`]));assert.equal(createHash('sha256').update(Buffer.from(b)).digest('hex'),d[`id${side}Sha256`]);n++;}}assert.equal(n,4);await updateDoc(doc(c.firestore(),`${root}/rooms/room_103`),{roomName:'LIVE CHECK 103'});console.log(JSON.stringify({freshClientPhotosVerified:n,room103NewRealtimeChangeSent:true}));}finally{await e.cleanup();}
