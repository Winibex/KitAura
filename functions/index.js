/**
 * functions/index.js
 *
 * KitAura Cloud Functions — all AI + tracking + paywall logic server-side.
 *
 * ENDPOINTS:
 *   aiFill      — generate CV/CL/proposal section content (Sonnet)
 *   spellcheck  — find spelling errors (Haiku)
 *
 * SECURITY:
 *   - Anthropic API key in Secret Manager
 *   - Token counts, costs, usage counters written server-side only
 *   - Frontend cannot manipulate subscription counters
 *
 * COST TRACKING:
 *   - Reads model rates from config/pricing (admin-editable)
 *   - Calculates exact USD cost per call
 *   - Writes to aiActivity + analytics atomically
 *
 * BILLING CYCLE:
 *   - Per-user cycle (not calendar month)
 *   - Checked and reset inline before each AI call
 */

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { defineSecret } = require("firebase-functions/params");
const admin = require("firebase-admin");
const axios = require("axios");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");
const { getStorage } = require("firebase-admin/storage");

admin.initializeApp();
const db = admin.firestore();

const ANTHROPIC_KEY = defineSecret("ANTHROPIC_KEY");
const ANTHROPIC_URL = "https://api.anthropic.com/v1/messages";
const API_VERSION = "2023-06-01";

const MODEL_SONNET = "claude-sonnet-4-6";
const MODEL_HAIKU = "claude-haiku-4-5-20251001";

// ════════════════════════════════════════════════════════════════════════
// HELPERS
// ════════════════════════════════════════════════════════════════════════

async function callClaude({ model, system, userContent, maxTokens, apiKey }) {
  const res = await axios.post(
    ANTHROPIC_URL,
    { model, max_tokens: maxTokens, system, messages: [{ role: "user", content: userContent }] },
    {
      headers: {
        "content-type": "application/json",
        "x-api-key": apiKey,
        "anthropic-version": API_VERSION,
        "anthropic-beta": "prompt-caching-2024-07-31",
      },
      timeout: 60000,
    }
  );
  const blocks = res.data.content || [];
  const text = blocks.filter((b) => b.type === "text").map((b) => b.text).join("");
  return { text, usage: res.data.usage || {} };
}

function calculateCost(usage, rates) {
  const inp = usage.input_tokens || 0;
  const out = usage.output_tokens || 0;
  const cacheRead = usage.cache_read_input_tokens || 0;
  const inputCost = (inp / 1e6) * rates.inputPerMTok;
  const outputCost = (out / 1e6) * rates.outputPerMTok;
  const cacheReadCost = (cacheRead / 1e6) * rates.inputPerMTok * rates.cacheReadMultiplier;
  return {
    inputCost: +inputCost.toFixed(6),
    outputCost: +outputCost.toFixed(6),
    cacheReadCost: +cacheReadCost.toFixed(6),
    totalCost: +(inputCost + outputCost + cacheReadCost).toFixed(6),
  };
}

async function getSubWithCycleCheck(uid) {
  const ref = db.doc(`users/${uid}/data/subscription`);
  const snap = await ref.get();
  if (!snap.exists) throw new HttpsError("not-found", "No subscription.");
  const sub = snap.data();
  const now = new Date();

  // Trial expiry check
  if (sub.plan === "trial" && sub.trialEndDate && now > sub.trialEndDate.toDate()) {
       await ref.update({ plan: "free", trialActive: false });
       sub.plan = "free";
       sub.trialActive = false;
     }

  // Billing cycle reset
  if (sub.cycleEndDate && now > sub.cycleEndDate.toDate()) {
    const newEnd = new Date(now.getTime() + 30 * 24 * 3600 * 1000);
    await ref.update({
      aiFillCount: 0, aiRewriteCount: 0, aiDesignCount: 0,
      exportCount: 0, spellcheckCount: 0,
      cycleStartDate: admin.firestore.Timestamp.fromDate(now),
      cycleEndDate: admin.firestore.Timestamp.fromDate(newEnd),
      lastResetDate: admin.firestore.Timestamp.fromDate(now),
    });
    sub.aiFillCount = 0; sub.aiRewriteCount = 0;
    sub.aiDesignCount = 0; sub.exportCount = 0; sub.spellcheckCount = 0;
  }
  return { sub, ref };
}

