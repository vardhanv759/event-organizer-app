import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

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

  // Provider
  final _fullNameCtrl = TextEditingController();
  final _dobCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  String _idType = 'Passport';
  final _idNumberCtrl = TextEditingController();

  // Space
  final _titleCtrl = TextEditingController();
  final _postcodeCtrl = TextEditingController();
  final _approxAreaCtrl = TextEditingController(text: 'Wembley');
  final _exactAddressCtrl = TextEditingController();
  final _hourlyCtrl = TextEditingController();
  String _spaceType = 'driveway';
  String _size = 'medium';

  // Photos (MVP: URLs)
  final List<String> _photoUrls = [];
  final _photoUrlCtrl = TextEditingController();

  // Agreements
  bool _authorityConfirmed = false;
  bool _termsAccepted = false;

  bool _submitting = false;

  @override
  void initState() {
    super.initState();

    final current = FirebaseAuth.instance.currentUser;
    _emailCtrl.text = (widget.userDoc['email'] ?? current?.email ?? '')
        .toString();

    final name = (widget.userDoc['name'] ?? '').toString().trim();
    if (name.isNotEmpty) _fullNameCtrl.text = name;

    final phone = (widget.userDoc['phone'] ?? '').toString().trim();
    if (phone.isNotEmpty) _phoneCtrl.text = phone;
  }

  @override
  void dispose() {
    _fullNameCtrl.dispose();
    _dobCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _idNumberCtrl.dispose();
    _titleCtrl.dispose();
    _postcodeCtrl.dispose();
    _approxAreaCtrl.dispose();
    _exactAddressCtrl.dispose();
    _hourlyCtrl.dispose();
    _photoUrlCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    if (!_formKey.currentState!.validate()) return;

    if (!_authorityConfirmed || !_termsAccepted) {
      _snack('Please confirm authority and accept terms to continue.');
      return;
    }

    setState(() => _submitting = true);

    try {
      final uid = user.uid;

      final providerStatusRaw =
          (widget.userDoc['parkingProviderStatus'] ?? 'none').toString();
      final providerStatus = providerStatusRaw.trim().toLowerCase();

      // Provider application: create/merge. Do not downgrade approved.
      final nextProviderStatus = providerStatus == 'approved'
          ? 'approved'
          : 'pending';

      await FirebaseFirestore.instance
          .collection('parking_provider_applications')
          .doc(uid)
          .set({
            'provider_uid': uid,
            'full_name': _fullNameCtrl.text.trim(),
            'dob': _dobCtrl.text.trim(),
            'email': _emailCtrl.text.trim(),
            'phone': _phoneCtrl.text.trim(),
            'id_type': _idType,
            'id_number': _idNumberCtrl.text.trim(),
            'proof_docs': <String>[], // Next phase: Storage uploads
            'status': nextProviderStatus,
            'status_lower': nextProviderStatus,
            'updated_at': FieldValue.serverTimestamp(),
            'submitted_at': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));

      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'parkingProviderStatus': nextProviderStatus,
        'name': _fullNameCtrl.text.trim(),
        'email': _emailCtrl.text.trim(),
        'phone': _phoneCtrl.text.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // Space request (ALWAYS pending review unless you choose otherwise)
      final hourly = double.tryParse(_hourlyCtrl.text.trim()) ?? 0.0;

      await FirebaseFirestore.instance.collection('parking_spaces').add({
        'provider_uid': uid,
        'provider_name': _fullNameCtrl.text.trim(),
        'provider_email': _emailCtrl.text.trim(),
        'provider_phone': _phoneCtrl.text.trim(),

        'title': _titleCtrl.text.trim(),
        'postcode': _postcodeCtrl.text.trim().toUpperCase(),
        'approx_area': _approxAreaCtrl.text.trim(),
        'exact_address': _exactAddressCtrl.text.trim(),

        'space_type': _spaceType,
        'size_label': _size,
        'hourly_rate_gbp': hourly,

        'photo_urls': _photoUrls,

        'status': 'pending',
        'status_lower': 'pending',

        'created_at': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      _snack(
        'Submitted successfully. Provider/Space is pending manual approval.',
      );
      Navigator.pop(context);
    } catch (e) {
      _snack('Failed to submit: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
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
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverAppBar(
            pinned: true,
            stretch: true,
            expandedHeight: 220,
            elevation: 0,
            backgroundColor: Colors.transparent,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: () => Navigator.pop(context),
            ),
            flexibleSpace: const FlexibleSpaceBar(background: _RegisterHero()),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 22),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                _SectionTitle(
                  title: 'Provider details',
                  subtitle:
                      'These details help prevent fraud and protect drivers.',
                ),
                const SizedBox(height: 10),
                _Card(
                  child: Form(
                    key: _formKey,
                    child: Column(
                      children: [
                        _TextField(
                          controller: _fullNameCtrl,
                          label: 'Full name (as per ID/Passport)',
                          validator: (v) => (v == null || v.trim().length < 2)
                              ? 'Enter your full name'
                              : null,
                        ),
                        const SizedBox(height: 12),
                        _TextField(
                          controller: _dobCtrl,
                          label: 'Date of birth (DD/MM/YYYY)',
                          validator: (v) => (v == null || v.trim().length < 8)
                              ? 'Enter your date of birth'
                              : null,
                        ),
                        const SizedBox(height: 12),
                        _TextField(
                          controller: _emailCtrl,
                          label: 'Email',
                          keyboardType: TextInputType.emailAddress,
                          validator: (v) => (v == null || !v.contains('@'))
                              ? 'Enter a valid email'
                              : null,
                        ),
                        const SizedBox(height: 12),
                        _TextField(
                          controller: _phoneCtrl,
                          label: 'Phone number',
                          keyboardType: TextInputType.phone,
                          validator: (v) => (v == null || v.trim().length < 8)
                              ? 'Enter a valid phone number'
                              : null,
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _Dropdown<String>(
                                label: 'Verification type',
                                value: _idType,
                                items: const [
                                  'Passport',
                                  'Driving Licence',
                                  'National ID',
                                ],
                                onChanged: (v) => setState(() => _idType = v),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _TextField(
                                controller: _idNumberCtrl,
                                label: 'ID number',
                                validator: (v) =>
                                    (v == null || v.trim().length < 4)
                                    ? 'Enter ID number'
                                    : null,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                _SectionTitle(
                  title: 'Parking space details',
                  subtitle:
                      'What drivers will see (address stays private until payment).',
                ),
                const SizedBox(height: 10),
                _Card(
                  child: Column(
                    children: [
                      _TextField(
                        controller: _titleCtrl,
                        label: 'Title (e.g., Parking near Wembley Stadium)',
                        validator: (v) => (v == null || v.trim().length < 4)
                            ? 'Enter a title'
                            : null,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _TextField(
                              controller: _postcodeCtrl,
                              label: 'Postcode (e.g., HA1 1EH)',
                              validator: (v) =>
                                  (v == null || v.trim().length < 4)
                                  ? 'Enter a valid postcode'
                                  : null,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _TextField(
                              controller: _approxAreaCtrl,
                              label: 'Area shown to drivers (approx.)',
                              validator: (v) => (v == null || v.trim().isEmpty)
                                  ? 'Enter area'
                                  : null,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _TextField(
                        controller: _exactAddressCtrl,
                        label: 'Exact address (hidden until payment)',
                        validator: (v) => (v == null || v.trim().length < 8)
                            ? 'Enter the exact address'
                            : null,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _Dropdown<String>(
                              label: 'Space type',
                              value: _spaceType,
                              items: const [
                                'driveway',
                                'allocated_bay',
                                'underground',
                                'gated',
                                'open_lot',
                              ],
                              onChanged: (v) => setState(() => _spaceType = v),
                              itemLabel: (v) => v.replaceAll('_', ' '),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _Dropdown<String>(
                              label: 'Size',
                              value: _size,
                              items: const ['small', 'medium', 'large'],
                              onChanged: (v) => setState(() => _size = v),
                              itemLabel: (v) =>
                                  v[0].toUpperCase() + v.substring(1),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _TextField(
                        controller: _hourlyCtrl,
                        label: 'Hourly rate (GBP)',
                        keyboardType: TextInputType.number,
                        validator: (v) {
                          final n = double.tryParse((v ?? '').trim());
                          if (n == null || n <= 0) {
                            return 'Enter a valid hourly price';
                          }
                          return null;
                        },
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                _SectionTitle(
                  title: 'Photos (MVP)',
                  subtitle:
                      'For now, add photo URLs. Next phase: upload to Storage.',
                ),
                const SizedBox(height: 10),
                _Card(
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _TextField(
                              controller: _photoUrlCtrl,
                              label: 'Photo URL (https://...)',
                              validator: (v) => null,
                            ),
                          ),
                          const SizedBox(width: 10),
                          ElevatedButton(
                            onPressed: () {
                              final url = _photoUrlCtrl.text.trim();
                              if (url.isEmpty) return;
                              setState(() {
                                _photoUrls.add(url);
                                _photoUrlCtrl.clear();
                              });
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF4F46E5),
                              foregroundColor: Colors.white,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 14,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: const Text(
                              'Add',
                              style: TextStyle(fontWeight: FontWeight.w900),
                            ),
                          ),
                        ],
                      ),
                      if (_photoUrls.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _photoUrls
                              .asMap()
                              .entries
                              .map(
                                (e) => _Chip(
                                  text: 'Photo ${e.key + 1}',
                                  onRemove: () => setState(
                                    () => _photoUrls.removeAt(e.key),
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                _SectionTitle(
                  title: 'Agreements',
                  subtitle: 'Required to submit.',
                ),
                const SizedBox(height: 10),
                _Card(
                  child: Column(
                    children: [
                      _CheckRow(
                        value: _authorityConfirmed,
                        onChanged: (v) =>
                            setState(() => _authorityConfirmed = v),
                        text:
                            'I confirm I have legal authority to rent out this space (owner/tenant/permission).',
                      ),
                      _CheckRow(
                        value: _termsAccepted,
                        onChanged: (v) => setState(() => _termsAccepted = v),
                        text:
                            'I accept platform terms and agree to manual review/approval before publishing.',
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _submitting ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4F46E5),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    child: _submitting
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text(
                            'Submit for manual approval',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 15,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'After approval, your space will appear under “Private parking nearby”.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF64748B),
                  ),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

class _RegisterHero extends StatelessWidget {
  const _RegisterHero();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF0EA5E9), Color(0xFF6366F1), Color(0xFF8B5CF6)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        Positioned(
          top: -70,
          right: -60,
          child: Container(
            height: 220,
            width: 220,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withOpacity(0.10),
            ),
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 56, 16, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Register Parking Space',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Premium, secure onboarding with manual approval.',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.92),
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                  ),
                ),
                const Spacer(),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: const [
                    _HeroPill(
                      icon: Icons.security_rounded,
                      text: 'Fraud control',
                    ),
                    _HeroPill(
                      icon: Icons.visibility_off_rounded,
                      text: 'Address hidden',
                    ),
                    _HeroPill(
                      icon: Icons.verified_rounded,
                      text: 'Manual review',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _HeroPill extends StatelessWidget {
  final IconData icon;
  final String text;

  const _HeroPill({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withOpacity(0.20)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              color: Colors.white.withOpacity(0.95),
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final String subtitle;

  const _SectionTitle({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
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
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF64748B),
                  height: 1.25,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});

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
      child: child,
    );
  }
}

class _TextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;

  const _TextField({
    required this.controller,
    required this.label,
    this.keyboardType,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      validator: validator,
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

class _Dropdown<T> extends StatelessWidget {
  final String label;
  final T value;
  final List<T> items;
  final ValueChanged<T> onChanged;
  final String Function(T v)? itemLabel;

  const _Dropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    this.itemLabel,
  });

  @override
  Widget build(BuildContext context) {
    final labelFn = itemLabel ?? (v) => v.toString();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          items: items
              .map(
                (t) => DropdownMenuItem<T>(
                  value: t,
                  child: Text(
                    labelFn(t),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              )
              .toList(),
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
          hint: Text(label),
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

class _Chip extends StatelessWidget {
  final String text;
  final VoidCallback onRemove;

  const _Chip({required this.text, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(text, style: const TextStyle(fontWeight: FontWeight.w800)),
      deleteIcon: const Icon(Icons.close_rounded, size: 18),
      onDeleted: onRemove,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      backgroundColor: const Color(0xFFF1F5F9),
    );
  }
}
