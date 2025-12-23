// organizer_application_sheet.dart
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

Future<void> showOrganizerApplicationSheet(
  BuildContext context, {
  required Map<String, dynamic> userData,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      return OrganizerApplicationSheet(userData: userData);
    },
  );
}

class OrganizerApplicationSheet extends StatefulWidget {
  final Map<String, dynamic> userData;

  const OrganizerApplicationSheet({super.key, required this.userData});

  @override
  State<OrganizerApplicationSheet> createState() =>
      _OrganizerApplicationSheetState();
}

class _OrganizerApplicationSheetState extends State<OrganizerApplicationSheet>
    with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();

  final _fullNameController = TextEditingController();
  final _address1Controller = TextEditingController();
  final _address2Controller = TextEditingController();
  final _cityController = TextEditingController();
  final _postalController = TextEditingController();
  final _idUrlController = TextEditingController();
  final _notesController = TextEditingController();

  DateTime? _dob;
  bool _isSaving = false;
  late AnimationController _fadeController;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..forward();

    // Pre-fill from userData if available
    final name = widget.userData['name'] as String?;
    if (name != null && name.isNotEmpty) {
      _fullNameController.text = name;
    }
    final city = widget.userData['city'] as String?;
    if (city != null && city.isNotEmpty) {
      _cityController.text = city;
    }
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _fullNameController.dispose();
    _address1Controller.dispose();
    _address2Controller.dispose();
    _cityController.dispose();
    _postalController.dispose();
    _idUrlController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pickDob() async {
    final now = DateTime.now();
    // Assume minimum age 16
    final latestDob = DateTime(now.year - 16, now.month, now.day);
    final earliestDob = DateTime(now.year - 80, now.month, now.day);

    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(now.year - 25, now.month, now.day),
      firstDate: earliestDob,
      lastDate: latestDob,
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

    if (picked == null) return;

    setState(() {
      _dob = picked;
    });
  }

  String _formatDob(DateTime? dob) {
    if (dob == null) return 'Select date of birth';
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(dob.day)}/${two(dob.month)}/${dob.year}';
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    if (_dob == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please select your date of birth'),
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
          content: const Text('You must be logged in to apply as organizer'),
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
      final email =
          widget.userData['email'] as String? ?? user.email ?? 'unknown';
      final fullName = _fullNameController.text.trim();

      final applicationData = {
        'userId': user.uid,
        'fullName': fullName,
        'email': email,
        'dob': Timestamp.fromDate(_dob!),
        'addressLine1': _address1Controller.text.trim(),
        'addressLine2': _address2Controller.text.trim(),
        'city': _cityController.text.trim(),
        'postalCode': _postalController.text.trim(),
        'idDocumentUrl': _idUrlController.text.trim().isEmpty
            ? null
            : _idUrlController.text.trim(),
        'additionalNotes': _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      // 1) Save application
      await FirebaseFirestore.instance
          .collection('organizer_requests')
          .doc(user.uid)
          .set(applicationData, SetOptions(merge: true));

      // 2) Mark user as "pending" organizer
      await FirebaseFirestore.instance.collection('users').doc(user.uid).update(
        {'organizerStatus': 'pending'},
      );

      if (!mounted) return;
      Navigator.of(context).pop();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Organizer application submitted. We\'ll review it shortly.',
          ),
          backgroundColor: Colors.green.shade500,
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
          content: Text('Failed to submit application: $e'),
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
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 20),
                    _buildHeader(),
                    const SizedBox(height: 24),
                    _buildFullNameField(),
                    const SizedBox(height: 16),
                    _buildDobField(),
                    const SizedBox(height: 16),
                    _buildAddressFields(),
                    const SizedBox(height: 16),
                    _buildIdField(),
                    const SizedBox(height: 16),
                    _buildNotesField(),
                    const SizedBox(height: 24),
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

  Widget _buildHeader() {
    return Column(
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
          child: const Icon(
            Icons.assignment_ind_rounded,
            color: Colors.white,
            size: 32,
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Organizer Application',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Color(0xFF0F172A),
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Tell us a bit more about you so we can approve your organizer account.',
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

  Widget _buildFullNameField() {
    return _modernTextField(
      controller: _fullNameController,
      label: 'Full Name',
      hint: 'Your full legal name',
      icon: Icons.person_rounded,
      color: const Color(0xFF3B82F6),
      validator: (v) =>
          v == null || v.trim().isEmpty ? 'Full name is required' : null,
    );
  }

  Widget _buildDobField() {
    return Column(
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
                Icons.cake_rounded,
                size: 18,
                color: Color(0xFF8B5CF6),
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              'Date of Birth',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Color(0xFF64748B),
                letterSpacing: -0.2,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: _pickDob,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _dob == null
                    ? Colors.grey.shade200
                    : const Color(0xFF8B5CF6),
                width: 1.5,
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.calendar_month_rounded,
                  size: 18,
                  color: Color(0xFF8B5CF6),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _formatDob(_dob),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: _dob == null
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
        ),
      ],
    );
  }

  Widget _buildAddressFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _modernTextAreaField(
          controller: _address1Controller,
          label: 'Address',
          hint: 'House number, street, locality',
          icon: Icons.home_rounded,
          color: const Color(0xFFF59E0B),
          validator: (v) =>
              v == null || v.trim().isEmpty ? 'Address is required' : null,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _modernTextField(
                controller: _cityController,
                label: 'City',
                hint: 'e.g., London',
                icon: Icons.location_city_rounded,
                color: const Color(0xFF06B6D4),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'City is required' : null,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _modernTextField(
                controller: _postalController,
                label: 'Postcode',
                hint: 'e.g., HA9 0AA',
                icon: Icons.pin_rounded,
                color: const Color(0xFF8B5CF6),
                validator: (v) => v == null || v.trim().isEmpty
                    ? 'Postcode is required'
                    : null,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildIdField() {
    return _modernTextField(
      controller: _idUrlController,
      label: 'ID document link',
      hint: 'Secure link to passport / driving licence (optional)',
      icon: Icons.badge_rounded,
      color: const Color(0xFF10B981),
      isOptional: true,
    );
  }

  Widget _buildNotesField() {
    return _modernTextAreaField(
      controller: _notesController,
      label: 'Additional details',
      hint: 'Tell us about the type of events you plan to host (optional)',
      icon: Icons.notes_rounded,
      color: const Color(0xFF64748B),
    );
  }

  Widget _buildSubmitButton() {
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
          onTap: _isSaving ? null : _submit,
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
                      ? 'Submitting application...'
                      : 'Submit Organizer Application',
                  style: const TextStyle(
                    fontSize: 15,
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

  // --------------------------------------------------------------------------
  // Reusable field builders
  // --------------------------------------------------------------------------

  Widget _modernTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    required Color color,
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

  Widget _modernTextAreaField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    required Color color,
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
}
