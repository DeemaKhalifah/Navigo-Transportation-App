import 'dart:math' as math;

import 'package:flutter/material.dart';

class Responsive {
  const Responsive._();

  static Size size(BuildContext context) => MediaQuery.sizeOf(context);

  static bool isLandscape(BuildContext context) {
    return MediaQuery.of(context).orientation == Orientation.landscape;
  }

  static bool isTablet(BuildContext context) {
    return size(context).shortestSide >= 600;
  }

  static double horizontalPadding(BuildContext context) {
    final width = size(context).width;
    // Scale page gutters by screen width, with caps so small phones do not
    // overflow and tablets do not look stretched.
    return width.clamp(320, 900) * 0.055;
  }

  static double verticalGap(BuildContext context, double base) {
    final height = size(context).height;
    final factor = height < 650 ? 0.7 : (isTablet(context) ? 1.15 : 1.0);
    // Replace large fixed spaces with proportional spacing that shrinks in
    // landscape/small devices and grows gently on tablets.
    return math.max(4, base * factor);
  }

  static double buttonHeight(BuildContext context) {
    // Buttons stay tappable on phones while avoiding oversized controls on
    // landscape screens where vertical space is scarce.
    return isLandscape(context) ? 48 : 52;
  }

  static double onboardingImageHeight(BuildContext context) {
    final s = size(context);
    final fraction = isLandscape(context) ? 0.40 : 0.46;
    // Images are sized from available height and capped from width, preventing
    // the onboarding art from clipping on small phones or taking over tablets.
    return math.min(s.height * fraction, s.width * 0.95).clamp(180, 420);
  }

  static BoxConstraints contentMaxWidth(BuildContext context) {
    // Forms/cards use the full phone width but remain readable on tablets.
    return BoxConstraints(maxWidth: isTablet(context) ? 560 : 450);
  }
}
