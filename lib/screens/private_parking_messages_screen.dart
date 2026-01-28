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
        // Notification badge in AppBar
        actions: [
          _NotificationBadge(uid: myUid),
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          // Trigger refresh
          await Future.delayed(const Duration(milliseconds: 500));
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
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
              onPressed: () {
                // Could navigate to a dedicated notifications screen
              },
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
      _toast(context, 'Request rejected', isError: false);
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
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF6366F1).withOpacity(0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Icon(
              Icons.mark_unread_chat_alt_rounded,
              color: Colors.white,
              size: 24,
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
                      color: const Color(0xFFEF4444),
                      onPressed: _reject,
                    ),
                    const SizedBox(width: 8),
                    _ActionButton(
                      icon: Icons.check_rounded,
                      color: const Color(0xFF10B981),
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

class _OutgoingRequestTile extends StatefulWidget {
  final String requestId;
  final String toUid;

  const _OutgoingRequestTile({required this.requestId, required this.toUid});

  @override
  State<_OutgoingRequestTile> createState() => _OutgoingRequestTileState();
}

class _OutgoingRequestTileState extends State<_OutgoingRequestTile>
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

  Future<void> _cancel() async {
    if (_busy) return;
    _animController.forward().then((_) => _animController.reverse());
    setState(() => _busy = true);
    try {
      await MessagingService.cancelChatRequest(widget.requestId);
      if (!mounted) return;
      _toast(context, 'Request cancelled', isError: false);
    } catch (e) {
      if (mounted) _toast(context, 'Cancel failed: $e', isError: true);
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
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
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
              color: const Color(0xFFEEF2FF),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.call_made_rounded,
              color: Color(0xFF6366F1),
              size: 24,
            ),
          ),
          title: _UserName(uid: widget.toUid),
          subtitle: const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text(
              'Request pending',
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
              : TextButton.icon(
                  onPressed: _cancel,
                  icon: const Icon(Icons.cancel_outlined, size: 18),
                  label: const Text(
                    'Cancel',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFFEF4444),
                  ),
                ),
        ),
      ),
    );
  }
}

/* -------------------------------------------------------------------------- */
/*                                CHATS SECTION                               */
/* -------------------------------------------------------------------------- */

class _ChatsSection extends StatelessWidget {
  final String myUid;
  const _ChatsSection({required this.myUid});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        StreamBuilder<int>(
          stream: MessagingService.unreadChatsCountStream(myUid),
          builder: (context, snapshot) {
            final count = snapshot.data ?? 0;
            return _SectionTitle('Active Chats', badge: count);
          },
        ),
        const SizedBox(height: 12),
        _ChatsList(myUid: myUid),
      ],
    );
  }
}

class _ChatsList extends StatelessWidget {
  final String myUid;
  const _ChatsList({required this.myUid});

  @override
  Widget build(BuildContext context) {
    final q = FirebaseFirestore.instance
        .collection('chats')
        .where('participants', arrayContains: myUid);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
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
            text: 'No active chats yet',
            icon: Icons.chat_bubble_outline,
          );
        }

        return Column(
          children: docs.map((d) {
            final data = d.data();
            final participants =
                (data['participants'] as List?)?.cast<String>() ?? <String>[];
            if (!participants.contains(myUid) || participants.length < 2) {
              return const SizedBox.shrink();
            }
            final otherUid = participants.firstWhere(
              (u) => u != myUid,
              orElse: () => '',
            );
            if (otherUid.isEmpty) return const SizedBox.shrink();

            final last = (data['last_message'] as String?)?.trim() ?? '';
            final unreadFor =
                (data['unread_for'] as List?)?.cast<String>() ?? <String>[];
            final isUnread = unreadFor.contains(myUid);

            return _ChatTile(
              chatId: d.id,
              otherUid: otherUid,
              lastMessage: last,
              isUnread: isUnread,
            );
          }).toList(),
        );
      },
    );
  }
}

class _ChatTile extends StatelessWidget {
  final String chatId;
  final String otherUid;
  final String lastMessage;
  final bool isUnread;

  const _ChatTile({
    required this.chatId,
    required this.otherUid,
    required this.lastMessage,
    required this.isUnread,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        gradient: isUnread
            ? const LinearGradient(
                colors: [Color(0xFFDCFCE7), Color(0xFFD1FAE5)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
        color: isUnread ? null : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isUnread
              ? const Color(0xFF10B981).withOpacity(0.3)
              : const Color(0xFFE2E8F0),
          width: isUnread ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: isUnread
                ? const Color(0xFF10B981).withOpacity(0.1)
                : Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              height: 50,
              width: 50,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isUnread
                      ? [const Color(0xFF10B981), const Color(0xFF059669)]
                      : [const Color(0xFF6366F1), const Color(0xFF8B5CF6)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color:
                        (isUnread
                                ? const Color(0xFF10B981)
                                : const Color(0xFF6366F1))
                            .withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Icon(
                Icons.chat_bubble_rounded,
                color: Colors.white,
                size: 24,
              ),
            ),
            if (isUnread)
              Positioned(
                right: -4,
                top: -4,
                child: Container(
                  height: 14,
                  width: 14,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                ),
              ),
          ],
        ),
        title: _UserName(uid: otherUid),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            lastMessage.isEmpty ? 'Tap to open chat' : lastMessage,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: isUnread ? FontWeight.w700 : FontWeight.w600,
              color: isUnread
                  ? const Color(0xFF0F172A)
                  : const Color(0xFF64748B),
            ),
          ),
        ),
        trailing: Icon(
          Icons.arrow_forward_ios_rounded,
          size: 16,
          color: isUnread ? const Color(0xFF10B981) : const Color(0xFF94A3B8),
        ),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) =>
                  PrivateParkingChatScreen(chatId: chatId, otherUid: otherUid),
            ),
          );
        },
      ),
    );
  }
}

/* -------------------------------------------------------------------------- */
/*                                   HELPERS                                  */
/* -------------------------------------------------------------------------- */

class _UserName extends StatelessWidget {
  final String uid;
  const _UserName({required this.uid});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData || !(snap.data?.exists ?? false)) {
          return Text(
            uid,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: Color(0xFF0F172A),
            ),
          );
        }
        final data = snap.data!.data() ?? <String, dynamic>{};
        final name = (data['name'] as String?)?.trim();
        return Text(
          (name == null || name.isEmpty) ? uid : name,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            color: Color(0xFF0F172A),
          ),
        );
      },
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  final int? badge;
  const _SectionTitle(this.text, {this.badge});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: Color(0xFF0F172A),
            ),
          ),
        ),
        if (badge != null && badge! > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFEF4444), Color(0xFFDC2626)],
              ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFEF4444).withOpacity(0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Text(
              badge! > 99 ? '99+' : badge.toString(),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
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
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 48, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          Text(
            text,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade500,
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
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: const Center(child: CircularProgressIndicator()),
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
    return Container(
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: IconButton(
        icon: Icon(icon, size: 20),
        color: color,
        onPressed: onPressed,
        padding: const EdgeInsets.all(8),
        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      ),
    );
  }
}

void _toast(BuildContext context, String msg, {bool isError = false}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(msg),
      backgroundColor: isError
          ? const Color(0xFFEF4444)
          : const Color(0xFF10B981),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );
}
