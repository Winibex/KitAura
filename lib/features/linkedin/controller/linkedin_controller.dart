// lib/features/linkedin/controller/linkedin_controller.dart
//
// FIXES from previous version:
//   1. copySection/copyAll format raw text properly (not JSON objects)
//   2. CV is optional — works with AI Profile alone
//   3. AI Profile is optional — works with just CV content
//   4. Loads default AI profile from FirebaseService.getDefaultAiProfile()

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/legacy.dart';
import '../../../shared/models/ai_profile_model.dart';
import '../../../shared/services/firebase_service.dart';
import '../../../shared/ai/claude_service.dart';

// ── Section keys ─────────────────────────────────────────────────────

class LinkedInSection {
  final String key;
  final String label;
  final IconData icon;

  const LinkedInSection(this.key, this.label, this.icon);
}

const kLinkedInSections = [
  LinkedInSection('headline', 'Headline', Icons.title),
  LinkedInSection('about', 'About', Icons.person_outline),
  LinkedInSection('experiences', 'Experience', Icons.work_outline),
  LinkedInSection('education', 'Education', Icons.school_outlined),
  LinkedInSection('skills', 'Skills', Icons.star_outline),
  LinkedInSection('projects', 'Projects', Icons.code),
  LinkedInSection('certifications', 'Certifications', Icons.verified_outlined),
  LinkedInSection('volunteer', 'Volunteer', Icons.volunteer_activism_outlined),
];

// ── State ────────────────────────────────────────────────────────────

class LinkedInState {
  final bool isLoading;
  final bool isGenerating;
  final String? regeneratingSection;
  final String? error;

  // Inputs
  final String? selectedCvId;
  final String? selectedCvTitle;
  final String customPrompt;
  final Set<String> selectedSections;

  // Profile info (for display)
  final bool hasAiProfile;
  final String? profileName;
  final String? selectedProfileId;

  // Results
  final Map<String, dynamic>? generatedContent;
  final String? activeDocId;

  // Saved generations
  final List<SavedLinkedIn> savedItems;
  final bool savedLoaded;

  const LinkedInState({
    this.isLoading = false,
    this.isGenerating = false,
    this.regeneratingSection,
    this.error,
    this.selectedCvId,
    this.selectedCvTitle,
    this.customPrompt = '',
    this.selectedSections = const {
      'headline', 'about', 'experiences', 'education',
      'skills', 'projects', 'certifications', 'volunteer',
    },
    this.hasAiProfile = false,
    this.profileName,
    this.selectedProfileId,
    this.generatedContent,
    this.activeDocId,
    this.savedItems = const [],
    this.savedLoaded = false,
  });

  bool get hasResults => generatedContent != null;
  bool get allSelected => selectedSections.length == kLinkedInSections.length;
  bool get canGenerate => selectedSections.isNotEmpty && (selectedCvId != null || hasAiProfile || selectedProfileId != null);

  LinkedInState copyWith({
    bool? isLoading,
    bool? isGenerating,
    String? regeneratingSection,
    String? error,
    String? selectedCvId,
    String? selectedCvTitle,
    String? customPrompt,
    Set<String>? selectedSections,
    bool? hasAiProfile,
    String? profileName,
    String? selectedProfileId,
    Map<String, dynamic>? generatedContent,
    String? activeDocId,
    List<SavedLinkedIn>? savedItems,
    bool? savedLoaded,
  }) {
    return LinkedInState(
      isLoading: isLoading ?? this.isLoading,
      isGenerating: isGenerating ?? this.isGenerating,
      regeneratingSection: regeneratingSection,
      error: error,
      selectedCvId: selectedCvId ?? this.selectedCvId,
      selectedCvTitle: selectedCvTitle ?? this.selectedCvTitle,
      customPrompt: customPrompt ?? this.customPrompt,
      selectedSections: selectedSections ?? this.selectedSections,
      hasAiProfile: hasAiProfile ?? this.hasAiProfile,
      profileName: profileName ?? this.profileName,
      selectedProfileId: selectedProfileId ?? this.selectedProfileId,
      generatedContent: generatedContent ?? this.generatedContent,
      activeDocId: activeDocId ?? this.activeDocId,
      savedItems: savedItems ?? this.savedItems,
      savedLoaded: savedLoaded ?? this.savedLoaded,
    );
  }
}

class SavedLinkedIn {
  final String id;
  final String title;
  final String? linkedCvTitle;
  final DateTime createdAt;

  const SavedLinkedIn({
    required this.id,
    required this.title,
    required this.linkedCvTitle,
    required this.createdAt,
  });

