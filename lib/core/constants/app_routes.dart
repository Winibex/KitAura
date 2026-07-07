class AppRoutes {
  AppRoutes._();

  // Auth
  static const String auth          = '/';
  static const String verifyEmail   = '/verify-email';
  static const String resetPassword = '/reset-password';

  // Dashboard
  static const String dashboard     = '/dashboard';

  // CV
  static const String cvDashboard   = '/cv';
  static const String cvTemplates   = '/cv/templates';
  static const String cvTemplatePreview = '/cv/templates/:templateId';
  static const String cvEditor      = '/cv/edit/:docId';

  // Cover Letter
  static const String clDashboard   = '/cover-letters';
  static const String clTemplates   = '/cover-letters/templates';
  static const String clTemplatePreview = '/cover-letters/templates/:templateId';
  static const String clEditor      = '/cover-letters/edit/:docId';

  // Proposal
  static const String proposalDashboard = '/proposals';
  static const String proposalTemplates = '/proposals/templates';
  static const String proposalTemplatePreview = '/proposals/templates/:templateId';
  static const String proposalEditor    = '/proposals/edit/:docId';

  // LinkedIn
  static const String linkedin      = '/linkedin';

  // Settings
  static const String settings      = '/settings';
}