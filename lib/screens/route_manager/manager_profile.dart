import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../controllers/manager_profile_controller.dart';
import '../../localization/localization_x.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_message.dart';
import '../../widgets/language_toggle_switch.dart';
import '../authentication/email_login.dart';
import 'route_manager_notification_compose.dart';
import 'route_manager_nav_bar.dart';
import 'route_schedule.dart';

class ManagerProfile extends StatefulWidget {
  const ManagerProfile({super.key});

  @override
  State<ManagerProfile> createState() => _ManagerProfileState();
}

class _ManagerProfileState extends State<ManagerProfile> {
  final ManagerProfileController controller = ManagerProfileController();

  @override
  void initState() {
    super.initState();

    controller.addListener(_refresh);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        controller.init();
      }
    });
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    controller.removeListener(_refresh);
    controller.dispose();
    super.dispose();
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    AppMessage.showInfo(context, msg);
  }

  void _showImagePicker() {
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: Text(context.texts.t('takePhoto')),
              onTap: () {
                Navigator.of(sheetContext).pop();
                controller.pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo),
              title: Text(context.texts.t('chooseGallery')),
              onTap: () {
                Navigator.of(sheetContext).pop();
                controller.pickImage(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveProfile() async {
    final error = await controller.saveProfile();

    if (!mounted) return;

    _showSnack(error ?? context.texts.t('profileUpdated'));
  }

  Future<void> _logout() async {
    await controller.logout();

    if (!mounted) return;

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const EmailLoginScreen()),
      (route) => false,
    );
  }

  Future<void> _changePassword() async {
    final currentPasswordController = TextEditingController();
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();

    bool obscureCurrent = true;
    bool obscureNew = true;
    bool obscureConfirm = true;
    bool isChanging = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> handleChangePassword() async {
              if (isChanging) return;

              setDialogState(() => isChanging = true);

              final error = await controller.changePassword(
                currentPasswordController.text,
                newPasswordController.text,
                confirmPasswordController.text,
              );

              if (!mounted) return;

              if (error == null) {
                Navigator.of(dialogContext).pop();

                _showSnack(context.texts.t('passwordChanged'));

                await controller.logout();

                if (!mounted) return;

                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const EmailLoginScreen()),
                  (route) => false,
                );
              } else {
                if (Navigator.of(dialogContext).canPop()) {
                  setDialogState(() => isChanging = false);
                }
                _showSnack(error);
              }
            }

            void closeDialog() {
              FocusManager.instance.primaryFocus?.unfocus();
              Navigator.of(dialogContext).pop();
            }

            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              backgroundColor: NavigoColors.lightorange,
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: NavigoDecorations.iconCircleDecoration(
                      NavigoColors.primaryOrange,
                    ),
                    child: const Icon(
                      Icons.lock_outline,
                      color: NavigoColors.primaryOrange,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    context.texts.t('changePassword'),
                    style: NavigoTextStyles.titleSmall.copyWith(
                      color: Colors.black,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: isChanging ? null : closeDialog,
                    icon: const Icon(
                      Icons.close,
                      color: NavigoColors.textMuted,
                      size: 20,
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 8),

                    /// 🔴 CURRENT PASSWORD
                    TextField(
                      controller: currentPasswordController,
                      obscureText: obscureCurrent,
                      enabled: !isChanging,
                      style: const TextStyle(color: Colors.black), // ✅ FIX
                      cursorColor: Colors.black,
                      decoration: NavigoDecorations.kInputDecoration.copyWith(
                        hintText: context.texts.t('currentPassword'),
                        hintStyle: const TextStyle(color: Colors.grey),
                        prefixIcon: const Icon(
                          Icons.lock,
                          color: NavigoColors.textMuted,
                        ),
                        suffixIcon: IconButton(
                          icon: Icon(
                            obscureCurrent
                                ? Icons.visibility_off
                                : Icons.visibility,
                            color: NavigoColors.textMuted,
                          ),
                          onPressed: isChanging
                              ? null
                              : () {
                                  setDialogState(() {
                                    obscureCurrent = !obscureCurrent;
                                  });
                                },
                        ),
                      ),
                    ),

                    const SizedBox(height: 14),

                    /// 🔴 NEW PASSWORD
                    TextField(
                      controller: newPasswordController,
                      obscureText: obscureNew,
                      enabled: !isChanging,
                      style: const TextStyle(color: Colors.black), // ✅ FIX
                      cursorColor: Colors.black,
                      decoration: NavigoDecorations.kInputDecoration.copyWith(
                        hintText: context.texts.t('newPassword'),
                        hintStyle: const TextStyle(color: Colors.grey),
                        prefixIcon: const Icon(
                          Icons.lock_open,
                          color: NavigoColors.accentGreen,
                        ),
                        suffixIcon: IconButton(
                          icon: Icon(
                            obscureNew
                                ? Icons.visibility_off
                                : Icons.visibility,
                            color: NavigoColors.textMuted,
                          ),
                          onPressed: isChanging
                              ? null
                              : () {
                                  setDialogState(() {
                                    obscureNew = !obscureNew;
                                  });
                                },
                        ),
                      ),
                    ),

                    const SizedBox(height: 14),

                    /// 🔴 CONFIRM PASSWORD
                    TextField(
                      controller: confirmPasswordController,
                      obscureText: obscureConfirm,
                      enabled: !isChanging,
                      style: const TextStyle(color: Colors.black), // ✅ FIX
                      cursorColor: Colors.black,
                      decoration: NavigoDecorations.kInputDecoration.copyWith(
                        hintText: context.texts.t('confirmNewPassword'),
                        hintStyle: const TextStyle(color: Colors.grey),
                        prefixIcon: const Icon(
                          Icons.lock_open,
                          color: NavigoColors.accentGreen,
                        ),
                        suffixIcon: IconButton(
                          icon: Icon(
                            obscureConfirm
                                ? Icons.visibility_off
                                : Icons.visibility,
                            color: NavigoColors.textMuted,
                          ),
                          onPressed: isChanging
                              ? null
                              : () {
                                  setDialogState(() {
                                    obscureConfirm = !obscureConfirm;
                                  });
                                },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                ElevatedButton(
                  onPressed: isChanging ? null : handleChangePassword,
                  style: NavigoDecorations.kPrimaryButtonLargeStyle,
                  child: isChanging
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: NavigoColors.textLight,
                          ),
                        )
                      : Text(context.texts.t('change')),
                ),
              ],
            );
          },
        );
      },
    );

    currentPasswordController.dispose();
    newPasswordController.dispose();
    confirmPasswordController.dispose();
  }

  Widget _buildProfileImage({
    BoxFit fit = BoxFit.cover,
    double? width,
    double? height,
  }) {
    return Image(
      image: controller.profileImageProvider,
      fit: fit,
      width: width,
      height: height,
    );
  }

  Widget _field(
    String label,
    TextEditingController fieldController,
    bool enabled,
    IconData icon,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: NavigoTextStyles.label),
        const SizedBox(height: 6),
        TextField(
          controller: fieldController,
          enabled: enabled,
          style: NavigoTextStyles.bodyMedium.copyWith(
            color: NavigoColors.textDark,
            fontWeight: FontWeight.w500,
          ),
          decoration: NavigoDecorations.kInputDecoration.copyWith(
            prefixIcon: Icon(icon, color: NavigoColors.accentGreen),
          ),
        ),
      ],
    );
  }

  Widget _settingsItem({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    Color color = NavigoColors.textDark,
  }) {
    return ListTile(
      onTap: onTap,
      leading: Icon(icon, color: color),
      title: Text(
        title,
        style: NavigoTextStyles.bodyMedium.copyWith(
          fontWeight: FontWeight.w500,
          color: color,
        ),
      ),
      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      bottomNavigationBar: const RouteManagerNavBar(currentIndex: 4),
      body: SafeArea(
        child: Column(
          children: [
            NavigoDecorations.topBar3(
              onBack: () {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => const RouteSchedule()),
                );
              },
              onNotification: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const RouteManagerNotificationCompose(),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    context.texts.t('profile'),
                    style: NavigoTextStyles.titleLarge,
                  ),
                  IconButton(
                    onPressed: controller.toggleEdit,
                    icon: Icon(
                      controller.isEditing ? Icons.close : Icons.edit,
                      color: NavigoColors.accentGreen,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: controller.isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : SingleChildScrollView(
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 20),
                        padding: const EdgeInsets.all(20),
                        decoration: NavigoDecorations.kCardDecoration,
                        child: Column(
                          children: [
                            Stack(
                              children: [
                                CircleAvatar(
                                  radius: 50,
                                  backgroundColor: NavigoColors.surfaceWhite,
                                  child: ClipOval(
                                    child: _buildProfileImage(
                                      fit: BoxFit.contain,
                                      width: 80,
                                      height: 80,
                                    ),
                                  ),
                                ),
                                if (controller.isEditing)
                                  Positioned(
                                    bottom: 0,
                                    right: 0,
                                    child: GestureDetector(
                                      onTap: _showImagePicker,
                                      child: Container(
                                        padding: const EdgeInsets.all(6),
                                        decoration:
                                            NavigoDecorations.iconCircleDecoration(
                                              NavigoColors.accentGreen,
                                            ),
                                        child: const Icon(
                                          Icons.camera_alt,
                                          size: 16,
                                          color: NavigoColors.textLight,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            _field(
                              context.texts.t('fullName'),
                              controller.nameController,
                              controller.isEditing,
                              Icons.person,
                            ),
                            const SizedBox(height: 16),
                            _field(
                              context.texts.t('email'),
                              controller.emailController,
                              false,
                              Icons.email,
                            ),
                            const SizedBox(height: 20),
                            if (controller.isEditing)
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton(
                                  onPressed: controller.isSaving
                                      ? null
                                      : _saveProfile,
                                  style: NavigoDecorations
                                      .kPrimaryButtonLargeStyle,
                                  child: controller.isSaving
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: NavigoColors.textLight,
                                          ),
                                        )
                                      : Text(context.texts.t('save')),
                                ),
                              ),
                            if (controller.isEditing)
                              const SizedBox(height: 20),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                context.texts.t('settings'),
                                style: NavigoTextStyles.titleSmall.copyWith(
                                  color: NavigoColors.textGray,
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Align(
                              alignment: AlignmentDirectional.centerStart,
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.language,
                                    color: NavigoColors.textDark,
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Text(
                                      context.texts.t('language'),
                                      style: NavigoTextStyles.bodyMedium
                                          .copyWith(
                                            fontWeight: FontWeight.w500,
                                            color: NavigoColors.textDark,
                                          ),
                                    ),
                                  ),
                                  const LanguageToggleSwitch(),
                                ],
                              ),
                            ),
                            const SizedBox(height: 8),
                            _settingsItem(
                              icon: Icons.lock_outline,
                              title: context.texts.t('changePassword'),
                              onTap: _changePassword,
                            ),
                            _settingsItem(
                              icon: Icons.logout,
                              title: context.texts.t('logout'),
                              color: NavigoColors.accentRed,
                              onTap: _logout,
                            ),
                          ],
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
