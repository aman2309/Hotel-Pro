const {test, after} = require('node:test');
const assert = require('node:assert/strict');
const {initializeApp, deleteApp} = require('firebase-admin/app');
const {getFirestore} = require('firebase-admin/firestore');
const otp = require('./sms_otp');

if (process.env.FIRESTORE_EMULATOR_HOST !== '127.0.0.1:18080') throw Error('Local emulator only');
const app = initializeApp({projectId: 'demo-hotel-pro-sync'}, 'sms-otp-tests');
const db = getFirestore(app);
after(() => deleteApp(app));

let seq = 0;
function mobile() {
  return `9${String(Date.now()).slice(-7)}${String(seq++ % 100).padStart(2, '0')}`;
}
function smsRecorder() {
  const sent = [];
  return {sent, send: async (message) => { sent.push(message); }};
}
function fakeAuth(existing = {}) {
  const users = new Map(Object.entries(existing));
  const created = [];
  return {
    created,
    async getUserByPhoneNumber(phone) {
      const uid = users.get(phone);
      if (!uid) throw Object.assign(Error('missing'), {code: 'auth/user-not-found'});
      return {uid, disabled: false};
    },
    async createUser({phoneNumber}) {
      const uid = `new_${phoneNumber}`;
      users.set(phoneNumber, uid);
      created.push(phoneNumber);
      return {uid, disabled: false};
    },
    async createCustomToken(uid) { return `token-for-${uid}`; },
  };
}

test('the SMS uses the exact DLT template with a 4-digit code and no +91', async () => {
  const m = mobile();
  const sms = smsRecorder();
  const result = await otp.sendLoginOtp({db, mobile: m, sendSms: sms.send, makeCode: () => '0427'});
  assert.equal(result.sent, true);
  assert.equal(result.resendAfter, 30);
  assert.equal(sms.sent.length, 1);
  assert.equal(sms.sent[0].mobile, m);
  assert.equal(sms.sent[0].text, 'Your OTP for Hotel Pro login is 0427 Valid for 2 minutes only. Do not share this OTP with anyone for security reasons. NCDM');
  assert.match(sms.sent[0].messageId, /^[0-9a-f]{16}$/);
  const stored = (await db.doc(`${otp.OTP_COLLECTION}/${m}`).get()).data();
  assert.notEqual(stored.hash, '0427');
  assert.equal(JSON.stringify(stored).includes('0427'), false);
});

test('a correct OTP logs in the existing +91 account with the same uid, once', async () => {
  const m = mobile();
  const now = Date.now();
  await otp.sendLoginOtp({db, mobile: m, now, sendSms: smsRecorder().send, makeCode: () => '1234'});
  const auth = fakeAuth({[`+91${m}`]: 'existing-owner'});
  const ok = await otp.verifyLoginOtp({db, auth, mobile: m, code: '1234', now: now + 1000});
  assert.deepEqual(ok, {token: 'token-for-existing-owner', isNewUser: false});
  assert.deepEqual(auth.created, []);
  const reused = await otp.verifyLoginOtp({db, auth, mobile: m, code: '1234', now: now + 2000});
  assert.equal(reused.error, 'expired');
});

test('a new number gets a new phone account', async () => {
  const m = mobile();
  const now = Date.now();
  await otp.sendLoginOtp({db, mobile: m, now, sendSms: smsRecorder().send, makeCode: () => '5555'});
  const auth = fakeAuth();
  const ok = await otp.verifyLoginOtp({db, auth, mobile: m, code: '5555', now});
  assert.equal(ok.isNewUser, true);
  assert.deepEqual(auth.created, [`+91${m}`]);
});

test('codes expire after 2 minutes', async () => {
  const m = mobile();
  const now = Date.now();
  await otp.sendLoginOtp({db, mobile: m, now, sendSms: smsRecorder().send, makeCode: () => '1111'});
  const late = await otp.verifyLoginOtp({db, auth: fakeAuth(), mobile: m, code: '1111', now: now + otp.OTP_TTL_MS + 1});
  assert.equal(late.error, 'expired');
});

