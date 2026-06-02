// =============================================================================
// user_models.dart
//
// Data models for all user-related Firestore documents.
//
// Firestore document layout:
//
//   users/{uid}                          → UserProfileModel
//   users/{uid}/data/subscription        → SubscriptionModel
//   users/{uid}/data/aiProfile           → AiProfileModel
//   users/{uid}/data/preferences         → UserPreferencesModel
//   users/{uid}/analytics/summary        → AnalyticsSummaryModel
//   users/{uid}/analytics/{YYYY-MM}      → MonthlyAnalyticsModel
//   users/{uid}/transactions/{txId}      → TransactionModel
//
// Each model follows the same three-part pattern:
//   • toJson()       — serialize to a Map for Firestore writes
//   • fromJson()     — deserialize from a Firestore document snapshot
//   • copyWith()     — immutable update helper (where applicable)
// =============================================================================