async function checkPaywall(sub, counterField, limitField) {
  if (sub.plan === "pro") return;
  if (sub.plan === "trial" && sub.trialActive) return;
  const limSnap = await db.doc("config/limits").get();
  if (!limSnap.exists) return;
  const lim = (limSnap.data()[sub.plan] || limSnap.data().free);
  const max = lim[limitField];
  if (max === -1) return;
  if ((sub[counterField] || 0) >= max) {
    const friendlyNames = {
          exportsPerMonth: "monthly export",
          aiFillPerMonth: "monthly AI generation",
          aiRewritePerMonth: "monthly AI rewrite",
          aiDesignPerMonth: "monthly AI design",
        };
        const name = friendlyNames[limitField] || "usage";
        throw new HttpsError("resource-exhausted",
          `You've reached your ${name} limit on the free plan. Upgrade to Pro for unlimited access.`);
  }
}

async function writeTracking({ uid, data, counterField, summaryField, monthlyField, monthlyToolField, tokens, cost }) {
  const batch = db.batch();
  const now = admin.firestore.Timestamp.fromDate(new Date());
  const month = new Date().toISOString().slice(0, 7);
  const FV = admin.firestore.FieldValue;

  // 1. aiActivity
  const actRef = db.collection(`users/${uid}/aiActivity`).doc();
  batch.set(actRef, {
    id: actRef.id, ...data,
    tokens: {
      inputTokens: tokens.input_tokens || 0,
      outputTokens: tokens.output_tokens || 0,
      cacheReadTokens: tokens.cache_read_input_tokens || 0,
      cacheCreationTokens: tokens.cache_creation_input_tokens || 0,
    },
    cost, createdAt: now,
  });

  // 2. subscription counter
  const subRef = db.doc(`users/${uid}/data/subscription`);
  batch.update(subRef, { [counterField]: FV.increment(1) });

  // 3. analytics summary
  const sumRef = db.doc(`users/${uid}/analytics/summary`);
  const sumUp = {
    lastActiveAt: now,
    totalTokensUsed: FV.increment((tokens.input_tokens || 0) + (tokens.output_tokens || 0)),
    totalCostUsd: FV.increment(cost.totalCost),
    [summaryField]: FV.increment(1),
  };
  batch.set(sumRef, sumUp, { merge: true });

  // 4. monthly analytics
  const monRef = db.doc(`users/${uid}/analytics/${month}`);
  const monUp = {
    month, updatedAt: now,
    totalInputTokens: FV.increment(tokens.input_tokens || 0),
    totalOutputTokens: FV.increment(tokens.output_tokens || 0),
    totalCacheReadTokens: FV.increment(tokens.cache_read_input_tokens || 0),
    totalInputCost: FV.increment(cost.inputCost),
    totalOutputCost: FV.increment(cost.outputCost),
    totalCost: FV.increment(cost.totalCost),
    [monthlyField]: FV.increment(1),
  };
  if (monthlyToolField) monUp[monthlyToolField] = FV.increment(1);
  batch.set(monRef, monUp, { merge: true });

  await batch.commit();
  return actRef.id;
}

async function uploadDetail(uid, activityId, detail) {
  try {
    const bucket = admin.storage().bucket();
    const path = `users/${uid}/ai_details/${activityId}.json`;
    await bucket.file(path).save(JSON.stringify(detail, null, 2), { contentType: "application/json" });
    await db.doc(`users/${uid}/aiActivity/${activityId}`).update({ detailsPath: path });
  } catch (e) { console.error("Detail upload failed:", e.message); }
}

// ════════════════════════════════════════════════════════════════════════
// 1. AI FILL
// ════════════════════════════════════════════════════════════════════════