  String get timeAgo {
    final diff = DateTime.now().difference(createdAt);
    if (diff.inDays > 7) return '${(diff.inDays / 7).floor()}w ago';
    if (diff.inDays > 0) return '${diff.inDays}d ago';
    if (diff.inHours > 0) return '${diff.inHours}h ago';
    if (diff.inMinutes > 0) return '${diff.inMinutes}m ago';
    return 'Just now';
  }
}

// ── Controller ───────────────────────────────────────────────────────

class LinkedInController extends StateNotifier<LinkedInState> {
  LinkedInController() : super(const LinkedInState());

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  // ── Check if AI profile exists ─────────────────────────────────────

  Future<void> checkAiProfile() async {
    if (_uid == null) return;
    try {
      final profile = await FirebaseService.getDefaultAiProfile(_uid!);
      if (profile != null) {
        state = state.copyWith(
          hasAiProfile: true,
          profileName: profile.name.isNotEmpty ? profile.name : profile.fullName,
        );
      }
    } catch (_) {}
  }

  // ── Section selection ──────────────────────────────────────────────

  void toggleSection(String key) {
    final current = Set<String>.from(state.selectedSections);
    if (current.contains(key)) {
      current.remove(key);
    } else {
      current.add(key);
    }
    state = state.copyWith(selectedSections: current);
  }

  void toggleAll() {
    if (state.allSelected) {
      state = state.copyWith(selectedSections: {});
    } else {
      state = state.copyWith(
        selectedSections: kLinkedInSections.map((s) => s.key).toSet(),
      );
    }
  }

  void selectCv(String? id, String? title) {
    state = state.copyWith(selectedCvId: id ?? '', selectedCvTitle: title ?? '');
  }

  void clearCv() {
    state = LinkedInState(
      isLoading: state.isLoading,
      isGenerating: state.isGenerating,
      error: state.error,
      selectedCvId: null,
      selectedCvTitle: null,
      customPrompt: state.customPrompt,
      selectedSections: state.selectedSections,
      hasAiProfile: state.hasAiProfile,
      profileName: state.profileName,
      generatedContent: state.generatedContent,
      activeDocId: state.activeDocId,
      savedItems: state.savedItems,
      savedLoaded: state.savedLoaded,
    );
  }

  void selectProfile(String id, String name) {
    state = state.copyWith(
      selectedProfileId: id,
      hasAiProfile: true,
      profileName: name,
    );
  }

  void setPrompt(String prompt) {
    state = state.copyWith(customPrompt: prompt);
  }

  // ── Generate ───────────────────────────────────────────────────────

  Future<void> generate() async {
    if (_uid == null) return;
    if (state.selectedSections.isEmpty) {
      state = state.copyWith(error: 'Select at least one section');
      return;
    }

    // Need at least CV or AI Profile
    if (state.selectedCvId == null && !state.hasAiProfile) {
      state = state.copyWith(
        error: 'Select a CV or set up an AI Profile in Settings first',
      );
      return;
    }

    state = state.copyWith(isGenerating: true, error: null);

    try {
      // Load CV content (optional)
      String? cvContent;
      if (state.selectedCvId != null && state.selectedCvId!.isNotEmpty) {
        cvContent = await _loadCvContent(state.selectedCvId!);
      }

      // Load AI profile (optional)
      AiProfileModel? profile;
      try {
        if (state.selectedProfileId != null) {
          final doc = await FirebaseService.getAiProfileById(_uid!, state.selectedProfileId!);
          if (doc.exists) {
            final data = doc.data() as Map<String, dynamic>;
            data['id'] = doc.id;
            profile = AiProfileModel.fromJson(data);
          }
        }
        // Fallback to default
        profile ??= await FirebaseService.getDefaultAiProfile(_uid!);
      } catch (_) {}

      // Sanitize profile — strip Timestamps
      final profileJson = profile?.toJson() ?? {};
      profileJson.remove('updatedAt');
      profileJson.remove('createdAt');

      // Need at least some data
      if ((cvContent == null || cvContent.isEmpty) && profile == null) {
        state = state.copyWith(
          isGenerating: false,
          error: 'No data found. Please create a CV or set up an AI Profile.',
        );
        return;
      }

      final result = await ClaudeService.aiFillSection(
        sectionType: 'all',
        tone: profile?.tone ?? 'professional',
        experienceLevel: profile?.experienceLevel ?? 'mid',
        profile: profileJson,
        tool: 'linkedin',
        jobDetails: {
          'selectedSections': List<String>.from(state.selectedSections),
          'customPrompt': state.customPrompt,
        },
        cvContent: cvContent ?? '',
      );

      if (result == null) {
        state = state.copyWith(isGenerating: false, error: 'AI returned no content');
        return;
      }

      final docId = await _saveToFirestore(result);

      state = state.copyWith(
        isGenerating: false,
        generatedContent: result,
        activeDocId: docId,
      );

      await loadSaved();
    } catch (e) {
      state = state.copyWith(
        isGenerating: false,
        error: e.toString().contains('limit')
            ? 'AI generation limit reached. Upgrade to Pro for unlimited access.'
            : 'Generation failed. Please try again.',
      );
    }
  }

