class AppRoutes {
  AppRoutes._();

  static const String auth          = '/';
  static const String dashboard     = '/dashboard';

  // CV tool
  static const String cvDashboard   = '/cv';
  static const String cvTemplates   = '/cv/cv_templates';
  static const String cvEditor      = '/cv/:docId';

  // Future tools
  static const String proposals     = '/proposals';
  static const String coverLetters  = '/cover-letters';
  static const String linkedin      = '/linkedin';

  static const String settings      = '/settings';
  static const String verifyEmail   = '/verify-email';
  static const String resetPassword = '/reset-password';
}