exports.aiFill = onCall({ secrets: [ANTHROPIC_KEY], region: "us-central1", timeoutSeconds: 120 }, async (req) => {
  if (!req.auth) throw new HttpsError("unauthenticated", "Sign in required.");
  const uid = req.auth.uid;
  const t0 = Date.now();
  const { sectionType="custom", tone="professional", experienceLevel="mid", profile={},
    tool="cv", documentId=null, documentTitle=null, templateId=null, sectionTitle=null, beforeText="" } = req.data || {};

  const { sub } = await getSubWithCycleCheck(uid);
  await checkPaywall(sub, "aiFillCount", "aiFillPerMonth");

  const pSnap = await db.doc("config/pricing").get();
  const rates = pSnap.exists ? pSnap.data().models[MODEL_SONNET] : { inputPerMTok:3, outputPerMTok:15, cacheReadMultiplier:0.1 };

  const sys = [{
    type: "text",
    text: `You are an expert ${tool === 'coverLetter' ? 'cover letter' : tool === 'proposal' ? 'proposal' : 'CV'} writer. Transform raw profile data into polished ${tool === 'coverLetter' ? 'cover letter' : tool === 'proposal' ? 'proposal' : 'CV'} content.\n\n` +
      "OUTPUT: Return ONLY a JSON object: {\"heading\":\"UPPERCASE TITLE\",\"entries\":[{\"title\":\"line\",\"lines\":[\"bullet\"]}]}\n\n" +
      "RULES: No markdown/code fences. Start bullets with '• '. Never invent data. Max ~120 words.\n" +
      "Tone: " + tone + ". Level: " + experienceLevel + ".\n\n" +
      "FORMATS: summary→heading='PROFESSIONAL SUMMARY',1 entry,title='',lines=['paragraph']. " +
      "experience→1 entry/role,title='Role — Company | Dates',lines=['• Achievement']. " +
      "education→title='Degree — School | Dates'. skills→lines=['Skill1 • Skill2']. " +
      "certifications→lines=['Cert1','Cert2']. languages→title='Lang — Level'. " +
      "contact→heading='',lines=['email | phone | location']. name→title='Full Name'. jobTitle→title='Title'.",
    cache_control: { type: "ephemeral" },
  }];

  let text, usage;
  try {
    const r = await callClaude({ model: MODEL_SONNET, system: sys,
      userContent: `Section: ${sectionType}\n\nProfile:\n${JSON.stringify(profile,null,2)}\n\nWrite now. JSON only.`,
      maxTokens: 1024, apiKey: ANTHROPIC_KEY.value() });
    text = r.text; usage = r.usage;
  } catch (err) {
    console.error("aiFill API error:", err?.response?.data || err.message);
    throw new HttpsError("internal", "AI generation failed.");
  }

  const cleaned = text.replace(/```json/g,"").replace(/```/g,"").trim();
  let content;
  try { content = JSON.parse(cleaned); } catch(e) {
    console.error("aiFill parse error:", cleaned);
    throw new HttpsError("internal", "AI returned malformed content.");
  }
  if (typeof content !== "object" || !Array.isArray(content.entries)) {
    throw new HttpsError("internal", "Unexpected AI output.");
  }

  const cost = calculateCost(usage, rates);
  const actId = await writeTracking({ uid,
    data: { tool, type:"aiFill", status:"success", model:MODEL_SONNET,
      documentId, documentTitle, templateId, sectionType, sectionTitle,
      rewriteOptions:null, spellcheckSummary:null, errorMessage:null, durationMs:Date.now()-t0 },
    counterField:"aiFillCount", summaryField:"totalAiFills",
    monthlyField:"aiFills", monthlyToolField:`${tool}AiFills`, tokens:usage, cost });

  uploadDetail(uid, actId, { tool, type:"aiFill", sectionType, beforeText,
    afterText:JSON.stringify(content), generatedContent:content,
    profileSnapshot:{ jobTitle:profile.jobTitle||"", experienceLevel, tone } });

  return { content };
});

// ════════════════════════════════════════════════════════════════════════
// 2. SPELLCHECK — free, tracked
// ════════════════════════════════════════════════════════════════════════

