import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

/// 🏠 ZONE HUB - Main screen for each Wembley zone
/// Contains 3 tabs: Feed (provider posts), Chat (group messages), Members
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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FF),
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) {
          return [
            // Premium Gradient Header
            SliverAppBar(
              expandedHeight: 140,
              floating: false,
              pinned: true,
              backgroundColor: widget.color,
              flexibleSpace: FlexibleSpaceBar(
                background: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [widget.gradientStart, widget.gradientEnd],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 80, 20, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          widget.zoneName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        _MemberCount(
                          zoneId: widget.zoneId,
                          color: Colors.white.withOpacity(0.9),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              bottom: TabBar(
                controller: _tabController,
                indicatorColor: Colors.white,
                indicatorWeight: 3,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white.withOpacity(0.6),
                labelStyle: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                ),
                tabs: const [
                  Tab(text: 'Feed'),
                  Tab(text: 'Chat'),
                  Tab(text: 'Members'),
                ],
              ),
            ),
          ];
        },
        body: TabBarView(
          controller: _tabController,
          children: [
            _FeedTab(zoneId: widget.zoneId, color: widget.color),
            _ChatTab(
              zoneId: widget.zoneId,
              zoneName: widget.zoneName,
              color: widget.color,
            ),
            _MembersTab(zoneId: widget.zoneId, color: widget.color),
          ],
        ),
      ),
      floatingActionButton: _tabController.index == 0
          ? _CreatePostFAB(
              zoneId: widget.zoneId,
              color: widget.color,
              gradientStart: widget.gradientStart,
              gradientEnd: widget.gradientEnd,
            )
          : null,
    );
  }
}

/// 📊 Member Count Widget
class _MemberCount extends StatelessWidget {
  final String zoneId;
  final Color color;

  const _MemberCount({required this.zoneId, required this.color});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('zones')
          .doc(zoneId)
          .collection('members')
          .snapshots(),
      builder: (context, snap) {
        final count = snap.data?.docs.length ?? 0;
        return Text(
          '$count members',
          style: TextStyle(
            color: color,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        );
      },
    );
  }
}

/// 📰 FEED TAB - Provider announcements and posts
class _FeedTab extends StatelessWidget {
  final String zoneId;
  final Color color;

  const _FeedTab({required this.zoneId, required this.color});

  @override
  Widget build(BuildContext context) {
    final postsQuery = FirebaseFirestore.instance
        .collection('zones')
        .doc(zoneId)
        .collection('posts')
        .orderBy('created_at', descending: true)
        .limit(50);

    return RefreshIndicator(
      onRefresh: () async {
        await Future.delayed(const Duration(milliseconds: 500));
      },
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: postsQuery.snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            return _EmptyState(
              icon: Icons.error_outline,
              message: 'Error loading feed',
              color: color,
            );
          }

          if (snap.connectionState == ConnectionState.waiting) {
            return Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            );
          }

          final posts = snap.data?.docs ?? [];

          if (posts.isEmpty) {
            return _EmptyState(
              icon: Icons.article_outlined,
              message: 'No posts yet\nBe the first to share!',
              color: color,
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: posts.length,
            itemBuilder: (context, index) {
              final post = posts[index];
              final data = post.data();
              return _PostCard(
                postId: post.id,
                zoneId: zoneId,
                data: data,
                color: color,
              );
            },
          );
        },
      ),
    );
  }
}

/// 📝 Post Card
class _PostCard extends StatelessWidget {
  final String postId;
  final String zoneId;
  final Map<String, dynamic> data;
  final Color color;

