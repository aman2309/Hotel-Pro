const {onCall, HttpsError} = require('firebase-functions/v2/https');
const {defineSecret} = require('firebase-functions/params');
const {initializeApp} = require('firebase-admin/app');
const {getFirestore} = require('firebase-admin/firestore');
const {activateLicense} = require('./license');
const {provisionHotel} = require('./onboarding');
initializeApp();
const pinSecret = defineSecret('HOTELPRO_PIN_HMAC_KEY');

function caller(request) {
  if (!request.auth?.uid || !request.auth.token.phone_number) {
    throw new HttpsError('unauthenticated', 'OTP login required');
  }
  return {uid: request.auth.uid, phone: request.auth.token.phone_number};
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
