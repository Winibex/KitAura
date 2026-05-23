/**
 * functions/index.js
 *
 * KitAura Claude proxy — keeps Anthropic API key on the SERVER.
 *
 * Two callable endpoints:
 *   - aiFill     → returns PLAIN TEXT in structured JSON (no styling).
 *                  The Flutter client applies template styles to the text.
 *                  Model: Sonnet 4.6 (quality writing)
 *   - spellcheck → finds spelling errors
 *                  Model: Haiku 4.5 (cheap, fast)
 *
 * Prompt caching: stable system prompt marked cache_control → 90% off on repeats.
 */

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { defineSecret } = require("firebase-functions/params");
const axios = require("axios");

const ANTHROPIC_KEY = defineSecret("ANTHROPIC_KEY");

const ANTHROPIC_URL = "https://api.anthropic.com/v1/messages";
const API_VERSION = "2023-06-01";

const MODEL_SONNET = "claude-sonnet-4-6";
const MODEL_HAIKU = "claude-haiku-4-5-20251001";

// ─── Helper: call Anthropic ────────────────────────────────────────────

async function callClaude({ model, system, userContent, maxTokens, apiKey }) {
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
      "anthropic-beta": "prompt-caching-2024-07-31",
    },
    timeout: 60000,
  });

  const blocks = res.data.content || [];
  return blocks
    .filter((b) => b.type === "text")
    .map((b) => b.text)
    .join("");
}

// ════════════════════════════════════════════════════════════════════════
// 1. AI FILL — returns PLAIN STRUCTURED TEXT (no styling)
//    The Flutter client extracts styles from the template's existing
//    delta and applies them to this text. This way every template
//    keeps its own colors/fonts/sizes automatically.
// ════════════════════════════════════════════════════════════════════════

exports.aiFill = onCall(
  { secrets: [ANTHROPIC_KEY], region: "us-central1" },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign in required.");
    }

    const {
      sectionType = "custom",
      tone = "professional",
      experienceLevel = "mid",
      profile = {},
    } = request.data || {};

    // ── System prompt — STABLE → cached at 10% cost ───────────────────
    const systemBlocks = [
      {
        type: "text",
        text:
          "You are an expert CV writer. You transform raw profile data into " +
          "polished, professional CV section content.\n\n" +
          "OUTPUT FORMAT — CRITICAL:\n" +
          "Return ONLY a valid JSON object with this structure:\n" +
          "{\n" +
          '  "heading": "SECTION HEADING IN UPPERCASE",\n' +
          '  "entries": [\n' +
          "    {\n" +
          '      "title": "Role/degree title line (with company/school, dates)",\n' +
          '      "lines": ["Achievement or detail line 1", "Line 2", ...]\n' +
          "    }\n" +
          "  ]\n" +
          "}\n\n" +
          "RULES:\n" +
          "- Return ONLY the JSON object. No markdown, no code fences, no explanation.\n" +
          "- heading: the section name in UPPERCASE (e.g. EXPERIENCE, EDUCATION, SKILLS).\n" +
          "- entries: array of items. Each has a 'title' and optional 'lines'.\n" +
          "- For sections without sub-items (like summary, contact, skills), use a " +
          "single entry with title='' and lines containing the content.\n" +
          "- Start achievement lines with '• ' (bullet + space).\n" +
          "- NEVER invent companies, dates, degrees, or numbers not in the data.\n" +
          "- If a field is missing, omit it — don't write placeholders.\n" +
          "- Keep it concise — CV space is limited. Max ~120 words of body.\n" +
          "- Write in a " + tone + " tone for a " + experienceLevel + "-level professional.\n\n" +
          "SECTION-SPECIFIC FORMATS:\n" +
          "- summary/profile/about: heading='PROFESSIONAL SUMMARY', one entry, " +
          "title='', lines=['2-3 sentence summary paragraph'].\n" +
          "- experience: heading='EXPERIENCE', one entry per role, title='Role — " +
          "Company | Dates', lines=['• Achievement 1', '• Achievement 2', ...].\n" +
          "- education: heading='EDUCATION', one entry per degree, title='Degree — " +
          "School | Dates', lines=['Optional detail'].\n" +
          "- skills: heading='SKILLS', one entry, title='', lines=['Skill1 • Skill2 • Skill3'].\n" +
          "- certifications: heading='CERTIFICATIONS', one entry, title='', " +
          "lines=['Cert1', 'Cert2'].\n" +
          "- languages: heading='LANGUAGES', one entry per language, title='Language — Level', " +
          "lines=[].\n" +
          "- contact: heading='', one entry, title='', lines=['email | phone | location | linkedin'].\n" +
          "- name: heading='', one entry, title='Full Name', lines=[].\n" +
          "- jobTitle: heading='', one entry, title='Job Title Text', lines=[].",
        cache_control: { type: "ephemeral" },
      },
    ];

    // ── User content — variable part ──────────────────────────────────
    const userContent =
      `Section to write: ${sectionType}\n\n` +
      `Profile data (JSON):\n${JSON.stringify(profile, null, 2)}\n\n` +
      `Write the "${sectionType}" section now. Return ONLY the JSON object.`;

    try {
      const raw = await callClaude({
        model: MODEL_SONNET,
        system: systemBlocks,
        userContent,
        maxTokens: 1024,
        apiKey: ANTHROPIC_KEY.value(),
      });

      const cleaned = raw.replace(/```json/g, "").replace(/```/g, "").trim();
      let result;
      try {
        result = JSON.parse(cleaned);
      } catch (e) {
        console.error("aiFill parse error. Raw:", cleaned);
        throw new HttpsError(
          "internal",
          "AI returned malformed content. Please try again."
        );
      }

      // Validate shape
      if (typeof result !== "object" || !Array.isArray(result.entries)) {
        console.error("aiFill bad shape:", JSON.stringify(result));
        throw new HttpsError("internal", "Unexpected AI output shape.");
      }

      return { content: result };
    } catch (err) {
      if (err instanceof HttpsError) throw err;
      console.error("aiFill error:", err?.response?.data || err.message);
      throw new HttpsError("internal", "AI generation failed. Try again.");
    }
  }
);

// ════════════════════════════════════════════════════════════════════════
// 2. SPELLCHECK — cheap Haiku model
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
        model: MODEL_HAIKU,
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