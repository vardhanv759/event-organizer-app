// manage_events_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'organize_event_sheet.dart';

class ManageEventsScreen extends StatelessWidget {
  final Map<String, dynamic> userData;

  const ManageEventsScreen({super.key, required this.userData});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('My Events')),
        body: const Center(
          child: Text('You must be logged in to manage events.'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Events'),
        backgroundColor: const Color(0xFF667EEA),
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('events_wembley')
            .where('organizerId', isEqualTo: user.uid)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const _EmptyState();
          }

          final docs = snapshot.data!.docs;

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            itemCount: docs.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final doc = docs[index];
              final data = doc.data();
              final name = data['name'] as String? ?? 'Untitled event';
              final venue = data['venueName'] as String? ?? 'Unknown venue';
              final ts = data['startDateTime'] as Timestamp?;
              final dt = ts?.toDate();
              final imageUrl =
                  data['thumbnailUrl'] as String? ??
                  data['imageUrl'] as String? ??
                  '';

              return _EventCard(
                name: name,
                venue: venue,
                dateTime: dt,
                imageUrl: imageUrl,
                onEdit: () {
                  showOrganizeEventSheet(
                    context,
                    userData: userData,
                    eventDoc: doc,
                  );
                },
                onDelete: () => _confirmDelete(context, doc),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Delete event?'),
          content: const Text(
            'This will permanently remove the event from the app.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirm != true) return;

    await doc.reference.delete();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Event deleted.'),
        backgroundColor: Colors.red.shade400,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFFEEF2FF),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.event_busy_rounded,
                size: 40,
                color: Color(0xFF667EEA),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'No events yet',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Once you create events as an organizer, they will appear here for editing and management.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade600,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EventCard extends StatelessWidget {
  final String name;
  final String venue;
  final DateTime? dateTime;
  final String imageUrl;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _EventCard({
    required this.name,
    required this.venue,
    required this.dateTime,
    required this.imageUrl,
    required this.onEdit,
    required this.onDelete,
  });

  String _formatDateTime(DateTime? dt) {
    if (dt == null) return 'Date TBC';
    String two(int v) => v.toString().padLeft(2, '0');
    final date = '${two(dt.day)}/${two(dt.month)}/${dt.year}';
    final time = '${two(dt.hour)}:${two(dt.minute)}';
    return '$date • $time';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: Colors.grey.shade100, width: 1.2),
      ),
      child: Row(
        children: [
          if (imageUrl.isNotEmpty)
            ClipRRect(
              borderRadius: const BorderRadius.horizontal(
                left: Radius.circular(20),
              ),
              child: Image.network(
                imageUrl,
                width: 90,
                height: 90,
                fit: BoxFit.cover,
              ),
            )
          else
            Container(
              width: 90,
              height: 90,
              decoration: const BoxDecoration(
                borderRadius: BorderRadius.horizontal(
                  left: Radius.circular(20),
                ),
                color: Color(0xFFEEF2FF),
              ),
              child: const Icon(Icons.event_rounded, color: Color(0xFF667EEA)),
            ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 12.0,
                vertical: 10,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    venue,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatDateTime(dateTime),
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade500,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Column(
            children: [
              IconButton(
                icon: const Icon(Icons.edit_rounded),
                color: const Color(0xFF3B82F6),
                onPressed: onEdit,
                tooltip: 'Edit event',
              ),
              IconButton(
                icon: const Icon(Icons.delete_rounded),
                color: Colors.red.shade400,
                onPressed: onDelete,
                tooltip: 'Delete event',
              ),
            ],
          ),
        ],
      ),
    );
  }
}
