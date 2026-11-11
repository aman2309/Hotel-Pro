const {FieldPath} = require('firebase-admin/firestore');
const {requireAdmin} = require('./admin');
const COLLECTIONS = ['rooms','bookings','futureBookings','guests','bills','payments','expenses','closedRooms','extraCharges','settings'];
function validId(id) {
  if (typeof id !== 'string' || !id || id.includes('/') || id.length > 150) throw Error('INVALID_HOTEL');
  return id;
}
function clean(value) {
  if (value?.toMillis) return value.toMillis();
  if (Array.isArray(value)) return value.map(clean);
  if (value && typeof value === 'object') return Object.fromEntries(Object.entries(value)
    .filter(([k]) => !['hotel_admin_password','adminPassword','pinHash','lastRedemptionId','activationId'].includes(k))
    .map(([k,v]) => [k,clean(v)]));
  return value ?? null;
}
function status(license, enabled, now = Date.now()) {
  if (!enabled) return 'Suspended';
  if ((license.expiresAt?.toMillis() || 0) > now) return 'Active';
  if (license.expiresAt || license.activated) return 'Expired';
  const end=license.trialEndsAt?.toMillis() || (license.trialStart?.toMillis() || 0) + 864000000;
  return end > now ? 'Trial' : 'Expired';
}
async function hotelSummary(ref) {
  const business=(await ref.get()).data();
  if (!business || business.deletedAt) throw Error('HOTEL_NOT_FOUND');
  const [license,settings,rooms,user] = await Promise.all([
    ref.collection('settings').doc('license').get(), ref.collection('settings').doc('hotel').get(),
    ref.collection('rooms').get(),business.ownerUid ? ref.firestore.doc(`users/${business.ownerUid}`).get() : null]);
  const l=license.data() || {}, s=settings.data() || {};
  const activeRooms=rooms.docs.map(d=>d.data()).filter(d=>!d.deleted);
  const counts={total:activeRooms.length,available:0,booked:0,cleaning:0,closed:0,future:0};
  for(const room of activeRooms) {
    const key={EMPTY:'available',BOOKED:'booked',CLEANING:'cleaning',CLOSED:'closed'}[room.status];
    if(key) counts[key]++;
    if(room.futureBooking) counts.future++;
  }
  return {hotelId:ref.id,hotelName:s.hotel_name || business.businessName || 'Hotel',
    ownerUid:business.ownerUid,email:user?.data()?.email || '',ownerName:user?.data()?.ownerName || '',
    phoneNumber:s.hotel_mobile || business.phoneNumber || '',address:s.hotel_address || '',
    enabled:business.enabled !== false,status:business.deletingAt ? 'Deleting' : status(l,business.enabled !== false),
    deleting: Boolean(business.deletingAt),createdAt:clean(business.createdAt),settings:clean(s),license:clean(l),rooms:counts};
}
async function listHotels(db, actor, input = {}) {
  requireAdmin(actor);
  const limit=input.limit ?? 30;
  if(!Number.isInteger(limit)||limit<1||limit>100) throw Error('INVALID_LIMIT');
  // Read only ordering metadata first, including legacy hotels without createdAt.
  const snapshot = await db.collection('businesses').select('createdAt', 'deletedAt').get();
  const ordered = snapshot.docs.filter(doc => !doc.get('deletedAt')).sort((a, b) =>
    (dateMs(b.get('createdAt')) ?? 0) - (dateMs(a.get('createdAt')) ?? 0) ||
    a.id.localeCompare(b.id));
  const cursorIndex = input.after ? ordered.findIndex(doc => doc.id === validId(input.after)) : -1;
  if (input.after && cursorIndex === -1) throw Error('Hotel list changed. Refresh and try again.');
  const page = ordered.slice(cursorIndex + 1, cursorIndex + 1 + limit);
  const items = [];
  for (let i = 0; i < page.length; i += 10) {
    items.push(...await Promise.all(page.slice(i, i + 10).map(doc => hotelSummary(doc.ref))));
  }
  return {items, nextCursor: cursorIndex + 1 + limit < ordered.length ? page.at(-1).id : null};
}
function dateMs(raw) {
  if(raw?.toMillis) return raw.toMillis();
  if(typeof raw === 'number') return raw;
  const n=Date.parse(raw || '');return Number.isNaN(n)?null:n;
}
function analytics(bills, expenses, from = 0, to = Date.now()) {
  const series=new Map();
  let billed=0,spent=0,stays=0,stayMinutes=0;
  for(const b of bills.filter(b=>!b.deleted)) {
    const day=dateMs(b.checkoutTime ?? b.bookingTime ?? b.bookingDate);
    if(day===null||day<from||day>to) continue;
    const amount=Number(b.totalBill)||0;
    billed+=amount;stays++;
    stayMinutes+=Number(b.stayDurationMinutes)||0;
    const key=new Date(day).toISOString().slice(0,7);
    const p=series.get(key)||{month:key,billed:0,expenses:0};p.billed+=amount;series.set(key,p);
  }
  for(const e of expenses.filter(e=>!e.deleted)) {
    const day=dateMs(e.dateTime ?? e.date ?? e.createdAt);
    if(day===null||day<from||day>to) continue;
    const amount=Number(e.amount)||0;spent+=amount;
    const key=new Date(day).toISOString().slice(0,7);
    const p=series.get(key)||{month:key,billed:0,expenses:0};p.expenses+=amount;series.set(key,p);
  }
  return {billed,expenses:spent,net:billed-spent,completedStays:stays,stayMinutes,
    series:[...series.values()].sort((a,b)=>a.month.localeCompare(b.month))};
}
async function hotelDetails(db,actor,input) {
  requireAdmin(actor);const id=validId(input.hotelId),ref=db.doc(`businesses/${id}`);
  if(!(await ref.get()).exists) throw Error('HOTEL_NOT_FOUND');
  const [summary,bills,expenses,guests,payments]=await Promise.all([hotelSummary(ref),ref.collection('bills').get(),
    ref.collection('expenses').get(),ref.collection('guests').get(),ref.collection('payments').get()]);
  const from=input.from == null ? 0 : dateMs(input.from),to=input.to == null ? Date.now() : dateMs(input.to);
  if(from===null||to===null||from>to) throw Error('INVALID_DATE_RANGE');
  return {...summary,analytics:analytics(bills.docs.map(d=>d.data()),expenses.docs.map(d=>d.data()),from,to),
    guests:guests.docs.filter(d=>!d.data().deleted).length,
    payments:payments.docs.filter(d=>!d.data().deleted).length};
}
async function records(db,actor,input) {
  requireAdmin(actor);const id=validId(input.hotelId),collection=input.collection;
  if(!COLLECTIONS.includes(collection)) throw Error('INVALID_COLLECTION');
  const limit=input.limit ?? 50;
  if(!Number.isInteger(limit)||limit<1||limit>100) throw Error('INVALID_LIMIT');
  let q=db.doc(`businesses/${id}`).collection(collection).orderBy(FieldPath.documentId()).limit(limit);
  if(input.after) q=q.startAfter(validId(input.after));
  const snap=await q.get();
  return {items:snap.docs.filter(d=>!d.data().deleted).map(d=>({id:d.id,...clean(d.data())})),
    nextCursor:snap.size===limit?snap.docs.at(-1).id:null};
}
async function audit(db,actor,input={}) {
  requireAdmin(actor);let q=db.collection('adminAuditLogs').orderBy('createdAt','desc').limit(50);
  if(input.after) {const d=await db.collection('adminAuditLogs').doc(validId(input.after)).get();if(!d.exists)throw Error('INVALID_CURSOR');q=q.startAfter(d);}
  const snap=await q.get();return {items:snap.docs.map(d=>({id:d.id,...clean(d.data())})),nextCursor:snap.size===50?snap.docs.at(-1).id:null};
}
module.exports={listHotels,hotelDetails,records,audit,analytics,status,clean};
