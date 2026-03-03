import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

class ManageParkingSpaceScreen extends StatefulWidget {
  final String spaceId;
  const ManageParkingSpaceScreen({super.key, required this.spaceId});

  @override
  State<ManageParkingSpaceScreen> createState() =>
      _ManageParkingSpaceScreenState();
}

class _ManageParkingSpaceScreenState extends State<ManageParkingSpaceScreen> {
  final _picker = ImagePicker();
  bool _uploading = false;

  // ========== EDIT LOCATION ==========
  Future<void> _editLocation(Map<String, dynamic> data) async {
    final titleCtrl = TextEditingController(text: data['title'] ?? '');
    final postcodeCtrl = TextEditingController(text: data['postcode'] ?? '');
    final areaCtrl = TextEditingController(
      text: data['approxArea'] ?? data['approx_area'] ?? data['area'] ?? '',
    );
    final addressCtrl = TextEditingController(
      text: data['exactAddress'] ?? data['exact_address'] ?? '',
    );

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Edit Location',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleCtrl,
                decoration: const InputDecoration(
                  labelText: 'Space Title',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: postcodeCtrl,
                decoration: const InputDecoration(
                  labelText: 'Postcode',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: areaCtrl,
                decoration: const InputDecoration(
                  labelText: 'Area',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: addressCtrl,
                decoration: const InputDecoration(
                  labelText: 'Exact Address',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4F46E5),
            ),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result == true) {
      await FirebaseFirestore.instance
          .collection('parking_spaces')
          .doc(widget.spaceId)
          .update({
            'title': titleCtrl.text.trim(),
            'postcode': postcodeCtrl.text.trim(),
            'approxArea': areaCtrl.text.trim(),
            'exactAddress': addressCtrl.text.trim(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
      _showSnackBar('Location updated successfully');
    }
  }

  // ========== EDIT SPACE DETAILS ==========
  Future<void> _editSpaceDetails(Map<String, dynamic> data) async {
    String spaceType =
        data['spaceType'] ?? data['space_type'] ?? data['type'] ?? 'driveway';
    String size = data['size'] ?? data['space_size'] ?? 'medium';
    final rateCtrl = TextEditingController(
      text: (data['hourlyRate'] ?? data['hourly_rate_gbp'] ?? 0.0).toString(),
    );
    String availability = data['availability'] ?? '24/7';

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text(
            'Edit Space Details',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: spaceType,
                  decoration: const InputDecoration(
                    labelText: 'Space Type',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'driveway',
                      child: Text('Driveway'),
                    ),
                    DropdownMenuItem(
                      value: 'allocated_bay',
                      child: Text('Allocated Bay'),
                    ),
                    DropdownMenuItem(
                      value: 'underground',
                      child: Text('Underground'),
                    ),
                    DropdownMenuItem(value: 'gated', child: Text('Gated')),
                    DropdownMenuItem(
                      value: 'open_lot',
                      child: Text('Open Lot'),
                    ),
                  ],
                  onChanged: (v) => setState(() => spaceType = v!),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: size,
                  decoration: const InputDecoration(
                    labelText: 'Size',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'small', child: Text('Small')),
                    DropdownMenuItem(value: 'medium', child: Text('Medium')),
                    DropdownMenuItem(value: 'large', child: Text('Large')),
                  ],
                  onChanged: (v) => setState(() => size = v!),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: rateCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Hourly Rate (£)',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: availability,
                  decoration: const InputDecoration(
                    labelText: 'Availability',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: '24/7',
                      child: Text('24/7 (Always Available)'),
                    ),
                    DropdownMenuItem(
                      value: 'weekdays_only',
                      child: Text('Weekdays Only (Mon-Fri)'),
                    ),
                    DropdownMenuItem(
                      value: 'weekends_only',
                      child: Text('Weekends Only (Sat-Sun)'),
                    ),
                    DropdownMenuItem(
                      value: 'event_days_only',
                      child: Text('Event Days Only'),
                    ),
                  ],
                  onChanged: (v) => setState(() => availability = v!),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4F46E5),
              ),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    if (result == true) {
      await FirebaseFirestore.instance
          .collection('parking_spaces')
          .doc(widget.spaceId)
          .update({
            'spaceType': spaceType,
            'size': size,
            'hourlyRate': double.tryParse(rateCtrl.text.trim()) ?? 0.0,
            'availability': availability,
            'updatedAt': FieldValue.serverTimestamp(),
          });
      _showSnackBar('Space details updated successfully');
    }
  }

