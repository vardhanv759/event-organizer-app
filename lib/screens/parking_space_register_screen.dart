import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

class ParkingSpaceRegisterScreen extends StatefulWidget {
  final Map<String, dynamic> userDoc;
  const ParkingSpaceRegisterScreen({super.key, required this.userDoc});

  @override
  State<ParkingSpaceRegisterScreen> createState() =>
      _ParkingSpaceRegisterScreenState();
}

class _ParkingSpaceRegisterScreenState
    extends State<ParkingSpaceRegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _picker = ImagePicker();

  // Space details
  final _titleCtrl = TextEditingController();
  final _postcodeCtrl = TextEditingController();
  final _approxAreaCtrl = TextEditingController(text: 'Wembley');
  final _exactAddressCtrl = TextEditingController();
  final _hourlyCtrl = TextEditingController();
  final _accessInstructionsCtrl = TextEditingController();
  final _vehicleRestrictionsCtrl = TextEditingController();

  String _spaceType = 'driveway';
  String _size = 'medium';
  String _availability = '24/7';

  // Amenities
  bool _isCovered = false;
  bool _hasEVCharging = false;
  bool _hasCCTV = false;
  bool _hasDisabledAccess = false;

  // Parking space photos (3-5 required)
  final List<File> _spaceImages = [];
  final List<String> _spaceImageUrls = [];

  // Agreements
  bool _authorityConfirmed = false;
  bool _termsAccepted = false;

  bool _submitting = false;
  bool _uploading = false;
  double _uploadProgress = 0.0;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _postcodeCtrl.dispose();
    _approxAreaCtrl.dispose();
    _exactAddressCtrl.dispose();
    _hourlyCtrl.dispose();
    _accessInstructionsCtrl.dispose();
    _vehicleRestrictionsCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickSpaceImage(ImageSource source) async {
    try {
      if (_spaceImages.length >= 5) {
        _snack('Maximum 5 photos allowed');
        return;
      }

      final XFile? pickedFile = await _picker.pickImage(
        source: source,
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );

      if (pickedFile != null) {
        setState(() {
          _spaceImages.add(File(pickedFile.path));
        });
      }
    } catch (e) {
      _snack('Failed to pick image: $e');
    }
  }

  void _showImageSourceDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              ListTile(
                leading: const Icon(
                  Icons.camera_alt_rounded,
                  color: Color(0xFF4F46E5),
                ),
                title: const Text(
                  'Take Photo',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _pickSpaceImage(ImageSource.camera);
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.photo_library_rounded,
                  color: Color(0xFF4F46E5),
                ),
                title: const Text(
                  'Choose from Gallery',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _pickSpaceImage(ImageSource.gallery);
                },
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  Future<String?> _uploadImage(File image, String path) async {
    try {
      final ref = FirebaseStorage.instance.ref().child(path);
      final uploadTask = ref.putFile(image);

      uploadTask.snapshotEvents.listen((event) {
        setState(() {
          _uploadProgress = event.bytesTransferred / event.totalBytes;
        });
      });

      await uploadTask;
      return await ref.getDownloadURL();
    } catch (e) {
      _snack('Upload failed: $e');
      return null;
    }
  }

  Future<void> _submit() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    if (!_formKey.currentState!.validate()) return;

    // Validate space photos
    if (_spaceImages.length < 3) {
      _snack('Please upload at least 3 parking space photos');
      return;
    }

    if (!_authorityConfirmed || !_termsAccepted) {
      _snack('Please confirm authority and accept terms to continue.');
      return;
    }

    setState(() {
      _submitting = true;
      _uploading = true;
    });

    try {
      final uid = user.uid;
      final timestamp = DateTime.now().millisecondsSinceEpoch;

      // Upload space photos
      for (int i = 0; i < _spaceImages.length; i++) {
        final url = await _uploadImage(
          _spaceImages[i],
          'parking_spaces/$uid/space_${timestamp}_$i.jpg',
        );
        if (url != null) {
          _spaceImageUrls.add(url);
        }
      }

      if (_spaceImageUrls.length < 3) {
        throw Exception('Failed to upload parking space photos');
      }

      setState(() => _uploading = false);

      // Create parking space
      final spaceRef = FirebaseFirestore.instance
          .collection('parking_spaces')
          .doc();
      await spaceRef.set({
        'providerId': uid,
        'title': _titleCtrl.text.trim(),
        'postcode': _postcodeCtrl.text.trim(),
        'approxArea': _approxAreaCtrl.text.trim(),
        'exactAddress': _exactAddressCtrl.text.trim(),
        'spaceType': _spaceType,
        'size': _size,
        'hourly_rate_gbp': double.tryParse(_hourlyCtrl.text.trim()) ?? 0.0,
        'availability': _availability,

        // Amenities
        'amenities': {
          'covered': _isCovered,
          'evCharging': _hasEVCharging,
          'cctv': _hasCCTV,
          'disabledAccess': _hasDisabledAccess,
        },

        // Additional info
        'accessInstructions': _accessInstructionsCtrl.text.trim(),
        'vehicleRestrictions': _vehicleRestrictionsCtrl.text.trim(),

        // Photos
        'photoUrls': _spaceImageUrls,

        // Agreements (saved to database)
        'agreements': {
          'authorityConfirmed': _authorityConfirmed,
          'termsAccepted': _termsAccepted,
          'agreedAt': FieldValue.serverTimestamp(),
        },

        // Status
        'status': 'pending',
        'approved': false,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      _snack('Space submitted successfully! Pending manual approval.');
      Navigator.pop(context);
    } catch (e) {
      _snack('Failed to submit: $e');
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
          _uploading = false;
        });
      }
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FF),
      body: Stack(
        children: [
          CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              _buildAppBar(),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 100),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    _buildInfoCard(),
                    const SizedBox(height: 20),
                    _buildLocationSection(),
                    const SizedBox(height: 20),
                    _buildSpaceDetailsSection(),
                    const SizedBox(height: 20),
                    _buildAmenitiesSection(),
                    const SizedBox(height: 20),
                    _buildAdditionalInfoSection(),
                    const SizedBox(height: 20),
                    _buildAvailabilitySection(),
                    const SizedBox(height: 20),
                    _buildSpacePhotosSection(),
                    const SizedBox(height: 20),
                    _buildAgreementsSection(),
                  ]),
                ),
              ),
            ],
          ),
          if (_uploading) _buildUploadOverlay(),
          _buildSubmitButton(),
        ],
      ),
    );
  }

  Widget _buildAppBar() {
    return SliverAppBar(
      pinned: true,
      stretch: true,
      expandedHeight: 220,
      elevation: 0,
      backgroundColor: Colors.transparent,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
        onPressed: () => Navigator.pop(context),
      ),
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          fit: StackFit.expand,
          children: [
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Color(0xFF6366F1),
                    Color(0xFF8B5CF6),
                    Color(0xFFEC4899),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),
            Positioned(
              right: -50,
              top: -50,
              child: Container(
                width: 200,
                height: 200,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.1),
                ),
              ),
            ),
            const SafeArea(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Icon(
                      Icons.add_location_alt_rounded,
                      color: Colors.white,
                      size: 40,
                    ),
                    SizedBox(height: 12),
                    Text(
                      'Add Parking Space',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.5,
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'Add a new space to your listings',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF3B82F6).withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF3B82F6).withOpacity(0.3),
          width: 2,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF3B82F6),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.info_rounded,
              color: Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Manual Review Required',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Your space will be reviewed before being published to drivers',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade700,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocationSection() {
    return _GlassCard(
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionHeader(
              icon: Icons.location_on_rounded,
              title: 'Location Details',
              subtitle: 'Where is your parking space?',
            ),
            const SizedBox(height: 16),
            _CustomTextField(
              controller: _titleCtrl,
              label: 'Space Title',
              hint: 'e.g., Secure parking near Wembley Stadium',
              icon: Icons.title_rounded,
              validator: (v) =>
                  (v == null || v.trim().length < 4) ? 'Enter a title' : null,
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _CustomTextField(
                    controller: _postcodeCtrl,
                    label: 'Postcode',
                    hint: 'HA9 0WS',
                    icon: Icons.location_on_rounded,
                    validator: (v) => (v == null || v.trim().length < 4)
                        ? 'Enter postcode'
                        : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _CustomTextField(
                    controller: _approxAreaCtrl,
                    label: 'Area',
                    hint: 'Wembley',
                    icon: Icons.map_rounded,
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Enter area' : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _CustomTextField(
              controller: _exactAddressCtrl,
              label: 'Exact Address',
              hint: 'Full address (hidden until payment)',
              icon: Icons.home_rounded,
              validator: (v) => (v == null || v.trim().length < 8)
                  ? 'Enter exact address'
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSpaceDetailsSection() {
    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            icon: Icons.local_parking_rounded,
            title: 'Space Details',
            subtitle: 'Specifications and pricing',
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _CustomDropdown(
                  label: 'Space Type',
                  value: _spaceType,
                  items: const [
                    'driveway',
                    'allocated_bay',
                    'underground',
                    'gated',
                    'open_lot',
                  ],
                  onChanged: (v) => setState(() => _spaceType = v),
                  itemLabel: (v) => v.replaceAll('_', ' ').toUpperCase(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _CustomDropdown(
                  label: 'Size',
                  value: _size,
                  items: const ['small', 'medium', 'large'],
                  onChanged: (v) => setState(() => _size = v),
                  itemLabel: (v) => v[0].toUpperCase() + v.substring(1),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _CustomTextField(
            controller: _hourlyCtrl,
            label: 'Hourly Rate',
            hint: '£5.00',
            icon: Icons.currency_pound_outlined,
            keyboardType: TextInputType.number,
            validator: (v) {
              final n = double.tryParse((v ?? '').trim());
              if (n == null || n <= 0) {
                return 'Enter valid price';
              }
              return null;
            },
          ),
        ],
      ),
    );
  }

  Widget _buildAmenitiesSection() {
    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            icon: Icons.star_rounded,
            title: 'Amenities & Features',
            subtitle: 'What makes your space special?',
          ),
          const SizedBox(height: 16),
          _AmenityCheckbox(
            value: _isCovered,
            title: 'Covered/Sheltered',
            icon: Icons.roofing_rounded,
            onChanged: (v) => setState(() => _isCovered = v ?? false),
          ),
          const SizedBox(height: 10),
          _AmenityCheckbox(
            value: _hasEVCharging,
            title: 'EV Charging Available',
            icon: Icons.ev_station_rounded,
            onChanged: (v) => setState(() => _hasEVCharging = v ?? false),
          ),
          const SizedBox(height: 10),
          _AmenityCheckbox(
            value: _hasCCTV,
            title: 'CCTV/Security',
            icon: Icons.videocam_rounded,
            onChanged: (v) => setState(() => _hasCCTV = v ?? false),
          ),
          const SizedBox(height: 10),
          _AmenityCheckbox(
            value: _hasDisabledAccess,
            title: 'Disabled Access',
            icon: Icons.accessible_rounded,
            onChanged: (v) => setState(() => _hasDisabledAccess = v ?? false),
          ),
        ],
      ),
    );
  }

  Widget _buildAdditionalInfoSection() {
    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            icon: Icons.info_outline_rounded,
            title: 'Additional Information',
            subtitle: 'Access and restrictions',
          ),
          const SizedBox(height: 16),
          _CustomTextField(
            controller: _accessInstructionsCtrl,
            label: 'Access Instructions',
            hint: 'e.g., Gate code 1234, Enter from side entrance',
            icon: Icons.key_rounded,
            maxLines: 3,
          ),
          const SizedBox(height: 14),
          _CustomTextField(
            controller: _vehicleRestrictionsCtrl,
            label: 'Vehicle Restrictions (Optional)',
            hint: 'e.g., Max height 2.1m, No commercial vehicles',
            icon: Icons.local_shipping_rounded,
            maxLines: 2,
          ),
        ],
      ),
    );
  }

  Widget _buildAvailabilitySection() {
    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            icon: Icons.access_time_rounded,
            title: 'Availability',
            subtitle: 'When is this space available?',
          ),
          const SizedBox(height: 16),
          _CustomDropdown(
            label: 'Availability',
            value: _availability,
            items: const [
              '24/7',
              'weekdays_only',
              'weekends_only',
              'event_days_only',
            ],
            onChanged: (v) => setState(() => _availability = v),
            itemLabel: (v) {
              switch (v) {
                case '24/7':
                  return '24/7 (Always Available)';
                case 'weekdays_only':
                  return 'Weekdays Only (Mon-Fri)';
                case 'weekends_only':
                  return 'Weekends Only (Sat-Sun)';
                case 'event_days_only':
                  return 'Event Days Only';
                default:
                  return v;
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSpacePhotosSection() {
    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            icon: Icons.photo_camera_rounded,
            title: 'Space Photos',
            subtitle: '3-5 clear photos required',
          ),
          const SizedBox(height: 16),
          if (_spaceImages.isNotEmpty)
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: List.generate(_spaceImages.length, (index) {
                return _SpacePhotoTile(
                  image: _spaceImages[index],
                  index: index + 1,
                  onRemove: () {
                    setState(() => _spaceImages.removeAt(index));
                  },
                );
              }),
            ),
          if (_spaceImages.isNotEmpty) const SizedBox(height: 12),
          if (_spaceImages.length < 5)
            InkWell(
              onTap: _showImageSourceDialog,
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFF4F46E5).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: const Color(0xFF4F46E5).withOpacity(0.3),
                    width: 2,
                    style: BorderStyle.solid,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.add_photo_alternate_rounded,
                      color: Color(0xFF4F46E5),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Add Photo (${_spaceImages.length}/5)',
                      style: const TextStyle(
                        color: Color(0xFF4F46E5),
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (_spaceImages.length < 3)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Row(
                children: [
                  const Icon(
                    Icons.info_rounded,
                    color: Color(0xFFEF4444),
                    size: 16,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Minimum 3 photos required',
                    style: TextStyle(
                      color: Colors.grey.shade700,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAgreementsSection() {
    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            icon: Icons.check_circle_rounded,
            title: 'Agreements',
            subtitle: 'Required confirmations',
          ),
          const SizedBox(height: 16),
          _CheckboxTile(
            value: _authorityConfirmed,
            title: 'I confirm I have authority to rent this parking space',
            onChanged: (v) => setState(() => _authorityConfirmed = v ?? false),
          ),
          const SizedBox(height: 10),
          _CheckboxTile(
            value: _termsAccepted,
            title: 'I accept the terms and conditions',
            onChanged: (v) => setState(() => _termsAccepted = v ?? false),
          ),
        ],
      ),
    );
  }

  Widget _buildUploadOverlay() {
    return Container(
      color: Colors.black54,
      child: Center(
        child: Container(
          margin: const EdgeInsets.all(40),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation(Color(0xFF4F46E5)),
              ),
              const SizedBox(height: 20),
              const Text(
                'Uploading space photos...',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              LinearProgressIndicator(
                value: _uploadProgress,
                backgroundColor: Colors.grey.shade200,
                valueColor: const AlwaysStoppedAnimation(Color(0xFF4F46E5)),
              ),
              const SizedBox(height: 10),
              Text(
                '${(_uploadProgress * 100).toInt()}%',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSubmitButton() {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 20,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        child: SafeArea(
          child: ElevatedButton(
            onPressed: _submitting ? null : _submit,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4F46E5),
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: _submitting
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(Colors.white),
                    ),
                  )
                : const Text(
                    'Submit for Approval',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

// ========== CUSTOM WIDGETS ==========

class _GlassCard extends StatelessWidget {
  final Widget child;
  const _GlassCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFF4F46E5).withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: const Color(0xFF4F46E5), size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF0F172A),
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade600,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CustomTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;
  final int maxLines;

  const _CustomTextField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.keyboardType,
    this.validator,
    this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: Color(0xFF334155),
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          validator: validator,
          maxLines: maxLines,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(
              color: Colors.grey.shade400,
              fontWeight: FontWeight.w600,
            ),
            prefixIcon: Icon(icon, color: const Color(0xFF4F46E5), size: 20),
            filled: true,
            fillColor: const Color(0xFF4F46E5).withOpacity(0.05),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: Colors.grey.shade200, width: 1.5),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFF4F46E5), width: 2),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(
                color: Color(0xFFEF4444),
                width: 1.5,
              ),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
          ),
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
      ],
    );
  }
}

