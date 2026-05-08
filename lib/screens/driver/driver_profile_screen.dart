import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../localization/localization_x.dart';
import '../../theme/app_theme.dart';
import '../../controllers/driver_profile_controller.dart';
import '../../widgets/app_message.dart';
import '../../widgets/language_toggle_switch.dart';
import 'driver_bottom_nav_bar.dart';
import 'driver_home_screen.dart';
import '../../screens/passenger/support_screen.dart';
import '../../models/driver_status.dart';
import '../welcome_flow/welcome.dart';

class DriverProfileScreen extends StatefulWidget {
  const DriverProfileScreen({super.key});

  @override
  State<DriverProfileScreen> createState() => _DriverProfileScreenState();
}

class _DriverProfileScreenState extends State<DriverProfileScreen> {
  late final DriverProfileController controller;

  @override
  void initState() {
    super.initState();
    controller = DriverProfileController();
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

  void _showSnack(String message) {
    AppMessage.showInfo(context, message);
  }

  void _showImagePicker() {
    showModalBottomSheet(
      context: context,
      builder: (_) {
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: Text(context.texts.t('takePhoto')),
                onTap: () {
                  Navigator.pop(context);
                  controller.pickImage(ImageSource.camera);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo),
                title: Text(context.texts.t('chooseGallery')),
                onTap: () {
                  Navigator.pop(context);
                  controller.pickImage(ImageSource.gallery);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _saveProfile() async {
    final error = await controller.saveProfile();

    if (!mounted) return;

    if (error == null) {
      _showSnack(context.texts.t('profileUpdated'));
    } else {
      _showSnack(error);
    }
  }

  Future<void> _goOnline() async {
    final error = await controller.goOnline();

    if (!mounted) return;

    _showSnack(error ?? context.texts.t('onlineQueue'));
  }

  Future<void> _goOffline() async {
    final error = await controller.goOffline();

    if (!mounted) return;

    _showSnack(error ?? context.texts.t('offlineQueue'));
  }

  Future<void> _logout() async {
    await controller.logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const OnboardingScreen()),
      (route) => false,
    );
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

  @override
  Widget build(BuildContext context) {
    final isAvailable = controller.driverStatus == DriverStatus.available;
    final isOffline = controller.driverStatus == DriverStatus.offline;

    return Scaffold(
      bottomNavigationBar: const DriverBottomNavBar(currentIndex: 3),
      body: SafeArea(
        child: Column(
          children: [
            NavigoDecorations.topBar(
              onBack: () => Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => DriverHomeScreen()),
              ),
              context: context,
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
                              children: <Widget>[
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
                              context.texts.t('phone'),
                              controller.phoneController,
                              controller.isEditing,
                              Icons.phone,
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
                                          width: 22,
                                          height: 22,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: NavigoColors.textLight,
                                          ),
                                        )
                                      : Text(context.texts.t('save')),
                                ),
                              ),
                            const SizedBox(height: 16),
                            Align(
                              // Use directional start so this text moves with
                              // the active language: left for English, right
                              // for Arabic after Directionality rebuilds.
                              alignment: AlignmentDirectional.centerStart,
                              child: Text(
                                '${context.texts.t('driverStatus')}: ${controller.statusLabel}',
                                style: NavigoTextStyles.bodyMedium.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            if (controller.onLiveTrip)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(
                                  context.texts.t('finishTripHint'),
                                  style: NavigoTextStyles.bodySmall.copyWith(
                                    color: NavigoColors.textMuted,
                                  ),
                                ),
                              )
                            else if (controller.assignedTrip)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(
                                  context.texts.t('assignedTripHint'),
                                  style: NavigoTextStyles.bodySmall.copyWith(
                                    color: NavigoColors.textMuted,
                                  ),
                                ),
                              ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton(
                                    onPressed:
                                        (controller.statusBusy ||
                                            controller
                                                .blocksAvailabilityToggle ||
                                            isAvailable)
                                        ? null
                                        : _goOnline,
                                    style: NavigoDecorations
                                        .kPrimaryButtonLargeStyle
                                        .copyWith(
                                          backgroundColor:
                                              const WidgetStatePropertyAll(
                                                NavigoColors.accentGreen,
                                              ),
                                        ),
                                    child: controller.statusBusy
                                        ? const SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: NavigoColors.textLight,
                                            ),
                                          )
                                        : Text(context.texts.t('goOnline')),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: ElevatedButton(
                                    onPressed:
                                        (controller.statusBusy ||
                                            controller
                                                .blocksAvailabilityToggle ||
                                            isOffline)
                                        ? null
                                        : _goOffline,
                                    style: NavigoDecorations
                                        .kPrimaryButtonLargeStyle
                                        .copyWith(
                                          backgroundColor:
                                              const WidgetStatePropertyAll(
                                                NavigoColors.accentRed,
                                              ),
                                        ),
                                    child: Text(context.texts.t('goOffline')),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            Align(
                              // Keep section headers aligned to the reading
                              // start instead of hard-coding the left side.
                              alignment: AlignmentDirectional.centerStart,
                              child: Text(
                                context.texts.t('settings'),
                                style: NavigoTextStyles.titleSmall.copyWith(
                                  color: NavigoColors.textGray,
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            const Align(
                              // The language switch follows the current text
                              // direction: English/LTR start is left, Arabic
                              // /RTL start is right.
                              alignment: AlignmentDirectional.centerStart,
                              child: LanguageToggleSwitch(),
                            ),
                            const SizedBox(height: 8),
                            _settingsItem(
                              icon: Icons.help_outline,
                              title: context.texts.t('helpSupport'),
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const HelpSupportScreen(),
                                  ),
                                );
                              },
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
}