exports.spellcheck = onCall({ secrets: [ANTHROPIC_KEY], region: "us-central1", timeoutSeconds: 60 }, async (req) => {
  if (!req.auth) throw new HttpsError("unauthenticated", "Sign in required.");
  const uid = req.auth.uid;
  const t0 = Date.now();
  const { sections={}, tool="cv", documentId=null, documentTitle=null } = req.data || {};
  if (!Object.keys(sections).length) return { corrections: [] };

  await getSubWithCycleCheck(uid);

  const pSnap = await db.doc("config/pricing").get();
  const rates = pSnap.exists ? pSnap.data().models[MODEL_HAIKU] : { inputPerMTok:1, outputPerMTok:5, cacheReadMultiplier:0.1 };

  const sys = [{
    type: "text",
    text: "Spelling checker for CVs. Find ONLY spelling mistakes. Skip proper nouns, companies, tech terms.\n" +
      "Return JSON array: [{\"section\":\"<title>\",\"wrong\":\"<word>\",\"correct\":\"<fix>\",\"offset\":<int>}]\n" +
      "No errors? Return []. No markdown.",
    cache_control: { type: "ephemeral" },
  }];

  const txt = Object.entries(sections).map(([t,v])=>`--- ${t} ---\n${v}`).join("\n\n");

  let result, usage;
  try {
    const r = await callClaude({ model:MODEL_HAIKU, system:sys,
      userContent:`Check spelling:\n\n${txt}`, maxTokens:1024, apiKey:ANTHROPIC_KEY.value() });
    result = r.text; usage = r.usage;
  } catch(err) {
    console.error("spellcheck error:", err?.response?.data || err.message);
    throw new HttpsError("internal", "Spellcheck failed.");
  }

  let corrections;
  try { corrections = JSON.parse(result.replace(/```json/g,"").replace(/```/g,"").trim()); } catch(e) { corrections = []; }
  if (!Array.isArray(corrections)) corrections = [];

  const cost = calculateCost(usage, rates);
  const actId = await writeTracking({ uid,
    data: { tool, type:"spellcheck", status:"success", model:MODEL_HAIKU,
      documentId, documentTitle, templateId:null, sectionType:null, sectionTitle:null,
      rewriteOptions:null,
      spellcheckSummary:{ errorsFound:corrections.length, correctionsAccepted:0, correctionsDismissed:0 },
      errorMessage:null, durationMs:Date.now()-t0 },
    counterField:"spellcheckCount", summaryField:"totalSpellchecks",
    monthlyField:"spellchecks", monthlyToolField:null, tokens:usage, cost });

  uploadDetail(uid, actId, { tool, type:"spellcheck",
    corrections: corrections.map(c=>({...c, userAction:"pending"})) });

  return { corrections, activityId: actId };
});

// ═══════════════════════════════════════════════════════════════════════════
// 3. AI REWRITE
// ═══════════════════════════════════════════════════════════════════════════

exports.aiRewrite = onCall({ secrets: [ANTHROPIC_KEY], region: "us-central1", timeoutSeconds: 120 }, async (req) => {
  if (!req.auth) throw new HttpsError("unauthenticated", "Sign in required.");
  const uid = req.auth.uid;
  const t0 = Date.now();
  const { text="", sectionType="custom", mode="professional", customInstruction=null,
    tool="cv", documentId=null, documentTitle=null, templateId=null, sectionTitle=null } = req.data || {};

  if (!text || !sectionType) throw new HttpsError("invalid-argument", "Missing text or sectionType");

  const { sub } = await getSubWithCycleCheck(uid);
  await checkPaywall(sub, "aiRewriteCount", "aiRewritePerMonth");

  const pSnap = await db.doc("config/pricing").get();
  const rates = pSnap.exists ? pSnap.data().models[MODEL_SONNET] : { inputPerMTok:3, outputPerMTok:15, cacheReadMultiplier:0.1 };

  let modeInstruction = "";
  switch (mode) {
    case "professional": modeInstruction = "Rewrite in a formal, polished professional tone. Use strong action verbs."; break;
    case "concise": modeInstruction = "Make it shorter and more impactful. Remove filler. Aim for 30-50% fewer words."; break;
    case "detailed": modeInstruction = "Expand with metrics, quantified accomplishments, and specific context."; break;
    case "creative": modeInstruction = "Rewrite with creative, engaging tone that stands out while staying professional."; break;
  }

  const customPart = customInstruction ? `\nAdditional instruction: "${customInstruction}"` : "";

  const sys = [{
    type: "text",
    text: "You are a professional CV content rewriter.\n\nRULES:\n" +
      "- Keep same structure (headings, bullets, entries)\n" +
      "- Preserve ALL facts: dates, companies, degrees, metrics\n" +
      "- Return ONLY rewritten text — no explanations, no markdown\n" +
      "- Keep same format as input\n" +
      "- If heading is ALL CAPS, keep it ALL CAPS\n\n" +
      "STYLE: " + modeInstruction + customPart,
    cache_control: { type: "ephemeral" },
  }];

  let rewrittenText, usage;
  try {
    const r = await callClaude({ model: MODEL_SONNET, system: sys,
      userContent: `Rewrite this ${sectionType} section:\n\n${text}`,
      maxTokens: 2000, apiKey: ANTHROPIC_KEY.value() });
    rewrittenText = r.text; usage = r.usage;
  } catch (err) {
    console.error("aiRewrite API error:", err?.response?.data || err.message);
    throw new HttpsError("internal", "AI rewrite failed.");
  }

  const cost = calculateCost(usage, rates);
  const actId = await writeTracking({ uid,
    data: { tool, type:"aiRewrite", status:"success", model:MODEL_SONNET,
      documentId, documentTitle, templateId, sectionType, sectionTitle:sectionTitle,
      rewriteOptions:{ mode, scope:"section" },
      spellcheckSummary:null, errorMessage:null, durationMs:Date.now()-t0 },
    counterField:"aiRewriteCount", summaryField:"totalAiRewrites",
    monthlyField:"aiRewrites", monthlyToolField:`${tool}AiRewrites`, tokens:usage, cost });

  uploadDetail(uid, actId, { tool, type:"aiRewrite", sectionType, scope:"section",
    mode, customInstruction: customInstruction || null,
    beforeText: text, afterText: rewrittenText });

  return { content: rewrittenText };
});

