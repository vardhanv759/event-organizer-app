import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'events_screen.dart';
import 'dining_screen.dart';
import 'map_screen.dart';
import 'manage_events_screen.dart';
import 'organize_event_sheet.dart';
import 'organizer_application_sheet.dart';

import 'offers_screen.dart';
import 'ai_planner_screen.dart';
import 'accommodation_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  int _selectedIndex = 0;

  bool _isCheckingEmailVerification = false;
  bool _isResendingVerification = false;

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  void setTab(int index) => setState(() => _selectedIndex = index);

  void _openProfileDrawer() {
    _scaffoldKey.currentState?.openEndDrawer();
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
                    color: Color(0xFF0F172A),
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
                        color: Color(0xFF64748B),
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Tip: Check Spam/Junk if you don’t see it.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFF64748B),
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
                  color: Color(0xFF0F172A),
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'You will need to sign in again to access your account.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: Color(0xFF64748B),
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
                          color: Color(0xFF334155),
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
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
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
                  icon: Icons.event_rounded,
                  label: 'Events',
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
                  icon: Icons.restaurant_rounded,
                  label: 'Dining',
                  onTap: () => setTab(3),
                ),
              ),
              Expanded(
                child: _PremiumNavItem(
                  isSelected: _selectedIndex == 4,
                  icon: Icons.hotel_rounded,
                  label: 'Stay',
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
        return const EventsListScreen();
      case 2:
        return const MapScreen();
      case 3:
        return const AdvancedDiningScreen();
      case 4:
        return const AccommodationScreen();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildProfileEndDrawer(
    Map<String, dynamic> userData,
    String organizerStatus,
  ) {
    final name = (userData['name'] as String?)?.trim();
    final email = (userData['email'] as String?)?.trim();
    final photoUrl = (userData['photoUrl'] as String?)?.trim();

    final safeName = (name == null || name.isEmpty) ? 'Guest' : name;
    final safeEmail = email ?? '';
    final canOrganize = organizerStatus == 'approved';

    return Drawer(
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(left: Radius.circular(26)),
      ),
      child: SafeArea(
        child: Column(
          children: [
            // Premium header
            Container(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
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
                  Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.22),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: SafeNetworkAvatar(
                      radius: 22,
                      photoUrl: photoUrl,
                      name: safeName,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          safeName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
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
                        const SizedBox(height: 10),
                        const Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _TinyBadge(
                              icon: Icons.verified_rounded,
                              text: 'Verified sources',
                            ),
                            _TinyBadge(
                              icon: Icons.refresh_rounded,
                              text: 'Updated daily',
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const Divider(height: 1),

            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
                children: [
                  _DrawerTile(
                    icon: Icons.person_rounded,
                    title: 'My Profile',
                    onTap: () => Navigator.pop(context),
                  ),
                  _DrawerTile(
                    icon: Icons.confirmation_number_rounded,
                    title: 'My Bookings',
                    onTap: () => Navigator.pop(context),
                  ),
                  _DrawerTile(
                    icon: Icons.bookmark_rounded,
                    title: 'Saved Events',
                    onTap: () => Navigator.pop(context),
                  ),
                  _DrawerTile(
                    icon: Icons.favorite_rounded,
                    title: 'Saved Restaurants',
                    onTap: () => Navigator.pop(context),
                  ),

                  const SizedBox(height: 8),
                  const _DrawerDividerLabel(label: 'Shortcuts'),
                  _DrawerTile(
                    icon: Icons.local_offer_rounded,
                    title: 'Offers',
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const OffersScreen()),
                      );
                    },
                  ),
                  _DrawerTile(
                    icon: Icons.auto_awesome_rounded,
                    title: 'Plan Your Day (AI)',
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const AiPlannerScreen(),
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 8),
                  const _DrawerDividerLabel(label: 'Organizer'),

                  if (canOrganize) ...[
                    _DrawerTile(
                      icon: Icons.add_business_rounded,
                      title: 'Organize an Event',
                      onTap: () {
                        Navigator.pop(context);
                        showOrganizeEventSheet(context, userData: userData);
                      },
                    ),
                    _DrawerTile(
                      icon: Icons.manage_accounts_rounded,
                      title: 'Manage My Events',
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                ManageEventsScreen(userData: userData),
                          ),
                        );
                      },
                    ),
                  ] else ...[
                    _DrawerTile(
                      icon: Icons.verified_user_rounded,
                      title: 'Become an Organizer',
                      subtitle: 'Apply to host and publish events',
                      onTap: () {
                        Navigator.pop(context);
                        showOrganizerApplicationSheet(
                          context,
                          userData: userData,
                        );
                      },
                    ),
                  ],

                  const SizedBox(height: 8),
                  const _DrawerDividerLabel(label: 'Support'),
                  _DrawerTile(
                    icon: Icons.settings_rounded,
                    title: 'Settings',
                    onTap: () => Navigator.pop(context),
                  ),
                  _DrawerTile(
                    icon: Icons.help_outline_rounded,
                    title: 'Help & Support',
                    onTap: () => Navigator.pop(context),
                  ),

                  const SizedBox(height: 10),
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: ListTile(
                      leading: const Icon(
                        Icons.logout_rounded,
                        color: Color(0xFFEF4444),
                      ),
                      title: const Text(
                        'Logout',
                        style: TextStyle(
                          color: Color(0xFFEF4444),
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      onTap: () async {
                        Navigator.pop(context);
                        await _logout();
                      },
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
        String organizerStatus = 'none';

        if (snapshot.connectionState == ConnectionState.waiting) {
          body = _buildLoadingState();
        } else if (!snapshot.hasData || !snapshot.data!.exists) {
          body = const Center(child: Text('User profile not found.'));
        } else {
          data = snapshot.data!.data()!;
          organizerStatus = (data['organizerStatus'] as String?) ?? 'none';
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
              endDrawer: (data == null)
                  ? null
                  : _buildProfileEndDrawer(data, organizerStatus),
            ),

            // Top-right profile avatar overlay (premium)
            Positioned(
              top: 10,
              right: 12,
              child: SafeArea(
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () {
                      if (data != null) _openProfileDrawer();
                    },
                    borderRadius: BorderRadius.circular(999),
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.86),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.14),
                            blurRadius: 18,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: SafeNetworkAvatar(
                        radius: 18,
                        photoUrl: (data?['photoUrl'] as String?)?.trim(),
                        name: (data?['name'] as String?)?.trim(),
                      ),
                    ),
                  ),
                ),
              ),
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
            color: Color(0xFF334155),
            height: 1.4,
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// PREMIUM EXPLORE TAB (advanced UI)
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
    final name = (userData['name'] as String?)?.trim();
    final firstName = (name == null || name.isEmpty)
        ? 'Guest'
        : name.split(' ').first;

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverAppBar(
          pinned: true,
          stretch: true,
          expandedHeight: 320,
          backgroundColor: Colors.transparent,
          elevation: 0,
          flexibleSpace: FlexibleSpaceBar(
            background: _HeroPremium(
              firstName: firstName,
              onSearchTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('Search coming soon'),
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
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 130),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              _SectionHeader(
                title: 'Upcoming in next 3 days',
                subtitle: 'Wembley • Updated today • Verified sources',
                actionText: 'See all',
                onAction: () => onGoToTab(1),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 150,
                child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: _upcoming3DaysStream(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const _UpcomingSkeletonRow();
                    }

                    final docs = snapshot.data?.docs ?? [];
                    if (docs.isEmpty) {
                      return _EmptyUpcomingCard(onTap: () => onGoToTab(1));
                    }

                    return ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: docs.length + 1,
                      separatorBuilder: (_, __) => const SizedBox(width: 12),
                      itemBuilder: (context, i) {
                        if (i == docs.length) {
                          return _SeeAllCard(onTap: () => onGoToTab(1));
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
              const SizedBox(height: 18),
              const _SectionHeader(
                title: 'Quick actions',
                subtitle: 'Designed for speed — no clutter',
              ),
              const SizedBox(height: 12),
              _PremiumActionGrid(
                onEvents: () => onGoToTab(1),
                onParking: () => onGoToTab(2),
                onDining: () => onGoToTab(3),
                onStay: () => onGoToTab(4),
                onOffers: onOpenOffers,
                onAi: onOpenAi,
              ),
              const SizedBox(height: 18),
              _PremiumInfoStrip(
                icon: Icons.auto_awesome_rounded,
                title: 'Plan your day (AI)',
                subtitle: 'One plan: event + parking + dining + timeline.',
                cta: 'Open AI Planner',
                onTap: onOpenAi,
              ),
              const SizedBox(height: 12),
              _PremiumInfoStrip(
                icon: Icons.local_offer_rounded,
                title: 'Offers for today',
                subtitle: 'Discounts and bundles linked to events.',
                cta: 'View Offers',
                onTap: onOpenOffers,
              ),
            ]),
          ),
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
          color: isSelected ? const Color(0xFFEEF2FF) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 24,
              color: isSelected
                  ? const Color(0xFF4F46E5)
                  : const Color(0xFF94A3B8),
            ),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: isSelected ? FontWeight.w900 : FontWeight.w700,
                  color: isSelected
                      ? const Color(0xFF4F46E5)
                      : const Color(0xFF94A3B8),
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
    return Stack(
      children: [
        // Background gradient
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF0EA5E9), Color(0xFF6366F1), Color(0xFF8B5CF6)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),

        // Soft light blobs
        Positioned(
          top: -80,
          right: -60,
          child: Container(
            height: 240,
            width: 240,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withOpacity(0.10),
            ),
          ),
        ),
        Positioned(
          bottom: -110,
          left: -80,
          child: Container(
            height: 260,
            width: 260,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withOpacity(0.08),
            ),
          ),
        ),

        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 34), // avatar overlay space
                Text(
                  'Welcome, $firstName',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.92),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Explore Wembley',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.8,
                    height: 1.08,
                  ),
                ),
                const SizedBox(height: 12),

                const Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _HeroPill(icon: Icons.location_on_rounded, text: 'Wembley'),
                    _HeroPill(icon: Icons.verified_rounded, text: 'Verified'),
                    _HeroPill(
                      icon: Icons.refresh_rounded,
                      text: 'Updated daily',
                    ),
                  ],
                ),

                const SizedBox(height: 14),
                _GlassSearchBar(onTap: onSearchTap),

                const Spacer(),

                // Compact “value strip”
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.14),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Colors.white.withOpacity(0.20)),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.info_outline_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Find events, parking and dining with a clean, verified experience.',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.90),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            height: 1.25,
                          ),
                        ),
                      ),
                    ],
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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.16),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white.withOpacity(0.22)),
            ),
            child: Row(
              children: [
                const Icon(Icons.search_rounded, color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Search events, food, parking…',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.90),
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.tune_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
              ],
            ),
          ),
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
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF0F172A),
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF64748B),
                ),
              ),
            ],
          ),
        ),
        if (actionText != null && onAction != null)
          TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF4F46E5),
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

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: 260,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.07),
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
                gradient: const LinearGradient(
                  colors: [Color(0xFF0EA5E9), Color(0xFF6366F1)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Icon(
                Icons.event_rounded,
                color: Colors.white,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF0F172A),
                      height: 1.2,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _Chip(text: category),
                      _Chip(text: countdown, icon: Icons.timer_rounded),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
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
            Icon(icon, size: 14, color: const Color(0xFF64748B)),
            const SizedBox(width: 6),
          ],
          Text(
            text,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: Color(0xFF334155),
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
        width: 170,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF111827), Color(0xFF334155)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.16),
              blurRadius: 24,
              offset: const Offset(0, 16),
            ),
          ],
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.arrow_forward_rounded, color: Colors.white),
            SizedBox(height: 10),
            Text(
              'See all events',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 14,
                letterSpacing: -0.2,
              ),
            ),
            SizedBox(height: 4),
            Text(
              'Browse full schedule',
              style: TextStyle(
                color: Color(0xFFCBD5E1),
                fontWeight: FontWeight.w700,
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
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
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
            child: const Icon(
              Icons.event_busy_rounded,
              color: Color(0xFF4F46E5),
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'No events in the next 3 days. Check Events for upcoming listings.',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: Color(0xFF334155),
                height: 1.25,
              ),
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: onTap,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4F46E5),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: const Text(
              'Open',
              style: TextStyle(fontWeight: FontWeight.w900),
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
      separatorBuilder: (_, __) => const SizedBox(width: 12),
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
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 0.98,
      children: [
        _ActionTile(
          label: 'Events',
          icon: Icons.event_rounded,
          gradient: const [Color(0xFF0EA5E9), Color(0xFF6366F1)],
          onTap: onEvents,
        ),
        _ActionTile(
          label: 'Parking',
          icon: Icons.local_parking_rounded,
          gradient: const [Color(0xFF22C55E), Color(0xFF0EA5E9)],
          onTap: onParking,
        ),
        _ActionTile(
          label: 'Dining',
          icon: Icons.restaurant_rounded,
          gradient: const [Color(0xFFF97316), Color(0xFFEF4444)],
          onTap: onDining,
        ),
        _ActionTile(
          label: 'Stay',
          icon: Icons.hotel_rounded,
          gradient: const [Color(0xFF8B5CF6), Color(0xFF6366F1)],
          onTap: onStay,
        ),
        _ActionTile(
          label: 'Offers',
          icon: Icons.local_offer_rounded,
          gradient: const [Color(0xFF111827), Color(0xFF334155)],
          onTap: onOffers,
          badge: 'Today',
        ),
        _ActionTile(
          label: 'Plan your day (AI)',
          icon: Icons.auto_awesome_rounded,
          gradient: const [Color(0xFF06B6D4), Color(0xFF8B5CF6)],
          onTap: onAi,
          badge: 'Smart',
        ),
      ],
    );
  }
}

