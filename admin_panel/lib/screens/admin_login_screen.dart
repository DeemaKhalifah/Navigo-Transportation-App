import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message ?? 'Login Failed')));
    } finally {
      if (!mounted) return;
      setState(() {
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NavigoColors.backgroundLight,
      body: Center(
        child: Container(
          width: 420,
          padding: const EdgeInsets.all(32),
          decoration: NavigoDecorations.kCardDecoration.copyWith(
            color: NavigoColors.surfaceWhite,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.admin_panel_settings_rounded,
                size: 70,
                color: NavigoColors.primaryOrange,
              ),

              const SizedBox(height: 20),

              const Text(
                'Admin Login',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: NavigoColors.textDark,
                ),
              ),

              const SizedBox(height: 10),

              const Text(
                'Sign in to continue',
                style: NavigoTextStyles.bodySmall,
              ),

              const SizedBox(height: 35),

              TextField(
                controller: emailController,
                style: NavigoTextStyles.fieldText,
                decoration: NavigoDecorations.kInputDecoration.copyWith(
                  hintText: 'Email',
                  prefixIcon: const Icon(Icons.email_outlined),
                ),
              ),

              const SizedBox(height: 20),

              TextField(
                controller: passwordController,
                obscureText: obscurePassword,
                style: NavigoTextStyles.fieldText,
                decoration: NavigoDecorations.kInputDecoration.copyWith(
                  hintText: 'Password',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(
                      obscurePassword ? Icons.visibility_off : Icons.visibility,
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
                title: const Text(
                  'Remember me',
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
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text('Login', style: NavigoTextStyles.button),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
