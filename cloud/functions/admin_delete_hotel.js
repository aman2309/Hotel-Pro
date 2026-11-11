const {FieldValue} = require('firebase-admin/firestore');
const {requireAdmin} = require('./admin');

/// Permanently deletes a hotel: its photos, every subcollection, the hotel
/// document itself, the owner's mapping (users/{uid}) and its phoneIndex
/// entries. Nothing is kept as a draft or tombstone; the owner can sign up
/// again as a new hotel. Only an audit log entry remains.
async function deleteHotel(db, actor, input, deletePhotos) {
  requireAdmin(actor);
  const id = input?.hotelId;
  if (typeof id !== 'string' || !id || id.length > 150 || id.includes('/') ||
      id === '.' || id === '..' || input.confirmHotelId !== id) {
    throw Error('Confirm the exact hotel before deleting.');
  }

  const ref = db.collection('businesses').doc(id);
  const snapshot = await ref.get();
  const owners = new Set();
  if (snapshot.exists) {
    const data = snapshot.data();
    for (const uid of [data.ownerUid, ...(data.previousOwnerUids || [])]) {
      if (typeof uid === 'string' && uid) owners.add(uid);
    }
    if (!data.deletingAt && !data.deletedAt) {
      // Detach access before cleanup so existing sessions cannot write new data.
      await ref.update({ownerUid: null, enabled: false, deletingAt: FieldValue.serverTimestamp()});
    }
  }

  try {
    await deletePhotos(`businesses/${id}/`);
    for (const collection of await ref.listCollections()) {
      await db.recursiveDelete(collection);
    }
  } catch (error) {
    console.error('Hotel cleanup failed', {hotelId: id, error});
    throw Error('Hotel access is disabled. Retry deletion to finish removing its records and photos.');
  }

  const [users, phones] = await Promise.all([
    db.collection('users').where('businessId', '==', id).get(),
    db.collection('phoneIndex').where('businessId', '==', id).get(),
  ]);
  if (!snapshot.exists && users.empty && phones.empty) throw Error('Hotel not found.');

  const batch = db.batch();
  for (const doc of [...users.docs, ...phones.docs]) {
    if (doc.ref.parent.id === 'users') owners.add(doc.id);
    batch.delete(doc.ref);
  }
  batch.delete(ref);
  batch.create(db.collection('adminAuditLogs').doc(), {
    actorUid: actor.uid, hotelId: id, action: 'hotel-deleted',
    hotelName: snapshot.exists ? snapshot.get('businessName') || null : null,
    ownerUids: [...owners], createdAt: FieldValue.serverTimestamp(),
  });
  await batch.commit();
  return {hotelId: id, deleted: true};
}

module.exports = {deleteHotel};