// ════════════════════════════════════════════════════════════════════════
// 4. TRACK EXPORT — increment counter + paywall check
// ════════════════════════════════════════════════════════════════════════

exports.trackExport = onCall({ region: "us-central1", timeoutSeconds: 30 }, async (req) => {
  if (!req.auth) throw new HttpsError("unauthenticated", "Please sign in to export.");
  const uid = req.auth.uid;
  const { tool = "cv", documentId = null, documentTitle = null } = req.data || {};

  if (!documentId) throw new HttpsError("invalid-argument", "Please save your document before exporting.");

  const { sub } = await getSubWithCycleCheck(uid);
  await checkPaywall(sub, "exportCount", "exportsPerMonth");

  // Resolve document path FIRST (before using it)
  const collectionMap = { cv: "cvs", coverLetter: "coverLetters", proposal: "proposals" };
  const collection = collectionMap[tool] || "cvs";
  const docRef = db.doc(`users/${uid}/${collection}/${documentId}`);

  // Check Pro template restriction on free plan
  if (sub.plan === "free") {
    try {
      const limSnap = await db.doc("config/proTemplates").get();
      const proTemplates = limSnap.exists ? (limSnap.data().proTemplates || []) : [];

      if (proTemplates.length > 0) {
        const docSnap = await docRef.get();
        if (docSnap.exists) {
          const templateId = docSnap.data().templateId;
          if (proTemplates.includes(templateId)) {
            throw new HttpsError("resource-exhausted",
              "This template is available on the Pro plan. Upgrade to unlock premium templates and unlimited exports.");
          }
        }
      }
    } catch (e) {
      if (e.code === "resource-exhausted") throw e; // Re-throw paywall errors
      console.error("Pro template check failed:", e.message);
    }
  }

  const batch = db.batch();
  const now = admin.firestore.Timestamp.fromDate(new Date());
  const FV = admin.firestore.FieldValue;
  const month = new Date().toISOString().slice(0, 7);

  // 1. Increment subscription export counter
  const subRef = db.doc(`users/${uid}/data/subscription`);
  batch.update(subRef, { exportCount: FV.increment(1) });

  // 2. Update the specific document's export count + lastExportedAt
  batch.update(docRef, {
    exportCount: FV.increment(1),
    lastExportedAt: now,
  });

  // 3. Analytics summary
  const sumRef = db.doc(`users/${uid}/analytics/summary`);
  batch.set(sumRef, { totalExports: FV.increment(1), lastActiveAt: now }, { merge: true });

  // 4. Monthly analytics
  const monRef = db.doc(`users/${uid}/analytics/${month}`);
  const monData = { month, exports: FV.increment(1), updatedAt: now };
  if (documentId) monData.exportedDocIds = FV.arrayUnion(documentId);
  batch.set(monRef, monData, { merge: true });

  // 5. Transaction log
  const txRef = db.collection(`users/${uid}/transactions`).doc();
  batch.set(txRef, {
    id: txRef.id, type: "export", tool, documentId, documentTitle,
    metadata: {}, createdAt: now,
  });

  await batch.commit();
  return { success: true };
});

