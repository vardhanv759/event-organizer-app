import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ═══════════════════════════════════════════════════════════════
// PROFANITY FILTER HELPERS
// ═══════════════════════════════════════════════════════════════

const _kBadWords = [
  'fuck',
  'shit',
  'bitch',
  'asshole',
  'bastard',
  'cunt',
  'dick',
  'pussy',
  'faggot',
  'nigger',
  'nigga',
  'whore',
  'slut',
  'bollocks',
  'twat',
  'wanker',
  'arse',
  'bugger',
  'prick',
  'tosser',
  'bellend',
];

bool _hasProfanity(String text) {
  final lower = text.toLowerCase();
  return _kBadWords.any((w) => lower.contains(w));
}

String _censorText(String text) {
  var result = text;
  for (final word in _kBadWords) {
    result = result.replaceAll(
      RegExp(word, caseSensitive: false),
      '•' * word.length,
    );
  }
  return result;
}

// ═══════════════════════════════════════════════════════════════
// USER NAME HELPER
// ═══════════════════════════════════════════════════════════════

/// Fetches user's display name from Firestore users collection
/// Priority:
/// 1. Firestore users/{uid}/name (full name)
/// 2. Firestore users/{uid}/displayName
/// 3. Firestore users/{uid}/firstName
/// 4. Firebase Auth displayName
/// 5. Fallback: 'User'
Future<String> _getUserDisplayName(String uid) async {
  if (uid.isEmpty) return 'User';

  try {
    // Fetch from Firestore users collection
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get();

    if (doc.exists) {
      final data = doc.data();
      if (data != null) {
        // Try full name first
        final fullName = (data['name'] as String?)?.trim();
        if (fullName != null && fullName.isNotEmpty) {
          return fullName;
        }

        // Try displayName
        final displayName = (data['displayName'] as String?)?.trim();
        if (displayName != null && displayName.isNotEmpty) {
          return displayName;
        }

        // Try first name
        final firstName = (data['firstName'] as String?)?.trim();
        if (firstName != null && firstName.isNotEmpty) {
          return firstName;
        }
      }
    }

    // Fall back to Firebase Auth displayName
    final authUser = FirebaseAuth.instance.currentUser;
    if (authUser?.uid == uid &&
        authUser?.displayName?.trim().isNotEmpty == true) {
      return authUser!.displayName!.trim();
    }

    return 'User';
  } catch (e) {
    print('Error fetching user name: $e');
    return 'User';
  }
}

// ═══════════════════════════════════════════════════════════════
// MAIN SCREEN
// ═══════════════════════════════════════════════════════════════

/// 🏘️ WEMBLEY ZONE HUB
/// Feed · Chat · Members  — with full moderation & security features
class WembleyZoneHubScreen extends StatefulWidget {
  final String zoneId;
  final String zoneName;
  final Color color;
  final Color gradientStart;
  final Color gradientEnd;

  const WembleyZoneHubScreen({
    super.key,
    required this.zoneId,
    required this.zoneName,
    required this.color,
    required this.gradientStart,
    required this.gradientEnd,
  });

  @override
  State<WembleyZoneHubScreen> createState() => _WembleyZoneHubScreenState();
}

