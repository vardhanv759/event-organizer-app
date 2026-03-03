import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'private_parking_messages_screen.dart';
import 'parking_provider_apply_screen.dart';
import 'parking_provider_dashboard_screen.dart';
import 'private_parking_nearby_screen.dart';
import 'wembley_communities_screen.dart';

class PrivateParkingScreen extends StatelessWidget {
  final Map<String, dynamic>
  userData; // keep for compatibility with your routing
  const PrivateParkingScreen({super.key, required this.userData});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    if (uid == null) {
      return const Scaffold(
        body: Center(child: Text('Please sign in to continue.')),
      );
    }

    final userRef = FirebaseFirestore.instance.collection('users').doc(uid);

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FF),
      appBar: AppBar(
        title: const Text('Private Parking'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: userRef.snapshots(),
        builder: (context, snap) {
          final userDoc = snap.data?.data() ?? <String, dynamic>{};

          final status =
              ((userDoc['parkingProviderStatus'] ??
                          userDoc['parkingProvider_status'] ??
                          userDoc['parkingProvider'] ??
                          userDoc['parkingProviderApproved'])
                      as String?)
                  ?.trim()
                  .toLowerCase() ??
              'none';

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 22),
            children: [
              _BigRowButton(
                title: 'Become a Host',
                subtitle: status == 'approved'
                    ? 'Manage your spaces and add new listings.'
                    : 'Earn money by renting your driveway/bay.',
                icon: Icons.add_business_rounded,
                gradient: const [Color(0xFF0EA5E9), Color(0xFF6366F1)],
                badgeText: status == 'approved'
                    ? 'Approved provider'
                    : (status == 'pending' ? 'Pending review' : null),
                onTap: () async {
                  if (status == 'approved') {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const ParkingProviderDashboardScreen(),
                      ),
                    );
                    return;
                  }

                  if (status == 'pending') {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Your provider application is pending manual review.',
                        ),
                      ),
                    );
                    return;
                  }

                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ParkingProviderApplyScreen(),
                    ),
                  );
                },
              ),
              const SizedBox(height: 14),
              _BigRowButton(
                title: 'Find Parking nearby',
                subtitle: 'Browse and book private spaces around Wembley.',
                icon: Icons.location_on_rounded,
                gradient: const [Color(0xFF8B5CF6), Color(0xFF6366F1)],
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const PrivateParkingNearbyScreen(),
                    ),
                  );
                },
              ),
              const SizedBox(height: 14),
              _BigRowButton(
                title: 'Messages',
                subtitle: 'Requests and chats with drivers/providers.',
                icon: Icons.chat_bubble_rounded,
                gradient: const [Color(0xFF22C55E), Color(0xFF0EA5E9)],
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const PrivateParkingMessagesScreen(),
                    ),
                  );
                },
              ),
              const SizedBox(height: 14), // ✅ FIX: spacing added here
              _BigRowButton(
                title: 'Community Hub',
                subtitle: 'Join your local zone and connect.',
                icon: Icons.location_city_rounded,
                gradient: const [Color(0xFFEC4899), Color(0xFF8B5CF6)],
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const WembleyCommunitiesScreen(),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              _InfoCard(
                title: 'How it works',
                points: const [
                  'Providers apply and are manually approved.',
                  'Approved providers can add spaces from the Provider Dashboard.',
                  'Only approved spaces become visible to drivers.',
                  'Drivers choose date/time + hours and pay (Stripe phase).',
                  'Exact address is shown only after payment (Stripe phase).',
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _BigRowButton extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final List<Color> gradient;
  final VoidCallback onTap;
  final String? badgeText;

  const _BigRowButton({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.gradient,
    required this.onTap,
    this.badgeText,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: LinearGradient(
            colors: gradient,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.12),
              blurRadius: 22,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.18),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white.withOpacity(0.22)),
              ),
              child: Icon(icon, color: Colors.white),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ),
                      if (badgeText != null) ...[
                        const SizedBox(width: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.18),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.22),
                            ),
                          ),
                          child: Text(
                            badgeText!,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.92),
                      fontWeight: FontWeight.w700,
                      height: 1.25,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            const Icon(
              Icons.chevron_right_rounded,
              color: Colors.white,
              size: 28,
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final String title;
  final List<String> points;

  const _InfoCard({required this.title, required this.points});

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
          const SizedBox(height: 10),
          ...points.map(
            (p) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.check_circle_rounded,
                    size: 18,
                    color: Color(0xFF22C55E),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      p,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF334155),
                        height: 1.25,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
