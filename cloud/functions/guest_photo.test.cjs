const {test} = require('node:test');
const assert = require('node:assert/strict');
const {parsePhotoPath, readGuestPhoto} = require('./guest_photo');

const db = owner => ({doc: () => ({get: async () => ({exists: owner !== null, get: () => owner})})});
const bucket = (bytes = Buffer.from('jpeg')) => ({
  file: () => ({
    exists: async () => [bytes !== null],
    getMetadata: async () => [{size: String(bytes?.length ?? 0), contentType: 'image/jpeg'}],
    download: async () => [bytes],
  }),
});
const path = 'businesses/biz1/guests/g1/versions/abc123/id_front.jpg';

test('accepts only guest ID photo paths', () => {
  assert.deepEqual(parsePhotoPath(path), {businessId: 'biz1'});
  assert.deepEqual(parsePhotoPath('businesses/biz1/guests/g1/additional/ag_9/id_back.jpg'), {businessId: 'biz1'});
  assert.equal(parsePhotoPath('businesses/biz1/guests/g1/../../x/id_front.jpg'), null);
  assert.equal(parsePhotoPath('businesses/biz1/bills/b1.pdf'), null);
  assert.equal(parsePhotoPath(42), null);
});

test('owner gets the photo bytes', async () => {
  const result = await readGuestPhoto({db: db('u1'), bucket: bucket(), uid: 'u1', isAdmin: false, path});
  assert.equal(Buffer.from(result.base64, 'base64').toString(), 'jpeg');
});

test('another hotel owner is refused', async () => {
  const result = await readGuestPhoto({db: db('u1'), bucket: bucket(), uid: 'u2', isAdmin: false, path});
  assert.equal(result.error, 'permission-denied');
});

test('admin may read and missing objects report not-found', async () => {
  const result = await readGuestPhoto({db: db('u1'), bucket: bucket(null), uid: 'admin', isAdmin: true, path});
  assert.equal(result.error, 'not-found');
});
