import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../theme/app_theme.dart';
import '../authentication/email_login.dart';
import 'RouteManagerNavBar.dart';
import 'RouteSchedule.dart';

class ManagerProfile extends StatefulWidget {
  const ManagerProfile({super.key});

  @override
  State<ManagerProfile> createState() => _ManagerProfileState();
}

class _ManagerProfileState extends State<ManagerProfile> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();

  final ImagePicker _picker = ImagePicker();

  File? _image;
  bool _isEditing = false;
  bool _isLoading = true;

  User? currentUser;
  DocumentReference<Map<String, dynamic>>? userDocRef;

  @override
  void initState() {
    super.initState();
    _initProfile();
  }

  Future<void> _initProfile() async {
    currentUser = FirebaseAuth.instance.currentUser;

    if (currentUser == null) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      return;
    }

    userDocRef = FirebaseFirestore.instance
        .collection('users')
        .doc(currentUser!.uid);

    await _loadUserData();
  }

  Future<void> _loadUserData() async {
    try {
      final ref = userDocRef;
      if (ref == null) {
        if (!mounted) return;
        setState(() => _isLoading = false);
        return;
      }

      final snapshot = await ref.get();

      if (!mounted) return;

      if (snapshot.exists) {
        final data = snapshot.data();

        _nameController.text =
            "${data?['firstName'] ?? ''} ${data?['lastName'] ?? ''}".trim();

        _emailController.text = (data?['email'] ?? currentUser?.email ?? '')
            .toString();
      }

      setState(() => _isLoading = false);
    } catch (e) {
      debugPrint("Error loading manager data: $e");
      if (!mounted) return;
      setState(() => _isLoading = false);

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Failed to load profile: $e")));
    }
  }

  void _toggleEdit() {
    if (!mounted) return;
    setState(() => _isEditing = !_isEditing);
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picked = await _picker.pickImage(source: source);
      if (picked == null || !mounted) return;

      setState(() => _image = File(picked.path));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Failed to pick image: $e")));
    }
  }

  void _showImagePicker() {
    if (!mounted) return;

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
                _pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo),
              title: const Text("Choose from Gallery"),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _pickImage(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _logout() async {
    try {
      await FirebaseAuth.instance.signOut();
      if (!mounted) return;

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const EmailLoginScreen()),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Failed to log out: $e")));
    }
  }

  Future<void> _changePassword() async {
    final currentPasswordController = TextEditingController();
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();

    bool obscureCurrent = true;
    bool obscureNew = true;
    bool obscureConfirm = true;
    bool isChanging = false;

    final user = FirebaseAuth.instance.currentUser;

    if (user == null || user.email == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("No logged in user found.")));
      return;
    }

    try {
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (stfContext, setDialogState) {
              Future<void> handleChangePassword() async {
                final currentPw = currentPasswordController.text.trim();
                final newPw = newPasswordController.text.trim();
                final confirmPw = confirmPasswordController.text.trim();

                if (currentPw.isEmpty || newPw.isEmpty || confirmPw.isEmpty) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Please fill in all fields")),
                  );
                  return;
                }

                if (newPw.length < 6) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        "New password must be at least 6 characters",
                      ),
                    ),
                  );
                  return;
                }

                if (newPw != confirmPw) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("New passwords do not match")),
                  );
                  return;
                }

                setDialogState(() => isChanging = true);

                try {
                  final credential = EmailAuthProvider.credential(
                    email: user.email!,
                    password: currentPw,
                  );

                  await user.reauthenticateWithCredential(credential);
                  await user.updatePassword(newPw);

                  if (Navigator.of(dialogContext).canPop()) {
                    Navigator.of(dialogContext).pop();
                  }

                  if (!mounted) return;

                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text("Password changed successfully"),
                    ),
                  );

                  await FirebaseAuth.instance.signOut();

                  if (!mounted) return;

                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => const EmailLoginScreen()),
                    (route) => false,
                  );
                } on FirebaseAuthException catch (e) {
                  if (Navigator.of(dialogContext).mounted) {
                    setDialogState(() => isChanging = false);
                  }

                  String message;
                  if (e.code == 'wrong-password' ||
                      e.code == 'invalid-credential') {
                    message = "Current password is incorrect.";
                  } else if (e.code == 'weak-password') {
                    message =
                        "New password is too weak. Use at least 6 characters.";
                  } else if (e.code == 'requires-recent-login') {
                    message =
                        "Please log in again, then try changing your password.";
                  } else {
                    message = e.message ?? "Failed to change password.";
                  }

                  if (!mounted) return;
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text(message)));
                } catch (e) {
                  if (Navigator.of(dialogContext).mounted) {
                    setDialogState(() => isChanging = false);
                  }

                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("Failed to change password: $e")),
                  );
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
                            onPressed: () {
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
                            onPressed: () {
                              setDialogState(() => obscureNew = !obscureNew);
                            },
                          ),
                        ),
                      ),

                      const SizedBox(height: 14),

                      TextField(
                        controller: confirmPasswordController,
                        obscureText: obscureConfirm,
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
                            onPressed: () {
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

  Future<void> _saveProfile() async {
    final ref = userDocRef;
    if (currentUser == null || ref == null) return;

    final fullName = _nameController.text.trim();
    final names = fullName.isEmpty
        ? <String>[]
        : fullName.split(RegExp(r'\s+'));
    final firstName = names.isNotEmpty ? names.first : "";
    final lastName = names.length > 1 ? names.sublist(1).join(" ") : "";

    try {
      await ref.update({
        "firstName": firstName,
        "lastName": lastName,
        "email": _emailController.text.trim(),
      });

      if (!mounted) return;

      setState(() => _isEditing = false);

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Profile updated")));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Failed to update profile: $e")));
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Widget _buildProfileImage({
    BoxFit fit = BoxFit.cover,
    double? width,
    double? height,
  }) {
    final ImageProvider imageProvider = _image != null
        ? FileImage(_image!)
        : const AssetImage("assets/images/logo.png");

    return Image(image: imageProvider, fit: fit, width: width, height: height);
  }

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
                    onPressed: _toggleEdit,
                    icon: Icon(
                      _isEditing ? Icons.close : Icons.edit,
                      color: NavigoColors.accentGreen,
                    ),
                  ),
                ],
              ),
            ),

            Expanded(
              child: _isLoading
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
                                if (_isEditing)
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
                              _nameController,
                              _isEditing,
                              Icons.person,
                            ),

                            const SizedBox(height: 16),

                            _field(
                              "Email",
                              _emailController,
                              _isEditing,
                              Icons.email,
                            ),

                            const SizedBox(height: 20),

                            if (_isEditing)
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton(
                                  onPressed: _saveProfile,
                                  style: NavigoDecorations
                                      .kPrimaryButtonLargeStyle,
                                  child: const Text("Save"),
                                ),
                              ),

                            if (_isEditing) const SizedBox(height: 20),

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
