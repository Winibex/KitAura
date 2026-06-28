// functions/admin_users.js
//
// User-management Cloud Functions: list + detail.
// Wraps function bodies in try/catch so client sees real errors,
// not the generic "internal".

const { onCall, HttpsError } = require('firebase-functions/v2/https');
const admin = require('firebase-admin');
const { adminGuard, REGION } = require('./admin')._helpers;

function formatMonth(date) {
  const y = date.getFullYear();
  const m = String(date.getMonth() + 1).padStart(2, '0');
  return `${y}-${m}`;
}

/**
 * Normalize any date-ish value to an ISO string. Handles:
 * - Firestore Timestamp (.toDate)
 * - RFC date string (e.g. "Mon, 26 Jun 2026 18:52:00 GMT" — Firebase Auth metadata)
 * - ISO 8601 string (returned as-is)
 * - Date object
 * - null/undefined → null
 */
function toIso(value) {
  if (!value) return null;
  if (typeof value === 'object' && typeof value.toDate === 'function') {
    try { return value.toDate().toISOString(); }
    catch (_) { return null; }
  }
  if (value instanceof Date) return value.toISOString();
  if (typeof value === 'string') {
    const d = new Date(value);
    return isNaN(d.getTime()) ? null : d.toISOString();
  }
  return null;
}

/**
 * Recursively convert Firestore Timestamps in any nested structure to
 * ISO strings. Safe to call on `null`, primitives, arrays, or objects.
 */
function convertTimestamps(obj) {
  if (obj === null || obj === undefined) return obj;
  if (typeof obj !== 'object') return obj;
  if (obj.toDate && typeof obj.toDate === 'function') {
    try { return obj.toDate().toISOString(); }
    catch (_) { return null; }
  }
  if (Array.isArray(obj)) return obj.map(convertTimestamps);
  const out = {};
  for (const [k, v] of Object.entries(obj)) {
    out[k] = convertTimestamps(v);
  }
  return out;
}

function serializeDoc(snap) {
  if (!snap.exists) return null;
  return convertTimestamps(snap.data());
}

async function fetchAllAuthUsers(maxUsers = 1000) {
  const all = [];
  let pageToken;
  do {
    const result = await admin.auth().listUsers(1000, pageToken);
    all.push(...result.users);
    pageToken = result.pageToken;
    if (all.length >= maxUsers) break;
  } while (pageToken);
  return all.slice(0, maxUsers);
}

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

// ─── adminListUsers ──────────────────────────────────────────────────────

exports.adminListUsers = onCall(
  { region: REGION, timeoutSeconds: 60 },
  withErrorReporting('adminListUsers', async (request) => {
    adminGuard(request);

    const {
      page = 0,
      pageSize = 50,
      search = '',
      planFilter = 'all',
      sortBy = 'signupDesc',
    } = request.data || {};

    const pageNum = Math.max(0, Number(page) || 0);
    const sizeNum = Math.min(100, Math.max(10, Number(pageSize) || 50));
    const searchLower = String(search).trim().toLowerCase();

    const authUsers = await fetchAllAuthUsers();

    let filtered = authUsers;
    if (searchLower) {
      filtered = authUsers.filter((u) => {
        const email = (u.email || '').toLowerCase();
        const uid = u.uid.toLowerCase();
        return email.includes(searchLower) || uid.includes(searchLower);
      });
    }

    const db = admin.firestore();
    const currentMonth = formatMonth(new Date());

    const enriched = await Promise.all(
      filtered.map(async (authUser) => {
        const uid = authUser.uid;
        const [profileSnap, subSnap, summarySnap, monthlySnap] =
            await Promise.all([
          db.doc(`users/${uid}`).get(),
          db.doc(`users/${uid}/data/subscription`).get(),
          db.doc(`users/${uid}/analytics/summary`).get(),
          db.doc(`users/${uid}/analytics/${currentMonth}`).get(),
        ]);

        const profile = profileSnap.exists ? profileSnap.data() : {};
        const sub = subSnap.exists ? subSnap.data() : {};
        const summary = summarySnap.exists ? summarySnap.data() : {};
        const monthly = monthlySnap.exists ? monthlySnap.data() : {};

        const signupAt =
          toIso(profile.createdAt) ||
          toIso(authUser.metadata.creationTime);
        const lastActiveAt = toIso(summary.lastActiveAt);

        const plan = sub.plan || 'free';
        const docCount =
          (Number(sub.cvCount) || 0) +
          (Number(sub.coverLetterCount) || 0) +
          (Number(sub.proposalCount) || 0);

        return {
          uid,
          email: authUser.email || null,
          displayName: profile.displayName || authUser.displayName || null,
          plan,
          trialActive: sub.trialActive === true,
          signupAt,
          lastActiveAt,
          docCount,
          mtdSpend: Number(monthly.totalCost) || 0,
        };
      })
    );

    let result = enriched;
    if (planFilter !== 'all') {
      result = enriched.filter((u) => u.plan === planFilter);
    }

    result.sort((a, b) => {
      switch (sortBy) {
        case 'signupAsc':
          return (a.signupAt || '').localeCompare(b.signupAt || '');
        case 'signupDesc':
          return (b.signupAt || '').localeCompare(a.signupAt || '');
        case 'lastActive':
          return (b.lastActiveAt || '').localeCompare(a.lastActiveAt || '');
        case 'spend':
          return (b.mtdSpend || 0) - (a.mtdSpend || 0);
        case 'docs':
          return (b.docCount || 0) - (a.docCount || 0);
        default:
          return 0;
      }
    });

    const total = result.length;
    const start = pageNum * sizeNum;
    const items = result.slice(start, start + sizeNum);

    return {
      items,
      total,
      page: pageNum,
      pageSize: sizeNum,
      hasMore: start + items.length < total,
    };
  })
);

// ─── adminGetUserOverview ────────────────────────────────────────────────

exports.adminGetUserOverview = onCall(
  { region: REGION, timeoutSeconds: 30 },
  withErrorReporting('adminGetUserOverview', async (request) => {
    adminGuard(request);

    const { targetUid } = request.data || {};
    if (!targetUid || typeof targetUid !== 'string') {
      throw new HttpsError(
        'invalid-argument',
        '`targetUid` (string) is required.'
      );
    }

    let authUser;
    try {
      authUser = await admin.auth().getUser(targetUid);
    } catch (_) {
      throw new HttpsError('not-found', `No user with UID ${targetUid}.`);
    }

    const db = admin.firestore();
    const currentMonth = formatMonth(new Date());

    const [profileSnap, subSnap, summarySnap, monthlySnap] =
        await Promise.all([
      db.doc(`users/${targetUid}`).get(),
      db.doc(`users/${targetUid}/data/subscription`).get(),
      db.doc(`users/${targetUid}/analytics/summary`).get(),
      db.doc(`users/${targetUid}/analytics/${currentMonth}`).get(),
    ]);

    return {
      uid: targetUid,
      currentMonth,
      auth: {
        email: authUser.email || null,
        displayName: authUser.displayName || null,
        photoURL: authUser.photoURL || null,
        emailVerified: authUser.emailVerified === true,
        disabled: authUser.disabled === true,
        providerIds:
          (authUser.providerData || []).map((p) => p.providerId),
        creationTime: toIso(authUser.metadata.creationTime),
        lastSignInTime: toIso(authUser.metadata.lastSignInTime),
        customClaims: authUser.customClaims || {},
      },
      profile: serializeDoc(profileSnap),
      subscription: serializeDoc(subSnap),
      summary: serializeDoc(summarySnap),
      monthly: serializeDoc(monthlySnap),
    };
  })
);