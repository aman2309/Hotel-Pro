'use strict';

// Hotel owner login by SMS OTP through the DLT SMS gateway.
// The code is generated here, never in the app. Firestore keeps only a salted
// hash with a 2-minute expiry (the SMS text promises 2 minutes).
const crypto = require('node:crypto');

const SMS_URL = 'http://165.101.248.69/api/v1/sms/mt';
const SENDER_ID = 'NCDMPL';
const PE_ID = '1402491070000048262';
const DLT_TEMPLATE_ID = '1477179455315438973';
// Must match the registered DLT template exactly, or the SMS is rejected.
const TEMPLATE = 'Your OTP for Hotel Pro login is {#num#} Valid for 2 minutes only. Do not share this OTP with anyone for security reasons. NCDM';

const OTP_TTL_MS = 2 * 60 * 1000;
const RESEND_COOLDOWN_MS = 30 * 1000;
const MAX_VERIFY_ATTEMPTS = 5;
const DAILY_SENDS_PER_NUMBER = 10;
const DAILY_SENDS_PER_IP = 40;
const OTP_COLLECTION = 'loginOtps';
const IP_COLLECTION = 'loginOtpIps';

function normalizeMobile(value) {
  const digits = typeof value === 'string' ? value.replace(/\D/g, '') : '';
  const ten = digits.length === 12 && digits.startsWith('91') ? digits.slice(2) : digits;
  return /^[6-9]\d{9}$/.test(ten) ? ten : null;
}

function istDay(now) {
  return new Date(now + 5.5 * 60 * 60 * 1000).toISOString().slice(0, 10);
}

function hashCode(salt, code) {
  return crypto.createHash('sha256').update(`${salt}:${code}`).digest('hex');
}

function randomCode() {
  return String(crypto.randomInt(0, 10000)).padStart(4, '0');
}

function smsText(code) {
  return TEMPLATE.replace('{#num#}', code);
}

/// Real gateway call. Anything but {"code":"200"} is a failed send.
async function sendSmsViaGateway({mobile, text, messageId}, fetchImpl = fetch, authorization = '') {
  const headers = {'Content-Type': 'application/json'};
  // The gateway requires an Authorization header (value kept in a secret).
  if (authorization) headers.Authorization = authorization;
  const response = await fetchImpl(SMS_URL, {
    method: 'POST',
    headers,
    body: JSON.stringify({
      senderId: SENDER_ID, dcs: 0, peId: PE_ID, text,
      dltTemplateId: DLT_TEMPLATE_ID, messageId, numbers: [mobile],
    }),
    signal: AbortSignal.timeout(15000),
  });
  let body = null;
  try {
    body = await response.json();
  } catch {
    body = null;
  }
  if (!body || String(body.code) !== '200') {
    throw Error(`SMS gateway rejected the message: HTTP ${response.status} ${JSON.stringify(body)}`);
  }
  return body;
}

