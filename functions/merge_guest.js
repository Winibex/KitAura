// functions/merge_guest.js
//
// Called when an anonymous user links with a credential that already exists.
// Copies the guest's documents into the existing account, then cleans up.
//
// Deploy: firebase deploy --only functions:mergeGuestData

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");

const REGION = "us-central1";

// Collections to migrate (user-visible data only)
const DOC_COLLECTIONS = ["cvs", "coverLetters", "proposals"];
const OTHER_COLLECTIONS = ["aiProfiles", "clientProfiles", "linkedinSummaries"];

exports.mergeGuestData = onCall(
  { region: REGION, timeoutSeconds: 60 },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Must be signed in");
    }

    const targetUid = request.auth.uid; // existing account (caller)
    const { fromUid } = request.data || {};

    if (!fromUid || typeof fromUid !== "string") {
      throw new HttpsError("invalid-argument", "fromUid is required");
    }
    if (fromUid === targetUid) {
      throw new HttpsError("invalid-argument", "Cannot merge with self");
    }

    const db = admin.firestore();
    const results = { copied: 0, collections: {} };

    // ── 1. Copy documents from guest → existing account ─────────────
    for (const col of [...DOC_COLLECTIONS, ...OTHER_COLLECTIONS]) {
      const guestDocs = await db
        .collection(`users/${fromUid}/${col}`)
        .get();

      let count = 0;
      for (const doc of guestDocs.docs) {
        const data = doc.data();
        // Update userId field if present
        if (data.userId) data.userId = targetUid;
        await db
          .collection(`users/${targetUid}/${col}`)
          .add(data);
        count++;
      }
      results.collections[col] = count;
      results.copied += count;
    }

    // ── 2. Update subscription doc counters on target ───────────────
    if (results.copied > 0) {
      const subRef = db.doc(`users/${targetUid}/data/subscription`);
      const subSnap = await subRef.get();
      if (subSnap.exists) {
        const update = {};
        const cvCount = results.collections["cvs"] || 0;
        const clCount = results.collections["coverLetters"] || 0;
        const propCount = results.collections["proposals"] || 0;

        if (cvCount > 0)
          update.cvCount = admin.firestore.FieldValue.increment(cvCount);
        if (clCount > 0)
          update.coverLetterCount =
            admin.firestore.FieldValue.increment(clCount);
        if (propCount > 0)
          update.proposalCount =
            admin.firestore.FieldValue.increment(propCount);

        if (Object.keys(update).length > 0) {
          await subRef.update(update);
        }
      }
    }

    // ── 3. Write transaction entry ──────────────────────────────────
    await db.collection(`users/${targetUid}/transactions`).add({
      id: null, // auto-generated
      type: "guestMerge",
      tool: null,
      documentId: fromUid,
      documentTitle: `Merged ${results.copied} docs from guest session`,
      metadata: results.collections,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    // ── 4. Clean up guest data ──────────────────────────────────────
    // Delete all subcollections
    for (const col of [
      ...DOC_COLLECTIONS,
      ...OTHER_COLLECTIONS,
      "aiActivity",
      "transactions",
    ]) {
      const guestDocs = await db
        .collection(`users/${fromUid}/${col}`)
        .get();
      const batch = db.batch();
      for (const doc of guestDocs.docs) {
        batch.delete(doc.ref);
      }
      if (guestDocs.docs.length > 0) await batch.commit();
    }

    // Delete data subcollection docs
    const dataDocs = await db.collection(`users/${fromUid}/data`).get();
    for (const doc of dataDocs.docs) {
      await doc.ref.delete();
    }

    // Delete analytics docs
    const analyticsDocs = await db
      .collection(`users/${fromUid}/analytics`)
      .get();
    for (const doc of analyticsDocs.docs) {
      await doc.ref.delete();
    }

    // Delete user profile doc
    await db.doc(`users/${fromUid}`).delete();

    // Delete the anonymous Auth user
    try {
      await admin.auth().deleteUser(fromUid);
    } catch (e) {
      // Non-critical — might already be deleted
      console.warn(`Failed to delete auth user ${fromUid}:`, e.message);
    }

    return { success: true, ...results };
  }
);