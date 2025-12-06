import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

/// ===============================
/// EVENTS LIST (current + upcoming)
/// ===============================
class EventsListScreen extends StatelessWidget {
  const EventsListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();

    final query = FirebaseFirestore.instance
        .collection('events')
        // keep only events that are about to start or already ongoing
        .where(
          'startTime',
          isGreaterThanOrEqualTo: Timestamp.fromDate(
            now.subtract(const Duration(hours: 2)),
          ),
        )
        .orderBy('startTime');

    return Scaffold(
      appBar: AppBar(title: const Text('Events near Wembley')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: query.snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          final docs = snapshot.data?.docs ?? [];
          if (docs.isEmpty) {
            return const Center(
              child: Text('No events added yet for Wembley.'),
            );
          }

          final now = DateTime.now();

          final events = docs.map((doc) {
            final data = doc.data();
            final start = (data['startTime'] as Timestamp).toDate();
            final end = (data['endTime'] as Timestamp).toDate();
            return _EventItem(
              id: doc.id,
              name: data['name'] ?? '',
              venue: data['venueName'] ?? data['venueAddress'] ?? '',
              address: data['address'] ?? data['venueAddress'] ?? '',
              startTime: start,
              endTime: end,
              city: data['city'] ?? '',
            );
          }).toList();

          final current = events.where((e) {
            return e.startTime.isBefore(now) && e.endTime.isAfter(now);
          }).toList();

          final upcoming = events.where((e) {
            return e.startTime.isAfter(now);
          }).toList();

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (current.isNotEmpty) ...[
                const Text(
                  'Currently Happening',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                ...current.map((e) => _EventCard(event: e)),
                const SizedBox(height: 24),
              ],
              const Text(
                'Upcoming Events',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              if (upcoming.isEmpty)
                const Text(
                  'No upcoming events yet.',
                  style: TextStyle(color: Colors.grey),
                )
              else
                ...upcoming.map((e) => _EventCard(event: e)),
            ],
          );
        },
      ),
    );
  }
}

class _EventItem {
  final String id;
  final String name;
  final String venue;
  final String address;
  final DateTime startTime;
  final DateTime endTime;
  final String city;

  _EventItem({
    required this.id,
    required this.name,
    required this.venue,
    required this.address,
    required this.startTime,
    required this.endTime,
    required this.city,
  });
}

class _EventCard extends StatelessWidget {
  final _EventItem event;

  const _EventCard({required this.event});

  String _formatTimeRange(DateTime start, DateTime end) {
    String two(int v) => v.toString().padLeft(2, '0');
    final s = '${two(start.hour)}:${two(start.minute)}';
    final e = '${two(end.hour)}:${two(end.minute)}';
    final date = '${two(start.day)}/${two(start.month)}/${start.year}';
    return '$date  •  $s - $e';
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
        title: Text(
          event.name,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(event.venue, style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 2),
            Text(
              _formatTimeRange(event.startTime, event.endTime),
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () {
          // later: open event details / map
        },
      ),
    );
  }
}

/// ========================================
/// ORGANIZER APPLICATION (Become organizer)
/// ========================================
class OrganizerApplicationScreen extends StatefulWidget {
  const OrganizerApplicationScreen({super.key});

  @override
  State<OrganizerApplicationScreen> createState() =>
      _OrganizerApplicationScreenState();
}

