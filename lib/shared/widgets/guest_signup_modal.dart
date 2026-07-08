// lib/shared/widgets/guest_signup_modal.dart
//
// Inline modal for converting anonymous user → real account.
// Uses linkWithCredential (email) or linkWithPopup (Google).
// Same UID preserved — zero data migration needed.

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_fonts.dart';
import 'guest_merge_picker.dart';

class GuestSignupModal extends StatefulWidget {
  const GuestSignupModal({super.key});

  /// Shows the inline signup modal. Returns true if account was linked.
  static Future<bool> show(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black54,
      builder: (_) => const GuestSignupModal(),
    );
    return result ?? false;
  }

  @override
  State<GuestSignupModal> createState() => _GuestSignupModalState();
}

class _GuestSignupModalState extends State<GuestSignupModal> {
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _loading = false;
  bool _googleLoading = false;
  String? _error;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  // ─── EMAIL LINK ────────────────────────────────────────────────────

  Future<void> _linkWithEmail() async {
    final name = _nameCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;

    // Validate
    if (name.isEmpty) {
      setState(() => _error = 'Please enter your name.');
      return;
    }
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = 'Please enter a valid email.');
      return;
    }
    if (password.length < 6) {
      setState(() => _error = 'Password must be at least 6 characters.');
      return;
    }

    setState(() { _loading = true; _error = null; });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null || !user.isAnonymous) {
        setState(() { _loading = false; _error = 'Not a guest session.'; });
        return;
      }

      final credential = EmailAuthProvider.credential(
        email: email,
        password: password,
      );
      await user.linkWithCredential(credential);
      await user.updateDisplayName(name);

      // Upgrade plan guest → free
      await _upgradeGuestPlan(name, email);

      if (mounted) Navigator.pop(context, true);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'email-already-in-use' || e.code == 'credential-already-in-use') {
        final guestUid = FirebaseAuth.instance.currentUser?.uid;
        setState(() => _loading = false);
        if (guestUid != null && mounted) {
          Navigator.pop(context, false); // close signup modal
          await GuestMergePickerModal.show(
            context,
            guestUid: guestUid,
            email: _emailCtrl.text.trim(),
            password: _passwordCtrl.text,
          );
        }
        return;
      }
      setState(() {
        _loading = false;
        _error = _mapError(e.code);
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = 'Something went wrong. Please try again.';
      });
    }
  }

  // ─── GOOGLE LINK ───────────────────────────────────────────────────

  Future<void> _linkWithGoogle() async {
    setState(() { _googleLoading = true; _error = null; });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null || !user.isAnonymous) {
        setState(() { _googleLoading = false; _error = 'Not a guest session.'; });
        return;
      }

      final googleProvider = GoogleAuthProvider()
        ..addScope('email')
        ..addScope('profile');

      await user.linkWithPopup(googleProvider);

      // Upgrade plan guest → free
      await _upgradeGuestPlan(
        user.displayName ?? '',
        user.email ?? '',
      );

      if (mounted) Navigator.pop(context, true);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'popup-closed-by-user' ||
          e.code == 'cancelled-popup-request') {
        setState(() => _googleLoading = false);
        return;
      }
      if (e.code == 'credential-already-in-use') {
        final guestUid = FirebaseAuth.instance.currentUser?.uid;
        setState(() => _googleLoading = false);
        if (guestUid != null && mounted) {
          Navigator.pop(context, false);
          await GuestMergePickerModal.show(
            context,
            guestUid: guestUid,
            email: FirebaseAuth.instance.currentUser?.email ?? '',
          );
        }
        return;
      }
      setState(() {
        _googleLoading = false;
        _error = _mapError(e.code);
      });
    } catch (e) {
      setState(() {
        _googleLoading = false;
        _error = 'Google sign-in failed. Please try again.';
      });
    }
  }

  // ─── PLAN UPGRADE ──────────────────────────────────────────────────

  Future<void> _upgradeGuestPlan(String name, String email) async {
    try {
      final callable = FirebaseFunctions
          .instanceFor(region: 'us-central1')
          .httpsCallable('upgradeGuestToFree');
      await callable.call({
        'displayName': name,
        'email': email,
      });
    } catch (e) {
      // Non-critical — plan upgrade can happen on next cycle check
      debugPrint('upgradeGuestToFree failed (non-critical): $e');
    }
  }

  // ─── ERROR MAPPING ─────────────────────────────────────────────────

  String _mapError(String code) {
    switch (code) {
      case 'email-already-in-use':
      case 'credential-already-in-use':
        return 'This email already has a KitAura account. Please sign in with that account instead.';
      case 'weak-password':
        return 'Password is too weak. Use at least 6 characters.';
      case 'invalid-email':
        return 'Please enter a valid email address.';
      case 'provider-already-linked':
        return 'This account is already linked.';
      default:
        return 'Something went wrong ($code). Please try again.';
    }
  }

  // ─── BUILD ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 420,
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
        child: SingleChildScrollView(
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
                child: const Icon(LucideIcons.userPlus,
                    size: 26, color: AppColors.darkRaspberry),
              ),
              const SizedBox(height: 18),

              const Text(
                'Create Your Account',
                style: TextStyle(
                  fontSize: 20,
                  fontFamily: AppFonts.poppins,
                  fontWeight: FontWeight.bold,
                  color: AppColors.prussianBlue,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Your documents will be saved to your new account automatically.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  fontFamily: AppFonts.openSans,
                  color: AppColors.slateGrey,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 24),

              // Google button
              SizedBox(
                width: double.infinity,
                height: 46,
                child: OutlinedButton.icon(
                  onPressed: (_loading || _googleLoading) ? null : _linkWithGoogle,
                  icon: _googleLoading
                      ? const SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppColors.prussianBlue),
                  )
                      : Image.network(
                    'https://www.gstatic.com/firebasejs/ui/2.0.0/images/auth/google.svg',
                    width: 20, height: 20,
                    errorBuilder: (_, _, _) =>
                    const Icon(LucideIcons.chrome, size: 18),
                  ),
                  label: Text(
                    _googleLoading ? 'Connecting...' : 'Continue with Google',
                    style: const TextStyle(
                      fontSize: 14,
                      fontFamily: AppFonts.poppins,
                      fontWeight: FontWeight.w500,
                      color: AppColors.prussianBlue,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.almondSilk),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Divider
              Row(
                children: [
                  const Expanded(child: Divider(color: AppColors.almondSilk)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Text(
                      'or',
                      style: TextStyle(
                        fontSize: 12,
                        fontFamily: AppFonts.openSans,
                        color: AppColors.slateGrey,
                      ),
                    ),
                  ),
                  const Expanded(child: Divider(color: AppColors.almondSilk)),
                ],
              ),
              const SizedBox(height: 16),

              // Name
              TextField(
                controller: _nameCtrl,
                enabled: !_loading && !_googleLoading,
                decoration: _inputDecoration('Full Name', LucideIcons.user),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 12),

              // Email
              TextField(
                controller: _emailCtrl,
                enabled: !_loading && !_googleLoading,
                keyboardType: TextInputType.emailAddress,
                decoration: _inputDecoration('Email', LucideIcons.mail),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 12),

              // Password
              TextField(
                controller: _passwordCtrl,
                enabled: !_loading && !_googleLoading,
                obscureText: _obscurePassword,
                decoration: _inputDecoration('Password', LucideIcons.lock).copyWith(
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword ? LucideIcons.eyeOff : LucideIcons.eye,
                      size: 16,
                      color: AppColors.slateGrey,
                    ),
                    onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _linkWithEmail(),
              ),
              const SizedBox(height: 20),

              // Error
              if (_error != null) ...[
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
                const SizedBox(height: 16),
              ],

              // Submit
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: (_loading || _googleLoading) ? null : _linkWithEmail,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.darkRaspberry,
                    foregroundColor: AppColors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 15,
                      fontFamily: AppFonts.poppins,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  child: _loading
                      ? const SizedBox(
                    width: 20, height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppColors.white),
                  )
                      : const Text('Create Account'),
                ),
              ),
              const SizedBox(height: 14),

              // Cancel
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () => Navigator.pop(context, false),
                  child: const Text(
                    'Maybe later',
                    style: TextStyle(
                      fontSize: 13,
                      fontFamily: AppFonts.poppins,
                      fontWeight: FontWeight.w500,
                      color: AppColors.slateGrey,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String hint, IconData icon) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(
        fontSize: 13,
        color: AppColors.slateGrey,
        fontFamily: AppFonts.openSans,
      ),
      prefixIcon: Icon(icon, size: 16, color: AppColors.slateGrey),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.almondSilk),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.almondSilk),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.darkRaspberry),
      ),
    );
  }
}