import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

Future<void> showOrganizeEventSheet(
  BuildContext context, {
  required Map<String, dynamic> userData,
  DocumentSnapshot<Map<String, dynamic>>? eventDoc,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      return OrganizeEventSheet(userData: userData, eventDoc: eventDoc);
    },
  );
}

class OrganizeEventSheet extends StatefulWidget {
  final Map<String, dynamic> userData;
  final DocumentSnapshot<Map<String, dynamic>>? eventDoc;

  const OrganizeEventSheet({super.key, required this.userData, this.eventDoc});

  @override
  State<OrganizeEventSheet> createState() => _OrganizeEventSheetState();
}

class _OrganizeEventSheetState extends State<OrganizeEventSheet>
    with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();

  final _nameController = TextEditingController();
  final _venueController = TextEditingController();
  final _address1Controller = TextEditingController();
  final _address2Controller = TextEditingController();
  final _postalController = TextEditingController();
  final _parkingInfoController = TextEditingController();
  final _imageUrlController = TextEditingController();

  DateTime? _startDateTime;
  bool _isSaving = false;
  late AnimationController _fadeController;

  final FocusNode _nameFocus = FocusNode();
  final FocusNode _venueFocus = FocusNode();
  final FocusNode _addressFocus = FocusNode();
  final FocusNode _parkingFocus = FocusNode();
  final FocusNode _imageFocus = FocusNode();

  bool get _isEditing => widget.eventDoc != null;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeController.forward();

    _prefillFromExistingEvent();
  }

  void _prefillFromExistingEvent() {
    final doc = widget.eventDoc;
    if (doc == null) return;

    final data = doc.data();
    if (data == null) return;

    _nameController.text = (data['name'] ?? '') as String;
    _venueController.text = (data['venueName'] ?? '') as String;
    _address1Controller.text = (data['addressLine1'] ?? '') as String;
    _address2Controller.text = (data['addressLine2'] ?? '') as String;
    _postalController.text = (data['postalCode'] ?? '') as String;
    _parkingInfoController.text = (data['parkingInfo'] ?? '') as String;
    _imageUrlController.text = (data['imageUrl'] ?? '') as String;

    final ts = data['startDateTime'];
    if (ts is Timestamp) {
      _startDateTime = ts.toDate();
    }
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _nameController.dispose();
    _venueController.dispose();
    _address1Controller.dispose();
    _address2Controller.dispose();
    _postalController.dispose();
    _parkingInfoController.dispose();
    _imageUrlController.dispose();
    _nameFocus.dispose();
    _venueFocus.dispose();
    _addressFocus.dispose();
    _parkingFocus.dispose();
    _imageFocus.dispose();
    super.dispose();
  }

  Future<void> _pickDateTime() async {
    final now = DateTime.now();

    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _startDateTime ?? now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF667EEA),
              surface: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );
    if (pickedDate == null) return;

    final initialTime = _startDateTime != null
        ? TimeOfDay(hour: _startDateTime!.hour, minute: _startDateTime!.minute)
        : const TimeOfDay(hour: 19, minute: 0);

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: initialTime,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF667EEA),
              surface: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );
    if (pickedTime == null) return;

    setState(() {
      _startDateTime = DateTime(
        pickedDate.year,
        pickedDate.month,
        pickedDate.day,
        pickedTime.hour,
        pickedTime.minute,
      );
    });
  }

  String _formatDateTime(DateTime? dt) {
    if (dt == null) return 'Select date & time';
    String two(int v) => v.toString().padLeft(2, '0');
    final date = '${two(dt.day)}/${two(dt.month)}/${dt.year}';
    final time = '${two(dt.hour)}:${two(dt.minute)}';
    return '$date  •  $time';
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    if (_startDateTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please select event date & time'),
          backgroundColor: Colors.red.shade400,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          margin: const EdgeInsets.all(16),
        ),
      );
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('You must be logged in to create events'),
          backgroundColor: Colors.red.shade400,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          margin: const EdgeInsets.all(16),
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final imageUrl = _imageUrlController.text.trim();
      final organizerName =
          widget.userData['name'] as String? ?? user.displayName ?? 'Organizer';

      final payload = <String, dynamic>{
        'name': _nameController.text.trim(),
        'venueName': _venueController.text.trim(),
        'city': 'London',
        'addressLine1': _address1Controller.text.trim(),
        'addressLine2': _address2Controller.text.trim(),
        'postalCode': _postalController.text.trim(),
        'startDateTime': Timestamp.fromDate(_startDateTime!),
        'timezone': 'Europe/London',
        'imageUrl': imageUrl.isEmpty ? null : imageUrl,
        'thumbnailUrl': imageUrl.isEmpty ? null : imageUrl,
        'url': null,
        'isFamilyEvent': false,
        'source': 'User Organizer',
        'area': 'Wembley',
        'organizerId': user.uid,
        'organizerName': organizerName,
        'parkingInfo': _parkingInfoController.text.trim(),
      };

      final eventsCol = FirebaseFirestore.instance.collection('events_wembley');

      if (widget.eventDoc == null) {
        // Create new event
        await eventsCol.add({
          ...payload,
          'createdAt': FieldValue.serverTimestamp(),
        });
      } else {
        // Update existing event
        await widget.eventDoc!.reference.update({
          ...payload,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      if (!mounted) return;

      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.eventDoc == null
                ? '✨ Event created and published!'
                : 'Event updated successfully',
          ),
          backgroundColor: Colors.green.shade400,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          margin: const EdgeInsets.all(16),
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to save event: $e'),
          backgroundColor: Colors.red.shade400,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          margin: const EdgeInsets.all(16),
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return FadeTransition(
      opacity: _fadeController,
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomInset),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 30,
                offset: const Offset(0, -8),
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Handle
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Header
                    _buildModernHeader(),
                    const SizedBox(height: 28),

                    // Form fields
                    _buildEventNameField(),
                    const SizedBox(height: 16),
                    _buildVenueField(),
                    const SizedBox(height: 16),
                    _buildAddressField(),
                    const SizedBox(height: 16),
                    _buildCityPostcodeRow(),
                    const SizedBox(height: 16),
                    _buildDateTimeField(),
                    const SizedBox(height: 16),
                    _buildParkingField(),
                    const SizedBox(height: 16),
                    _buildImageUrlField(),
                    const SizedBox(height: 20),

                    // Organizer info
                    _buildOrganizerInfo(),
                    const SizedBox(height: 20),

                    // Submit button
                    _buildSubmitButton(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildModernHeader() {
    final isEditing = _isEditing;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
            ),
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF667EEA).withOpacity(0.3),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Icon(
            isEditing
                ? Icons.edit_calendar_rounded
                : Icons.add_business_rounded,
            color: Colors.white,
            size: 32,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          isEditing ? 'Edit Event' : 'Organize an Event',
          style: const TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.bold,
            color: Color(0xFF0F172A),
            letterSpacing: -0.5,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          isEditing
              ? 'Update your event details for Wembley.'
              : 'Share your event with Wembley. Create an amazing experience!',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            color: Colors.grey.shade600,
            height: 1.5,
          ),
        ),
      ],
    );
  }

  Widget _buildEventNameField() {
    return _buildModernTextField(
      controller: _nameController,
      label: 'Event Name',
      hint: 'e.g., Summer Concert 2024',
      icon: Icons.edit_rounded,
      focusNode: _nameFocus,
      color: const Color(0xFF3B82F6),
      validator: (v) =>
          v == null || v.trim().isEmpty ? 'Event name required' : null,
    );
  }

  Widget _buildVenueField() {
    return _buildModernTextField(
      controller: _venueController,
      label: 'Venue / Location',
      hint: 'e.g., Wembley Stadium',
      icon: Icons.location_on_rounded,
      focusNode: _venueFocus,
      color: const Color(0xFF10B981),
      validator: (v) => v == null || v.trim().isEmpty ? 'Venue required' : null,
    );
  }

  Widget _buildAddressField() {
    return _buildModernTextAreaField(
      controller: _address1Controller,
      label: 'Complete Address',
      hint: 'Street address, area, and any important details',
      icon: Icons.home_work_rounded,
      focusNode: _addressFocus,
      color: const Color(0xFFF59E0B),
      validator: (v) =>
          v == null || v.trim().isEmpty ? 'Address required' : null,
    );
  }

  Widget _buildCityPostcodeRow() {
    return Row(
      children: [
        Expanded(
          child: _buildModernTextField(
            controller: _address2Controller,
            label: 'Area',
            hint: 'e.g., Wembley Park',
            icon: Icons.map_rounded,
            color: const Color(0xFF06B6D4),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildModernTextField(
            controller: _postalController,
            label: 'Postcode',
            hint: 'e.g., HA9 0AA',
            icon: Icons.pin_rounded,
            color: const Color(0xFF8B5CF6),
          ),
        ),
      ],
    );
  }

  Widget _buildDateTimeField() {
    return GestureDetector(
      onTap: _pickDateTime,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFF3E8FF),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFD8B4FE), width: 2),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF8B5CF6).withOpacity(0.1),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF8B5CF6).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.access_time_rounded,
                    size: 20,
                    color: Color(0xFF8B5CF6),
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Event Date & Time',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF64748B),
                    letterSpacing: -0.2,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFD8B4FE), width: 1.5),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.calendar_today_rounded,
                    size: 18,
                    color: Color(0xFF8B5CF6),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _formatDateTime(_startDateTime),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: _startDateTime == null
                            ? Colors.grey.shade500
                            : const Color(0xFF0F172A),
                      ),
                    ),
                  ),
                  Icon(
                    Icons.arrow_forward_rounded,
                    size: 18,
                    color: Colors.grey.shade400,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildParkingField() {
    return _buildModernTextAreaField(
      controller: _parkingInfoController,
      label: 'Parking Options',
      hint: 'On-site parking, nearby car park, street parking, etc.',
      icon: Icons.local_parking_rounded,
      focusNode: _parkingFocus,
      color: const Color(0xFF10B981),
    );
  }

  Widget _buildImageUrlField() {
    return _buildModernTextField(
      controller: _imageUrlController,
      label: 'Event Image URL',
      hint: 'Paste a HTTPS image link (optional)',
      icon: Icons.image_rounded,
      focusNode: _imageFocus,
      color: const Color(0xFFEF4444),
      isOptional: true,
    );
  }

  Widget _buildModernTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    required Color color,
    FocusNode? focusNode,
    String? Function(String?)? validator,
    bool isOptional = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 18, color: color),
            ),
            const SizedBox(width: 10),
            Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Color(0xFF64748B),
                letterSpacing: -0.2,
              ),
            ),
            if (isOptional)
              Text(
                ' (optional)',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey.shade500,
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          focusNode: focusNode,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
            filled: true,
            fillColor: Colors.grey.shade50,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 14,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: Colors.grey.shade200, width: 1.5),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: Colors.grey.shade200, width: 1.5),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: color, width: 2),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: Colors.red.shade300, width: 1.5),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: Colors.red.shade400, width: 2),
            ),
          ),
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Color(0xFF0F172A),
          ),
          validator: validator,
        ),
      ],
    );
  }

  Widget _buildModernTextAreaField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    required Color color,
    FocusNode? focusNode,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 18, color: color),
            ),
            const SizedBox(width: 10),
            Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Color(0xFF64748B),
                letterSpacing: -0.2,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          focusNode: focusNode,
          maxLines: 3,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
            filled: true,
            fillColor: Colors.grey.shade50,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 14,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: Colors.grey.shade200, width: 1.5),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: Colors.grey.shade200, width: 1.5),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: color, width: 2),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: Colors.red.shade300, width: 1.5),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: Colors.red.shade400, width: 2),
            ),
          ),
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Color(0xFF0F172A),
          ),
          validator: validator,
        ),
      ],
    );
  }

  Widget _buildOrganizerInfo() {
    final organizerName = widget.userData['name'] ?? 'You';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF667EEA).withOpacity(0.08),
            const Color(0xFF764BA2).withOpacity(0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFF667EEA).withOpacity(0.2),
          width: 1.5,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF667EEA).withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.verified_user_rounded,
              size: 20,
              color: Color(0xFF667EEA),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Event Organizer',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF64748B),
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  organizerName,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubmitButton() {
    final isEditing = _isEditing;

    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF667EEA).withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _isSaving ? null : _save,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_isSaving)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                else
                  const Icon(
                    Icons.check_circle_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                const SizedBox(width: 10),
                Text(
                  _isSaving
                      ? (isEditing ? 'Updating Event...' : 'Creating Event...')
                      : (isEditing ? 'Save Changes' : 'Organize Event Now'),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: -0.3,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
