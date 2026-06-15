import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'my_profile_screen.dart';
import 'search_screen.dart'; // Advanced multi-collection search
import 'settings_screen.dart';
import 'help_and_support_screen.dart';
import 'favorites_screen.dart';

import 'my_bookings_screen.dart';
import 'private_parking_messages_screen.dart';
import '../services/zone_prompt_service.dart';
import '../services/zone_utils.dart';
import 'wembley_communities_screen.dart';

import 'events_screen.dart';
import 'dining_screen.dart';
import 'parking_hub_screen.dart' as hub;

import 'offers_screen.dart';
import 'ai_planner_screen.dart';
import 'accommodation_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeUi {
  static const Color bg = Color(0xFFFBFBFD);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color border = Color(0xFFEEF0F6);

  static const Color primary = Color(0xFF4C6EF5); // Electric Indigo
  static const Color primarySoft = Color(0xFFEEF2FF);

  static const Color text = Color(0xFF0B1220);
  static const Color textMuted = Color(0xFF667085);
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  // ---- spacing system (single source of truth)
  static const double _pad = 16;
  static const double _padSm = 12;
  static const double _radiusLg = 22;
  static const double _gap8 = 8;
  static const double _gap12 = 12;
  static const double _gap16 = 16;
  static const double _gap24 = 24;

  int _selectedIndex = 0;

  bool _isCheckingEmailVerification = false;
  bool _isResendingVerification = false;

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  void setTab(int index) => setState(() => _selectedIndex = index);

  void _openProfileDrawer() {
    _scaffoldKey.currentState?.openEndDrawer();
  }

  bool _zonePromptShown = false;

  Future<void> maybePromptZoneJoin({
    required double lat,
    required double lng,
    required String displayName,
    required String photoUrl,
  }) async {
    if (_zonePromptShown) return; // avoid repeated prompts in same session
    _zonePromptShown = true;

    final zoneId = ZoneUtils.zoneIdFor(lat, lng);
    if (zoneId == null) return; // not inside Wembley 3-mile radius

    final decision = await ZonePromptService.getDecisionForZone(zoneId);
    if (decision == 'rejected' || decision == 'accepted') return;

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 46,
                height: 5,
                decoration: BoxDecoration(
                  color: const Color(0xFFE2E8F0),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                "Join your Wembley public group?",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 6),
              Text(
                "You’re currently inside the 3-mile Wembley zone. Join to chat with providers and see local updates.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade700),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () async {
                        await ZonePromptService.setDecision(
                          zoneId: zoneId,
                          decision: 'rejected',
                        );
                        if (mounted) Navigator.pop(context);
                      },
                      child: const Text("No, don’t ask again"),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        await ZonePromptService.joinZone(
                          zoneId: zoneId,
                          displayName: displayName,
                          photoUrl: photoUrl,
                        );
                        if (mounted) Navigator.pop(context);
                      },
                      child: const Text("Join"),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
            ],
          ),
        );
      },
    );
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _buildPremiumLogoutDialog(),
    );

    if (confirm == true) {
      if (!kIsWeb) {
        await GoogleSignIn.instance.signOut();
      }
      await FirebaseAuth.instance.signOut();
    }
  }

  Stream<int> _pendingChatRequestsCountStream(String uid) {
    return FirebaseFirestore.instance
        .collection('chat_requests')
        .where('to_uid', isEqualTo: uid)
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .map((s) => s.docs.length);
  }

  Future<void> _checkEmailVerified() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _isCheckingEmailVerification = true);
    try {
      await user.reload();
      final refreshed = FirebaseAuth.instance.currentUser;
      final verified = refreshed?.emailVerified ?? false;

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            verified
                ? 'Email verified successfully. Enjoy all features!'
                : 'Verification not detected yet. Please open the email link and try again.',
          ),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          margin: const EdgeInsets.all(16),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to check verification: $e'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          margin: const EdgeInsets.all(16),
        ),
      );
    } finally {
      if (mounted) setState(() => _isCheckingEmailVerification = false);
    }
  }

  Future<void> _resendVerificationEmail() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _isResendingVerification = true);
    try {
      await user.sendEmailVerification();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Verification link re-sent to ${user.email}. Please check spam/junk too.',
          ),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          margin: const EdgeInsets.all(16),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to send verification email: $e'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          margin: const EdgeInsets.all(16),
        ),
      );
    } finally {
      if (mounted) setState(() => _isResendingVerification = false);
    }
  }

  Widget _buildEmailVerificationOverlay(String? email) {
    final emailText = email ?? 'your email address';

    return Positioned.fill(
      child: Container(
        color: Colors.black.withOpacity(0.56),
        child: Center(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 18),
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.25),
                  blurRadius: 30,
                  offset: const Offset(0, 16),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF6366F1).withOpacity(0.10),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.mark_email_unread_rounded,
                    size: 34,
                    color: Color(0xFF6366F1),
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Verify your email',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: _HomeUi.text,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'We sent a verification link to:\n$emailText\n\nVerify to unlock all features.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF475569),
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Row(
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        size: 18,
                        color: _HomeUi.textMuted,
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Tip: Check Spam/Junk if you don’t see it.',
                          style: TextStyle(
                            fontSize: 12,
                            color: _HomeUi.textMuted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isCheckingEmailVerification
                        ? null
                        : _checkEmailVerified,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6366F1),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 0,
                    ),
                    child: _isCheckingEmailVerification
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white,
                              ),
                            ),
                          )
                        : const Text(
                            'I’ve verified my email',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _isResendingVerification
                      ? null
                      : _resendVerificationEmail,
                  child: _isResendingVerification
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text(
                          'Resend verification link',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPremiumLogoutDialog() {
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.18),
                blurRadius: 28,
                offset: const Offset(0, 18),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFEF4444), Color(0xFFF97316)],
                  ),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(
                  Icons.logout_rounded,
                  color: Colors.white,
                  size: 26,
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Sign out?',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: _HomeUi.text,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'You will need to sign in again to access your account.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: _HomeUi.textMuted,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: BorderSide(
                            color: Colors.grey.shade200,
                            width: 1.4,
                          ),
                        ),
                      ),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: _HomeUi.text,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        backgroundColor: const Color(0xFFEF4444),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 0,
                      ),
                      child: const Text(
                        'Sign out',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Premium bottom navigation (5 tabs)
  // ---------------------------------------------------------------------------
  Widget _buildPremiumBottomNav() {
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 14),
      decoration: BoxDecoration(
        color: const Color.fromARGB(255, 255, 255, 255),
        borderRadius: BorderRadius.circular(_radiusLg),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 26,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: _PremiumNavItem(
                  isSelected: _selectedIndex == 0,
                  icon: Icons.explore_rounded,
                  label: 'Explore',
                  onTap: () => setTab(0),
                ),
              ),
              Expanded(
                child: _PremiumNavItem(
                  isSelected: _selectedIndex == 1,
                  icon: Icons.favorite_outline_rounded,
                  label: 'Favorites',
                  onTap: () => setTab(1),
                ),
              ),
              Expanded(
                child: _PremiumNavItem(
                  isSelected: _selectedIndex == 2,
                  icon: Icons.local_parking_rounded,
                  label: 'Parking',
                  onTap: () => setTab(2),
                ),
              ),
              Expanded(
                child: _PremiumNavItem(
                  isSelected: _selectedIndex == 3,
                  icon: Icons.calendar_month_rounded,
                  label: 'Bookings',
                  onTap: () => setTab(3),
                ),
              ),
              Expanded(
                child: _PremiumNavItem(
                  isSelected: _selectedIndex == 4,
                  icon: Icons.help_outline_rounded,
                  label: 'Help & Support',
                  onTap: () => setTab(4),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBodyForTab(
    BuildContext context,
    int index,
    Map<String, dynamic> userData,
  ) {
    switch (index) {
      case 0:
        return ExploreTabPremium(
          userData: userData,
          onGoToTab: setTab,
          onOpenOffers: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const OffersScreen()),
          ),
          onOpenAi: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AiPlannerScreen()),
          ),
        );
      case 1:
        return const FavoritesScreen();
      case 2:
        return hub.ParkingHubScreen(userData: userData);
      case 3:
        return const MyBookingsScreen();
      case 4:
        return const HelpAndSupportScreen();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildProfileEndDrawer(Map<String, dynamic> userData) {
    final name = ((userData['displayName'] ?? userData['name']) as String?)
        ?.trim();
    final firstName = (name == null || name.isEmpty)
        ? 'Guest'
        : name.split(' ').first;
    final email = (userData['email'] as String?)?.trim();
    final photoUrl = (userData['photoUrl'] as String?)?.trim();
    final safeEmail = email ?? '';

    return Drawer(
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(left: Radius.circular(26)),
      ),
      child: SafeArea(
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Color(0xFF0EA5E9),
                    Color(0xFF6366F1),
                    Color(0xFF8B5CF6),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          firstName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 18,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          safeEmail,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.85),
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.22),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: SafeNetworkAvatar(
                      radius: 26,
                      photoUrl: photoUrl,
                      name: firstName,
                    ),
                  ),
                ],
              ),
            ),

            // Quick access grid
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
                child: Column(
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _QuickAccessTile(
                            icon: Icons.person_rounded,
                            title: 'My Profile',
                            subtitle: 'View & edit',
                            gradientColors: const [
                              Color(0xFF0EA5E9),
                              Color(0xFF6366F1),
                            ],
                            onTap: () {
                              Navigator.pop(context);
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const MyProfileScreen(),
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: _QuickAccessTile(
                            icon: Icons.mark_unread_chat_alt_rounded,
                            title: 'Messages',
                            subtitle: 'Requests',
                            gradientColors: const [
                              Color(0xFFFB923C),
                              Color(0xFFF43F5E),
                            ],
                            decorationAngle: 0.35,
                            trailing: StreamBuilder<int>(
                              stream: _pendingChatRequestsCountStream(
                                FirebaseAuth.instance.currentUser!.uid,
                              ),
                              builder: (context, snap) {
                                final count = snap.data ?? 0;
                                if (count <= 0) return const SizedBox.shrink();

                                return Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 7,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(999),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.15),
                                        blurRadius: 4,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Text(
                                    count > 99 ? '99+' : '$count',
                                    style: const TextStyle(
                                      color: Color(0xFFF43F5E),
                                      fontWeight: FontWeight.w900,
                                      fontSize: 11,
                                    ),
                                  ),
                                );
                              },
                            ),
                            onTap: () {
                              Navigator.pop(context);
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      const PrivateParkingMessagesScreen(),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _QuickAccessTile(
                            icon: Icons.location_city_rounded,
                            title: 'Wembley\nCommunities',
                            subtitle: 'Explore zones',
                            gradientColors: const [
                              Color(0xFF10B981),
                              Color(0xFF06B6D4),
                            ],
                            decorationAngle: -0.25,
                            onTap: () {
                              Navigator.pop(context);
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      const WembleyCommunitiesScreen(),
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: _QuickAccessTile(
                            icon: Icons.settings_rounded,
                            title: 'Settings',
                            subtitle: 'Preferences',
                            gradientColors: const [
                              Color(0xFF8B5CF6),
                              Color(0xFFA855F7),
                            ],
                            centered: true,
                            decorationAngle: 0.2,
                            onTap: () {
                              Navigator.pop(context);
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const SettingsScreen(),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // Logout pinned to the bottom
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: _LogoutTile(
                onTap: () async {
                  Navigator.pop(context);
                  await _logout();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF0EA5E9), Color(0xFF6366F1), Color(0xFF8B5CF6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.18),
            borderRadius: BorderRadius.circular(26),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.12),
                blurRadius: 20,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
              SizedBox(width: 12),
              Text(
                'Loading your experience...',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authUser = FirebaseAuth.instance.currentUser;
    final uid = FirebaseAuth.instance.currentUser?.uid;

    if (authUser == null) {
      return const Scaffold(body: Center(child: Text('No user logged in.')));
    }

    final userDocRef = FirebaseFirestore.instance
        .collection('users')
        .doc(authUser.uid);

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: userDocRef.snapshots(),
      builder: (context, snapshot) {
        Widget body;
        Map<String, dynamic>? data;

        if (snapshot.connectionState == ConnectionState.waiting) {
          body = _buildLoadingState();
        } else if (!snapshot.hasData || !snapshot.data!.exists) {
          body = const Center(child: Text('User profile not found.'));
        } else {
          data = snapshot.data!.data()!;
          body = _buildBodyForTab(context, _selectedIndex, data);
        }

        final isPasswordUser = authUser.providerData.any(
          (p) => p.providerId == 'password',
        );
        final needsVerificationGate =
            isPasswordUser && !(authUser.emailVerified);

        return Stack(
          children: [
            Scaffold(
              key: _scaffoldKey,
              backgroundColor: const Color(0xFFF8F9FF),
              body: body,
              bottomNavigationBar: _buildPremiumBottomNav(),
              endDrawer: (data == null) ? null : _buildProfileEndDrawer(data),
            ),

            if (needsVerificationGate)
              _buildEmailVerificationOverlay(authUser.email),
          ],
        );
      },
    );
  }
}

class ParkingWebPlaceholder extends StatelessWidget {
  const ParkingWebPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FF),
      appBar: AppBar(
        title: const Text('Parking'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: const Padding(
        padding: EdgeInsets.all(18),
        child: Text(
          'Parking map is temporarily disabled on web to avoid Google Maps web runtime issues.\n\n'
          'Run on Android/iOS for the live map.\n\n'
          'Next: We will migrate web maps to a stable implementation.',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: _HomeUi.text,
            height: 1.4,
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// PREMIUM EXPLORE TAB (advanced UI + real search)
// ============================================================================
class ExploreTabPremium extends StatelessWidget {
  final Map<String, dynamic> userData;
  final void Function(int index) onGoToTab;
  final VoidCallback onOpenOffers;
  final VoidCallback onOpenAi;

  const ExploreTabPremium({
    super.key,
    required this.userData,
    required this.onGoToTab,
    required this.onOpenOffers,
    required this.onOpenAi,
  });

  Stream<QuerySnapshot<Map<String, dynamic>>> _upcoming3DaysStream() {
    final now = DateTime.now();
    final end = now.add(const Duration(days: 3));

    return FirebaseFirestore.instance
        .collection('events_wembley')
        .where('startDateTime', isGreaterThanOrEqualTo: Timestamp.fromDate(now))
        .where('startDateTime', isLessThanOrEqualTo: Timestamp.fromDate(end))
        .orderBy('startDateTime')
        .limit(12)
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    final name = ((userData['displayName'] ?? userData['name']) as String?)
        ?.trim();
    final firstName = (name == null || name.isEmpty)
        ? 'Guest'
        : name.split(' ').first;

    return Stack(
      children: [
        CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverAppBar(
              pinned: true,
              stretch: true,
              expandedHeight: 247,
              backgroundColor: Colors.transparent,
              elevation: 0,
              automaticallyImplyLeading: false, // ✅ Removes the menu icon
              actions: const [], // ✅ Prevents automatic endDrawer button
              flexibleSpace: FlexibleSpaceBar(
                background: _HeroPremium(
                  firstName: firstName,
                  onSearchTap: () {
                    // Navigate to advanced search screen
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const SearchScreen()),
                    );
                  },
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(32),
                    topRight: Radius.circular(32),
                  ),
                ),
                child: const SizedBox(height: 0),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                16,
                12,
                16,
                130,
              ), // ✅ Changed from 20 to 12
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  const SizedBox(height: 12), // ✅ Keep as 12 (was already good)
                  _PremiumActionGrid(
                    onEvents: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const EventsListScreen(),
                      ),
                    ),
                    onParking: () => onGoToTab(2),
                    onDining: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const AdvancedDiningScreen(),
                      ),
                    ),
                    onStay: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const AccommodationScreen(),
                      ),
                    ),
                    onOffers: onOpenOffers,
                    onAi: onOpenAi,
                  ),
                  const SizedBox(height: 24),
                  _SectionHeader(
                    title: 'Upcoming in next 3 days',
                    subtitle: 'Wembley • Updated today • Verified sources',
                    actionText: 'See all',
                    onAction: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const EventsListScreen(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 150,
                    child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: _upcoming3DaysStream(),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const _UpcomingSkeletonRow();
                        }

                        final docs = snapshot.data?.docs ?? [];
                        if (docs.isEmpty) {
                          return _EmptyUpcomingCard(
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const EventsListScreen(),
                              ),
                            ),
                          );
                        }

                        return ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: docs.length + 1,
                          separatorBuilder: (_, _) => const SizedBox(width: 14),
                          itemBuilder: (context, i) {
                            if (i == docs.length) {
                              return _SeeAllCard(
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const EventsListScreen(),
                                  ),
                                ),
                              );
                            }
                            final e = docs[i].data();
                            final title =
                                (e['title'] as String?) ?? 'Unnamed event';
                            final ts = e['startDateTime'] as Timestamp?;
                            final dt = ts?.toDate();

                            final category = (e['category'] as String?)?.trim();
                            final cat = (category == null || category.isEmpty)
                                ? 'Event'
                                : category;

                            return _UpcomingEventCard(
                              title: title,
                              category: cat,
                              start: dt,
                              onTap: () {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(title),
                                    behavior: SnackBarBehavior.floating,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    margin: const EdgeInsets.all(16),
                                  ),
                                );
                              },
                            );
                          },
                        );
                      },
                    ),
                  ),
                ]),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ============================================================================