class _ActionTile extends StatelessWidget {
  final String label;
  final IconData icon;
  final List<Color> gradient;
  final VoidCallback onTap;
  final String? badge;

  const _ActionTile({
    required this.label,
    required this.icon,
    required this.gradient,
    required this.onTap,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: LinearGradient(
            colors: gradient,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.10),
              blurRadius: 20,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: Stack(
          children: [
            Positioned(
              top: 10,
              right: 10,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: Colors.white, size: 20),
              ),
            ),
            Positioned(
              left: 12,
              bottom: 12,
              right: 12,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (badge != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.18),
                        borderRadius: BorderRadius.circular(999),
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
                    const SizedBox(height: 8),
                  ],
                  Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                      letterSpacing: -0.2,
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

class _PremiumInfoStrip extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String cta;
  final VoidCallback onTap;

  const _PremiumInfoStrip({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.cta,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
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
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF4F46E5),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                cta,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DrawerTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  const _DrawerTile({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
      ),
      child: ListTile(
        leading: Icon(icon, color: const Color(0xFF334155)),
        title: Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w900,
            color: Color(0xFF0F172A),
          ),
        ),
        subtitle: subtitle == null
            ? null
            : Text(
                subtitle!,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF64748B),
                ),
              ),
        onTap: onTap,
      ),
    );
  }
}

class _DrawerDividerLabel extends StatelessWidget {
  final String label;
  const _DrawerDividerLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 6),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w900,
          color: Color(0xFF94A3B8),
          letterSpacing: 0.6,
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
// SAFE NETWORK AVATAR (fixes CircleAvatar assertion + handles 429)
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
        color: const Color(0xFFEEF2FF),
        alignment: Alignment.center,
        child: Text(
          _initial,
          style: TextStyle(
            fontWeight: FontWeight.w900,
            color: const Color(0xFF4F46E5),
            fontSize: radius * 0.9,
          ),
        ),
      );
    }

    return SizedBox(
      width: size,
      height: size,
      child: ClipOval(
        child: url.isEmpty
            ? fallback()
            : Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    fallback(), // handles 429 and any other errors
              ),
      ),
    );
  }
}