  const _PostCard({
    required this.postId,
    required this.zoneId,
    required this.data,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final authorId = data['author_id'] as String? ?? '';
    final authorType = data['author_type'] as String? ?? 'user';
    final text = data['text'] as String? ?? '';
    final parkingSpaceId = data['parking_space_id'] as String?;
    final createdAt = (data['created_at'] as Timestamp?)?.toDate();
    final likes = (data['likes'] as List?)?.cast<String>() ?? [];

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: authorType == 'provider'
            ? Border.all(color: color.withOpacity(0.3), width: 2)
            : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Author Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: authorType == 'provider'
                      ? LinearGradient(colors: [color, color.withOpacity(0.7)])
                      : null,
                  color: authorType != 'provider'
                      ? const Color(0xFFE2E8F0)
                      : null,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  authorType == 'provider'
                      ? Icons.local_parking_rounded
                      : Icons.person_rounded,
                  color: authorType == 'provider'
                      ? Colors.white
                      : const Color(0xFF64748B),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _AuthorName(uid: authorId),
                    if (authorType == 'provider')
                      Container(
                        margin: const EdgeInsets.only(top: 4),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'PARKING PROVIDER',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            color: color,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (createdAt != null)
                Text(
                  _formatTime(createdAt),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade500,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),

          // Post Content
          Text(
            text,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Color(0xFF0F172A),
              height: 1.4,
            ),
          ),

          // Parking Space Link
          if (parkingSpaceId != null) ...[
            const SizedBox(height: 12),
            _ParkingSpaceLink(spaceId: parkingSpaceId, color: color),
          ],

          // Actions
          const SizedBox(height: 14),
          Row(
            children: [
              _LikeButton(
                postId: postId,
                zoneId: zoneId,
                likes: likes,
                color: color,
              ),
              const SizedBox(width: 20),
              Icon(
                Icons.comment_outlined,
                size: 18,
                color: Colors.grey.shade600,
              ),
              const SizedBox(width: 6),
              Text(
                '0',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);

    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return DateFormat('MMM d').format(time);
  }
}

/// 👤 Author Name Widget
class _AuthorName extends StatelessWidget {
  final String uid;

  const _AuthorName({required this.uid});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .snapshots(),
      builder: (context, snap) {
        final name = snap.data?.data()?['name'] as String? ?? 'User';
        return Text(
          name,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w900,
            color: Color(0xFF0F172A),
          ),
        );
      },
    );
  }
}

/// ❤️ Like Button
class _LikeButton extends StatelessWidget {
  final String postId;
  final String zoneId;
  final List<String> likes;
  final Color color;

  const _LikeButton({
    required this.postId,
    required this.zoneId,
    required this.likes,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const SizedBox.shrink();

    final isLiked = likes.contains(user.uid);

    return GestureDetector(
      onTap: () => _toggleLike(user.uid),
      child: Row(
        children: [
          Icon(
            isLiked ? Icons.favorite : Icons.favorite_border,
            size: 18,
            color: isLiked ? color : Colors.grey.shade600,
          ),
          const SizedBox(width: 6),
          Text(
            '${likes.length}',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: isLiked ? color : Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleLike(String uid) async {
    final postRef = FirebaseFirestore.instance
        .collection('zones')
        .doc(zoneId)
        .collection('posts')
        .doc(postId);

    if (likes.contains(uid)) {
      await postRef.update({
        'likes': FieldValue.arrayRemove([uid]),
      });
    } else {
      await postRef.update({
        'likes': FieldValue.arrayUnion([uid]),
      });
    }
  }
}

/// 🅿️ Parking Space Link
class _ParkingSpaceLink extends StatelessWidget {
  final String spaceId;
  final Color color;

  const _ParkingSpaceLink({required this.spaceId, required this.color});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('parking_spaces')
          .doc(spaceId)
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData || !snap.data!.exists) {
          return const SizedBox.shrink();
        }

        final data = snap.data!.data()!;
        final title = data['title'] as String? ?? 'Parking Space';
        final hourlyRate = (data['hourly_rate_gbp'] as num?)?.toDouble() ?? 0;

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withOpacity(0.3)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.local_parking_rounded,
                  color: color,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: color,
                      ),
                    ),
                    Text(
                      '£${hourlyRate.toStringAsFixed(2)}/hour',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios_rounded, size: 16, color: color),
            ],
          ),
        );
      },
    );
  }
}

/// 💬 CHAT TAB - Group messaging
class _ChatTab extends StatefulWidget {
  final String zoneId;
  final String zoneName;
  final Color color;

  const _ChatTab({
    required this.zoneId,
    required this.zoneName,
    required this.color,
  });

