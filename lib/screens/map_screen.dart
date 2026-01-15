import 'dart:ui';
import 'package:flutter/material.dart';

import 'paid_parking_screen.dart';
import 'private_parking_screen.dart';
import 'free_parking_screen.dart';

/// IMPORTANT:
/// This file keeps the name MapScreen to avoid breaking your existing navigation.
/// Functionally, it is now the "Parking Hub" screen.
class MapScreen extends StatelessWidget {
  final Map<String, dynamic> userData;

  const MapScreen({super.key, required this.userData});

  @override
  Widget build(BuildContext context) {
    return ParkingHubScreen(userData: userData);
  }
}

class ParkingHubScreen extends StatelessWidget {
  final Map<String, dynamic> userData;

  const ParkingHubScreen({super.key, required this.userData});

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
            expandedHeight: 260,
            elevation: 0,
            backgroundColor: Colors.transparent,
            flexibleSpace: FlexibleSpaceBar(
              background: _ParkingHeroHeader(
                onSmartTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text(
                        'Smart Parking is coming next (recommendation engine).',
                      ),
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      margin: const EdgeInsets.all(16),
                    ),
                  );
                },
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 120),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                const _SectionHeader(
                  title: 'Choose your parking type',
                  subtitle:
                      'Fast navigation • Clear choices • Scalable for future',
                ),
                const SizedBox(height: 14),

                _ParkingHeroTile(
                  title: 'Paid Parking',
                  subtitle:
                      'Official car parks, predictable pricing, closest options',
                  badge: 'Recommended',
                  icon: Icons.local_parking_rounded,
                  gradient: const [Color(0xFF0EA5E9), Color(0xFF6366F1)],
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const PaidParkingScreen(),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 12),

                _ParkingHeroTile(
                  title: 'Private Parking',
                  subtitle:
                      'Driveways & private spots — often cheaper, limited supply',
                  badge: 'Future marketplace',
                  icon: Icons.home_work_rounded,
                  gradient: const [Color(0xFF8B5CF6), Color(0xFF6366F1)],
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            PrivateParkingScreen(userData: userData),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 12),

                _ParkingHeroTile(
                  title: 'Free Parking Zones',
                  subtitle:
                      'Street zones with restrictions — always check signage',
                  badge: 'Check rules',
                  icon: Icons.map_rounded,
                  gradient: const [Color(0xFF111827), Color(0xFF334155)],
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const FreeParkingZonesScreen(),
                      ),
                    );
                  },
                ),

                const SizedBox(height: 18),

                const _SectionHeader(
                  title: 'Wembley tips',
                  subtitle: 'Small things that prevent big problems',
                ),
                const SizedBox(height: 12),

                const _TipCard(
                  icon: Icons.schedule_rounded,
                  title: 'Arrive early on event days',
                  subtitle:
                      'Aim 60–90 mins early to avoid congestion and closures.',
                ),
                const SizedBox(height: 10),
                const _TipCard(
                  icon: Icons.verified_rounded,
                  title: 'Prefer verified options',
                  subtitle:
                      'Paid & verified zones reduce risk of fines, towing, or closures.',
                ),
                const SizedBox(height: 10),
                const _TipCard(
                  icon: Icons.warning_amber_rounded,
                  title: 'Free zones can turn risky',
                  subtitle:
                      'Restrictions may change by time/day. Always read signage.',
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Premium UI components
// -----------------------------------------------------------------------------

class _ParkingHeroHeader extends StatelessWidget {
  final VoidCallback onSmartTap;

  const _ParkingHeroHeader({required this.onSmartTap});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Gradient background
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF0EA5E9), Color(0xFF6366F1), Color(0xFF8B5CF6)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),

        // Soft blobs
        Positioned(
          top: -90,
          right: -70,
          child: Container(
            height: 260,
            width: 260,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withOpacity(0.10),
            ),
          ),
        ),
        Positioned(
          bottom: -120,
          left: -90,
          child: Container(
            height: 280,
            width: 280,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withOpacity(0.08),
            ),
          ),
        ),

        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title row
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.16),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.22),
                        ),
                      ),
                      child: const Icon(
                        Icons.local_parking_rounded,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Parking',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.92),
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Find the right spot',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.6,
                              height: 1.08,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                const Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _HeroPill(icon: Icons.location_on_rounded, text: 'Wembley'),
                    _HeroPill(
                      icon: Icons.verified_rounded,
                      text: 'Verified zones',
                    ),
                    _HeroPill(
                      icon: Icons.refresh_rounded,
                      text: 'Updated daily',
                    ),
                  ],
                ),

                const Spacer(),

                // Smart parking card
                InkWell(
                  onTap: onSmartTap,
                  borderRadius: BorderRadius.circular(18),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.16),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.22),
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.18),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: const Icon(
                                Icons.auto_awesome_rounded,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Smart Parking (coming next): best option based on event time + distance.',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.92),
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                  height: 1.25,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.18),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: const Icon(
                                Icons.arrow_forward_rounded,
                                color: Colors.white,
                                size: 18,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
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
              fontWeight: FontWeight.w900,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _ParkingHeroTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final String badge;
  final IconData icon;
  final List<Color> gradient;
  final VoidCallback onTap;

  const _ParkingHeroTile({
    required this.title,
    required this.subtitle,
    required this.badge,
    required this.icon,
    required this.gradient,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        height: 120,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            colors: gradient,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.10),
              blurRadius: 22,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: Stack(
          children: [
            Positioned(
              top: 14,
              right: 14,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  badge,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
            Positioned(
              left: 14,
              top: 16,
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: Colors.white),
              ),
            ),
            Positioned(
              left: 14,
              right: 14,
              bottom: 14,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.90),
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;

  const _SectionHeader({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w900,
            color: Color(0xFF0F172A),
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: Color(0xFF64748B),
          ),
        ),
      ],
    );
  }
}

class _TipCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _TipCard({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
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
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFEEF2FF),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: const Color(0xFF4F46E5)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF0F172A),
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
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
