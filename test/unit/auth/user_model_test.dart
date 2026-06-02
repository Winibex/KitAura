// test/unit/auth/user_model_test.dart
//
// Run:  flutter test test/unit/auth/user_model_test.dart
//
// Pure unit tests for data serialization. No Firebase, no mocks needed.
// These verify that toJson → fromJson round-trips preserve all data,
// that defaults are applied correctly, and that computed properties work.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kitaura/shared/models/ai_profile_model.dart';
import 'package:kitaura/shared/models/analytics_summary_model.dart';
import 'package:kitaura/shared/models/monthly_analytics_model.dart';
import 'package:kitaura/shared/models/subscription_model.dart';
import 'package:kitaura/shared/models/transaction_model.dart';
import 'package:kitaura/shared/models/user_preferences_model.dart';
import 'package:kitaura/shared/models/user_profile_model.dart';

void main() {
  // ─── USER PROFILE MODEL ────────────────────────────────────────────

  group('UserProfileModel', () {
    test('toJson produces correct keys', () {
      final now = DateTime(2026, 5, 17);
      final model = UserProfileModel(
        uid: 'uid123',
        email: 'a@b.com',
        displayName: 'Ada',
        createdAt: now,
      );
      final json = model.toJson();

      expect(json['uid'], 'uid123');
      expect(json['email'], 'a@b.com');
      expect(json['displayName'], 'Ada');
      expect(json['createdAt'], isA<Timestamp>());
      expect(json['updatedAt'], isA<Timestamp>());
      // Optional fields default to null
      expect(json['photoUrl'], isNull);
      expect(json['phone'], isNull);
      expect(json['location'], isNull);
      expect(json['bio'], isNull);
    });

    test('fromJson → toJson round-trip preserves data', () {
      final now = DateTime(2026, 5, 17);
      final original = UserProfileModel(
        uid: 'uid1',
        email: 'x@y.com',
        displayName: 'Test User',
        photoUrl: 'https://photo.url',
        phone: '+1234567890',
        location: 'Lahore',
        bio: 'A bio.',
        createdAt: now,
      );

      final json = original.toJson();
      final restored = UserProfileModel.fromJson(json);

      expect(restored.uid, original.uid);
      expect(restored.email, original.email);
      expect(restored.displayName, original.displayName);
      expect(restored.photoUrl, original.photoUrl);
      expect(restored.phone, original.phone);
      expect(restored.location, original.location);
      expect(restored.bio, original.bio);
    });

    test('fromJson handles missing fields gracefully', () {
      final model = UserProfileModel.fromJson({});

      expect(model.uid, '');
      expect(model.email, '');
      expect(model.displayName, '');
      expect(model.photoUrl, isNull);
    });

    test('copyWith updates only specified fields', () {
      final now = DateTime(2026, 5, 17);
      final original = UserProfileModel(
        uid: 'uid1',
        email: 'a@b.com',
        displayName: 'Old Name',
        createdAt: now,
      );

      final updated = original.copyWith(displayName: 'New Name');

      expect(updated.displayName, 'New Name');
      expect(updated.uid, 'uid1'); // unchanged
      expect(updated.email, 'a@b.com'); // unchanged
      expect(updated.createdAt, now); // unchanged
    });

    test('updatedAt defaults to createdAt when not specified', () {
      final now = DateTime(2026, 5, 17);
      final model = UserProfileModel(
        uid: 'uid1',
        email: 'a@b.com',
        displayName: 'Test',
        createdAt: now,
      );

      expect(model.updatedAt, now);
    });
  });

  // ─── SUBSCRIPTION MODEL ────────────────────────────────────────────

  group('SubscriptionModel', () {
    test('default values are free plan with zero counts', () {
      const model = SubscriptionModel();
      expect(model.plan, 'free');
      expect(model.exportCount, 0);
      expect(model.aiFillCount, 0);
      expect(model.cvCount, 0);
      expect(model.isPro, false);
    });

    test('isPro returns true when plan is pro', () {
      const model = SubscriptionModel(plan: 'pro');
      expect(model.isPro, true);
    });

    test('isPro returns true when trial is active', () {
      const model = SubscriptionModel(plan: 'trial', trialActive: true);
      expect(model.isPro, true);
    });

    test('canExport returns true when under free limit', () {
      const model = SubscriptionModel(exportCount: 2);
      expect(model.canExport, true);
    });

    test('canExport returns false when at free limit', () {
      const model = SubscriptionModel(exportCount: 3);
      expect(model.canExport, false);
    });

    test('canExport always true for pro', () {
      const model = SubscriptionModel(plan: 'pro', exportCount: 999);
      expect(model.canExport, true);
    });

    test('canUseAI returns false when at free limit', () {
      const model = SubscriptionModel(aiFillCount: 15);
      expect(model.canUseAI, false);
    });

    test('canCreateCV returns false when at free limit', () {
      const model = SubscriptionModel(cvCount: 3);
      expect(model.canCreateCV, false);
    });

    test('fromJson → toJson round-trip preserves data', () {
      const original = SubscriptionModel(
        plan: 'pro',
        exportCount: 5,
        aiFillCount: 3,
        cvCount: 7,
      );
      final json = original.toJson();
      final restored = SubscriptionModel.fromJson(json);
      expect(restored.plan, 'pro');
      expect(restored.exportCount, 5);
      expect(restored.aiFillCount, 3);
      expect(restored.cvCount, 7);
    });

    test('fromJson handles missing fields with defaults', () {
      final model = SubscriptionModel.fromJson({});
      expect(model.plan, 'free');
      expect(model.exportCount, 0);
    });
  });

  // ─── ANALYTICS SUMMARY MODEL ──────────────────────────────────────

  group('AnalyticsSummaryModel', () {
    test('default values are all zero', () {
      const model = AnalyticsSummaryModel();

      expect(model.loginCount, 0);
      expect(model.totalExports, 0);
      expect(model.totalAiFills, 0);
      expect(model.totalCvsCreated, 0);
      expect(model.signupSource, isNull);
    });

    test('fromJson → toJson round-trip', () {
      final now = DateTime(2026, 5, 17);
      final original = AnalyticsSummaryModel(
        lastLoginAt: now,
        loginCount: 42,
        totalExports: 10,
        signupSource: 'google',
      );

      final json = original.toJson();
      final restored = AnalyticsSummaryModel.fromJson(json);

      expect(restored.loginCount, 42);
      expect(restored.totalExports, 10);
      expect(restored.signupSource, 'google');
    });
  });

  // ─── WORK EXPERIENCE ENTRY ────────────────────────────────────────

  group('WorkExperienceEntry', () {
    test('defaults are empty strings', () {
      const entry = WorkExperienceEntry();
      expect(entry.jobTitle, '');
      expect(entry.company, '');
      expect(entry.isCurrentRole, false);
    });

    test('fromJson → toJson round-trip', () {
      const original = WorkExperienceEntry(
        jobTitle: 'Engineer',
        company: 'Acme',
        startDate: '2024-01',
        endDate: '2026-05',
        isCurrentRole: true,
        description: 'Built things.',
      );

      final json = original.toJson();
      final restored = WorkExperienceEntry.fromJson(json);

      expect(restored.jobTitle, 'Engineer');
      expect(restored.company, 'Acme');
      expect(restored.isCurrentRole, true);
      expect(restored.description, 'Built things.');
    });

    test('copyWith updates only specified fields', () {
      const original = WorkExperienceEntry(
        jobTitle: 'Engineer',
        company: 'Acme',
      );

      final updated = original.copyWith(company: 'NewCorp');

      expect(updated.jobTitle, 'Engineer'); // unchanged
      expect(updated.company, 'NewCorp');
    });
  });

  // ─── EDUCATION ENTRY ──────────────────────────────────────────────

  group('EducationEntry', () {
    test('fromJson handles missing fields', () {
      final entry = EducationEntry.fromJson({});
      expect(entry.degree, '');
      expect(entry.school, '');
      expect(entry.gradeValue, isNull);
    });

    test('copyWith preserves unchanged fields', () {
      const original = EducationEntry(
        degree: 'BS CS',
        school: 'MIT',
        gradeValue: '3.9',
      );

      final updated = original.copyWith(school: 'Stanford');

      expect(updated.degree, 'BS CS');
      expect(updated.school, 'Stanford');
      expect(updated.gradeValue, '3.9');
    });
  });

  // ─── LANGUAGE ENTRY ───────────────────────────────────────────────

  group('LanguageEntry', () {
    test('default proficiency is intermediate', () {
      const entry = LanguageEntry();
      expect(entry.proficiency, 'intermediate');
    });

    test('fromJson round-trip', () {
      const original = LanguageEntry(
        language: 'Urdu',
        proficiency: 'native',
      );

      final json = original.toJson();
      final restored = LanguageEntry.fromJson(json);

      expect(restored.language, 'Urdu');
      expect(restored.proficiency, 'native');
    });
  });

  // ─── AI PROFILE MODEL ────────────────────────────────────────────

  group('AiProfileModel', () {
    test('defaults are empty/default values', () {
      const model = AiProfileModel();

      expect(model.fullName, '');
      expect(model.experienceLevel, 'mid');
      expect(model.tone, 'professional');
      expect(model.experiences, isEmpty);
      expect(model.education, isEmpty);
      expect(model.skills, isEmpty);
    });

    test('fromJson restores nested lists correctly', () {
      final json = {
        'fullName': 'Ada',
        'email': 'a@b.com',
        'phone': '+1234',
        'location': 'Lahore',
        'experienceLevel': 'senior',
        'tone': 'creative',
        'industry': 'Tech',
        'skills': ['Dart', 'Flutter'],
        'certifications': ['AWS'],
        'experiences': [
          {
            'jobTitle': 'Dev',
            'company': 'Acme',
            'startDate': '2024-01',
            'endDate': '2026-01',
            'isCurrentRole': false,
            'description': 'Code.',
          },
        ],
        'education': [
          {
            'degree': 'BS',
            'school': 'LUMS',
            'startDate': '2020',
            'endDate': '2024',
          },
        ],
        'languages': [
          {'language': 'Urdu', 'proficiency': 'native'},
          {'language': 'English', 'proficiency': 'fluent'},
        ],
        'updatedAt': Timestamp.fromDate(DateTime(2026, 5, 17)),
      };

      final model = AiProfileModel.fromJson(json);

      expect(model.fullName, 'Ada');
      expect(model.experienceLevel, 'senior');
      expect(model.skills, ['Dart', 'Flutter']);
      expect(model.certifications, ['AWS']);
      expect(model.experiences, hasLength(1));
      expect(model.experiences.first.jobTitle, 'Dev');
      expect(model.education, hasLength(1));
      expect(model.education.first.school, 'LUMS');
      expect(model.languages, hasLength(2));
    });

    test('copyWith updates updatedAt automatically', () {
      const original = AiProfileModel(fullName: 'Old');
      final updated = original.copyWith(fullName: 'New');

      expect(updated.fullName, 'New');
      expect(updated.updatedAt, isNotNull);
    });
  });

  // ─── USER PREFERENCES MODEL ──────────────────────────────────────

  group('UserPreferencesModel', () {
    test('defaults are sensible', () {
      const model = UserPreferencesModel();

      expect(model.onboardingComplete, false);
      expect(model.theme, 'light');
      expect(model.emailNotifications, true);
      expect(model.defaultTemplate, isNull);
      expect(model.defaultFont, isNull);
    });

    test('fromJson round-trip', () {
      const original = UserPreferencesModel(
        onboardingComplete: true,
        defaultTemplate: 'classic_navy',
        defaultFont: 'Poppins',
        theme: 'dark',
        emailNotifications: false,
      );

      final json = original.toJson();
      final restored = UserPreferencesModel.fromJson(json);

      expect(restored.onboardingComplete, true);
      expect(restored.defaultTemplate, 'classic_navy');
      expect(restored.defaultFont, 'Poppins');
      expect(restored.theme, 'dark');
      expect(restored.emailNotifications, false);
    });
  });

  // ─── TRANSACTION MODEL ────────────────────────────────────────────

  group('TransactionModel', () {
    test('createdAt defaults to now when not specified', () {
      final model = TransactionModel(id: 'tx1', type: 'export');
      expect(model.createdAt, isNotNull);
    });

    test('fromJson round-trip', () {
      final now = DateTime(2026, 5, 17);
      final original = TransactionModel(
        id: 'tx1',
        type: 'aiFill',
        cvId: 'cv1',
        cvTitle: 'My CV',
        metadata: {'section': 'experience'},
        createdAt: now,
      );

      final json = original.toJson();
      final restored = TransactionModel.fromJson(json);

      expect(restored.id, 'tx1');
      expect(restored.type, 'aiFill');
      expect(restored.cvId, 'cv1');
      expect(restored.cvTitle, 'My CV');
      expect(restored.metadata?['section'], 'experience');
    });

    test('fromJson handles missing optional fields', () {
      final model = TransactionModel.fromJson({'id': 'tx2', 'type': 'export'});
      expect(model.cvId, isNull);
      expect(model.cvTitle, isNull);
      expect(model.metadata, isNull);
    });
  });

  // ─── MONTHLY ANALYTICS MODEL ──────────────────────────────────────

  group('MonthlyAnalyticsModel', () {
    test('fromJson round-trip', () {
      final original = MonthlyAnalyticsModel(
        month: '2026-05',
        exports: 3,
        aiFills: 7,
        cvsCreated: 2,
        logins: 15,
        exportedCvIds: ['cv1', 'cv2'],
      );

      final json = original.toJson();
      final restored = MonthlyAnalyticsModel.fromJson(json);

      expect(restored.month, '2026-05');
      expect(restored.exports, 3);
      expect(restored.aiFills, 7);
      expect(restored.exportedCvIds, ['cv1', 'cv2']);
    });
  });
}