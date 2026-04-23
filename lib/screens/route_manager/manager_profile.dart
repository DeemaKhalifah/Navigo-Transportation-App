import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../controllers/manager_profile_controller.dart';
import '../../theme/app_theme.dart';
import '../authentication/email_login.dart';
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
    controller.init();
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
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _showImagePicker() {
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text("Take Photo"),
              onTap: () {
                Navigator.of(sheetContext).pop();
                controller.pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo),
              title: const Text("Choose from Gallery"),
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

    _showSnack(error ?? "Profile updated");
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

    try {
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (stfContext, setDialogState) {
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

                  _showSnack("Password changed successfully");

                  await controller.logout();

                  if (!mounted) return;

                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => const EmailLoginScreen()),
                    (route) => false,
                  );
                } else {
                  setDialogState(() => isChanging = false);
                  _showSnack(error);
                }
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
                    const Text(
                      "Change Password",
                      style: NavigoTextStyles.titleSmall,
                    ),
                  ],
                ),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 8),
                      TextField(
                        controller: currentPasswordController,
                        obscureText: obscureCurrent,
                        enabled: !isChanging,
                        style: NavigoTextStyles.bodyMedium.copyWith(
                          color: NavigoColors.textDark,
                          fontWeight: FontWeight.w500,
                        ),
                        decoration: NavigoDecorations.kInputDecoration.copyWith(
                          hintText: "Current Password",
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
                                    setDialogState(
                                      () => obscureCurrent = !obscureCurrent,
                                    );
                                  },
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: newPasswordController,
                        obscureText: obscureNew,
                        enabled: !isChanging,
                        style: NavigoTextStyles.bodyMedium.copyWith(
                          color: NavigoColors.textDark,
                          fontWeight: FontWeight.w500,
                        ),
                        decoration: NavigoDecorations.kInputDecoration.copyWith(
                          hintText: "New Password",
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
                                    setDialogState(
                                      () => obscureNew = !obscureNew,
                                    );
                                  },
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: confirmPasswordController,
                        obscureText: obscureConfirm,
                        enabled: !isChanging,
                        style: NavigoTextStyles.bodyMedium.copyWith(
                          color: NavigoColors.textDark,
                          fontWeight: FontWeight.w500,
                        ),
                        decoration: NavigoDecorations.kInputDecoration.copyWith(
                          hintText: "Confirm New Password",
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
                                    setDialogState(
                                      () => obscureConfirm = !obscureConfirm,
                                    );
                                  },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: isChanging
                        ? null
                        : () => Navigator.of(dialogContext).pop(),
                    child: Text(
                      "Cancel",
                      style: NavigoTextStyles.bodyMedium.copyWith(
                        fontWeight: FontWeight.w600,
                        color: NavigoColors.textMuted,
                      ),
                    ),
                  ),
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
                        : const Text("Change"),
                  ),
                ],
              );
            },
          );
        },
      );
    } finally {
      currentPasswordController.dispose();
      newPasswordController.dispose();
      confirmPasswordController.dispose();
    }
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
      bottomNavigationBar: const RouteManagerNavBar(currentIndex: 3),
      body: SafeArea(
        child: Column(
          children: [
            NavigoDecorations.topBar(
              onBack: () {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => const RouteSchedule()),
                );
              },
              context: context,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("Profile", style: NavigoTextStyles.titleLarge),
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
                              "Full Name",
                              controller.nameController,
                              controller.isEditing,
                              Icons.person,
                            ),
                            const SizedBox(height: 16),
                            _field(
                              "Email",
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
                                      : const Text("Save"),
                                ),
                              ),
                            if (controller.isEditing)
                              const SizedBox(height: 20),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                "Settings",
                                style: NavigoTextStyles.titleSmall.copyWith(
                                  color: NavigoColors.textGray,
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            _settingsItem(
                              icon: Icons.lock_outline,
                              title: "Change Password",
                              onTap: _changePassword,
                            ),
                            _settingsItem(
                              icon: Icons.logout,
                              title: "Log out",
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
