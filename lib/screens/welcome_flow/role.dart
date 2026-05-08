import 'package:flutter/material.dart';

import '../../localization/localization_x.dart';
import '../../theme/app_theme.dart';
import '../../widgets/responsive.dart';
import '../authentication/driver_signup.dart';
import '../authentication/passenger_sign_up.dart';
import '../authentication/phone_number_screen.dart';

class RoleSelectionScreen extends StatelessWidget {
  const RoleSelectionScreen({super.key});

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
    final iconSize = Responsive.isLandscape(context) ? 36.0 : 40.0;

    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: () => _onRoleSelected(context, role),
        style: NavigoDecorations.kRoleButtonStyle,
        child: Row(
          children: [
            SizedBox.square(
              // Role icons shrink slightly in landscape so long translated text
              // has enough horizontal room without overflowing.
              dimension: iconSize,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: NavigoColors.surfaceWhite,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: NavigoColors.accentGreen, size: 24),
              ),
            ),
            SizedBox(width: Responsive.verticalGap(context, 14)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: NavigoTextStyles.titleSmall),
                  SizedBox(height: Responsive.verticalGap(context, 4)),
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
    final padding = Responsive.horizontalPadding(context);

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              // The whole role card scrolls in landscape and on compact phones,
              // preventing clipped buttons when text scales up.
              padding: EdgeInsets.symmetric(
                horizontal: padding,
                vertical: Responsive.verticalGap(context, 24),
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Center(
                  child: ConstrainedBox(
                    constraints: Responsive.contentMaxWidth(context),
                    child: Container(
                      decoration: NavigoDecorations.kLightCardDecoration,
                      padding: EdgeInsets.symmetric(
                        vertical: Responsive.verticalGap(context, 28),
                        horizontal: padding.clamp(16, 28),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            context.texts.t('createYourAccount'),
                            textAlign: TextAlign.center,
                            style: NavigoTextStyles.titleLarge,
                          ),
                          SizedBox(height: Responsive.verticalGap(context, 10)),
                          Text(
                            context.texts.t('chooseRoleContinue'),
                            textAlign: TextAlign.center,
                            style: NavigoTextStyles.bodySmall,
                          ),
                          SizedBox(height: Responsive.verticalGap(context, 22)),
                          _buildRoleButton(
                            context,
                            context.texts.t('passengerRole'),
                            context.texts.t('passengerRoleDescription'),
                            Icons.person_outline,
                            'passenger',
                          ),
                          SizedBox(height: Responsive.verticalGap(context, 14)),
                          _buildRoleButton(
                            context,
                            context.texts.t('driverRole'),
                            context.texts.t('driverRoleDescription'),
                            Icons.drive_eta,
                            'driver',
                          ),
                          SizedBox(height: Responsive.verticalGap(context, 22)),
                          Text(
                            context.texts.t('alreadyHaveAccount'),
                            textAlign: TextAlign.center,
                            style: NavigoTextStyles.bodySmall,
                          ),
                          TextButton(
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
            );
          },
        ),
      ),
    );
  }
}
