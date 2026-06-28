// functions/admin_dashboard.js
//
// Read-only Cloud Functions for the admin dashboard. Fetches KPI numbers
// across all users in a single call. Optimized for correctness, not for
// scale — at large user counts (>1000) we'll cache results in
// `config/aggregateCache` and refresh hourly (Phase A5).

const { onCall, HttpsError } = require('firebase-functions/v2/https');
const admin = require('firebase-admin');
const { adminGuard, REGION } = require('./admin')._helpers;

function formatMonth(date) {
  const y = date.getFullYear();
  const m = String(date.getMonth() + 1).padStart(2, '0');
  return `${y}-${m}`;
}

exports.adminGetDashboardKpis = onCall(
  { region: REGION, timeoutSeconds: 60 },
  async (request) => {
    adminGuard(request);

    const db = admin.firestore();
    const now = new Date();
    const dayAgo = new Date(now.getTime() - 24 * 60 * 60 * 1000);
    const weekAgo = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000);
    const currentMonth = formatMonth(now);

    // ─── Step 1: List all users ─────────────────────────────────────────
    const usersSnap = await db.collection('users').get();
    const totalUsers = usersSnap.size;

    // ─── Step 2: Per-user aggregations in parallel ──────────────────────
    let activeToday = 0;
    let signupsThisWeek = 0;
    let activeTrials = 0;
    let mtdSpend = 0;
    let totalInputTokens = 0;
    let totalCacheReadTokens = 0;
    const userMonthSpend = new Map();

    await Promise.all(
      usersSnap.docs.map(async (userDoc) => {
        const uid = userDoc.id;
        const userData = userDoc.data() || {};

        // Signup this week
        const createdAt = userData.createdAt;
        if (createdAt && createdAt.toDate && createdAt.toDate() > weekAgo) {
          signupsThisWeek++;
        }

        const [summarySnap, monthlySnap, subSnap] = await Promise.all([
          db.doc(`users/${uid}/analytics/summary`).get(),
          db.doc(`users/${uid}/analytics/${currentMonth}`).get(),
          db.doc(`users/${uid}/data/subscription`).get(),
        ]);

        // Active today
        if (summarySnap.exists) {
          const s = summarySnap.data() || {};
          if (s.lastActiveAt && s.lastActiveAt.toDate &&
              s.lastActiveAt.toDate() > dayAgo) {
            activeToday++;
          }
        }

        // MTD spend
        if (monthlySnap.exists) {
          const m = monthlySnap.data() || {};
          const cost = Number(m.totalCost) || 0;
          mtdSpend += cost;
          totalInputTokens += Number(m.totalInputTokens) || 0;
          totalCacheReadTokens += Number(m.totalCacheReadTokens) || 0;
          if (cost > 0) userMonthSpend.set(uid, cost);
        }

        // Active trial
        if (subSnap.exists) {
          const sub = subSnap.data() || {};
          if (sub.plan === 'trial' && sub.trialActive === true) {
            activeTrials++;
          }
        }
      })
    );

    // ─── Step 3: 24h failures and refusals (collection group) ───────────
    let failures24h = 0;
    let refusals24h = 0;
    try {
      const [failuresSnap, refusalsSnap] = await Promise.all([
        db
          .collectionGroup('aiActivity')
          .where('status', '==', 'error')
          .where('createdAt', '>', dayAgo)
          .count()
          .get(),
        db
          .collectionGroup('aiActivity')
          .where('status', '==', 'refused')
          .where('createdAt', '>', dayAgo)
          .count()
          .get(),
      ]);
      failures24h = failuresSnap.data().count;
      refusals24h = refusalsSnap.data().count;
    } catch (e) {
      // If the collection group index doesn't exist yet, return 0s
      // (Firestore will log a creation link in the console)
      console.warn('aiActivity collection group query failed:', e.message);
    }

    // ─── Step 4: Top 5 spenders this month + email lookup ───────────────
    const topEntries = [...userMonthSpend.entries()]
      .sort((a, b) => b[1] - a[1])
      .slice(0, 5);

    let topSpenders = [];
    if (topEntries.length > 0) {
      const lookup = await admin.auth().getUsers(
        topEntries.map(([uid]) => ({ uid }))
      );
      const uidToEmail = new Map(
        lookup.users.map((u) => [u.uid, u.email || null])
      );
      topSpenders = topEntries.map(([uid, spend]) => ({
        uid,
        email: uidToEmail.get(uid),
        spend,
      }));
    }

    // ─── Step 5: Derived metrics ─────────────────────────────────────────
    const cacheHitRate =
      totalInputTokens + totalCacheReadTokens > 0
        ? totalCacheReadTokens / (totalInputTokens + totalCacheReadTokens)
        : 0;

    return {
      totalUsers,
      activeToday,
      signupsThisWeek,
      activeTrials,
      mtdSpend,
      failures24h,
      refusals24h,
      cacheHitRate,
      topSpenders,
      generatedAt: new Date().toISOString(),
    };
  }
);
