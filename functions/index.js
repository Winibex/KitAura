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
    await ref.update({ trialActive: false });
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
    throw new HttpsError("resource-exhausted",
      `You've reached your ${limitField.replace("PerMonth", "")} limit. Upgrade to Pro.`);
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
    text: "You are an expert CV writer. Transform raw profile data into polished CV content.\n\n" +
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
// AI REWRITE
// ═══════════════════════════════════════════════════════════════════════════

exports.aiRewrite = onCall(
  { region: "us-central1", secrets: ["ANTHROPIC_KEY"] },
  async (request) => {
    // ── Auth check ──────────────────────────────────────────────────────
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign in required");
    }
    const uid = request.auth.uid;

    const {
      text,
      sectionType,
      mode,
      customInstruction,
      tool,
      documentId,
      documentTitle,
      templateId,
    } = request.data;

    if (!text || !sectionType) {
      throw new HttpsError("invalid-argument", "Missing text or sectionType");
    }

    const db = getFirestore();
    const subRef = db.doc(`users/${uid}/data/subscription`);
    const subSnap = await subRef.get();
    const subData = subSnap.data() || {};

    // ── Cycle reset check ───────────────────────────────────────────────
    await checkAndResetCycle(uid, subRef, subData);
    const freshSub = (await subRef.get()).data() || {};

    // ── Paywall check ───────────────────────────────────────────────────
    const limitsSnap = await db.doc("config/limits").get();
    const limits = limitsSnap.data();
    const planLimits = limits[freshSub.plan || "free"];

    if (
      planLimits.aiRewritePerMonth !== -1 &&
      (freshSub.aiRewriteCount || 0) >= planLimits.aiRewritePerMonth
    ) {
      throw new HttpsError(
        "resource-exhausted",
        "AI Rewrite limit reached. Upgrade to Pro for unlimited rewrites."
      );
    }

    // ── Build prompt ────────────────────────────────────────────────────
    const rewriteMode = mode || "professional";
    let modeInstruction = "";
    switch (rewriteMode) {
      case "professional":
        modeInstruction =
          "Rewrite in a formal, polished professional tone suitable for corporate CVs. Use strong action verbs and industry-standard phrasing.";
        break;
      case "concise":
        modeInstruction =
          "Make it shorter and more impactful. Remove filler words. Compress sentences. Use strong action verbs. Aim for 30-50% fewer words while keeping all key information.";
        break;
      case "detailed":
        modeInstruction =
          "Expand with more specific details, metrics, quantified accomplishments, and context. Add measurable results where appropriate (e.g. 'increased revenue by 25%').";
        break;
      case "creative":
        modeInstruction =
          "Rewrite with a creative, engaging tone that stands out from typical CVs while remaining professional. Use vivid language and compelling narrative.";
        break;
    }

    const customPart = customInstruction
      ? `\n\nAdditional user instruction: "${customInstruction}"`
      : "";

    const systemPrompt = `You are a professional CV content rewriter. You improve CV section text without changing its meaning.

RULES:
- Keep the same general structure (headings, bullet points, entries)
- Preserve ALL factual information: dates, company names, degrees, metrics
- Only change wording, tone, and phrasing
- Return ONLY the rewritten text — no explanations, no markdown, no quotes
- Keep the same format as the input (if input has bullet points, output should too)
- If the input has a heading in ALL CAPS, keep it in ALL CAPS
- Maintain professional CV formatting conventions

STYLE: ${modeInstruction}${customPart}`;

    // ── Call Anthropic API ──────────────────────────────────────────────
    const startTime = Date.now();
    const ANTHROPIC_KEY = process.env.ANTHROPIC_KEY;

    const response = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-api-key": ANTHROPIC_KEY,
        "anthropic-version": "2023-06-01",
      },
      body: JSON.stringify({
        model: "claude-sonnet-4-6",
        max_tokens: 2000,
        system: [
          {
            type: "text",
            text: systemPrompt,
            cache_control: { type: "ephemeral" },
          },
        ],
        messages: [
          {
            role: "user",
            content: `Rewrite this ${sectionType} section:\n\n${text}`,
          },
        ],
      }),
    });

    const result = await response.json();
    const durationMs = Date.now() - startTime;

    if (result.error) {
      throw new HttpsError("internal", result.error.message);
    }

    const content = result.content?.[0]?.text || "";
    const usage = result.usage || {};

    // ── Calculate cost ─────────────────────────────────────────────────
    const pricingSnap = await db.doc("config/pricing").get();
    const pricing = pricingSnap.data();
    const modelPricing = pricing.models["claude-sonnet-4-6"];

    const inputCost =
      ((usage.input_tokens || 0) / 1000000) * modelPricing.inputPerMTok;
    const outputCost =
      ((usage.output_tokens || 0) / 1000000) * modelPricing.outputPerMTok;
    const cacheReadCost =
      ((usage.cache_read_input_tokens || 0) / 1000000) *
      modelPricing.inputPerMTok *
      modelPricing.cacheReadMultiplier;
    const totalCost = inputCost + outputCost + cacheReadCost;

    // ── Batch write (atomic) ───────────────────────────────────────────
    const batch = db.batch();
    const activityRef = db.collection(`users/${uid}/aiActivity`).doc();
    const now = FieldValue.serverTimestamp();
    const month = new Date().toISOString().slice(0, 7);

    // 1. Activity log
    batch.set(activityRef, {
      id: activityRef.id,
      tool: tool || "cv",
      type: "aiRewrite",
      status: "success",
      documentId: documentId || null,
      documentTitle: documentTitle || null,
      templateId: templateId || null,
      sectionType: sectionType,
      sectionTitle: null,
      tokens: {
        inputTokens: usage.input_tokens || 0,
        outputTokens: usage.output_tokens || 0,
        cacheReadTokens: usage.cache_read_input_tokens || 0,
        cacheCreationTokens: usage.cache_creation_input_tokens || 0,
      },
      cost: { inputCost, outputCost, cacheReadCost, totalCost },
      model: "claude-sonnet-4-6",
      rewriteOptions: { mode: rewriteMode, scope: "section" },
      spellcheckSummary: null,
      detailsPath: `users/${uid}/ai_details/${activityRef.id}.json`,
      errorMessage: null,
      createdAt: now,
      durationMs,
    });

    // 2. Increment rewrite counter
    batch.update(subRef, {
      aiRewriteCount: FieldValue.increment(1),
    });

    // 3. Analytics summary
    const summaryRef = db.doc(`users/${uid}/analytics/summary`);
    batch.set(
      summaryRef,
      {
        totalAiRewrites: FieldValue.increment(1),
        totalTokensUsed: FieldValue.increment(
          (usage.input_tokens || 0) + (usage.output_tokens || 0)
        ),
        totalCostUsd: FieldValue.increment(totalCost),
        lastActiveAt: now,
      },
      { merge: true }
    );

    // 4. Monthly analytics
    const monthRef = db.doc(`users/${uid}/analytics/${month}`);
    batch.set(
      monthRef,
      {
        month,
        aiRewrites: FieldValue.increment(1),
        cvAiRewrites: FieldValue.increment(1),
        totalInputTokens: FieldValue.increment(usage.input_tokens || 0),
        totalOutputTokens: FieldValue.increment(usage.output_tokens || 0),
        totalCost: FieldValue.increment(totalCost),
        updatedAt: now,
      },
      { merge: true }
    );

    await batch.commit();

    // ── Upload detail to Storage (fire-and-forget) ─────────────────────
    try {
      const bucket = getStorage().bucket();
      const detailPath = `users/${uid}/ai_details/${activityRef.id}.json`;
      const detailJson = JSON.stringify({
        tool: tool || "cv",
        type: "aiRewrite",
        sectionType,
        scope: "section",
        mode: rewriteMode,
        customInstruction: customInstruction || null,
        beforeText: text,
        afterText: content,
      });
      await bucket.file(detailPath).save(detailJson, {
        contentType: "application/json",
      });
    } catch (storageErr) {
      console.warn("Detail upload failed (non-critical):", storageErr.message);
    }

    // ── Return content only ────────────────────────────────────────────
    return { content };
  }
);