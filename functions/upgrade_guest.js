// Add to functions/index.js (or import from functions/upgrade_guest.js)
//
// Called after linkWithCredential succeeds. Upgrades plan from 'guest' to 'free'
// and updates the user profile with real email/displayName.
//
// Deploy: firebase deploy --only functions:upgradeGuestToFree

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");

const REGION = "us-central1";

exports.upgradeGuestToFree = onCall(
  { region: REGION, timeoutSeconds: 10 },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Must be signed in");
    }

    const uid = request.auth.uid;
    const db = admin.firestore();
    const subRef = db.doc(`users/${uid}/data/subscription`);
    const userRef = db.doc(`users/${uid}`);

    const subSnap = await subRef.get();
    if (!subSnap.exists) {
      throw new HttpsError("not-found", "No subscription doc found");
    }

    const currentPlan = subSnap.data().plan;
    if (currentPlan !== "guest") {
      // Already upgraded or was never a guest — no-op
      return { success: true, plan: currentPlan };
    }

    // Upgrade plan + extend cycle to 30 days from now
    const now = admin.firestore.Timestamp.now();
    const cycleEnd = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000);

    const batch = db.batch();

    batch.update(subRef, {
      plan: "free",
      cycleStartDate: now,
      cycleEndDate: admin.firestore.Timestamp.fromDate(cycleEnd),
      lastResetDate: now,
    });

    // Update user profile with real identity if provided
    const { displayName, email, phone } = request.data || {};
    const profileUpdate = { updatedAt: now };
    if (displayName) profileUpdate.displayName = displayName;
    if (email) profileUpdate.email = email;
    if (phone) profileUpdate.phone = phone;
    batch.update(userRef, profileUpdate);

    await batch.commit();

    return { success: true, plan: "free" };
  }
);