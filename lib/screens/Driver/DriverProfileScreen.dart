import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../../theme/app_theme.dart';
import 'DriverBottomNavBar.dart';
import 'DriverHomeScreen.dart';
import '../../screens/passenger/support_screen.dart';
import '../../models/driver_status.dart';
import '../../services/driver_queue_repository.dart';

class DriverProfileScreen extends StatefulWidget {
  const DriverProfileScreen({super.key});

  @override
  State<DriverProfileScreen> createState() => _DriverProfileScreenState();
}

class _DriverProfileScreenState extends State<DriverProfileScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();

  final ImagePicker _picker = ImagePicker();

  File? _image;
  String? _imageUrl;

  bool _isEditing = false;
  bool _isLoading = true;
  bool _isSaving = false;
  bool _statusBusy = false;

  /// From `drivers/{uid}.status` — [DriverStatus] values.
  String _driverStatus = DriverStatus.offline;
  String? _assignedRouteId;

  User? currentUser;
  DocumentReference<Map<String, dynamic>>? userDocRef;
  final DriverQueueRepository _queueRepo = DriverQueueRepository();
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _driverDocSub;

  @override
  void initState() {
    super.initState();
    currentUser = FirebaseAuth.instance.currentUser;

    if (currentUser != null) {
      userDocRef = FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser!.uid);
      _driverDocSub = FirebaseFirestore.instance
          .collection('drivers')
          .doc(currentUser!.uid)
          .snapshots()
          .listen((snap) {
        if (!mounted || !snap.exists) return;
        final st = snap.data()?['status'] as String?;
        final rid = snap.data()?['routeId'] as String?;
        if (st != null) {
          setState(() {
            _driverStatus = st;
            if (rid != null) _assignedRouteId = rid;
          });
        }
      });
      _loadUserData();
    } else {
      _isLoading = false;
    }
  }

  Future<void> _loadUserData() async {
    if (userDocRef == null) return;

    try {
      final snapshot = await userDocRef!.get();

      if (snapshot.exists) {
        final data = snapshot.data() ?? {};

        _nameController.text =
            "${data['firstName'] ?? ''} ${data['lastName'] ?? ''}".trim();

        _phoneController.text = data['phone'] ?? '';
        _imageUrl = data['image'];
      }

      if (currentUser != null) {
        final d = await FirebaseFirestore.instance
            .collection('drivers')
            .doc(currentUser!.uid)
            .get();
        if (d.exists) {
          final dd = d.data() ?? {};
          _driverStatus = dd['status'] as String? ?? DriverStatus.offline;
          _assignedRouteId = dd['routeId'] as String?;
        }
      }
    } catch (e) {
      debugPrint("Error loading driver data: $e");
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Failed to load profile: $e")));
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _toggleEdit() {
    setState(() => _isEditing = !_isEditing);
  }

  Future<void> _pickImage(ImageSource source) async {
    final picked = await _picker.pickImage(source: source, imageQuality: 75);

    if (picked != null) {
      setState(() {
        _image = File(picked.path);
      });
    }
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
                title: const Text("Take Photo"),
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.camera);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo),
                title: const Text("Choose from Gallery"),
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.gallery);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<String?> _uploadProfileImage() async {
    if (_image == null || currentUser == null) return _imageUrl;

    try {
      final storageRef = FirebaseStorage.instance
          .ref()
          .child('profile_images')
          .child('${currentUser!.uid}.jpg');

      await storageRef.putFile(_image!);
      final downloadUrl = await storageRef.getDownloadURL();

      return downloadUrl;
    } catch (e) {
      debugPrint("Image upload error: $e");
      rethrow;
    }
  }

  Future<void> _saveProfile() async {
    if (currentUser == null || userDocRef == null) return;

    setState(() {
      _isSaving = true;
    });

    final names = _nameController.text.trim().split(" ");
    final firstName = names.isNotEmpty ? names.first : "";
    final lastName = names.length > 1 ? names.sublist(1).join(" ") : "";

    try {
      final uploadedImageUrl = await _uploadProfileImage();

      await userDocRef!.update({
        "firstName": firstName,
        "lastName": lastName,
        "phone": _phoneController.text.trim(),
        "image": uploadedImageUrl,
      });

      if (mounted) {
        setState(() {
          _imageUrl = uploadedImageUrl;
          _isEditing = false;
        });

        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("Profile updated")));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Failed to update profile: $e")));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  bool get _onLiveTrip => _driverStatus == DriverStatus.onTrip;

  bool get _assignedTrip => _driverStatus == DriverStatus.assigned;

  bool get _blocksAvailabilityToggle =>
      _onLiveTrip || _assignedTrip;

  String get _statusLabel {
    switch (_driverStatus) {
      case DriverStatus.available:
        return 'Available';
      case DriverStatus.assigned:
        return 'Assigned (start trip when ready)';
      case DriverStatus.onTrip:
        return 'On trip';
      default:
        return 'Offline';
    }
  }

  Future<void> _goOnline() async {
    if (currentUser == null || _blocksAvailabilityToggle) return;
    final routeId = _assignedRouteId?.trim();
    if (routeId == null || routeId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No route assigned. Update your driver profile in Firestore.'),
        ),
      );
      return;
    }

    setState(() => _statusBusy = true);
    try {
      final dRef = FirebaseFirestore.instance
          .collection('drivers')
          .doc(currentUser!.uid);

      await dRef.update({'status': DriverStatus.available});
      await _queueRepo.joinQueue(routeId, currentUser!.uid);

      if (mounted) {
        setState(() => _driverStatus = DriverStatus.available);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('You are online and in the driver queue.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not go online: $e')));
      }
    } finally {
      if (mounted) setState(() => _statusBusy = false);
    }
  }

  Future<void> _goOffline() async {
    if (currentUser == null || _blocksAvailabilityToggle) return;
    final routeId = _assignedRouteId?.trim();
    if (routeId == null || routeId.isEmpty) {
      await FirebaseFirestore.instance
          .collection('drivers')
          .doc(currentUser!.uid)
          .update({'status': DriverStatus.offline});
      if (mounted) setState(() => _driverStatus = DriverStatus.offline);
      return;
    }

    setState(() => _statusBusy = true);
    try {
      final dRef = FirebaseFirestore.instance
          .collection('drivers')
          .doc(currentUser!.uid);

      await dRef.update({'status': DriverStatus.offline});
      await _queueRepo.leaveQueue(routeId, currentUser!.uid);

      if (mounted) {
        setState(() => _driverStatus = DriverStatus.offline);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('You are offline and left the queue.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not go offline: $e')));
      }
    } finally {
      if (mounted) setState(() => _statusBusy = false);
    }
  }

  Future<void> _logout() async {
    final uid = currentUser?.uid;
    if (uid != null) {
      try {
        final d = await FirebaseFirestore.instance
            .collection('drivers')
            .doc(uid)
            .get();
        final routeId = d.data()?['routeId'] as String?;
        if (routeId != null && routeId.isNotEmpty) {
          await _queueRepo.leaveQueue(routeId, uid);
        }
        await FirebaseFirestore.instance.collection('drivers').doc(uid).update({
          'status': DriverStatus.offline,
        });
      } catch (e) {
        debugPrint('Logout driver cleanup: $e');
      }
    }
    await FirebaseAuth.instance.signOut();
    if (mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  @override
  void dispose() {
    _driverDocSub?.cancel();
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Widget _buildProfileImage({
    BoxFit fit = BoxFit.cover,
    double? width,
    double? height,
  }) {
    final imageProvider = _image != null
        ? FileImage(_image!)
        : (_imageUrl != null && _imageUrl!.isNotEmpty)
        ? NetworkImage(_imageUrl!)
        : const AssetImage("assets/images/logo.png") as ImageProvider;

    return Image(image: imageProvider, fit: fit, width: width, height: height);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      bottomNavigationBar: const DriverBottomNavBar(currentIndex: 3),
      body: SafeArea(
        child: Column(
          children: [
            NavigoDecorations.topBar(
              onBack: () => Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const DriverHomeScreen()),
              ),
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
                              "Phone",
                              _phoneController,
                              _isEditing,
                              Icons.phone,
                            ),
                            const SizedBox(height: 20),
                            if (_isEditing)
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton(
                                  onPressed: _isSaving ? null : _saveProfile,
                                  style: NavigoDecorations
                                      .kPrimaryButtonLargeStyle,
                                  child: _isSaving
                                      ? const SizedBox(
                                          width: 22,
                                          height: 22,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: NavigoColors.textLight,
                                          ),
                                        )
                                      : const Text("Save"),
                                ),
                              ),
                            const SizedBox(height: 16),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'Driver status: $_statusLabel',
                                style: NavigoTextStyles.bodyMedium.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            if (_onLiveTrip)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(
                                  'Finish your current trip before changing availability.',
                                  style: NavigoTextStyles.bodySmall.copyWith(
                                    color: NavigoColors.textMuted,
                                  ),
                                ),
                              )
                            else if (_assignedTrip)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(
                                  'You have an assigned trip. Start it from Trips or wait until the route manager updates the schedule.',
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
                                    onPressed: (_statusBusy ||
                                            _blocksAvailabilityToggle ||
                                            _driverStatus ==
                                                DriverStatus.available)
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
                                    child: const Text('Go online'),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: ElevatedButton(
                                    onPressed: (_statusBusy ||
                                            _blocksAvailabilityToggle ||
                                            _driverStatus ==
                                                DriverStatus.offline)
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
                                    child: const Text('Go offline'),
                                  ),
                                ),
                              ],
                            ),
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
                              icon: Icons.help_outline,
                              title: "Help & Support",
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
