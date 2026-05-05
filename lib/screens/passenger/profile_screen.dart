import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../controllers/profile_controller.dart';
import '../../localization/localization_x.dart';
import '../../theme/app_theme.dart';
import '../../widgets/language_toggle_switch.dart';
import 'passenger_bottom_nav_bar.dart';
import 'passenger_home_screen.dart';
import 'support_screen.dart';

/// Passenger profile screen — UI only.
/// All business logic delegated to [ProfileController].
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final ProfileController _controller;

  @override
  void initState() {
    super.initState();
    _controller = ProfileController();
    _controller.addListener(_onControllerChange);
    _controller.init();
  }

  void _onControllerChange() {
    if (mounted) setState(() {});
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
                  _controller.pickImage(ImageSource.camera);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo),
                title: Text(context.texts.t('chooseGallery')),
                onTap: () {
                  Navigator.pop(context);
                  _controller.pickImage(ImageSource.gallery);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _handleSaveProfile() async {
    final error = await _controller.saveProfile();
    if (!mounted) return;
    if (error != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
    } else {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(context.texts.t('profileUpdated'))));
    }
  }

  Future<void> _handleLogout() async {
    await _controller.logout();
    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  Widget _buildProfileImage({
    BoxFit fit = BoxFit.cover,
    double? width,
    double? height,
  }) {
    return Image(
      image: _controller.profileImageProvider,
      fit: fit,
      width: width,
      height: height,
    );
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChange);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      bottomNavigationBar: const PassengerBottomNavBar(currentIndex: 3),
      body: SafeArea(
        child: Column(
          children: [
            /// TOP BAR
            NavigoDecorations.topBar(
              onBack: () => Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                    builder: (_) => const PassengerHomeScreen()),
              ),
              context: context,
            ),

            /// TITLE
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(context.texts.t('profile'), style: NavigoTextStyles.titleLarge),
                  IconButton(
                    onPressed: _controller.toggleEdit,
                    icon: Icon(
                      _controller.isEditing ? Icons.close : Icons.edit,
                      color: NavigoColors.accentGreen,
                    ),
                  ),
                ],
              ),
            ),

            /// BODY
            Expanded(
              child: SingleChildScrollView(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 20),
                  padding: const EdgeInsets.all(20),
                  decoration: NavigoDecorations.kCardDecoration,
                  child: Column(
                    children: [
                      /// PROFILE IMAGE
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
                          if (_controller.isEditing)
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

                      /// NAME
                      _field(
                        context.texts.t('fullName'),
                        _controller.nameController,
                        _controller.isEditing,
                        Icons.person,
                      ),

                      const SizedBox(height: 16),

                      /// PHONE
                      _field(
                        context.texts.t('phone'),
                        _controller.phoneController,
                        _controller.isEditing,
                        Icons.phone,
                      ),

                      const SizedBox(height: 20),

                      /// SAVE BUTTON
                      if (_controller.isEditing)
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _handleSaveProfile,
                            style:
                                NavigoDecorations.kPrimaryButtonLargeStyle,
                            child: Text(context.texts.t('save')),
                          ),
                        ),

                      const SizedBox(height: 20),

                      /// SETTINGS
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

                      const Align(
                        alignment: Alignment.centerLeft,
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
                        onTap: _handleLogout,
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

  /// FIELD
  Widget _field(
    String label,
    TextEditingController controller,
    bool enabled,
    IconData icon,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: NavigoTextStyles.label),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
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
