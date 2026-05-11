import 'package:flutter/material.dart';

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

  static InputDecoration kInputDecoration = const InputDecoration(
    contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
    foregroundColor: NavigoColors.textLight,
    shape: const RoundedRectangleBorder(
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
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(16)),
    ),
  );

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
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(NavigoSizes.chipRadius),
      ),
      child: Text(label, style: NavigoTextStyles.status.copyWith(color: color)),
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
