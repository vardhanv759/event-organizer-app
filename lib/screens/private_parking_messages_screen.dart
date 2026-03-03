import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../services/messaging_service.dart';
import 'private_parking_chat_screen.dart';

class PrivateParkingMessagesScreen extends StatelessWidget {
  const PrivateParkingMessagesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock_outline, size: 64, color: Colors.grey.shade400),
              const SizedBox(height: 16),
              Text(
                'Please sign in to view messages',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
    }
    final myUid = user.uid;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FF),
      appBar: AppBar(
        title: const Text(
          'Messages',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          _NotificationBadge(uid: myUid),
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await Future.delayed(const Duration(milliseconds: 500));
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ✅ REMOVED: Public Chats section (community messaging)
            _IncomingRequestsSection(myUid: myUid),
            const SizedBox(height: 24),
            _OutgoingRequestsSection(myUid: myUid),
            const SizedBox(height: 24),
            _ChatsSection(myUid: myUid),
          ],
        ),
      ),
    );
  }
}

/* -------------------------------------------------------------------------- */
/*                            PUBLIC CHATS (NEW)                              */
/* -------------------------------------------------------------------------- */
/*                            NOTIFICATION BADGE                              */
/* -------------------------------------------------------------------------- */

class _NotificationBadge extends StatelessWidget {
  final String uid;
  const _NotificationBadge({required this.uid});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: MessagingService.totalNotificationCountStream(uid),
      builder: (context, snapshot) {
        final count = snapshot.data ?? 0;

        return Stack(
          clipBehavior: Clip.none,
          children: [
            IconButton(
              icon: const Icon(Icons.notifications_outlined),
              onPressed: () {},
            ),
            if (count > 0)
              Positioned(
                right: 8,
                top: 8,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: Color(0xFFEF4444),
                    shape: BoxShape.circle,
                  ),
                  constraints: const BoxConstraints(
                    minWidth: 18,
                    minHeight: 18,
                  ),
                  child: Text(
                    count > 99 ? '99+' : count.toString(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/* -------------------------------------------------------------------------- */
/*                           INCOMING REQUESTS SECTION                        */
/* -------------------------------------------------------------------------- */

class _IncomingRequestsSection extends StatelessWidget {
  final String myUid;
  const _IncomingRequestsSection({required this.myUid});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        StreamBuilder<int>(
          stream: MessagingService.pendingRequestsCountStream(myUid),
          builder: (context, snapshot) {
            final count = snapshot.data ?? 0;
            return _SectionTitle('Incoming Requests', badge: count);
          },
        ),
        const SizedBox(height: 12),
        _IncomingRequests(myUid: myUid),
      ],
    );
  }
}

class _IncomingRequests extends StatelessWidget {
  final String myUid;
  const _IncomingRequests({required this.myUid});

  @override
  Widget build(BuildContext context) {
    final q = FirebaseFirestore.instance
        .collection('chat_requests')
        .where('to_uid', isEqualTo: myUid)
        .where('status', isEqualTo: 'pending');

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: q.snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return const _EmptyCard(
            text: 'Error loading requests',
            icon: Icons.error_outline,
          );
        }
        if (snap.connectionState == ConnectionState.waiting) {
          return const _LoadingCard();
        }

        final docs = snap.data?.docs ?? const [];
        if (docs.isEmpty) {
          return const _EmptyCard(
            text: 'No incoming requests',
            icon: Icons.inbox_outlined,
          );
        }

        return Column(
          children: docs.map((d) {
            final data = d.data();
            final fromUid = (data['from_uid'] as String?)?.trim() ?? '';
            if (fromUid.isEmpty) return const SizedBox.shrink();

            return _IncomingRequestTile(requestId: d.id, fromUid: fromUid);
          }).toList(),
        );
      },
    );
  }
}

class _IncomingRequestTile extends StatefulWidget {
  final String requestId;
  final String fromUid;

  const _IncomingRequestTile({required this.requestId, required this.fromUid});

  @override
  State<_IncomingRequestTile> createState() => _IncomingRequestTileState();
}

