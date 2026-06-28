// functions/admin_config.js
//
// Generic config writer. Handles config/limits, config/pricing,
// config/proTemplates, and config/featureFlags via a single endpoint
// with per-doc validation. config/announcement uses its own endpoint
// (richer schema, added in a later step).

const { onCall, HttpsError } = require('firebase-functions/v2/https');
const admin = require('firebase-admin');
const { adminGuard, REGION } = require('./admin')._helpers;

const ALLOWED_DOCS = ['limits', 'pricing', 'proTemplates', 'featureFlags'];

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

// ─── Per-doc validators ─────────────────────────────────────────────────

const LIMIT_FIELDS = [
  'aiFillPerMonth',
  'aiRewritePerMonth',
  'aiEditPerMonth',
  'aiEditHourlyBurst',
  'aiDesignPerMonth',
  'exportsPerMonth',
  'maxDocs',
  'historyVisibleActions',
  'spellcheckLimit',
];

function isIntGteMinusOne(v) {
  return typeof v === 'number' && Number.isInteger(v) && v >= -1;
}

function validateLimits(data) {
  for (const plan of ['free', 'trial', 'pro']) {
    const block = data[plan];
    if (!block || typeof block !== 'object') {
      throw new HttpsError(
        'invalid-argument',
        `Missing or invalid "${plan}" block.`
      );
    }
    for (const field of LIMIT_FIELDS) {
      if (!isIntGteMinusOne(block[field])) {
        throw new HttpsError(
          'invalid-argument',
          `${plan}.${field} must be an integer ≥ -1 (-1 = unlimited).`
        );
      }
    }
  }
  if (!Number.isInteger(data.trialDays) || data.trialDays < 1) {
    throw new HttpsError(
      'invalid-argument',
      'trialDays must be an integer ≥ 1.'
    );
  }
  if (typeof data.proMonthlyPrice !== 'number' ||
      data.proMonthlyPrice < 0) {
    throw new HttpsError(
      'invalid-argument',
      'proMonthlyPrice must be ≥ 0.'
    );
  }
}

function validatePricing(data) {
  if (!data.models || typeof data.models !== 'object') {
    throw new HttpsError(
      'invalid-argument',
      'pricing.models block is required.'
    );
  }
  for (const [model, rates] of Object.entries(data.models)) {
    if (!rates || typeof rates !== 'object') {
      throw new HttpsError(
        'invalid-argument',
        `Invalid rates for model "${model}".`
      );
    }
    for (const k of ['inputPerMTok', 'outputPerMTok',
                     'cacheReadMultiplier']) {
      if (typeof rates[k] !== 'number' || rates[k] < 0) {
        throw new HttpsError(
          'invalid-argument',
          `${model}.${k} must be a number ≥ 0.`
        );
      }
    }
  }
}

function validateProTemplates(data) {
  if (!Array.isArray(data.proTemplates)) {
    throw new HttpsError(
      'invalid-argument',
      'proTemplates must be an array.'
    );
  }
  for (const id of data.proTemplates) {
    if (typeof id !== 'string' || id.length === 0) {
      throw new HttpsError(
        'invalid-argument',
        'Each proTemplates entry must be a non-empty string.'
      );
    }
  }
}

function validateFeatureFlags(data) {
  for (const [k, v] of Object.entries(data)) {
    if (k === 'updatedAt' || k === 'updatedBy') continue;
    if (typeof v !== 'boolean') {
      throw new HttpsError(
        'invalid-argument',
        `featureFlags.${k} must be a boolean.`
      );
    }
  }
}

const VALIDATORS = {
  limits: validateLimits,
  pricing: validatePricing,
  proTemplates: validateProTemplates,
  featureFlags: validateFeatureFlags,
};

// ─── adminUpdateConfig ──────────────────────────────────────────────────

exports.adminUpdateConfig = onCall(
  { region: REGION, timeoutSeconds: 30 },
  withErrorReporting('adminUpdateConfig', async (request) => {
    adminGuard(request);

    const { docId, newData } = request.data || {};
    if (!ALLOWED_DOCS.includes(docId)) {
      throw new HttpsError(
        'invalid-argument',
        `docId must be one of: ${ALLOWED_DOCS.join(', ')}.`
      );
    }
    if (!newData || typeof newData !== 'object') {
      throw new HttpsError('invalid-argument', 'newData must be an object.');
    }

    VALIDATORS[docId](newData);

    const db = admin.firestore();
    const ref = db.doc(`config/${docId}`);
    const beforeSnap = await ref.get();
    const before = beforeSnap.exists ? beforeSnap.data() : {};

    // Strip metadata fields the client might have included
    const clean = { ...newData };
    delete clean.updatedAt;
    delete clean.updatedBy;

    const serverNow = admin.firestore.FieldValue.serverTimestamp();
    const update = {
      ...clean,
      updatedAt: serverNow,
      updatedBy: request.auth.uid,
    };

    // Strip Firestore Timestamps from `before` for audit log
    const beforeForAudit = { ...before };
    delete beforeForAudit.updatedAt;
    delete beforeForAudit.updatedBy;

    const batch = db.batch();
    batch.set(ref, update, { merge: false });

    batch.set(db.collection('adminActivity').doc(), {
      adminUid: request.auth.uid,
      adminEmail: request.auth.token.email || null,
      action: 'adminUpdateConfig',
      target: {
        type: 'config',
        id: docId,
        label: `config/${docId}`,
      },
      before: beforeForAudit,
      after: clean,
      metadata: {},
      createdAt: serverNow,
    });

    await batch.commit();
    return { success: true, docId };
  })
);
