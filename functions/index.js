/**
 * functions/index.js
 *
 * KitAura Claude proxy — keeps the Anthropic API key on the SERVER.
 * The Flutter web app calls THESE endpoints; the key never ships to the browser.
 *
 * Two callable endpoints:
 *   - aiFill     → generates polished CV section content as Quill Delta JSON
 *                  (model: Sonnet 4.6 — quality writing)
 *   - spellcheck → finds spelling errors in CV text
 *                  (model: Haiku 4.5 — cheap, fast)
 *
 * COST CONTROL:
 *   - Model routing: cheap Haiku for spellcheck, Sonnet for writing.
 *   - Prompt caching: the stable system prompt is marked with cache_control,
 *     so repeated calls in a session read it at 10% of input cost.
 *
 * SETUP:
 *   1. cd functions && npm install firebase-admin firebase-functions axios
 *   2. Set the secret (NOT in code, NOT in git):
 *        firebase functions:secrets:set ANTHROPIC_KEY
 *      (paste your sk-ant-... key when prompted)
 *   3. firebase deploy --only functions
 *
 * The Flutter app calls these as httpsCallable — auth is enforced automatically.
 */

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { defineSecret } = require("firebase-functions/params");
const axios = require("axios");

const ANTHROPIC_KEY = defineSecret("ANTHROPIC_KEY");

const ANTHROPIC_URL = "https://api.anthropic.com/v1/messages";
const API_VERSION = "2023-06-01";

// Model IDs (verified current as of 2026)
const MODEL_SONNET = "claude-sonnet-4-6";          // AI Fill — quality writing
const MODEL_HAIKU = "claude-haiku-4-5-20251001";   // Spellcheck — cheap & fast

// ─── Helper: call Anthropic ────────────────────────────────────────────────

async function callClaude({ model, system, userContent, maxTokens, apiKey }) {
  // `system` is an array of content blocks so we can attach cache_control
  // to the stable portion (90% cheaper on cache hits).
  const body = {
    model,
    max_tokens: maxTokens,
    system,
    messages: [{ role: "user", content: userContent }],
  };

  const res = await axios.post(ANTHROPIC_URL, body, {
    headers: {
      "content-type": "application/json",
      "x-api-key": apiKey,
      "anthropic-version": API_VERSION,
      // Enables prompt caching beta header (safe to always send)
      "anthropic-beta": "prompt-caching-2024-07-31",
    },
    timeout: 60000,
  });

  // Extract concatenated text from content blocks
  const blocks = res.data.content || [];
  return blocks
    .filter((b) => b.type === "text")
    .map((b) => b.text)
    .join("");
}

// ════════════════════════════════════════════════════════════════════════
// 1. AI FILL — returns Quill Delta JSON for a CV section
// ════════════════════════════════════════════════════════════════════════

