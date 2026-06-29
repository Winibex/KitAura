// functions/admin_cost_by_user.js
//
// Step 20 — Cost by User.
//
// Aggregates the last 30 days of aiActivity (collection-group scan) by user,
// joins emails + current plan, ranks by chosen sort key, and returns a page.
//
// Same data source as adminGetCostOverview — different slicing. Once the
// deferred `config/aggregateCache` lands, both functions will switch to
// reading from it instead of scanning aiActivity on every call.

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

/** Chunked batch-read user docs for email + plan. */
async function fetchUserMeta(db, uids) {
  const unique = Array.from(new Set(uids)).filter(Boolean);
  if (unique.length === 0) return {};
  const meta = {};
  const CHUNK = 30;
  for (let i = 0; i < unique.length; i += CHUNK) {
    const chunk = unique.slice(i, i + CHUNK);
    const snap = await db
      .collection('users')
      .where(admin.firestore.FieldPath.documentId(), 'in', chunk)
      .get();
    snap.docs.forEach((d) => {
      meta[d.id] = { email: d.data().email || null, plan: null };
    });
  }

  // Pull current plan from subscription doc per user (parallelized).
  await Promise.all(
    unique.map(async (uid) => {
      try {
        const subSnap = await db.doc(`users/${uid}/data/subscription`).get();
        if (subSnap.exists) {
          if (!meta[uid]) meta[uid] = { email: null, plan: null };
          meta[uid].plan = subSnap.data().plan || 'free';
        }
      } catch (_) {
        // Non-fatal — leave plan null
      }
    })
  );

  return meta;
}

exports.adminGetCostByUser = onCall(
  { region: REGION, timeoutSeconds: 120 },
  withErrorReporting('adminGetCostByUser', async (request) => {
    adminGuard(request);

    const data = request.data || {};
    const page = Math.max(1, Number(data.page) || 1);
    const pageSize = Math.min(Math.max(Number(data.pageSize) || 25, 5), 100);
    const sortBy = ['spend', 'refusalRate', 'callCount'].includes(data.sortBy)
      ? data.sortBy
      : 'spend';

    const db = admin.firestore();
    const now = new Date();
    const windowStart = new Date(now.getTime() - 30 * 24 * 60 * 60 * 1000);

    // ── Single collection-group scan, last 30 days ────────────────────
    const snap = await db
      .collectionGroup('aiActivity')
      .where(
        'createdAt',
        '>=',
        admin.firestore.Timestamp.fromDate(windowStart)
      )
      .get();

    // ── Aggregate per user ────────────────────────────────────────────
    const perUser = new Map(); // uid -> aggregates
    snap.docs.forEach((doc) => {
      const parent = doc.ref.parent.parent;
      if (!parent) return;
      const uid = parent.id;
      const d = doc.data();
      const cost = (d.cost && d.cost.totalCost) || 0;
      const status = d.status || 'success';

      let agg = perUser.get(uid);
      if (!agg) {
        agg = {
          uid,
          totalCost: 0,
          callCount: 0,
          failureCount: 0,
          refusalCount: 0,
          lastActivityAt: null,
        };
        perUser.set(uid, agg);
      }
      agg.totalCost += cost;
      agg.callCount += 1;
      if (status === 'error') agg.failureCount += 1;
      if (status === 'refused') agg.refusalCount += 1;

      const ts = d.createdAt;
      if (ts && typeof ts.toDate === 'function') {
        const t = ts.toDate().getTime();
        if (!agg.lastActivityAt || t > agg.lastActivityAt) {
          agg.lastActivityAt = t;
        }
      }
    });

    // ── Sort ──────────────────────────────────────────────────────────
    let rows = Array.from(perUser.values()).map((r) => ({
      ...r,
      refusalRate: r.callCount > 0 ? r.refusalCount / r.callCount : 0,
    }));

    const sortFns = {
      spend: (a, b) => b.totalCost - a.totalCost,
      callCount: (a, b) => b.callCount - a.callCount,
      refusalRate: (a, b) => {
        // Push zero-refusal users to the bottom; among refusers, rank by rate
        // then by absolute count so a 1/1 user doesn't outrank a 9/10 user.
        if (b.refusalRate !== a.refusalRate) {
          return b.refusalRate - a.refusalRate;
        }
        return b.refusalCount - a.refusalCount;
      },
    };
    rows.sort(sortFns[sortBy]);

    const totalUsers = rows.length;
    const totalPages = Math.max(1, Math.ceil(totalUsers / pageSize));
    const safePage = Math.min(page, totalPages);
    const startIdx = (safePage - 1) * pageSize;
    const pageRows = rows.slice(startIdx, startIdx + pageSize);

    // ── Hydrate emails + plans only for the current page ──────────────
    const meta = await fetchUserMeta(db, pageRows.map((r) => r.uid));

    const users = pageRows.map((r) => ({
      uid: r.uid,
      email: (meta[r.uid] && meta[r.uid].email) || null,
      plan: (meta[r.uid] && meta[r.uid].plan) || null,
      totalCost: +r.totalCost.toFixed(6),
      callCount: r.callCount,
      failureCount: r.failureCount,
      refusalCount: r.refusalCount,
      refusalRate: +r.refusalRate.toFixed(4),
      lastActiveAt: r.lastActivityAt
        ? new Date(r.lastActivityAt).toISOString()
        : null,
    }));

    return {
      users,
      totalUsers,
      page: safePage,
      pageSize,
      totalPages,
      sortBy,
      windowStart: windowStart.toISOString(),
      windowEnd: now.toISOString(),
    };
  })
);
