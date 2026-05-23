// =============================================================================
// USER PREFERENCES
// Firestore path: users/{uid}/data/preferences
//
// Lightweight document that persists the user's app-level settings.
// Kept separate from the profile so preference updates don't trigger
// unnecessary profile listeners.
// =============================================================================

class UserPreferencesModel {
  final bool onboardingComplete;   // false until the user finishes onboarding
  final String? defaultTemplate;  // template ID to pre-select on new CV creation
  final String? defaultFont;      // font family preference for CV rendering
  final String theme;             // 'light' | 'dark'
  final bool emailNotifications;  // opt-in/out of marketing & status emails

  const UserPreferencesModel({
    this.onboardingComplete  = false,
    this.defaultTemplate,
    this.defaultFont,
    this.theme               = 'light',
    this.emailNotifications  = true,
  });

  // ---------------------------------------------------------------------------
  // Serialization
  // ---------------------------------------------------------------------------

  Map<String, dynamic> toJson() => {
    'onboardingComplete': onboardingComplete,
    'defaultTemplate':    defaultTemplate,
    'defaultFont':        defaultFont,
    'theme':              theme,
    'emailNotifications': emailNotifications,
  };

  factory UserPreferencesModel.fromJson(Map<String, dynamic> json) {
    return UserPreferencesModel(
      onboardingComplete: json['onboardingComplete'] ?? false,
      defaultTemplate:    json['defaultTemplate'],
      defaultFont:        json['defaultFont'],
      theme:              json['theme']              ?? 'light',
      emailNotifications: json['emailNotifications'] ?? true,
    );
  }
}