class _IncomingRequestTileState extends State<_IncomingRequestTile>
    with SingleTickerProviderStateMixin {
  bool _busy = false;
  late AnimationController _animController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> _reject() async {
    if (_busy) return;
    _animController.forward().then((_) => _animController.reverse());
    setState(() => _busy = true);
    try {
      await MessagingService.rejectChatRequest(widget.requestId);
      if (!mounted) return;
      _toast(context, 'Request rejected');
    } catch (e) {
      if (mounted) _toast(context, 'Reject failed: $e', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _accept() async {
    if (_busy) return;
    _animController.forward().then((_) => _animController.reverse());
    setState(() => _busy = true);

    try {
      final chatId = await MessagingService.acceptChatRequest(widget.requestId);

      if (!mounted) return;

      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PrivateParkingChatScreen(
            chatId: chatId,
            otherUid: widget.fromUid,
          ),
        ),
      );
    } catch (e) {
      if (mounted) _toast(context, 'Accept failed: $e', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scaleAnimation,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFEEF2FF), Color(0xFFFDF4FF)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFF6366F1).withOpacity(0.2)),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF6366F1).withOpacity(0.08),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 8,
          ),
          leading: Container(
            height: 50,
            width: 50,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.mark_unread_chat_alt_rounded,
              color: Colors.white,
            ),
          ),
          title: _UserName(uid: widget.fromUid),
          subtitle: const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text(
              'Wants to chat with you',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Color(0xFF64748B),
              ),
            ),
          ),
          trailing: _busy
              ? const SizedBox(
                  height: 24,
                  width: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _ActionButton(
                      icon: Icons.close_rounded,
                      color: Color(0xFFEF4444),
                      onPressed: _reject,
                    ),
                    const SizedBox(width: 8),
                    _ActionButton(
                      icon: Icons.check_rounded,
                      color: Color(0xFF10B981),
                      onPressed: _accept,
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

/* -------------------------------------------------------------------------- */
/*                           OUTGOING REQUESTS SECTION                        */
/* -------------------------------------------------------------------------- */

class _OutgoingRequestsSection extends StatelessWidget {
  final String myUid;
  const _OutgoingRequestsSection({required this.myUid});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle('Outgoing Requests'),
        const SizedBox(height: 12),
        _OutgoingRequests(myUid: myUid),
      ],
    );
  }
}

class _OutgoingRequests extends StatelessWidget {
  final String myUid;
  const _OutgoingRequests({required this.myUid});

  @override
  Widget build(BuildContext context) {
    final q = FirebaseFirestore.instance
        .collection('chat_requests')
        .where('from_uid', isEqualTo: myUid)
        .where('status', isEqualTo: 'pending');

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: q.snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return const _EmptyCard(
            text: 'Error loading requests',
            icon: Icons.error_outline,
          );
        }
        if (snap.connectionState == ConnectionState.waiting) {
          return const _LoadingCard();
        }

        final docs = snap.data?.docs ?? const [];
        if (docs.isEmpty) {
          return const _EmptyCard(
            text: 'No outgoing requests',
            icon: Icons.outbox_outlined,
          );
        }

        return Column(
          children: docs.map((d) {
            final data = d.data();
            final toUid = (data['to_uid'] as String?)?.trim() ?? '';
            if (toUid.isEmpty) return const SizedBox.shrink();

            return _OutgoingRequestTile(requestId: d.id, toUid: toUid);
          }).toList(),
        );
      },
    );
  }
}

class _OutgoingRequestTile extends StatelessWidget {
  final String requestId;
  final String toUid;

  const _OutgoingRequestTile({required this.requestId, required this.toUid});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: ListTile(
        leading: const Icon(Icons.schedule_rounded, color: Color(0xFF64748B)),
        title: _UserName(uid: toUid),
        subtitle: const Text('Pending'),
        trailing: TextButton(
          onPressed: () async {
            await MessagingService.cancelChatRequest(requestId);
            _toast(context, 'Request cancelled');
          },
          child: const Text('Cancel'),
        ),
      ),
    );
  }
}