class _CustomDropdown extends StatelessWidget {
  final String label;
  final String value;
  final List<String> items;
  final Function(String) onChanged;
  final String Function(String)? itemLabel;

  const _CustomDropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    this.itemLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: Color(0xFF334155),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: const Color(0xFF4F46E5).withOpacity(0.05),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.grey.shade200, width: 1.5),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isExpanded: true,
              icon: const Icon(
                Icons.arrow_drop_down_rounded,
                color: Color(0xFF4F46E5),
              ),
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
                color: Color(0xFF0F172A),
              ),
              items: items.map((item) {
                return DropdownMenuItem(
                  value: item,
                  child: Text(itemLabel?.call(item) ?? item),
                );
              }).toList(),
              onChanged: (v) => v != null ? onChanged(v) : null,
            ),
          ),
        ),
      ],
    );
  }
}

class _AmenityCheckbox extends StatelessWidget {
  final bool value;
  final String title;
  final IconData icon;
  final Function(bool?) onChanged;

  const _AmenityCheckbox({
    required this.value,
    required this.title,
    required this.icon,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: value
              ? const Color(0xFF4F46E5).withOpacity(0.08)
              : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: value ? const Color(0xFF4F46E5) : Colors.grey.shade300,
            width: 2,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: value ? const Color(0xFF4F46E5) : Colors.white,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: value ? const Color(0xFF4F46E5) : Colors.grey.shade400,
                  width: 2,
                ),
              ),
              child: value
                  ? const Icon(
                      Icons.check_rounded,
                      color: Colors.white,
                      size: 16,
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Icon(
              icon,
              color: value ? const Color(0xFF4F46E5) : Colors.grey.shade600,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: value ? const Color(0xFF0F172A) : Colors.grey.shade700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SpacePhotoTile extends StatelessWidget {
  final File image;
  final int index;
  final VoidCallback onRemove;

  const _SpacePhotoTile({
    required this.image,
    required this.index,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final width = (MediaQuery.of(context).size.width - 62) / 3;

    return Container(
      width: width,
      height: width,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF22C55E), width: 2),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.file(image, fit: BoxFit.cover),
          ),
          Positioned(
            top: 6,
            right: 6,
            child: GestureDetector(
              onTap: onRemove,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  color: Color(0xFFEF4444),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.close_rounded,
                  color: Colors.white,
                  size: 14,
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 6,
            left: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '#$index',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CheckboxTile extends StatelessWidget {
  final bool value;
  final String title;
  final Function(bool?) onChanged;

  const _CheckboxTile({
    required this.value,
    required this.title,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: value
              ? const Color(0xFF4F46E5).withOpacity(0.08)
              : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: value ? const Color(0xFF4F46E5) : Colors.grey.shade300,
            width: 2,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: value ? const Color(0xFF4F46E5) : Colors.white,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: value ? const Color(0xFF4F46E5) : Colors.grey.shade400,
                  width: 2,
                ),
              ),
              child: value
                  ? const Icon(
                      Icons.check_rounded,
                      color: Colors.white,
                      size: 16,
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: value ? const Color(0xFF0F172A) : Colors.grey.shade700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