// UI components
// ============================================================================

class _PremiumNavItem extends StatelessWidget {
  final bool isSelected;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _PremiumNavItem({
    required this.isSelected,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? _HomeUi.primarySoft : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 24,
              color: isSelected ? _HomeUi.primary : _HomeUi.textMuted,
            ),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: isSelected ? FontWeight.w900 : FontWeight.w700,
                  color: isSelected ? _HomeUi.primary : _HomeUi.textMuted,
                  letterSpacing: -0.2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroPremium extends StatelessWidget {
  final String firstName;
  final VoidCallback onSearchTap;

  const _HeroPremium({required this.firstName, required this.onSearchTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF8FAFC),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),

              // Welcome text
              RichText(
                text: TextSpan(
                  children: [
                    const TextSpan(
                      text: 'Welcome, ',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF64748B),
                      ),
                    ),
                    TextSpan(
                      text: firstName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 8),

              // "Explore Wembley" - keep as is
              RichText(
                text: const TextSpan(
                  children: [
                    TextSpan(
                      text: 'Explore ',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w400,
                        color: Color(0xFF0F172A),
                        height: 1.2,
                      ),
                    ),
                    TextSpan(
                      text: 'Wembley',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0F172A),
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 8),

              // Subtitle - keep as is
              const Text(
                'Discover upcoming events, dining spots,\nand places to stay.',
                style: TextStyle(
                  fontSize: 14,
                  color: Color(0xFF64748B),
                  height: 1.5,
                ),
              ),

              const SizedBox(height: 24),

              // Search bar
              _GlassSearchBar(onTap: onSearchTap),

              const Spacer(),
            ],
          ),
        ),
      ),
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
              fontWeight: FontWeight.w800,
              fontSize: 12,
              letterSpacing: -0.1,
            ),
          ),
        ],
      ),
    );
  }
}

