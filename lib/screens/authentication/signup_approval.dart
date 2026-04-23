import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import 'phone_number_screen.dart';

class SignupApprovalScreen extends StatelessWidget {
  const SignupApprovalScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NavigoColors.backgroundLight,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 30),
              decoration: NavigoDecorations.kCardDecoration,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Check Icon
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: NavigoColors.successLight,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: NavigoColors.accentGreen,
                        width: 2,
                      ),
                    ),
                    child: const Icon(
                      Icons.check,
                      color: NavigoColors.accentGreen,
                      size: 40,
                    ),
                  ),

                  const SizedBox(height: 20),

                  Text(
                    "Request received",
                    style: NavigoTextStyles.titleMedium,
                  ),

                  const SizedBox(height: 10),

                  Text(
                    "Your account is pending approval.\nWe'll notify you once it's verified.",
                    textAlign: TextAlign.center,
                    style: NavigoTextStyles.bodySmall,
                  ),

                  const SizedBox(height: 30),

                  SizedBox(
                    width: double.infinity,
                    height: NavigoSizes.buttonHeightLarge,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const PhoneNumberScreen(),
                          ),
                        );
                      },
                      style: NavigoDecorations.kPrimaryButtonLargeStyle,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            "Back to Sign in",
                            style: NavigoTextStyles.button,
                          ),
                          const SizedBox(width: 10),
                          const Icon(Icons.arrow_forward),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
