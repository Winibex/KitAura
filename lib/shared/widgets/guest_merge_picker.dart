// lib/shared/widgets/guest_merge_picker.dart
//
// Shown when linkWithCredential fails with credential-already-in-use.
// User chooses: merge guest docs into existing account, or discard guest work.

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_fonts.dart';

class GuestMergePickerResult {
  final bool signedIn;
  final bool merged;
  const GuestMergePickerResult({this.signedIn = false, this.merged = false});
}

class GuestMergePickerModal extends StatefulWidget {
  /// The anonymous user's UID (before signing into existing account).
  final String guestUid;

  /// Email of the existing account.
  final String email;

  /// Password (for email flow). Null for Google flow.
  final String? password;

  const GuestMergePickerModal({
    super.key,
    required this.guestUid,
    required this.email,
    this.password,
  });

  /// Shows the picker. Returns result indicating what happened.
  static Future<GuestMergePickerResult> show(
      BuildContext context, {
        required String guestUid,
        required String email,
        String? password,
      }) async {
    final result = await showDialog<GuestMergePickerResult>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black54,
      builder: (_) => GuestMergePickerModal(
        guestUid: guestUid,
        email: email,
        password: password,
      ),
    );
    return result ?? const GuestMergePickerResult();
  }

  @override
  State<GuestMergePickerModal> createState() => _GuestMergePickerModalState();
}

class _GuestMergePickerModalState extends State<GuestMergePickerModal> {
  bool _merging = false;
  bool _discarding = false;
  String? _error;

  // ─── MERGE: sign into existing + copy guest docs ───────────────────

  Future<void> _mergeAndSignIn() async {
    setState(() { _merging = true; _error = null; });

    try {
      // Sign into the existing account
      await _signIntoExistingAccount();

      // Call merge Cloud Function
      final callable = FirebaseFunctions
          .instanceFor(region: 'us-central1')
          .httpsCallable('mergeGuestData');
      await callable.call({'fromUid': widget.guestUid});

      if (mounted) {
        Navigator.pop(context,
            const GuestMergePickerResult(signedIn: true, merged: true));
      }
    } catch (e) {
      debugPrint('Merge failed: $e');
      setState(() {
        _merging = false;
        _error = 'Merge failed. Please try again.';
      });
    }
  }

  // ─── DISCARD: just sign into existing, orphan guest data ───────────

  Future<void> _discardAndSignIn() async {
    setState(() { _discarding = true; _error = null; });

    try {
      await _signIntoExistingAccount();

      if (mounted) {
        Navigator.pop(context,
            const GuestMergePickerResult(signedIn: true, merged: false));
      }
    } catch (e) {
      debugPrint('Sign-in failed: $e');
      setState(() {
        _discarding = false;
        _error = 'Sign-in failed. Please try again.';
      });
    }
  }

  Future<void> _signIntoExistingAccount() async {
    if (widget.password != null) {
      // Email flow — sign in with the typed credentials
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: widget.email,
        password: widget.password!,
      );
    } else {
      // Google flow — re-trigger popup
      final googleProvider = GoogleAuthProvider()
        ..addScope('email')
        ..addScope('profile');
      await FirebaseAuth.instance.signInWithPopup(googleProvider);
    }
  }

  // ─── BUILD ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final busy = _merging || _discarding;

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 440,
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 30,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Icon
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: AppColors.petalFrost,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(LucideIcons.gitMerge,
                  size: 26, color: AppColors.darkRaspberry),
            ),
            const SizedBox(height: 18),

            const Text(
              'Account Already Exists',
              style: TextStyle(
                fontSize: 20,
                fontFamily: AppFonts.poppins,
                fontWeight: FontWeight.bold,
                color: AppColors.prussianBlue,
              ),
            ),
            const SizedBox(height: 8),

            Text(
              '${widget.email} already has a KitAura account. What would you like to do with the documents you created as a guest?',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                fontFamily: AppFonts.openSans,
                color: AppColors.slateGrey,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),

            // Option 1: Merge
            _OptionCard(
              icon: LucideIcons.folderInput,
              title: 'Import guest documents',
              subtitle: 'Copy your guest work into your existing account. Nothing is lost.',
              buttonLabel: _merging ? 'Merging...' : 'Merge & Sign In',
              loading: _merging,
              disabled: busy,
              isPrimary: true,
              onTap: _mergeAndSignIn,
            ),
            const SizedBox(height: 12),

            // Option 2: Discard
            _OptionCard(
              icon: LucideIcons.logIn,
              title: 'Just sign me in',
              subtitle: 'Discard guest documents and sign into your existing account.',
              buttonLabel: _discarding ? 'Signing in...' : 'Sign In Only',
              loading: _discarding,
              disabled: busy,
              isPrimary: false,
              onTap: _discardAndSignIn,
            ),

            // Error
            if (_error != null) ...[
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: AppColors.error.withValues(alpha: 0.2)),
                ),
                child: Text(
                  _error!,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.error,
                    fontFamily: AppFonts.openSans,
                  ),
                ),
              ),
            ],

            const SizedBox(height: 16),

            // Cancel
            MouseRegion(
              cursor: busy ? SystemMouseCursors.basic : SystemMouseCursors.click,
              child: GestureDetector(
                onTap: busy ? null : () => Navigator.pop(
                    context, const GuestMergePickerResult()),
                child: Text(
                  'Cancel',
                  style: TextStyle(
                    fontSize: 13,
                    fontFamily: AppFonts.poppins,
                    fontWeight: FontWeight.w500,
                    color: busy ? AppColors.almondSilk : AppColors.slateGrey,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OptionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String buttonLabel;
  final bool loading;
  final bool disabled;
  final bool isPrimary;
  final VoidCallback onTap;

  const _OptionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.buttonLabel,
    required this.loading,
    required this.disabled,
    required this.isPrimary,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isPrimary ? AppColors.lavenderBlush : AppColors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isPrimary ? AppColors.darkRaspberry.withValues(alpha: 0.2) : AppColors.almondSilk,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: AppColors.darkRaspberry),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontFamily: AppFonts.poppins,
                    fontWeight: FontWeight.w600,
                    color: AppColors.prussianBlue,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: const TextStyle(
              fontSize: 12,
              fontFamily: AppFonts.openSans,
              color: AppColors.slateGrey,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 40,
            child: isPrimary
                ? ElevatedButton(
              onPressed: disabled ? null : onTap,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.darkRaspberry,
                foregroundColor: AppColors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                textStyle: const TextStyle(
                  fontSize: 13,
                  fontFamily: AppFonts.poppins,
                  fontWeight: FontWeight.w600,
                ),
              ),
              child: loading
                  ? const SizedBox(
                width: 18, height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppColors.white),
              )
                  : Text(buttonLabel),
            )
                : OutlinedButton(
              onPressed: disabled ? null : onTap,
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.almondSilk),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                textStyle: const TextStyle(
                  fontSize: 13,
                  fontFamily: AppFonts.poppins,
                  fontWeight: FontWeight.w500,
                ),
              ),
              child: loading
                  ? const SizedBox(
                width: 18, height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppColors.prussianBlue),
              )
                  : Text(buttonLabel,
                  style: const TextStyle(color: AppColors.prussianBlue)),
            ),
          ),
        ],
      ),
    );
  }
}