// ════════════════════════════════════════════════════════════════════════
// 5. TRACK LOGIN — increment login counters
// ════════════════════════════════════════════════════════════════════════
//
// Called by frontend on every sign-in (email, Google).
// Updates: analytics/summary.loginCount + lastLoginAt + lastActiveAt
//          analytics/{YYYY-MM}.logins

exports.trackLogin = onCall({ region: "us-central1", timeoutSeconds: 15 }, async (req) => {
  if (!req.auth) throw new HttpsError("unauthenticated", "Sign in required.");
  const uid = req.auth.uid;

  const batch = db.batch();
  const now = admin.firestore.Timestamp.fromDate(new Date());
  const FV = admin.firestore.FieldValue;
  const month = new Date().toISOString().slice(0, 7);

  // 1. Lifetime summary
  const sumRef = db.doc(`users/${uid}/analytics/summary`);
  batch.set(sumRef, {
    lastLoginAt: now,
    loginCount: FV.increment(1),
    lastActiveAt: now,
  }, { merge: true });

  // 2. Monthly analytics
  const monRef = db.doc(`users/${uid}/analytics/${month}`);
  batch.set(monRef, {
    month,
    logins: FV.increment(1),
    updatedAt: now,
  }, { merge: true });

  await batch.commit();
  return { success: true };
});

// ════════════════════════════════════════════════════════════════════════
// 6. TRACK DOC CREATED — increment counters when CV/CL/Proposal is created
// ════════════════════════════════════════════════════════════════════════
//
// Called by frontend AFTER successfully creating a document.
// Updates: subscription.{cvCount|coverLetterCount|proposalCount} (+1)
//          analytics/summary.total{Cvs|CoverLetters|Proposals}Created (+1)
//          analytics/{YYYY-MM}.{cvs|coverLetters|proposals}Created (+1)
//          transactions/{txId} (type: cvCreated|coverLetterCreated|proposalCreated)

exports.trackDocCreated = onCall({ region: "us-central1", timeoutSeconds: 30 }, async (req) => {
  if (!req.auth) throw new HttpsError("unauthenticated", "Sign in required.");
  const uid = req.auth.uid;
  const { tool = "cv", documentId = null, documentTitle = null } = req.data || {};

  // Validate tool
  const toolMap = {
    cv:          { sub: "cvCount",          sum: "totalCvsCreated",          mon: "cvsCreated",          tx: "cvCreated" },
    coverLetter: { sub: "coverLetterCount", sum: "totalCoverLettersCreated", mon: "coverLettersCreated", tx: "coverLetterCreated" },
    proposal:    { sub: "proposalCount",    sum: "totalProposalsCreated",    mon: "proposalsCreated",    tx: "proposalCreated" },
  };
  const fields = toolMap[tool];
  if (!fields) throw new HttpsError("invalid-argument", `Unknown tool: ${tool}`);

  const batch = db.batch();
  const now = admin.firestore.Timestamp.fromDate(new Date());
  const FV = admin.firestore.FieldValue;
  const month = new Date().toISOString().slice(0, 7);

  // 1. Subscription doc counter
  const subRef = db.doc(`users/${uid}/data/subscription`);
  batch.update(subRef, { [fields.sub]: FV.increment(1) });

  // 2. Analytics summary
  const sumRef = db.doc(`users/${uid}/analytics/summary`);
  batch.set(sumRef, {
    [fields.sum]: FV.increment(1),
    lastActiveAt: now,
  }, { merge: true });

  // 3. Monthly analytics
  const monRef = db.doc(`users/${uid}/analytics/${month}`);
  batch.set(monRef, {
    month,
    [fields.mon]: FV.increment(1),
    updatedAt: now,
  }, { merge: true });

  // 4. Transaction log
  const txRef = db.collection(`users/${uid}/transactions`).doc();
  batch.set(txRef, {
    id: txRef.id,
    type: fields.tx,
    tool,
    documentId,
    documentTitle,
    metadata: {},
    createdAt: now,
  });

  await batch.commit();
  return { success: true };
});