test('five wrong attempts lock the code', async () => {
  const m = mobile();
  const now = Date.now();
  await otp.sendLoginOtp({db, mobile: m, now, sendSms: smsRecorder().send, makeCode: () => '2468'});
  const auth = fakeAuth();
  for (let i = 1; i < otp.MAX_VERIFY_ATTEMPTS; i++) {
    const wrong = await otp.verifyLoginOtp({db, auth, mobile: m, code: '0000', now});
    assert.deepEqual(wrong, {error: 'invalid-code', remaining: otp.MAX_VERIFY_ATTEMPTS - i});
  }
  assert.equal((await otp.verifyLoginOtp({db, auth, mobile: m, code: '0000', now})).error, 'too-many-attempts');
  assert.equal((await otp.verifyLoginOtp({db, auth, mobile: m, code: '2468', now})).error, 'expired');
});

test('resend has a 30s cooldown and replaces the old code', async () => {
  const m = mobile();
  const now = Date.now();
  const sms = smsRecorder();
  await otp.sendLoginOtp({db, mobile: m, now, sendSms: sms.send, makeCode: () => '1000'});
  const early = await otp.sendLoginOtp({db, mobile: m, now: now + 10000, sendSms: sms.send, makeCode: () => '2000'});
  assert.equal(early.error, 'cooldown');
  assert.equal(early.retryAfter, 20);
  assert.equal(sms.sent.length, 1);
  await otp.sendLoginOtp({db, mobile: m, now: now + otp.RESEND_COOLDOWN_MS, sendSms: sms.send, makeCode: () => '2000'});
  const auth = fakeAuth();
  assert.equal((await otp.verifyLoginOtp({db, auth, mobile: m, code: '1000', now: now + 31000})).error, 'invalid-code');
  assert.ok((await otp.verifyLoginOtp({db, auth, mobile: m, code: '2000', now: now + 31000})).token);
});

test('each number has a daily send limit', async () => {
  const m = mobile();
  const start = Date.now();
  const sms = smsRecorder();
  for (let i = 0; i < otp.DAILY_SENDS_PER_NUMBER; i++) {
    const r = await otp.sendLoginOtp({db, mobile: m, now: start + i * otp.RESEND_COOLDOWN_MS, sendSms: sms.send});
    assert.equal(r.sent, true);
  }
  const blocked = await otp.sendLoginOtp({db, mobile: m, now: start + 11 * otp.RESEND_COOLDOWN_MS, sendSms: sms.send});
  assert.equal(blocked.error, 'daily-limit');
});

test('a failed SMS invalidates the code and allows an immediate retry', async () => {
  const m = mobile();
  const now = Date.now();
  const failed = await otp.sendLoginOtp({db, mobile: m, now, sendSms: async () => { throw Error('gateway down'); }, makeCode: () => '7777'});
  assert.equal(failed.error, 'sms-failed');
  assert.equal((await otp.verifyLoginOtp({db, auth: fakeAuth(), mobile: m, code: '7777', now})).error, 'expired');
  const retry = await otp.sendLoginOtp({db, mobile: m, now: now + 1000, sendSms: smsRecorder().send});
  assert.equal(retry.sent, true);
});

test('bad input is refused before any SMS', async () => {
  const sms = smsRecorder();
  assert.equal((await otp.sendLoginOtp({db, mobile: '12345', sendSms: sms.send})).error, 'invalid-mobile');
  assert.equal((await otp.verifyLoginOtp({db, auth: fakeAuth(), mobile: mobile(), code: '12a4'})).error, 'invalid-code');
  assert.equal(sms.sent.length, 0);
  assert.equal(otp.normalizeMobile('+91 98765 43210'), '9876543210');
});

test('the gateway call matches the API and treats non-200 as failure', async () => {
  const calls = [];
  const fakeFetch = (body) => async (url, init) => {
    calls.push({url, init});
    return {status: 200, json: async () => body};
  };
  await otp.sendSmsViaGateway({mobile: '9977243008', text: 'x', messageId: 'abc'},
    fakeFetch({code: '200', message: '[{"number":"9977243008","messageId":"abc"}]'}));
  assert.equal(calls[0].url, 'http://165.101.248.69/api/v1/sms/mt');
  assert.deepEqual(JSON.parse(calls[0].init.body), {
    senderId: 'NCDMPL', dcs: 0, peId: '1402491070000048262', text: 'x',
    dltTemplateId: '1477179455315438973', messageId: 'abc', numbers: ['9977243008'],
  });
  await assert.rejects(otp.sendSmsViaGateway({mobile: '9977243008', text: 'x', messageId: 'abc'},
    fakeFetch({code: '400', message: 'bad template'})));
});