class _GlassSearchBar extends StatelessWidget {
  final VoidCallback onTap;

  const _GlassSearchBar({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 18,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Row(
          children: [
            const Icon(
              Icons.search_rounded,
              color: Color(0xFF94A3B8),
              size: 22,
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Search events, dining, accommodation...',
                style: TextStyle(
                  color: Color(0xFF94A3B8),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFFEEF2FF), // soft accent bg
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(
                Icons.tune_rounded,
                color: Color(0xFF2563EB), // accent
                size: 20,
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
  final String? actionText;
  final VoidCallback? onAction;

  const _SectionHeader({
    required this.title,
    required this.subtitle,
    this.actionText,
    this.onAction,
  });

  const _SectionHeader.simple({required this.title, required this.subtitle})
    : actionText = null,
      onAction = null;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: _HomeUi.text,
                  letterSpacing: -0.4,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: _HomeUi.textMuted,
                ),
              ),
            ],
          ),
        ),
        if (actionText != null && onAction != null)
          TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(
              foregroundColor: _HomeUi.primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              actionText!,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
      ],
    );
  }
}

class _UpcomingEventCard extends StatelessWidget {
  final String title;
  final String category;
  final DateTime? start;
  final VoidCallback onTap;

  const _UpcomingEventCard({
    required this.title,
    required this.category,
    required this.start,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final countdown = _formatCountdown(start);
    final imageUrl = _getCategoryImage(category);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 260,
        height: 150, // Fixed height
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Background image
              Image.network(
                imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                    ),
                  ),
                ),
              ),

              // Gradient overlay
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.black.withOpacity(0.6),
                      Colors.black.withOpacity(0.2),
                    ],
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                  ),
                ),
              ),

              // Content
              Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Category badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.25),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        category,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),

                    const Spacer(),

                    // Title
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        height: 1.2,
                      ),
                    ),

                    const SizedBox(height: 6),

                    // Time/countdown
                    Text(
                      countdown,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.white.withOpacity(0.9),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Add this method to the _UpcomingEventCard class
  String _getCategoryImage(String category) {
    final lower = category.toLowerCase();
    if (lower.contains('sport') ||
        lower.contains('football') ||
        lower.contains('uefa')) {
      return 'https://images.unsplash.com/photo-1540747913346-19e32365c21a?w=400';
    } else if (lower.contains('music') || lower.contains('concert')) {
      return 'https://images.unsplash.com/photo-1470229722913-7c0e2dbbafd3?w=400';
    } else if (lower.contains('comedy') || lower.contains('show')) {
      return 'https://images.unsplash.com/photo-1485846234645-a62644f84728?w=400';
    } else {
      return 'https://images.unsplash.com/photo-1492684223066-81342ee5ff30?w=400';
    }
  }

  String _formatCountdown(DateTime? start) {
    if (start == null) return 'Time TBA';
    final diff = start.difference(DateTime.now());
    if (diff.isNegative) return 'Started';
    final d = diff.inDays;
    final h = diff.inHours % 24;
    final m = diff.inMinutes % 60;
    if (d > 0) return '${d}d ${h}h';
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }
}

