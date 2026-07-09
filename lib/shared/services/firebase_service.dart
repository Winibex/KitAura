// =============================================================================
// firebase_service.dart
//
// A single static facade over Firebase Auth and Firestore.
//
// Design decisions:
//   • All methods are static — no instance needed; callers import and call directly.
//   • Private constructor prevents accidental instantiation.
//   • All multi-document writes use Firestore batches so the database is never
//     left in a partially-written state (atomic all-or-nothing semantics).
//   • Document references are built from private helper getters, keeping path
//     strings in one place and making future path changes trivial.
//   • Auth, Firestore CRUD for all collections (users, CVs, subscriptions,
//     analytics, transactions), batched writes for new user creation and usage
//     tracking.
//
// Firestore document layout (mirrors user_models.dart):
//
//   users/{uid}                          → user profile
//   users/{uid}/data/subscription        → plan & usage counters
//   users/{uid}/data/aiProfile           → AI generation profile
//   users/{uid}/data/preferences         → app settings
//   users/{uid}/analytics/summary        → lifetime aggregate stats
//   users/{uid}/analytics/{YYYY-MM}      → per-month stats
//   users/{uid}/cvs/{cvId}               → individual CV documents
//   users/{uid}/transactions/{txId}      → append-only event log
// =============================================================================

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

import '../models/ai_profile_model.dart';
import '../models/subscription_model.dart';

class FirebaseService {
  // Private constructor — this class is a pure static utility; never instantiate it.
  FirebaseService._();

  // ---------------------------------------------------------------------------
  // Singleton SDK references
  // Stored as static finals so the SDK objects are initialised once and
  // reused across all calls, matching the Firebase SDK's own singleton pattern.
  // ---------------------------------------------------------------------------

  static final FirebaseAuth      _auth = FirebaseAuth.instance;
  static final FirebaseFirestore _db   = FirebaseFirestore.instance;

  // ===========================================================================
  // AUTH
  // ===========================================================================

  /// The currently signed-in [User], or null if no user is authenticated.
  static User? get currentUser => _auth.currentUser;

  /// A broadcast stream that emits a [User] on sign-in and null on sign-out.
  /// Useful for router guards and global auth listeners.
  static Stream<User?> get authStateChanges => _auth.authStateChanges();

  // ---------------------------------------------------------------------------
  // Sign in / sign up
  // ---------------------------------------------------------------------------

  /// Signs in an existing user with [email] and [password].
  /// Throws [FirebaseAuthException] on invalid credentials, network errors, etc.
  static Future<UserCredential> signInWithEmail(
      String email,
      String password,
      ) async
  {
    return await _auth.signInWithEmailAndPassword(
      email:    email,
      password: password,
    );
  }

  /// Creates a new Firebase Auth account with [email] and [password].
  /// Does NOT create Firestore documents — call [createNewUserDocuments] after.
  static Future<UserCredential> signUpWithEmail(
      String email,
      String password,
      ) async
  {
    return await _auth.createUserWithEmailAndPassword(
      email:    email,
      password: password,
    );
  }

  /// Launches the Google OAuth popup (web) or native flow (mobile/desktop).
  /// Requests the 'email' and 'profile' scopes so display name and photo
  /// are available on the returned [UserCredential].
  static Future<UserCredential> signInWithGoogle() async {
    final googleProvider = GoogleAuthProvider()
      ..addScope('email')
      ..addScope('profile');
    return await _auth.signInWithPopup(googleProvider);
  }

  /// Signs the current user out of Firebase Auth.
  static Future<void> signOut() async => await _auth.signOut();

  /// Creates an anonymous Firebase Auth session.
  /// The anonymous uid persists in the browser's IndexedDB across
  /// tab/browser restarts on the same device.
  /// Call [createNewUserDocuments] after to bootstrap Firestore docs.
  static Future<UserCredential> signInAnonymously() async {
    return await _auth.signInAnonymously();
  }

  /// Sends a password-reset email to [email].
  /// The email contains a link that lets the user set a new password.
  static Future<void> sendPasswordResetEmail(String email) async {
    await _auth.sendPasswordResetEmail(email: email);
  }

