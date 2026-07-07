// functions/admin_announcement.js
//
// Dedicated endpoint for the system announcement banner. Separate from
// adminUpdateConfig because the schema is richer (active toggle,
// severity enum, optional link).

const { onCall, HttpsError } = require('firebase-functions/v2/https');
const admin = require('firebase-admin');
const crypto = require('crypto');
const { adminGuard, REGION } = require('./admin')._helpers;

const VALID_SEVERITIES = ['info', 'warn', 'critical'];

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

exports.adminUpdateAnnouncement = onCall(
  { region: REGION, timeoutSeconds: 30 },
  withErrorReporting('adminUpdateAnnouncement', async (request) => {
    adminGuard(request);

    const data = request.data || {};
    const active = data.active;
    const title = (data.title ?? '').toString();
    const body = (data.body ?? '').toString();
    const severity = (data.severity ?? 'info').toString();
    const linkUrl =
      data.linkUrl == null ? null : data.linkUrl.toString();
    const linkLabel =
      data.linkLabel == null ? null : data.linkLabel.toString();

    if (typeof active !== 'boolean') {
      throw new HttpsError('invalid-argument', '`active` must be boolean.');
    }
    if (title.length > 200) {
      throw new HttpsError(
        'invalid-argument',
        '`title` max length is 200 characters.'
      );
    }
    if (body.length > 2000) {
      throw new HttpsError(
        'invalid-argument',
        '`body` max length is 2000 characters.'
      );
    }
    if (!VALID_SEVERITIES.includes(severity)) {
      throw new HttpsError(
        'invalid-argument',
        `\`severity\` must be one of: ${VALID_SEVERITIES.join(', ')}.`
      );
    }
    if (linkUrl != null && linkUrl.length > 500) {
      throw new HttpsError(
        'invalid-argument',
        '`linkUrl` max length is 500 characters.'
      );
    }
    if (linkLabel != null && linkLabel.length > 100) {
      throw new HttpsError(
        'invalid-argument',
        '`linkLabel` max length is 100 characters.'
      );
    }
    if (active && title.trim().length === 0) {
      throw new HttpsError(
        'failed-precondition',
        'Active announcements must have a title.'
      );
    }

    const db = admin.firestore();
    const ref = db.doc('config/announcement');
    const beforeSnap = await ref.get();
    const before = beforeSnap.exists ? beforeSnap.data() : {};

    const serverNow = admin.firestore.FieldValue.serverTimestamp();
    // Fresh id on every save — any admin change re-notifies dismissed users.
        const newDoc = {
          id: crypto.randomBytes(8).toString('hex'),
          active,
          title,
          body,
          severity,
          linkUrl: linkUrl && linkUrl.length > 0 ? linkUrl : null,
          linkLabel: linkLabel && linkLabel.length > 0 ? linkLabel : null,
          updatedAt: serverNow,
          updatedBy: request.auth.uid,
        };

    // Strip Timestamps from audit snapshots
    const stripMeta = (o) => {
      const c = { ...o };
      delete c.updatedAt;
      delete c.updatedBy;
      return c;
    };

    const batch = db.batch();
    batch.set(ref, newDoc, { merge: false });

    batch.set(db.collection('adminActivity').doc(), {
      adminUid: request.auth.uid,
      adminEmail: request.auth.token.email || null,
      action: 'adminUpdateAnnouncement',
      target: {
        type: 'config',
        id: 'announcement',
        label: 'config/announcement',
      },
      before: stripMeta(before),
      after: stripMeta(newDoc),
      metadata: {},
      createdAt: serverNow,
    });

    await batch.commit();
    return { success: true };
  })
);