// ════════════════════════════════════════════════════════════════════════
// 7. TRACK DOC DELETED — decrement counter + log deletion
// ════════════════════════════════════════════════════════════════════════
//
// Called by frontend BEFORE deleting a document (or right after).
// Option A behavior: deleting frees up a slot so user can create another.
//
// Updates: subscription.{cvCount|coverLetterCount|proposalCount} (-1, min 0)
//          transactions/{txId} (type: cvDeleted|coverLetterDeleted|proposalDeleted)
//
// NOTE: We do NOT decrement lifetime totals in analytics/summary —
//       those reflect "how many were ever created" and shouldn't go down.

exports.trackDocDeleted = onCall({ region: "us-central1", timeoutSeconds: 30 }, async (req) => {
  if (!req.auth) throw new HttpsError("unauthenticated", "Sign in required.");
  const uid = req.auth.uid;
  const { tool = "cv", documentId = null, documentTitle = null } = req.data || {};

  const toolMap = {
    cv:          { sub: "cvCount",          tx: "cvDeleted" },
    coverLetter: { sub: "coverLetterCount", tx: "coverLetterDeleted" },
    proposal:    { sub: "proposalCount",    tx: "proposalDeleted" },
  };
  const fields = toolMap[tool];
  if (!fields) throw new HttpsError("invalid-argument", `Unknown tool: ${tool}`);

  // Read current count first so we don't go negative
  const subRef = db.doc(`users/${uid}/data/subscription`);
  const subSnap = await subRef.get();
  if (!subSnap.exists) throw new HttpsError("not-found", "No subscription.");
  const currentCount = subSnap.data()[fields.sub] || 0;

  const batch = db.batch();
  const now = admin.firestore.Timestamp.fromDate(new Date());
  const FV = admin.firestore.FieldValue;

  // 1. Decrement subscription counter (clamp to 0 — defensive)
  if (currentCount > 0) {
    batch.update(subRef, { [fields.sub]: FV.increment(-1) });
  }

  // 2. Update last active timestamp on summary
  const sumRef = db.doc(`users/${uid}/analytics/summary`);
  batch.set(sumRef, { lastActiveAt: now }, { merge: true });

  // 3. Transaction log
  const txRef = db.collection(`users/${uid}/transactions`).doc();
  batch.set(txRef, {
    id: txRef.id,
    type: fields.tx,
    tool,
    documentId,
    documentTitle,
    metadata: {},
    createdAt: now,
  });

  await batch.commit();
  return { success: true };
});

// ════════════════════════════════════════════════════════════════════════
// 8. UPDATE SPELLCHECK RESULT — track accept/dismiss decisions
// ════════════════════════════════════════════════════════════════════════
//
// Called after user clicks Accept/Dismiss on spellcheck corrections.
// Updates: aiActivity/{activityId}.spellcheckSummary counts
//          Storage: ai_details/{activityId}.json corrections[].userAction

exports.updateSpellcheckResult = onCall({ region: "us-central1", timeoutSeconds: 30 }, async (req) => {
  if (!req.auth) throw new HttpsError("unauthenticated", "Sign in required.");
  const uid = req.auth.uid;
  const { activityId, corrections } = req.data || {};

  if (!activityId) throw new HttpsError("invalid-argument", "activityId required");
  if (!Array.isArray(corrections)) throw new HttpsError("invalid-argument", "corrections array required");

  // Verify activity belongs to this user
  const actRef = db.doc(`users/${uid}/aiActivity/${activityId}`);
  const actSnap = await actRef.get();
  if (!actSnap.exists) throw new HttpsError("not-found", "Activity not found");

  // Count accepted / dismissed
  let accepted = 0;
  let dismissed = 0;
  for (const c of corrections) {
    if (c.userAction === "accepted") accepted++;
    else if (c.userAction === "dismissed") dismissed++;
  }

  // 1. Update aiActivity spellcheckSummary
  await actRef.update({
    "spellcheckSummary.correctionsAccepted": accepted,
    "spellcheckSummary.correctionsDismissed": dismissed,
  });

  // 2. Update Storage JSON with per-correction userAction
  try {
    const bucket = admin.storage().bucket();
    const path = `users/${uid}/ai_details/${activityId}.json`;
    const file = bucket.file(path);
    const [exists] = await file.exists();
    if (exists) {
      const [content] = await file.download();
      const detail = JSON.parse(content.toString());
      detail.corrections = corrections; // Replace with updated array
      await file.save(JSON.stringify(detail, null, 2), {
        contentType: "application/json",
      });
    }
  } catch (e) {
    console.error("Spellcheck detail update failed:", e.message);
    // Non-critical — Firestore counts are the source of truth
  }

  return { success: true, accepted, dismissed };
});