class _WembleyZoneHubScreenState extends State<WembleyZoneHubScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  int _memberCount = 0;
  String _myRole = 'user';
  bool _isBlocked = false;
  bool _notifMuted = false;
  int _unreadCount = 0;
  int _pendingReports = 0;

  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';
  bool get _isProvider => _myRole == 'provider';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (_tabController.index == 1 && !_tabController.indexIsChanging) {
        _markChatRead();
        if (mounted) setState(() => _unreadCount = 0);
      }
    });
    _bootstrap();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    await Future.wait([
      _loadMemberCount(),
      _loadMyRole(),
      _loadBlockStatus(),
      _loadNotifMute(),
      _loadUnreadCount(),
    ]);
  }

  Future<void> _loadMemberCount() async {
    try {
      final s = await _db
          .collection('zones')
          .doc(widget.zoneId)
          .collection('members')
          .get();
      if (mounted) setState(() => _memberCount = s.docs.length);
    } catch (_) {}
  }

  Future<void> _loadMyRole() async {
    try {
      // ✅ Provider status is determined by users/{uid}.parking_provider_status == 'approved'
      final d = await _db.collection('users').doc(_uid).get();
      if (mounted && d.exists) {
        final status = d.data()?['parkingProviderStatus'] as String? ?? '';
        final role = status == 'approved' ? 'provider' : 'user';
        setState(() => _myRole = role);
        if (role == 'provider') _loadPendingReports();
      }
    } catch (_) {}
  }

  Future<void> _loadBlockStatus() async {
    try {
      final d = await _db
          .collection('zones')
          .doc(widget.zoneId)
          .collection('blocked')
          .doc(_uid)
          .get();
      if (mounted) setState(() => _isBlocked = d.exists);
    } catch (_) {}
  }

  Future<void> _loadNotifMute() async {
    try {
      final d = await _db
          .collection('users')
          .doc(_uid)
          .collection('zone_settings')
          .doc(widget.zoneId)
          .get();
      if (mounted) setState(() => _notifMuted = d.data()?['muted'] == true);
    } catch (_) {}
  }

  Future<void> _loadUnreadCount() async {
    try {
      final act = await _db
          .collection('users')
          .doc(_uid)
          .collection('zone_activity')
          .doc(widget.zoneId)
          .get();
      final lastRead = act.data()?['lastReadAt'] as Timestamp?;
      if (lastRead == null) return;
      final s = await _db
          .collection('zones')
          .doc(widget.zoneId)
          .collection('messages')
          .where('timestamp', isGreaterThan: lastRead)
          .where('senderId', isNotEqualTo: _uid)
          .get();
      if (mounted) setState(() => _unreadCount = s.docs.length);
    } catch (_) {}
  }

  Future<void> _loadPendingReports() async {
    try {
      final s = await _db
          .collection('zones')
          .doc(widget.zoneId)
          .collection('reports')
          .where('status', isEqualTo: 'pending')
          .get();
      if (mounted) setState(() => _pendingReports = s.docs.length);
    } catch (_) {}
  }

  Future<void> _markChatRead() async {
    try {
      await _db
          .collection('users')
          .doc(_uid)
          .collection('zone_activity')
          .doc(widget.zoneId)
          .set({
            'lastReadAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
    } catch (_) {}
  }

  Future<void> _toggleNotifMute() async {
    final next = !_notifMuted;
    setState(() => _notifMuted = next);
    await _db
        .collection('users')
        .doc(_uid)
        .collection('zone_settings')
        .doc(widget.zoneId)
        .set({'muted': next}, SetOptions(merge: true));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            next
                ? '🔕 Notifications muted for this zone'
                : '🔔 Notifications enabled',
          ),
          backgroundColor: widget.color,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FF),
      body: Column(
        children: [
          _ZoneHeader(
            zoneName: widget.zoneName,
            memberCount: _memberCount,
            gradientStart: widget.gradientStart,
            gradientEnd: widget.gradientEnd,
            color: widget.color,
            isProvider: _isProvider,
            pendingReports: _pendingReports,
            notifMuted: _notifMuted,
            unreadCount: _unreadCount,
            tabController: _tabController,
            onBack: () => Navigator.pop(context),
            onToggleMute: _toggleNotifMute,
            onProviderDashboard: () => _showProviderDashboard(),
          ),
          if (_isBlocked)
            _BlockedBanner(
              zoneId: widget.zoneId,
              myUid: _uid,
              color: widget.color,
            ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _FeedTab(
                  zoneId: widget.zoneId,
                  color: widget.color,
                  isProvider: _isProvider,
                  myUid: _uid,
                ),
                _isBlocked
                    ? _BlockedChatPlaceholder(
                        zoneId: widget.zoneId,
                        myUid: _uid,
                        color: widget.color,
                      )
                    : _ChatTab(
                        zoneId: widget.zoneId,
                        color: widget.color,
                        isProvider: _isProvider,
                        myUid: _uid,
                        onReportsChanged: (n) {
                          if (mounted) setState(() => _pendingReports = n);
                        },
                      ),
                _MembersTab(
                  zoneId: widget.zoneId,
                  color: widget.color,
                  isProvider: _isProvider,
                  myUid: _uid,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showProviderDashboard() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ProviderDashboard(
        zoneId: widget.zoneId,
        color: widget.color,
        myUid: _uid,
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// ZONE HEADER
// ═══════════════════════════════════════════════════════════════

class _ZoneHeader extends StatelessWidget {
  final String zoneName;
  final int memberCount;
  final Color gradientStart, gradientEnd, color;
  final bool isProvider, notifMuted;
  final int pendingReports, unreadCount;
  final TabController tabController;
  final VoidCallback onBack, onToggleMute, onProviderDashboard;

  const _ZoneHeader({
    required this.zoneName,
    required this.memberCount,
    required this.gradientStart,
    required this.gradientEnd,
    required this.color,
    required this.isProvider,
    required this.pendingReports,
    required this.notifMuted,
    required this.unreadCount,
    required this.tabController,
    required this.onBack,
    required this.onToggleMute,
    required this.onProviderDashboard,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [gradientStart, gradientEnd],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 8, 4),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(
                      Icons.arrow_back_rounded,
                      color: Colors.white,
                    ),
                    onPressed: onBack,
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          zoneName,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          '$memberCount members',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.white.withOpacity(0.9),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Notification mute
                  IconButton(
                    tooltip: notifMuted
                        ? 'Unmute notifications'
                        : 'Mute notifications',
                    icon: Icon(
                      notifMuted
                          ? Icons.notifications_off_rounded
                          : Icons.notifications_rounded,
                      color: Colors.white,
                    ),
                    onPressed: onToggleMute,
                  ),
                  // Provider shield
                  if (isProvider)
                    Stack(
                      children: [
                        IconButton(
                          tooltip: 'Provider Dashboard',
                          icon: const Icon(
                            Icons.shield_rounded,
                            color: Colors.white,
                          ),
                          onPressed: onProviderDashboard,
                        ),
                        if (pendingReports > 0)
                          Positioned(
                            right: 8,
                            top: 8,
                            child: Container(
                              width: 16,
                              height: 16,
                              decoration: const BoxDecoration(
                                color: Color(0xFFEF4444),
                                shape: BoxShape.circle,
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                '$pendingReports',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                ],
              ),
            ),
            TabBar(
              controller: tabController,
              indicatorColor: Colors.white,
              indicatorWeight: 3,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white.withOpacity(0.65),
              labelStyle: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
              unselectedLabelStyle: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
              tabs: [
                const Tab(text: 'Feed'),
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('Chat'),
                      if (unreadCount > 0) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '$unreadCount',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const Tab(text: 'Members'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// BLOCKED BANNER
// ═══════════════════════════════════════════════════════════════

class _BlockedBanner extends StatelessWidget {
  final String zoneId, myUid;
  final Color color;
  const _BlockedBanner({
    required this.zoneId,
    required this.myUid,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFEF4444),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          const Icon(Icons.block_rounded, color: Colors.white, size: 18),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'You have been blocked from this zone.',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
          TextButton(
            onPressed: () => _submitAppeal(context),
            style: TextButton.styleFrom(foregroundColor: Colors.white),
            child: const Text(
              'Appeal',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                decoration: TextDecoration.underline,
                decorationColor: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _submitAppeal(BuildContext context) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'Submit Appeal',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        content: TextField(
          controller: ctrl,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: 'Explain why you should be unblocked...',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: color),
            onPressed: () async {
              if (ctrl.text.trim().isEmpty) return;
              await FirebaseFirestore.instance
                  .collection('zones')
                  .doc(zoneId)
                  .collection('appeals')
                  .add({
                    'uid': myUid,
                    'reason': ctrl.text.trim(),
                    'createdAt': FieldValue.serverTimestamp(),
                    'status': 'pending',
                  });
              if (ctx.mounted) {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(
                    content: Text(
                      '✅ Appeal submitted. A provider will review it.',
                    ),
                    backgroundColor: Color(0xFF10B981),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
            child: const Text('Submit'),
          ),
        ],
      ),
    );
  }
}

class _BlockedChatPlaceholder extends StatelessWidget {
  final String zoneId, myUid;
  final Color color;
  const _BlockedChatPlaceholder({
    required this.zoneId,
    required this.myUid,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.no_meeting_room_rounded,
                size: 56,
                color: Colors.red,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Chat Restricted',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'You\'ve been blocked from this zone\'s chat. Use the banner above to submit an appeal.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// FEED TAB
// ═══════════════════════════════════════════════════════════════

class _FeedTab extends StatelessWidget {
  final String zoneId, myUid;
  final Color color;
  final bool isProvider;

  const _FeedTab({
    required this.zoneId,
    required this.myUid,
    required this.color,
    required this.isProvider,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('zones')
          .doc(zoneId)
          .collection('posts')
          .orderBy('isPinned', descending: true)
          .orderBy('timestamp', descending: true)
          .limit(50)
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final posts = snap.data?.docs ?? [];

        return Stack(
          children: [
            posts.isEmpty
                ? _buildEmptyState()
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                    itemCount: posts.length,
                    itemBuilder: (ctx, i) {
                      final data = posts[i].data() as Map<String, dynamic>;
                      return _PostCard(
                        postId: posts[i].id,
                        post: data,
                        color: color,
                        zoneId: zoneId,
                        myUid: myUid,
                        isProvider: isProvider,
                      );
                    },
                  ),

            // Provider FAB or info bar
            if (isProvider)
              Positioned(
                right: 16,
                bottom: 16,
                child: FloatingActionButton.extended(
                  onPressed: () => _showCreateDialog(context),
                  backgroundColor: color,
                  icon: const Icon(Icons.edit_rounded),
                  label: const Text(
                    'New Post',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              )
            else
              Positioned(
                bottom: 12,
                left: 16,
                right: 16,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.07),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: color.withOpacity(0.25)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.lock_outline_rounded, size: 15, color: color),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Only approved providers can create posts',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: color,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: color.withOpacity(0.09),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.article_outlined, size: 56, color: color),
            ),
            const SizedBox(height: 24),
            const Text(
              'No posts yet',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Providers share parking updates,\nlocal events, and announcements here.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }

  void _showCreateDialog(BuildContext context) {
    final titleCtrl = TextEditingController();
    final contentCtrl = TextEditingController();
    bool pinned = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text(
            'Create Post',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: titleCtrl,
                  decoration: InputDecoration(
                    labelText: 'Title *',
                    hintText: 'Announcement title...',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: contentCtrl,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: 'Details (optional)',
                    hintText: 'Add more information...',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Switch(
                      value: pinned,
                      onChanged: (v) => setS(() => pinned = v),
                      activeColor: color,
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.push_pin_rounded, size: 16),
                    const SizedBox(width: 4),
                    const Text(
                      'Pin to top of Feed',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: color,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: () async {
                if (titleCtrl.text.trim().isEmpty) return;
                final user = FirebaseAuth.instance.currentUser;
                if (user == null) return;
                await FirebaseFirestore.instance
                    .collection('zones')
                    .doc(zoneId)
                    .collection('posts')
                    .add({
                      'title': titleCtrl.text.trim(),
                      'content': contentCtrl.text.trim(),
                      'authorId': user.uid,
                      'authorName': user.displayName ?? 'Provider',
                      'timestamp': FieldValue.serverTimestamp(),
                      'likes': 0,
                      'isPinned': pinned,
                    });
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Publish'),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// POST CARD
// ═══════════════════════════════════════════════════════════════

class _PostCard extends StatelessWidget {
  final String postId, zoneId, myUid;
  final Map<String, dynamic> post;
  final Color color;
  final bool isProvider;

  const _PostCard({
    required this.postId,
    required this.zoneId,
    required this.myUid,
    required this.post,
    required this.color,
    required this.isProvider,
  });

  @override
  Widget build(BuildContext context) {
    final isPinned = post['isPinned'] == true;
    final isMyPost = post['authorId'] == myUid;
    final canEdit = isProvider || isMyPost;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: isPinned ? Border.all(color: color, width: 2) : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Pinned ribbon
          if (isPinned)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: color,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(14),
                ),
              ),
              child: const Row(
                children: [
                  Icon(Icons.push_pin_rounded, size: 13, color: Colors.white),
                  SizedBox(width: 6),
                  Text(
                    'Pinned Announcement',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Author row
                Row(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: color.withOpacity(0.12),
                      child: Icon(
                        Icons.storefront_rounded,
                        color: color,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                post['authorName'] ?? 'Provider',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: color.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  'Provider',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    color: color,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (canEdit)
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert, color: Colors.grey),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        onSelected: (v) => _handleAction(context, v),
                        itemBuilder: (_) => [
                          PopupMenuItem(
                            value: 'pin',
                            child: Row(
                              children: [
                                Icon(
                                  isPinned
                                      ? Icons.push_pin_outlined
                                      : Icons.push_pin_rounded,
                                  size: 16,
                                ),
                                const SizedBox(width: 8),
                                Text(isPinned ? 'Unpin' : 'Pin to top'),
                              ],
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'delete',
                            child: Row(
                              children: [
                                Icon(
                                  Icons.delete_outline,
                                  size: 16,
                                  color: Colors.red,
                                ),
                                SizedBox(width: 8),
                                Text(
                                  'Delete post',
                                  style: TextStyle(color: Colors.red),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                // Title
                Text(
                  post['title'] ?? '',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A),
                  ),
                ),
                // Content
                if ((post['content'] ?? '').toString().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    post['content'],
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade700,
                      height: 1.5,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                // Like button
                _LikeButton(
                  postId: postId,
                  zoneId: zoneId,
                  myUid: myUid,
                  color: color,
                  likes: post['likes'] ?? 0,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleAction(BuildContext context, String action) async {
    if (action == 'delete') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Delete Post?'),
          content: const Text('This action cannot be undone.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete'),
            ),
          ],
        ),
      );
      if (ok == true) {
        await FirebaseFirestore.instance
            .collection('zones')
            .doc(zoneId)
            .collection('posts')
            .doc(postId)
            .delete();
      }
    } else if (action == 'pin') {
      await FirebaseFirestore.instance
          .collection('zones')
          .doc(zoneId)
          .collection('posts')
          .doc(postId)
          .update({'isPinned': !(post['isPinned'] == true)});
    }
  }
}

// ═══════════════════════════════════════════════════════════════
// LIKE BUTTON
// ═══════════════════════════════════════════════════════════════

class _LikeButton extends StatefulWidget {
  final String postId, zoneId, myUid;
  final Color color;
  final int likes;

  const _LikeButton({
    required this.postId,
    required this.zoneId,
    required this.myUid,
    required this.color,
    required this.likes,
  });

  @override
  State<_LikeButton> createState() => _LikeButtonState();
}

class _LikeButtonState extends State<_LikeButton> {
  bool _liked = false;
  late int _count;

  @override
  void initState() {
    super.initState();
    _count = widget.likes;
    _checkLiked();
  }

  Future<void> _checkLiked() async {
    final d = await FirebaseFirestore.instance
        .collection('zones')
        .doc(widget.zoneId)
        .collection('posts')
        .doc(widget.postId)
        .collection('likes')
        .doc(widget.myUid)
        .get();
    if (mounted) setState(() => _liked = d.exists);
  }

  Future<void> _toggle() async {
    HapticFeedback.lightImpact();
    final ref = FirebaseFirestore.instance
        .collection('zones')
        .doc(widget.zoneId)
        .collection('posts')
        .doc(widget.postId);
    if (_liked) {
      await ref.collection('likes').doc(widget.myUid).delete();
      await ref.update({'likes': FieldValue.increment(-1)});
      if (mounted)
        setState(() {
          _liked = false;
          _count--;
        });
    } else {
      await ref.collection('likes').doc(widget.myUid).set({
        'uid': widget.myUid,
        'at': FieldValue.serverTimestamp(),
      });
      await ref.update({'likes': FieldValue.increment(1)});
      if (mounted)
        setState(() {
          _liked = true;
          _count++;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _toggle,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: Icon(
              _liked ? Icons.favorite_rounded : Icons.favorite_border,
              key: ValueKey(_liked),
              size: 18,
              color: _liked ? Colors.red : Colors.grey.shade500,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            '$_count',
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// CHAT TAB
// ═══════════════════════════════════════════════════════════════

class _ChatTab extends StatefulWidget {
  final String zoneId, myUid;
  final Color color;
  final bool isProvider;
  final ValueChanged<int>? onReportsChanged;

  const _ChatTab({
    required this.zoneId,
    required this.myUid,
    required this.color,
    required this.isProvider,
    this.onReportsChanged,
  });

  @override
  State<_ChatTab> createState() => _ChatTabState();
}

class _ChatTabState extends State<_ChatTab> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  final _msgTimes = <DateTime>[];

  bool _isMuted = false;
  DateTime? _mutedUntil;

  @override
  void initState() {
    super.initState();
    _checkMuteStatus();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _checkMuteStatus() async {
    try {
      final d = await FirebaseFirestore.instance
          .collection('zones')
          .doc(widget.zoneId)
          .collection('muted')
          .doc(widget.myUid)
          .get();
      if (!d.exists || !mounted) return;
      final data = d.data()!;
      final isPermanent = data['isPermanent'] == true;
      final until = data['mutedUntil'] as Timestamp?;
      if (isPermanent) {
        setState(() => _isMuted = true);
      } else if (until != null && until.toDate().isAfter(DateTime.now())) {
        setState(() {
          _isMuted = true;
          _mutedUntil = until.toDate();
        });
      } else if (!isPermanent && until != null) {
        // Expired — clean up
        await d.reference.delete();
      }
    } catch (_) {}
  }

  bool _isRateLimited() {
    final now = DateTime.now();
    _msgTimes.removeWhere((t) => now.difference(t).inSeconds > 60);
    return _msgTimes.length >= 5;
  }

  Future<void> _send() async {
    if (widget.myUid.isEmpty) return;
    if (_isMuted) {
      _showMutedWarning();
      return;
    }

    final text = _ctrl.text.trim();
    if (text.isEmpty) return;

    // Rate limit
    if (_isRateLimited()) {
      _showSnack(
        '⚠️ Slow down! Max 5 messages per minute.',
        const Color(0xFFF59E0B),
      );
      return;
    }

    // Profanity check
    final hasBadWords = _hasProfanity(text);
    if (hasBadWords) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Row(
            children: [
              Text('⚠️ ', style: TextStyle(fontSize: 20)),
              Text(
                'Language Warning',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
              ),
            ],
          ),
          content: const Text(
            'Your message may contain language that violates community guidelines. It will be sent with those words censored.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Edit Message'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF59E0B),
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Send Censored'),
            ),
          ],
        ),
      );
      if (proceed != true) return;
    }

    _ctrl.clear();
    _msgTimes.add(DateTime.now());

    // ✅ FIX: Get actual user name from Firestore
    final senderName = await _getUserDisplayName(widget.myUid);
    final finalText = hasBadWords ? _censorText(text) : text;

    await FirebaseFirestore.instance
        .collection('zones')
        .doc(widget.zoneId)
        .collection('messages')
        .add({
          'text': finalText,
          'senderId': widget.myUid,
          'senderName': senderName,
          'timestamp': FieldValue.serverTimestamp(),
          'isSystemMessage': false,
          'deletedAt': null,
        });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _showMutedWarning() {
    final msg = _mutedUntil != null
        ? 'You are muted until ${_mutedUntil!.hour}:${_mutedUntil!.minute.toString().padLeft(2, '0')}.'
        : 'You have been permanently muted in this zone.';
    _showSnack('🔇 $msg', const Color(0xFFEF4444));
  }

  void _showSnack(String text, Color bg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: bg,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _onLongPressMessage(Map<String, dynamic> data, String msgId) {
    if (data['isSystemMessage'] == true) return;
    HapticFeedback.mediumImpact();
    _showMessageOptions(data, msgId);
  }

  void _showMessageOptions(Map<String, dynamic> data, String msgId) {
    final isMe = data['senderId'] == widget.myUid;
    final isDeleted = data['deletedAt'] != null;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              const SizedBox(height: 12),

              // Reaction row
              if (!isDeleted)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: ['👍', '❤️', '😂', '😮', '😢', '🙏'].map((emoji) {
                      return GestureDetector(
                        onTap: () async {
                          Navigator.pop(context);
                          await _toggleReaction(msgId, emoji);
                        },
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            emoji,
                            style: const TextStyle(fontSize: 26),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),

              if (!isDeleted) const Divider(height: 1),

              // Actions
              if (!isDeleted && (isMe || widget.isProvider))
                ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFFFEE2E2),
                    radius: 18,
                    child: Icon(
                      Icons.delete_outline,
                      color: Colors.red,
                      size: 18,
                    ),
                  ),
                  title: const Text(
                    'Delete Message',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    isMe ? 'Remove your message' : 'Remove as provider',
                    style: const TextStyle(fontSize: 12),
                  ),
                  onTap: () async {
                    Navigator.pop(context);
                    await _deleteMessage(msgId);
                  },
                ),

              if (!isDeleted && !isMe)
                ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFFFEF3C7),
                    radius: 18,
                    child: Icon(
                      Icons.flag_outlined,
                      color: Color(0xFFF59E0B),
                      size: 18,
                    ),
                  ),
                  title: const Text(
                    'Report Message',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: const Text(
                    'Flag for provider review',
                    style: TextStyle(fontSize: 12),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _showReportDialog(data, msgId);
                  },
                ),

              if (widget.isProvider && !isMe) ...[
                ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFFEDE9FE),
                    radius: 18,
                    child: Icon(
                      Icons.timer_outlined,
                      color: Color(0xFF6366F1),
                      size: 18,
                    ),
                  ),
                  title: const Text(
                    'Mute User (24 Hours)',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: const Text(
                    'Temporarily silence this member',
                    style: TextStyle(fontSize: 12),
                  ),
                  onTap: () async {
                    Navigator.pop(context);
                    await _muteUser(
                      data['senderId'],
                      data['senderName'] ?? 'User',
                      isPermanent: false,
                    );
                  },
                ),
                ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFFFEE2E2),
                    radius: 18,
                    child: Icon(
                      Icons.block_rounded,
                      color: Colors.red,
                      size: 18,
                    ),
                  ),
                  title: const Text(
                    'Block from Zone',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Colors.red,
                    ),
                  ),
                  subtitle: const Text(
                    'Requires existing report',
                    style: TextStyle(fontSize: 12),
                  ),
                  onTap: () async {
                    Navigator.pop(context);
                    await _blockUser(
                      data['senderId'],
                      data['senderName'] ?? 'User',
                    );
                  },
                ),
              ],
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _toggleReaction(String msgId, String emoji) async {
    final ref = FirebaseFirestore.instance
        .collection('zones')
        .doc(widget.zoneId)
        .collection('messages')
        .doc(msgId)
        .collection('reactions')
        .doc(widget.myUid);
    final d = await ref.get();
    if (d.exists && d.data()?['emoji'] == emoji) {
      await ref.delete();
    } else {
      await ref.set({'emoji': emoji, 'uid': widget.myUid});
    }
  }

  Future<void> _deleteMessage(String msgId) async {
    await FirebaseFirestore.instance
        .collection('zones')
        .doc(widget.zoneId)
        .collection('messages')
        .doc(msgId)
        .update({
          'deletedAt': FieldValue.serverTimestamp(),
          'text': '[Message deleted]',
        });
  }

  void _showReportDialog(Map<String, dynamic> data, String msgId) {
    const reasons = [
      'Vulgar language',
      'Racist / discriminatory',
      'Spam',
      'Harassment',
      'Threatening behaviour',
      'Other',
    ];
    String? selected;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text(
            'Report Message',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Select a reason:',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              ...reasons.map(
                (r) => RadioListTile<String>(
                  dense: true,
                  value: r,
                  groupValue: selected,
                  title: Text(r, style: const TextStyle(fontSize: 14)),
                  onChanged: (v) => setS(() => selected = v),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFEF4444),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: selected == null
                  ? null
                  : () async {
                      Navigator.pop(ctx);
                      await _submitReport(data, msgId, selected!);
                    },
              child: const Text('Submit Report'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submitReport(
    Map<String, dynamic> data,
    String msgId,
    String reason,
  ) async {
    // ✅ FIX: Get reporter's name from Firestore
    final reporterName = await _getUserDisplayName(widget.myUid);

    await FirebaseFirestore.instance
        .collection('zones')
        .doc(widget.zoneId)
        .collection('reports')
        .add({
          'type': 'message',
          'messageId': msgId,
          'messageText': data['text'] ?? '',
          'reportedUid': data['senderId'] ?? '',
          'reportedName': data['senderName'] ?? 'User',
          'reporterUid': widget.myUid,
          'reporterName': reporterName, // ✅ ADD reporter name
          'reason': reason,
          'createdAt': FieldValue.serverTimestamp(),
          'status': 'pending',
        });
    _showSnack(
      '✅ Report submitted. A provider will review it.',
      const Color(0xFF10B981),
    );
  }

  Future<void> _muteUser(
    String targetUid,
    String targetName, {
    required bool isPermanent,
  }) async {
    final until = isPermanent
        ? null
        : DateTime.now().add(const Duration(hours: 24));
    await FirebaseFirestore.instance
        .collection('zones')
        .doc(widget.zoneId)
        .collection('muted')
        .doc(targetUid)
        .set({
          'uid': targetUid,
          'mutedBy': widget.myUid,
          'isPermanent': isPermanent,
          'mutedUntil': until != null ? Timestamp.fromDate(until) : null,
          'mutedAt': FieldValue.serverTimestamp(),
        });
    await _audit(
      'mute',
      targetUid,
      isPermanent ? 'Permanent mute' : '24h mute applied to $targetName',
    );
    _showSnack(
      isPermanent
          ? '🔇 $targetName permanently muted'
          : '🔇 $targetName muted for 24 hours',
      const Color(0xFF6366F1),
    );
  }

  Future<void> _blockUser(String targetUid, String targetName) async {
    // Require existing report
    final reports = await FirebaseFirestore.instance
        .collection('zones')
        .doc(widget.zoneId)
        .collection('reports')
        .where('reportedUid', isEqualTo: targetUid)
        .where('status', isEqualTo: 'pending')
        .get();

    if (reports.docs.isEmpty) {
      _showSnack(
        '⚠️ A pending report is required before blocking.',
        const Color(0xFFF59E0B),
      );
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Block $targetName?',
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        content: const Text(
          'This will block them from the zone\'s chat and feed. They may submit an appeal.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Block'),
          ),
        ],
      ),
    );

    if (ok == true) {
      await FirebaseFirestore.instance
          .collection('zones')
          .doc(widget.zoneId)
          .collection('blocked')
          .doc(targetUid)
          .set({
            'uid': targetUid,
            'blockedBy': widget.myUid,
            'blockedAt': FieldValue.serverTimestamp(),
          });
      for (final r in reports.docs) {
        await r.reference.update({'status': 'resolved_blocked'});
      }
      await _audit('block', targetUid, '$targetName blocked from zone');
      _showSnack('🚫 $targetName blocked from zone', Colors.red);
    }
  }

  Future<void> _audit(String action, String targetUid, String note) async {
    // ✅ FIX: Get performer's name from Firestore
    final performerName = await _getUserDisplayName(widget.myUid);

    await FirebaseFirestore.instance
        .collection('zones')
        .doc(widget.zoneId)
        .collection('audit_log')
        .add({
          'action': action,
          'targetUid': targetUid,
          'performedBy': widget.myUid,
          'performerName': performerName, // ✅ ADD performer name
          'note': note,
          'createdAt': FieldValue.serverTimestamp(),
        });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('zones')
                .doc(widget.zoneId)
                .collection('messages')
                .orderBy('timestamp', descending: false)
                .limit(100)
                .snapshots(),
            builder: (context, snap) {
              if (!snap.hasData)
                return const Center(child: CircularProgressIndicator());
              final docs = snap.data!.docs;

              if (docs.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.chat_bubble_outline_rounded,
                        size: 56,
                        color: widget.color.withOpacity(0.4),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'No messages yet',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Say hello 👋',
                        style: TextStyle(color: Color(0xFF64748B)),
                      ),
                    ],
                  ),
                );
              }

              return ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                itemCount: docs.length,
                itemBuilder: (ctx, i) {
                  final data = docs[i].data() as Map<String, dynamic>;
                  final msgId = docs[i].id;

                  if (data['isSystemMessage'] == true) {
                    return _SystemMessage(text: data['text'] ?? '');
                  }

                  final isMe = data['senderId'] == widget.myUid;
                  return GestureDetector(
                    onLongPress: () => _onLongPressMessage(data, msgId),
                    child: _MessageBubble(
                      msgId: msgId,
                      message: data,
                      isMe: isMe,
                      color: widget.color,
                      zoneId: widget.zoneId,
                      myUid: widget.myUid,
                    ),
                  );
                },
              );
            },
          ),
        ),

        // Input bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 8,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: _isMuted
                          ? Colors.grey.shade100
                          : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: TextField(
                      controller: _ctrl,
                      enabled: !_isMuted,
                      maxLines: null,
                      textCapitalization: TextCapitalization.sentences,
                      onSubmitted: (_) => _send(),
                      decoration: InputDecoration(
                        hintText: _isMuted
                            ? '🔇 You are currently muted'
                            : 'Type a message...',
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 12,
                        ),
                        hintStyle: TextStyle(color: Colors.grey.shade400),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                CircleAvatar(
                  backgroundColor: _isMuted
                      ? Colors.grey.shade300
                      : widget.color,
                  child: IconButton(
                    icon: const Icon(
                      Icons.send_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                    onPressed: _isMuted ? null : _send,
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

// ═══════════════════════════════════════════════════════════════
// MESSAGE BUBBLE
// ═══════════════════════════════════════════════════════════════

class _MessageBubble extends StatelessWidget {
  final String msgId, zoneId, myUid;
  final Map<String, dynamic> message;
  final bool isMe;
  final Color color;

  const _MessageBubble({
    required this.msgId,
    required this.zoneId,
    required this.myUid,
    required this.message,
    required this.isMe,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final isDeleted = message['deletedAt'] != null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment: isMe
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isMe) ...[
            CircleAvatar(
              radius: 15,
              backgroundColor: color.withOpacity(0.12),
              child: Icon(Icons.person, color: color, size: 15),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: isMe
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                if (!isMe)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4, left: 4),
                    child: Text(
                      message['senderName'] ?? 'User',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  constraints: const BoxConstraints(maxWidth: 270),
                  decoration: BoxDecoration(
                    color: isDeleted
                        ? Colors.grey.shade200
                        : isMe
                        ? color
                        : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(18),
                      topRight: const Radius.circular(18),
                      bottomLeft: Radius.circular(isMe ? 18 : 4),
                      bottomRight: Radius.circular(isMe ? 4 : 18),
                    ),
                  ),
                  child: Text(
                    message['text'] ?? '',
                    style: TextStyle(
                      fontSize: 14,
                      color: isDeleted
                          ? Colors.grey
                          : isMe
                          ? Colors.white
                          : const Color(0xFF0F172A),
                      fontStyle: isDeleted
                          ? FontStyle.italic
                          : FontStyle.normal,
                    ),
                  ),
                ),
                _ReactionRow(msgId: msgId, zoneId: zoneId, myUid: myUid),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// REACTION ROW
// ═══════════════════════════════════════════════════════════════

class _ReactionRow extends StatelessWidget {
  final String msgId, zoneId, myUid;
  const _ReactionRow({
    required this.msgId,
    required this.zoneId,
    required this.myUid,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('zones')
          .doc(zoneId)
          .collection('messages')
          .doc(msgId)
          .collection('reactions')
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData || snap.data!.docs.isEmpty)
          return const SizedBox.shrink();
        final Map<String, int> counts = {};
        String? myEmoji;
        for (final d in snap.data!.docs) {
          final data = d.data() as Map<String, dynamic>;
          final e = data['emoji'] as String? ?? '';
          counts[e] = (counts[e] ?? 0) + 1;
          if (d.id == myUid) myEmoji = e;
        }
        return Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Wrap(
            spacing: 4,
            children: counts.entries.map((entry) {
              final mine = myEmoji == entry.key;
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: mine
                      ? const Color(0xFF6366F1).withOpacity(0.1)
                      : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(10),
                  border: mine
                      ? Border.all(
                          color: const Color(0xFF6366F1).withOpacity(0.4),
                        )
                      : null,
                ),
                child: Text(
                  '${entry.key} ${entry.value}',
                  style: const TextStyle(fontSize: 12),
                ),
              );
            }).toList(),
          ),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// SYSTEM MESSAGE
// ═══════════════════════════════════════════════════════════════

class _SystemMessage extends StatelessWidget {
  final String text;
  const _SystemMessage({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.grey.shade200,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// MEMBERS TAB
// ═══════════════════════════════════════════════════════════════

class _MembersTab extends StatelessWidget {
  final String zoneId, myUid;
  final Color color;
  final bool isProvider;

  const _MembersTab({
    required this.zoneId,
    required this.myUid,
    required this.color,
    required this.isProvider,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('zones')
          .doc(zoneId)
          .collection('members')
          .orderBy('joinedAt', descending: false)
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData)
          return const Center(child: CircularProgressIndicator());
        final docs = snap.data!.docs;

        if (docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.people_outline_rounded,
                  size: 56,
                  color: color.withOpacity(0.4),
                ),
                const SizedBox(height: 16),
                const Text(
                  'No members yet',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          );
        }

        // Providers first
        final sorted = [...docs]
          ..sort((a, b) {
            final aRole = (a.data() as Map)['role'] ?? 'user';
            final bRole = (b.data() as Map)['role'] ?? 'user';
            if (aRole == 'provider' && bRole != 'provider') return -1;
            if (bRole == 'provider' && aRole != 'provider') return 1;
            return 0;
          });

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: sorted.length,
          itemBuilder: (ctx, i) {
            final member = sorted[i].data() as Map<String, dynamic>;
            return _MemberCard(
              member: member,
              color: color,
              isProvider: isProvider,
              myUid: myUid,
              zoneId: zoneId,
            );
          },
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// MEMBER CARD
// ═══════════════════════════════════════════════════════════════

class _MemberCard extends StatelessWidget {
  final Map<String, dynamic> member;
  final Color color;
  final bool isProvider;
  final String myUid, zoneId;

  const _MemberCard({
    required this.member,
    required this.color,
    required this.isProvider,
    required this.myUid,
    required this.zoneId,
  });

  @override
  Widget build(BuildContext context) {
    final role = member['role'] as String? ?? 'user';
    final uid = member['uid'] as String? ?? '';
    final photoUrl = member['photoUrl'] as String?;
    final isMe = uid == myUid;
    final isProviderMember = role == 'provider';

    // ✅ FIX: Fetch name from Firestore users collection
    return FutureBuilder<String>(
      future: _getUserDisplayName(uid),
      builder: (context, snapshot) {
        final name = snapshot.data ?? 'Loading...';

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: isProviderMember
                ? Border.all(color: color, width: 2)
                : null,
            boxShadow: [
              BoxShadow(
                color: isProviderMember
                    ? color.withOpacity(0.12)
                    : Colors.black.withOpacity(0.04),
                blurRadius: isProviderMember ? 12 : 6,
                offset: Offset(0, isProviderMember ? 4 : 2),
              ),
            ],
          ),
          child: Row(
            children: [
              // Avatar
              Stack(
                children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundColor: color.withOpacity(0.1),
                    backgroundImage: (photoUrl != null && photoUrl.isNotEmpty)
                        ? NetworkImage(photoUrl)
                        : null,
                    child: (photoUrl == null || photoUrl.isEmpty)
                        ? Icon(
                            isProviderMember
                                ? Icons.storefront_rounded
                                : Icons.person,
                            color: color,
                            size: 24,
                          )
                        : null,
                  ),
                  // Online dot placeholder
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 1.5),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 12),

              // Name + role
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            name,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                        ),
                        if (isMe) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: color.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'You',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: color,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: isProviderMember
                            ? color.withOpacity(0.1)
                            : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        isProviderMember ? '🏢 Provider' : '👤 Member',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: isProviderMember
                              ? color
                              : Colors.grey.shade600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Actions (only for other members)
              if (!isMe) ...[
                _ConnectButton(targetUid: uid, myUid: myUid, color: color),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => _reportMember(context, uid, name),
                  child: Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.flag_outlined,
                      size: 16,
                      color: Colors.red,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ); // End of Container
      }, // End of FutureBuilder builder
    ); // End of FutureBuilder
  }

  void _reportMember(
    BuildContext context,
    String targetUid,
    String targetName,
  ) {
    const reasons = [
      'Harassment',
      'Inappropriate behaviour',
      'Spam / fake account',
      'Racist language',
      'Other',
    ];
    String? selected;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text(
            'Report $targetName',
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: reasons
                .map(
                  (r) => RadioListTile<String>(
                    dense: true,
                    value: r,
                    groupValue: selected,
                    title: Text(r, style: const TextStyle(fontSize: 14)),
                    onChanged: (v) => setS(() => selected = v),
                  ),
                )
                .toList(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: selected == null
                  ? null
                  : () async {
                      await FirebaseFirestore.instance
                          .collection('zones')
                          .doc(zoneId)
                          .collection('reports')
                          .add({
                            'type': 'member',
                            'reportedUid': targetUid,
                            'reportedName': targetName,
                            'reporterUid': myUid,
                            'reason': selected,
                            'createdAt': FieldValue.serverTimestamp(),
                            'status': 'pending',
                          });
                      if (ctx.mounted) {
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(
                            content: Text(
                              '✅ Member reported for provider review.',
                            ),
                            backgroundColor: Color(0xFF10B981),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      }
                    },
              child: const Text('Submit Report'),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// CONNECT BUTTON
// ═══════════════════════════════════════════════════════════════

class _ConnectButton extends StatefulWidget {
  final String targetUid, myUid;
  final Color color;
  const _ConnectButton({
    required this.targetUid,
    required this.myUid,
    required this.color,
  });

  @override
  State<_ConnectButton> createState() => _ConnectButtonState();
}

class _ConnectButtonState extends State<_ConnectButton> {
  /// none | pending | connected
  String _status = 'none';

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    try {
      // Check outgoing
      final out = await FirebaseFirestore.instance
          .collection('connect_requests')
          .doc('${widget.myUid}_${widget.targetUid}')
          .get();
      if (out.exists && mounted) {
        setState(() => _status = out.data()?['status'] ?? 'pending');
        return;
      }
      // Check incoming
      final inc = await FirebaseFirestore.instance
          .collection('connect_requests')
          .doc('${widget.targetUid}_${widget.myUid}')
          .get();
      if (inc.exists && mounted) {
        setState(() => _status = inc.data()?['status'] ?? 'pending');
      }
    } catch (_) {}
  }

  Future<void> _sendRequest() async {
    await FirebaseFirestore.instance
        .collection('connect_requests')
        .doc('${widget.myUid}_${widget.targetUid}')
        .set({
          'fromUid': widget.myUid,
          'toUid': widget.targetUid,
          'status': 'pending',
          'createdAt': FieldValue.serverTimestamp(),
        });
    if (mounted) setState(() => _status = 'pending');
  }

  @override
  Widget build(BuildContext context) {
    if (_status == 'connected') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.green.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_rounded, size: 13, color: Colors.green),
            SizedBox(width: 3),
            Text(
              'Connected',
              style: TextStyle(
                fontSize: 11,
                color: Colors.green,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
    }
    if (_status == 'pending') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Text(
          'Pending',
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }
    return GestureDetector(
      onTap: _sendRequest,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: widget.color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: widget.color.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.person_add_alt_1_rounded, size: 13, color: widget.color),
            const SizedBox(width: 4),
            Text(
              'Connect',
              style: TextStyle(
                fontSize: 11,
                color: widget.color,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// PROVIDER DASHBOARD
// ═══════════════════════════════════════════════════════════════

class _ProviderDashboard extends StatelessWidget {
  final String zoneId, myUid;
  final Color color;

  const _ProviderDashboard({
    required this.zoneId,
    required this.myUid,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.82,
      decoration: const BoxDecoration(
        color: Color(0xFFF8F9FF),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(99),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.shield_rounded, color: color, size: 22),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Provider Dashboard',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: DefaultTabController(
              length: 3,
              child: Column(
                children: [
                  TabBar(
                    labelColor: color,
                    unselectedLabelColor: Colors.grey,
                    indicatorColor: color,
                    labelStyle: const TextStyle(fontWeight: FontWeight.w700),
                    tabs: const [
                      Tab(text: '🚨 Reports'),
                      Tab(text: '📬 Appeals'),
                      Tab(text: '📋 Audit Log'),
                    ],
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _ReportsView(
                          zoneId: zoneId,
                          color: color,
                          myUid: myUid,
                        ),
                        _AppealsView(zoneId: zoneId, color: color),
                        _AuditLogView(zoneId: zoneId),
                      ],
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

// ═══════════════════════════════════════════════════════════════
// REPORTS VIEW (inside dashboard)
// ═══════════════════════════════════════════════════════════════

class _ReportsView extends StatelessWidget {
  final String zoneId, myUid;
  final Color color;
  const _ReportsView({
    required this.zoneId,
    required this.myUid,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('zones')
          .doc(zoneId)
          .collection('reports')
          .where('status', isEqualTo: 'pending')
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData)
          return const Center(child: CircularProgressIndicator());
        final docs = snap.data!.docs;

        if (docs.isEmpty) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.check_circle_outline_rounded,
                  size: 52,
                  color: Color(0xFF10B981),
                ),
                SizedBox(height: 12),
                Text(
                  'All clear!',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                ),
                SizedBox(height: 4),
                Text(
                  'No pending reports',
                  style: TextStyle(color: Colors.grey),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          itemBuilder: (ctx, i) {
            final data = docs[i].data() as Map<String, dynamic>;
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.red.withOpacity(0.15)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.03),
                    blurRadius: 6,
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.flag_rounded,
                        size: 15,
                        color: Color(0xFFEF4444),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Reported: ${data['reportedName'] ?? 'Unknown'}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          data['reason'] ?? '',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.red,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if ((data['messageText'] ?? '').toString().isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Text(
                        '"${data['messageText']}"',
                        style: TextStyle(
                          fontSize: 13,
                          fontStyle: FontStyle.italic,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          onPressed: () =>
                              docs[i].reference.update({'status': 'dismissed'}),
                          child: const Text(
                            'Dismiss',
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF6366F1),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          onPressed: () => _mute24h(
                            context,
                            data['reportedUid'],
                            docs[i].id,
                          ),
                          child: const Text(
                            'Mute 24h',
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          onPressed: () => _block(
                            context,
                            data['reportedUid'],
                            data['reportedName'] ?? '',
                            docs[i].id,
                          ),
                          child: const Text(
                            'Block',
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _mute24h(
    BuildContext context,
    String targetUid,
    String reportId,
  ) async {
    final until = DateTime.now().add(const Duration(hours: 24));
    await FirebaseFirestore.instance
        .collection('zones')
        .doc(zoneId)
        .collection('muted')
        .doc(targetUid)
        .set({
          'uid': targetUid,
          'mutedBy': myUid,
          'isPermanent': false,
          'mutedUntil': Timestamp.fromDate(until),
          'mutedAt': FieldValue.serverTimestamp(),
        });
    await FirebaseFirestore.instance
        .collection('zones')
        .doc(zoneId)
        .collection('reports')
        .doc(reportId)
        .update({'status': 'resolved_muted'});
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🔇 User muted for 24 hours'),
          backgroundColor: Color(0xFF6366F1),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _block(
    BuildContext context,
    String targetUid,
    String targetName,
    String reportId,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Block $targetName?',
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        content: const Text(
          'They will be blocked from chat and feed. They can appeal.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Block'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await FirebaseFirestore.instance
          .collection('zones')
          .doc(zoneId)
          .collection('blocked')
          .doc(targetUid)
          .set({
            'uid': targetUid,
            'blockedBy': myUid,
            'blockedAt': FieldValue.serverTimestamp(),
          });
      await FirebaseFirestore.instance
          .collection('zones')
          .doc(zoneId)
          .collection('reports')
          .doc(reportId)
          .update({'status': 'resolved_blocked'});
      await FirebaseFirestore.instance
          .collection('zones')
          .doc(zoneId)
          .collection('audit_log')
          .add({
            'action': 'block',
            'targetUid': targetUid,
            'performedBy': myUid,
            'note': '$targetName blocked from zone via report',
            'createdAt': FieldValue.serverTimestamp(),
          });
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🚫 User blocked from zone'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }
}

// ═══════════════════════════════════════════════════════════════
// APPEALS VIEW
// ═══════════════════════════════════════════════════════════════

class _AppealsView extends StatelessWidget {
  final String zoneId;
  final Color color;
  const _AppealsView({required this.zoneId, required this.color});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('zones')
          .doc(zoneId)
          .collection('appeals')
          .where('status', isEqualTo: 'pending')
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData)
          return const Center(child: CircularProgressIndicator());
        final docs = snap.data!.docs;

        if (docs.isEmpty) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.inbox_outlined, size: 48, color: Colors.grey),
                SizedBox(height: 12),
                Text(
                  'No pending appeals',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          itemBuilder: (ctx, i) {
            final data = docs[i].data() as Map<String, dynamic>;
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.blue.withOpacity(0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ✅ FIX: Show user name instead of UID
                  FutureBuilder<String>(
                    future: _getUserDisplayName(data['uid'] ?? ''),
                    builder: (context, snapshot) {
                      final displayName = snapshot.data ?? 'Loading...';
                      return Text(
                        'From: $displayName',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                  Text(
                    data['reason'] ?? '',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          onPressed: () =>
                              docs[i].reference.update({'status': 'rejected'}),
                          child: const Text('Reject'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: color,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          onPressed: () async {
                            await FirebaseFirestore.instance
                                .collection('zones')
                                .doc(zoneId)
                                .collection('blocked')
                                .doc(data['uid'])
                                .delete();
                            await docs[i].reference.update({
                              'status': 'approved',
                            });
                            if (ctx.mounted) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    '✅ Appeal approved — user unblocked',
                                  ),
                                  backgroundColor: Color(0xFF10B981),
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            }
                          },
                          child: const Text('Approve & Unblock'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// AUDIT LOG VIEW
// ═══════════════════════════════════════════════════════════════

class _AuditLogView extends StatelessWidget {
  final String zoneId;
  const _AuditLogView({required this.zoneId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('zones')
          .doc(zoneId)
          .collection('audit_log')
          .orderBy('createdAt', descending: true)
          .limit(50)
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData)
          return const Center(child: CircularProgressIndicator());
        final docs = snap.data!.docs;

        if (docs.isEmpty) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.history_rounded, size: 48, color: Colors.grey),
                SizedBox(height: 12),
                Text(
                  'No actions yet',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          itemBuilder: (ctx, i) {
            final data = docs[i].data() as Map<String, dynamic>;
            final action = data['action'] as String? ?? '';
            final (icon, iconColor) = switch (action) {
              'block' => (Icons.block_rounded, Colors.red),
              'mute' => (Icons.volume_off_rounded, const Color(0xFF6366F1)),
              _ => (Icons.info_outline_rounded, Colors.grey),
            };
            return ListTile(
              dense: true,
              leading: CircleAvatar(
                radius: 16,
                backgroundColor: iconColor.withOpacity(0.1),
                child: Icon(icon, size: 16, color: iconColor),
              ),
              title: Text(
                data['note'] ?? action,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
              subtitle: Text(
                'By: ${data['performerName'] ?? 'Provider'}', // ✅ FIX: Use name
                style: const TextStyle(fontSize: 11),
              ),
            );
          },
        );
      },
    );
  }
}
