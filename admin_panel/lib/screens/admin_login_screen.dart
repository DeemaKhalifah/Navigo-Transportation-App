import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../localization/localization_x.dart';
import '../theme/app_theme.dart';
import '../widgets/language_toggle.dart';
import 'admin_dashboard_screen.dart';

class AdminLoginScreen extends StatefulWidget {
  const AdminLoginScreen({super.key});

  @override
  State<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends State<AdminLoginScreen> {
  static const String _rememberEmailKey = 'admin_remember_email';
  static const String _rememberEnabledKey = 'admin_remember_enabled';

  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  bool isLoading = false;
  bool obscurePassword = true;
  bool rememberMe = false;

  @override
  void initState() {
    super.initState();
    _loadRememberedAdmin();
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  Future<void> _loadRememberedAdmin() async {
    final prefs = await SharedPreferences.getInstance();
    final shouldRemember = prefs.getBool(_rememberEnabledKey) ?? false;
    final rememberedEmail = prefs.getString(_rememberEmailKey) ?? '';

    if (!mounted) return;
    setState(() {
      rememberMe = shouldRemember;
      if (shouldRemember) {
        emailController.text = rememberedEmail;
      }
    });
  }

  Future<void> _saveRememberedAdmin() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_rememberEnabledKey, rememberMe);

    if (rememberMe) {
      await prefs.setString(_rememberEmailKey, emailController.text.trim());
    } else {
      await prefs.remove(_rememberEmailKey);
    }
  }

  Future<void> loginAdmin() async {
    try {
      setState(() {
        isLoading = true;
      });

      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: emailController.text.trim(),
        password: passwordController.text.trim(),
      );

      await _saveRememberedAdmin();

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const AdminDashboardScreen()),
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message ?? context.texts.t('loginFailed'))),
      );
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final texts = context.texts;

    return Scaffold(
      backgroundColor: NavigoColors.backgroundLight,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Center(
                  child: Container(
                    width: 420,
                    padding: const EdgeInsets.all(32),
                    decoration: NavigoDecorations.kCardDecoration.copyWith(
                      color: NavigoColors.surfaceWhite,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Align(
                          alignment: AlignmentDirectional.centerEnd,
                          child: LanguageToggle(),
                        ),
                        const SizedBox(height: 18),
                        const Icon(
                          Icons.admin_panel_settings_rounded,
                          size: 70,
                          color: NavigoColors.primaryOrange,
                        ),
                        const SizedBox(height: 20),
                        Text(
                          texts.t('adminLogin'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: NavigoColors.textDark,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          texts.t('signInToContinue'),
                          textAlign: TextAlign.center,
                          style: NavigoTextStyles.bodySmall,
                        ),
                        const SizedBox(height: 35),
                        TextField(
                          controller: emailController,
                          style: NavigoTextStyles.fieldText,
                          decoration: NavigoDecorations.kInputDecoration
                              .copyWith(
                                hintText: texts.t('email'),
                                prefixIcon: const Icon(Icons.email_outlined),
                              ),
                        ),
                        const SizedBox(height: 20),
                        TextField(
                          controller: passwordController,
                          obscureText: obscurePassword,
                          style: NavigoTextStyles.fieldText,
                          decoration: NavigoDecorations.kInputDecoration
                              .copyWith(
                                hintText: texts.t('password'),
                                prefixIcon: const Icon(Icons.lock_outline),
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    obscurePassword
                                        ? Icons.visibility_off
                                        : Icons.visibility,
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      obscurePassword = !obscurePassword;
                                    });
                                  },
                                ),
                              ),
                        ),
                        const SizedBox(height: 16),
                        CheckboxListTile(
                          value: rememberMe,
                          onChanged: isLoading
                              ? null
                              : (value) {
                                  setState(() {
                                    rememberMe = value ?? false;
                                  });
                                },
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.leading,
                          activeColor: NavigoColors.primaryOrange,
                          title: Text(
                            texts.t('rememberMe'),
                            style: NavigoTextStyles.bodyMedium,
                          ),
                        ),
                        const SizedBox(height: 18),
                        SizedBox(
                          width: double.infinity,
                          height: 55,
                          child: ElevatedButton(
                            onPressed: isLoading ? null : loginAdmin,
                            style: NavigoDecorations.kPrimaryButtonStyle,
                            child: isLoading
                                ? const CircularProgressIndicator(
                                    color: Colors.white,
                                  )
                                : Text(
                                    texts.t('login'),
                                    style: NavigoTextStyles.button,
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
