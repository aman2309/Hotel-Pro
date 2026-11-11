const {onCall, HttpsError} = require('firebase-functions/v2/https');
const {defineSecret} = require('firebase-functions/params');
const {initializeApp} = require('firebase-admin/app');
const {getFirestore} = require('firebase-admin/firestore');
const {activateLicense} = require('./license');
const {provisionHotel} = require('./onboarding');
initializeApp();
const pinSecret = defineSecret('HOTELPRO_PIN_HMAC_KEY');

function caller(request) {
  if (!request.auth?.uid || !(request.auth.token.email || request.auth.token.phone_number)) {
    throw new HttpsError('unauthenticated', 'Login required');
  }
  return {uid: request.auth.uid, phone: request.auth.token.email || request.auth.token.phone_number};
}

exports.redeemHotelPin = onCall({region: 'asia-south1', secrets: [pinSecret], maxInstances: 5}, async (request) => {
  const {uid, phone} = caller(request);
  if (typeof request.data?.pin !== 'string' || !/^\d{8}$/.test(request.data.pin)) {
    throw new HttpsError('invalid-argument', '8 digit PIN required');
  }
  let result;
  try {
    result = await activateLicense(getFirestore(), uid, phone, request.data.pin, pinSecret.value());
  } catch {
    throw new HttpsError('failed-precondition', 'Hotel setup needs review');
  }
  if (result.error) {
    throw new HttpsError(
      result.error === 'rate-limited' ? 'resource-exhausted' : 'permission-denied',
      'Activation unsuccessful. Try later or contact the seller.',
    );
  }
  return {activated: result.activated, businessId: result.businessId, expiresAt: result.expiresAt, idempotent: result.idempotent === true};
});

exports.provisionHotel = onCall({region: 'asia-south1', maxInstances: 5}, async (request) => {
  const {uid, phone} = caller(request);
  try {
    const result = await provisionHotel(getFirestore(), uid, phone);
    return {provisioned: result.provisioned, businessId: result.businessId, roomsAdded: result.roomsAdded, reason: result.reason};
  } catch {
    throw new HttpsError('failed-precondition', 'Hotel setup needs review');
  }
});

// Retain the callable name for installed apps; setup v3 seeds the standard
// twelve-room template once for a new hotel. Existing hotels are unchanged.
exports.initializeEmptyHotel = onCall({region: 'asia-south1', maxInstances: 5}, async (request) => {
  const {uid, phone} = caller(request);
  try {
    const result = await provisionHotel(getFirestore(), uid, phone);
    return {...result, setupVersion: 3};
  } catch {
    throw new HttpsError('failed-precondition', 'Hotel setup needs review');
  }
});

// The future admin panel uses the same Firebase project and hotel documents.
// Only an Admin SDK-issued custom claim grants access; a profile role does not.
const hotelAdmin = require('./admin');
function adminActor(request) {
  return {uid: request.auth?.uid, admin: request.auth?.token?.admin === true};
}
exports.adminListHotels = onCall({region: 'asia-south1', maxInstances: 5}, async request => {
  try { return await hotelAdmin.listHotels(getFirestore(), adminActor(request), request.data || {}); }
  catch (error) { throw new HttpsError(error.message === 'ADMIN_REQUIRED' ? 'permission-denied' : 'invalid-argument', 'Admin hotel lookup failed'); }
});
exports.adminSetHotelEnabled = onCall({region: 'asia-south1', maxInstances: 5}, async request => {
  try { return await hotelAdmin.setHotelEnabled(getFirestore(), adminActor(request), request.data?.hotelId, request.data?.enabled); }
  catch (error) { throw new HttpsError(error.message === 'ADMIN_REQUIRED' ? 'permission-denied' : 'invalid-argument', 'Admin hotel update failed'); }
});

const keys = require('./license_keys');
const adminData = require('./admin_data');
function callableError(error) {
  if(error instanceof HttpsError) return error;
  const denied=['ADMIN_REQUIRED','OWNER_REQUIRED'].includes(error.message);
  return new HttpsError(denied?'permission-denied':'failed-precondition',
    error.message === 'ADMIN_REQUIRED' ? 'Administrator access required.' : error.message);
}
function adminCall(handler, secret = false) {
  return onCall({region:'asia-south1',maxInstances:5,...(secret?{secrets:[pinSecret]}:{})},async request=>{
    try {return await handler(getFirestore(),adminActor(request),request.data||{},secret?pinSecret.value():null);}
    catch(error){throw callableError(error);}
  });
}
const {deleteHotel} = require('./admin_delete_hotel');
const {getStorage} = require('firebase-admin/storage');
exports.adminDeleteHotel = onCall({region: 'asia-south1', maxInstances: 5, timeoutSeconds: 540}, async request => {
  try {
    return await deleteHotel(getFirestore(), adminActor(request), request.data, prefix =>
      getStorage().bucket('yankees-hotel-pro.firebasestorage.app').deleteFiles({prefix, force: true}));
  } catch (error) {
    throw callableError(error);
  }
});
exports.adminListHotelsV2=adminCall(adminData.listHotels);
exports.adminHotelDetails=adminCall(adminData.hotelDetails);
exports.adminHotelRecords=adminCall(adminData.records);
exports.adminAuditLog=adminCall(adminData.audit);
exports.adminIssueLicenseKey=adminCall(keys.issueKey,true);
exports.adminListLicenseKeys=adminCall(keys.listKeys);
exports.adminRevokeLicenseKey=adminCall((db,actor,input)=>keys.revokeKey(db,actor,input.keyId));
exports.adminLicenseRevenue=adminCall((db,actor,input)=>keys.revenue(db,actor,input));
exports.redeemHotelLicenseKey=onCall({region:'asia-south1',secrets:[pinSecret],maxInstances:5},async request=>{
  const {uid,phone}=caller(request);
  try {
    const result=await keys.redeemKey(getFirestore(),uid,phone,request.data?.key,pinSecret.value());
    if(result.error) throw new HttpsError(result.error==='rate-limited'?'resource-exhausted':'permission-denied',
      result.error==='rate-limited'?'Too many attempts. Try again in 15 minutes.':'This key is invalid, already used, revoked, or assigned to another hotel.');
    return result;
  } catch(error) {throw callableError(error);}
});

// Guest ID photos for the web app (avoids needing a Storage bucket CORS rule).
const guestPhoto = require('./guest_photo');
exports.getGuestPhoto = onCall({region: 'asia-south1', maxInstances: 10, memory: '512MiB'}, async request => {
  const result = await guestPhoto.readGuestPhoto({
    db: getFirestore(),
    bucket: getStorage().bucket('yankees-hotel-pro.firebasestorage.app'),
    uid: request.auth?.uid,
    isAdmin: request.auth?.token?.admin === true,
    path: request.data?.path,
  });
  if (result.error) throw new HttpsError(result.error, 'Photo is not available');
  return result;
});