/* -------------------------------------------------------------------------- */
/*                                   CHATS                                    */
/* -------------------------------------------------------------------------- */

class _ChatsSection extends StatelessWidget {
  final String myUid;
  const _ChatsSection({required this.myUid});

  @override
  Widget build(BuildContext context) {
    final q = FirebaseFirestore.instance
        .collection('chats')
        .where('participants', arrayContains: myUid);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle('Chats'),
        const SizedBox(height: 12),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: q.snapshots(),
          builder: (context, snap) {
            if (snap.hasError) {
              return const _EmptyCard(
                text: 'Error loading chats',
                icon: Icons.error_outline,
              );
            }
            if (snap.connectionState == ConnectionState.waiting) {
              return const _LoadingCard();
            }

            final docs = snap.data?.docs ?? const [];
            if (docs.isEmpty) {
              return const _EmptyCard(
                text: 'No chats yet',
                icon: Icons.chat_bubble_outline,
              );
            }

            return Column(
              children: docs.map((d) {
                final data = d.data();
                final parts =
                    (data['participants'] as List?)?.cast<String>() ?? [];
                final otherUid = parts.firstWhere(
                  (x) => x != myUid,
                  orElse: () => '',
                );
                if (otherUid.isEmpty) return const SizedBox.shrink();

                final lastMsg = (data['last_message'] as String?) ?? '';
                final unreadFor =
                    (data['unread_for'] as List?)?.cast<String>() ?? [];
                final isUnread = unreadFor.contains(myUid);

                return _ChatTile(
                  chatId: d.id,
                  otherUid: otherUid,
                  lastMessage: lastMsg,
                  unread: isUnread,
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }
}

class _ChatTile extends StatelessWidget {
  final String chatId;
  final String otherUid;
  final String lastMessage;
  final bool unread;

  const _ChatTile({
    required this.chatId,
    required this.otherUid,
    required this.lastMessage,
    required this.unread,
  });

  @override
  Widget build(BuildContext context) {
    final myUid = FirebaseAuth.instance.currentUser?.uid ?? '';

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('chats')
          .doc(chatId)
          .snapshots(),
      builder: (context, chatSnap) {
        final chatData = chatSnap.data?.data() as Map<String, dynamic>? ?? {};
        final lastSenderId = chatData['last_sender_id']?.toString() ?? '';
        final lastMessageAt = chatData['last_message_at'] as Timestamp?;

        return Material(
          // ✅ NEW: Light purple background for unread
          color: unread ? const Color(0xFFF8F9FF) : Colors.white,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () async {
              // ✅ NEW: Auto-mark as read when opening
              if (unread) {
                await MessagingService.markChatRead(chatId);
              }

              if (context.mounted) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PrivateParkingChatScreen(
                      chatId: chatId,
                      otherUid: otherUid,
                    ),
                  ),
                );
              }
            },
            child: Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border.all(
                  color: unread
                      ? const Color(0xFF6366F1).withOpacity(0.2)
                      : const Color(0xFFE2E8F0),
                ),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                children: [
                  // Avatar with red dot
                  Stack(
                    children: [
                      StreamBuilder<DocumentSnapshot>(
                        stream: FirebaseFirestore.instance
                            .collection('users')
                            .doc(otherUid)
                            .snapshots(),
                        builder: (context, userSnap) {
                          final userData =
                              userSnap.data?.data() as Map<String, dynamic>? ??
                              {};
                          final userName =
                              userData['name']?.toString() ?? 'User';
                          final userPhoto = userData['photoURL']?.toString();

                          return CircleAvatar(
                            radius: 26,
                            backgroundColor: const Color(0xFF6366F1),
                            backgroundImage: userPhoto != null
                                ? NetworkImage(userPhoto)
                                : null,
                            child: userPhoto == null
                                ? Text(
                                    userName[0].toUpperCase(),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  )
                                : null,
                          );
                        },
                      ),
                      // ✅ NEW: Red dot for unread
                      if (unread)
                        Positioned(
                          right: 0,
                          top: 0,
                          child: Container(
                            width: 14,
                            height: 14,
                            decoration: BoxDecoration(
                              color: const Color(0xFFEF4444),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 14),
                  // Message content
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: StreamBuilder<DocumentSnapshot>(
                                stream: FirebaseFirestore.instance
                                    .collection('users')
                                    .doc(otherUid)
                                    .snapshots(),
                                builder: (context, userSnap) {
                                  final userData =
                                      userSnap.data?.data()
                                          as Map<String, dynamic>? ??
                                      {};
                                  final userName =
                                      userData['name']?.toString() ?? 'User';

                                  return Text(
                                    userName,
                                    style: TextStyle(
                                      fontSize: 16,
                                      // ✅ NEW: Bold if unread
                                      fontWeight: unread
                                          ? FontWeight.w900
                                          : FontWeight.w700,
                                      color: const Color(0xFF0F172A),
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  );
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            // Time
                            Text(
                              _formatTime(lastMessageAt),
                              style: TextStyle(
                                fontSize: 12,
                                // ✅ NEW: Bold if unread
                                fontWeight: unread
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: unread
                                    ? const Color(0xFF6366F1)
                                    : const Color(0xFF94A3B8),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            // "You:" prefix if current user sent
                            if (lastSenderId == myUid)
                              Text(
                                'You: ',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: unread
                                      ? FontWeight.w700
                                      : FontWeight.w600,
                                  color: const Color(0xFF64748B),
                                ),
                              ),
                            Expanded(
                              child: Text(
                                lastMessage.isEmpty ? 'Say hi 👋' : lastMessage,
                                style: TextStyle(
                                  fontSize: 14,
                                  // ✅ NEW: Bold if unread
                                  fontWeight: unread
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  color: unread
                                      ? const Color(0xFF0F172A)
                                      : const Color(0xFF64748B),
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Chevron
                  Icon(
                    Icons.chevron_right_rounded,
                    color: unread
                        ? const Color(0xFF6366F1)
                        : const Color(0xFFCBD5E1),
                    size: 24,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String _formatTime(Timestamp? timestamp) {
    if (timestamp == null) return '';

    final now = DateTime.now();
    final date = timestamp.toDate();
    final difference = now.difference(date);

    if (difference.inMinutes < 1) {
      return 'Now';
    } else if (difference.inHours < 1) {
      return '${difference.inMinutes}m';
    } else if (difference.inDays < 1) {
      return '${difference.inHours}h';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d';
    } else {
      return '${date.day}/${date.month}';
    }
  }
}

/* -------------------------------------------------------------------------- */
/*                                 UI PARTS                                   */
/* -------------------------------------------------------------------------- */

class _SectionTitle extends StatelessWidget {
  final String text;
  final int? badge;

  const _SectionTitle(this.text, {this.badge});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          text,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w900,
            color: Color(0xFF0F172A),
          ),
        ),
        if (badge != null && badge! > 0) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFFEF4444),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              badge!.toString(),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _EmptyCard extends StatelessWidget {
  final String text;
  final IconData icon;

  const _EmptyCard({required this.text, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF94A3B8)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Color(0xFF64748B),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: const Row(
        children: [
          SizedBox(
            height: 18,
            width: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 12),
          Text(
            'Loading...',
            style: TextStyle(
              color: Color(0xFF64748B),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _UserName extends StatelessWidget {
  final String uid;
  // your users collection uses "name"
  const _UserName({required this.uid});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .snapshots(),
      builder: (context, snap) {
        final name = (snap.data?.data()?['name'] as String?)?.trim();
        return Text(
          (name == null || name.isEmpty) ? 'User' : name,
          style: const TextStyle(fontWeight: FontWeight.w900),
        );
      },
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onPressed;

  const _ActionButton({
    required this.icon,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Icon(icon, color: color),
      ),
    );
  }
}

void _toast(BuildContext context, String text, {bool isError = false}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(text),
      backgroundColor: isError
          ? const Color(0xFFEF4444)
          : const Color(0xFF111827),
    ),
  );
}
