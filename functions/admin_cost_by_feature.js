// functions/admin_cost_by_feature.js
//
// Step 21 — Cost by Feature.
//
// Aggregates the last 30 days of aiActivity (collection-group scan)
// grouped by `tool`. Returns both totals per tool (for the breakdown
// table) and a daily time series (for the stacked bar chart).
//
// Days with zero activity are filled with explicit zero entries so the
// frontend time axis is continuous.

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

// Friendly labels matched to the schema's `tool` values.
const TOOL_LABELS = {
  cv: 'CV (Compose & Refine)',
  coverLetter: 'Cover Letter (Compose & Refine)',
  proposal: 'Proposal (Compose & Refine)',
  linkedin: 'LinkedIn Generator',
  clientExtract: 'Client Builder — Extract',
  clientChat: 'Client Builder — Chat',
  editorAI: 'AI Assistant (Command-K)',
  spellcheck: 'AI Proofread',
};

// Stable order so the frontend can rely on slot positions if desired.
const KNOWN_TOOLS = Object.keys(TOOL_LABELS);

function dateKey(d) {
  // YYYY-MM-DD in UTC. Matches schema convention.
  return d.toISOString().slice(0, 10);
}

exports.adminGetCostByFeature = onCall(
  { region: REGION, timeoutSeconds: 120 },
  withErrorReporting('adminGetCostByFeature', async (request) => {
    adminGuard(request);

    const db = admin.firestore();
    const now = new Date();
    const windowStart = new Date(now.getTime() - 30 * 24 * 60 * 60 * 1000);

    // ── Single collection-group scan ──────────────────────────────────
    const snap = await db
      .collectionGroup('aiActivity')
      .where(
        'createdAt',
        '>=',
        admin.firestore.Timestamp.fromDate(windowStart)
      )
      .get();

    // ── Aggregate by tool ─────────────────────────────────────────────
    const perTool = new Map();
    // perDay: { 'YYYY-MM-DD': { [tool]: cost } }
    const perDay = new Map();
    let grandTotal = 0;
    let grandCalls = 0;

    snap.docs.forEach((doc) => {
      const d = doc.data();
      const rawTool = d.tool;
      if (!rawTool || !KNOWN_TOOLS.includes(rawTool)) return;

      const cost = (d.cost && d.cost.totalCost) || 0;
      const status = d.status || 'success';

      let agg = perTool.get(rawTool);
      if (!agg) {
        agg = {
          tool: rawTool,
          label: TOOL_LABELS[rawTool],
          totalCost: 0,
          callCount: 0,
          failureCount: 0,
          refusalCount: 0,
        };
        perTool.set(rawTool, agg);
      }
      agg.totalCost += cost;
      agg.callCount += 1;
      if (status === 'error') agg.failureCount += 1;
      if (status === 'refused') agg.refusalCount += 1;

      grandTotal += cost;
      grandCalls += 1;

      // Daily bucket
      const ts = d.createdAt;
      if (ts && typeof ts.toDate === 'function') {
        const key = dateKey(ts.toDate());
        let dayMap = perDay.get(key);
        if (!dayMap) {
          dayMap = {};
          perDay.set(key, dayMap);
        }
        dayMap[rawTool] = (dayMap[rawTool] || 0) + cost;
      }
    });

    // ── Build continuous 30-day series (zero-fill missing days) ──────
    const daily = [];
    const cursor = new Date(windowStart);
    cursor.setUTCHours(0, 0, 0, 0);
    while (cursor <= now) {
      const key = dateKey(cursor);
      const dayMap = perDay.get(key) || {};
      const byTool = {};
      for (const t of KNOWN_TOOLS) {
        byTool[t] = +(dayMap[t] || 0).toFixed(6);
      }
      daily.push({ date: key, byTool });
      cursor.setUTCDate(cursor.getUTCDate() + 1);
    }

    // ── Build features array sorted by spend desc ────────────────────
    const features = Array.from(perTool.values())
      .map((f) => ({
        tool: f.tool,
        label: f.label,
        totalCost: +f.totalCost.toFixed(6),
        callCount: f.callCount,
        failureCount: f.failureCount,
        refusalCount: f.refusalCount,
        sharePct:
          grandTotal > 0 ? +((f.totalCost / grandTotal) * 100).toFixed(2) : 0,
      }))
      .sort((a, b) => b.totalCost - a.totalCost);

    return {
      features,
      daily,
      grandTotal: +grandTotal.toFixed(6),
      grandCalls,
      windowStart: windowStart.toISOString(),
      windowEnd: now.toISOString(),
    };
  })
);
