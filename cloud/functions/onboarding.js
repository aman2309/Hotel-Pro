const {Timestamp, FieldValue} = require('firebase-admin/firestore');

const REPAIR_AFTER_MS = Date.parse('2026-10-22T18:30:00.000Z');
const TRIAL_MS = 10 * 24 * 60 * 60 * 1000;
const DEFAULT_ROOM_NUMBERS = [101, 102, 103, 104, 105, 106, 201, 202, 203, 204, 205, 206];
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
    if (!user || (phone.includes('@') ? user.email !== phone : user.phoneNumber !== phone)) throw Error('Verified owner required');
    const id = user.businessId;
    if (typeof id !== 'string' || !id || id.includes('/')) throw Error('Invalid mapping');
    const bizRef = db.doc(`businesses/${id}`);
    const licenseRef = db.doc(`businesses/${id}/settings/license`);
    const markerRef = db.doc(`businesses/${id}/settings/onboarding`);
    const historyRefs = HISTORY.map((name) => db.collection(`businesses/${id}/${name}`).limit(1));
    const [bizSnap, licenseSnap, markerSnap, roomsSnap, ...rest] = await Promise.all([
      tx.get(bizRef),
      tx.get(licenseRef),
      tx.get(markerRef),
      tx.get(db.collection(`businesses/${id}/rooms`).limit(1)),
      ...historyRefs.map((query) => tx.get(query)),
    ]);
    const historySnaps = rest;
    if (!bizSnap.exists || bizSnap.data().ownerUid !== uid) throw Error('Hotel owner mismatch');
    const biz = bizSnap.data();
    if (markerSnap.data()?.status === 'complete') {
      return {provisioned: false, reason: 'already-complete', businessId: id, roomsAdded: 0};
    }
    const operational = historySnaps.some((snap) => !snap.empty);
    if (biz.dataResetAt || operational || !isVerifiedNewAccount(biz, licenseSnap.exists, licenseSnap.data() || {})) {
      return {provisioned: false, reason: 'existing-hotel', businessId: id, roomsAdded: 0};
    }
    // Seed once, on the server, only for a genuinely new empty hotel.
    // Any existing room (including a tombstone) protects the owner's custom setup.
    const added = roomsSnap.empty ? DEFAULT_ROOM_NUMBERS.length : 0;
    if (added) {
      for (const roomNumber of DEFAULT_ROOM_NUMBERS) {
        tx.create(db.doc(`businesses/${id}/rooms/room_${roomNumber}`), {
          roomNumber, roomType: 'Standard', normalRent: 0, status: 'EMPTY',
          schemaVersion: 3, deleted: false,
          createdAt: Timestamp.fromMillis(now), updatedAt: Timestamp.fromMillis(now),
        });
      }
      tx.set(db.doc(`businesses/${id}/settings/sync`), {
        schemaVersion: 3, lastSyncAt: FieldValue.serverTimestamp(),
      }, {merge: true});
    }
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
      roomTemplateVersion: 1,
      completedAt: Timestamp.fromMillis(now),
    });
    tx.set(bizRef, {onboardingStatus: 'complete'}, {merge: true});
    return {provisioned: true, reason: 'initialized', businessId: id, roomsAdded: added};
  });
}

module.exports = {provisionHotel, isVerifiedNewAccount, TRIAL_MS, DEFAULT_ROOM_NUMBERS};
