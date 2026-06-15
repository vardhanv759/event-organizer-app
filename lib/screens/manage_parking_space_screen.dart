import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:qr_flutter/qr_flutter.dart';

class ManageParkingSpaceScreen extends StatefulWidget {
  final String spaceId;
  const ManageParkingSpaceScreen({super.key, required this.spaceId});

  @override
  State<ManageParkingSpaceScreen> createState() =>
      _ManageParkingSpaceScreenState();
}

class _ManageParkingSpaceScreenState extends State<ManageParkingSpaceScreen>
    with SingleTickerProviderStateMixin {
  final _picker = ImagePicker();
  bool _uploading = false;
  late TabController _tabController;
  int _currentPhotoIndex = 0;
  final PageController _photoPageController = PageController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _photoPageController.dispose();
    super.dispose();
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
            borderRadius: BorderRadius.circular(20),
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
                  value: spaceType,
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
                  value: size,
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
                  value: availability,
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
                backgroundColor: const Color.fromARGB(255, 252, 252, 254),
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
      _showSnackBar('Space details updated');
    }
  }

  // ========== EDIT AMENITIES ==========
  Future<void> _editAmenities(Map<String, dynamic> data) async {
    bool cctv = data['hasCCTV'] ?? data['has_cctv'] ?? false;
    bool lighting = data['hasLighting'] ?? data['has_lighting'] ?? false;
    bool covered = data['isCovered'] ?? data['is_covered'] ?? false;
    bool evCharging = data['hasEVCharging'] ?? data['has_ev_charging'] ?? false;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text(
            'Edit Amenities',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SwitchListTile(
                title: const Text('CCTV'),
                value: cctv,
                onChanged: (v) => setState(() => cctv = v),
              ),
              SwitchListTile(
                title: const Text('Lighting'),
                value: lighting,
                onChanged: (v) => setState(() => lighting = v),
              ),
              SwitchListTile(
                title: const Text('Covered'),
                value: covered,
                onChanged: (v) => setState(() => covered = v),
              ),
              SwitchListTile(
                title: const Text('EV Charging'),
                value: evCharging,
                onChanged: (v) => setState(() => evCharging = v),
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
                backgroundColor: const Color.fromARGB(255, 247, 247, 249),
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
            'hasCCTV': cctv,
            'hasLighting': lighting,
            'isCovered': covered,
            'hasEVCharging': evCharging,
            'updatedAt': FieldValue.serverTimestamp(),
          });
      _showSnackBar('Amenities updated');
    }
  }

  // ========== EDIT ADDITIONAL INFO ==========
  Future<void> _editAdditionalInfo(Map<String, dynamic> data) async {
    final accessCtrl = TextEditingController(
      text: data['accessInstructions'] ?? data['access_instructions'] ?? '',
    );
    final restrictionsCtrl = TextEditingController(
      text: data['vehicleRestrictions'] ?? data['vehicle_restrictions'] ?? '',
    );

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Edit Additional Info',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: accessCtrl,
              decoration: const InputDecoration(
                labelText: 'Access Instructions',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: restrictionsCtrl,
              decoration: const InputDecoration(
                labelText: 'Vehicle Restrictions',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
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
              backgroundColor: const Color.fromARGB(255, 242, 242, 243),
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
      _showSnackBar('Additional info updated');
    }
  }

  // ========== ADD PHOTO ==========
  Future<void> _addPhoto() async {
    final pickedFile = await _picker.pickImage(source: ImageSource.gallery);
    if (pickedFile == null) return;

    setState(() => _uploading = true);
    try {
      final file = File(pickedFile.path);
      final storageRef = FirebaseStorage.instance.ref().child(
        'parking_spaces/${widget.spaceId}/${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await storageRef.putFile(file);
      final url = await storageRef.getDownloadURL();
      await FirebaseFirestore.instance
          .collection('parking_spaces')
          .doc(widget.spaceId)
          .update({
            'photoUrls': FieldValue.arrayUnion([url]),
            'updatedAt': FieldValue.serverTimestamp(),
          });
      _showSnackBar('Photo added');
    } catch (e) {
      _showSnackBar('Error: $e');
    } finally {
      setState(() => _uploading = false);
    }
  }

  // ========== DELETE PHOTO ==========
  Future<void> _deletePhoto(String url) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Delete Photo?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await FirebaseFirestore.instance
          .collection('parking_spaces')
          .doc(widget.spaceId)
          .update({
            'photoUrls': FieldValue.arrayRemove([url]),
            'updatedAt': FieldValue.serverTimestamp(),
          });
      _showSnackBar('Photo deleted');
    }
  }

  // ========== DELETE SPACE ==========
  Future<void> _deleteSpace() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Delete Space?',
          style: TextStyle(fontWeight: FontWeight.w900, color: Colors.red),
        ),
        content: const Text('This is permanent and cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete Forever'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await FirebaseFirestore.instance
          .collection('parking_spaces')
          .doc(widget.spaceId)
          .delete();
      if (mounted) Navigator.pop(context);
    }
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('parking_spaces')
          .doc(widget.spaceId)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Scaffold(
            body: Center(child: Text('Error: ${snapshot.error}')),
          );
        }
        if (!snapshot.hasData || !snapshot.data!.exists) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final data = snapshot.data!.data()!;
        final title = data['title'] ?? 'Untitled Space';
        final postcode = data['postcode'] ?? '';
        final area =
            data['approxArea'] ?? data['approx_area'] ?? data['area'] ?? '';
        final exactAddress =
            data['exactAddress'] ?? data['exact_address'] ?? '';
        final spaceType =
            data['spaceType'] ??
            data['space_type'] ??
            data['type'] ??
            'driveway';
        final size = data['size'] ?? data['space_size'] ?? 'medium';
        final hourlyRate =
            (data['hourlyRate'] ?? data['hourly_rate_gbp'] ?? 0.0) as num;
        final availability = data['availability'] ?? '24/7';
        final status = (data['status'] ?? 'pending').toString().toLowerCase();
        final isApproved = status == 'approved';
        final isActive = data['isActive'] ?? true;
        final List<dynamic> photoUrls = data['photoUrls'] ?? [];
        final hasCCTV = data['hasCCTV'] ?? data['has_cctv'] ?? false;
        final hasLighting =
            data['hasLighting'] ?? data['has_lighting'] ?? false;
        final isCovered = data['isCovered'] ?? data['is_covered'] ?? false;
        final hasEVCharging =
            data['hasEVCharging'] ?? data['has_ev_charging'] ?? false;
        final accessInstructions =
            data['accessInstructions'] ?? data['access_instructions'] ?? '';
        final vehicleRestrictions =
            data['vehicleRestrictions'] ?? data['vehicle_restrictions'] ?? '';

        // Analytics (mock data - replace with real)
        final totalViews = data['totalViews'] ?? 127;
        final totalBookings = data['totalBookings'] ?? 8;
        final totalEarnings = data['totalEarnings'] ?? 240.0;
        final rating = data['rating'] ?? 4.8;

        return Scaffold(
          backgroundColor: const Color(0xFFF8F9FF),
          body: CustomScrollView(
            slivers: [
              _buildHeroHeader(title, status, isApproved, isActive, photoUrls),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      // Analytics Dashboard
                      _buildAnalytics(
                        totalViews,
                        totalBookings,
                        totalEarnings,
                        rating,
                      ),
                      const SizedBox(height: 24),
                      // Tabs
                      _buildTabs(),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
              // Tab Content in Sliver
              SliverFillRemaining(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      // Details Tab
                      _buildDetailsTab(
                        data,
                        title,
                        postcode,
                        area,
                        exactAddress,
                        spaceType,
                        size,
                        hourlyRate.toDouble(),
                        availability,
                        hasCCTV,
                        hasLighting,
                        isCovered,
                        hasEVCharging,
                        accessInstructions,
                        vehicleRestrictions,
                      ),
                      // Photos Tab
                      _buildPhotosTab(photoUrls),
                      // Settings Tab
                      _buildSettingsTab(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeroHeader(
    String title,
    String status,
    bool isApproved,
    bool isActive,
    List photoUrls,
  ) {
    return SliverAppBar(
      expandedHeight: 280,
      pinned: true,
      backgroundColor: Colors.transparent,
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          fit: StackFit.expand,
          children: [
            if (photoUrls.isNotEmpty)
              PageView.builder(
                controller: _photoPageController,
                onPageChanged: (index) =>
                    setState(() => _currentPhotoIndex = index),
                itemCount: photoUrls.length,
                itemBuilder: (context, index) =>
                    Image.network(photoUrls[index], fit: BoxFit.cover),
              )
            else
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)],
                  ),
                ),
                child: const Center(
                  child: Icon(
                    Icons.local_parking,
                    size: 80,
                    color: Colors.white,
                  ),
                ),
              ),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.3),
                    Colors.black.withOpacity(0.7),
                  ],
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
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isApproved ? Icons.verified : Icons.pending,
                                color: Colors.white,
                                size: 16,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                status.toUpperCase(),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (!isActive)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.red,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.pause,
                                  color: Colors.white,
                                  size: 16,
                                ),
                                SizedBox(width: 6),
                                Text(
                                  'PAUSED',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        shadows: [
                          Shadow(color: Colors.black38, blurRadius: 10),
                        ],
                      ),
                      maxLines: 2,
                    ),
                    if (photoUrls.length > 1) ...[
                      const SizedBox(height: 12),
                      Row(
                        children: List.generate(
                          photoUrls.length,
                          (index) => Container(
                            margin: const EdgeInsets.only(right: 6),
                            width: index == _currentPhotoIndex ? 24 : 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: index == _currentPhotoIndex
                                  ? Colors.white
                                  : Colors.white.withOpacity(0.5),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnalytics(
    int views,
    int bookings,
    double earnings,
    double rating,
  ) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 14,
      crossAxisSpacing: 14,
      childAspectRatio: 1.5,
      children: [
        _AnalyticsCard(
          icon: Icons.visibility_rounded,
          label: 'Views',
          value: views.toString(),
          color: const Color(0xFF6366F1),
          trend: '+12%',
        ),
        _AnalyticsCard(
          icon: Icons.event_available_rounded,
          label: 'Bookings',
          value: bookings.toString(),
          color: const Color(0xFF10B981),
          trend: '+5',
        ),
        _AnalyticsCard(
          icon: Icons.payments_rounded,
          label: 'Earnings',
          value: '£${earnings.toStringAsFixed(0)}',
          color: const Color(0xFFF59E0B),
          trend: '+£48',
        ),
        _AnalyticsCard(
          icon: Icons.star_rounded,
          label: 'Rating',
          value: rating.toStringAsFixed(1),
          color: const Color(0xFFEF4444),
          trend: rating >= 4.5 ? 'Excellent' : 'Good',
        ),
      ],
    );
  }

  Widget _buildTabs() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: TabBar(
        controller: _tabController,
        labelColor: const Color.fromARGB(255, 166, 9, 239),
        unselectedLabelColor: const Color(0xFF64748B),
        indicator: const UnderlineTabIndicator(
          borderSide: BorderSide(color: Color(0xFF4F46E5), width: 4),
          insets: EdgeInsets.symmetric(horizontal: 32),
        ),
        indicatorPadding: const EdgeInsets.all(6),
        labelStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
        tabs: const [
          Tab(text: 'Details'),
          Tab(text: 'Photos'),
          Tab(text: 'Settings'),
        ],
      ),
    );
  }

  Widget _buildDetailsTab(
    Map<String, dynamic> data,
    String title,
    String postcode,
    String area,
    String exactAddress,
    String spaceType,
    String size,
    double hourlyRate,
    String availability,
    bool hasCCTV,
    bool hasLighting,
    bool isCovered,
    bool hasEVCharging,
    String accessInstructions,
    String vehicleRestrictions,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        children: [
          _buildLocationSection(title, postcode, area, exactAddress),
          const SizedBox(height: 16),
          _buildSpaceDetailsSection(
            data,
            spaceType,
            size,
            hourlyRate,
            availability,
          ),
          const SizedBox(height: 16),
          _buildAmenitiesSection(
            data,
            hasCCTV,
            hasLighting,
            isCovered,
            hasEVCharging,
          ),
          const SizedBox(height: 16),
          _buildAdditionalInfoSection(
            data,
            accessInstructions,
            vehicleRestrictions,
          ),
        ],
      ),
    );
  }

  Widget _buildLocationSection(
    String title,
    String postcode,
    String area,
    String exactAddress,
  ) {
    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            icon: Icons.location_on_rounded,
            title: 'Location',
            subtitle: 'Address details (read-only)',
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

  Widget _buildSpaceDetailsSection(
    Map<String, dynamic> data,
    String spaceType,
    String size,
    double hourlyRate,
    String availability,
  ) {
    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _SectionHeader(
                  icon: Icons.info_outline_rounded,
                  title: 'Space Details',
                  subtitle: 'Type, size, and pricing',
                ),
              ),
              IconButton(
                onPressed: () => _editSpaceDetails(data),
                icon: const Icon(Icons.edit_rounded, color: Color(0xFF4F46E5)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _InfoRow(
            label: 'Space Type',
            value: _formatSpaceType(spaceType),
            icon: Icons.local_parking_rounded,
          ),
          const SizedBox(height: 12),
          _InfoRow(
            label: 'Size',
            value: size.toUpperCase(),
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
            icon: Icons.schedule_rounded,
          ),
        ],
      ),
    );
  }

  Widget _buildAmenitiesSection(
    Map<String, dynamic> data,
    bool hasCCTV,
    bool hasLighting,
    bool isCovered,
    bool hasEVCharging,
  ) {
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
                  subtitle: 'Features and facilities',
                ),
              ),
              IconButton(
                onPressed: () => _editAmenities(data),
                icon: const Icon(Icons.edit_rounded, color: Color(0xFF4F46E5)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              if (hasCCTV) _amenityChip(Icons.videocam, 'CCTV'),
              if (hasLighting) _amenityChip(Icons.lightbulb, 'Lighting'),
              if (isCovered) _amenityChip(Icons.roofing, 'Covered'),
              if (hasEVCharging) _amenityChip(Icons.ev_station, 'EV Charging'),
              if (!hasCCTV && !hasLighting && !isCovered && !hasEVCharging)
                const Text(
                  'No amenities',
                  style: TextStyle(color: Colors.grey),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAdditionalInfoSection(
    Map<String, dynamic> data,
    String accessInstructions,
    String vehicleRestrictions,
  ) {
    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _SectionHeader(
                  icon: Icons.description_rounded,
                  title: 'Additional Info',
                  subtitle: 'Access and restrictions',
                ),
              ),
              IconButton(
                onPressed: () => _editAdditionalInfo(data),
                icon: const Icon(Icons.edit_rounded, color: Color(0xFF4F46E5)),
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

  Widget _buildPhotosTab(List photoUrls) {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 20),
      child: _GlassCard(
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: _SectionHeader(
                    icon: Icons.photo_camera_rounded,
                    title: 'Photos',
                    subtitle:
                        '${photoUrls.length} photo${photoUrls.length != 1 ? 's' : ''}',
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _uploading ? null : _addPhoto,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color.fromARGB(255, 248, 248, 250),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: _uploading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                        )
                      : const Icon(Icons.add_photo_alternate_rounded, size: 18),
                  label: Text(_uploading ? 'Uploading...' : 'Add'),
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (photoUrls.isEmpty)
              const Padding(
                padding: EdgeInsets.all(40),
                child: Column(
                  children: [
                    Icon(
                      Icons.add_photo_alternate_outlined,
                      size: 64,
                      color: Color.fromARGB(255, 158, 158, 158),
                    ),
                    SizedBox(height: 16),
                    Text(
                      'No photos yet',
                      style: TextStyle(
                        color: Colors.grey,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Add photos to showcase your space',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              )
            else
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 14,
                  crossAxisSpacing: 14,
                  childAspectRatio: 1.2,
                ),
                itemCount: photoUrls.length,
                itemBuilder: (context, index) => Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Image.network(
                        photoUrls[index],
                        width: double.infinity,
                        height: double.infinity,
                        fit: BoxFit.cover,
                      ),
                    ),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: GestureDetector(
                        onTap: () => _deletePhoto(photoUrls[index]),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.delete_rounded,
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 20),
      child: _GlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionHeader(
              icon: Icons.settings_rounded,
              title: 'Settings',
              subtitle: 'Manage your space',
            ),
            const SizedBox(height: 20),
            InkWell(
              onTap: _deleteSpace,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xFFEF4444).withOpacity(0.3),
                  ),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.delete_forever_rounded,
                      color: Color(0xFFEF4444),
                      size: 24,
                    ),
                    SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        'Delete Parking Space',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFFEF4444),
                        ),
                      ),
                    ),
                    Icon(
                      Icons.arrow_forward_ios_rounded,
                      color: Color(0xFFEF4444),
                      size: 18,
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

  Widget _amenityChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF4F46E5).withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF4F46E5).withOpacity(0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: const Color(0xFF4F46E5), size: 18),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF4F46E5),
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  String _formatSpaceType(String type) => type
      .split('_')
      .map((word) => word[0].toUpperCase() + word.substring(1))
      .join(' ');
  String _formatAvailability(String availability) {
    switch (availability) {
      case 'weekdays_only':
        return 'Weekdays Only (Mon-Fri)';
      case 'weekends_only':
        return 'Weekends Only (Sat-Sun)';
      case 'event_days_only':
        return 'Event Days Only';
      default:
        return '24/7 (Always Available)';
    }
  }
}

// ========== CUSTOM WIDGETS ==========

class _GlassCard extends StatelessWidget {
  final Widget child;
  const _GlassCard({required this.child});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
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
  Widget build(BuildContext context) => Row(
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
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
      ),
    ],
  );
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
  Widget build(BuildContext context) => Row(
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

class _AnalyticsCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final String trend;
  const _AnalyticsCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    required this.trend,
  });
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      gradient: LinearGradient(colors: [color, color.withOpacity(0.7)]),
      borderRadius: BorderRadius.circular(20),
      boxShadow: [
        BoxShadow(
          color: color.withOpacity(0.3),
          blurRadius: 20,
          offset: const Offset(0, 10),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Icon(icon, color: Colors.white, size: 28),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                trend,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: Colors.white.withOpacity(0.9),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ],
    ),
  );
}