/// Sends (or re-sends) a login OTP. A resend replaces the previous code.
async function sendLoginOtp({db, mobile: rawMobile, ip, now = Date.now(), sendSms, makeCode = randomCode}) {
  const mobile = normalizeMobile(rawMobile);
  if (!mobile) return {error: 'invalid-mobile'};
  const day = istDay(now);
  const ref = db.collection(OTP_COLLECTION).doc(mobile);
  const ipRef = ip
    ? db.collection(IP_COLLECTION).doc(crypto.createHash('sha256').update(String(ip)).digest('hex'))
    : null;
  const code = makeCode();
  const salt = crypto.randomBytes(16).toString('hex');
  const messageId = crypto.randomBytes(8).toString('hex');

  const reserved = await db.runTransaction(async (tx) => {
    const [snap, ipSnap] = await Promise.all([tx.get(ref), ipRef ? tx.get(ipRef) : null]);
    const data = snap.data() || {};
    const lastSentAt = data.lastSentAt || 0;
    if (now - lastSentAt < RESEND_COOLDOWN_MS) {
      return {error: 'cooldown', retryAfter: Math.ceil((RESEND_COOLDOWN_MS - (now - lastSentAt)) / 1000)};
    }
    const dayCount = data.day === day ? data.dayCount || 0 : 0;
    if (dayCount >= DAILY_SENDS_PER_NUMBER) return {error: 'daily-limit'};
    const ipData = ipSnap?.data() || {};
    const ipCount = ipData.day === day ? ipData.count || 0 : 0;
    if (ipRef && ipCount >= DAILY_SENDS_PER_IP) return {error: 'daily-limit'};
    tx.set(ref, {
      hash: hashCode(salt, code), salt, expiresAt: now + OTP_TTL_MS, attempts: 0,
      lastSentAt: now, day, dayCount: dayCount + 1, messageId,
    });
    if (ipRef) tx.set(ipRef, {day, count: ipCount + 1});
    return {ok: true};
  });
  if (reserved.error) return reserved;

  try {
    await sendSms({mobile, text: smsText(code), messageId});
  } catch (error) {
    console.error('Login OTP SMS failed', {mobileEnding: mobile.slice(-4), error: String(error)});
    // The code never reached the owner: invalidate it and allow an immediate retry.
    await ref.set({hash: null, salt: null, lastSentAt: 0}, {merge: true});
    // Gateway status and message only (never the code), for debugging.
    return {error: 'sms-failed', gateway: String(error?.message || error).slice(0, 300)};
  }
  return {sent: true, resendAfter: RESEND_COOLDOWN_MS / 1000, expiresIn: OTP_TTL_MS / 1000};
}

/// Checks the OTP and returns a Firebase custom token for the owner's
/// phone account. An existing +91 account keeps its uid (and its hotel).
async function verifyLoginOtp({db, auth, mobile: rawMobile, code, now = Date.now()}) {
  const mobile = normalizeMobile(rawMobile);
  if (!mobile) return {error: 'invalid-mobile'};
  if (typeof code !== 'string' || !/^\d{4}$/.test(code)) return {error: 'invalid-code', remaining: null};
  const ref = db.collection(OTP_COLLECTION).doc(mobile);

  const checked = await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const data = snap.data();
    if (!data || !data.hash || !data.salt) return {error: 'expired'};
    if (now > data.expiresAt) {
      tx.set(ref, {hash: null, salt: null}, {merge: true});
      return {error: 'expired'};
    }
    const attempts = data.attempts || 0;
    if (attempts >= MAX_VERIFY_ATTEMPTS) return {error: 'too-many-attempts'};
    const expected = Buffer.from(data.hash, 'hex');
    const actual = Buffer.from(hashCode(data.salt, code), 'hex');
    if (expected.length !== actual.length || !crypto.timingSafeEqual(expected, actual)) {
      const used = attempts + 1;
      if (used >= MAX_VERIFY_ATTEMPTS) {
        tx.set(ref, {attempts: used, hash: null, salt: null}, {merge: true});
        return {error: 'too-many-attempts'};
      }
      tx.set(ref, {attempts: used}, {merge: true});
      return {error: 'invalid-code', remaining: MAX_VERIFY_ATTEMPTS - used};
    }
    // One use only.
    tx.set(ref, {hash: null, salt: null, verifiedAt: now}, {merge: true});
    return {ok: true};
  });
  if (checked.error) return checked;

  const phoneNumber = `+91${mobile}`;
  let user;
  let isNewUser = false;
  try {
    user = await auth.getUserByPhoneNumber(phoneNumber);
  } catch (error) {
    if (error?.code !== 'auth/user-not-found') throw error;
    user = await auth.createUser({phoneNumber});
    isNewUser = true;
  }
  if (user.disabled) return {error: 'user-disabled'};
  const token = await auth.createCustomToken(user.uid);
  return {token, isNewUser};
}

module.exports = {
  sendLoginOtp, verifyLoginOtp, sendSmsViaGateway, normalizeMobile, smsText, hashCode,
  OTP_TTL_MS, RESEND_COOLDOWN_MS, MAX_VERIFY_ATTEMPTS, DAILY_SENDS_PER_NUMBER,
  OTP_COLLECTION, TEMPLATE,
};
