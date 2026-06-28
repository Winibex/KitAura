// functions/admin_actions.js
//
// Mutation endpoints for user management. Every write happens in a
// Firestore batch alongside an `adminActivity` audit-log entry, so an
// admin action and its audit record are atomic.

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

function tsFromDate(date) {
  return admin.firestore.Timestamp.fromDate(date);
}

/**
 * Fetch the target user's subscription doc, profile doc, and Auth record
 * (used for the audit log label). Throws not-found if any are missing.
 */
async function loadTarget(targetUid) {
  const db = admin.firestore();
  const subRef = db.doc(`users/${targetUid}/data/subscription`);
  const userRef = db.doc(`users/${targetUid}`);

  const [subSnap, userSnap] = await Promise.all([
    subRef.get(),
    userRef.get(),
  ]);

  if (!subSnap.exists) {
    throw new HttpsError(
      'not-found',
      `No subscription document for user ${targetUid}.`
    );
  }

  let authRecord;
  try {
    authRecord = await admin.auth().getUser(targetUid);
  } catch (_) {
    throw new HttpsError('not-found', `No auth user ${targetUid}.`);
  }

  return {
    subRef,
    userRef,
    sub: subSnap.data() || {},
    profile: userSnap.exists ? userSnap.data() : {},
    label: authRecord.email || targetUid,
  };
}

function assertNotSelf(request, targetUid) {
  if (request.auth.uid === targetUid) {
    throw new HttpsError(
      'failed-precondition',
      'You cannot perform this action on your own account.'
    );
  }
}

// ─── adminSetPlan ────────────────────────────────────────────────────────
// Grant Pro (plan='pro', cycleDays default 30) or Revoke (plan='free').

exports.adminSetPlan = onCall(
  { region: REGION, timeoutSeconds: 30 },
  withErrorReporting('adminSetPlan', async (request) => {
    adminGuard(request);

    const { targetUid, plan, cycleDays = 30 } = request.data || {};
    if (!targetUid) {
      throw new HttpsError('invalid-argument', '`targetUid` required.');
    }
    if (!['free', 'pro'].includes(plan)) {
      throw new HttpsError(
        'invalid-argument',
        '`plan` must be "free" or "pro".'
      );
    }
    assertNotSelf(request, targetUid);

    const cycleDaysNum =
      Math.max(1, Math.min(3650, Number(cycleDays) || 30));
    const { subRef, sub, label } = await loadTarget(targetUid);

    const db = admin.firestore();
    const nowDate = new Date();
    const serverNow = admin.firestore.FieldValue.serverTimestamp();

    let update;
    if (plan === 'pro') {
      const endDate = new Date(
        nowDate.getTime() + cycleDaysNum * 86400000
      );
      update = {
        plan: 'pro',
        subscriptionStartDate: serverNow,
        subscriptionEndDate: tsFromDate(endDate),
        cycleStartDate: serverNow,
        cycleEndDate: tsFromDate(endDate),
        trialActive: false,
      };
    } else {
      update = {
        plan: 'free',
        trialActive: false,
        subscriptionStartDate: null,
        subscriptionEndDate: null,
      };
    }

    const batch = db.batch();
    batch.update(subRef, update);

    batch.set(db.collection('adminActivity').doc(), {
      adminUid: request.auth.uid,
      adminEmail: request.auth.token.email || null,
      action: 'adminSetPlan',
      target: { type: 'user', id: targetUid, label },
      before: {
        plan: sub.plan || 'free',
        trialActive: sub.trialActive === true,
      },
      after: { plan, cycleDays: plan === 'pro' ? cycleDaysNum : null },
      metadata: {},
      createdAt: serverNow,
    });

    batch.set(
      db.collection(`users/${targetUid}/transactions`).doc(),
      {
        type: plan === 'pro' ? 'planUpgrade' : 'planDowngrade',
        tool: null,
        documentId: null,
        documentTitle: null,
        metadata: {
          newPlan: plan,
          previousPlan: sub.plan || 'free',
          byAdmin: request.auth.uid,
          cycleDays: plan === 'pro' ? cycleDaysNum : null,
        },
        createdAt: serverNow,
      }
    );

    await batch.commit();
    return { success: true, plan, cycleDays: cycleDaysNum };
  })
);

// ─── adminResetCounters ──────────────────────────────────────────────────
// Reset all cycle counters to zero and start a new 30-day cycle.

exports.adminResetCounters = onCall(
  { region: REGION, timeoutSeconds: 30 },
  withErrorReporting('adminResetCounters', async (request) => {
    adminGuard(request);

    const { targetUid } = request.data || {};
    if (!targetUid) {
      throw new HttpsError('invalid-argument', '`targetUid` required.');
    }

    const { subRef, sub, label } = await loadTarget(targetUid);

    const db = admin.firestore();
    const serverNow = admin.firestore.FieldValue.serverTimestamp();
    const newEnd = new Date(Date.now() + 30 * 86400000);

    const before = {
      aiFillCount: Number(sub.aiFillCount) || 0,
      aiRewriteCount: Number(sub.aiRewriteCount) || 0,
      editorAiCount: Number(sub.editorAiCount) || 0,
      exportCount: Number(sub.exportCount) || 0,
      spellcheckCount: Number(sub.spellcheckCount) || 0,
    };

    const batch = db.batch();
    batch.update(subRef, {
      aiFillCount: 0,
      aiRewriteCount: 0,
      editorAiCount: 0,
      editorAiHourlyCount: 0,
      editorAiHourlyResetAt: null,
      editorAiRefusalCount: 0,
      exportCount: 0,
      spellcheckCount: 0,
      cycleStartDate: serverNow,
      cycleEndDate: tsFromDate(newEnd),
      lastResetDate: serverNow,
    });

    batch.set(db.collection('adminActivity').doc(), {
      adminUid: request.auth.uid,
      adminEmail: request.auth.token.email || null,
      action: 'adminResetCounters',
      target: { type: 'user', id: targetUid, label },
      before,
      after: { all: 0 },
      metadata: {},
      createdAt: serverNow,
    });

    await batch.commit();
    return { success: true };
  })
);