  @override
  State<_ChatTab> createState() => _ChatTabState();
}

class _ChatTabState extends State<_ChatTab> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  bool _sending = false;

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _sendMessage() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    setState(() => _sending = true);

    try {
      await FirebaseFirestore.instance
          .collection('zones')
          .doc(widget.zoneId)
          .collection('messages')
          .add({
            'sender_id': user.uid,
            'sender_name': user.displayName ?? 'User',
            'text': text,
            'created_at': FieldValue.serverTimestamp(),
          });

      _messageController.clear();

      // Scroll to bottom
      Future.delayed(const Duration(milliseconds: 100), () {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final messagesQuery = FirebaseFirestore.instance
        .collection('zones')
        .doc(widget.zoneId)
        .collection('messages')
        .orderBy('created_at', descending: false)
        .limit(100);

    return Column(
      children: [
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: messagesQuery.snapshots(),
            builder: (context, snap) {
              if (snap.hasError) {
                return _EmptyState(
                  icon: Icons.error_outline,
                  message: 'Error loading messages',
                  color: widget.color,
                );
              }

              if (snap.connectionState == ConnectionState.waiting) {
                return Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(widget.color),
                  ),
                );
              }

              final messages = snap.data?.docs ?? [];

              if (messages.isEmpty) {
                return _EmptyState(
                  icon: Icons.chat_bubble_outline,
                  message: 'No messages yet\nStart the conversation!',
                  color: widget.color,
                );
              }

              return ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.all(16),
                itemCount: messages.length,
                itemBuilder: (context, index) {
                  final msg = messages[index];
                  final data = msg.data();
                  return _ChatBubble(data: data, color: widget.color);
                },
              );
            },
          ),
        ),

        // Message Input
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8F9FF),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: TextField(
                      controller: _messageController,
                      decoration: const InputDecoration(
                        hintText: 'Type a message...',
                        border: InputBorder.none,
                      ),
                      maxLines: null,
                      textCapitalization: TextCapitalization.sentences,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [widget.color, widget.color.withOpacity(0.8)],
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: _sending
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white,
                              ),
                            ),
                          )
                        : const Icon(Icons.send_rounded, color: Colors.white),
                    onPressed: _sending ? null : _sendMessage,
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

/// 💬 Chat Bubble
class _ChatBubble extends StatelessWidget {
  final Map<String, dynamic> data;
  final Color color;

  const _ChatBubble({required this.data, required this.color});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final senderId = data['sender_id'] as String? ?? '';
    final senderName = data['sender_name'] as String? ?? 'User';
    final text = data['text'] as String? ?? '';
    final createdAt = (data['created_at'] as Timestamp?)?.toDate();
    final isMe = senderId == user?.uid;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: isMe
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isMe) ...[
            CircleAvatar(
              radius: 16,
              backgroundColor: color.withOpacity(0.2),
              child: Text(
                senderName[0].toUpperCase(),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: color,
                ),
              ),
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
                    padding: const EdgeInsets.only(left: 12, bottom: 4),
                    child: Text(
                      senderName,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    gradient: isMe
                        ? LinearGradient(
                            colors: [color, color.withOpacity(0.8)],
                          )
                        : null,
                    color: !isMe ? Colors.white : null,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Text(
                    text,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: isMe ? Colors.white : const Color(0xFF0F172A),
                      height: 1.3,
                    ),
                  ),
                ),
                if (createdAt != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      _formatTime(createdAt),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);

    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return DateFormat('MMM d, h:mm a').format(time);
  }
}

/// 👥 MEMBERS TAB - Member directory
class _MembersTab extends StatelessWidget {
  final String zoneId;
  final Color color;

  const _MembersTab({required this.zoneId, required this.color});

  @override
  Widget build(BuildContext context) {
    final membersQuery = FirebaseFirestore.instance
        .collection('zones')
        .doc(zoneId)
        .collection('members')
        .orderBy('joinedAt', descending: true);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: membersQuery.snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return _EmptyState(
            icon: Icons.error_outline,
            message: 'Error loading members',
            color: color,
          );
        }

