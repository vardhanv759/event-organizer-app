import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'map_screen.dart';
import 'private_parking_screen.dart';

class ParkingHubScreen extends StatelessWidget {
  final Map<String, dynamic> userData;

  const ParkingHubScreen({super.key, required this.userData});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FF),
      appBar: AppBar(
        title: const Text('Parking'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 22),
        child: Column(
          children: [
            _BigActionCard(
              title: 'Paid Parking',
              subtitle: 'Car parks, tariffs, and walking distance.',
              icon: Icons.local_parking_rounded,
              gradient: const [Color(0xFF22C55E), Color(0xFF0EA5E9)],
              onTap: () {
                if (kIsWeb) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const _WebMapNoticeScreen(),
                    ),
                  );
                  return;
                }
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => MapScreen(userData: userData),
                  ),
                );
              },
            ),
            const SizedBox(height: 14),
            _BigActionCard(
              title: 'Free Parking Zones',
              subtitle: 'Discover free zones and restrictions.',
              icon: Icons.park_rounded,
              gradient: const [Color(0xFF111827), Color(0xFF334155)],
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        const _ComingSoonScreen(title: 'Free Parking Zones'),
                  ),
                );
              },
            ),
            const SizedBox(height: 14),
            _BigActionCard(
              title: 'Private Parking',
              subtitle: 'Book local private spaces or list yours.',
              icon: Icons.home_work_rounded,
              gradient: const [Color(0xFF6366F1), Color(0xFF8B5CF6)],
              badge: 'New',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PrivateParkingScreen(userData: userData),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _BigActionCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final List<Color> gradient;
  final String? badge;
  final VoidCallback onTap;

  const _BigActionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.gradient,
    required this.onTap,
    this.badge,
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
              height: 52,
              width: 52,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.18),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white.withOpacity(0.22)),
              ),
              child: Icon(icon, color: Colors.white, size: 26),
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
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ),
                      if (badge != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.20),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.22),
                            ),
                          ),
                          child: Text(
                            badge!,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 11,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.90),
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

class _ComingSoonScreen extends StatelessWidget {
  final String title;
  const _ComingSoonScreen({required this.title});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FF),
      appBar: AppBar(
        title: Text(title),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: const Padding(
        padding: EdgeInsets.all(18),
        child: Text(
          'Coming soon.\n\nNext, we will implement this with premium UI and real data.',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: Color(0xFF334155),
            height: 1.4,
          ),
        ),
      ),
    );
  }
}

class _WebMapNoticeScreen extends StatelessWidget {
  const _WebMapNoticeScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FF),
      appBar: AppBar(
        title: const Text('Paid Parking'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: const Padding(
        padding: EdgeInsets.all(18),
        child: Text(
          'Live Google Maps is currently disabled on Web for stability.\n\nPlease run on Android/iOS for the full map.',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: Color(0xFF334155),
            height: 1.4,
          ),
        ),
      ),
    );
  }
}
