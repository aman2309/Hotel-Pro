const {FieldPath, FieldValue} = require('firebase-admin/firestore');

function requireAdmin(actor) {
  if (!actor?.uid || actor.admin !== true) throw Error('ADMIN_REQUIRED');
}
function hotelId(value) {
  if (typeof value !== 'string' || !value || value.includes('/') || value.length > 150) throw Error('INVALID_HOTEL');
  return value;
}
async function listHotels(db, actor, options = {}) {
  requireAdmin(actor);
  const limit = options.limit ?? 30;
  if (!Number.isInteger(limit) || limit < 1 || limit > 100) throw Error('INVALID_LIMIT');
  let query = db.collection('businesses').orderBy(FieldPath.documentId()).limit(limit);
  if (options.after) query = query.startAfter(hotelId(options.after));
  const hotels = await query.get();
  const items = await Promise.all(hotels.docs.map(async document => {
    const data = document.data();
    const license = (await document.ref.collection('settings').doc('license').get()).data() || {};
    return {hotelId: document.id, hotelName: data.businessName || '', ownerUid: data.ownerUid,
      phoneNumber: data.phoneNumber || '', enabled: data.enabled !== false,
      license: {activated: license.activated === true, expiresAt: license.expiresAt?.toMillis?.() ?? null,
        trialEndsAt: license.trialEndsAt?.toMillis?.() ?? null}};
  }));
  return {items, nextCursor: hotels.size === limit ? hotels.docs.at(-1).id : null};
}
async function setHotelEnabled(db, actor, id, enabled) {
  requireAdmin(actor);
  id = hotelId(id);
  if (typeof enabled !== 'boolean') throw Error('INVALID_STATUS');
  const ref = db.doc(`businesses/${id}`), audit = db.collection('adminAuditLogs').doc();
  await db.runTransaction(async tx => {
    const hotel = await tx.get(ref);
    if (!hotel.exists) throw Error('HOTEL_NOT_FOUND');
    tx.update(ref, {enabled, updatedAt: FieldValue.serverTimestamp()});
    tx.create(audit, {actorUid: actor.uid, hotelId: id, action: enabled ? 'hotel-resumed' : 'hotel-suspended',
      previousEnabled: hotel.data().enabled !== false, enabled, createdAt: FieldValue.serverTimestamp()});
  });
  return {hotelId: id, enabled};
}
module.exports = {requireAdmin, listHotels, setHotelEnabled};