// ─── adminResetHourlyBurst ───────────────────────────────────────────────

exports.adminResetHourlyBurst = onCall(
  { region: REGION, timeoutSeconds: 15 },
  withErrorReporting('adminResetHourlyBurst', async (request) => {
    adminGuard(request);

    const { targetUid } = request.data || {};
    if (!targetUid) {
      throw new HttpsError('invalid-argument', '`targetUid` required.');
    }

    const { subRef, sub, label } = await loadTarget(targetUid);

    const db = admin.firestore();
    const serverNow = admin.firestore.FieldValue.serverTimestamp();

    const batch = db.batch();
    batch.update(subRef, {
      editorAiHourlyCount: 0,
      editorAiHourlyResetAt: null,
    });

    batch.set(db.collection('adminActivity').doc(), {
      adminUid: request.auth.uid,
      adminEmail: request.auth.token.email || null,
      action: 'adminResetHourlyBurst',
      target: { type: 'user', id: targetUid, label },
      before: {
        editorAiHourlyCount: Number(sub.editorAiHourlyCount) || 0,
      },
      after: { editorAiHourlyCount: 0 },
      metadata: {},
      createdAt: serverNow,
    });

    await batch.commit();
    return { success: true };
  })
);

// ─── adminResetRefusalCount ──────────────────────────────────────────────

exports.adminResetRefusalCount = onCall(
  { region: REGION, timeoutSeconds: 15 },
  withErrorReporting('adminResetRefusalCount', async (request) => {
    adminGuard(request);

    const { targetUid } = request.data || {};
    if (!targetUid) {
      throw new HttpsError('invalid-argument', '`targetUid` required.');
    }

    const { subRef, sub, label } = await loadTarget(targetUid);

    const db = admin.firestore();
    const serverNow = admin.firestore.FieldValue.serverTimestamp();

    const batch = db.batch();
    batch.update(subRef, { editorAiRefusalCount: 0 });

    batch.set(db.collection('adminActivity').doc(), {
      adminUid: request.auth.uid,
      adminEmail: request.auth.token.email || null,
      action: 'adminResetRefusalCount',
      target: { type: 'user', id: targetUid, label },
      before: {
        editorAiRefusalCount: Number(sub.editorAiRefusalCount) || 0,
      },
      after: { editorAiRefusalCount: 0 },
      metadata: {},
      createdAt: serverNow,
    });

    await batch.commit();
    return { success: true };
  })
);

// ─── adminExtendTrial ────────────────────────────────────────────────────
// Extend (or start) a trial by N days. Rejected for Pro users.

exports.adminExtendTrial = onCall(
  { region: REGION, timeoutSeconds: 30 },
  withErrorReporting('adminExtendTrial', async (request) => {
    adminGuard(request);

    const { targetUid, days = 7 } = request.data || {};
    if (!targetUid) {
      throw new HttpsError('invalid-argument', '`targetUid` required.');
    }
    const daysNum = Math.max(1, Math.min(365, Number(days) || 7));

    const { subRef, userRef, sub, profile, label } =
        await loadTarget(targetUid);

    if (sub.plan === 'pro') {
      throw new HttpsError(
        'failed-precondition',
        'Cannot extend trial for a Pro user. Revoke Pro first.'
      );
    }

    const db = admin.firestore();
    const nowDate = new Date();
    const serverNow = admin.firestore.FieldValue.serverTimestamp();

    // Base for extension: current trialEndDate if in future, else now.
    let baseDate = nowDate;
    if (sub.trialEndDate && typeof sub.trialEndDate.toDate === 'function') {
      const existingEnd = sub.trialEndDate.toDate();
      if (existingEnd > nowDate) baseDate = existingEnd;
    }
    const newEnd = new Date(baseDate.getTime() + daysNum * 86400000);

    const batch = db.batch();
    batch.update(subRef, {
      plan: 'trial',
      trialActive: true,
      trialUsed: true,
      trialStartDate: sub.trialStartDate || serverNow,
      trialEndDate: tsFromDate(newEnd),
      cycleStartDate: sub.trialStartDate || serverNow,
      cycleEndDate: tsFromDate(newEnd),
    });

    if (profile.hasUsedTrial !== true) {
      batch.update(userRef, { hasUsedTrial: true });
    }

    batch.set(db.collection('adminActivity').doc(), {
      adminUid: request.auth.uid,
      adminEmail: request.auth.token.email || null,
      action: 'adminExtendTrial',
      target: { type: 'user', id: targetUid, label },
      before: {
        plan: sub.plan || 'free',
        trialActive: sub.trialActive === true,
        trialEndDate: sub.trialEndDate?.toDate?.().toISOString() || null,
      },
      after: {
        plan: 'trial',
        trialEndDate: newEnd.toISOString(),
        days: daysNum,
      },
      metadata: {},
      createdAt: serverNow,
    });

    batch.set(
      db.collection(`users/${targetUid}/transactions`).doc(),
      {
        type: 'trialActivated',
        tool: null,
        documentId: null,
        documentTitle: null,
        metadata: {
          days: daysNum,
          byAdmin: request.auth.uid,
          trialEndDate: newEnd.toISOString(),
        },
        createdAt: serverNow,
      }
    );

    await batch.commit();
    return { success: true, days: daysNum };
  })
);
