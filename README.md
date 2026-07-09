<div align="center">

# KitAura

**AI-powered CV, cover letter, and proposal builder — built in Flutter Web.**

[![Live](https://img.shields.io/badge/live-app--kitaura.winibex.com-831843)](https://app-kitaura.winibex.com)
[![Marketing](https://img.shields.io/badge/marketing-kitaura.winibex.com-CF4D6F)](https://kitaura.winibex.com)
[![Flutter](https://img.shields.io/badge/Flutter-3.41.9-0F172A)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3.11.5-0F172A)](https://dart.dev)

</div>

---

## What is KitAura?

KitAura is a free document-building SaaS that lets anyone create professional CVs, cover letters, and proposals — with AI Compose, AI Refine, AI Assistant (Command-K editing), and AI Proofread. It also includes a LinkedIn content generator that turns your career profile into optimized posts, headlines, and summaries.

- **Free-tier at launch** — Stripe deferred; admin can manually grant Pro
- **Guest mode** — anonymous users can browse, build, and export a CV before signing up (Firebase Anonymous Auth)
- **AI-powered** — Claude Sonnet 4.6 for content, Claude Haiku 4.5 for proofreading
- **Live in production** at [app-kitaura.winibex.com](https://app-kitaura.winibex.com)

## Features

**Editors**
- Free-canvas WYSIWYG editor for CV, cover letter, and proposal
- 24 templates across the three document types (11 CV, 5 CL, 8 Proposal)
- Multi-page A4 canvas with auto-arrange, snap guides, marquee select
- Rich text via `flutter_quill`, custom fonts, per-op PDF rendering
- Undo/redo, keyboard shortcuts (Ctrl+J / ⌘J for AI Assistant)

**AI**
- **AI Compose** — generates section content from your Career Profile
- **AI Refine** — 4 preset rewrite modes + custom instructions
- **AI Assistant** — Command-K bar for natural-language canvas edits (11 op types)
- **AI Proofread** — free spellcheck via Haiku
- **AI Client Builder** — one-shot brief extraction + multi-turn interview for proposals

**Guest mode**
- Lazy anonymous sign-in on first action
- 3 docs / 15 AI Compose / 7 AI Assistant / 3 exports before signup
- `linkWithCredential` upgrade preserves guest work (same UID)
- Merge picker for the credential-already-in-use case

**Everything else**
- Firebase App Check (reCAPTCHA Enterprise) on all AI endpoints
- Server-side counter tracking (frontend can't touch subscription writes)
- Live feature-flag gating from `config/featureFlags` (kill-switch every AI feature independently)
- Announcement banner reading `config/announcement`
- Skeleton loading, offline detection, safe-default policies throughout

## Tech Stack

| Layer | Choice |
|---|---|
| Frontend | Flutter Web 3.41.9 / Dart 3.11.5 |
| Rich text | `flutter_quill` 11.5.0 |
| PDF | `pdf` + `printing` (direct `pw.Font.ttf` loading) |
| State | Riverpod 2.x (StateNotifier + ChangeNotifier + StreamProvider) |
| Navigation | `go_router` with auth guard |
| Auth | Firebase Auth (Google + Email/Password + Anonymous) |
| Database | Firebase Firestore (Schema v6) |
| Storage | Firebase Storage |
| AI | Claude Sonnet 4.6 & Haiku 4.5 via Firebase Cloud Functions proxy |
| App Check | reCAPTCHA Enterprise |
| Email | Resend (branded verification + password reset) |
| Hosting | Hostinger Business Plan + GitHub Actions CI/CD |

Custom fonts: Arial, OpenSans, Poppins, Sekuya (in `assets/fonts/`).

## Project Structure

```
lib/
├── app.dart, main.dart, firebase_options.dart
├── core/
│   ├── constants/    # colors, fonts, routes, sizes, AI labels
│   ├── theme/
│   └── utils/        # responsive, validators
├── features/
│   ├── auth/         # login, signup, password reset
│   ├── dashboard/    # main dashboard
│   ├── ai_setup/     # Career Profile wizard
│   ├── cv/           # dashboard + templates + editor
│   ├── cover_letter/ # dashboard + templates + editor
│   ├── proposal/     # dashboard + templates + editor
│   ├── linkedin/     # LinkedIn content generator
│   └── settings/     # profile, plan, preferences, profiles
└── shared/
    ├── ai/           # Claude controller + service, spellcheck
    ├── canvas/       # engine (canvas_controller, reflow, PDF) + editor UI
    ├── models/       # subscription, ai_profile, canvas_item, etc.
    ├── providers/    # ai_profiles, feature_flags
    ├── services/     # firebase_service, paywall_service, connectivity
    └── widgets/      # sidebar, top bar, banners, modals

functions/
├── index.js          # aiFill, aiRewrite, aiEdit, spellcheck, tracking
├── upgrade_guest.js
└── merge_guest.js
```

## Firebase Schema (v6)

Full schema in project docs. Highlights:

```
users/{uid}
users/{uid}/data/subscription       # plan, counters, cycle
users/{uid}/data/preferences
users/{uid}/aiProfiles/{profileId}  # Career Profiles (multi + default flag)
users/{uid}/clientProfiles/{id}     # Proposals client data
users/{uid}/cvs/{cvId}              # CV documents
users/{uid}/coverLetters/{clId}
users/{uid}/proposals/{propId}
users/{uid}/linkedinSummaries/{id}
users/{uid}/aiActivity/{id}         # per-call log (tokens, cost, status)
users/{uid}/analytics/{YYYY-MM}     # monthly aggregates
users/{uid}/analytics/summary       # lifetime aggregates
users/{uid}/transactions/{txId}

config/limits                       # plan limits (admin-editable)
config/pricing                      # Anthropic rates
config/proTemplates                 # Pro template IDs
config/featureFlags                 # 8 kill-switches
config/announcement                 # active system banner
```

**Security:** Cloud Functions own all counter, aiActivity, and analytics writes. Frontend can only write user-owned content (profile, aiProfiles, docs, preferences).

## Cloud Functions

| Endpoint | Model | Purpose |
|---|---|---|
| `aiFill` | Sonnet 4.6 | AI Compose (CV/CL/proposal/LinkedIn + client extract/chat) |
| `aiRewrite` | Sonnet 4.6 | AI Refine |
| `aiEdit` | Sonnet 4.6 | AI Assistant (Command-K canvas edits) |
| `spellcheck` | Haiku 4.5 | AI Proofread |
| `trackExport` | — | Export paywall + counter + Pro template check |
| `trackLogin` / `trackDocCreated` / `trackDocDeleted` | — | Server-side counters |
| `activateTrial` | — | 7-day trial activation |
| `upgradeGuestToFree` | — | Guest → real account conversion |
| `mergeGuestData` | — | Merge guest docs into existing account |

All AI endpoints enforce Firebase App Check (reCAPTCHA Enterprise).

## Plan Limits

| Feature | Guest | Free | Trial (7d) | Pro ($8/mo)* |
|---|---|---|---|---|
| Docs (CV+CL+Proposal combined) | 3 | 5 | Unlimited | 30 |
| AI Compose + Refine (combined) | 15/mo | 30/mo | Unlimited | 100/mo |
| AI Assistant | 7/mo | 15/mo | Unlimited | 100/mo + 20/hr |
| Exports | 3/mo | 10/mo | Unlimited | Unlimited |
| AI Proofread | Free | Free | Free | Free |

\* Pro tier exists in schema and Cloud Functions but Stripe is deferred at launch. Admin can manually grant Pro via the admin panel.

## Running Locally

```bash
# 1. Clone
git clone https://github.com/Winibex/KitAura.git
cd KitAura

# 2. Install
flutter pub get

# 3. Firebase config
# Place your firebase_options.dart at lib/firebase_options.dart
# (run `flutterfire configure` if setting up a new Firebase project)

# 4. Run
flutter run -d chrome
```

**Cloud Functions:**

```bash
cd functions
npm install
firebase deploy --only functions:aiFill  # deploy single function
```

Secrets required in Google Secret Manager:
- `ANTHROPIC_KEY`
- `RESEND_API_KEY`

## Deployment

Push to `main` triggers GitHub Actions:
1. Setup Flutter 3.41.9 → `flutter pub get`
2. `flutter build web --release --base-href "/" --tree-shake-icons --source-maps`
3. Push `build/web/` to `hostinger-deploy` branch
4. Hostinger auto-pulls from `hostinger-deploy`

Requires `.htaccess` on the Hostinger side redirecting all routes to `index.html` for client-side routing.

## Architecture Principles

- **Strict MVC.** Views never import `cloud_firestore`. All data access via controllers/services.
- **Riverpod discipline.** `ref.read` in event handlers, `ref.watch` only in `build()`.
- **Server-side counter tracking.** Frontend cannot manipulate subscription doc.
- **Doc counts from collection queries**, not `subscription.cvCount`. Frontend never trusts server counters for reads.
- **Feature flags default TRUE** on error or missing. Safe defaults everywhere.
- **Continuation items** cleared *before* reflow, never saved to Firestore.
- **Quill newlines** always plain — never `{'insert': 'text\n', 'attributes': {...}}`.
- **AnimationControllers only tick when visible.** Overlays and top bars gate on visibility state.

## Brand

**Primary palette**
- Warm Grey `#F8F5F2` — page backgrounds
- Lavender Blush `#FFF1F5` — editor bg, input fills
- Petal Frost `#FFE4EC` — cards, borders
- Prussian Blue `#0F172A` — text, dark bg, headers
- Dark Raspberry `#831843` — primary CTAs

**Secondary**
- Almond Silk `#C5AFA4` — borders, muted text
- Dusty Rose `#CC7E85` — hover states
- Magenta Bloom `#CF4D6F` — badges, emphasis
- Dusty Mauve `#A36D90` — secondary buttons
- Slate Grey `#76818E` — subtitles, placeholders

**Fonts**
- Poppins — UI headings, buttons, labels
- OpenSans — body text
- Arial — default CV text
- Sekuya — display/decorative

## Related Projects

- **[kitaura_admin](https://github.com/Winibex/kitaura_admin)** — separate Flutter Web admin panel sharing this Firebase backend
- **kitaura.winibex.com** — WordPress marketing site (separate repo)

## License

Proprietary. All rights reserved © 2026 Winibex.

## Contact

Built by [@Winibex](https://github.com/Winibex).