  // ========== EDIT AMENITIES ==========
  Future<void> _editAmenities(Map<String, dynamic> data) async {
    final amenities = data['amenities'] as Map<String, dynamic>? ?? {};
    bool isCovered = amenities['covered'] ?? false;
    bool hasEVCharging = amenities['evCharging'] ?? false;
    bool hasCCTV = amenities['cctv'] ?? false;
    bool hasDisabledAccess = amenities['disabledAccess'] ?? false;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text(
            'Edit Amenities',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CheckboxListTile(
                title: const Text('Covered/Sheltered'),
                value: isCovered,
                onChanged: (v) => setState(() => isCovered = v ?? false),
              ),
              CheckboxListTile(
                title: const Text('EV Charging'),
                value: hasEVCharging,
                onChanged: (v) => setState(() => hasEVCharging = v ?? false),
              ),
              CheckboxListTile(
                title: const Text('CCTV/Security'),
                value: hasCCTV,
                onChanged: (v) => setState(() => hasCCTV = v ?? false),
              ),
              CheckboxListTile(
                title: const Text('Disabled Access'),
                value: hasDisabledAccess,
                onChanged: (v) =>
                    setState(() => hasDisabledAccess = v ?? false),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4F46E5),
              ),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    if (result == true) {
      await FirebaseFirestore.instance
          .collection('parking_spaces')
          .doc(widget.spaceId)
          .update({
            'amenities': {
              'covered': isCovered,
              'evCharging': hasEVCharging,
              'cctv': hasCCTV,
              'disabledAccess': hasDisabledAccess,
            },
            'updatedAt': FieldValue.serverTimestamp(),
          });
      _showSnackBar('Amenities updated successfully');
    }
  }