  // ===========================================================================
  // BATCHED NEW USER CREATION
  //
  // Writes all five initial documents for a brand-new user in a single
  // Firestore batch commit. Because a batch is atomic, either every document
  // is created or none are — no orphaned partial user records.
  //
  // Documents written:
  //   1. users/{uid}                     → profile
  //   2. users/{uid}/data/subscription   → free-tier subscription defaults
  //   3. users/{uid}/analytics/summary   → analytics summary (loginCount = 1)
  //   4. users/{uid}/data/preferences    → app preference defaults
  //   5. users/{uid}/analytics/{YYYY-MM} → current-month analytics seed
  // ===========================================================================

  static Future<void> createNewUserDocuments({
    required String uid,
    required String email,
    required String displayName,
    String? photoUrl,
    required String signupSource, // 'email' | 'google' | etc.
    required String phoneNumber,
  }) async
  {
    // Idempotency guard — if user doc already exists, skip creation.
    // Prevents overwriting data for already-initialized anonymous users
    // or during credential linking (linkWithCredential preserves the uid).
    final existingDoc = await _userDoc(uid).get();
    if (existingDoc.exists) return;

    final batch = _db.batch();
    final now   = Timestamp.fromDate(DateTime.now());

    // 1. ── User profile ──────────────────────────────────────────────────────
    batch.set(_userDoc(uid), {
      'uid':         uid,
      'email':       email,
      'displayName': displayName,
      'photoUrl':    photoUrl,
      'phone':       phoneNumber,
      'location':    null,
      'bio':         null,
      'hasUsedTrial': false,
      'createdAt':   now,
      'updatedAt':   now,
    });

    // 2. ── Subscription — free tier with per-user billing cycle ──────
    final cycleEnd = DateTime.now().add(const Duration(days: 30));
    final plan = signupSource == 'anonymous' ? 'guest' : 'free';
    final initialSubscription = SubscriptionModel(
      plan: plan,
      cycleStartDate: now.toDate(),
      cycleEndDate: cycleEnd,
      lastResetDate: now.toDate(),
    );
    batch.set(_subscriptionDoc(uid), initialSubscription.toJson());

    // 3. ── Analytics summary — seed with the sign-up login ───────────────────
    batch.set(_analyticsSummaryDoc(uid), {
      'lastLoginAt':     now,
      'loginCount':      1,     // count the sign-up itself as the first login
      'totalExports':    0,
      'totalAiFills':    0,
      'totalCvsCreated': 0,
      'lastActiveAt':    now,
      'signupSource':    signupSource,
      'device':          _detectDevice(),
      'browser':         _detectBrowser(),
    });

    // 4. ── Preferences — sensible defaults ───────────────────────────────────
    batch.set(_preferencesDoc(uid), {
      'onboardingComplete': false,  // user must complete onboarding first
      'defaultTemplate':    null,
      'defaultFont':        null,
      'theme':              'light',
      'emailNotifications': true,
    });

    // 5. ── Monthly analytics — seed current month with the sign-up login ─────
    batch.set(
      _monthlyAnalyticsDoc(uid, _currentMonth),
      {
        'month':          _currentMonth,
        'logins':         1,
        'exports':        0,
        'aiFills':        0,
        'cvsCreated':     0,
        'exportedDocIds': <String>[],
        // 'exportedCvIds':  <String>[],
        'updatedAt':      now,
      },
    );

    await batch.commit();
  }

  // ===========================================================================
  // DOCUMENT REFERENCE HELPERS (private)
  //
  // All Firestore paths are defined here and nowhere else.
  // Changing a path requires editing exactly one line.
  // ===========================================================================

  /// Root user document: users/{uid}
  static DocumentReference _userDoc(String uid) =>
      _db.collection('users').doc(uid);

