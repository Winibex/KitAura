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
  }) async
  {
    final batch = _db.batch();
    final now   = Timestamp.fromDate(DateTime.now());

    // 1. ── User profile ──────────────────────────────────────────────────────
    batch.set(_userDoc(uid), {
      'uid':         uid,
      'email':       email,
      'displayName': displayName,
      'photoUrl':    photoUrl,
      'phone':       null,
      'location':    null,
      'bio':         null,
      'hasUsedTrial': false,
      'createdAt':   now,
      'updatedAt':   now,
    });

    // 2. ── Subscription — free tier with per-user billing cycle ──────
    final cycleEnd = DateTime.now().add(const Duration(days: 30));
    batch.set(_subscriptionDoc(uid), {
      'plan': 'free',

      // Trial
      'trialStartDate': null,
      'trialEndDate': null,
      'trialActive': false,
      'trialUsed': false,

      // Billing cycle (30 days from signup)
      'cycleStartDate': now,
      'cycleEndDate': Timestamp.fromDate(cycleEnd),
      'lastResetDate': now,

      // Usage counters (reset each cycle)
      'aiFillCount': 0,
      'aiRewriteCount': 0,
      'aiDesignCount': 0,
      'exportCount': 0,
      'spellcheckCount': 0,

      // Document counts (lifetime)
      'cvCount': 0,
      'coverLetterCount': 0,
      'proposalCount': 0,

      // Stripe
      'stripeCustomerId': null,
      'stripeSubscriptionId': null,
      'subscriptionStartDate': null,
      'subscriptionEndDate': null,
    });

    // 3. ── Analytics summary — seed with the sign-up login ───────────────────
    batch.set(_analyticsSummaryDoc(uid), {
      'lastLoginAt':     now,
      'loginCount':      1,     // count the sign-up itself as the first login
      'totalExports':    0,
      'totalAiFills':    0,
      'totalCvsCreated': 0,
      'lastActiveAt':    now,
      'signupSource':    signupSource,
      'device':          null,
      'browser':         null,
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
        'exportedCvIds':  <String>[],
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
  // AI PROFILE  —  users/{uid}/data/aiProfile
  // ===========================================================================

  static DocumentReference _aiProfileDoc(String uid) =>
      _userDoc(uid).collection('data').doc('aiProfile');

  /// Overwrites the AI profile document with [data].
  /// The AI profile is always saved in full — partial merges are not supported
  /// because nested lists (experiences, education) must be replaced atomically.
  static Future<void> saveAiProfile(
      String uid,
      Map<String, dynamic> data,
      ) async =>
      await _aiProfileDoc(uid).set(data);

  /// Fetches the AI profile document snapshot.
  static Future<DocumentSnapshot> getAiProfile(String uid) async =>
      await _aiProfileDoc(uid).get();

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

  // ---------------------------------------------------------------------------
  // trackLogin
  //
  // Updates both the lifetime summary and the current-month document in a
  // single batch. Called on every sign-in (including Google).
  // Uses merge:true so the monthly document is created automatically if it
  // doesn't exist yet (e.g. first login of a new month).
  // ---------------------------------------------------------------------------

  static Future<void> trackLogin(String uid) async {
    final batch = _db.batch();
    final now   = Timestamp.fromDate(DateTime.now());

    // Lifetime summary — increment login counter and update last-seen timestamps.
    batch.set(
      _analyticsSummaryDoc(uid),
      {
        'lastLoginAt':  now,
        'loginCount':   FieldValue.increment(1),
        'lastActiveAt': now,
      },
      SetOptions(merge: true),
    );

    // Current-month document — increment this month's login tally.
    batch.set(
      _monthlyAnalyticsDoc(uid, _currentMonth),
      {
        'month':     _currentMonth,
        'logins':    FieldValue.increment(1),
        'updatedAt': now,
      },
      SetOptions(merge: true),
    );

    await batch.commit();
  }

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
}