class _Chip extends StatelessWidget {
  final String text;
  final IconData? icon;

  const _Chip({required this.text, this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: _HomeUi.textMuted),
            const SizedBox(width: 6),
          ],
          Text(
            text,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: _HomeUi.text,
            ),
          ),
        ],
      ),
    );
  }
}

class _SeeAllCard extends StatelessWidget {
  final VoidCallback onTap;

  const _SeeAllCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: 160,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF111827), _HomeUi.text],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 24),
            SizedBox(height: 10),
            Text(
              'See all events',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 14,
                letterSpacing: -0.3,
                height: 1.2,
              ),
            ),
            SizedBox(height: 4),
            Text(
              'Browse full schedule',
              style: TextStyle(
                color: Color(0xFFCBD5E1),
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyUpcomingCard extends StatelessWidget {
  final VoidCallback onTap;

  const _EmptyUpcomingCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFF1F5F9), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _HomeUi.primarySoft,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.event_busy_rounded,
              color: _HomeUi.primary,
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Text(
              'No events in the next 3 days. Check Events for upcoming listings.',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: _HomeUi.text,
                height: 1.3,
              ),
            ),
          ),
          const SizedBox(width: 10),
          ElevatedButton(
            onPressed: onTap,
            style: ElevatedButton.styleFrom(
              backgroundColor: _HomeUi.primary,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: const Text(
              'Open',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _UpcomingSkeletonRow extends StatelessWidget {
  const _UpcomingSkeletonRow();

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: 3,
      separatorBuilder: (_, _) => const SizedBox(width: 12),
      itemBuilder: (context, _) => Container(
        width: 260,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.6),
          borderRadius: BorderRadius.circular(20),
        ),
      ),
    );
  }
}