  /// Returns the current calendar month as an ISO string: "YYYY-MM".
  /// Used as the document ID for monthly analytics records.
  static String get _currentMonth {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}';
  }

  // ===========================================================================
  // USER PROFILE  —  users/{uid}
  // ===========================================================================

  /// Creates (or overwrites) a user profile document.
  static Future<void> createUserProfile(
      String uid,
      Map<String, dynamic> data,
      ) async =>
      await _userDoc(uid).set(data);

  /// Fetches the user profile document snapshot.
  static Future<DocumentSnapshot> getUserProfile(String uid) async =>
      await _userDoc(uid).get();

  /// Partially updates the user profile with the given [data] fields.
  /// Only the provided keys are changed; all other fields are left intact.
  static Future<void> updateUserProfile(
      String uid,
      Map<String, dynamic> data,
      ) async =>
      await _userDoc(uid).update(data);

  // ===========================================================================
  // SUBSCRIPTION  —  users/{uid}/data/subscription
  // ===========================================================================

  static DocumentReference _subscriptionDoc(String uid) =>
      _userDoc(uid).collection('data').doc('subscription');

  /// Creates (or overwrites) the subscription document.
  static Future<void> createSubscription(
      String uid,
      Map<String, dynamic> data,
      ) async =>
      await _subscriptionDoc(uid).set(data);

  /// Fetches the subscription document snapshot.
  static Future<DocumentSnapshot> getSubscription(String uid) async =>
      await _subscriptionDoc(uid).get();

  /// Merges [data] into the subscription document.
  /// Prefer this over a full overwrite to avoid accidentally clearing Stripe IDs.
  static Future<void> updateSubscription(
      String uid,
      Map<String, dynamic> data,
      ) async =>
      await _subscriptionDoc(uid).set(data, SetOptions(merge: true));