  // ========== EDIT ADDITIONAL INFO ==========
  Future<void> _editAdditionalInfo(Map<String, dynamic> data) async {
    final accessCtrl = TextEditingController(
      text: data['accessInstructions'] ?? '',
    );
    final restrictionsCtrl = TextEditingController(
      text: data['vehicleRestrictions'] ?? '',
    );

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Edit Additional Info',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: accessCtrl,
                decoration: const InputDecoration(
                  labelText: 'Access Instructions',
                  border: OutlineInputBorder(),
                  hintText: 'e.g., Gate code 1234, Enter from side entrance',
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: restrictionsCtrl,
                decoration: const InputDecoration(
                  labelText: 'Vehicle Restrictions',
                  border: OutlineInputBorder(),
                  hintText: 'e.g., Max height 2.1m, No commercial vehicles',
                ),
                maxLines: 2,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4F46E5),
            ),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result == true) {
      await FirebaseFirestore.instance
          .collection('parking_spaces')
          .doc(widget.spaceId)
          .update({
            'accessInstructions': accessCtrl.text.trim(),
            'vehicleRestrictions': restrictionsCtrl.text.trim(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
      _showSnackBar('Additional info updated successfully');
    }
  }

  // ========== ADD PHOTO ==========
  Future<void> _addPhoto() async {
    try {
      final source = await showModalBottomSheet<ImageSource>(
        context: context,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (context) => SafeArea(
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
                leading: const Icon(Icons.camera_alt, color: Color(0xFF4F46E5)),
                title: const Text(
                  'Take Photo',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                onTap: () => Navigator.pop(context, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(
                  Icons.photo_library,
                  color: Color(0xFF4F46E5),
                ),
                title: const Text(
                  'Choose from Gallery',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                onTap: () => Navigator.pop(context, ImageSource.gallery),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      );

      if (source == null) return;

      final XFile? pickedFile = await _picker.pickImage(
        source: source,
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );

      if (pickedFile == null) return;

      setState(() => _uploading = true);

      final uid = FirebaseAuth.instance.currentUser!.uid;
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final ref = FirebaseStorage.instance.ref().child(
        'parking_spaces/$uid/space_${timestamp}_${DateTime.now().microsecond}.jpg',
      );

      await ref.putFile(File(pickedFile.path));
      final url = await ref.getDownloadURL();

      final doc = await FirebaseFirestore.instance
          .collection('parking_spaces')
          .doc(widget.spaceId)
          .get();
      final currentPhotos = List<String>.from(doc.data()?['photoUrls'] ?? []);
      currentPhotos.add(url);

      await FirebaseFirestore.instance
          .collection('parking_spaces')
          .doc(widget.spaceId)
          .update({
            'photoUrls': currentPhotos,
            'updatedAt': FieldValue.serverTimestamp(),
          });

      _showSnackBar('Photo added successfully');
    } catch (e) {
      _showSnackBar('Failed to add photo: $e', isError: true);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  // ========== DELETE PHOTO ==========
  Future<void> _deletePhoto(String photoUrl, List photoUrls) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Delete Photo',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        content: const Text('Are you sure you want to delete this photo?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final updatedPhotos = List<String>.from(photoUrls)..remove(photoUrl);
      await FirebaseFirestore.instance
          .collection('parking_spaces')
          .doc(widget.spaceId)
          .update({
            'photoUrls': updatedPhotos,
            'updatedAt': FieldValue.serverTimestamp(),
          });
      _showSnackBar('Photo deleted successfully');
    }
  }

  // ========== DELETE SPACE ==========
  Future<void> _deleteSpace() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Delete Parking Space',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        content: const Text(
          'Are you sure you want to delete this parking space?\n\n'
          'This action cannot be undone. The space will be permanently removed from the database.',
          style: TextStyle(height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
            ),
            child: const Text('Delete Permanently'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await FirebaseFirestore.instance
            .collection('parking_spaces')
            .doc(widget.spaceId)
            .delete();
        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Parking space deleted successfully'),
              backgroundColor: Color(0xFF10B981),
            ),
          );
        }
      } catch (e) {
        _showSnackBar('Failed to delete: $e', isError: true);
      }
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError
              ? const Color(0xFFEF4444)
              : const Color(0xFF10B981),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final ref = FirebaseFirestore.instance
        .collection('parking_spaces')
        .doc(widget.spaceId);

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FF),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: ref.snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(
                strokeWidth: 3,
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF6366F1)),
              ),
            );
          }
          if (!snap.hasData || !snap.data!.exists) {
            return const Center(child: Text('Space not found'));
          }

          final data = snap.data!.data()!;

          // Support both old and new field names
          final title = (data['title'] ?? 'Parking space').toString();
          final postcode = (data['postcode'] ?? '').toString();
          final area =
              ((data['approxArea'] ?? data['approx_area'] ?? data['area']) ??
                      '')
                  .toString();
          final exactAddress =
              (data['exactAddress'] ?? data['exact_address'] ?? '').toString();
          final spaceType =
              ((data['spaceType'] ?? data['space_type'] ?? data['type']) ??
                      'driveway')
                  .toString();
          final size = ((data['size'] ?? data['space_size']) ?? 'medium')
              .toString();
          final hourlyRateValue =
              data['hourlyRate'] ??
              data['hourly_rate_gbp'] ??
              data['hourly_rate'];
          final hourlyRate = (hourlyRateValue is num)
              ? hourlyRateValue.toDouble()
              : 0.0;
          final status = ((data['status'] ?? data['status_lc']) ?? 'pending')
              .toString();
          final approved = data['approved'] ?? false;
          final availability = (data['availability'] ?? '24/7').toString();

          // Amenities
          final amenities = data['amenities'] as Map<String, dynamic>? ?? {};
          final isCovered = amenities['covered'] ?? false;
          final hasEVCharging = amenities['evCharging'] ?? false;
          final hasCCTV = amenities['cctv'] ?? false;
          final hasDisabledAccess = amenities['disabledAccess'] ?? false;

          // Additional info
          final accessInstructions = (data['accessInstructions'] ?? '')
              .toString();
          final vehicleRestrictions = (data['vehicleRestrictions'] ?? '')
              .toString();

          // Photos
          final photoUrls =
              (data['photoUrls'] ?? data['photo_urls'] ?? []) as List;

          final isApproved =
              (status.toLowerCase() == 'approved' && approved == true);

          return Stack(
            children: [
              CustomScrollView(
                physics: const BouncingScrollPhysics(),
                slivers: [
                  _buildAppBar(title, isApproved, status),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 100),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate([
                        // Space Photos
                        _buildPhotosSection(photoUrls),
                        const SizedBox(height: 20),

                        // Location
                        _buildLocationSection(
                          data: data,
                          title: title,
                          postcode: postcode,
                          area: area,
                          exactAddress: exactAddress,
                        ),
                        const SizedBox(height: 20),

                        // Space Details
                        _buildSpaceDetailsSection(
                          data: data,
                          spaceType: spaceType,
                          size: size,
                          hourlyRate: hourlyRate,
                          availability: availability,
                        ),
                        const SizedBox(height: 20),

                        // Amenities
                        if (isCovered ||
                            hasEVCharging ||
                            hasCCTV ||
                            hasDisabledAccess)
                          _buildAmenitiesSection(
                            data: data,
                            isCovered: isCovered,
                            hasEVCharging: hasEVCharging,
                            hasCCTV: hasCCTV,
                            hasDisabledAccess: hasDisabledAccess,
                          ),
                        if (isCovered ||
                            hasEVCharging ||
                            hasCCTV ||
                            hasDisabledAccess)
                          const SizedBox(height: 20),

                        // Additional Info
                        _buildAdditionalInfoSection(
                          data: data,
                          accessInstructions: accessInstructions,
                          vehicleRestrictions: vehicleRestrictions,
                        ),
                        const SizedBox(height: 20),

                        // Delete Button
                        _buildDeleteButton(),
                      ]),
                    ),
                  ),
                ],
              ),
              if (_uploading)
                Container(
                  color: Colors.black54,
                  child: const Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation(Colors.white),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildAppBar(String title, bool isApproved, String status) {
    return SliverAppBar(
      pinned: true,
      stretch: true,
      expandedHeight: 200,
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
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.settings_rounded,
                          color: Colors.white,
                          size: 32,
                        ),
                        const SizedBox(width: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: isApproved
                                ? const Color(0xFF10B981)
                                : const Color(0xFFF59E0B),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            status.toUpperCase(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Manage Space',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      title,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.9),
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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

  Widget _buildPhotosSection(List photoUrls) {
    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _SectionHeader(
                  icon: Icons.photo_camera_rounded,
                  title: 'Space Photos',
                  subtitle:
                      '${photoUrls.length} photo${photoUrls.length != 1 ? 's' : ''}',
                ),
              ),
              ElevatedButton.icon(
                onPressed: _addPhoto,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4F46E5),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                ),
                icon: const Icon(Icons.add_photo_alternate_rounded, size: 18),
                label: const Text(
                  'Add',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                ),
              ),
            ],
          ),
          if (photoUrls.isNotEmpty) const SizedBox(height: 16),
          if (photoUrls.isNotEmpty)
            SizedBox(
              height: 120,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: photoUrls.length,
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (context, index) {
                  return Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          width: 120,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Image.network(
                            photoUrls[index].toString(),
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => const Center(
                              child: Icon(Icons.broken_image_rounded, size: 40),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 6,
                        right: 6,
                        child: GestureDetector(
                          onTap: () => _deletePhoto(
                            photoUrls[index].toString(),
                            photoUrls,
                          ),
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
                    ],
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLocationSection({
    required Map<String, dynamic> data,
    required String title,
    required String postcode,
    required String area,
    required String exactAddress,
  }) {
    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _SectionHeader(
                  icon: Icons.location_on_rounded,
                  title: 'Location',
                  subtitle: 'Address details',
                ),
              ),
              IconButton(
                onPressed: () => _editLocation(data),
                icon: const Icon(Icons.edit_rounded, color: Color(0xFF4F46E5)),
                tooltip: 'Edit Location',
              ),
            ],
          ),
          const SizedBox(height: 16),
          _InfoRow(label: 'Title', value: title, icon: Icons.title_rounded),
          const SizedBox(height: 12),
          _InfoRow(
            label: 'Postcode',
            value: postcode,
            icon: Icons.pin_drop_rounded,
          ),
          const SizedBox(height: 12),
          _InfoRow(label: 'Area', value: area, icon: Icons.map_rounded),
          const SizedBox(height: 12),
          _InfoRow(
            label: 'Exact Address',
            value: exactAddress.isNotEmpty ? exactAddress : 'Not provided',
            icon: Icons.home_rounded,
          ),
        ],
      ),
    );
  }

  Widget _buildSpaceDetailsSection({
    required Map<String, dynamic> data,
    required String spaceType,
    required String size,
    required double hourlyRate,
    required String availability,
  }) {
    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _SectionHeader(
                  icon: Icons.local_parking_rounded,
                  title: 'Space Details',
                  subtitle: 'Type, size, and pricing',
                ),
              ),
              IconButton(
                onPressed: () => _editSpaceDetails(data),
                icon: const Icon(Icons.edit_rounded, color: Color(0xFF4F46E5)),
                tooltip: 'Edit Details',
              ),
            ],
          ),
          const SizedBox(height: 16),
          _InfoRow(
            label: 'Type',
            value: spaceType.replaceAll('_', ' ').toUpperCase(),
            icon: Icons.category_rounded,
          ),
          const SizedBox(height: 12),
          _InfoRow(
            label: 'Size',
            value: size[0].toUpperCase() + size.substring(1),
            icon: Icons.straighten_rounded,
          ),
          const SizedBox(height: 12),
          _InfoRow(
            label: 'Hourly Rate',
            value: '£${hourlyRate.toStringAsFixed(2)}/hour',
            icon: Icons.attach_money_rounded,
            valueColor: const Color(0xFF10B981),
          ),
          const SizedBox(height: 12),
          _InfoRow(
            label: 'Availability',
            value: _formatAvailability(availability),
            icon: Icons.access_time_rounded,
          ),
        ],
      ),
    );
  }

  String _formatAvailability(String availability) {
    switch (availability) {
      case '24/7':
        return '24/7 (Always Available)';
      case 'weekdays_only':
        return 'Weekdays Only (Mon-Fri)';
      case 'weekends_only':
        return 'Weekends Only (Sat-Sun)';
      case 'event_days_only':
        return 'Event Days Only';
      default:
        return availability;
    }
  }

  Widget _buildAmenitiesSection({
    required Map<String, dynamic> data,
    required bool isCovered,
    required bool hasEVCharging,
    required bool hasCCTV,
    required bool hasDisabledAccess,
  }) {
    final amenitiesList = [
      if (isCovered)
        {'icon': Icons.roofing_rounded, 'label': 'Covered/Sheltered'},
      if (hasEVCharging)
        {'icon': Icons.ev_station_rounded, 'label': 'EV Charging'},
      if (hasCCTV) {'icon': Icons.videocam_rounded, 'label': 'CCTV/Security'},
      if (hasDisabledAccess)
        {'icon': Icons.accessible_rounded, 'label': 'Disabled Access'},
    ];

    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _SectionHeader(
                  icon: Icons.star_rounded,
                  title: 'Amenities',
                  subtitle:
                      '${amenitiesList.length} feature${amenitiesList.length != 1 ? 's' : ''}',
                ),
              ),
              IconButton(
                onPressed: () => _editAmenities(data),
                icon: const Icon(Icons.edit_rounded, color: Color(0xFF4F46E5)),
                tooltip: 'Edit Amenities',
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: amenitiesList.map((amenity) {
              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF4F46E5).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xFF4F46E5).withOpacity(0.3),
                    width: 1.5,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      amenity['icon'] as IconData,
                      color: const Color(0xFF4F46E5),
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      amenity['label'] as String,
                      style: const TextStyle(
                        color: Color(0xFF4F46E5),
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildAdditionalInfoSection({
    required Map<String, dynamic> data,
    required String accessInstructions,
    required String vehicleRestrictions,
  }) {
    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _SectionHeader(
                  icon: Icons.info_outline_rounded,
                  title: 'Additional Information',
                  subtitle: 'Access and restrictions',
                ),
              ),
              IconButton(
                onPressed: () => _editAdditionalInfo(data),
                icon: const Icon(Icons.edit_rounded, color: Color(0xFF4F46E5)),
                tooltip: 'Edit Info',
              ),
            ],
          ),
          const SizedBox(height: 16),
          _InfoRow(
            label: 'Access Instructions',
            value: accessInstructions.isNotEmpty
                ? accessInstructions
                : 'Not provided',
            icon: Icons.key_rounded,
          ),
          const SizedBox(height: 12),
          _InfoRow(
            label: 'Vehicle Restrictions',
            value: vehicleRestrictions.isNotEmpty
                ? vehicleRestrictions
                : 'None',
            icon: Icons.local_shipping_rounded,
          ),
        ],
      ),
    );
  }

  Widget _buildDeleteButton() {
    return _GlassCard(
      child: InkWell(
        onTap: _deleteSpace,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.delete_forever_rounded,
                  color: Color(0xFFEF4444),
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Text(
                  'Delete Parking Space',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFFEF4444),
                  ),
                ),
              ),
              const Icon(
                Icons.arrow_forward_ios_rounded,
                color: Color(0xFFEF4444),
                size: 18,
              ),
            ],
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

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color? valueColor;

  const _InfoRow({
    required this.label,
    required this.value,
    required this.icon,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: const Color(0xFF94A3B8), size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: valueColor ?? const Color(0xFF0F172A),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