class _PremiumActionGrid extends StatelessWidget {
  final VoidCallback onEvents;
  final VoidCallback onParking;
  final VoidCallback onDining;
  final VoidCallback onStay;
  final VoidCallback onOffers;
  final VoidCallback onAi;

  const _PremiumActionGrid({
    required this.onEvents,
    required this.onParking,
    required this.onDining,
    required this.onStay,
    required this.onOffers,
    required this.onAi,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Row 1: Events, Dining
        Row(
          children: [
            Expanded(
              child: _LargeActionCard(
                title: 'Events',
                subtitle: 'See what’s happening',
                imageUrl:
                    'https://images.unsplash.com/photo-1470229722913-7c0e2dbbafd3?w=600',
                onTap: onEvents,
                showArrow: true,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _LargeActionCard(
                title: 'Dining',
                subtitle: 'Discover great restaurants',
                imageUrl:
                    'https://images.unsplash.com/photo-1504674900247-0877df9cc836?w=600',
                onTap: onDining,
                showArrow: true,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // Row 2: Stay, Offers
        Row(
          children: [
            Expanded(
              child: _LargeActionCard(
                title: 'Stay',
                subtitle: 'Find a cozy place to stay',
                imageUrl:
                    'https://images.unsplash.com/photo-1566665797739-1674de7a421a?w=600',
                onTap: onStay,
                showArrow: true,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _LargeActionCard(
                title: 'Offers',
                subtitle: 'Special deals & discounts',
                imageUrl:
                    'https://images.unsplash.com/photo-1607083206869-4c7672e72a8a?w=600',
                onTap: onOffers,
                badge: 'Today',
                showArrow: true,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Row 3: Parking, AI
        Row(
          children: [
            Expanded(
              child: _LargeActionCard(
                title: 'Parking',
                subtitle: 'Book your parking spot',
                imageUrl:
                    'https://images.unsplash.com/photo-1590674899484-d5640e854abe?w=600',
                onTap: onParking,
                showArrow: true,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _LargeActionCard(
                title: 'Plan your day (AI)',
                subtitle: 'Smart festival planning',
                imageUrl:
                    'https://images.unsplash.com/photo-1451187580459-43490279c0fa?w=600',
                onTap: onAi,
                badge: 'Smart',
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _LargeActionCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String imageUrl;
  final VoidCallback onTap;
  final String? badge;
  final bool showArrow;

  const _LargeActionCard({
    required this.title,
    required this.subtitle,
    required this.imageUrl,
    required this.onTap,
    this.badge,
    this.showArrow = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Image card
          Container(
            height: 120,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Background image
                  Image.network(
                    imageUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                        Container(color: const Color(0xFF6366F1)),
                  ),

                  // Dark overlay for text readability
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.black.withOpacity(0.5),
                          Colors.black.withOpacity(0.2),
                        ],
                        begin: Alignment.bottomLeft,
                        end: Alignment.topRight,
                      ),
                    ),
                  ),

                  // Content on image
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Badge at top-right if exists
                        if (badge != null)
                          Align(
                            alignment: Alignment.topRight,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.9),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                badge!,
                                style: const TextStyle(
                                  color: Color(0xFF0F172A),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),

                        const Spacer(),

                        // Title at bottom-left
                        Text(
                          title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            height: 1.1,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 10),

          // Subtitle below card
          Row(
            children: [
              Expanded(
                child: Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF64748B),
                    height: 1.4,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (showArrow) ...[
                const SizedBox(width: 4),
                const Icon(
                  Icons.arrow_forward,
                  size: 16,
                  color: Color(0xFF64748B),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// A single quick-access card used in the profile end drawer.
///
/// Each instance gets its own gradient and an oversized, faded background
/// icon for visual identity. [centered] switches the content layout from
/// the default top-icon/bottom-text arrangement to a fully centered one,
/// which is used for the Settings tile to give it a distinct look.
class _QuickAccessTile extends StatelessWidget {
  const _QuickAccessTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.gradientColors,
    required this.onTap,
    this.trailing,
    this.centered = false,
    this.decorationAngle = -0.35,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final List<Color> gradientColors;
  final VoidCallback onTap;
  final Widget? trailing;
  final bool centered;
  final double decorationAngle;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Container(
          height: 132,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: LinearGradient(
              colors: gradientColors,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: gradientColors.last.withOpacity(0.35),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                right: -16,
                bottom: -16,
                child: Transform.rotate(
                  angle: decorationAngle,
                  child: Icon(
                    icon,
                    size: 90,
                    color: Colors.white.withOpacity(0.14),
                  ),
                ),
              ),
              if (trailing != null)
                Positioned(top: 0, right: 0, child: trailing!),
              centered ? _buildCentered() : _buildDefault(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _iconBadge() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.22),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(icon, color: Colors.white, size: 22),
    );
  }

  Widget _buildDefault() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _iconBadge(),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 15,
                height: 1.15,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TextStyle(
                color: Colors.white.withOpacity(0.85),
                fontWeight: FontWeight.w600,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCentered() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _iconBadge(),
        const SizedBox(height: 10),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: 15,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white.withOpacity(0.85),
            fontWeight: FontWeight.w600,
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}

/// Standalone logout action, visually separated from the quick-access grid
/// and anchored to the bottom of the drawer.
class _LogoutTile extends StatelessWidget {
  const _LogoutTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: const Color(0xFFFEF2F2),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFFECACA), width: 1.2),
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.logout_rounded, color: Color(0xFFEF4444), size: 20),
              SizedBox(width: 8),
              Text(
                'Logout',
                style: TextStyle(
                  color: Color(0xFFEF4444),
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TinyBadge extends StatelessWidget {
  final IconData icon;
  final String text;

  const _TinyBadge({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.18),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withOpacity(0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// SAFE NETWORK AVATAR
// ============================================================================
class SafeNetworkAvatar extends StatelessWidget {
  final double radius;
  final String? photoUrl;
  final String? name;

  const SafeNetworkAvatar({
    super.key,
    required this.radius,
    required this.photoUrl,
    required this.name,
  });

  String get _initial {
    final raw = (name ?? '').trim();
    if (raw.isEmpty) return 'G';
    return raw[0].toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final url = (photoUrl ?? '').trim();
    final size = radius * 2;

    Widget fallback() {
      return Container(
        color: _HomeUi.primarySoft,
        alignment: Alignment.center,
        child: Text(
          _initial,
          style: TextStyle(
            fontWeight: FontWeight.w900,
            color: _HomeUi.primary,
            fontSize: radius * 0.9,
          ),
        ),
      );
    }

    // Always add cache-busting for updated images (not just web)
    final effectiveUrl = url.isNotEmpty
        ? '$url${url.contains('?') ? '&' : '?'}v=${url.hashCode}'
        : url;

    return SizedBox(
      width: size,
      height: size,
      child: ClipOval(
        child: effectiveUrl.isEmpty
            ? fallback()
            : Image.network(
                effectiveUrl,
                key: ValueKey(effectiveUrl), // forces rebuild when URL changes
                fit: BoxFit.cover,
                cacheWidth: (size * 2).toInt(), // optimize for retina displays
                errorBuilder: (_, _, _) => fallback(),
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return fallback(); // show fallback while loading
                },
              ),
      ),
    );
  }
}
