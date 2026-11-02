const {Timestamp} = require('firebase-admin/firestore');
const {DEFAULT_ROOMS, emptyRoomDocument} = require('./default_rooms');

const REPAIR_AFTER_MS = Date.parse('2026-10-22T18:30:00.000Z');
const TRIAL_MS = 10 * 24 * 60 * 60 * 1000;
const HISTORY = ['bookings', 'guests', 'bills', 'payments', 'expenses'];

function isVerifiedNewAccount(biz, licenseExists, license) {
  if (!biz || biz.dataResetAt) return false;
  if (biz.onboardingStatus === 'complete') return false;
  if (licenseExists && (license.trialStart || license.activated === true || license.expiresAt)) {
    return biz.onboardingStatus === 'pending' || biz.newOwnerSetup === true;
  }
  if (biz.onboardingStatus === 'pending' || biz.newOwnerSetup === true) return true;
  const created = biz.createdAt && biz.createdAt.toDate ? biz.createdAt.toDate() : null;
  return Boolean(created && created.getTime() >= REPAIR_AFTER_MS && !licenseExists);
}

async function provisionHotel(db, uid, phone, now = Date.now()) {
  const userRef = db.doc(`users/${uid}`);
  return db.runTransaction(async (tx) => {
    const userSnap = await tx.get(userRef);
    const user = userSnap.data();
    if (!user || user.phoneNumber !== phone) throw Error('Verified owner required');
    const id = user.businessId;
    if (typeof id !== 'string' || !id || id.includes('/')) throw Error('Invalid mapping');
    const bizRef = db.doc(`businesses/${id}`);
    const licenseRef = db.doc(`businesses/${id}/settings/license`);
    const markerRef = db.doc(`businesses/${id}/settings/onboarding`);
    const roomRefs = DEFAULT_ROOMS.map((spec) => db.doc(`businesses/${id}/rooms/room_${spec.roomNumber}`));
    const historyRefs = HISTORY.map((name) => db.collection(`businesses/${id}/${name}`).limit(1));
    const [bizSnap, licenseSnap, markerSnap, ...rest] = await Promise.all([
      tx.get(bizRef),
      tx.get(licenseRef),
      tx.get(markerRef),
      ...roomRefs.map((ref) => tx.get(ref)),
      ...historyRefs.map((query) => tx.get(query)),
    ]);
    const roomSnaps = rest.slice(0, DEFAULT_ROOMS.length);
    const historySnaps = rest.slice(DEFAULT_ROOMS.length);
    if (!bizSnap.exists || bizSnap.data().ownerUid !== uid) throw Error('Hotel owner mismatch');
    const biz = bizSnap.data();
    if (markerSnap.data()?.status === 'complete') {
      return {provisioned: false, reason: 'already-complete', businessId: id, roomsAdded: 0};
    }
    const operational = historySnaps.some((snap) => !snap.empty);
    if (biz.dataResetAt || operational || !isVerifiedNewAccount(biz, licenseSnap.exists, licenseSnap.data() || {})) {
      return {provisioned: false, reason: 'existing-hotel', businessId: id, roomsAdded: 0};
    }
    let added = 0;
    DEFAULT_ROOMS.forEach((spec, index) => {
      if (roomSnaps[index].exists) return;
      tx.set(roomRefs[index], emptyRoomDocument(spec));
      added += 1;
    });
    if (!licenseSnap.exists) {
      tx.set(licenseRef, {
        trialStart: Timestamp.fromMillis(now),
        trialEndsAt: Timestamp.fromMillis(now + TRIAL_MS),
        activated: false,
        plan: null,
        expiresAt: null,
        setupVersion: 1,
      });
    }
    tx.set(markerRef, {
      status: 'complete',
      roomsAdded: added,
      completedAt: Timestamp.fromMillis(now),
    });
    tx.set(bizRef, {onboardingStatus: 'complete'}, {merge: true});
    return {provisioned: true, reason: 'initialized', businessId: id, roomsAdded: added};
  });
}

module.exports = {provisionHotel, isVerifiedNewAccount, TRIAL_MS};