        if (snap.connectionState == ConnectionState.waiting) {
          return Center(
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          );
        }

        final members = snap.data?.docs ?? [];

        if (members.isEmpty) {
          return _EmptyState(
            icon: Icons.people_outline,
            message: 'No members yet',
            color: color,
          );
        }

        // Separate providers and users
        final providers = members
            .where((m) => m.data()['role'] == 'provider')
            .toList();
        final users = members
            .where((m) => m.data()['role'] != 'provider')
            .toList();

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (providers.isNotEmpty) ...[
              Text(
                'Parking Providers (${providers.length})',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 12),
              ...providers.map(
                (m) =>
                    _MemberCard(data: m.data(), color: color, isProvider: true),
              ),
              const SizedBox(height: 24),
            ],
            Text(
              'Community Members (${users.length})',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 12),
            ...users.map(
              (m) =>
                  _MemberCard(data: m.data(), color: color, isProvider: false),
            ),
          ],
        );
      },
    );
  }
}

/// 👤 Member Card
class _MemberCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final Color color;
  final bool isProvider;

  const _MemberCard({
    required this.data,
    required this.color,
    required this.isProvider,
  });

  @override
  Widget build(BuildContext context) {
    final displayName = data['displayName'] as String? ?? 'User';
    final joinedAt = (data['joinedAt'] as Timestamp?)?.toDate();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: isProvider
            ? Border.all(color: color.withOpacity(0.3), width: 2)
            : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              gradient: isProvider
                  ? LinearGradient(colors: [color, color.withOpacity(0.7)])
                  : null,
              color: !isProvider ? const Color(0xFFE2E8F0) : null,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Center(
              child: Text(
                displayName[0].toUpperCase(),
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: isProvider ? Colors.white : const Color(0xFF64748B),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF0F172A),
                  ),
                ),
                if (isProvider)
                  Container(
                    margin: const EdgeInsets.only(top: 4),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'PROVIDER',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        color: color,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                if (joinedAt != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Joined ${_formatDate(joinedAt)}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inDays < 1) return 'today';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    if (diff.inDays < 30) return '${(diff.inDays / 7).floor()}w ago';
    return DateFormat('MMM d, y').format(date);
  }
}

/// ➕ Create Post FAB
class _CreatePostFAB extends StatelessWidget {
  final String zoneId;
  final Color color;
  final Color gradientStart;
  final Color gradientEnd;

  const _CreatePostFAB({
    required this.zoneId,
    required this.color,
    required this.gradientStart,
    required this.gradientEnd,
  });

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton.extended(
      onPressed: () => _showCreatePostDialog(context),
      backgroundColor: color,
      label: const Text(
        'Create Post',
        style: TextStyle(fontWeight: FontWeight.w900),
      ),
      icon: const Icon(Icons.add_rounded),
    );
  }

  void _showCreatePostDialog(BuildContext context) {
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(
          'Create Post',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'Share an update...',
            border: OutlineInputBorder(),
          ),
          maxLines: 5,
          maxLength: 500,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final text = controller.text.trim();
              if (text.isEmpty) return;

              final user = FirebaseAuth.instance.currentUser;
              if (user == null) return;

              // Check if user is a provider
              final memberDoc = await FirebaseFirestore.instance
                  .collection('zones')
                  .doc(zoneId)
                  .collection('members')
                  .doc(user.uid)
                  .get();

              final role = memberDoc.data()?['role'] as String? ?? 'user';

              await FirebaseFirestore.instance
                  .collection('zones')
                  .doc(zoneId)
                  .collection('posts')
                  .add({
                    'author_id': user.uid,
                    'author_type': role,
                    'text': text,
                    'likes': [],
                    'comments_count': 0,
                    'created_at': FieldValue.serverTimestamp(),
                  });

              if (context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('Post created!')));
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: color),
            child: const Text('Post'),
          ),
        ],
      ),
    );
  }
}

/// ❌ Empty State Widget
class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  final Color color;

  const _EmptyState({
    required this.icon,
    required this.message,
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
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 48, color: color),
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade600,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