  // ── Regenerate single section ──────────────────────────────────────

  Future<void> regenerateSection(String sectionKey) async {
    if (_uid == null) return;

    state = state.copyWith(isGenerating: true, regeneratingSection: sectionKey, error: null);

    try {
      String? cvContent;
      if (state.selectedCvId != null && state.selectedCvId!.isNotEmpty) {
        cvContent = await _loadCvContent(state.selectedCvId!);
      }

      AiProfileModel? profile;
      try {
        if (state.selectedProfileId != null) {
          final doc = await FirebaseService.getAiProfileById(_uid!, state.selectedProfileId!);
          if (doc.exists) {
            final data = doc.data() as Map<String, dynamic>;
            data['id'] = doc.id;
            profile = AiProfileModel.fromJson(data);
          }
        }
        profile ??= await FirebaseService.getDefaultAiProfile(_uid!);
      } catch (_) {}

      final profileJson = profile?.toJson() ?? {};
      profileJson.remove('updatedAt');
      profileJson.remove('createdAt');

      final result = await ClaudeService.aiFillSection(
        sectionType: sectionKey,
        tone: profile?.tone ?? 'professional',
        experienceLevel: profile?.experienceLevel ?? 'mid',
        profile: profileJson,
        tool: 'linkedin',
        cvContent: cvContent ?? '',
        jobDetails: {
          'selectedSections': [sectionKey],
          'customPrompt': state.customPrompt,
        },
      );

      if (result != null && state.generatedContent != null) {
        final updated = Map<String, dynamic>.from(state.generatedContent!);
        updated[sectionKey] = result;

        if (state.activeDocId != null) {
          await FirebaseService.updateLinkedInSummary(
            _uid!, state.activeDocId!,
            {'generatedContent': updated, 'updatedAt': FieldValue.serverTimestamp()},
          );
        }

        state = state.copyWith(isGenerating: false, regeneratingSection: null, generatedContent: updated);
      } else {
        state = state.copyWith(isGenerating: false, regeneratingSection: null);
      }
    } catch (e) {
      state = state.copyWith(isGenerating: false, regeneratingSection: null, error: 'Regeneration failed');
    }
  }

  // ── Load saved generations ─────────────────────────────────────────

  Future<void> loadSaved() async {
    if (_uid == null) return;

    try {
      final snap = await FirebaseService.getLinkedInSummaries(_uid!);
      final items = snap.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return SavedLinkedIn(
          id: doc.id,
          title: data['title'] ?? 'LinkedIn Content',
          linkedCvTitle: data['linkedCvTitle'],
          createdAt: (data['createdAt'] as dynamic)?.toDate() ?? DateTime.now(),
        );
      }).toList();

