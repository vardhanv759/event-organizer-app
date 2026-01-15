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

  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _postcodeCtrl = TextEditingController();

  bool _authorityConfirmed = false;
  bool _termsAccepted = false;
  bool _loading = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _postcodeCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    if (!_formKey.currentState!.validate()) return;

    if (!_authorityConfirmed || !_termsAccepted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please confirm authority and accept terms to continue.',
          ),
        ),
      );
      return;
    }

    setState(() => _loading = true);

    try {
      final uid = user.uid;
      final email = user.email ?? '';

      // 1) Write provider application
      await FirebaseFirestore.instance
          .collection('parking_provider_applications')
          .doc(uid)
          .set({
            'provider_uid': uid,
            'full_name': _nameCtrl.text.trim(),
            'email': email.trim(),
            'phone': _phoneCtrl.text.trim(),
            'home_postcode': _postcodeCtrl.text.trim(),
            'proof_docs': <String>[], // upload later in next phase
            'status': 'pending',
            'submitted_at': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));

      // 2) Update user status
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'parkingProviderStatus': 'pending',
        'name': _nameCtrl.text.trim(),
        'email': email.trim(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Application submitted. Status: pending review.'),
        ),
      );

      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to submit application: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = FirebaseAuth.instance.currentUser?.email ?? '';

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FF),
      appBar: AppBar(
        title: const Text('Apply as Parking Provider'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 22),
        child: Column(
          children: [
            _HeaderCard(email: email),
            const SizedBox(height: 14),
            _FormCard(
              formKey: _formKey,
              nameCtrl: _nameCtrl,
              phoneCtrl: _phoneCtrl,
              postcodeCtrl: _postcodeCtrl,
            ),
            const SizedBox(height: 14),
            _ChecksCard(
              authorityConfirmed: _authorityConfirmed,
              termsAccepted: _termsAccepted,
              onAuthorityChanged: (v) =>
                  setState(() => _authorityConfirmed = v),
              onTermsChanged: (v) => setState(() => _termsAccepted = v),
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
                        'Submit Application',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
              ),
            ),
          ],
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
            'Private Parking Provider',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'You will be manually reviewed before you can publish spaces.',
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

class _FormCard extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController nameCtrl;
  final TextEditingController phoneCtrl;
  final TextEditingController postcodeCtrl;

  const _FormCard({
    required this.formKey,
    required this.nameCtrl,
    required this.phoneCtrl,
    required this.postcodeCtrl,
  });

  @override
  Widget build(BuildContext context) {
    InputDecoration deco(String hint) => InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
    );

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
      child: Form(
        key: formKey,
        child: Column(
          children: [
            TextFormField(
              controller: nameCtrl,
              decoration: deco('Full name'),
              validator: (v) => (v == null || v.trim().length < 2)
                  ? 'Enter your full name'
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: phoneCtrl,
              decoration: deco('Phone number'),
              keyboardType: TextInputType.phone,
              validator: (v) => (v == null || v.trim().length < 8)
                  ? 'Enter a valid phone number'
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: postcodeCtrl,
              decoration: deco('Home postcode (UK)'),
              validator: (v) => (v == null || v.trim().length < 4)
                  ? 'Enter a valid postcode'
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _ChecksCard extends StatelessWidget {
  final bool authorityConfirmed;
  final bool termsAccepted;
  final ValueChanged<bool> onAuthorityChanged;
  final ValueChanged<bool> onTermsChanged;

  const _ChecksCard({
    required this.authorityConfirmed,
    required this.termsAccepted,
    required this.onAuthorityChanged,
    required this.onTermsChanged,
  });

  @override
  Widget build(BuildContext context) {
    Widget row({
      required bool value,
      required ValueChanged<bool> onChanged,
      required String text,
    }) {
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
        children: [
          row(
            value: authorityConfirmed,
            onChanged: onAuthorityChanged,
            text:
                'I confirm I have authority to rent out this parking space (owner/tenant/permission).',
          ),
          row(
            value: termsAccepted,
            onChanged: onTermsChanged,
            text:
                'I accept the platform terms and agree to manual review/approval before publishing.',
          ),
        ],
      ),
    );
  }
}
