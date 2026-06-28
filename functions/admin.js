// functions/admin.js
//
// Admin-only Cloud Functions for KitAura.
// All endpoints require the caller to have `admin: true` custom claim.
// Every mutation writes an audit-log entry to `adminActivity/{actionId}`.

const { onCall, HttpsError } = require('firebase-functions/v2/https');
const admin = require('firebase-admin');

const REGION = 'us-central1';

// ─── HELPERS ─────────────────────────────────────────────────────────────

/**
 * Throws permission-denied unless caller has `admin: true` custom claim.
 * Call this as the first line of every admin endpoint.
 */
function adminGuard(request) {
  if (!request.auth || request.auth.token.admin !== true) {
    throw new HttpsError('permission-denied', 'Admin access required.');
  }
}

/**
 * Append an audit log entry to `adminActivity`. Called by every mutation
 * endpoint, ideally inside the same write batch as the mutation itself.
 */
async function writeAdminActivity({
  adminUid,
  adminEmail,
  action,
  target,
  before,
  after,
  metadata,
}) {
  return admin.firestore().collection('adminActivity').add({
    adminUid,
    adminEmail: adminEmail || null,
    action,
    target,
    before: before || {},
    after: after || {},
    metadata: metadata || {},
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });
}

// ─── setAdminClaim ───────────────────────────────────────────────────────
//
// Grant or revoke the `admin: true` custom claim on a target user.
// Caller must already be an admin. You cannot revoke your own claim.

exports.setAdminClaim = onCall({ region: REGION }, async (request) => {
  adminGuard(request);

  const { targetUid, grant } = request.data || {};
  if (!targetUid || typeof targetUid !== 'string') {
    throw new HttpsError('invalid-argument', '`targetUid` (string) is required.');
  }
  if (typeof grant !== 'boolean') {
    throw new HttpsError('invalid-argument', '`grant` (boolean) is required.');
  }

  // Lookup target user
  let user;
  try {
    user = await admin.auth().getUser(targetUid);
  } catch (err) {
    throw new HttpsError('not-found', `No user with UID ${targetUid}.`);
  }

  // Prevent self-revoke
  if (!grant && request.auth.uid === targetUid) {
    throw new HttpsError(
      'failed-precondition',
      'You cannot revoke your own admin claim.'
    );
  }

  // Compute new claim set (preserve other claims, only touch admin)
  const beforeClaims = user.customClaims || {};
  const newClaims = { ...beforeClaims };
  if (grant) {
    newClaims.admin = true;
  } else {
    delete newClaims.admin;
  }

  await admin.auth().setCustomUserClaims(targetUid, newClaims);

  await writeAdminActivity({
    adminUid: request.auth.uid,
    adminEmail: request.auth.token.email,
    action: grant ? 'setAdminClaim' : 'revokeAdminClaim',
    target: {
      type: 'user',
      id: targetUid,
      label: user.email || targetUid,
    },
    before: { admin: beforeClaims.admin === true },
    after: { admin: grant },
  });

  return {
    success: true,
    targetUid,
    email: user.email || null,
    isAdmin: grant,
  };
});

// Exported for use by sibling admin modules
exports._helpers = { adminGuard, writeAdminActivity, REGION };
