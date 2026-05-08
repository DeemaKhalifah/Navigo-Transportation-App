import 'package:flutter/material.dart';
import 'package:navigo/screens/notifications_screen.dart';

class NavigoColors {
  static const Color primaryOrange = Color(0xFFFF9800);
  static const Color primaryAmber = Color(0xFFF59E0B);
  static const Color backgroundLight = Color(0xFFF5F5F5);
  static const Color backgroundAlt = Color(0xFFF9F8F4);
  static const Color cardLight = Color(0xFFFAFAFA);
  static const Color inputFill = Color(0xFFF7F7F7);
  static const Color surfaceWhite = Colors.white;
  static const Color textLight = Colors.white;
  static const Color transparent = Colors.transparent;
  static const Color textDark = Color(0xFF1F2937);
  static const Color textGray = Colors.black54;
  static const Color textMuted = Color(0xFF757575);
  static const Color shadowColor = Colors.black12;
  static const Color accentGreen = Colors.green;
  static const Color accentBlue = Color(0xFF2196F3);
  static const Color accentRed = Color(0xFFE53935);
  static const Color borderLight = Color(0xFFE0E0E0);
  static const Color successLight = Color(0xFFE8F5E9);
  static const Color lightorange = Color.fromARGB(255, 247, 241, 234);
}

class NavigoTextStyles {
  static const TextStyle titleLarge = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.bold,
    color: NavigoColors.textDark,
  );
  static const TextStyle titleMedium = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.bold,
    color: NavigoColors.textDark,
  );
  static const TextStyle titleSmall = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.bold,
    color: NavigoColors.textDark,
  );
  static const TextStyle label = TextStyle(
    fontSize: 13,
    color: NavigoColors.textGray,
  );
  static const TextStyle bodySmall = TextStyle(
    fontSize: 14,
    color: NavigoColors.textMuted,
  );
  static const TextStyle bodyMedium = TextStyle(
    fontSize: 14,
    color: NavigoColors.textGray,
  );
  static const TextStyle button = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.bold,
    color: NavigoColors.textLight,
  );
  static const TextStyle buttonOrangeLink = TextStyle(
    fontSize: 16,
    color: NavigoColors.primaryOrange,
    fontWeight: FontWeight.w700,
    fontStyle: FontStyle.italic,
  );
  static const TextStyle actionLink = TextStyle(
    fontSize: 14,
    color: NavigoColors.accentGreen,
    fontWeight: FontWeight.w700,
  );
  static const TextStyle chip = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w600,
  );
  static const TextStyle status = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w700,
  );
  static const TextStyle fieldText = TextStyle(
    fontSize: 16,
    color: NavigoColors.textDark,
  );
}

class NavigoSizes {
  static const double screenPadding = 16;
  static const double cardPadding = 16;
  static const double sectionGap = 20;
  static const double itemGap = 12;
  static const double cardRadius = 20;
  static const double buttonHeight = 52;
  static const double buttonHeightLarge = 55;
  static const double chipRadius = 20;
  static const double inputRadius = 12;
  static const double bottomSheetRadius = 28;
}

class NavigoDecorations {
  static Widget topBar({
    required VoidCallback onBack,
    VoidCallback? onNotification,
    BuildContext? context, // ← add this
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          /// BACK BUTTON
          Container(
            decoration: kTopBarBackButton,
            child: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new, size: 20),
              onPressed: onBack,
            ),
          ),

