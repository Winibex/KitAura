// functions/admin_abuse_monitor.js
//
// Step 22 — Abuse Monitor.
//
// Composite screen combining three triage signals:
//   1. High refusals — users with >= 3 refusals this cycle (5 = soft-block)
//   2. Hourly burst hitters — users currently at >= 10/20 hourly cap (Pro)
//   3. Cost outliers — users in the top 10% of 30-day spend
//
// Each user appearing in any signal is returned with all three metrics
// so the UI can show the full picture in one row.

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

const REFUSAL_THRESHOLD = 3;        // 3+ refusals = on the radar (5 = soft block)
const BURST_THRESHOLD = 10;          // 10+ of 20 hourly burst limit = heavy usage
const COST_OUTLIER_PERCENTILE = 0.9; // Top 10% of spenders

/** Batch-fetch user profile emails. */
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

exports.adminGetAbuseMonitor = onCall(
  { region: REGION, timeoutSeconds: 120 },
  withErrorReporting('adminGetAbuseMonitor', async (request) => {
    adminGuard(request);

    const db = admin.firestore();
    const now = new Date();
    const windowStart = new Date(now.getTime() - 30 * 24 * 60 * 60 * 1000);

    // ── Signal 1 + 2: scan subscription docs (refusals, hourly burst) ──
    // Subscription docs are at users/{uid}/data/subscription. We need a
    // collection-group query because there are many users.
    const subSnap = await db.collectionGroup('data').get();

    // Filter to subscription docs only (also matches 'preferences' which
    // shares the parent collection)
    const subs = subSnap.docs.filter((d) => d.id === 'subscription');

    // ── Signal 3: 30-day cost aggregation ─────────────────────────────
    const activitySnap = await db
      .collectionGroup('aiActivity')
      .where(
        'createdAt',
        '>=',
        admin.firestore.Timestamp.fromDate(windowStart)
      )
      .get();

    // Aggregate per-user spend
    const spendMap = new Map(); // uid -> totalCost
    activitySnap.docs.forEach((doc) => {
      const parent = doc.ref.parent.parent;
      if (!parent) return;
      const uid = parent.id;
      const cost = (doc.data().cost && doc.data().cost.totalCost) || 0;
      spendMap.set(uid, (spendMap.get(uid) || 0) + cost);
    });

    // Compute outlier threshold (top 10%)
    let outlierThreshold = 0;
    if (spendMap.size > 0) {
      const sortedSpend = Array.from(spendMap.values()).sort((a, b) => b - a);
      const idx = Math.floor(sortedSpend.length * (1 - COST_OUTLIER_PERCENTILE));
      outlierThreshold = sortedSpend[idx] || 0;
    }

    // ── Combine signals per user ──────────────────────────────────────
    // userInfo: { uid -> { plan, refusalCount, hourlyCount, hourlyResetAt,
    //                      monthlyCount, totalCost, signals: [...] } }
    const userInfo = new Map();

    function ensureUser(uid) {
      let info = userInfo.get(uid);
      if (!info) {
        info = {
          uid,
          plan: null,
          refusalCount: 0,
          hourlyCount: 0,
          hourlyResetAt: null,
          monthlyCount: 0,
          totalCost: 0,
          signals: [],
        };
        userInfo.set(uid, info);
      }
      return info;
    }

    // Signal 1+2 from subscription docs
    subs.forEach((doc) => {
      const parent = doc.ref.parent.parent; // users/{uid}
      if (!parent) return;
      const uid = parent.id;
      const d = doc.data();

      const refusalCount = d.editorAiRefusalCount || 0;
      const hourlyCount = d.editorAiHourlyCount || 0;
      const hourlyResetAt = d.editorAiHourlyResetAt
        ? d.editorAiHourlyResetAt.toDate()
        : null;
      const monthlyCount = d.editorAiCount || 0;

      // Hourly window: only count if still within the active 60-min window
      const hourlyActive = hourlyResetAt && hourlyResetAt > now;

      const triggered =
        refusalCount >= REFUSAL_THRESHOLD ||
        (hourlyActive && hourlyCount >= BURST_THRESHOLD);

      if (!triggered) return; // Only track users with at least one signal

      const info = ensureUser(uid);
      info.plan = d.plan || 'free';
      info.refusalCount = refusalCount;
      info.hourlyCount = hourlyActive ? hourlyCount : 0;
      info.hourlyResetAt = hourlyActive ? hourlyResetAt.toISOString() : null;
      info.monthlyCount = monthlyCount;

      if (refusalCount >= REFUSAL_THRESHOLD) {
        info.signals.push('refusals');
      }
      if (hourlyActive && hourlyCount >= BURST_THRESHOLD) {
        info.signals.push('burst');
      }
    });

    // Signal 3: cost outliers (only flag if above threshold AND threshold meaningful)
    if (outlierThreshold > 0.10) {
      // Only call it an outlier if the threshold is at least 10 cents —
      // avoids flagging every user when total usage is tiny.
      spendMap.forEach((spend, uid) => {
        if (spend >= outlierThreshold) {
          const info = ensureUser(uid);
          info.totalCost = spend;
          if (!info.signals.includes('costOutlier')) {
            info.signals.push('costOutlier');
          }
        }
      });
    }

    // Pull totalCost for any flagged users that didn't trip the cost signal
    userInfo.forEach((info, uid) => {
      if (info.totalCost === 0) {
        info.totalCost = spendMap.get(uid) || 0;
      }
    });

    // ── Hydrate plan for users only flagged by cost signal ────────────
    const needsPlan = [];
    userInfo.forEach((info, uid) => {
      if (info.plan === null) needsPlan.push(uid);
    });
    if (needsPlan.length > 0) {
      // Read subscription docs for these users directly
      await Promise.all(
        needsPlan.map(async (uid) => {
          try {
            const ss = await db.doc(`users/${uid}/data/subscription`).get();
            if (ss.exists) {
              const sd = ss.data();
              const info = userInfo.get(uid);
              info.plan = sd.plan || 'free';
              info.refusalCount = sd.editorAiRefusalCount || 0;
              info.monthlyCount = sd.editorAiCount || 0;
            }
          } catch (_) {
            // Non-fatal
          }
        })
      );
    }

    // ── Hydrate emails ────────────────────────────────────────────────
    const allUids = Array.from(userInfo.keys());
    const emailMap = await fetchUserEmails(db, allUids);

    // ── Build final response ranked by severity ──────────────────────
    const flagged = Array.from(userInfo.values()).map((info) => ({
      uid: info.uid,
      email: emailMap[info.uid] || null,
      plan: info.plan || 'free',
      refusalCount: info.refusalCount,
      hourlyCount: info.hourlyCount,
      hourlyResetAt: info.hourlyResetAt,
      monthlyCount: info.monthlyCount,
      totalCost: +info.totalCost.toFixed(6),
      signals: info.signals,
      severity: info.signals.length, // 1, 2, or 3 — more signals = higher severity
    }));

    // Rank: multiple signals first, then by refusal count, then by spend
    flagged.sort((a, b) => {
      if (b.severity !== a.severity) return b.severity - a.severity;
      if (b.refusalCount !== a.refusalCount) {
        return b.refusalCount - a.refusalCount;
      }
      return b.totalCost - a.totalCost;
    });

    // Summary counts
    const summary = {
      refusalUsers: flagged.filter((u) => u.signals.includes('refusals')).length,
      burstUsers: flagged.filter((u) => u.signals.includes('burst')).length,
      costOutlierUsers: flagged.filter((u) =>
        u.signals.includes('costOutlier')
      ).length,
      multiSignalUsers: flagged.filter((u) => u.severity >= 2).length,
    };

    return {
      flagged,
      summary,
      thresholds: {
        refusalThreshold: REFUSAL_THRESHOLD,
        burstThreshold: BURST_THRESHOLD,
        outlierThreshold: +outlierThreshold.toFixed(6),
        outlierPercentile: COST_OUTLIER_PERCENTILE,
      },
      windowStart: windowStart.toISOString(),
      windowEnd: now.toISOString(),
    };
  })
);