// ===========================================================================
  // Career ProfileS (multiple) — users/{uid}/aiProfiles/{profileId}
  // ===========================================================================

  // ─── AI PROFILES (Career Profiles) ──────────────────────────────────

  static CollectionReference _aiProfilesCollection(String uid) =>
      _userDoc(uid).collection('aiProfiles');

  /// Get all Career Profiles for a user, ordered by name.
  static Future<QuerySnapshot> getAiProfiles(String uid) async =>
      await _aiProfilesCollection(uid).orderBy('name').get();

  /// Get a single Career Profile by ID.
  static Future<DocumentSnapshot> getAiProfileById(
      String uid, String profileId) async =>
      await _aiProfilesCollection(uid).doc(profileId).get();

  /// Get the default Career Profile. Falls back to the first profile if
  /// none is marked default. Returns null if the user has no profiles.
  static Future<AiProfileModel?> getDefaultAiProfile(String uid) async {
    // Prefer the explicitly default profile.
    final defaults = await _aiProfilesCollection(uid)
        .where('isDefault', isEqualTo: true)
        .limit(1)
        .get();
    if (defaults.docs.isNotEmpty) {
      final data = defaults.docs.first.data() as Map<String, dynamic>;
      data['id'] = defaults.docs.first.id;
      return AiProfileModel.fromJson(data);
    }
    // No default — return whatever first profile exists (if any).
    final any = await _aiProfilesCollection(uid).limit(1).get();
    if (any.docs.isNotEmpty) {
      final data = any.docs.first.data() as Map<String, dynamic>;
      data['id'] = any.docs.first.id;
      return AiProfileModel.fromJson(data);
    }
    return null;
  }

  /// Create a new Career Profile. First profile is automatically marked
  /// default. Subsequent profiles are never default on creation — user
  /// must explicitly call setDefaultAiProfile to change the default.
  static Future<DocumentReference> createAiProfile(
      String uid, Map<String, dynamic> data) async {
    final existing = await _aiProfilesCollection(uid).limit(1).get();
    if (existing.docs.isEmpty) {
      data['isDefault'] = true;
    } else {
      // Force isDefault to false on new profiles after the first.
      // Use setDefaultAiProfile() to change which profile is default.
      data['isDefault'] = false;
    }
    return await _aiProfilesCollection(uid).add(data);
  }

  /// Update an existing Career Profile.
  static Future<void> updateAiProfile(
      String uid, String profileId, Map<String, dynamic> data) async =>
      await _aiProfilesCollection(uid).doc(profileId).update(data);

  /// Save (create or update) a Career Profile. Returns the profile's doc ID.
  ///
  /// If the data sets isDefault: true on an existing profile, ALL other
  /// profiles will have their isDefault cleared to maintain the invariant
  /// that exactly one profile is default at a time.
  static Future<String> saveAiProfileMulti(
      String uid, Map<String, dynamic> data, {String? profileId}) async
  {
    if (profileId == null) {
      // New profile — createAiProfile handles the default logic.
      final ref = await createAiProfile(uid, data);
      return ref.id;
    }

    // Existing profile update.
    final isBecomingDefault = data['isDefault'] == true;
    if (isBecomingDefault) {
      // Atomically: clear all OTHER defaults, then save this one.
      final batch = _db.batch();
      final allProfiles = await _aiProfilesCollection(uid).get();
      for (final doc in allProfiles.docs) {
        if (doc.id != profileId && (doc.data() as Map)['isDefault'] == true) {
          batch.update(doc.reference, {'isDefault': false});
        }
      }
      batch.set(
        _aiProfilesCollection(uid).doc(profileId),
        data,
        SetOptions(merge: true),
      );
      await batch.commit();
    } else {
      // Normal update, no default change.
      await _aiProfilesCollection(uid)
          .doc(profileId)
          .set(data, SetOptions(merge: true));
    }
    return profileId;
  }

  /// Delete a Career Profile by ID. If the deleted profile was the default
  /// and other profiles exist, promotes the first remaining profile to default.
  static Future<void> deleteAiProfile(String uid, String profileId) async {
    final docRef = _aiProfilesCollection(uid).doc(profileId);
    final doc = await docRef.get();
    final wasDefault = doc.exists && (doc.data() as Map)['isDefault'] == true;

    await docRef.delete();

    if (wasDefault) {
      final remaining = await _aiProfilesCollection(uid).limit(1).get();
      if (remaining.docs.isNotEmpty) {
        await remaining.docs.first.reference.update({'isDefault': true});
      }
    }
  }

  /// Set a profile as default (unsets all other defaults atomically).
  static Future<void> setDefaultAiProfile(String uid, String profileId) async {
    final batch = _db.batch();
    final allProfiles = await _aiProfilesCollection(uid).get();
    for (final doc in allProfiles.docs) {
      if (doc.id != profileId && (doc.data() as Map)['isDefault'] == true) {
        batch.update(doc.reference, {'isDefault': false});
      }
    }
    batch.update(_aiProfilesCollection(uid).doc(profileId), {'isDefault': true});
    await batch.commit();
  }

  /// Get profile count for a user (for "first profile? make it default" checks).
  static Future<int> getAiProfileCount(String uid) async {
    final snap = await _aiProfilesCollection(uid).get();
    return snap.docs.length;
  }

  // ===========================================================================
  // PREFERENCES  —  users/{uid}/data/preferences
  // ===========================================================================

  static DocumentReference _preferencesDoc(String uid) =>
      _userDoc(uid).collection('data').doc('preferences');

  /// Merges [data] into the preferences document.
  /// Safe to call with a partial map — unspecified fields are preserved.
  static Future<void> savePreferences(
      String uid,
      Map<String, dynamic> data,
      ) async =>
      await _preferencesDoc(uid).set(data, SetOptions(merge: true));

  /// Fetches the preferences document snapshot.
  static Future<DocumentSnapshot> getPreferences(String uid) async =>
      await _preferencesDoc(uid).get();

  // ===========================================================================
  // ANALYTICS SUMMARY  —  users/{uid}/analytics/summary
  // ===========================================================================

  static DocumentReference _analyticsSummaryDoc(String uid) =>
      _userDoc(uid).collection('analytics').doc('summary');

  /// Creates (or overwrites) the analytics summary document.
  /// Typically only called during user initialisation; prefer [trackLogin] for
  /// subsequent updates.
  static Future<void> createAnalyticsSummary(
      String uid,
      Map<String, dynamic> data,
      ) async =>
      await _analyticsSummaryDoc(uid).set(data);

  /// Fetches the analytics summary document snapshot.
  static Future<DocumentSnapshot> getAnalyticsSummary(String uid) async =>
      await _analyticsSummaryDoc(uid).get();


  // ===========================================================================
  // MONTHLY ANALYTICS  —  users/{uid}/analytics/{YYYY-MM}
  // ===========================================================================

  static DocumentReference _monthlyAnalyticsDoc(String uid, String month) =>
      _userDoc(uid).collection('analytics').doc(month);

  /// Fetches the analytics document for the given [month] (format: "YYYY-MM").
  static Future<DocumentSnapshot> getMonthlyAnalytics(
      String uid,
      String month,
      ) async =>
      await _monthlyAnalyticsDoc(uid, month).get();

  // ===========================================================================
  // CVs  —  users/{uid}/cvs/{cvId}
  // ===========================================================================

  /// Returns the CVs sub-collection reference for [uid].
  static CollectionReference _cvsCollection(String uid) =>
      _userDoc(uid).collection('cvs');

  /// Creates a new CV document with an auto-generated ID.
  /// Returns the [DocumentReference] so the caller can read back the new ID.
  static Future<DocumentReference> createCV(
      String uid,
      Map<String, dynamic> data,
      ) async {
    return await _cvsCollection(uid).add(data);
  }

  /// Partially updates the CV document identified by [cvId].
  /// Only the provided [data] keys are changed.
  static Future<void> updateCV(
      String uid,
      String cvId,
      Map<String, dynamic> data,
      ) async {
    await _cvsCollection(uid).doc(cvId).update(data);
  }

  /// Permanently deletes the CV document identified by [cvId].
  /// The caller is responsible for decrementing the subscription CV count
  /// (via [decrementCvCount] or a dedicated track method).
  static Future<void> deleteCV(String uid, String cvId) async {
    await _cvsCollection(uid).doc(cvId).delete();
  }

  /// Fetches a single CV document snapshot.
  static Future<DocumentSnapshot> getCV(String uid, String cvId) async {
    return await _cvsCollection(uid).doc(cvId).get();
  }

  /// Fetches all CVs for [uid], ordered by most recently updated first.
  static Future<QuerySnapshot> getUserCVs(String uid) async {
    return await _cvsCollection(uid)
        .orderBy('updatedAt', descending: true)
        .get();
  }

  // ===========================================================================
  // COVER LETTERS — users/{uid}/coverLetters/{clId}
  // ===========================================================================

  static CollectionReference _coverLettersCollection(String uid) =>
      _userDoc(uid).collection('coverLetters');

  static Future<DocumentReference> createCoverLetter(
      String uid, Map<String, dynamic> data) async =>
      await _coverLettersCollection(uid).add(data);

  static Future<void> updateCoverLetter(
      String uid, String clId, Map<String, dynamic> data) async =>
      await _coverLettersCollection(uid).doc(clId).update(data);

  static Future<void> deleteCoverLetter(String uid, String clId) async =>
      await _coverLettersCollection(uid).doc(clId).delete();

  static Future<DocumentSnapshot> getCoverLetter(String uid, String clId) async =>
      await _coverLettersCollection(uid).doc(clId).get();

  static Future<QuerySnapshot> getUserCoverLetters(String uid) async =>
      await _coverLettersCollection(uid).orderBy('updatedAt', descending: true).get();

  // ===========================================================================
  // PROPOSALS — users/{uid}/proposals/{propId}
  // ===========================================================================

  static CollectionReference _proposalsCollection(String uid) =>
      _userDoc(uid).collection('proposals');

  static Future<DocumentReference> createProposal(
      String uid, Map<String, dynamic> data) async =>
      await _proposalsCollection(uid).add(data);

  static Future<void> updateProposal(
      String uid, String propId, Map<String, dynamic> data) async =>
      await _proposalsCollection(uid).doc(propId).update(data);

  static Future<void> deleteProposal(String uid, String propId) async =>
      await _proposalsCollection(uid).doc(propId).delete();

  static Future<DocumentSnapshot> getProposal(String uid, String propId) async =>
      await _proposalsCollection(uid).doc(propId).get();

  static Future<QuerySnapshot> getUserProposals(String uid) async =>
      await _proposalsCollection(uid).orderBy('updatedAt', descending: true).get();

  // ===========================================================================
  // CLIENT PROFILES — users/{uid}/clientProfiles/{clientId}
  // ===========================================================================

  static CollectionReference _clientProfilesCollection(String uid) =>
      _userDoc(uid).collection('clientProfiles');

  static Future<QuerySnapshot> getClientProfiles(String uid) async =>
      await _clientProfilesCollection(uid)
          .orderBy('updatedAt', descending: true)
          .get();

  static Future<DocumentSnapshot> getClientProfileById(
      String uid, String clientId) async =>
      await _clientProfilesCollection(uid).doc(clientId).get();

  static Future<DocumentReference> createClientProfile(
      String uid, Map<String, dynamic> data) async =>
      await _clientProfilesCollection(uid).add(data);

  static Future<void> updateClientProfile(
      String uid, String clientId, Map<String, dynamic> data) async =>
      await _clientProfilesCollection(uid).doc(clientId).update(data);

  static Future<String> saveClientProfile(
      String uid, Map<String, dynamic> data, {String? clientId}) async {
    if (clientId != null) {
      await _clientProfilesCollection(uid)
          .doc(clientId)
          .set(data, SetOptions(merge: true));
      return clientId;
    } else {
      final ref = await createClientProfile(uid, data);
      return ref.id;
    }
  }

  static Future<void> deleteClientProfile(String uid, String clientId) async =>
      await _clientProfilesCollection(uid).doc(clientId).delete();

  // ===========================================================================
  // LINKEDIN SUMMARIES — users/{uid}/linkedinSummaries/{id}
  // ===========================================================================

  static CollectionReference _linkedInCollection(String uid) =>
      _userDoc(uid).collection('linkedinSummaries');

  static Future<QuerySnapshot> getLinkedInSummaries(String uid) async =>
      await _linkedInCollection(uid)
          .orderBy('createdAt', descending: true)
          .limit(20)
          .get();

  static Future<DocumentSnapshot> getLinkedInSummary(String uid, String docId) async =>
      await _linkedInCollection(uid).doc(docId).get();

  static Future<DocumentReference> createLinkedInSummary(
      String uid, Map<String, dynamic> data) async =>
      await _linkedInCollection(uid).add(data);

  static Future<void> updateLinkedInSummary(
      String uid, String docId, Map<String, dynamic> data) async =>
      await _linkedInCollection(uid).doc(docId).update(data);

  static Future<void> deleteLinkedInSummary(String uid, String docId) async =>
      await _linkedInCollection(uid).doc(docId).delete();

  // ===========================================================================
  // AI ACTIVITY — users/{uid}/aiActivity/{id} (READ ONLY from frontend)
  // ===========================================================================

  static Future<QuerySnapshot> getAiActivity(String uid, {int limit = 50}) async =>
      await _userDoc(uid).collection('aiActivity')
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .get();

  static Future<QuerySnapshot> getAiActivityByTool(String uid, String tool, {int limit = 50}) async =>
      await _userDoc(uid).collection('aiActivity')
          .where('tool', isEqualTo: tool)
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .get();

  // ===========================================================================
  // TRANSACTIONS  —  users/{uid}/transactions/{txId}
  //
  // Append-only event log. Documents are never updated or deleted.
  // ===========================================================================

  /// Fetches the [limit] most recent transaction records (default: 50).
  /// Ordered by creation time, newest first.
  static Future<QuerySnapshot> getTransactions(
      String uid, {
        int limit = 50,
      }) async
  {
    return await _userDoc(uid)
        .collection('transactions')
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .get();
  }

  /// Fetches all transactions of a specific [type] for [uid],
  /// ordered newest first. Useful for filtering by event category
  /// (e.g. 'export', 'aiFill', 'cvCreated').
  static Future<QuerySnapshot> getTransactionsByType(
      String uid,
      String type,
      ) async
  {
    return await _userDoc(uid)
        .collection('transactions')
        .where('type', isEqualTo: type)
        .orderBy('createdAt', descending: true)
        .get();
  }

  /// Fetches plan limits from config/limits for the given plan.
  /// Returns a map with resolved limits (replaces -1 with 999 for unlimited).
  /// Falls back to hardcoded free defaults if config doc doesn't exist.
  static Future<Map<String, int>> getPlanLimits(String plan) async {
    try {
      final limDoc = await _db.doc('config/limits').get();
      if (limDoc.exists) {
        final planLimits = (limDoc.data()?[plan] ?? limDoc.data()?['free']) as Map<String, dynamic>?;
        if (planLimits != null) {
          return {
            'maxCvs': _resolveLimit(planLimits['maxCvs'], 3),
            'maxCoverLetters': _resolveLimit(planLimits['maxCoverLetters'], 3),
            'maxProposals': _resolveLimit(planLimits['maxProposals'], 3),
            'exportsPerMonth': _resolveLimit(planLimits['exportsPerMonth'], 3),
            'aiFillPerMonth': _resolveLimit(planLimits['aiFillPerMonth'], 15),
            'aiRewritePerMonth': _resolveLimit(planLimits['aiRewritePerMonth'], 15),
            'aiDesignPerMonth': _resolveLimit(planLimits['aiDesignPerMonth'], 5),
            'maxDocs': _resolveLimit(planLimits['maxDocs'], 5),
          };
        }
      }
    } catch (e) {
      debugPrint('getPlanLimits error: $e');
    }
    // Fallback defaults
    return {
      'maxCvs': 3, 'maxCoverLetters': 3, 'maxProposals': 3,
      'exportsPerMonth': 3, 'aiFillPerMonth': 15,
      'aiRewritePerMonth': 15, 'aiDesignPerMonth': 5,
      'maxDocs': 5,
    };
  }

  /// Resolves -1 (unlimited in Firestore) to 999 for UI display.
  static int _resolveLimit(dynamic value, int fallback) {
    final v = value as int? ?? fallback;
    return v == -1 ? 999 : v;
  }

  /// Detects the browser name from the user agent string.
  /// Returns "Chrome", "Edge", "Firefox", "Safari", or "Unknown".
  static String _detectBrowser() {
    try {
      final ua = web.window.navigator.userAgent;
      if (ua.contains('Edg/'))      return 'Edge';
      if (ua.contains('OPR/') || ua.contains('Opera')) return 'Opera';
      if (ua.contains('Chrome/'))   return 'Chrome';
      if (ua.contains('Firefox/'))  return 'Firefox';
      if (ua.contains('Safari/'))   return 'Safari';
      return 'Unknown';
    } catch (_) {
      return 'Unknown';
    }
  }

  /// Detects the OS/platform from the user agent string.
  /// Returns "Windows", "macOS", "Linux", "Android", "iOS", or "Unknown".
  static String _detectDevice() {
    try {
      final ua = web.window.navigator.userAgent;
      if (ua.contains('Windows'))    return 'Windows';
      if (ua.contains('Macintosh'))  return 'macOS';
      if (ua.contains('Android'))    return 'Android';
      if (ua.contains('iPhone') || ua.contains('iPad') || ua.contains('iPod')) return 'iOS';
      if (ua.contains('Linux'))      return 'Linux';
      return 'Unknown';
    } catch (_) {
      return 'Unknown';
    }
  }

  static Future<double> getProPrice() async {
    try {
      final doc = await FirebaseFirestore.instance.doc('config/limits').get();
      if (doc.exists) {
        return (doc.data()?['proMonthlyPrice'] ?? -1).toDouble();
      }
    } catch (_) {}
    return -1; // fallback
  }

  /// Records that the user has dismissed a given announcement.
  /// Called by AnnouncementBanner on dismiss or CTA click.
  static Future<void> markAnnouncementSeen(String announcementId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    await FirebaseFirestore.instance
        .doc('users/${user.uid}')
        .update({'lastSeenAnnouncementId': announcementId});
  }
}