const {FieldValue} = require('firebase-admin/firestore');

/// Login moved from email + password to mobile OTP. A hotel registered with
/// email belongs to that email UID, while an OTP login gets a new phone UID.
/// This moves exactly one such hotel to the verified mobile when the mobile
/// saved at signup matches the OTP-verified number.
///
/// Never moves a hotel whose current owner already has a verified phone
/// login, never overwrites an existing mapping of the caller, and refuses
/// ambiguous matches (two hotels with the same mobile).
async function claimHotelByPhone(db, uid, phone, getAuthUser) {
  if (typeof uid !== 'string' || !uid || typeof phone !== 'string' || !/^\+\d{8,15}$/.test(phone)) {
    return {claimed: false, reason: 'phone-login-required'};
  }
  const digits = phone.slice(1);
  const userRef = db.doc(`users/${uid}`);
  const phoneRef = db.doc(`phoneIndex/${digits}`);
  const [userSnap, phoneSnap] = await Promise.all([userRef.get(), phoneRef.get()]);
  if (typeof userSnap.data()?.businessId === 'string' && userSnap.data().businessId) {
    return {claimed: false, reason: 'already-mapped', businessId: userSnap.data().businessId};
  }
  if (phoneSnap.exists) {
    return {claimed: false, reason: 'phone-already-mapped'};
  }
  const matches = await db.collection('businesses').where('phoneNumber', '==', phone).limit(2).get();
  if (matches.empty) return {claimed: false, reason: 'no-match'};
  if (matches.size > 1) return {claimed: false, reason: 'ambiguous'};
  const bizDoc = matches.docs[0];
  const businessId = bizDoc.id;
  const previousOwnerUid = bizDoc.data().ownerUid;
  if (previousOwnerUid === uid) return {claimed: false, reason: 'already-owner', businessId};
  if (typeof previousOwnerUid === 'string' && previousOwnerUid) {
    const previous = await getAuthUser(previousOwnerUid);
    // A verified mobile owner keeps their hotel; only email-era owners move.
    if (previous && previous.phoneNumber) return {claimed: false, reason: 'owner-has-phone-login'};
  }
  const previousUserSnap = typeof previousOwnerUid === 'string' && previousOwnerUid
    ? await db.doc(`users/${previousOwnerUid}`).get()
    : null;
  const previousUser = previousUserSnap?.data() || {};

  return db.runTransaction(async (tx) => {
    const bizRef = db.doc(`businesses/${businessId}`);
    const [biz, user, index] = await Promise.all([tx.get(bizRef), tx.get(userRef), tx.get(phoneRef)]);
    if (!biz.exists || biz.data().ownerUid !== previousOwnerUid || biz.data().phoneNumber !== phone) {
      return {claimed: false, reason: 'changed'};
    }
    if (user.data()?.businessId || index.exists) return {claimed: false, reason: 'changed'};
    const now = FieldValue.serverTimestamp();
    tx.set(bizRef, {
      ownerUid: uid,
      ...(previousOwnerUid ? {previousOwnerUids: FieldValue.arrayUnion(previousOwnerUid)} : {}),
      ownerMigratedAt: now,
      updatedAt: now,
    }, {merge: true});
    tx.set(userRef, {
      businessId,
      role: 'owner',
      phoneNumber: phone,
      ownerName: typeof previousUser.ownerName === 'string' ? previousUser.ownerName : '',
      ...(typeof previousUser.email === 'string' ? {legacyEmail: previousUser.email} : {}),
      migratedFromUid: previousOwnerUid || null,
      createdAt: now,
      updatedAt: now,
    }, {merge: true});
    tx.create(phoneRef, {ownerUid: uid, businessId, phoneNumber: phone});
    if (previousUserSnap?.exists) {
      tx.set(previousUserSnap.ref, {migratedToUid: uid, updatedAt: now}, {merge: true});
    }
    tx.create(db.collection('adminAuditLogs').doc(), {
      actorUid: uid,
      action: 'owner-moved-to-mobile-login',
      hotelId: businessId,
      fromUid: previousOwnerUid || null,
      createdAt: now,
    });
    return {claimed: true, businessId};
  });
}

module.exports = {claimHotelByPhone};
