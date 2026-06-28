// functions/admin_user_documents.js
//
// Returns one user's documents grouped by type: cvs, coverLetters,
// proposals. Sorted by updatedAt desc, capped at 50 per type.

const { onCall, HttpsError } = require('firebase-functions/v2/https');
const admin = require('firebase-admin');
const { adminGuard, REGION } = require('./admin')._helpers;

function withErrorReporting(fnName, handler) {
  return async (request) => {
    try {
      return await handler(request);
    } catch (err) {
      if (err && err.httpErrorCode) throw err;
      console.error(`${fnName} failed:`, (err && err.stack) || err);
      throw new HttpsError(
        'internal',
        (err && err.message) ? err.message : 'Unknown error'
      );
    }
  };
}

function toIso(value) {
  if (!value) return null;
  if (typeof value.toDate === 'function') return value.toDate().toISOString();
  if (value instanceof Date) return value.toISOString();
  return null;
}

function int(v) {
  return typeof v === 'number' ? v : 0;
}

function summarizeDoc(doc) {
  const d = doc.data();
  return {
    id: doc.id,
    title: d.title || '(untitled)',
    templateId: d.templateId || null,
    thumbnailUrl: d.thumbnailUrl || null,
    status: d.status || 'draft',
    isArchived: d.isArchived === true,
    exportCount: int(d.exportCount),
    lastExportedAt: toIso(d.lastExportedAt),
    createdAt: toIso(d.createdAt),
    updatedAt: toIso(d.updatedAt),
    selectedProfileName: d.selectedProfileName || null,
    selectedProfileId: d.selectedProfileId || null,
    linkedClientId: d.linkedClientId || null,
    linkedCvId: d.linkedCvId || null,
    targetCompany: d.targetCompany || null,
    targetRole: d.targetRole || null,
    clientName: d.clientName || null,
  };
}

exports.adminListUserDocuments = onCall(
  { region: REGION, timeoutSeconds: 30 },
  withErrorReporting('adminListUserDocuments', async (request) => {
    adminGuard(request);

    const targetUid = (request.data?.targetUid || '').toString().trim();
    if (!targetUid) {
      throw new HttpsError('invalid-argument', 'targetUid required.');
    }

    const db = admin.firestore();
    const userRef = db.collection('users').doc(targetUid);

    // Verify user exists for cleaner error
    const userSnap = await userRef.get();
    if (!userSnap.exists) {
      throw new HttpsError('not-found', 'User not found.');
    }

    const limit = 50;
    const [cvSnap, clSnap, propSnap] = await Promise.all([
      userRef
          .collection('cvs')
          .orderBy('updatedAt', 'desc')
          .limit(limit)
          .get(),
      userRef
          .collection('coverLetters')
          .orderBy('updatedAt', 'desc')
          .limit(limit)
          .get(),
      userRef
          .collection('proposals')
          .orderBy('updatedAt', 'desc')
          .limit(limit)
          .get(),
    ]);

    const cvs = cvSnap.docs.map(summarizeDoc);
    const coverLetters = clSnap.docs.map(summarizeDoc);
    const proposals = propSnap.docs.map(summarizeDoc);

    return {
      cvs,
      coverLetters,
      proposals,
      counts: {
        cvs: cvs.length,
        coverLetters: coverLetters.length,
        proposals: proposals.length,
        total: cvs.length + coverLetters.length + proposals.length,
      },
    };
  }),
);
