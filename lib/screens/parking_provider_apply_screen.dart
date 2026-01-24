import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class ParkingProviderApplyScreen extends StatefulWidget {
  const ParkingProviderApplyScreen({super.key});

  @override
  State<ParkingProviderApplyScreen> createState() =>
      _ParkingProviderApplyScreenState();
}

class _ParkingProviderApplyScreenState
    extends State<ParkingProviderApplyScreen> {
  final _formKey = GlobalKey<FormState>();

  // Provider identity
  final _fullNameCtrl = TextEditingController();
  final _dobCtrl = TextEditingController(); // keep as text for now: DD/MM/YYYY
  final _phoneCtrl = TextEditingController();
  String _verificationType = 'Passport';

  // Space details
  final _spaceTitleCtrl = TextEditingController();
  final _postcodeCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _hourlyRateCtrl = TextEditingController();
  String _spaceType = 'Driveway';
  String _spaceSize = 'Medium';
  final _photoUrlsCtrl = TextEditingController(); // comma/newline separated

  bool _authorityConfirmed = false;
  bool _propertyConfirmed = false;
  bool _termsAccepted = false;
  bool _loading = false;

  @override
  void dispose() {
    _fullNameCtrl.dispose();
    _dobCtrl.dispose();
    _phoneCtrl.dispose();
    _spaceTitleCtrl.dispose();
    _postcodeCtrl.dispose();
    _addressCtrl.dispose();
    _hourlyRateCtrl.dispose();
    _photoUrlsCtrl.dispose();
    super.dispose();
  }

  String _norm(String s) => s.trim();
  String _normLc(String s) => s.trim().toLowerCase();

  List<String> _parsePhotoUrls(String raw) {
    final parts = raw
        .split(RegExp(r'[, \n]+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    // Basic sanity: keep unique
    return parts.toSet().toList();
  }

  Future<void> _submit() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    if (!_formKey.currentState!.validate()) return;

    if (!_authorityConfirmed || !_propertyConfirmed || !_termsAccepted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please confirm authority, property ownership/permission, and accept terms.',
          ),
        ),
      );
      return;
    }

    setState(() => _loading = true);

    try {
      final uid = user.uid;
      final email = user.email ?? '';

      // 1) Create/Update provider application
      await FirebaseFirestore.instance
          .collection('parking_provider_applications')
          .doc(uid)
          .set({
            'provider_uid': uid,
            'full_name': _norm(_fullNameCtrl.text),
            'dob': _norm(
              _dobCtrl.text,
            ), // store as text for now (next phase: Date)
            'email': _norm(email),
            'phone': _norm(_phoneCtrl.text),
            'verification_type': _verificationType,
            'status': 'pending',
            'status_lc': 'pending',
            'submitted_at': FieldValue.serverTimestamp(),
            'updated_at': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));

      // 2) Create first parking space (pending)
      final hourlyRate = double.tryParse(_hourlyRateCtrl.text.trim()) ?? 0.0;

      await FirebaseFirestore.instance.collection('parking_spaces').add({
        'provider_uid': uid,
        'title': _norm(_spaceTitleCtrl.text),
        'postcode': _norm(_postcodeCtrl.text),
        'address': _norm(
          _addressCtrl.text,
        ), // do NOT show publicly (driver UI hides)
        'space_type': _spaceType,
        'space_size': _spaceSize,
        'hourly_rate_gbp': hourlyRate,
        'photo_urls': _parsePhotoUrls(_photoUrlsCtrl.text),
        'status': 'pending',
        'status_lc': 'pending',
        'created_at': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
      });

      // 3) Update user doc (single source of truth for app gating)
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'parkingProviderStatus': 'pending',
        'name': _norm(_fullNameCtrl.text),
        'email': _norm(email),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Submitted. Your provider + space are pending manual review.',
          ),
        ),
      );

      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to submit: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  InputDecoration _deco(String hint) => InputDecoration(
    hintText: hint,
    filled: true,
    fillColor: const Color(0xFFF8FAFC),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide.none,
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
  );

  @override
  Widget build(BuildContext context) {
    final email = FirebaseAuth.instance.currentUser?.email ?? '';

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FF),
      appBar: AppBar(
        title: const Text('Register Private Parking'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 22),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              _HeaderCard(email: email),
              const SizedBox(height: 14),

              // SECTION: Provider identity
              _SectionCard(
                title: 'Provider details',
                child: Column(
                  children: [
                    TextFormField(
                      controller: _fullNameCtrl,
                      decoration: _deco('Full name (as per ID/passport)'),
                      validator: (v) => (v == null || v.trim().length < 2)
                          ? 'Enter your full name'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _dobCtrl,
                      decoration: _deco('Date of birth (DD/MM/YYYY)'),
                      validator: (v) => (v == null || v.trim().length < 8)
                          ? 'Enter your DOB'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _phoneCtrl,
                      decoration: _deco('Phone number'),
                      keyboardType: TextInputType.phone,
                      validator: (v) => (v == null || v.trim().length < 8)
                          ? 'Enter a valid phone number'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    _DropdownField<String>(
                      label: 'Verification type',
                      value: _verificationType,
                      items: const [
                        'Passport',
                        'Driving Licence',
                        'National ID',
                      ],
                      onChanged: (v) => setState(() => _verificationType = v),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              // SECTION: Parking space details
              _SectionCard(
                title: 'Parking space details',
                child: Column(
                  children: [
                    TextFormField(
                      controller: _spaceTitleCtrl,
                      decoration: _deco(
                        'Title (e.g., Parking near Wembley Stadium)',
                      ),
                      validator: (v) => (v == null || v.trim().length < 3)
                          ? 'Enter a title'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _postcodeCtrl,
                      decoration: _deco('Postcode (e.g., HA1 1EH)'),
                      validator: (v) => (v == null || v.trim().length < 4)
                          ? 'Enter a valid postcode'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _addressCtrl,
                      decoration: _deco('Exact address (kept private for now)'),
                      validator: (v) => (v == null || v.trim().length < 6)
                          ? 'Enter an address'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    _DropdownField<String>(
                      label: 'Space type',
                      value: _spaceType,
                      items: const ['Driveway', 'Garage', 'Car Park', 'Other'],
                      onChanged: (v) => setState(() => _spaceType = v),
                    ),
                    const SizedBox(height: 12),
                    _DropdownField<String>(
                      label: 'Space size',
                      value: _spaceSize,
                      items: const ['Small', 'Medium', 'Large'],
                      onChanged: (v) => setState(() => _spaceSize = v),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _hourlyRateCtrl,
                      decoration: _deco('Hourly rate (GBP)'),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      validator: (v) {
                        final val = double.tryParse((v ?? '').trim());
                        if (val == null || val <= 0) {
                          return 'Enter a valid hourly rate';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _photoUrlsCtrl,
                      decoration: _deco(
                        'Photo URLs (comma/newline separated) — optional for now',
                      ),
                      maxLines: 3,
                    ),
                    const SizedBox(height: 6),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Note: In the next phase we will upload images to Firebase Storage directly.',
                        style: TextStyle(
                          color: Color(0xFF64748B),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              // SECTION: Confirmations
              _SectionCard(
                title: 'Confirmations',
                child: Column(
                  children: [
                    _CheckRow(
                      value: _authorityConfirmed,
                      onChanged: (v) => setState(() => _authorityConfirmed = v),
                      text:
                          'I confirm I have authority to rent out this parking space (owner/tenant/permission).',
                    ),
                    _CheckRow(
                      value: _propertyConfirmed,
                      onChanged: (v) => setState(() => _propertyConfirmed = v),
                      text:
                          'I confirm the information provided is accurate and relates to my property/permission.',
                    ),
                    _CheckRow(
                      value: _termsAccepted,
                      onChanged: (v) => setState(() => _termsAccepted = v),
                      text:
                          'I accept the platform terms and agree to manual review before publishing.',
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _loading ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4F46E5),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: _loading
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text(
                          'Submit for approval',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  final String email;
  const _HeaderCard({required this.email});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0EA5E9), Color(0xFF6366F1), Color(0xFF8B5CF6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
            blurRadius: 22,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Private Parking Registration',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Submit provider + first space. Manual approval is required.',
            style: TextStyle(
              color: Colors.white.withOpacity(0.92),
              fontWeight: FontWeight.w700,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Signed in as: $email',
            style: TextStyle(
              color: Colors.white.withOpacity(0.9),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _SectionCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 18,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _DropdownField<T> extends StatelessWidget {
  final String label;
  final T value;
  final List<T> items;
  final ValueChanged<T> onChanged;

  const _DropdownField({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      initialValue: value,
      items: items
          .map((e) => DropdownMenuItem<T>(value: e, child: Text('$e')))
          .toList(),
      onChanged: (v) => onChanged(v as T),
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 14,
        ),
      ),
    );
  }
}

class _CheckRow extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  final String text;

  const _CheckRow({
    required this.value,
    required this.onChanged,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Checkbox(value: value, onChanged: (v) => onChanged(v ?? false)),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                text,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF334155),
                  height: 1.25,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