// ════════════════════════════════════════════════════════════════════════
// 9. ACTIVATE TRIAL — 7-day free trial, no credit card
// ════════════════════════════════════════════════════════════════════════
//
// APPEND THIS TO functions/index.js
//
// Checks: user hasn't already used trial (trialUsed flag on subscription
// AND hasUsedTrial on user profile — double check prevents abuse).
// Sets: plan='trial', trialActive=true, trialUsed=true, new 7-day cycle.
// Resets all usage counters to 0 for the trial period.

exports.activateTrial = onCall({ region: "us-central1", timeoutSeconds: 30 }, async (req) => {
  if (!req.auth) throw new HttpsError("unauthenticated", "Sign in required.");
  const uid = req.auth.uid;

  const batch = db.batch();
  const now = admin.firestore.Timestamp.fromDate(new Date());
  const trialEnd = new Date(Date.now() + 7 * 24 * 60 * 60 * 1000); // 7 days
  const FV = admin.firestore.FieldValue;
  const month = new Date().toISOString().slice(0, 7);

  // ── Read subscription ────────────────────────────────────────────
  const subRef = db.doc(`users/${uid}/data/subscription`);
  const subSnap = await subRef.get();
  if (!subSnap.exists) throw new HttpsError("not-found", "No subscription found.");
  const sub = subSnap.data();

  // ── Guard: already used trial ────────────────────────────────────
  if (sub.trialUsed === true) {
    throw new HttpsError("already-exists",
      "You've already used your free trial. Upgrade to Pro for unlimited access.");
  }

  // ── Guard: already on trial or pro ───────────────────────────────
  if (sub.plan === "trial" && sub.trialActive === true) {
    throw new HttpsError("already-exists", "Your trial is already active.");
  }
  if (sub.plan === "pro") {
    throw new HttpsError("already-exists", "You're already on the Pro plan.");
  }

  // ── Double-check via user profile flag ───────────────────────────
  const userRef = db.doc(`users/${uid}`);
  const userSnap = await userRef.get();
  if (userSnap.exists && userSnap.data().hasUsedTrial === true) {
    // Sync the flag back to subscription (in case it got out of sync)
    batch.update(subRef, { trialUsed: true });
    await batch.commit();
    throw new HttpsError("already-exists",
      "You've already used your free trial. Upgrade to Pro for unlimited access.");
  }

  // ── Activate trial ───────────────────────────────────────────────

  // 1. Update subscription
  batch.update(subRef, {
    plan: "trial",
    trialStartDate: now,
    trialEndDate: admin.firestore.Timestamp.fromDate(trialEnd),
    trialActive: true,
    trialUsed: true,

    // Reset billing cycle to trial period (7 days)
    cycleStartDate: now,
    cycleEndDate: admin.firestore.Timestamp.fromDate(trialEnd),
    lastResetDate: now,

    // Reset all usage counters for fresh trial
    aiFillCount: 0,
    aiRewriteCount: 0,
    aiDesignCount: 0,
    exportCount: 0,
    spellcheckCount: 0,
  });

  // 2. Mark user profile (survives subscription changes)
  batch.update(userRef, {
    hasUsedTrial: true,
    updatedAt: now,
  });

  // 3. Analytics summary
  const sumRef = db.doc(`users/${uid}/analytics/summary`);
  batch.set(sumRef, { lastActiveAt: now }, { merge: true });

  // 4. Transaction log
  const txRef = db.collection(`users/${uid}/transactions`).doc();
  batch.set(txRef, {
    id: txRef.id,
    type: "trialActivated",
    tool: null,
    documentId: null,
    documentTitle: null,
    metadata: {
      trialDays: 7,
      trialEndDate: admin.firestore.Timestamp.fromDate(trialEnd),
    },
    createdAt: now,
  });

  // 5. Monthly analytics
  const monRef = db.doc(`users/${uid}/analytics/${month}`);
  batch.set(monRef, {
    month,
    updatedAt: now,
  }, { merge: true });

  await batch.commit();

  return {
    success: true,
    plan: "trial",
    trialEndDate: trialEnd.toISOString(),
    daysRemaining: 7,
  };
});