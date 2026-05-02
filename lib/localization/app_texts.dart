import 'package:flutter/widgets.dart';

class AppTexts {
  AppTexts(this.locale);

  final Locale locale;

  static const supportedLocales = [Locale('en'), Locale('ar')];

  static const Map<String, Map<String, String>> _strings = {
    'en': {
      'language': 'Language',
      'arabic': 'Arabic',
      'english': 'English',
      'welcomeSubtitle': 'Browse routes, track vehicles, and request trips.',
      'getStarted': 'Get Started',
      'signIn': 'Sign in',
      'profile': 'Profile',
      'fullName': 'Full Name',
      'phone': 'Phone',
      'email': 'Email',
      'save': 'Save',
      'settings': 'Settings',
      'helpSupport': 'Help & Support',
      'logout': 'Log out',
      'profileUpdated': 'Profile updated',
      'driverStatus': 'Driver status',
      'goOnline': 'Go online',
      'goOffline': 'Go offline',
      'onlineQueue': 'You are online and in the driver queue.',
      'offlineQueue': 'You are offline and left the queue.',
      'finishTripHint': 'Finish your current trip before changing availability.',
      'assignedTripHint':
          'You have an assigned trip. Start it from Trips or wait until the route manager updates the schedule.',
      'changePassword': 'Change Password',
      'takePhoto': 'Take Photo',
      'chooseGallery': 'Choose from Gallery',
      'currentPassword': 'Current Password',
      'newPassword': 'New Password',
      'confirmNewPassword': 'Confirm New Password',
      'cancel': 'Cancel',
      'change': 'Change',
      'passwordChanged': 'Password changed successfully',
    },
    'ar': {
      'language': 'اللغة',
      'arabic': 'العربية',
      'english': 'الإنجليزية',
      'welcomeSubtitle': 'تصفح المسارات، تتبع المركبات، واطلب الرحلات.',
      'getStarted': 'ابدأ الآن',
      'signIn': 'تسجيل الدخول',
      'profile': 'الملف الشخصي',
      'fullName': 'الاسم الكامل',
      'phone': 'الهاتف',
      'email': 'البريد الإلكتروني',
      'save': 'حفظ',
      'settings': 'الإعدادات',
      'helpSupport': 'المساعدة والدعم',
      'logout': 'تسجيل الخروج',
      'profileUpdated': 'تم تحديث الملف الشخصي',
      'driverStatus': 'حالة السائق',
      'goOnline': 'اتصال',
      'goOffline': 'غير متصل',
      'onlineQueue': 'أنت متصل الآن وفي قائمة السائقين.',
      'offlineQueue': 'أنت غير متصل الآن وتمت إزالتك من القائمة.',
      'finishTripHint': 'أكمل رحلتك الحالية قبل تغيير حالة التوفر.',
      'assignedTripHint':
          'لديك رحلة مخصصة. ابدأها من صفحة الرحلات أو انتظر تحديث مدير المسار.',
      'changePassword': 'تغيير كلمة المرور',
      'takePhoto': 'التقاط صورة',
      'chooseGallery': 'اختيار من المعرض',
      'currentPassword': 'كلمة المرور الحالية',
      'newPassword': 'كلمة المرور الجديدة',
      'confirmNewPassword': 'تأكيد كلمة المرور الجديدة',
      'cancel': 'إلغاء',
      'change': 'تغيير',
      'passwordChanged': 'تم تغيير كلمة المرور بنجاح',
    },
  };

  String t(String key) {
    final lang = _strings[locale.languageCode] ?? _strings['en']!;
    return lang[key] ?? _strings['en']![key] ?? key;
  }
}
