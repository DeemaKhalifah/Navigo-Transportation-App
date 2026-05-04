import 'package:flutter/material.dart';
import '../../localization/localization_x.dart';
import '../../theme/app_theme.dart';
import '../authentication/phone_number_screen.dart';

// Import signup screens
import '../authentication/passenger_sign_up.dart';
import '../authentication/driver_signup.dart';

class RoleSelectionScreen extends StatelessWidget {
  const RoleSelectionScreen({super.key});

  // Handle role selection + navigation
  void _onRoleSelected(BuildContext context, String role) {
    if (role == 'passenger') {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const PassengerSignupScreen()),
      );
    } else if (role == 'driver') {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const DriverSignupScreen()),
      );
    }
  }

  Widget _buildRoleButton(
    BuildContext context,
    String title,
    String description,
    IconData icon,
    String role,
  ) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: () => _onRoleSelected(context, role),
        style: NavigoDecorations.kRoleButtonStyle,
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: NavigoColors.surfaceWhite,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: NavigoColors.accentGreen, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: NavigoTextStyles.titleSmall),
                  const SizedBox(height: 4),
                  Text(description, style: NavigoTextStyles.bodyMedium),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Container(
              decoration: NavigoDecorations.kLightCardDecoration,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 30,
                  horizontal: 20,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      context.texts.t('createYourAccount'),
                      style: NavigoTextStyles.titleLarge,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      context.texts.t('chooseRoleContinue'),
                      textAlign: TextAlign.center,
                      style: NavigoTextStyles.bodySmall,
                    ),
                    const SizedBox(height: 24),

                    // Passenger
                    _buildRoleButton(
                      context,
                      context.texts.t('passengerRole'),
                      context.texts.t('passengerRoleDescription'),
                      Icons.person_outline,
                      'passenger',
                    ),

                    const SizedBox(height: 16),

                    // Driver
                    _buildRoleButton(
                      context,
                      context.texts.t('driverRole'),
                      context.texts.t('driverRoleDescription'),
                      Icons.drive_eta,
                      'driver',
                    ),

                    const SizedBox(height: 24),

                    Text(
                      context.texts.t('alreadyHaveAccount'),
                      style: NavigoTextStyles.bodySmall,
                    ),

                    TextButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const PhoneNumberScreen(),
                          ),
                        );
                      },
                      child: Text(
                        context.texts.t('signIn'),
                        style: NavigoTextStyles.actionLink,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
