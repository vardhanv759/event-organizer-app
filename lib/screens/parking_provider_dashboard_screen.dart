import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'parking_space_register_screen.dart';
import 'manage_parking_space_screen.dart';

class ParkingProviderDashboardScreen extends StatelessWidget {
  const ParkingProviderDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final uid = user?.uid;

    if (uid == null) {
      return const Scaffold(
        body: Center(child: Text('Please sign in to continue.')),
      );
    }

    final userRef = FirebaseFirestore.instance.collection('users').doc(uid);

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FF),
      appBar: AppBar(
        title: const Text('Provider Dashboard'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: userRef.snapshots(),
          builder: (context, userSnap) {
            final userData = userSnap.data?.data() ?? <String, dynamic>{};
            final status =
                ((userData['parkingProviderStatus'] ??
                            userData['parkingProvider_status'] ??
                            'approved')
                        as String?)
                    ?.trim()
                    .toLowerCase() ??
                'approved';

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _TopStatusCard(status: status),
                const SizedBox(height: 14),
                const Text(
                  'Your spaces',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: _CompositeSpacesList(
                    uid: uid,
                    userData: userData,
                    userEmail: user?.email ?? '',
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ✅ FIX: Composite queries for both field names
class _CompositeSpacesList extends StatelessWidget {
  final String uid;
  final Map<String, dynamic> userData;
  final String userEmail;

  const _CompositeSpacesList({
    required this.uid,
    required this.userData,
    required this.userEmail,
  });

  @override
  Widget build(BuildContext context) {
    final spacesRef = FirebaseFirestore.instance.collection('parking_spaces');

    // ✅ Query 1: New field name (providerId)
    final query1 = spacesRef.where('providerId', isEqualTo: uid);

    // ✅ Query 2: Old field name (provider_uid)
    final query2 = spacesRef.where('provider_uid', isEqualTo: uid);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: query1.snapshots(),
      builder: (context, snap1) {
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: query2.snapshots(),
          builder: (context, snap2) {
            if (snap1.hasError || snap2.hasError) {
              return _ErrorBox(
                text: 'Error loading spaces: ${snap1.error ?? snap2.error}',
              );
            }

            if (snap1.connectionState == ConnectionState.waiting ||
                snap2.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            // ✅ Merge results from both queries
            final docs1 = snap1.data?.docs ?? [];
            final docs2 = snap2.data?.docs ?? [];

            // Deduplicate by document ID
            final seenIds = <String>{};
            final allDocs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];

            for (final doc in [...docs1, ...docs2]) {
              if (!seenIds.contains(doc.id)) {
                seenIds.add(doc.id);
                allDocs.add(doc);
              }
            }

            // Sort by creation date
            allDocs.sort((a, b) {
              final at = a.data()['createdAt'] ?? a.data()['created_at'];
              final bt = b.data()['createdAt'] ?? b.data()['created_at'];
              final aMs = (at is Timestamp) ? at.millisecondsSinceEpoch : 0;
              final bMs = (bt is Timestamp) ? bt.millisecondsSinceEpoch : 0;
              return bMs.compareTo(aMs);
            });

            if (allDocs.isEmpty) {
              return _EmptyState(
                onAdd: () {
                  final mergedUserData = <String, dynamic>{
                    ...userData,
                    'uid': uid,
                    'email': userEmail,
                  };
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          ParkingSpaceRegisterScreen(userDoc: mergedUserData),
                    ),
                  );
                },
              );
            }

            return ListView.separated(
              padding: const EdgeInsets.only(bottom: 90),
              itemCount: allDocs.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final doc = allDocs[i];
                final d = doc.data();

                // Support both old and new field names
                final title = (d['title'] as String?)?.trim().isEmpty == false
                    ? (d['title'] as String).trim()
                    : 'Private parking';
                final postcode = (d['postcode'] as String?)?.trim() ?? '';

                // Support approxArea, approx_area, area
                final areaValue =
                    d['approxArea'] ?? d['approx_area'] ?? d['area'];
                final area = (areaValue as String?)?.trim() ?? 'Wembley';

                // Support hourlyRate, hourly_rate_gbp
                final hourlyValue = d['hourlyRate'] ?? d['hourly_rate_gbp'];
                final hourly = (hourlyValue is num)
                    ? hourlyValue.toDouble()
                    : 0.0;

                // Support status, status_lc
                final statusValue = d['status'] ?? d['status_lc'];
                final statusText =
                    (statusValue as String?)?.trim() ?? 'pending';

                return _SpaceCard(
                  title: title,
                  subtitle: postcode.isNotEmpty ? '$postcode • $area' : area,
                  price: '£${hourly.toStringAsFixed(2)}/hr',
                  status: statusText,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            ManageParkingSpaceScreen(spaceId: doc.id),
                      ),
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }
}

class _TopStatusCard extends StatelessWidget {
  final String status;
  const _TopStatusCard({required this.status});

  @override
  Widget build(BuildContext context) {
    final isApproved = status == 'approved';

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
      child: Row(
        children: [
          Container(
            height: 44,
            width: 44,
            decoration: BoxDecoration(
              color: isApproved
                  ? const Color(0xFFECFDF5)
                  : const Color(0xFFFFFBEB),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              isApproved ? Icons.verified_rounded : Icons.hourglass_bottom,
              color: isApproved
                  ? const Color(0xFF16A34A)
                  : const Color(0xFFB45309),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isApproved ? 'Approved provider' : 'Pending review',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  isApproved
                      ? 'You can add and manage your private parking spaces.'
                      : 'Your account is under manual verification.',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF64748B),
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SpaceCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String price;
  final String status;
  final VoidCallback onTap;

  const _SpaceCard({
    required this.title,
    required this.subtitle,
    required this.price,
    required this.status,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final s = status.trim().toLowerCase();
    final isApproved = s == 'approved';
    final chipBg = isApproved
        ? const Color(0xFFECFDF5)
        : const Color(0xFFFFFBEB);
    final chipFg = isApproved
        ? const Color(0xFF16A34A)
        : const Color(0xFFB45309);

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
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
        child: Row(
          children: [
            Container(
              height: 56,
              width: 56,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF0EA5E9), Color(0xFF6366F1)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(
                Icons.local_parking_rounded,
                color: Colors.white,
                size: 28,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF64748B),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: chipBg,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          isApproved ? 'Approved' : 'Pending',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            color: chipFg,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        price,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF1D4ED8),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: Color(0xFF64748B)),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
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
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.add_road_rounded,
              size: 42,
              color: Color(0xFF6366F1),
            ),
            const SizedBox(height: 10),
            const Text(
              'No spaces yet',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 16,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Add your first private parking space to make it visible (after approval).',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: Color(0xFF64748B),
                height: 1.25,
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: onAdd,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4F46E5),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                icon: const Icon(Icons.add_rounded),
                label: const Text(
                  'Add space',
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

class _ErrorBox extends StatelessWidget {
  final String text;
  const _ErrorBox({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFDE68A)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontWeight: FontWeight.w800,
          color: Color(0xFF92400E),
          height: 1.25,
        ),
      ),
    );
  }
}