class _OrganizerApplicationScreenState
    extends State<OrganizerApplicationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _fullNameController = TextEditingController();
  final _dobController = TextEditingController();
  final _idTypeController = TextEditingController();
  final _idNumberController = TextEditingController();

  DateTime? _selectedDob;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _fullNameController.dispose();
    _dobController.dispose();
    _idTypeController.dispose();
    _idNumberController.dispose();
    super.dispose();
  }

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final initial = DateTime(now.year - 25, now.month, now.day);

    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDob ?? initial,
      firstDate: DateTime(1950),
      lastDate: DateTime(now.year - 18, now.month, now.day),
    );

    if (picked != null) {
      setState(() {
        _selectedDob = picked;
        _dobController.text =
            '${picked.day.toString().padLeft(2, '0')}/${picked.month.toString().padLeft(2, '0')}/${picked.year}';
      });
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _isSubmitting = true);

    try {
      final firestore = FirebaseFirestore.instance;

      await firestore.collection('organizer_requests').doc(user.uid).set({
        'userId': user.uid,
        'email': user.email,
        'fullName': _fullNameController.text.trim(),
        'dob': _dobController.text.trim(),
        'idType': _idTypeController.text.trim(),
        'idNumber': _idNumberController.text.trim(),
        // TODO: attach a file upload URL here later using Firebase Storage
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });

      // mark status on user document
      await firestore.collection('users').doc(user.uid).set({
        'organizerStatus': 'pending',
        'isOrganizer': false,
      }, SetOptions(merge: true));

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Processing your request, we will review and confirm your role.',
          ),
        ),
      );

      Navigator.of(context).pop(); // back to profile
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to submit request: $e')));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Become an Organizer')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              const Text(
                'Provide your details to become an event organizer for Wembley events. '
                'We will manually review and verify your application.',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _fullNameController,
                decoration: const InputDecoration(
                  labelText: 'Full Name',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _dobController,
                readOnly: true,
                onTap: _pickDob,
                decoration: const InputDecoration(
                  labelText: 'Date of Birth',
                  border: OutlineInputBorder(),
                  suffixIcon: Icon(Icons.cake_outlined),
                ),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Please select DOB' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _idTypeController,
                decoration: const InputDecoration(
                  labelText: 'ID Type (e.g. Passport, Driving Licence)',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _idNumberController,
                decoration: const InputDecoration(
                  labelText: 'ID Number',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blueGrey.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'ID proof upload will be added later. For now we store your ID type and number safely in Firestore.',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isSubmitting ? null : _submit,
                  child: _isSubmitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Submit Application'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// ==============================
/// CREATE EVENT (for organizers)
/// ==============================
class CreateEventScreen extends StatefulWidget {
  const CreateEventScreen({super.key});

  @override
  State<CreateEventScreen> createState() => _CreateEventScreenState();
}

class _CreateEventScreenState extends State<CreateEventScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _venueNameController = TextEditingController();
  final _addressController = TextEditingController();

  DateTime? _startTime;
  DateTime? _endTime;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _nameController.dispose();
    _venueNameController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _pickStart() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null) return;

    final time = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 19, minute: 0),
    );
    if (time == null) return;

    setState(() {
      _startTime = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  Future<void> _pickEnd() async {
    final base = _startTime ?? DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: base,
      lastDate: base.add(const Duration(days: 3)),
    );
    if (date == null) return;

    final time = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 22, minute: 0),
    );
    if (time == null) return;

    setState(() {
      _endTime = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_startTime == null || _endTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select start and end time')),
      );
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _isSubmitting = true);

    try {
      await FirebaseFirestore.instance.collection('events').add({
        'name': _nameController.text.trim(),
        'venueName': _venueNameController.text.trim(),
        'address': _addressController.text.trim(),
        'city': 'Wembley',
        'startTime': Timestamp.fromDate(_startTime!),
        'endTime': Timestamp.fromDate(_endTime!),
        'createdBy': user.uid,
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Event created successfully')),
      );
      Navigator.of(context).pop(); // back to profile
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to create event: $e')));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  String _formatDateTime(DateTime? dt) {
    if (dt == null) return 'Select';
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(dt.day)}/${two(dt.month)}/${dt.year}  ${two(dt.hour)}:${two(dt.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create Event (Wembley)')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Event Name',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _venueNameController,
                decoration: const InputDecoration(
                  labelText: 'Venue Name',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _addressController,
                decoration: const InputDecoration(
                  labelText: 'Venue Address',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Start Time'),
                subtitle: Text(_formatDateTime(_startTime)),
                trailing: const Icon(Icons.access_time),
                onTap: _pickStart,
              ),
              const Divider(),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('End Time'),
                subtitle: Text(_formatDateTime(_endTime)),
                trailing: const Icon(Icons.access_time),
                onTap: _pickEnd,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isSubmitting ? null : _submit,
                  icon: const Icon(Icons.check_rounded),
                  label: _isSubmitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Create Event'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
