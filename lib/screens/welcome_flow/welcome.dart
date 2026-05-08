import 'package:flutter/material.dart';

import '../../localization/localization_x.dart';
import '../../theme/app_theme.dart';
import '../../widgets/language_toggle_switch.dart';
import '../../widgets/responsive.dart';
import '../authentication/phone_number_screen.dart';
import 'role.dart';

class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final padding = Responsive.horizontalPadding(context);

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Stack(
              children: [
                SingleChildScrollView(
                  // The scroll view prevents RenderFlex overflow when the
                  // device rotates to landscape or runs on a very small phone.
                  padding: EdgeInsets.symmetric(horizontal: padding),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: Responsive.contentMaxWidth(context),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              height: Responsive.verticalGap(
                                context,
                                isLandscape ? 54 : 70,
                              ),
                            ),
                            _buildIllustrationSection(context),
                            _buildContentSection(context),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                PositionedDirectional(
                  top: Responsive.verticalGap(context, 12),
                  start: _isArabic(context) ? null : padding,
                  end: _isArabic(context) ? padding : null,
                  // The switch stays above the image and uses directional
                  // positioning so it moves with English/LTR and Arabic/RTL.
                  child: const LanguageToggleSwitch(),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  bool _isArabic(BuildContext context) {
    return Directionality.of(context) == TextDirection.rtl;
  }

  Widget _buildIllustrationSection(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: Responsive.verticalGap(context, 18)),
      child: Image.asset(
        'assets/images/welcome.png',
        width: MediaQuery.sizeOf(context).width * 0.8,
        height: Responsive.onboardingImageHeight(context),
        // The image now uses the available screen size instead of a fixed
        // 400px height, so rotation and tablets resize it naturally.
        fit: BoxFit.contain,
      ),
    );
  }

  Widget _buildContentSection(BuildContext context) {
    return Column(
      children: [
        Text(
          context.texts.t('welcomeSubtitle'),
          textAlign: TextAlign.center,
          style: NavigoTextStyles.bodySmall.copyWith(height: 1.4),
        ),
        SizedBox(height: Responsive.verticalGap(context, 24)),
        SizedBox(
          width: double.infinity,
          height: Responsive.buttonHeight(context),
          child: ElevatedButton(
            style: NavigoDecorations.kPrimaryButtonLargeStyle,
            onPressed: () => _onGetStartedPressed(context),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(child: Text(context.texts.t('getStarted'))),
                SizedBox(width: Responsive.verticalGap(context, 10)),
                const Icon(Icons.arrow_forward),
              ],
            ),
          ),
        ),
        SizedBox(height: Responsive.verticalGap(context, 14)),
        TextButton(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => PhoneNumberScreen()),
            );
          },
          child: Text(
            context.texts.t('signIn'),
            style: NavigoTextStyles.actionLink,
          ),
        ),
        SizedBox(height: Responsive.verticalGap(context, 16)),
      ],
    );
  }

  void _onGetStartedPressed(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => const RoleSelectionScreen()),
    );
  }
}
