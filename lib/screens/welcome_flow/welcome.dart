import 'package:flutter/material.dart';
import '../../localization/localization_x.dart';
import '../../theme/app_theme.dart';
import '../../widgets/language_toggle_switch.dart';
import 'role.dart';
import '../authentication/phone_number_screen.dart';

class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildIllustrationSection(),
                    _buildContentSection(context),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIllustrationSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.only(bottom: 20.0),
      child: Column(
        children: [
          Image.asset(
            'assets/images/welcome.png',
            width: double.infinity,
            height: 400,
            fit: BoxFit.contain,
          ),
        ],
      ),
    );
  }

  Widget _buildContentSection(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 30.0),
      child: Column(
        children: [
          const Align(
            alignment: Alignment.centerRight,
            child: LanguageToggleSwitch(),
          ),
          const SizedBox(height: 8),
          Text(
            context.texts.t('welcomeSubtitle'),
            textAlign: TextAlign.center,
            style: NavigoTextStyles.bodySmall.copyWith(height: 1.4),
          ),

          const SizedBox(height: 28),

          /// Get Started Button
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              style: NavigoDecorations.kPrimaryButtonLargeStyle,
              onPressed: () => _onGetStartedPressed(context),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(context.texts.t('getStarted')),
                  const SizedBox(width: 12),
                  const Icon(Icons.arrow_forward),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          /// Sign In Button
          TextButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => PhoneNumberScreen()),
              );
            },
            child: Text(context.texts.t('signIn'), style: NavigoTextStyles.actionLink),
          ),

          const SizedBox(height: 8),

          const SizedBox(height: 12),
        ],
      ),
    );
  }

  void _onGetStartedPressed(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => const RoleSelectionScreen()),
    );
  }
}
