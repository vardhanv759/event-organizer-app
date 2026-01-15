import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class ParkingSpaceRegisterScreen extends StatefulWidget {
  final String providerUid;

  const ParkingSpaceRegisterScreen({super.key, required this.providerUid});

  @override
  State<ParkingSpaceRegisterScreen> createState() =>
      _ParkingSpaceRegisterScreenState();
}

class _ParkingSpaceRegisterScreenState
    extends State<ParkingSpaceRegisterScreen> {
  final _formKey = GlobalKey<FormState>();

  final _titleCtrl = TextEditingController();
  final _rateCtrl = TextEditingController();
  final _areaCtrl = TextEditingController();
  final _rulesCtrl = TextEditingController();
  final _amenitiesCtrl = TextEditingController();
  final _postcodeCtrl = TextEditingController();

  String _spaceType = 'Driveway';
  bool _loading = false;
  bool _hydrated = false;
  bool _docExists = false;

  DocumentReference<Map<String, dynamic>> get _docRef => FirebaseFirestore
      .instance
      .collection('parking_spaces')
      .doc(widget.providerUid);

  @override
  void dispose() {
    _titleCtrl.dispose();
    _rateCtrl.dispose();
    _areaCtrl.dispose();
    _rulesCtrl.dispose();
    _amenitiesCtrl.dispose();
    _postcodeCtrl.dispose();
    super.dispose();
  }

  Future<void> _hydrateIfNeeded(
    DocumentSnapshot<Map<String, dynamic>> snap,
  ) async {
    if (_hydrated) return;

    _docExists = snap.exists;
    final data = snap.data() ?? {};

    _titleCtrl.text = (data['title'] ?? '').toString();
    _rateCtrl.text = (data['hourly_rate_gbp'] ?? '').toString();
    _areaCtrl.text = (data['approx_area'] ?? '').toString();
    _rulesCtrl.text = (data['rules'] ?? '').toString();
    _postcodeCtrl.text = (data['postcode'] ?? '').toString();

    final amenities = (data['amenities'] is List)
        ? (data['amenities'] as List).map((e) => e.toString()).toList()
        : <String>[];
    _amenitiesCtrl.text = amenities.join(', ');

    final st = (data['space_type'] ?? '').toString().trim();
    if (st.isNotEmpty) _spaceType = st;

    _hydrated = true;
    if (mounted) setState(() {});
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _loading = true);
    try {
      final amenities = _amenitiesCtrl.text
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();

      final payload = <String, dynamic>{
        'provider_uid': widget.providerUid,
        'title': _titleCtrl.text.trim(),
        'postcode': _postcodeCtrl.text.trim(),
        'space_type': _spaceType,
        'hourly_rate_gbp': double.tryParse(_rateCtrl.text.trim()) ?? 0.0,
        'approx_area': _areaCtrl.text.trim(),
        'rules': _rulesCtrl.text.trim(),
        'amenities': amenities,

        // IMPORTANT: space approval is separate from provider approval
        // Keep it pending until you manually approve the space.
        'status': 'pending',
        'updated_at': FieldValue.serverTimestamp(),
      };

      if (!_docExists) {
        payload['created_at'] = FieldValue.serverTimestamp();
      }

      await _docRef.set(payload, SetOptions(merge: true));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Saved. Space status: pending review.')),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to save: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _docRef.snapshots(),
      builder: (context, snap) {
        final ds = snap.data;
        if (ds != null) {
          _hydrateIfNeeded(ds);
        }

        return Scaffold(
          backgroundColor: const Color(0xFFF8F9FF),
          appBar: AppBar(
            title: const Text('Register Parking Space'),
            backgroundColor: Colors.transparent,
            elevation: 0,
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 22),
            child: Form(
              key: _formKey,
              child: Column(
                children: [
                  _field(_titleCtrl, 'Listing title', (v) {
                    if (v == null || v.trim().length < 3)
                      return 'Enter a title';
                    return null;
                  }),
                  const SizedBox(height: 12),

                  _field(_postcodeCtrl, 'Postcode (UK)', (v) {
                    if (v == null || v.trim().length < 4)
                      return 'Enter a postcode';
                    return null;
                  }),
                  const SizedBox(height: 12),

                  DropdownButtonFormField<String>(
                    value: _spaceType,
                    items: const [
                      DropdownMenuItem(
                        value: 'Driveway',
                        child: Text('Driveway'),
                      ),
                      DropdownMenuItem(value: 'Bay', child: Text('Bay')),
                      DropdownMenuItem(value: 'Garage', child: Text('Garage')),
                      DropdownMenuItem(value: 'Other', child: Text('Other')),
                    ],
                    onChanged: (v) =>
                        setState(() => _spaceType = v ?? 'Driveway'),
                    decoration: _deco('Space type'),
                  ),
                  const SizedBox(height: 12),

                  _field(
                    _rateCtrl,
                    'Hourly rate (GBP)',
                    (v) {
                      final x = double.tryParse((v ?? '').trim());
                      if (x == null || x <= 0)
                        return 'Enter a valid hourly rate';
                      return null;
                    },
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 12),

                  _field(
                    _areaCtrl,
                    'Approx area / notes (optional)',
                    (_) => null,
                  ),
                  const SizedBox(height: 12),

                  _field(
                    _amenitiesCtrl,
                    'Amenities (comma-separated)',
                    (_) => null,
                  ),
                  const SizedBox(height: 12),

                  _field(
                    _rulesCtrl,
                    'Rules / instructions',
                    (_) => null,
                    maxLines: 4,
                  ),
                  const SizedBox(height: 16),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _loading ? null : _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF4F46E5),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 0,
                      ),
                      child: _loading
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text(
                              'Submit for Review',
                              style: TextStyle(fontWeight: FontWeight.w900),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
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

  Widget _field(
    TextEditingController ctrl,
    String hint,
    String? Function(String?) validator, {
    TextInputType? keyboardType,
    int maxLines = 1,
  }) {
    return TextFormField(
      controller: ctrl,
      decoration: _deco(hint),
      validator: validator,
      keyboardType: keyboardType,
      maxLines: maxLines,
    );
  }
}