exports.aiFill = onCall(
  { secrets: [ANTHROPIC_KEY], region: "us-central1" },
  async (request) => {
    // Auth enforced — request.auth is null if not signed in
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign in required.");
    }

    const {
      sectionType = "custom",
      tone = "professional",
      experienceLevel = "mid",
      profile = {},
    } = request.data || {};

    // ── System prompt — STABLE across calls → cached ──────────────────
    const systemBlocks = [
      {
        type: "text",
        text:
          "You are an expert CV writer. You transform a person's raw profile " +
          "data into polished, professional CV section content.\n\n" +
          "OUTPUT FORMAT — CRITICAL:\n" +
          "Return ONLY a valid JSON array of Quill Delta ops. No markdown, no " +
          "explanation, no code fences. Each op is an object:\n" +
          '  {"insert": "text\\n"}  for plain text\n' +
          '  {"insert": "text\\n", "attributes": {"bold": true, "size": "13"}}  for styled\n\n' +
          "FORMATTING RULES:\n" +
          "- The section HEADING (e.g. EXPERIENCE) must be bold, size 13, UPPERCASE.\n" +
          "- Job/role titles and degree names: bold, size 11.\n" +
          "- Body lines and bullets: size 11, no bold.\n" +
          "- Use real bullet character '• ' at the start of achievement lines.\n" +
          "- Every insert string MUST end with \\n.\n" +
          "- Keep it concise — CV space is limited. Max ~120 words of body.\n" +
          "- NEVER invent companies, dates, or numbers not in the provided data.\n" +
          "- If a field is missing, omit it gracefully — do not write placeholders.",
        // Cache this stable instruction block — 90% cheaper on repeat calls
        cache_control: { type: "ephemeral" },
      },
    ];

    // ── User content — the variable part (profile + section) ──────────
    const userContent =
      `Tone: ${tone}\nExperience level: ${experienceLevel}\n` +
      `Section to write: ${sectionType}\n\n` +
      `Profile data (JSON):\n${JSON.stringify(profile, null, 2)}\n\n` +
      `Write the "${sectionType}" section now. Return ONLY the Quill Delta JSON array.`;

    try {
      const raw = await callClaude({
        model: MODEL_SONNET,
        system: systemBlocks,
        userContent,
        maxTokens: 1024,
        apiKey: ANTHROPIC_KEY.value(),
      });

      // Strip any accidental code fences, parse JSON
      const cleaned = raw.replace(/```json/g, "").replace(/```/g, "").trim();
      let delta;
      try {
        delta = JSON.parse(cleaned);
      } catch (e) {
        throw new HttpsError(
          "internal",
          "AI returned malformed content. Please try again."
        );
      }

      if (!Array.isArray(delta)) {
        throw new HttpsError("internal", "Unexpected AI output shape.");
      }

      return { delta };
    } catch (err) {
      if (err instanceof HttpsError) throw err;
      console.error("aiFill error:", err?.response?.data || err.message);
      throw new HttpsError("internal", "AI generation failed. Try again.");
    }
  }
);

// ════════════════════════════════════════════════════════════════════════
// 2. SPELLCHECK — returns array of corrections (cheap Haiku model)
// ════════════════════════════════════════════════════════════════════════

exports.spellcheck = onCall(
  { secrets: [ANTHROPIC_KEY], region: "us-central1" },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign in required.");
    }

    const { sections = {} } = request.data || {};
    if (Object.keys(sections).length === 0) {
      return { corrections: [] };
    }

    const systemBlocks = [
      {
        type: "text",
        text:
          "You are a spelling checker for CVs. Find ONLY genuine spelling " +
          "mistakes — never grammar, style, or word choice. Skip proper " +
          "nouns, company names, and technical terms.\n\n" +
          "Return ONLY a JSON array. Each element:\n" +
          '  {"section": "<section title>", "wrong": "<misspelled word>", ' +
          '"correct": "<fix>", "offset": <int char position in that section>}\n' +
          "If there are no errors, return []. No markdown, no explanation.",
        cache_control: { type: "ephemeral" },
      },
    ];

    const sectionsText = Object.entries(sections)
      .map(([title, text]) => `--- ${title} ---\n${text}`)
      .join("\n\n");

    const userContent = `Check this CV for spelling errors:\n\n${sectionsText}`;

    try {
      const raw = await callClaude({
        model: MODEL_HAIKU, // cheap model for spellcheck
        system: systemBlocks,
        userContent,
        maxTokens: 1024,
        apiKey: ANTHROPIC_KEY.value(),
      });

      const cleaned = raw.replace(/```json/g, "").replace(/```/g, "").trim();
      let corrections;
      try {
        corrections = JSON.parse(cleaned);
      } catch (e) {
        corrections = [];
      }

      if (!Array.isArray(corrections)) corrections = [];
      return { corrections };
    } catch (err) {
      console.error("spellcheck error:", err?.response?.data || err.message);
      throw new HttpsError("internal", "Spellcheck failed. Try again.");
    }
  }
);