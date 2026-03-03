import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

class ParkingProviderApplyScreen extends StatefulWidget {
  const ParkingProviderApplyScreen({super.key});

  @override
  State<ParkingProviderApplyScreen> createState() =>
      _ParkingProviderApplyScreenState();
}

class _ParkingProviderApplyScreenState
    extends State<ParkingProviderApplyScreen> {
  final _formKey = GlobalKey<FormState>();
  final _picker = ImagePicker();

  // Personal details
  final _fullNameCtrl = TextEditingController();
  final _dobCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _licenseNumberCtrl = TextEditingController();
  final _licenseExpiryCtrl = TextEditingController();

  // ID verification photos
  File? _licenseFrontImage;
  File? _licenseBackImage;
  File? _selfieImage;

  // Confirmations
  bool _authorityConfirmed = false;
  bool _termsAccepted = false;

  // Loading states
  bool _submitting = false;
  bool _uploading = false;
  double _uploadProgress = 0.0;

  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    if (user?.phoneNumber != null && user!.phoneNumber!.isNotEmpty) {
      _phoneCtrl.text = user.phoneNumber!;
    }
  }

  @override
  void dispose() {
    _fullNameCtrl.dispose();
    _dobCtrl.dispose();
    _phoneCtrl.dispose();
    _licenseNumberCtrl.dispose();
    _licenseExpiryCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source, String type) async {
    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: source,
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );

      if (pickedFile != null) {
        setState(() {
          if (type == 'license_front') {
            _licenseFrontImage = File(pickedFile.path);
          } else if (type == 'license_back') {
            _licenseBackImage = File(pickedFile.path);
          } else if (type == 'selfie') {
            _selfieImage = File(pickedFile.path);
          }
        });
      }
    } catch (e) {
      _snack('Failed to pick image: $e');
    }
  }

  void _showImageSourceDialog(String type) {
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
                  _pickImage(ImageSource.camera, type);
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
                  _pickImage(ImageSource.gallery, type);
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

    // Validate images
    if (_licenseFrontImage == null) {
      _snack('Please upload driver\'s license front photo');
      return;
    }
    if (_licenseBackImage == null) {
      _snack('Please upload driver\'s license back photo');
      return;
    }
    if (_selfieImage == null) {
      _snack('Please upload selfie verification photo');
      return;
    }

    if (!_authorityConfirmed || !_termsAccepted) {
      _snack('Please confirm all requirements and accept terms');
      return;
    }

    setState(() {
      _submitting = true;
      _uploading = true;
    });

    try {
      final uid = user.uid;
      final timestamp = DateTime.now().millisecondsSinceEpoch;

      // Upload ID photos
      final licenseFrontUrl = await _uploadImage(
        _licenseFrontImage!,
        'parking_providers/$uid/license_front_$timestamp.jpg',
      );

      final licenseBackUrl = await _uploadImage(
        _licenseBackImage!,
        'parking_providers/$uid/license_back_$timestamp.jpg',
      );

      final selfieUrl = await _uploadImage(
        _selfieImage!,
        'parking_providers/$uid/selfie_$timestamp.jpg',
      );

      if (licenseFrontUrl == null ||
          licenseBackUrl == null ||
          selfieUrl == null) {
        throw Exception('Failed to upload photos');
      }

      setState(() => _uploading = false);

      // Save application to Firestore
      await FirebaseFirestore.instance
          .collection('parking_provider_applications')
          .doc(uid)
          .set({
            'provider_uid': uid,
            'full_name': _fullNameCtrl.text.trim(),
            'dob': _dobCtrl.text.trim(),
            'email': user.email ?? '',
            'phone': _phoneCtrl.text.trim(),
            'license_number': _licenseNumberCtrl.text.trim(),
            'license_expiry': _licenseExpiryCtrl.text.trim(),
            'license_front_url': licenseFrontUrl,
            'license_back_url': licenseBackUrl,
            'selfie_url': selfieUrl,
            'status': 'pending',
            'submitted_at': FieldValue.serverTimestamp(),
            'updated_at': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));

      // Update user document
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'parkingProviderStatus': 'pending',
        'name': _fullNameCtrl.text.trim(),
        'phone': _phoneCtrl.text.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;

      _snack('Application submitted! Pending manual review.');
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
                    _buildPersonalDetailsSection(),
                    const SizedBox(height: 20),
                    _buildIDVerificationSection(),
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
                    Color(0xFF0EA5E9),
                    Color(0xFF6366F1),
                    Color(0xFF8B5CF6),
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
                      Icons.verified_user_rounded,
                      color: Colors.white,
                      size: 40,
                    ),
                    SizedBox(height: 12),
                    Text(
                      'Become a Provider',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.5,
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'Complete verification to list parking spaces',
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
                  'Verification Required',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Once approved, you can add parking spaces from your provider dashboard',
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

  Widget _buildPersonalDetailsSection() {
    return _GlassCard(
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionHeader(
              icon: Icons.person_rounded,
              title: 'Personal Details',
              subtitle: 'Required for identity verification',
            ),
            const SizedBox(height: 16),
            _CustomTextField(
              controller: _fullNameCtrl,
              label: 'Full Name',
              hint: 'As shown on driver\'s license',
              icon: Icons.badge_rounded,
              validator: (v) => (v == null || v.trim().length < 2)
                  ? 'Enter your full name'
                  : null,
            ),
            const SizedBox(height: 14),
            _CustomTextField(
              controller: _dobCtrl,
              label: 'Date of Birth',
              hint: 'DD/MM/YYYY',
              icon: Icons.cake_rounded,
              validator: (v) => (v == null || v.trim().length < 8)
                  ? 'Enter your date of birth'
                  : null,
            ),
            const SizedBox(height: 14),
            _CustomTextField(
              controller: _phoneCtrl,
              label: 'Phone Number',
              hint: '+44 7XXX XXXXXX',
              icon: Icons.phone_rounded,
              keyboardType: TextInputType.phone,
              validator: (v) => (v == null || v.trim().length < 8)
                  ? 'Enter a valid phone number'
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIDVerificationSection() {
    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            icon: Icons.verified_user_rounded,
            title: 'ID Verification',
            subtitle: 'Driver\'s license + selfie required',
          ),
          const SizedBox(height: 16),
          _CustomTextField(
            controller: _licenseNumberCtrl,
            label: 'License Number',
            hint: 'e.g., MORGA657054SM9IJ',
            icon: Icons.confirmation_number_rounded,
            validator: (v) => (v == null || v.trim().length < 4)
                ? 'Enter license number'
                : null,
          ),
          const SizedBox(height: 14),
          _CustomTextField(
            controller: _licenseExpiryCtrl,
            label: 'License Expiry Date',
            hint: 'DD/MM/YYYY',
            icon: Icons.calendar_today_rounded,
            validator: (v) =>
                (v == null || v.trim().length < 8) ? 'Enter expiry date' : null,
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _ImageUploadBox(
                  title: 'License Front',
                  subtitle: 'Clear photo',
                  image: _licenseFrontImage,
                  onTap: () => _showImageSourceDialog('license_front'),
                  onRemove: () => setState(() => _licenseFrontImage = null),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ImageUploadBox(
                  title: 'License Back',
                  subtitle: 'Clear photo',
                  image: _licenseBackImage,
                  onTap: () => _showImageSourceDialog('license_back'),
                  onRemove: () => setState(() => _licenseBackImage = null),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _ImageUploadBox(
            title: 'Selfie Verification',
            subtitle: 'Hold your license next to your face',
            image: _selfieImage,
            onTap: () => _showImageSourceDialog('selfie'),
            onRemove: () => setState(() => _selfieImage = null),
            fullWidth: true,
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
            title:
                'I confirm I will provide accurate information about parking spaces I list',
            onChanged: (v) => setState(() => _authorityConfirmed = v ?? false),
          ),
          const SizedBox(height: 10),
          _CheckboxTile(
            value: _termsAccepted,
            title:
                'I accept the terms and conditions and agree to manual verification',
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
                'Uploading verification photos...',
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
                    'Submit Application',
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

  const _CustomTextField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.keyboardType,
    this.validator,
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

class _ImageUploadBox extends StatelessWidget {
  final String title;
  final String subtitle;
  final File? image;
  final VoidCallback onTap;
  final VoidCallback? onRemove;
  final bool fullWidth;

  const _ImageUploadBox({
    required this.title,
    required this.subtitle,
    required this.image,
    required this.onTap,
    this.onRemove,
    this.fullWidth = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        height: fullWidth ? 140 : 160,
        decoration: BoxDecoration(
          color: image != null
              ? Colors.grey.shade100
              : const Color(0xFF4F46E5).withOpacity(0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: image != null
                ? const Color(0xFF22C55E)
                : Colors.grey.shade300,
            width: 2,
          ),
        ),
        child: image != null
            ? Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Image.file(image!, fit: BoxFit.cover),
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: GestureDetector(
                      onTap: onRemove,
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: const BoxDecoration(
                          color: Color(0xFFEF4444),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.close_rounded,
                          color: Colors.white,
                          size: 16,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF22C55E),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.check_circle_rounded,
                            color: Colors.white,
                            size: 14,
                          ),
                          SizedBox(width: 4),
                          Text(
                            'Uploaded',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.add_photo_alternate_rounded,
                    color: Color(0xFF4F46E5),
                    size: 36,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      subtitle,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ),
                ],
              ),
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
