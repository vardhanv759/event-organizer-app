import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'parking_space_register_screen.dart';
import 'parking_space_details_screen.dart';

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
    final spacesQuery = FirebaseFirestore.instance
        .collection('parking_spaces')
        .where('provider_uid', isEqualTo: uid);
    // IMPORTANT: no orderBy here to avoid composite index requirement.

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
                  child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: spacesQuery.snapshots(),
                    builder: (context, snap) {
                      if (snap.hasError) {
                        return _ErrorBox(
                          text:
                              'Error loading spaces: ${snap.error}\n\nTip: If you re-add orderBy() later, Firestore may require a composite index.',
                        );
                      }
                      if (snap.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      final docs = snap.data?.docs ?? [];

                      // Client-side sort by created_at desc (if present)
                      docs.sort((a, b) {
                        final at = a.data()['created_at'];
                        final bt = b.data()['created_at'];
                        final aMs = (at is Timestamp)
                            ? at.millisecondsSinceEpoch
                            : 0;
                        final bMs = (bt is Timestamp)
                            ? bt.millisecondsSinceEpoch
                            : 0;
                        return bMs.compareTo(aMs);
                      });

                      if (docs.isEmpty) {
                        return _EmptyState(
                          onAdd: () {
                            final mergedUserData = <String, dynamic>{
                              ...userData,
                              'uid': uid,
                              'email': user?.email ?? '',
                            };
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ParkingSpaceRegisterScreen(
                                  userDoc: mergedUserData,
                                ),
                              ),
                            );
                          },
                        );
                      }

                      return ListView.separated(
                        padding: const EdgeInsets.only(bottom: 90),
                        itemCount: docs.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, i) {
                          final doc = docs[i];
                          final d = doc.data();
                          final title =
                              (d['title'] as String?)?.trim().isEmpty == false
                              ? (d['title'] as String).trim()
                              : 'Private parking';
                          final postcode =
                              (d['postcode'] as String?)?.trim() ?? '';
                          final area =
                              (d['approx_area'] as String?)?.trim() ??
                              'Wembley';
                          final hourly = (d['hourly_rate_gbp'] is num)
                              ? (d['hourly_rate_gbp'] as num).toDouble()
                              : 0.0;
                          final statusText =
                              (d['status'] as String?)?.trim() ?? 'pending';

                          return _SpaceCard(
                            title: title,
                            subtitle: postcode.isNotEmpty
                                ? '$postcode • $area'
                                : area,
                            price: '£${hourly.toStringAsFixed(2)}/hr',
                            status: statusText,
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ParkingSpaceDetailsScreen(
                                    spaceId: doc.id,
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      );
                    },
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
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.shield_rounded, color: Color(0xFF64748B)),
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