          /// RIGHT SIDE — notification + logo
          Row(
            children: [
              Container(
                decoration: kTopBarBackButton,
                child: IconButton(
                  icon: const Icon(Icons.notifications_none, size: 20),
                  onPressed:
                      onNotification ??
                      (context != null
                          ? () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const NotificationsScreen(),
                              ),
                            )
                          : () {}),
                ),
              ),
              const SizedBox(width: 8),
              CircleAvatar(
                radius: 30,
                backgroundColor: NavigoColors.surfaceWhite,
                child: Padding(
                  padding: const EdgeInsets.all(3),
                  child: ClipOval(
                    child: Image.asset(
                      'assets/images/logo.png',
                      fit: BoxFit.contain,
                      width: 40,
                      height: 40,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static Widget topBar1({
    required VoidCallback onBack,
    VoidCallback? onNotification,
    BuildContext? context, // ← add this
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          /// BACK BUTTON
          Container(
            decoration: kTopBarBackButton,
            child: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new, size: 20),
              onPressed: onBack,
            ),
          ),

          /// RIGHT SIDE — notification + logo
          Row(
            children: [
              Container(decoration: kTopBarBackButton),
              const SizedBox(width: 8),
              CircleAvatar(
                radius: 30,
                backgroundColor: NavigoColors.surfaceWhite,
                child: Padding(
                  padding: const EdgeInsets.all(3),
                  child: ClipOval(
                    child: Image.asset(
                      'assets/images/logo.png',
                      fit: BoxFit.contain,
                      width: 40,
                      height: 40,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static Widget topBar3({
    required VoidCallback onBack,
    VoidCallback? onNotification,
    BuildContext? context, // ← add this
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          /// BACK BUTTON
          Container(
            decoration: kTopBarBackButton,
            child: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new, size: 20),
              onPressed: onBack,
            ),
          ),

          /// RIGHT SIDE — notification + logo
          Row(
            children: [
              Container(
                decoration: kTopBarBackButton,
                child: IconButton(
                  icon: const Icon(Icons.edit, size: 20),
                  onPressed:
                      onNotification ??
                      (context != null
                          ? () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const NotificationsScreen(),
                              ),
                            )
                          : () {}),
                ),
              ),
              const SizedBox(width: 8),
              CircleAvatar(
                radius: 30,
                backgroundColor: NavigoColors.surfaceWhite,
                child: Padding(
                  padding: const EdgeInsets.all(3),
                  child: ClipOval(
                    child: Image.asset(
                      'assets/images/logo.png',
                      fit: BoxFit.contain,
                      width: 40,
                      height: 40,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static final BoxDecoration kCardDecoration = BoxDecoration(
    color: NavigoColors.lightorange,
    borderRadius: const BorderRadius.all(Radius.circular(20)),
    border: Border.all(color: NavigoColors.primaryOrange, width: 1.2),
    boxShadow: [
      BoxShadow(
        color: NavigoColors.shadowColor.withOpacity(0.1),
        offset: const Offset(0, 2),
        blurRadius: 10,
        spreadRadius: 2,
      ),
    ],
  );

  static final BoxDecoration kLightCardDecoration = BoxDecoration(
    color: NavigoColors.lightorange,
    borderRadius: const BorderRadius.all(Radius.circular(20)),
    border: Border.all(color: NavigoColors.primaryOrange, width: 1.2),
    boxShadow: [
      BoxShadow(
        color: NavigoColors.shadowColor.withOpacity(0.1),
        offset: const Offset(0, 2),
        blurRadius: 10,
        spreadRadius: 2,
      ),
    ],
  );

  static BoxDecoration kTopBarBackButton = BoxDecoration(
    shape: BoxShape.circle,
    border: const Border.fromBorderSide(
      BorderSide(color: NavigoColors.borderLight),
    ),
  );

  static final BoxDecoration kBottomSheetDecoration = BoxDecoration(
    color: NavigoColors.surfaceWhite,
    borderRadius: const BorderRadius.vertical(
      top: Radius.circular(NavigoSizes.bottomSheetRadius),
    ),
  );

  static final BoxDecoration kBottomNavDecoration = BoxDecoration(
    color: NavigoColors.surfaceWhite,
    boxShadow: [
      BoxShadow(
        color: NavigoColors.shadowColor.withOpacity(0.2),
        blurRadius: 10,
      ),
    ],
  );

  static InputDecoration kInputDecoration = InputDecoration(
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    filled: true,
    fillColor: NavigoColors.inputFill,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(12)),
      borderSide: BorderSide.none,
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(12)),
      borderSide: BorderSide.none,
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(12)),
      borderSide: BorderSide(color: NavigoColors.primaryOrange, width: 2),
    ),
  );

  static ButtonStyle kPrimaryButtonStyle = ElevatedButton.styleFrom(
    backgroundColor: NavigoColors.primaryOrange,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(12)),
    ),
    padding: const EdgeInsets.symmetric(vertical: 15),
    elevation: 0,
  );

  static ButtonStyle kPrimaryButtonLargeStyle = ElevatedButton.styleFrom(
    backgroundColor: NavigoColors.primaryOrange,
    foregroundColor: NavigoColors.textLight,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(30)),
    ),
    elevation: 0,
  );

  static ButtonStyle kAmberButtonStyle = ElevatedButton.styleFrom(
    backgroundColor: NavigoColors.primaryAmber,
    foregroundColor: NavigoColors.textLight,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(16)),
    ),
  );

  static ButtonStyle kRoleButtonStyle = OutlinedButton.styleFrom(
    side: BorderSide(color: NavigoColors.primaryOrange, width: 2),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(16)),
    ),
    backgroundColor: NavigoColors.surfaceWhite,
    padding: EdgeInsets.symmetric(vertical: 18, horizontal: 16),
  );

  static BoxDecoration selectorDecoration({required bool selected}) {
    return BoxDecoration(
      color: selected ? NavigoColors.primaryOrange : NavigoColors.surfaceWhite,
      borderRadius: BorderRadius.circular(NavigoSizes.chipRadius),
      border: Border.all(color: NavigoColors.primaryOrange, width: 1.5),
    );
  }

  static BoxDecoration statusDecoration(Color color) {
    return BoxDecoration(
      color: color.withOpacity(0.12),
      borderRadius: BorderRadius.circular(NavigoSizes.chipRadius),
    );
  }

  static BoxDecoration iconCircleDecoration(Color color) {
    return BoxDecoration(
      color: color.withOpacity(0.12),
      shape: BoxShape.circle,
    );
  }

  static BoxDecoration surfaceDecoration({
    double radius = NavigoSizes.inputRadius,
    Color color = NavigoColors.surfaceWhite,
    bool bordered = true,
  }) {
    return BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(radius),
      border: bordered ? Border.all(color: NavigoColors.borderLight) : null,
    );
  }

  static ButtonStyle coloredButton(Color color) {
    return NavigoDecorations.kPrimaryButtonLargeStyle.copyWith(
      backgroundColor: WidgetStatePropertyAll(color),
    );
  }

  static Widget dragHandle() {
    return Container(
      width: 40,
      height: 5,
      decoration: BoxDecoration(
        color: NavigoColors.borderLight,
        borderRadius: BorderRadius.circular(10),
      ),
    );
  }

  static Widget pageTitle({
    required String title,
    String? subtitle,
    Widget? trailing,
    EdgeInsetsGeometry padding = const EdgeInsets.symmetric(horizontal: 20),
  }) {
    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: subtitle == null
            ? CrossAxisAlignment.center
            : CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: NavigoTextStyles.titleLarge),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(subtitle, style: NavigoTextStyles.bodySmall),
                ],
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }

  static Widget homeStyleTitleBar({
    required String title,
    required String subtitle,
    required Widget avatar,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: NavigoTextStyles.titleLarge),
            Text(subtitle, style: NavigoTextStyles.bodySmall),
          ],
        ),
        avatar,
      ],
    );
  }

  static Widget selectorChip({
    required String label,
    required bool selected,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: selectorDecoration(selected: selected),
        child: Text(
          label,
          style: NavigoTextStyles.chip.copyWith(
            color: selected
                ? NavigoColors.textLight
                : NavigoColors.primaryOrange,
          ),
        ),
      ),
    );
  }

  static Widget statusChip({
    required String label,
    required Color color,
    EdgeInsetsGeometry padding = const EdgeInsets.symmetric(
      horizontal: 12,
      vertical: 5,
    ),
  }) {
    return Container(
      padding: padding,
      decoration: statusDecoration(color),
      child: Text(label, style: NavigoTextStyles.status.copyWith(color: color)),
    );
  }

  static Widget navItem({
    required IconData icon,
    required String label,
    required bool isActive,
    Widget? iconWidget,
  }) {
    final color = isActive ? NavigoColors.accentGreen : NavigoColors.textMuted;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconTheme(
          data: IconThemeData(color: color),
          child: iconWidget ?? Icon(icon, color: color),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: NavigoTextStyles.bodySmall.copyWith(
            fontSize: 12,
            color: color,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ],
    );
  }
}

