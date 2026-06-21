// lib/core/constants/app_ai_labels.dart
//
// Centralized labels and tooltips for every AI-powered feature in KitAura.
//
// Why centralized:
//   - Feature names appear in dozens of UI locations (buttons, dropdowns,
//     tooltips, paywall messages, settings, analytics). Renaming "AI Compose"
//     to "AI Compose" should be a one-line change, not a 30-file search.
//   - Tooltips need to be consistent. If "AI Compose" is described slightly
//     differently in three places, users get confused.
//
// Usage:
//   Text(AiLabels.aiCompose)
//   AiLabelTooltip(label: AiLabels.careerProfile, tip: AiTooltips.careerProfile)

import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import 'app_colors.dart';
import 'app_fonts.dart';

/// Premium-sounding labels for every AI feature.
/// Update the right-hand string to rename a feature app-wide.
class AiLabels {
  AiLabels._();

  // ─── Core concepts ──────────────────────────────────────────────
  /// The user's saved professional background (work, skills, education).
  /// Replaces "Career Profile" everywhere.
  static const careerProfile = 'Career Profile';
  static const careerProfiles = 'Career Profiles';
  static const yourCareerProfile = 'Your Career Profile';

  // ─── AI features ────────────────────────────────────────────────
  /// Generate new content for a section from the Career Profile.
  /// Replaces "AI Compose".
  static const aiCompose = 'AI Compose';

  /// Rewrite existing content in a different tone or style.
  /// Replaces "AI Refine".
  static const aiRefine = 'AI Refine';

  /// The command-K bar — natural-language editor commands.
  /// Replaces "AI Edit".
  static const aiAssistant = 'AI Assistant';

  /// One-button whole-document generation for proposals.
  static const aiComposeProposal = 'AI Compose Proposal';

  /// One-button whole-document generation for cover letters.
  static const aiComposeLetter = 'AI Compose Letter';

  /// Spellcheck — free for everyone.
  /// Replaces "AI Proofread".
  static const aiProofread = 'AI Proofread';

  // ─── AI Refine modes ────────────────────────────────────────────
  static const refineProfessional = 'Professional';
  static const refineConcise = 'Concise';
  static const refineDetailed = 'Detailed';
  static const refineCreative = 'Creative';

  /// "Custom" mode — user provides specific instructions.
  static const refineCustom = 'Custom Instructions';

  // ─── AI Compose modes ───────────────────────────────────────────
  /// Generates polished content using AI from the Career Profile.
  static const composeWithAi = 'Generate with AI';

  /// Copies Career Profile data into the section without an AI call.
  /// Costs no tokens, results are plainer but instant.
  static const composeRaw = 'Just Insert My Data';

  // ─── Misc ───────────────────────────────────────────────────────
  static const checkSpelling = 'Check Spelling';
  static const usageThisMonth = 'Usage this month';
  static const upgradeForMore = 'Upgrade for more';
}

/// Tooltips paired with the labels above.
class AiTooltips {
  AiTooltips._();

  static const careerProfile =
      'Your professional background — work, skills, education. Powers every AI feature in the app.';

  static const aiCompose =
      'Generate professionally written content for this section using your Career Profile.';

  static const aiRefine =
      'Transform your writing — rewrite this section to be more professional, concise, detailed, or creative.';

  static const aiAssistant =
      'Make any change in plain English — formatting, layout, content, or full redesigns. Press Ctrl+J anywhere.';

  static const aiComposeProposal =
      'Generate a complete, tailored proposal from your client brief and Career Profile.';

  static const aiComposeLetter =
      'Write a tailored cover letter from the job details and your Career Profile.';

  static const aiProofread =
      'Catch typos and spelling errors. Free and unlimited on every plan.';

  static const refineProfessional =
      'Polish for a formal, business tone with strong action verbs.';
  static const refineConcise =
      'Shorten and sharpen — remove filler, keep impact.';
  static const refineDetailed =
      'Expand with metrics, specifics, and quantified results.';
  static const refineCreative =
      'Rewrite with a bolder, more engaging voice while staying professional.';
  static const refineCustom =
      'Tell AI exactly how to rewrite this section. Cannot add new sections — only rewrites what\'s here.';

  static const composeWithAi =
      'AI uses your Career Profile to write polished, tailored content. Costs one AI call.';
  static const composeRaw =
      'Inserts your raw Career Profile data into the section. No AI, no tokens used — instant.';

  static const careerProfileSelector =
      'Choose which Career Profile to use. AI will tailor content based on the selected profile.';
}

/// A label + small info icon that shows a tooltip on hover (desktop) or
/// tap (mobile). Use this for AI feature labels in the right panel,
/// dropdowns, and settings.
///
/// Built on the same pattern as InfoLabel but tuned for the editor's
/// compact right-panel layout — smaller font, less vertical padding.
class AiLabelTooltip extends StatelessWidget {
  final String label;
  final String tip;
  final TextStyle? labelStyle;
  final bool showIcon;

  const AiLabelTooltip({
    super.key,
    required this.label,
    required this.tip,
    this.labelStyle,
    this.showIcon = true,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            label,
            style:
                labelStyle ??
                const TextStyle(
                  fontSize: 11,
                  fontFamily: AppFonts.poppins,
                  fontWeight: FontWeight.w600,
                  color: AppColors.prussianBlue,
                  letterSpacing: 0.2,
                ),
          ),
        ),
        if (showIcon) ...[
          const SizedBox(width: 4),
          Tooltip(
            message: tip,
            textStyle: const TextStyle(
              fontSize: 11.5,
              fontFamily: AppFonts.openSans,
              color: AppColors.white,
              height: 1.4,
            ),
            decoration: BoxDecoration(
              color: AppColors.prussianBlue,
              borderRadius: BorderRadius.circular(8),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            margin: const EdgeInsets.symmetric(horizontal: 16),
            preferBelow: true,
            waitDuration: const Duration(milliseconds: 200),
            child: const Icon(
              LucideIcons.info,
              size: 11,
              color: AppColors.slateGrey,
            ),
          ),
        ],
      ],
    );
  }
}

/// A premium-styled section header badge for the AI tools area of the
/// right panel. Use this above grouped AI controls instead of plain text
/// to give the AI features visual weight.
class AiSectionHeader extends StatelessWidget {
  final String label;
  final IconData icon;
  final String? tip;

  const AiSectionHeader({
    super.key,
    required this.label,
    required this.icon,
    this.tip,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: Row(
        children: [
          Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.darkRaspberry, AppColors.magentaBloom],
              ),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Icon(icon, size: 10, color: AppColors.white),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              fontFamily: AppFonts.poppins,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.0,
              color: AppColors.prussianBlue,
            ),
          ),
          if (tip != null) ...[
            const SizedBox(width: 6),
            Tooltip(
              message: tip!,
              child: const Icon(
                LucideIcons.info,
                size: 11,
                color: AppColors.slateGrey,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
