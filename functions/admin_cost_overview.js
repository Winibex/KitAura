// functions/admin_cost_overview.js
//
// Aggregates AI spend across all users for the last N days.
// Reads from the `aiActivity` collection group. For MVP we recompute
// on every call; later this should be cached in config/aggregateCache
// and refreshed hourly via a scheduled function.

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

function dateKeyUtc(d) {
  const y = d.getUTCFullYear();
  const m = String(d.getUTCMonth() + 1).padStart(2, '0');
  const day = String(d.getUTCDate()).padStart(2, '0');
  return `${y}-${m}-${day}`;
}

exports.adminGetCostOverview = onCall(
  { region: REGION, timeoutSeconds: 120 },
  withErrorReporting('adminGetCostOverview', async (request) => {
    adminGuard(request);

    const daysBack = Math.min(
      Math.max(Number(request.data?.daysBack) || 30, 1),
      90,
    );

    const dayMs = 24 * 60 * 60 * 1000;
    const now = Date.now();
    const startMs = now - daysBack * dayMs;
    const startDate = new Date(startMs);

    const db = admin.firestore();
    const snap = await db
      .collectionGroup('aiActivity')
      .where(
        'createdAt',
        '>=',
        admin.firestore.Timestamp.fromDate(startDate),
      )
      .get();

    const todayStart = now - dayMs;
    const weekStart = now - 7 * dayMs;
    const monthStart = now - 30 * dayMs;

    let todayCost = 0;
    let weekCost = 0;
    let monthCost = 0;
    let todayCalls = 0;
    let weekCalls = 0;
    let monthCalls = 0;
    let totalCalls = 0;
    let totalFailures = 0;
    let totalRefusals = 0;
    let totalCacheReadTokens = 0;
    let totalInputTokens = 0;
    let totalOutputTokens = 0;

    const byModel = {};
    const byTool = {};
    const byDay = {};

    snap.docs.forEach((doc) => {
      const d = doc.data();
      const cost =
        (d.cost && typeof d.cost.totalCost === 'number')
          ? d.cost.totalCost
          : 0;
      const ts = d.createdAt && typeof d.createdAt.toMillis === 'function'
        ? d.createdAt.toMillis()
        : 0;
      const model = d.model || 'unknown';
      const tool = d.tool || 'unknown';
      const tokens = d.tokens || {};
      const cacheRead =
        typeof tokens.cacheReadTokens === 'number'
          ? tokens.cacheReadTokens
          : 0;
      const inputTok =
        typeof tokens.inputTokens === 'number' ? tokens.inputTokens : 0;
      const outputTok =
        typeof tokens.outputTokens === 'number' ? tokens.outputTokens : 0;

      totalCalls += 1;
      if (d.status === 'error') totalFailures += 1;
      if (d.status === 'refused') totalRefusals += 1;
      totalCacheReadTokens += cacheRead;
      totalInputTokens += inputTok;
      totalOutputTokens += outputTok;

      if (ts >= todayStart) {
        todayCost += cost;
        todayCalls += 1;
      }
      if (ts >= weekStart) {
        weekCost += cost;
        weekCalls += 1;
      }
      if (ts >= monthStart) {
        monthCost += cost;
        monthCalls += 1;
      }

      if (!byModel[model]) byModel[model] = { cost: 0, count: 0 };
      byModel[model].cost += cost;
      byModel[model].count += 1;

      if (!byTool[tool]) byTool[tool] = { cost: 0, count: 0 };
      byTool[tool].cost += cost;
      byTool[tool].count += 1;

      const dKey = dateKeyUtc(new Date(ts));
      if (!byDay[dKey]) byDay[dKey] = { cost: 0, count: 0 };
      byDay[dKey].cost += cost;
      byDay[dKey].count += 1;
    });

    // Fill zero days
    const dailySpend = [];
    for (let i = daysBack - 1; i >= 0; i -= 1) {
      const d = new Date(now - i * dayMs);
      const key = dateKeyUtc(d);
      const entry = byDay[key] || { cost: 0, count: 0 };
      dailySpend.push({
        date: key,
        cost: entry.cost,
        count: entry.count,
      });
    }

    const byModelArr = Object.entries(byModel)
      .map(([k, v]) => ({ model: k, cost: v.cost, count: v.count }))
      .sort((a, b) => b.cost - a.cost);

    const byToolArr = Object.entries(byTool)
      .map(([k, v]) => ({ tool: k, cost: v.cost, count: v.count }))
      .sort((a, b) => b.cost - a.cost);

    // Cache savings estimate: cache reads cost 10% of regular input.
    // Saved = cacheReadTokens * 0.9 * sonnetInputRate / 1M.
    // Hard-coded Sonnet rate ($3/MTok) for an approximate number.
    const cacheSavings = (totalCacheReadTokens / 1_000_000) * 3 * 0.9;

    return {
      daysBack,
      refreshedAt: new Date().toISOString(),
      totals: {
        today: todayCost,
        week: weekCost,
        month: monthCost,
      },
      callCounts: {
        today: todayCalls,
        week: weekCalls,
        month: monthCalls,
      },
      totalCalls,
      totalFailures,
      totalRefusals,
      tokens: {
        input: totalInputTokens,
        output: totalOutputTokens,
        cacheRead: totalCacheReadTokens,
      },
      cacheSavings,
      dailySpend,
      byModel: byModelArr,
      byTool: byToolArr,
    };
  }),
);