      state = state.copyWith(savedItems: items, savedLoaded: true);
    } catch (e) {
      debugPrint('LinkedIn load saved error: $e');
    }
  }

  Future<void> loadSavedGeneration(String docId) async {
    if (_uid == null) return;
    state = state.copyWith(isLoading: true);

    try {
      final doc = await FirebaseService.getLinkedInSummary(_uid!, docId);
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        state = state.copyWith(
          isLoading: false,
          selectedCvId: data['linkedCvId'],
          selectedCvTitle: data['linkedCvTitle'],
          customPrompt: data['customPrompt'] ?? '',
          generatedContent: data['generatedContent'] != null
              ? Map<String, dynamic>.from(data['generatedContent'])
              : null,
          activeDocId: docId,
        );
      }
    } catch (e) {
      state = state.copyWith(isLoading: false, error: 'Failed to load');
    }
  }

  Future<void> deleteSaved(String docId) async {
    if (_uid == null) return;
    await FirebaseService.deleteLinkedInSummary(_uid!, docId);

    if (state.activeDocId == docId) {
      state = LinkedInState(
        savedItems: state.savedItems,
        savedLoaded: true,
        hasAiProfile: state.hasAiProfile,
        profileName: state.profileName,
      );
    }
    await loadSaved();
  }

  void clearResults() {
    state = LinkedInState(
      savedItems: state.savedItems,
      savedLoaded: true,
      hasAiProfile: state.hasAiProfile,
      profileName: state.profileName,
    );
  }

  // ── Copy to clipboard — PLAIN TEXT formatting ──────────────────────

  Future<void> copySection(String sectionKey) async {
    final content = state.generatedContent?[sectionKey];
    if (content == null) return;

    final text = formatSectionText(sectionKey, content);
    await Clipboard.setData(ClipboardData(text: text));
  }

  Future<void> copyAll() async {
    if (state.generatedContent == null) return;
    final buffer = StringBuffer();

    for (final section in kLinkedInSections) {
      final content = state.generatedContent![section.key];
      if (content == null) continue;

      buffer.writeln('═══ ${section.label.toUpperCase()} ═══');
      buffer.writeln(formatSectionText(section.key, content));
      buffer.writeln();
    }

    await Clipboard.setData(ClipboardData(text: buffer.toString().trim()));
  }

  /// Converts any section content into clean, pasteable plain text.
  String formatSectionText(String key, dynamic data) {
    if (data is String) return data;

    if (data is List) {
      final buffer = StringBuffer();
      for (final item in data) {
        if (item is String) {
          buffer.writeln(item);
        } else if (item is Map) {
          // Experience: { role, description }
          // Education: { degree, description }
          // Projects: { name, description }
          // Certifications: { name, description }
          // Volunteer: { role, description }
          final title = item['role'] ?? item['name'] ?? item['degree'] ?? '';
          final desc = item['description'] ?? '';
          if (title.isNotEmpty) buffer.writeln(title);
          if (desc.isNotEmpty) buffer.writeln(desc);
          buffer.writeln();
        }
      }
      return buffer.toString().trim();
    }

    if (data is Map) {
      // Standard aiFill format: { heading, entries: [{ title, lines }] }
      if (data['entries'] != null && data['entries'] is List) {
        final buffer = StringBuffer();
        for (final entry in data['entries']) {
          if (entry is Map) {
            final title = entry['title'] ?? '';
            if (title.isNotEmpty) buffer.writeln(title);
            final lines = entry['lines'];
            if (lines is List) {
              for (final line in lines) {
                buffer.writeln(line);
              }
            }
            buffer.writeln();
          }
        }
        return buffer.toString().trim();
      }

      // Fallback: just join values
      return data.values
          .where((v) => v != null && v.toString().isNotEmpty)
          .join('\n');
    }

    return data.toString();
  }

  // ── Helpers ────────────────────────────────────────────────────────

  Future<String?> _loadCvContent(String cvId) async {
    if (_uid == null) return null;
    try {
      final doc = await FirebaseService.getCV(_uid!, cvId);
      if (!doc.exists) return null;
      final data = doc.data() as Map<String, dynamic>;
      final items = data['items'] as List<dynamic>? ?? [];

      final buffer = StringBuffer();
      for (final item in items) {
        if (item is! Map) continue;
        if (item['type'] != 'textSection') continue;
        final delta = item['delta'] as List<dynamic>?;
        if (delta == null) continue;
        final title = item['title'] ?? '';
        if (title.isNotEmpty) buffer.writeln('--- $title ---');
        for (final op in delta) {
          if (op is Map && op['insert'] is String) {
            buffer.write(op['insert']);
          }
        }
        buffer.writeln();
      }
      return buffer.toString().trim();
    } catch (e) {
      return null;
    }
  }

  Future<String> _saveToFirestore(Map<String, dynamic> content) async {
    final data = {
      'title': 'LinkedIn Content — ${state.selectedCvTitle ?? "AI Profile"}',
      'linkedCvId': state.selectedCvId,
      'linkedCvTitle': state.selectedCvTitle,
      'customPrompt': state.customPrompt,
      'selectedSections': List<String>.from(state.selectedSections),
      'generatedContent': content,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (state.activeDocId != null) {
      await FirebaseService.updateLinkedInSummary(
          _uid!, state.activeDocId!, data);
      return state.activeDocId!;
    } else {
      final ref = await FirebaseService.createLinkedInSummary(_uid!, data);
      return ref.id;
    }
  }
}

final linkedInControllerProvider =
StateNotifierProvider<LinkedInController, LinkedInState>(
      (ref) => LinkedInController(),
);