ThemeData get appTheme {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: NavigoColors.primaryOrange,
      brightness: Brightness.light,
    ),
  );

  return base.copyWith(
    scaffoldBackgroundColor: NavigoColors.backgroundLight,
    cardTheme: CardThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
      ),
      elevation: 4,
    ),
    inputDecorationTheme: InputDecorationTheme(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      filled: true,
      fillColor: NavigoColors.inputFill,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        borderSide: BorderSide(color: NavigoColors.primaryOrange, width: 2),
      ),
      hintStyle: const TextStyle(fontSize: 16, color: NavigoColors.textMuted),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: NavigoDecorations.kPrimaryButtonStyle.copyWith(
        textStyle: WidgetStateProperty.all(NavigoTextStyles.button),
      ),
    ),
    dialogTheme: DialogThemeData(
      // AlertDialog titles should stay readable on every dialog background.
      // This applies to default `title: Text(...)` dialogs across the app.
      titleTextStyle: NavigoTextStyles.titleSmall.copyWith(color: Colors.black),
    ),
    textTheme: const TextTheme(
      headlineLarge: NavigoTextStyles.titleLarge,
      headlineMedium: NavigoTextStyles.titleMedium,
      titleLarge: NavigoTextStyles.titleSmall,
      bodySmall: NavigoTextStyles.bodySmall,
      bodyMedium: NavigoTextStyles.bodyMedium,
      labelLarge: NavigoTextStyles.label,
    ),
  );
}
