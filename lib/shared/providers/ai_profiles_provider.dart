// lib/shared/providers/ai_profiles_provider.dart
//
// Cached AI profiles for the current user. Loads ONCE and caches —
// the wizard, LinkedIn generator, and proposal panel all read from here
// instead of each calling Firebase, keeping read counts (and the bill) low.
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/ai_profile_model.dart';
import '../services/firebase_service.dart';

/// Fetches all AI profiles for the signed-in user, once, and caches them.
/// Call `ref.invalidate(aiProfilesProvider)` after creating/editing/deleting
/// a profile to force a refresh.
final aiProfilesProvider = FutureProvider<List<AiProfileModel>>((ref) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return [];
  final snap = await FirebaseService.getAiProfiles(uid);
  return snap.docs.map((d) {
    final data = Map<String, dynamic>.from(d.data() as Map);
    data['id'] = d.id;
    return AiProfileModel.fromJson(data);
  }).toList();
});