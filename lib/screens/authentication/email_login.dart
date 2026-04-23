import 'package:flutter/material.dart';

import 'package:navigo/controllers/app_controller_scope.dart';
import '../../theme/app_theme.dart';
import 'PhoneNumberScreen.dart';
import '../route_manager/RouteSchedule.dart';

class EmailLoginScreen extends StatefulWidget {
  const EmailLoginScreen({super.key});

  @override
  State<EmailLoginScreen> createState() => _EmailLoginScreenState();
}

class _EmailLoginScreenState extends State<EmailLoginScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    final auth = AppControllerScope.of(context).authController;
    String email = _emailController.text.trim();
    String password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter email and password")),
      );
      return;
    }

    final role = await auth.signInWithEmail(email, password);
    if (!mounted) return;

    if (role == 'route_manager') {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const RouteSchedule()),
      );
      return;
    }

    if (role == null) {
      final code = auth.errorCode;
      String message = "Login failed";
      if (code == 'user-not-found') {
        message = "No user found for this email.";
      } else if (code == 'wrong-password' ||
          code == 'invalid-credential' ||
          code == 'INVALID_LOGIN_CREDENTIALS') {
        message = "Incorrect password.";
      } else if (auth.error != null && auth.error!.isNotEmpty) {
        message = auth.error!;
      }
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
      return;
    }

    // Signed in, but not a route manager.
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("You are not authorized as a Route Manager")),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = AppControllerScope.of(context).authController;

    return Scaffold(
      backgroundColor: NavigoColors.backgroundLight,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Column(
          children: [
            NavigoDecorations.topBar(onBack: () => Navigator.pop(context)),

            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 450),
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: NavigoDecorations.kCardDecoration,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            "Route Manager Login",
                            style: NavigoTextStyles.titleLarge,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            "Sign in using your administrator email and password.",
                            style: NavigoTextStyles.bodyMedium,
                          ),
                          const SizedBox(height: 10),

                          NavigoDecorations.statusChip(
                            label: "Route Manager only",
                            color: NavigoColors.accentGreen,
                          ),
                          const SizedBox(height: 20),

                          Text("Email", style: NavigoTextStyles.label),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _emailController,
                            style: NavigoTextStyles.fieldText,
                            decoration: NavigoDecorations.kInputDecoration
                                .copyWith(
                                  hintText: "RouteManager@navigo.com",
                                  prefixIcon: const Icon(
                                    Icons.email_outlined,
                                    color: NavigoColors.accentGreen,
                                  ),
                                  suffixIcon: IconButton(
                                    icon: const Icon(Icons.clear),
                                    onPressed: () => _emailController.clear(),
                                  ),
                                ),
                          ),
                          const SizedBox(height: 16),

                          Text("Password", style: NavigoTextStyles.label),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _passwordController,
                            obscureText: _obscurePassword,
                            style: NavigoTextStyles.fieldText,
                            decoration: NavigoDecorations.kInputDecoration
                                .copyWith(
                                  prefixIcon: const Icon(
                                    Icons.lock_outline,
                                    color: NavigoColors.accentGreen,
                                  ),
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                      _obscurePassword
                                          ? Icons.visibility_off
                                          : Icons.visibility,
                                    ),
                                    onPressed: () {
                                      setState(() {
                                        _obscurePassword = !_obscurePassword;
                                      });
                                    },
                                  ),
                                ),
                          ),
                          const SizedBox(height: 25),

                          SizedBox(
                            width: double.infinity,
                            height: NavigoSizes.buttonHeightLarge,
                            child: ElevatedButton(
                              style: NavigoDecorations.kPrimaryButtonLargeStyle,
                              onPressed: auth.isLoading ? null : _signIn,
                              child: auth.isLoading
                                  ? const CircularProgressIndicator(
                                      color: NavigoColors.textLight,
                                    )
                                  : Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Text(
                                          "Sign In",
                                          style: NavigoTextStyles.button,
                                        ),
                                        const SizedBox(width: 10),
                                        const Icon(Icons.arrow_forward),
                                      ],
                                    ),
                            ),
                          ),
                          const SizedBox(height: 12),

                          Center(
                            child: TextButton(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        const PhoneNumberScreen(),
                                  ),
                                );
                              },
                              child: Text(
                                "Back to user login",
                                style: NavigoTextStyles.actionLink,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
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
