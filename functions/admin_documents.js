// functions/admin_documents.js
//
// Step 23 — Documents List + Inspector.
//
// Two endpoints:
//   adminListDocuments — paginated cross-user list of one document type
//                         (cv | coverLetter | proposal), sorted by
//                         updatedAt desc. Cursor-based pagination.
//
//   adminGetDocument   — full Firestore doc data for a single document,
//                         joined with the owner's email.

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

// Map admin-facing type → Firestore subcollection name.
const TYPE_TO_COLLECTION = {
  cv: 'cvs',
  coverLetter: 'coverLetters',
  proposal: 'proposals',
};

/** Chunked email fetch by uid. */
async function fetchUserEmails(db, uids) {
  const unique = Array.from(new Set(uids)).filter(Boolean);
  if (unique.length === 0) return {};
  const map = {};
  const CHUNK = 30;
  for (let i = 0; i < unique.length; i += CHUNK) {
    const chunk = unique.slice(i, i + CHUNK);
    const snap = await db
      .collection('users')
      .where(admin.firestore.FieldPath.documentId(), 'in', chunk)
      .get();
    snap.docs.forEach((d) => {
      map[d.id] = d.data().email || null;
    });
  }
  return map;
}

// ─── adminListDocuments ──────────────────────────────────────────────────

exports.adminListDocuments = onCall(
  { region: REGION, timeoutSeconds: 60 },
  withErrorReporting('adminListDocuments', async (request) => {
    adminGuard(request);

    const data = request.data || {};
    const type = data.type || 'cv';
    const collection = TYPE_TO_COLLECTION[type];
    if (!collection) {
      throw new HttpsError(
        'invalid-argument',
        `Unknown type: ${type}. Must be cv, coverLetter, or proposal.`
      );
    }

    const limit = Math.min(Math.max(Number(data.limit) || 25, 5), 100);
    const cursor = data.cursor || null;

    const db = admin.firestore();
    let query = db
      .collectionGroup(collection)
      .orderBy('updatedAt', 'desc');

    if (cursor) {
      const cursorDate = new Date(cursor);
      if (!isNaN(cursorDate.getTime())) {
        query = query.startAfter(
          admin.firestore.Timestamp.fromDate(cursorDate)
        );
      }
    }

    query = query.limit(limit);
    const snap = await query.get();

    const rawItems = snap.docs.map((doc) => {
      const parent = doc.ref.parent.parent; // users/{uid}
      const uid = parent ? parent.id : null;
      return { doc, uid, data: doc.data() };
    });

    const emailMap = await fetchUserEmails(
      db,
      rawItems.map((r) => r.uid).filter(Boolean)
    );

    const documents = rawItems.map(({ doc, uid, data }) => {
      const items = Array.isArray(data.items) ? data.items : [];
      return {
        docId: doc.id,
        type,
        uid,
        ownerEmail: uid ? emailMap[uid] || null : null,
        title: data.title || '(untitled)',
        templateId: data.templateId || null,
        status: data.status || 'draft',
        isArchived: data.isArchived === true,
        exportCount: typeof data.exportCount === 'number'
          ? data.exportCount
          : 0,
        itemCount: items.length,
        lastExportedAt: toIso(data.lastExportedAt),
        createdAt: toIso(data.createdAt),
        updatedAt: toIso(data.updatedAt),
      };
    });

    const lastDoc = snap.docs.length > 0
      ? snap.docs[snap.docs.length - 1]
      : null;
    const nextCursor = lastDoc
      ? toIso(lastDoc.data().updatedAt)
      : null;

    return {
      documents,
      nextCursor,
      hasMore: snap.docs.length === limit,
    };
  })
);

// ─── adminGetDocument ────────────────────────────────────────────────────

exports.adminGetDocument = onCall(
  { region: REGION, timeoutSeconds: 30 },
  withErrorReporting('adminGetDocument', async (request) => {
    adminGuard(request);

    const data = request.data || {};
    const uid = (data.uid || '').toString();
    const type = (data.type || '').toString();
    const docId = (data.docId || '').toString();

    const collection = TYPE_TO_COLLECTION[type];
    if (!collection) {
      throw new HttpsError('invalid-argument', `Unknown type: ${type}`);
    }
    if (!uid || !docId) {
      throw new HttpsError('invalid-argument', 'uid and docId required');
    }

    const db = admin.firestore();
    const docSnap = await db
      .doc(`users/${uid}/${collection}/${docId}`)
      .get();
    if (!docSnap.exists) {
      throw new HttpsError('not-found', 'Document not found.');
    }
    const docData = docSnap.data();

    // Owner email
    const userSnap = await db.collection('users').doc(uid).get();
    const ownerEmail = userSnap.exists
      ? userSnap.data().email || null
      : null;

    // Stringify Firestore Timestamps to ISO for safe transport
    const sanitized = JSON.parse(JSON.stringify(docData, (key, value) => {
      if (value && typeof value === 'object' && typeof value.toDate === 'function') {
        return value.toDate().toISOString();
      }
      return value;
    }));

    return {
      docId,
      type,
      uid,
      ownerEmail,
      data: sanitized,
    };
  })
);
