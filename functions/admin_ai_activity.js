// functions/admin_ai_activity.js
//
// Cross-user AI activity feed. Uses a collectionGroup query on
// `aiActivity`, ordered by createdAt desc. Cursor-based pagination by
// passing the last item's createdAt ISO string.

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
  try {
    const d = new Date(value);
    if (!isNaN(d.getTime())) return d.toISOString();
  } catch (_) {}
  return null;
}

function num(v) {
  return typeof v === 'number' ? v : 0;
}

/**
 * Batch-fetch user emails for a list of UIDs. Firestore IN queries
 * are limited to 30 ids per call, so we chunk.
 */
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

exports.adminListAiActivity = onCall(
  { region: REGION, timeoutSeconds: 60 },
  withErrorReporting('adminListAiActivity', async (request) => {
    adminGuard(request);

    const data = request.data || {};
    const limit = Math.min(Math.max(Number(data.limit) || 50, 1), 200);
    const cursor = data.cursor || null; // ISO string of last item's createdAt
    const startDate = data.startDate || null; // ISO string, inclusive lower bound
    const statusFilter = data.statusFilter || null; // 'success' | 'error' | 'refused' | 'cancelled'

    const userId = (data.userId || '').toString().trim() || null;

    const db = admin.firestore();
    let query;
    if (userId) {
      query = db
        .collection('users')
        .doc(userId)
        .collection('aiActivity')
        .orderBy('createdAt', 'desc');
    } else {
      query = db.collectionGroup('aiActivity').orderBy('createdAt', 'desc');
    }

    if (cursor) {
      const cursorDate = new Date(cursor);
      if (!isNaN(cursorDate.getTime())) {
        query = query.startAfter(admin.firestore.Timestamp.fromDate(cursorDate));
      }
    }
    if (startDate) {
      const startD = new Date(startDate);
      if (!isNaN(startD.getTime())) {
        query = query.where(
          'createdAt',
          '>=',
          admin.firestore.Timestamp.fromDate(startD)
        );
      }
    }

    if (statusFilter) {
      query = query.where('status', '==', statusFilter);
    }

    query = query.limit(limit);

    const snap = await query.get();

    const rawItems = snap.docs.map((doc) => {
      const resolvedUid = userId
          ? userId
          : (doc.ref.parent.parent ? doc.ref.parent.parent.id : null);
      return { doc, userId: resolvedUid, data: doc.data() };
    });

    let emailMap = {};
    if (userId) {
      // Single-user scope — fetch one email
      const userSnap = await db.collection('users').doc(userId).get();
      emailMap[userId] = userSnap.exists ? (userSnap.data().email || null) : null;
    } else {
      const uids = rawItems.map((r) => r.userId).filter(Boolean);
      emailMap = await fetchUserEmails(db, uids);
    }

    const items = rawItems.map(({ doc, userId, data }) => {
      const tokens = data.tokens || {};
      const cost = data.cost || {};
      return {
        id: doc.id,
        userId,
        userEmail: userId ? emailMap[userId] || null : null,
        tool: data.tool || null,
        type: data.type || null,
        status: data.status || null,
        sectionType: data.sectionType || null,
        documentId: data.documentId || null,
        documentTitle: data.documentTitle || null,
        templateId: data.templateId || null,
        model: data.model || null,
        totalCost: num(cost.totalCost),
        inputTokens: num(tokens.inputTokens),
        outputTokens: num(tokens.outputTokens),
        cacheReadTokens: num(tokens.cacheReadTokens),
        cacheCreationTokens: num(tokens.cacheCreationTokens),
        errorMessage: data.errorMessage || null,
        refusalReason:
          (data.rewriteOptions && data.rewriteOptions.refusalReason) ||
          data.refusalReason ||
          null,
        editorAiOps: Array.isArray(data.editorAiOps) ? data.editorAiOps : null,
        rewriteMode:
          (data.rewriteOptions && data.rewriteOptions.mode) || null,
        durationMs: num(data.durationMs),
        createdAt: toIso(data.createdAt),
      };
    });

    const lastDoc = snap.docs.length > 0
      ? snap.docs[snap.docs.length - 1]
      : null;
    const nextCursor = lastDoc
      ? toIso(lastDoc.data().createdAt)
      : null;

    return {
      items,
      nextCursor,
      hasMore: snap.docs.length === limit,
    };
  })
);
