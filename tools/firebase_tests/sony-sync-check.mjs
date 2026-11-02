import {initializeTestEnvironment} from '@firebase/rules-unit-testing';
import {doc,getDoc,getDocs,collection,updateDoc} from 'firebase/firestore';
import assert from 'node:assert/strict';
const env=await initializeTestEnvironment({projectId:'demo-hotel-pro-sync',firestore:{host:'127.0.0.1',port:18080}});
try{const db=env.authenticatedContext('SNzxI9YKyt9oo3j34KVprQvfkeTZ',{phone_number:'+919999999995'}).firestore(),root='businesses/biz_dSTe8zIERdCHRfUZ4CoW';for(const n of [101,102])assert.equal((await getDoc(doc(db,`${root}/rooms/room_${n}`))).data().status,'BOOKED');const bookings=await getDocs(collection(db,`${root}/bookings`)),guests=await getDocs(collection(db,`${root}/guests`));await updateDoc(doc(db,`${root}/rooms/room_103`),{roomName:'SYNC CHECK 103'});console.log(JSON.stringify({secondOwnerClientRead:'passed',bookingCount:bookings.size,guestCount:guests.size,room103RenameSent:true,productionChanged:false}));}finally{await env.cleanup();}
