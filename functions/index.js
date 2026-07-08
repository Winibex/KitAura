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

const { Resend } = require("resend");
const RESEND_API_KEY = defineSecret("RESEND_API_KEY");

const FROM_EMAIL = '"KitAura" <noreply@kitaura.winibex.com>';
const SUPPORT_EMAIL = "support@kitaura.winibex.com";
const APP_URL = "https://app-kitaura.winibex.com";

// ════════════════════════════════════════════════════════════════════════
// HELPERS
// ════════════════════════════════════════════════════════════════════════

async function callClaude({ model, system, userContent, messages, maxTokens, apiKey }) {
  const msgs = messages || [{ role: "user", content: userContent }];
  const res = await axios.post(
    ANTHROPIC_URL,
    { model, max_tokens: maxTokens, system, messages: msgs },
    {
      headers: {
        "content-type": "application/json",
        "x-api-key": apiKey,
        "anthropic-version": API_VERSION,
        "anthropic-beta": "prompt-caching-2024-07-31",
      },
      timeout: 300000,
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
        editorAiCount: 0, editorAiRefusalCount: 0,
        editorAiHourlyCount: 0,
        editorAiHourlyResetAt: null,
        cycleStartDate: admin.firestore.Timestamp.fromDate(now),
        cycleEndDate: admin.firestore.Timestamp.fromDate(newEnd),
        lastResetDate: admin.firestore.Timestamp.fromDate(now),
      });
      sub.aiFillCount = 0; sub.aiRewriteCount = 0;
      sub.aiDesignCount = 0; sub.exportCount = 0; sub.spellcheckCount = 0;
      sub.editorAiCount = 0; sub.editorAiRefusalCount = 0;
      sub.editorAiHourlyCount = 0;
      sub.editorAiHourlyResetAt = null;
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

async function checkCombinedAiContentPaywall(sub) {
  // Pro/trial: enforce 100/month combined cap.
  // Free: enforce 15/month combined cap.
  // Trial = pro-equivalent.
  const isPro = sub.plan === "pro" || (sub.plan === "trial" && sub.trialActive);
  const used = (sub.aiFillCount || 0) + (sub.aiRewriteCount || 0);
  const max = isPro ? 100 : 15;

  if (used >= max) {
    const upgradeNote = isPro
      ? ""
      : " Upgrade to Pro for 100 per month.";
    throw new HttpsError(
      "resource-exhausted",
      `You've used all ${max} AI Compose + Refine calls this cycle.${upgradeNote}`
    );
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

  // 2. subscription counter (skip if not provided — used for chat mid-turns)
    if (counterField) {
      const subRef = db.doc(`users/${uid}/data/subscription`);
      batch.update(subRef, { [counterField]: FV.increment(1) });
    }

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

async function trackFailure({ uid, tool, type, errorMessage, durationMs,
  documentId = null, documentTitle = null, templateId = null,
  sectionType = null, sectionTitle = null, model = null,
  partialUsage = null }) {
  try {
    const now = admin.firestore.Timestamp.fromDate(new Date());
    const actRef = db.collection(`users/${uid}/aiActivity`).doc();
    await actRef.set({
      id: actRef.id,
      tool,
      type,
      status: "error",
      model,
      documentId,
      documentTitle,
      templateId,
      sectionType,
      sectionTitle,
      rewriteOptions: null,
      spellcheckSummary: null,
      errorMessage: (errorMessage || "Unknown error").slice(0, 500),
      tokens: {
        inputTokens: (partialUsage && partialUsage.input_tokens) || 0,
        outputTokens: (partialUsage && partialUsage.output_tokens) || 0,
        cacheReadTokens: (partialUsage && partialUsage.cache_read_input_tokens) || 0,
        cacheCreationTokens: (partialUsage && partialUsage.cache_creation_input_tokens) || 0,
      },
      cost: { inputCost: 0, outputCost: 0, cacheReadCost: 0, totalCost: 0 },
      durationMs: durationMs || 0,
      createdAt: now,
    });
  } catch (e) {
    console.error("trackFailure failed (non-critical):", e.message);
  }
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

exports.aiFill = onCall({ secrets: [ANTHROPIC_KEY], region: "us-central1", timeoutSeconds: 300, enforceAppCheck: true }, async (req) => {
  if (!req.auth) throw new HttpsError("unauthenticated", "Sign in required.");
  const uid = req.auth.uid;
  const t0 = Date.now();
  const { sectionType="custom", tone="professional", experienceLevel="mid", profile={},
    tool="cv", documentId=null, documentTitle=null, templateId=null, sectionTitle=null,
    beforeText="", jobDetails=null, cvContent=null } = req.data || {};

  const { sub } = await getSubWithCycleCheck(uid);
    // For clientChat, skip the combined cap — we only "charge" when the
    // conversation completes (handled in writeTracking decision below).
    // The 20-turn server-side cap on transcript length is the real safety net.
    if (tool !== "clientChat") {
      await checkCombinedAiContentPaywall(sub);
    }

  const pSnap = await db.doc("config/pricing").get();
  const rates = pSnap.exists ? pSnap.data().models[MODEL_SONNET] : { inputPerMTok:3, outputPerMTok:15, cacheReadMultiplier:0.1 };

  // ── Build system prompt based on tool ────────────────────────────
  let sys;

  if (tool === "coverLetter" && sectionType === "all") {
    // ── COVER LETTER: GENERATE ALL SECTIONS ──────────────────────
    sys = [{
      type: "text",
      text: `You are an expert cover letter writer. Generate a complete, professional cover letter.

OUTPUT: Return ONLY a JSON object with these keys:
{
  "senderAddress": { "heading": "", "entries": [{"title": "", "lines": ["name", "address", "contact info"]}] },
  "recipientAddress": { "heading": "", "entries": [{"title": "", "lines": ["hiring manager name", "title", "company", "address"]}] },
  "dateLine": { "heading": "", "entries": [{"title": "", "lines": ["formatted date"]}] },
  "salutation": { "heading": "", "entries": [{"title": "", "lines": ["Dear ..."]}] },
  "coverLetterBody": { "heading": "", "entries": [{"title": "", "lines": ["paragraph1", "paragraph2", "paragraph3", "paragraph4"]}] },
  "closing": { "heading": "", "entries": [{"title": "", "lines": ["Sincerely,"]}] },
  "signature": { "heading": "", "entries": [{"title": "", "lines": ["Full Name"]}] }
}

RULES:
- No markdown or code fences. JSON only.
- The cover letter body should have 3-4 paragraphs.
- Paragraph 1: Express interest in the role and company.
- Paragraph 2: Highlight relevant experience and achievements from the CV.
- Paragraph 3: Show knowledge of the company and why you're a good fit.
- Paragraph 4: Call to action and thank you.
- Use the job description to tailor content specifically.
- Use the CV content to reference real achievements, skills, and experience.
- Never invent facts — only use what's in the CV and profile.
- Tone: ${tone}. Experience level: ${experienceLevel}.
- Keep total body under 350 words.`,
      cache_control: { type: "ephemeral" },
    }];
  } else if (tool === "coverLetter") {
    // ── COVER LETTER: SINGLE SECTION ─────────────────────────────
    sys = [{
      type: "text",
      text: `You are an expert cover letter writer. Generate content for a specific cover letter section.

OUTPUT: Return ONLY a JSON object: {"heading":"","entries":[{"title":"","lines":["content"]}]}

SECTION FORMATS:
- senderAddress → lines: [full name, address, email | phone]
- recipientAddress → lines: [hiring manager name, title, company, address, city]
- dateLine → lines: [formatted date like "June 6, 2026"]
- salutation → lines: ["Dear [name],"] or "Dear Hiring Manager,"
- coverLetterBody → lines: [paragraph1, paragraph2, paragraph3, paragraph4] (3-4 paragraphs, under 300 words total)
- closing → lines: ["Sincerely,"]
- signature → lines: [full name]

RULES:
- No markdown or code fences. JSON only.
- Never invent facts — only use data from profile and job details.
- Tone: ${tone}. Level: ${experienceLevel}.`,
      cache_control: { type: "ephemeral" },
    }];

    } else if (tool === "linkedin" && sectionType === "all") {
        // ── LINKEDIN: GENERATE ALL SECTIONS ──────────────────────
        const selectedSections = (jobDetails?.selectedSections || []).join(", ");
        const customPrompt = jobDetails?.customPrompt || "";
        sys = [{
          type: "text",
          text: `You are an expert LinkedIn profile writer. Generate optimized LinkedIn content.

    The user wants these sections generated: ${selectedSections}

    OUTPUT: Return ONLY a JSON object. Include ONLY the requested section keys.
    Available keys and their formats:

    "headline": "string — max 220 chars, keyword-rich, pipe-separated phrases"

    "about": "string — 3-4 paragraphs, first-person, engaging opening hook, achievements with metrics, call to action at end, under 2600 chars"

    "experiences": [{"role": "Job Title — Company", "description": "2-3 paragraphs rewritten for LinkedIn — first person, achievement-focused, metrics where possible"}]

    "education": [{"degree": "Degree — School", "description": "1-2 sentences, relevant coursework or achievements"}]

    "skills": ["Skill1", "Skill2", ...] — ordered by relevance, include industry keywords, max 20

    "projects": [{"name": "Project Name", "description": "2-3 sentences, impact-focused, technologies used"}]

    "certifications": [{"name": "Cert Name — Issuer", "description": "1 sentence about relevance"}]

    "volunteer": [{"role": "Role — Organization", "description": "1-2 sentences about impact"}]

    RULES:
    - No markdown or code fences. JSON only.
    - Write in first person ("I" not "they").
    - Include relevant industry keywords naturally for LinkedIn SEO.
    - Focus on achievements and metrics, not just responsibilities.
    - Make content engaging and professional.
    - Never invent facts — only use data from the CV and profile.
    - Tone: ${tone}. Experience level: ${experienceLevel}.
    ${customPrompt ? "Additional instructions: " + customPrompt : ""}`,
          cache_control: { type: "ephemeral" },
        }];
      } else if (tool === "linkedin") {
        // ── LINKEDIN: SINGLE SECTION REGENERATE ──────────────────
        sys = [{
          type: "text",
          text: `You are an expert LinkedIn profile writer. Regenerate content for the "${sectionType}" section.

    OUTPUT: Return ONLY a JSON object in the format for this section type:
    - headline: {"heading":"","entries":[{"title":"","lines":["headline text"]}]}
    - about: {"heading":"","entries":[{"title":"","lines":["paragraph1","paragraph2","paragraph3"]}]}
    - experiences: {"heading":"","entries":[{"title":"Role — Company","lines":["description"]}]}
    - education: {"heading":"","entries":[{"title":"Degree — School","lines":["description"]}]}
    - skills: {"heading":"","entries":[{"title":"","lines":["Skill1","Skill2",...]}]}
    - projects: {"heading":"","entries":[{"title":"Project Name","lines":["description"]}]}
    - certifications: {"heading":"","entries":[{"title":"Cert — Issuer","lines":["description"]}]}
    - volunteer: {"heading":"","entries":[{"title":"Role — Org","lines":["description"]}]}

    RULES:
    - No markdown. JSON only.
    - First person. Achievement-focused. Include metrics.
    - Never invent facts. Tone: ${tone}. Level: ${experienceLevel}.`,
          cache_control: { type: "ephemeral" },
        }];


} else if (tool === "proposal" && sectionType === "all") {
    // ── PROPOSAL: GENERATE WHOLE PROPOSAL (text + tables) ──────────
    const manifest = Array.isArray(req.data.sectionManifest) ? req.data.sectionManifest : [];
    const manifestDesc = manifest.map((s) => {
          if (s.kind === "table") {
            const maxRows = s.maxRows ? `, exactly ${s.maxRows} data rows` : "";
            return `- id "${s.id}" — ${s.title || s.sectionType} (TABLE, columns: [${(s.headers || []).join(", ")}]${maxRows})`;
          }
          const shape = s.shape ? `, SHAPE=${s.shape}` : "";
          return `- id "${s.id}" — ${s.title || s.sectionType} (TEXT${shape})`;
        }).join("\n");

    sys = [{
      type: "text",
      text: `You are an expert proposal writer. Generate a complete, coherent client proposal where every section reinforces the others (the solution addresses the stated problem, pricing matches the deliverables, timeline aligns with scope).

      You will receive: the sender's profile, a client brief (the client, their project, goals, budget, deliverables, milestones), optionally the sender's CV, and a SECTION MANIFEST listing each section to fill.

      SECTION MANIFEST:
      ${manifestDesc}

      OUTPUT: Return ONLY a JSON object keyed by the exact section id strings above. No markdown, no code fences.

      HOW THE SHAPE RENDERS (use it deliberately):
      Each TEXT section is {"kind":"text","heading":"","entries":[ {"title":"","lines":["",...]} ]}.
        - "heading": usually leave "" (the section already has a styled heading on the page).
        - Each entry "title" renders as a BOLD label line.
        - Each entry "lines" render as normal body text under that label (one line each).
      So:
        - PROSE section (executive summary, problem, overview, about) = ONE entry, title "", lines = 1-2 short paragraphs.
        - LABELLED section (a phased solution, or clauses when SHAPE=clauses) = MANY entries, each title = the bold label, lines = the short body. This is how you make bold labels. Only do this when the section's SHAPE is phases or clauses. Do NOT write "**label:**" markdown inside a line; put the label in "title".
        - Pure BULLET list = ONE entry, title "", each bullet its own line starting with "• ".

      SHAPE GUIDE — produce exactly the structure for each section's SHAPE:
        - SHAPE=prose      → ONE entry, title "", lines = 1-2 short paragraphs.
        - SHAPE=phases     → MANY entries, each title = phase label (e.g. "Phase 1: Discovery & Planning"), lines = ONE short sentence. 3-5 phases max.
        - SHAPE=clauses    → MANY entries, each title = clause label (e.g. "Payment Schedule", "Scope Changes"), lines = ONE concise sentence. 4-7 clauses max.
        - SHAPE=bullets    → EXACTLY ONE entry with title "" (empty). Every line is one flat bullet starting with "• ". Do NOT split into multiple entries. Do NOT put bold labels in "title". Do NOT create sub-headings or a label+body (clause) structure even if the section is called "Terms" or "Conditions" — keep it a single flat bulleted list.
        - SHAPE=numbered   → ONE entry, title "", each line starts with "1. " then "2. " etc.
        - SHAPE=oneLiner   → ONE entry, title "", lines = ONE short sentence. Do NOT add multiple entries or clauses.
        - SHAPE=titleLine  → ONE entry, title = the project title (bold), lines = ONE short subtitle/tagline (one sentence).
        - No SHAPE given   → infer from the title using your best judgment, defaulting to prose.

      For TABLE sections, generate EXACTLY the declared "data rows" count when stated. Do not add or remove rows.

      For TABLE sections, the value is:
        {"kind":"table","rows":[["cell","cell","cell"], ...]}
        - Each row MUST have exactly the same number of cells as the declared columns, in column order.
        - Do NOT include the header row — only data rows.
        - For pricing tables use the client's line items and budget; include a total row if a total column exists.
        - Amounts as plain strings (e.g. "$2,500"), no math errors.

      RULES:
      - Return EVERY section id from the manifest as a key.
      - Keep it tight: labels short, bodies 1-2 sentences. No filler, no repetition.
      - Never invent facts not supported by the brief/profile. If data is thin, write professional generic content rather than fabricating specifics.
      - Tone: ${tone}. Experience level: ${experienceLevel}.`,
      cache_control: { type: "ephemeral" },
    }];
  } else if (tool === "proposal") {
    // ── PROPOSAL: SINGLE SECTION (reuses CV-style shape) ──────────
    sys = [{
      type: "text",
      text: `You are an expert proposal writer. Generate content for one proposal section.
OUTPUT: Return ONLY a JSON object: {"heading":"","entries":[{"title":"","lines":["content"]}]}
RULES: No markdown/code fences. Never invent facts. Tone: ${tone}. Level: ${experienceLevel}.`,
      cache_control: { type: "ephemeral" },
    }];

  } else if (tool === "clientExtract") {
      // ── CLIENT PROFILE EXTRACTION (free-text brief → structured model) ──
      sys = [{
        type: "text",
        text: `You read a free-text project/sales brief and extract a structured client profile for a proposal builder. Output ONLY a JSON object (no markdown, no code fences) with EXACTLY these keys:
  {
    "clientName": "string",
    "clientCompany": "string|null",
    "clientEmail": "string|null",
    "clientPhone": "string|null",
    "clientWebsite": "string|null",
    "industry": "string|null",
    "projectTitle": "string",
    "projectType": "development|design|marketing|consulting|product|service|general",
    "projectDescription": "string|null",
    "problemStatement": "string|null",
    "projectGoals": ["string"],
    "deliverables": [{"name":"string","description":"string|null"}],
    "scopeNotes": "string|null",
    "startDate": "string|null",
    "endDate": "string|null",
    "milestones": [{"title":"string","date":"string|null","description":"string|null"}],
    "budgetRange": "string|null",
    "pricingModel": "fixed|hourly|retainer|milestone|per-unit|null",
    "lineItems": [{"item":"string","description":"string|null","amount":number|null}],
    "competitorInfo": "string|null",
    "specialRequirements": "string|null",
    "customNotes": "string|null",
    "typeSpecific": {
      "techStack": ["string"],
      "platformTargets": "string|null",
      "integrationNeeds": "string|null",
      "sprintCount": number|null,
      "brandGuidelines": boolean|null,
      "designRevisions": number|null,
      "creativeBrief": "string|null",
      "channels": ["string"],
      "targetAudience": "string|null",
      "campaignGoals": "string|null",
      "kpiMetrics": ["string"],
      "warrantyTerms": "string|null",
      "shippingTerms": "string|null",
      "paymentTerms": "string|null",
      "productItems": [{"name":"string","sku":"string|null","quantity":number,"unitPrice":number}],
      "taxPercent": number|null,
      "shippingCost": number|null
    }
  }
  RULES:
  - Infer "projectType" from the brief. If it's selling physical goods (e.g. shoes, equipment), use "product" and fill typeSpecific.productItems (name/quantity/unitPrice) — do NOT use deliverables/milestones for products.
  - If software/app/web build → "development" (fill techStack/platformTargets). Branding/graphics → "design". Campaigns/SEO/ads → "marketing". Advisory → "consulting". Ongoing service → "service". Otherwise "general".
  - Only fill what the brief actually states or strongly implies. Leave everything else null or empty arrays. NEVER invent client names, emails, phone numbers, or amounts that aren't given.
  - projectGoals/deliverables/milestones: extract only if the brief mentions them.
  - Keep strings concise.
  - Output ONLY the JSON object.`,
        cache_control: { type: "ephemeral" },
      }];

    } else if (tool === "clientChat") {
      // ── CLIENT INTERVIEW (multi-turn → asks questions, returns envelope) ──
      sys = [{
        type: "text",
        text: `You interview a freelancer/agency to build a client profile for a proposal, asking ONLY for information that maps to the allowed fields below. You are strict: never ask for anything outside these fields, never invent field keys.

ALLOWED FIELD KEYS (use these exact keys):
clientName, clientCompany, clientEmail, clientPhone, clientWebsite, industry,
clientTaxId, projectTitle, projectType, projectDescription, problemStatement,
projectGoals, deliverables, scopeNotes, startDate, endDate, milestones,
budgetRange, pricingModel, lineItems, competitorInfo, specialRequirements,
customNotes, techStack, platformTargets, integrationNeeds, sprintCount,
brandGuidelines, designRevisions, creativeBrief, channels, targetAudience,
campaignGoals, kpiMetrics, warrantyTerms, shippingTerms, paymentTerms,
productItems, taxPercent, shippingCost

projectType is one of: development, design, marketing, consulting, product, service, general.

FLOW:
1. Read everything the user has said so far. Infer projectType early.
2. Ask ONLY for fields that the detected type needs and that are still missing or unclear:
   - product (selling physical goods): productItems (name/qty/unitPrice), taxPercent, shippingCost, warrantyTerms, shippingTerms, endDate (delivery/lead time), client + tax fields. DO NOT ask for problemStatement, projectGoals, milestones, deliverables.
   - development: techStack, platformTargets, integrationNeeds, deliverables, milestones, budget/pricing, problem/goals.
   - design: creativeBrief, brandGuidelines, designRevisions, deliverables, milestones, pricing.
   - marketing: channels, targetAudience, campaignGoals, kpiMetrics, deliverables, pricing.
   - consulting: problemStatement, projectGoals, deliverables, milestones, pricing.
   - service: deliverables, paymentTerms, pricing, milestones.
3. Group related fields into ONE question (e.g. email + phone together). Ask at most ~4 fields per turn.
4. When you have enough to write a solid proposal, output mode "complete".

OUTPUT — return ONLY a JSON object (no markdown, no code fences), one of:

A) Ask for info:
{ "mode":"question",
  "intro":"short sentence introducing what you need",
  "fields":[
    {"key":"<allowed key>","label":"Human label","type":"text","hint":"optional hint"},
    {"key":"pricingModel","label":"Pricing Model","type":"choice","options":["Fixed","Hourly","Retainer","Milestone"],"allowCustom":true}
  ]
}
- "type" is "text" or "choice". For "choice", include "options" and "allowCustom" (true/false).
- For list fields (productItems, deliverables, milestones, lineItems, projectGoals, techStack, channels, kpiMetrics) use type "text" and tell the user in the label/hint to separate entries with commas or new lines.

B) Finished:
{ "mode":"complete",
  "profile": { ...a full ClientProfileModel JSON using the same keys/shape as the extract format, including a "typeSpecific" object... } }

RULES:
- Never ask for a field not in the allowed list.
- Never fabricate values the user didn't give. Unknown → leave null/empty in the final profile.
- Keep labels and intros short and friendly.
- Prefer fewer, well-grouped turns. Don't drag the interview out.
- Tone: ${tone}.
- For STRING-typed fields (everything declared as "string|null" in the profile schema), output a single string or null — NEVER an array. If you have multiple points, join them with semicolons or commas inside ONE string. This applies to ALL: clientName, clientCompany, clientEmail, clientPhone, clientWebsite, industry, clientTaxId, projectTitle, projectDescription, problemStatement, scopeNotes, startDate, endDate, budgetRange, pricingModel, competitorInfo, specialRequirements, customNotes, platformTargets, integrationNeeds, creativeBrief, targetAudience, campaignGoals, warrantyTerms, shippingTerms, paymentTerms.
  - CORRECT:   "specialRequirements": "Security and data privacy must be enforced"
  - WRONG:     "specialRequirements": ["Security", "Data privacy"]
- For NUMBER-typed fields (sprintCount, designRevisions, taxPercent, shippingCost, unitPrice,
quantity, amount), output a number or null — NEVER a string. CORRECT: 17. WRONG: "17%".
- For list fields whose schema is an array of OBJECTS, every entry MUST be an object with the
declared keys — NEVER a bare string. This applies to: deliverables, milestones, lineItems, productItems.
  - CORRECT:   "deliverables": [{"name":"Mobile app","description":null}, {"name":"Backend API","description":null}]
  - WRONG:     "deliverables": ["Mobile app", "Backend API"]
  - If the user only gave a name, still wrap it: {"name":"Mobile app","description":null}.
  - If the list is empty, return [] — never null, never a string.
- For list fields whose schema is an array of STRINGS,
every entry MUST be a string — never an object. This applies to: projectGoals,
techStack, channels, kpiMetrics.`,
        cache_control: { type: "ephemeral" },
      }];

    } else {
    // ── CV: ORIGINAL PROMPT (unchanged) ──────────────────────────
    sys = [{
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
  }

  // ── Build user content ───────────────────────────────────────────
  let userContent = `Section: ${sectionType}\n\nProfile:\n${JSON.stringify(profile,null,2)}`;

  if (tool === "coverLetter" || tool === "linkedin") {
      if (jobDetails) userContent += `\n\nJob Details:\n${JSON.stringify(jobDetails, null, 2)}`;
      if (cvContent) userContent += `\n\nCandidate's CV Content:\n${cvContent}`;
    }
    if (tool === "proposal") {
      if (jobDetails) userContent += `\n\nClient Brief:\n${JSON.stringify(jobDetails, null, 2)}`;
      if (cvContent) userContent += `\n\nSender's CV Content:\n${cvContent}`;
    }
    if (tool === "clientExtract") {
      userContent = `Brief:\n${req.data.briefText || ""}\n\nExtract the client profile now. JSON only.`;
    }

  // ── Multi-turn transcript for clientChat ──────────────────────────
  // The frontend holds the conversation in memory and resends it each turn
  // (Claude is stateless — this is how "memory" works). We cap length and
  // pass it as the messages array; userContent is ignored for this tool.
  let chatMessages = null;
  if (tool === "clientChat") {
    const turns = Array.isArray(req.data.messages) ? req.data.messages : [];
    chatMessages = turns
      .filter((m) => m && (m.role === "user" || m.role === "assistant") && typeof m.content === "string")
      .slice(-20) // safety cap on transcript length
      .map((m) => ({ role: m.role, content: m.content }));
    if (chatMessages.length === 0) {
      chatMessages = [{ role: "user", content: req.data.briefText || "Let's start." }];
    }
  }

  if (tool !== "clientExtract" && tool !== "clientChat") {
      userContent += "\n\nWrite now. JSON only.";
    }

  const maxTok = (tool === "proposal" && sectionType === "all") ? 8192
      : (tool === "clientExtract" || tool === "clientChat") ? 4096 : 2048;

  let text, usage;
    try {
      const r = await callClaude({ model: MODEL_SONNET, system: sys,
        userContent, messages: chatMessages, maxTokens: maxTok,
        apiKey: ANTHROPIC_KEY.value() });
      text = r.text; usage = r.usage;
    } catch (err) {
      console.error("aiFill API error:", err?.response?.data || err.message);
      await trackFailure({
        uid, tool, type: "aiFill",
        errorMessage: err?.message || "API call failed",
        durationMs: Date.now() - t0,
        documentId, documentTitle, templateId, sectionType, sectionTitle,
        model: MODEL_SONNET,
      });
      throw new HttpsError("internal", "AI generation failed.");
    }

  let cleaned = text.replace(/```json/g, "").replace(/```/g, "").trim();
    // Salvage: if there's leading/trailing prose, extract the outermost JSON object.
    const firstBrace = cleaned.indexOf("{");
    const lastBrace = cleaned.lastIndexOf("}");
    if (firstBrace > 0 || (lastBrace !== -1 && lastBrace < cleaned.length - 1)) {
      if (firstBrace !== -1 && lastBrace !== -1 && lastBrace > firstBrace) {
        cleaned = cleaned.slice(firstBrace, lastBrace + 1);
      }
    }
    let content;
    try {
      content = JSON.parse(cleaned);
    } catch (e) {
      console.error("aiFill parse error. Length:", cleaned.length,
        "| Last 200 chars:", cleaned.slice(-200));
      throw new HttpsError("internal", "AI returned malformed content.");
    }

  // For CL "all" mode, validate we got section keys
  if (((tool === "coverLetter" || tool === "linkedin") && sectionType === "all") ||
          (tool === "proposal" && sectionType === "all") ||
          (tool === "clientExtract") || (tool === "clientChat")) {
        if (typeof content !== "object") throw new HttpsError("internal", "Unexpected AI output.");
      } else {
      if (typeof content !== "object" || !Array.isArray(content.entries)) {
        throw new HttpsError("internal", "Unexpected AI output.");
      }
    }

  const cost = calculateCost(usage, rates);

    // ── Counter decision (Phase E10) ──────────────────────────────
    // For clientChat: only charge a credit when the conversation actually
    // produces a complete client profile. Mid-turn questions are tracked
    // for cost visibility but don't burn the user's monthly allowance.
    let counterField = "aiFillCount";
    let monthlyToolField = `${tool}AiFills`;
    if (tool === "clientChat") {
      const isComplete = content && content.mode === "complete";
      if (!isComplete) {
        counterField = null;          // skip counter bump
        monthlyToolField = null;      // skip monthly tool counter
      }
    }

    const actId = await writeTracking({ uid,
      data: { tool, type:"aiFill", status:"success", model:MODEL_SONNET,
        documentId, documentTitle, templateId, sectionType, sectionTitle,
        rewriteOptions:null, spellcheckSummary:null, errorMessage:null, durationMs:Date.now()-t0 },
      counterField, summaryField:"totalAiFills",
      monthlyField:"aiFills", monthlyToolField, tokens:usage, cost });


  uploadDetail(uid, actId, { tool, type:"aiFill", sectionType, beforeText,
    afterText:JSON.stringify(content), generatedContent:content,
    profileSnapshot:{ jobTitle:profile.jobTitle||"", experienceLevel, tone },
    jobDetails: jobDetails || null });

  return { content };
});

// ════════════════════════════════════════════════════════════════════════
// 2. SPELLCHECK — free, tracked
// ════════════════════════════════════════════════════════════════════════

exports.spellcheck = onCall({ secrets: [ANTHROPIC_KEY], region: "us-central1", timeoutSeconds: 60, enforceAppCheck: true }, async (req) => {
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
      const r = await callClaude({ model: MODEL_HAIKU, system: sys,
        userContent: `Check spelling:\n\n${txt}`, maxTokens: 1024, apiKey: ANTHROPIC_KEY.value() });
      result = r.text;
      usage = r.usage;
    } catch (err) {
      console.error("spellcheck error:", err?.response?.data || err.message);
      await trackFailure({
        uid, tool, type: "spellcheck",
        errorMessage: err?.message || "API call failed",
        durationMs: Date.now() - t0,
        documentId, documentTitle,
        model: MODEL_HAIKU,
      });
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

exports.aiRewrite = onCall({ secrets: [ANTHROPIC_KEY], region: "us-central1", timeoutSeconds: 120, enforceAppCheck: true }, async (req) => {
  if (!req.auth) throw new HttpsError("unauthenticated", "Sign in required.");
  const uid = req.auth.uid;
  const t0 = Date.now();
  const { text="", sectionType="custom", mode="professional", customInstruction=null,
    tool="cv", documentId=null, documentTitle=null, templateId=null, sectionTitle=null } = req.data || {};

  if (!text || !sectionType) throw new HttpsError("invalid-argument", "Missing text or sectionType");

  const { sub } = await getSubWithCycleCheck(uid);
  await checkCombinedAiContentPaywall(sub);

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
      await trackFailure({
        uid, tool, type: "aiRewrite",
        errorMessage: err?.message || "API call failed",
        durationMs: Date.now() - t0,
        documentId, documentTitle, templateId, sectionType, sectionTitle,
        model: MODEL_SONNET,
      });
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

  const toolMap = {
    cv:          { sub: "cvCount",          sum: "totalCvsCreated",          mon: "cvsCreated",          tx: "cvCreated" },
    coverLetter: { sub: "coverLetterCount", sum: "totalCoverLettersCreated", mon: "coverLettersCreated", tx: "coverLetterCreated" },
    proposal:    { sub: "proposalCount",    sum: "totalProposalsCreated",    mon: "proposalsCreated",    tx: "proposalCreated" },
  };
  const fields = toolMap[tool];
  if (!fields) throw new HttpsError("invalid-argument", `Unknown tool: ${tool}`);

  // ── NEW: Combined doc cap (5 free / 30 pro) ────────────────────
  const subRef = db.doc(`users/${uid}/data/subscription`);
  const subSnap = await subRef.get();
  if (subSnap.exists) {
    const sub = subSnap.data();
    const isPro = sub.plan === "pro" || (sub.plan === "trial" && sub.trialActive);
    const totalDocs = (sub.cvCount || 0) + (sub.coverLetterCount || 0) + (sub.proposalCount || 0);
    const maxDocs = isPro ? 30 : 5;
    if (totalDocs >= maxDocs) {
      const upgradeNote = isPro
        ? " Contact support if you need more."
        : " Upgrade to Pro for up to 30 documents.";
      throw new HttpsError(
        "resource-exhausted",
        `You've reached the ${maxDocs}-document limit.${upgradeNote}`
      );
    }
  }
  // ── END NEW ─────────────────────────────────────────────────────

  const batch = db.batch();
  const now = admin.firestore.Timestamp.fromDate(new Date());
  const FV = admin.firestore.FieldValue;
  const month = new Date().toISOString().slice(0, 7);

  // 1. Subscription doc counter
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

// ════════════════════════════════════════════════════════════════════════
// 10. AI EDIT — natural-language editor commands (command-K)
// ════════════════════════════════════════════════════════════════════════
//
// Returns a list of structured ops the frontend applies to CanvasController.
// Strict abuse prevention:
//   - System prompt enforces refusal envelope for off-topic requests
//   - max_tokens 1024 cap (legit op envelope fits easily; off-topic content can't)
//   - Server-side refusal counter; 5 refusals/cycle → soft block (free + pro alike)
//   - Separate editorAiCount paywall counter, free=15/month, trial/pro=unlimited
//
// Ops returned (11 total) — see /docs op format v2:
//   updateText, formatText, updateItem, moveItem, deleteItem, duplicateItem,
//   addItem, updateCanvas, generateContent, updateTable, updateReflow

exports.aiEdit = onCall({ secrets: [ANTHROPIC_KEY], region: "us-central1", timeoutSeconds: 60, enforceAppCheck: true }, async (req) => {
  if (!req.auth) throw new HttpsError("unauthenticated", "Sign in required.");
  const uid = req.auth.uid;
  const t0 = Date.now();
  const {
    instruction = "",
    snapshot = null,           // { pageCount, canvasBackground, items: [...] }
    tool = "cv",               // cv | coverLetter | proposal
    documentId = null,
    documentTitle = null,
    templateId = null,
  } = req.data || {};

  if (!instruction || !instruction.trim()) {
    throw new HttpsError("invalid-argument", "Please type what you want to change.");
  }
  if (!snapshot || !Array.isArray(snapshot.items)) {
    throw new HttpsError("invalid-argument", "Editor state missing — try reloading the page.");
  }

  // ── Billing cycle + paywall ────────────────────────────────────
  // ── Billing cycle + paywall ────────────────────────────────────
    const { sub, ref: subRef } = await getSubWithCycleCheck(uid);

    // Monthly cap (7 free / 100 pro)
    const isPro = sub.plan === "pro" || (sub.plan === "trial" && sub.trialActive);
    const monthlyUsed = sub.editorAiCount || 0;
    const monthlyMax = isPro ? 100 : 7;
    if (monthlyUsed >= monthlyMax) {
      const upgradeNote = isPro
        ? ""
        : " Upgrade to Pro for 100 per month.";
      throw new HttpsError(
        "resource-exhausted",
        `You've used all ${monthlyMax} AI Assistant calls this cycle.${upgradeNote}`
      );
    }

    // Refusal soft-block (5/cycle, all tiers)
    const refusalCount = sub.editorAiRefusalCount || 0;
    if (refusalCount >= 5) {
      throw new HttpsError(
        "resource-exhausted",
        "AI Assistant is for editing this document only. You've made several off-topic requests this cycle — it'll reset next cycle."
      );
    }

    // Hourly burst (20/hour, Pro only — free's monthly cap is too low for hourly to matter)
    if (isPro) {
      const now = new Date();
      const hourlyResetAt = sub.editorAiHourlyResetAt ? sub.editorAiHourlyResetAt.toDate() : null;
      let hourlyCount = sub.editorAiHourlyCount || 0;

      // Reset window if it expired
      if (!hourlyResetAt || now >= hourlyResetAt) {
        hourlyCount = 0;
        const newWindow = new Date(now.getTime() + 60 * 60 * 1000); // +1 hour
        await subRef.update({
          editorAiHourlyCount: 0,
          editorAiHourlyResetAt: admin.firestore.Timestamp.fromDate(newWindow),
        });
        sub.editorAiHourlyCount = 0;
        sub.editorAiHourlyResetAt = admin.firestore.Timestamp.fromDate(newWindow);
      } else if (hourlyCount >= 20) {
        const minsLeft = Math.ceil((hourlyResetAt - now) / 60000);
        throw new HttpsError(
          "resource-exhausted",
          `You've used 20 AI Assistant calls in the last hour. Try again in ${minsLeft} minutes.`
        );
      }
    }

  // ── Pricing ────────────────────────────────────────────────────
  const pSnap = await db.doc("config/pricing").get();
  const rates = pSnap.exists ? pSnap.data().models[MODEL_SONNET]
    : { inputPerMTok: 3, outputPerMTok: 15, cacheReadMultiplier: 0.1 };

  // ── System prompt: strict gatekeeper + op schema ───────────────
  const sys = [{
    type: "text",
    text: `You are an editor AI for a document-builder app called KitAura. The user is editing a ${tool === "cv" ? "CV" : tool === "coverLetter" ? "cover letter" : "client proposal"} on a free-form canvas. Your ONLY job is to translate the user's instruction into structured JSON ops that modify the canvas. Nothing else.

YOU MUST RETURN ONLY ONE OF THESE TWO ENVELOPE SHAPES — no markdown, no code fences, no preamble:

A) OPS ENVELOPE (user asked for valid edits):
{
  "ops": [ ... ],
  "summary": "Short human-readable description of what you did.",
  "warnings": [],
  "refusal": null
}

B) REFUSAL ENVELOPE (user asked for anything that isn't editing this document):
{
  "ops": [],
  "summary": "Friendly one-sentence message redirecting them.",
  "warnings": [],
  "refusal": "off-topic"
}

C) ADVISORY MESSAGE (user is asking for opinion/advice, not an edit):
{
    "ops": [],
    "summary": "Friendly explanation that you execute edits but they decide what they want.",
    "warnings": [],
    "refusal": "advisory"
}

REFUSE these requests with envelope B:
- Writing code, scripts, or programs of any kind
- General chat, jokes, opinions, advice unrelated to the document
- Math problems, homework, translations not part of editing the document
- Anything that doesn't map to a structural edit of the canvas items below
- Requests for harmful, illegal, or unsafe content

ACCEPT these with envelope A:
- Format changes (bold, color, size, alignment, font)
- Layout changes (move, resize, rotate, delete, duplicate items)
- Content edits (rename headings, edit/delete/insert lines)
- Adding new items (sections, shapes, lines)
- Page changes (background, add/remove pages)
- AI content generation for a specific section (writing new summary text, rewriting bullets, etc.) — return as generateContent op
- Table cell edits
- Reflow tagging (pin, heading role, group)

QUESTION vs COMMAND detection:
- If the user is ASKING ("can you do X?", "is it possible to...", "what would happen if..."),
this is usually still a command in disguise — humans phrase commands as questions to be polite.
Do the work.
- BUT if the user is genuinely uncertain or seeking advice
("which color looks better?", "should I add a hobbies section?", "is my CV too long?"),
 refuse with a "message" envelope explaining you only execute edits, not give advice.
 Suggest they make the call and ask you to apply it.

THE CANVAS SNAPSHOT — every item the user can edit, with a temporary id "i0", "i1", etc.:
${JSON.stringify(snapshot, null, 2)}

EVERY op MUST reference an itemId from this snapshot (except addItem and updateCanvas). If you can't find a matching item, add a clear warning to the warnings array and skip that op.

THE 11 ALLOWED OPS — return only ops in this exact shape:

1. updateText — edit text inside a textSection
{ "op": "updateText", "itemId": "i0", "mode": "replaceLine" | "deleteLine" | "insertLine" | "replaceRange", "lineIndex": 0, "range": [start, end], "newText": "..." }

2. formatText — change Quill attributes
{ "op": "formatText", "itemId": "i0", "scope": "whole" | "line" | "range", "lineIndex": 0, "range": [start, end], "attrs": { "bold": true, "italic": null, "underline": null, "color": "#RRGGBB", "size": "14", "font": "Poppins", "align": "left"|"center"|"right" } }
(null clears an attribute. Omit keys you don't want to change.)

3. updateItem — item visual props
{ "op": "updateItem", "itemId": "i0", "props": { "color": "#RRGGBB", "borderColor": "#RRGGBB"|null, "borderWidth": 0, "rotation": 0, "flipX": false, "flipY": false, "w": 100, "h": 50 } }

4. moveItem — position / page / alignment
{ "op": "moveItem", "itemId": "i0", "toPage": 1, "align": "centerH"|"centerV"|"left"|"right"|"top"|"bottom", "x": 40, "y": 120, "dx": 0, "dy": 0 }
(Use explicit x/y when stated. align when user says "center"/"left". dx/dy for relative moves. Page is 1-based.)

5. deleteItem — remove an item
{ "op": "deleteItem", "itemId": "i0" }

6. duplicateItem — clone an item
{ "op": "duplicateItem", "itemId": "i0", "toPage": 1, "offsetY": 20 }

7. addItem — create a new item
{ "op": "addItem", "type": "textSection"|"rectangle"|"line"|"circle"|"imageBox"|"icon"|"triangle"|"star"|"arrow"|"diamond"|"hexagon"|"skewedRectangle", "page": 1, "x": 40, "y": 600, "w": 515, "h": 80, "color": "#RRGGBB", "sectionType": "hobbies"|"summary"|null, "title": "HOBBIES", "initialText": "• Reading\\n• Hiking", "role": null, "group": null }
(For textSection, set sectionType and initialText. For shapes, set color.)

8. updateCanvas — page-level
{ "op": "updateCanvas", "canvasBackground": "#RRGGBB", "pageAction": "add"|"removeLast"|"removeAt", "pageIndex": 2 }

9. generateContent — AI rewrite/generate for a target section
{ "op": "generateContent", "itemId": "i0", "sectionType": "summary"|"experience"|"skills"|..., "mode": "replace"|"append"|"rewrite", "instruction": "User's content request, e.g. 'focus on Python and ML'", "tone": "professional"|"creative"|"concise" }

10. updateTable — table cell/row/col/style edits (tableSection items)
{ "op": "updateTable", "itemId": "i0", "action": "setCell"|"setRow"|"setColumn"|"addRow"|"addColumn"|"deleteRow"|"deleteColumn"|"setHeaderStyle"|"setBorderStyle", "row": 0, "col": 0, "value": "...", "rowValues": ["a","b","c"], "style": { "headerBgColor": "#RRGGBB", "headerTextColor": "#RRGGBB", "cellTextColor": "#RRGGBB", "borderColor": "#RRGGBB", "fontSize": 11, "showHeader": true } }

11. updateReflow — reflow engine tags
{ "op": "updateReflow", "itemId": "i0", "role": "hero"|"top_band"|"pinned"|"heading"|"underline"|"signature"|null, "group": "name"|null, "beforeHeadingGap": 20 }

RULES:
- Return ONLY the JSON envelope. No prose before or after. No markdown.
- Omit op fields the user didn't specify rather than guessing values.
- Multiple ops are fine when the request implies multiple edits.
- For ambiguous targets ("the heading" when there are several), pick the most likely based on context and add a warning if uncertain.
- Keep the summary under 20 words.
- If the user combines structural + content ("delete the old summary and write a new one about X"), emit BOTH a structural op AND a generateContent op.

EXAMPLES:

User: "make the summary heading bold"
→ { "ops": [{"op":"formatText","itemId":"i0","scope":"line","lineIndex":0,"attrs":{"bold":true}}], "summary": "Made the summary heading bold.", "warnings": [], "refusal": null }

User: "write me a Python script to scrape Reddit"
→ { "ops": [], "summary": "I can only edit this document. Try asking me to format text, move sections, or rewrite content.", "warnings": [], "refusal": "off-topic" }

User: "what's the capital of France"
→ { "ops": [], "summary": "I can only edit this document. Ask me to change text, layout, or formatting.", "warnings": [], "refusal": "off-topic" }

User: "rewrite the summary to focus on my Python experience"
→ { "ops": [{"op":"generateContent","itemId":"i0","sectionType":"summary","mode":"rewrite","instruction":"focus on Python experience"}], "summary": "Rewriting the summary.", "warnings": [], "refusal": null }

User: "delete the navy bar at top and add a thinner red one"
→ { "ops": [{"op":"deleteItem","itemId":"i2"},{"op":"addItem","type":"rectangle","page":1,"x":0,"y":0,"w":595,"h":40,"color":"#831843"}], "summary": "Replaced the navy bar with a thinner red one.", "warnings": [], "refusal": null }`,
    cache_control: { type: "ephemeral" },
  }];

  // ── Call Claude with strict 1024 token cap ─────────────────────
  const userContent = `Instruction: ${instruction.trim()}\n\nReturn the JSON envelope now.`;

  let text, usage;
    try {
      const r = await callClaude({
        model: MODEL_SONNET,
        system: sys,
        userContent,
        maxTokens: 4096,
        apiKey: ANTHROPIC_KEY.value(),
      });
      text = r.text;
      usage = r.usage;
    } catch (err) {
      console.error("aiEdit API error:", err?.response?.data || err.message);
      await trackFailure({
        uid, tool: "editorAI", type: "aiEdit",
        errorMessage: err?.message || "API call failed",
        durationMs: Date.now() - t0,
        documentId, documentTitle, templateId,
        model: MODEL_SONNET,
      });
      throw new HttpsError("internal", "AI editor failed. Please try again.");
    }

  // ── Parse envelope (with JSON salvage) ─────────────────────────
  let cleaned = text.replace(/```json/g, "").replace(/```/g, "").trim();
  const first = cleaned.indexOf("{");
  const last = cleaned.lastIndexOf("}");
  if (first > 0 || (last !== -1 && last < cleaned.length - 1)) {
    if (first !== -1 && last !== -1 && last > first) {
      cleaned = cleaned.slice(first, last + 1);
    }
  }
  let envelope;
  try {
    envelope = JSON.parse(cleaned);
  } catch (e) {
    console.error("aiEdit parse error. Last 200:", cleaned.slice(-200));
    throw new HttpsError("internal", "AI returned malformed output. Try rephrasing.");
  }

  // Normalize
  if (!Array.isArray(envelope.ops)) envelope.ops = [];
  if (!Array.isArray(envelope.warnings)) envelope.warnings = [];
  if (typeof envelope.summary !== "string") envelope.summary = "";
  const isRefusal = envelope.refusal != null && envelope.refusal !== "";

  // ── Tracking + refusal counter ─────────────────────────────────
  const cost = calculateCost(usage, rates);

  const actId = await writeTracking({
    uid,
    data: {
      tool: "editorAI",
      type: isRefusal ? "aiEditRefusal" : "aiEdit",
      status: isRefusal ? "refused" : "success",
      model: MODEL_SONNET,
      documentId,
      documentTitle,
      templateId,
      sectionType: null,
      sectionTitle: null,
      rewriteOptions: null,
      spellcheckSummary: null,
      errorMessage: null,
      refusalReason: isRefusal ? envelope.refusal : null,
      durationMs: Date.now() - t0,
    },
    counterField: "editorAiCount",
    summaryField: "totalEditorAiCalls",
    monthlyField: "editorAiCalls",
    monthlyToolField: null,
    tokens: usage,
    cost,
  });

  // Increment refusal counter on the subscription doc (separate from main batch
  // because writeTracking already committed; this is a small follow-up update).
  if (isRefusal) {
    try {
      await subRef.update({
        editorAiRefusalCount: FieldValue.increment(1),
      });
    } catch (e) {
      console.error("Refusal counter update failed:", e.message);
    }
  }

  // ── Upload detail JSON ─────────────────────────────────────────
  uploadDetail(uid, actId, {
    tool: "editorAI",
    type: isRefusal ? "aiEditRefusal" : "aiEdit",
    instruction: instruction.trim(),
    snapshot,
    envelope,
  });

  if (isPro) {
      try {
        await subRef.update({
          editorAiHourlyCount: FieldValue.increment(1),
        });
      } catch (e) {
        console.error("Hourly counter update failed:", e.message);
      }
    }

  return { envelope };
});

// ════════════════════════════════════════════════════════════════════════
// EMAIL — verification + password reset via Resend
// ════════════════════════════════════════════════════════════════════════

function getVerificationTemplate(displayName, verifyLink) {
  const name = displayName || "there";
  const year = new Date().getFullYear();
  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0"/>
  <title>Verify your email – KitAura</title>
</head>
<body style="margin:0;padding:0;background-color:#F8F5F2;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;">
<div style="max-width:580px;margin:40px auto;background:#ffffff;border-radius:16px;overflow:hidden;box-shadow:0 4px 32px rgba(15,23,42,0.08);">
  <div style="background:linear-gradient(135deg,#831843 0%,#CF4D6F 60%,#CC7E85 100%);padding:48px 40px 40px;text-align:center;">
    <div style="font-family:Georgia,serif;font-size:26px;font-weight:600;color:#ffffff;letter-spacing:0.04em;margin-bottom:28px;">KitAura</div>
    <div style="width:64px;height:64px;background:rgba(255,255,255,0.15);border-radius:50%;margin:0 auto 20px;line-height:64px;">
      <span style="display:inline-block;vertical-align:middle;color:#ffffff;font-size:30px;">✉</span>
    </div>
    <h1 style="font-family:Georgia,serif;font-size:30px;font-weight:500;color:#ffffff;line-height:1.2;margin:0;">Confirm your email address</h1>
    <p style="font-size:14px;color:rgba(255,255,255,0.85);margin:8px 0 0;">One quick step to activate your KitAura account</p>
  </div>
  <div style="padding:44px 40px 36px;">
    <p style="font-family:Georgia,serif;font-size:22px;font-weight:500;color:#0F172A;margin:0 0 16px;">Hello, ${name} 👋</p>
    <p style="font-size:15px;color:#76818E;line-height:1.75;margin:0 0 32px;">
      Thank you for joining <strong style="color:#831843;">KitAura</strong>.
      To complete your registration and unlock your account, please verify
      your email address by clicking the button below.
    </p>
    <div style="text-align:center;margin-bottom:36px;">
      <a href="${verifyLink}" style="display:inline-block;background:#831843;color:#ffffff !important;text-decoration:none;font-size:15px;font-weight:500;letter-spacing:0.03em;padding:16px 48px;border-radius:50px;">Verify my email</a>
    </div>
    <div style="background:#FFF1F5;border-radius:10px;padding:18px 20px;margin-bottom:28px;">
      <p style="font-size:12.5px;color:#76818E;margin:0 0 8px;">Button not working? Copy and paste this link into your browser:</p>
      <a href="${verifyLink}" style="font-size:11.5px;color:#831843;word-break:break-all;text-decoration:none;font-weight:500;">${verifyLink}</a>
    </div>
    <div style="background:#FFF1F5;border-left:3px solid #CF4D6F;border-radius:0 8px 8px 0;padding:14px 16px;margin-bottom:28px;">
      <p style="font-size:13px;color:#76818E;line-height:1.6;margin:0;">
        <strong style="color:#0F172A;font-weight:500;">Didn't request this?</strong> You can safely ignore this email —
        your account won't be activated unless you click the button above.
        This link expires in <strong>24 hours</strong>.
      </p>
    </div>
    <hr style="border:none;border-top:1px solid #FFE4EC;margin:32px 0;"/>
    <p style="font-size:13px;color:#76818E;text-align:center;line-height:1.7;margin:0;">
      Need help? Reach us at
      <a href="mailto:${SUPPORT_EMAIL}" style="color:#831843;font-weight:500;text-decoration:none;">${SUPPORT_EMAIL}</a>
    </p>
  </div>
  <div style="background:#0F172A;padding:28px 40px;text-align:center;">
    <div style="font-family:Georgia,serif;font-size:18px;font-weight:500;color:#C5AFA4;letter-spacing:0.05em;margin-bottom:10px;">KitAura</div>
    <p style="font-size:12px;color:#76818E;line-height:1.8;margin:0;">© ${year} KitAura. All rights reserved.<br/>You're receiving this because you created an account with us.</p>
  </div>
</div>
</body>
</html>`;
}

function getPasswordResetTemplate(displayName, resetLink) {
  const name = displayName || "there";
  const year = new Date().getFullYear();
  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8"/>
  <meta name="viewport" content="width=device-width, initial-scale=1.0"/>
  <title>Reset your password – KitAura</title>
</head>
<body style="margin:0;padding:0;background-color:#F8F5F2;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;">
<div style="max-width:580px;margin:40px auto;background:#ffffff;border-radius:16px;overflow:hidden;box-shadow:0 4px 32px rgba(15,23,42,0.08);">
  <div style="background:linear-gradient(135deg,#0F172A 0%,#1e293b 100%);padding:48px 40px 40px;text-align:center;">
    <div style="font-family:Georgia,serif;font-size:26px;font-weight:600;color:#ffffff;letter-spacing:0.04em;margin-bottom:28px;">KitAura</div>
    <div style="width:64px;height:64px;background:rgba(131,24,67,0.2);border-radius:50%;margin:0 auto 20px;line-height:64px;">
      <span style="display:inline-block;vertical-align:middle;color:#CC7E85;font-size:28px;">🔒</span>
    </div>
    <h1 style="font-family:Georgia,serif;font-size:28px;font-weight:500;color:#ffffff;margin:0;">Reset your password</h1>
    <p style="font-size:14px;color:rgba(255,255,255,0.7);margin:8px 0 0;">We received a request to reset your KitAura password</p>
  </div>
  <div style="padding:44px 40px 36px;">
    <p style="font-family:Georgia,serif;font-size:22px;font-weight:500;color:#0F172A;margin:0 0 16px;">Hello, ${name} 👋</p>
    <p style="font-size:15px;color:#76818E;line-height:1.75;margin:0 0 32px;">
      We received a request to reset the password for your <strong style="color:#831843;">KitAura</strong> account.
      Click the button below to choose a new password. This link is valid for <strong>1 hour</strong>.
    </p>
    <div style="text-align:center;margin-bottom:36px;">
      <a href="${resetLink}" style="display:inline-block;background:#831843;color:#ffffff !important;text-decoration:none;font-size:15px;font-weight:500;letter-spacing:0.03em;padding:16px 48px;border-radius:50px;">Reset my password</a>
    </div>
    <div style="background:#FFF1F5;border-radius:10px;padding:18px 20px;margin-bottom:28px;">
      <p style="font-size:12.5px;color:#76818E;margin:0 0 8px;">Button not working? Copy and paste this link into your browser:</p>
      <a href="${resetLink}" style="font-size:11.5px;color:#831843;word-break:break-all;text-decoration:none;font-weight:500;">${resetLink}</a>
    </div>
    <div style="background:#FFF1F5;border-left:3px solid #CF4D6F;border-radius:0 8px 8px 0;padding:14px 16px;margin-bottom:28px;">
      <p style="font-size:13px;color:#76818E;line-height:1.6;margin:0;">
        <strong style="color:#0F172A;font-weight:500;">Didn't request this?</strong> Ignore this email — your password won't change.
        If you're concerned, contact us at <a href="mailto:${SUPPORT_EMAIL}" style="color:#831843;text-decoration:none;">${SUPPORT_EMAIL}</a>.
      </p>
    </div>
    <hr style="border:none;border-top:1px solid #FFE4EC;margin:32px 0;"/>
    <p style="font-size:13px;color:#76818E;text-align:center;line-height:1.7;margin:0;">
      Need help? <a href="mailto:${SUPPORT_EMAIL}" style="color:#831843;font-weight:500;text-decoration:none;">${SUPPORT_EMAIL}</a>
    </p>
  </div>
  <div style="background:#0F172A;padding:28px 40px;text-align:center;">
    <div style="font-family:Georgia,serif;font-size:18px;font-weight:500;color:#C5AFA4;letter-spacing:0.05em;margin-bottom:10px;">KitAura</div>
    <p style="font-size:12px;color:#76818E;line-height:1.8;margin:0;">© ${year} KitAura. All rights reserved.</p>
  </div>
</div>
</body>
</html>`;
}

async function sendEmail({ to, subject, html, apiKey }) {
  const resend = new Resend(apiKey);
  const result = await resend.emails.send({
    from: FROM_EMAIL,
    to,
    subject,
    html,
  });
  if (result.error) {
    throw new Error(`Resend send failed: ${JSON.stringify(result.error)}`);
  }
  return result.data;
}

// Action code settings — emails route back to your app so the user lands on
// a clean Firebase-handled page.
const actionCodeSettings = {
  url: `${APP_URL}/auth`,
  handleCodeInApp: false,
};

// ─── Callable: send verification email ─────────────────────────────────
// Called by the frontend right after sign-up (and from the "Resend email"
// button on the verify-email screen). Uses the currently-authenticated
// user so it can't be abused to spam arbitrary addresses.
exports.sendVerificationEmail = onCall(
  { secrets: [RESEND_API_KEY], region: "us-central1", timeoutSeconds: 30 },
  async (req) => {
    if (!req.auth) throw new HttpsError("unauthenticated", "Sign in required.");
    const uid = req.auth.uid;

    try {
      const user = await admin.auth().getUser(uid);
      if (user.emailVerified) {
        return { success: true, alreadyVerified: true };
      }
      if (!user.email) {
        throw new HttpsError("failed-precondition", "No email on account.");
      }

      const verifyLink = await admin.auth().generateEmailVerificationLink(
        user.email,
        actionCodeSettings,
      );
      const html = getVerificationTemplate(user.displayName, verifyLink);
      await sendEmail({
        to: user.email,
        subject: "Verify your email – KitAura",
        html,
        apiKey: RESEND_API_KEY.value(),
      });

      console.log(`Verification email sent to ${user.email}`);
      return { success: true };
    } catch (err) {
      console.error("sendVerificationEmail failed:", err.message);
      if (err.code === "auth/user-not-found") {
        throw new HttpsError("not-found", "User not found.");
      }
      throw new HttpsError("internal", "Could not send verification email.");
    }
  },
);

// ─── Callable: send password reset email ───────────────────────────────
// Public — does NOT require auth (user is locked out by definition).
// Always returns success to prevent email enumeration attacks.
exports.sendPasswordResetEmail = onCall(
  { secrets: [RESEND_API_KEY], region: "us-central1", timeoutSeconds: 30 },
  async (req) => {
    const email = (req.data && req.data.email || "").trim().toLowerCase();
    if (!email) {
      throw new HttpsError("invalid-argument", "Email is required.");
    }

    try {
      const user = await admin.auth().getUserByEmail(email);
      const resetLink = await admin.auth().generatePasswordResetLink(
        email,
        actionCodeSettings,
      );
      const html = getPasswordResetTemplate(user.displayName, resetLink);
      await sendEmail({
        to: email,
        subject: "Reset your password – KitAura",
        html,
        apiKey: RESEND_API_KEY.value(),
      });
      console.log(`Password reset email sent to ${email}`);
    } catch (err) {
      // Log but don't expose — security best practice.
      console.error("sendPasswordResetEmail (silent):", err.message);
    }

    return { success: true };
  },
);

// ─── ADMIN ENDPOINTS ─────────────────────────────────────────────────────
exports.setAdminClaim = require('./admin').setAdminClaim;

exports.adminGetDashboardKpis = require('./admin_dashboard').adminGetDashboardKpis;

exports.adminListUsers = require('./admin_users').adminListUsers;
exports.adminGetUserOverview = require('./admin_users').adminGetUserOverview;

exports.adminSetPlan = require('./admin_actions').adminSetPlan;
exports.adminResetCounters = require('./admin_actions').adminResetCounters;
exports.adminResetHourlyBurst = require('./admin_actions').adminResetHourlyBurst;
exports.adminResetRefusalCount = require('./admin_actions').adminResetRefusalCount;
exports.adminExtendTrial = require('./admin_actions').adminExtendTrial;

exports.adminUpdateConfig = require('./admin_config').adminUpdateConfig;

exports.adminUpdateAnnouncement = require('./admin_announcement').adminUpdateAnnouncement;

exports.adminListAiActivity = require('./admin_ai_activity').adminListAiActivity;

exports.adminGetCostOverview = require('./admin_cost_overview').adminGetCostOverview;
exports.adminGetCostByUser = require('./admin_cost_by_user').adminGetCostByUser;
exports.adminGetCostByFeature = require('./admin_cost_by_feature').adminGetCostByFeature;

exports.adminListUserDocuments = require('./admin_user_documents').adminListUserDocuments;

exports.adminGetAbuseMonitor = require('./admin_abuse_monitor').adminGetAbuseMonitor;

exports.adminListDocuments = require('./admin_documents').adminListDocuments;
exports.adminGetDocument = require('./admin_documents').adminGetDocument;

const { upgradeGuestToFree } = require("./upgrade_guest");
const { mergeGuestData } = require("./merge_guest");

exports.upgradeGuestToFree = upgradeGuestToFree;
exports.mergeGuestData = mergeGuestData;