import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'private_parking_messages_screen.dart';
import 'parking_provider_apply_screen.dart';
import 'parking_provider_dashboard_screen.dart';
import 'private_parking_nearby_screen.dart';
import 'wembley_communities_screen.dart';

class PrivateParkingScreen extends StatelessWidget {
  final Map<String, dynamic> userData;

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
        title: const Text(
          'Private Parking',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            color: Color(0xFF0F172A),
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFF0F172A)),
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

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header text
                const Text(
                  'Quick Actions',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF0F172A),
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Choose an option to get started',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF64748B),
                  ),
                ),
                const SizedBox(height: 20),

                // 2x2 Grid Layout
                _buildGrid(context, status),

                const SizedBox(height: 24),

                // How it works section
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
            ),
          );
        },
      ),
    );
  }

  Widget _buildGrid(BuildContext context, String status) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 14,
      crossAxisSpacing: 14,
      childAspectRatio: 0.95,
      children: [
        // 1. Become a Host / Manage Your Space (changes based on status)
        _GridCard(
          title: status == 'approved' ? 'Manage Your\nSpace' : 'Become\na Host',
          icon: status == 'approved'
              ? Icons.dashboard_rounded
              : Icons.add_business_rounded,
          gradient: status == 'approved'
              ? const [
                  Color(0xFF10B981),
                  Color(0xFF059669),
                ] // Green for approved providers
              : const [
                  Color(0xFF0EA5E9),
                  Color(0xFF6366F1),
                ], // Blue for new applicants
          badgeText: status == 'pending' ? 'Pending' : null,
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

        // 2. Find Parking
        _GridCard(
          title: 'Find Parking',
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

        // 3. Messages
        _GridCard(
          title: 'Messages',
          icon: Icons.chat_bubble_rounded,
          gradient: const [
            Color.fromARGB(255, 29, 18, 239),
            Color.fromARGB(255, 141, 68, 236),
          ],
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const PrivateParkingMessagesScreen(),
              ),
            );
          },
        ),

        // 4. Community Hub
        _GridCard(
          title: 'Community Hub',
          icon: Icons.location_city_rounded,
          gradient: const [Color(0xFFEC4899), Color(0xFF8B5CF6)],
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const WembleyCommunitiesScreen(),
              ),
            );
          },
        ),
      ],
    );
  }
}

// Grid Card Widget (Home Screen Style)
class _GridCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Color> gradient;
  final VoidCallback onTap;
  final String? badgeText;

  const _GridCard({
    required this.title,
    required this.icon,
    required this.gradient,
    required this.onTap,
    this.badgeText,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: LinearGradient(
            colors: gradient,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: gradient[0].withOpacity(0.3),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Stack(
          children: [
            // Content
            Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Icon
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.3),
                        width: 1,
                      ),
                    ),
                    child: Icon(icon, color: Colors.white, size: 28),
                  ),

                  const Spacer(),

                  // Title
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      height: 1.2,
                      letterSpacing: -0.5,
                    ),
                  ),
                ],
              ),
            ),

            // Badge
            if (badgeText != null)
              Positioned(
                top: 12,
                right: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.25),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withOpacity(0.4)),
                  ),
                  child: Text(
                    badgeText!,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 10,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// Info Card (unchanged)
class _InfoCard extends StatelessWidget {
  final String title;
  final List<String> points;

  const _InfoCard({required this.title, required this.points});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFEEF2FF),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.info_outline_rounded,
                  color: Color(0xFF6366F1),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF0F172A),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...points.map(
            (p) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 2),
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: const Color(0xFF22C55E).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(
                      Icons.check_rounded,
                      size: 14,
                      color: Color(0xFF22C55E),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      p,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF475569),
                        height: 1.4,
                        fontSize: 14,
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
