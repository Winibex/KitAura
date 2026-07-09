// lib/shared/providers/announcement_provider.dart
//
// Three providers:
//   announcementProvider              → live config/announcement doc
//   lastSeenAnnouncementIdProvider    → live users/{uid}.lastSeenAnnouncementId
//   shouldShowAnnouncementProvider    → resolved AnnouncementModel or null
//
// The banner widget only watches shouldShowAnnouncementProvider so the
// visibility rule lives in one place. Errors or missing docs resolve to
// "no banner" — safe default matches the feature-flags policy.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/announcement_model.dart';

/// Live stream of config/announcement.
final announcementProvider = StreamProvider<AnnouncementModel?>((ref) {
  return FirebaseFirestore.instance
      .doc('config/announcement')
      .snapshots()
      .map((snap) {
    if (!snap.exists) return null;
    final data = snap.data();
    if (data == null) return null;
    return AnnouncementModel.fromMap(data);
  }).handleError((_) => null);
});

/// Live stream of the current user's lastSeenAnnouncementId.
/// Returns null when signed out or when the field is missing (never dismissed).
final lastSeenAnnouncementIdProvider = StreamProvider<String?>((ref) {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return Stream.value(null);

  return FirebaseFirestore.instance
      .doc('users/${user.uid}')
      .snapshots()
      .map((snap) {
    if (!snap.exists) return null;
    return snap.data()?['lastSeenAnnouncementId'] as String?;
  }).handleError((_) => null);
});

/// Resolves to the announcement the user should currently see, or null.
/// Combines: active + has-id + not-yet-dismissed.
final shouldShowAnnouncementProvider = Provider<AnnouncementModel?>((ref) {
  final announcement = ref.watch(announcementProvider).value;
  if (announcement == null || !announcement.isDisplayable) return null;

  final lastSeen = ref.watch(lastSeenAnnouncementIdProvider).value;
  if (lastSeen == announcement.id) return null;

  return announcement;
});