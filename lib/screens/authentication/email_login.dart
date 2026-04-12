import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../theme/app_theme.dart';
import 'PhoneNumberScreen.dart';
import '../route_manager/RouteSchedule.dart'; // <-- your main screen

class EmailLoginScreen extends StatefulWidget {
  const EmailLoginScreen({super.key});

  @override
  State<EmailLoginScreen> createState() => _EmailLoginScreenState();
}

class _EmailLoginScreenState extends State<EmailLoginScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    String email = _emailController.text.trim();
    String password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter email and password")),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // Firebase Auth sign-in
      UserCredential userCredential = await FirebaseAuth.instance
          .signInWithEmailAndPassword(email: email, password: password);

      String uid = userCredential.user!.uid;

      // Check role in Firestore
      DocumentSnapshot userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();

      if (userDoc.exists && userDoc.get('role') == 'route_manager') {
        // Navigate to Route Manager main screen
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const RouteSchedule()),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("You are not authorized as a Route Manager"),
          ),
        );
      }
    } on FirebaseAuthException catch (e) {
      String message = "Login failed";
      if (e.code == 'user-not-found') {
        message = "No user found for this email.";
      } else if (e.code == 'wrong-password') {
        message = "Incorrect password.";
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Error: $e")));
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NavigoColors.backgroundLight,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Column(
          children: [
            // Top Bar
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
                          const Text(
                            "Route Manager Login",
                            style: NavigoTextStyles.titleLarge,
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            "Sign in using your administrator email and password.",
                            style: NavigoTextStyles.bodyMedium,
                          ),
                          const SizedBox(height: 10),

                          // Badge
                          NavigoDecorations.statusChip(
                            label: "Route Manager only",
                            color: NavigoColors.accentGreen,
                          ),
                          const SizedBox(height: 20),

                          // Email Field
                          const Text("Email", style: NavigoTextStyles.label),
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

                          // Password Field
                          const Text("Password", style: NavigoTextStyles.label),
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

                          // Sign In Button
                          SizedBox(
                            width: double.infinity,
                            height: NavigoSizes.buttonHeightLarge,
                            child: ElevatedButton(
                              style: NavigoDecorations.kPrimaryButtonLargeStyle,
                              onPressed: _isLoading ? null : _signIn,
                              child: _isLoading
                                  ? const CircularProgressIndicator(
                                      color: NavigoColors.textLight,
                                    )
                                  : Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: const [
                                        Text(
                                          "Sign In",
                                          style: NavigoTextStyles.button,
                                        ),
                                        SizedBox(width: 10),
                                        Icon(Icons.arrow_forward),
                                      ],
                                    ),
                            ),
                          ),
                          const SizedBox(height: 12),

                          // Back to user login
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
