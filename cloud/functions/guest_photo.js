'use strict';

// Web browsers cannot download Storage objects without a bucket CORS rule.
// This callable reads a guest ID photo server-side with the same access rule
// as storage.rules (`allow read: if isAdmin() || isBusinessOwner(businessId)`).
const MAX_BYTES = 5 * 1024 * 1024;
const PATH = /^businesses\/([A-Za-z0-9_-]+)\/guests\/[A-Za-z0-9_-]+\/(?:[A-Za-z0-9_-]+\/)*id_(?:front|back)\.jpg$/;

function parsePhotoPath(path) {
  if (typeof path !== 'string' || path.length > 512 || path.includes('..')) return null;
  const match = PATH.exec(path);
  return match ? {businessId: match[1]} : null;
}

async function readGuestPhoto({db, bucket, uid, isAdmin, path}) {
  const parsed = parsePhotoPath(path);
  if (!parsed) return {error: 'invalid-argument'};
  if (!uid) return {error: 'unauthenticated'};
  if (!isAdmin) {
    const business = await db.doc(`businesses/${parsed.businessId}`).get();
    if (!business.exists || business.get('ownerUid') !== uid) {
      return {error: 'permission-denied'};
    }
  }
  const file = bucket.file(path);
  const [exists] = await file.exists();
  if (!exists) return {error: 'not-found'};
  const [metadata] = await file.getMetadata();
  if (Number(metadata.size) > MAX_BYTES) return {error: 'failed-precondition'};
  const [bytes] = await file.download();
  return {base64: bytes.toString('base64'), contentType: metadata.contentType || 'image/jpeg'};
}

module.exports = {parsePhotoPath, readGuestPhoto, MAX_BYTES};
