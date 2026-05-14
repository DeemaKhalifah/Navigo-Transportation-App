import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../localization/localization_x.dart';
import '../theme/app_theme.dart';

Future<void> showAdminAccountDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const _AdminAccountDialog(),
  );
}

class _AdminAccountDialog extends StatefulWidget {
  const _AdminAccountDialog();

  @override
  State<_AdminAccountDialog> createState() => _AdminAccountDialogState();
}

class _AdminAccountDialogState extends State<_AdminAccountDialog> {
  final TextEditingController _currentPasswordController =
      TextEditingController();
  final TextEditingController _newPasswordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _changePassword() async {
    final user = FirebaseAuth.instance.currentUser;
    final email = user?.email ?? '';
    final currentPassword = _currentPasswordController.text.trim();
    final newPassword = _newPasswordController.text.trim();
    final confirmPassword = _confirmPasswordController.text.trim();

    setState(() => _errorMessage = null);

    if (user == null || email.isEmpty) {
      setState(() => _errorMessage = context.texts.t('noLoggedInAdmin'));
      return;
    }

    if (currentPassword.isEmpty ||
        newPassword.isEmpty ||
        confirmPassword.isEmpty) {
      setState(() => _errorMessage = context.texts.t('fillAllPasswordFields'));
      return;
    }

    if (newPassword.length < 6) {
      setState(() => _errorMessage = context.texts.t('passwordMinLength'));
      return;
    }

    if (newPassword != confirmPassword) {
      setState(() => _errorMessage = context.texts.t('passwordsDoNotMatch'));
      return;
    }

    try {
      setState(() => _isLoading = true);

      final credential = EmailAuthProvider.credential(
        email: email,
        password: currentPassword,
      );

      await user.reauthenticateWithCredential(credential);
      await user.updatePassword(newPassword);

      if (!mounted) return;

      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context);
      messenger.showSnackBar(
        SnackBar(content: Text(context.texts.t('passwordChangedSuccessfully'))),
      );
    } on FirebaseAuthException catch (e) {
      setState(() {
        _errorMessage = _firebaseMessage(e);
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  String _firebaseMessage(FirebaseAuthException e) {
    if (e.code == 'wrong-password' || e.code == 'invalid-credential') {
      return context.texts.t('currentPasswordIncorrect');
    }
    if (e.code == 'weak-password') {
      return context.texts.t('newPasswordWeak');
    }
    if (e.code == 'requires-recent-login') {
      return context.texts.t('loginAgainChangePassword');
    }

    return e.message ?? e.code;
  }

  @override
  Widget build(BuildContext context) {
    final email = FirebaseAuth.instance.currentUser?.email ?? 'No email';
    final texts = context.texts;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 48, vertical: 40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const CircleAvatar(
                    radius: 24,
                    backgroundColor: NavigoColors.primaryOrange,
                    child: Icon(
                      Icons.admin_panel_settings,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      texts.t('adminAccount'),
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _isLoading ? null : () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                    tooltip: texts.t('close'),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              TextFormField(
                readOnly: true,
                initialValue: email,
                decoration: NavigoDecorations.kInputDecoration.copyWith(
                  labelText: texts.t('email'),
                  prefixIcon: const Icon(Icons.email_rounded),
                  fillColor: NavigoColors.backgroundAlt,
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _currentPasswordController,
                obscureText: true,
                decoration: NavigoDecorations.kInputDecoration.copyWith(
                  labelText: texts.t('currentPassword'),
                  prefixIcon: const Icon(Icons.lock_outline_rounded),
                  fillColor: Colors.white,
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _newPasswordController,
                obscureText: true,
                decoration: NavigoDecorations.kInputDecoration.copyWith(
                  labelText: texts.t('newPassword'),
                  prefixIcon: const Icon(Icons.lock_reset_rounded),
                  fillColor: Colors.white,
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _confirmPasswordController,
                obscureText: true,
                decoration: NavigoDecorations.kInputDecoration.copyWith(
                  labelText: texts.t('confirmNewPassword'),
                  prefixIcon: const Icon(Icons.verified_user_rounded),
                  fillColor: Colors.white,
                ),
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 14),
                Text(
                  _errorMessage!,
                  style: const TextStyle(
                    color: NavigoColors.accentRed,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _isLoading ? null : () => Navigator.pop(context),
                    child: Text(texts.t('cancel')),
                  ),
                  const SizedBox(width: 10),
                  FilledButton(
                    onPressed: _isLoading ? null : _changePassword,
                    style: FilledButton.styleFrom(
                      backgroundColor: NavigoColors.primaryOrange,
                      foregroundColor: Colors.white,
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(texts.t('changePasswordButton')),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
