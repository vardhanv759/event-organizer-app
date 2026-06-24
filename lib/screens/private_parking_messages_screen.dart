import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../services/messaging_service.dart';
import '../utils/time_format.dart';
import '../utils/chat_avatar.dart';
import 'premium_chat_requests_screen.dart';
import 'private_parking_chat_screen.dart';

class PrivateParkingMessagesScreen extends StatefulWidget {
  const PrivateParkingMessagesScreen({super.key});

  @override
  State<PrivateParkingMessagesScreen> createState() =>
      _PrivateParkingMessagesScreenState();
}

class _PrivateParkingMessagesScreenState
    extends State<PrivateParkingMessagesScreen> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

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
          _RequestsBellButton(myUid: myUid),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: _SearchField(controller: _searchController),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                await Future.delayed(const Duration(milliseconds: 500));
              },
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                children: [
                  _RequestsBanner(myUid: myUid),
                  // Scoping the search query to its own ValueListenableBuilder
                  // (TextEditingController is itself a ValueNotifier) means
                  // only the chat list rebuilds while typing - the bell and
                  // banner above stay completely untouched.
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _searchController,
                    builder: (context, value, _) => _ChatsList(
                      myUid: myUid,
                      query: value.text.trim().toLowerCase(),
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

class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  const _SearchField({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          hintText: 'Search conversations',
          hintStyle: TextStyle(
            color: Colors.grey.shade500,
            fontWeight: FontWeight.w600,
          ),
          prefixIcon: const Icon(
            Icons.search_rounded,
            color: Color(0xFF94A3B8),
          ),
          suffixIcon: ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, _) {
              if (value.text.isEmpty) return const SizedBox.shrink();
              return IconButton(
                icon: const Icon(Icons.close_rounded, size: 18),
                onPressed: controller.clear,
              );
            },
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),
    );
  }
}

class _RequestsBellButton extends StatelessWidget {
  final String myUid;
  const _RequestsBellButton({required this.myUid});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: MessagingService.pendingRequestsCountStream(myUid),
      builder: (context, snap) {
        final count = snap.data ?? 0;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            IconButton(
              icon: const Icon(Icons.notifications_outlined),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const PremiumChatRequestsScreen(),
                ),
              ),
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

class _RequestsBanner extends StatelessWidget {
  final String myUid;
  const _RequestsBanner({required this.myUid});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: MessagingService.pendingRequestsCountStream(myUid),
      builder: (context, snap) {
        final count = snap.data ?? 0;
        if (count <= 0) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const PremiumChatRequestsScreen(),
              ),
            ),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF6366F1).withOpacity(0.3),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.mark_unread_chat_alt_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$count message ${count == 1 ? 'request' : 'requests'}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'Tap to review and respond',
                          style: TextStyle(
                            color: Colors.white70,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: Colors.white),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ChatsList extends StatelessWidget {
  final String myUid;
  final String query;
  const _ChatsList({required this.myUid, required this.query});

  @override
  Widget build(BuildContext context) {
    // Requires a composite index (participants array-contains + orderBy
    // last_message_at) - Firestore will surface a direct console link to
    // create it the first time this runs if it doesn't exist yet.
    final q = FirebaseFirestore.instance
        .collection('chats')
        .where('participants', arrayContains: myUid)
        .orderBy('last_message_at', descending: true);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: q.snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return const _EmptyState(
            icon: Icons.error_outline_rounded,
            title: 'Couldn\'t load chats',
            subtitle: 'Pull down to try again',
          );
        }
        if (snap.connectionState == ConnectionState.waiting) {
          return const _ChatListSkeleton();
        }

        // hidden_for is filtered client-side - Firestore can't combine an
        // array-contains (participants) with an array-not-contains
        // (hidden_for) in a single query, and chat lists are small enough
        // that this is cheap.
        final docs = (snap.data?.docs ?? []).where((d) {
          final hidden =
              (d.data()['hidden_for'] as List?)?.cast<String>() ?? [];
          return !hidden.contains(myUid);
        }).toList();

        if (docs.isEmpty) {
          return const _EmptyState(
            icon: Icons.chat_bubble_outline_rounded,
            title: 'No conversations yet',
            subtitle: 'Accepted chat requests will show up here',
          );
        }

        return Column(
          children: docs.map((d) {
            final data = d.data();
            final parts = (data['participants'] as List?)?.cast<String>() ?? [];
            final otherUid = parts.firstWhere(
              (x) => x != myUid,
              orElse: () => '',
            );
            if (otherUid.isEmpty) return const SizedBox.shrink();

            return _ChatRow(
              key: ValueKey(d.id),
              chatId: d.id,
              myUid: myUid,
              otherUid: otherUid,
              query: query,
            );
          }).toList(),
        );
      },
    );
  }
}

/// One row in the inbox. This is a StatefulWidget specifically so the two
/// Firestore streams it needs (the chat doc, and the other user's doc) are
/// created ONCE via `late final` and cached for the lifetime of this row's
/// state - not reconstructed on every rebuild. Constructing them inline in
/// a `build()` method would make every new message from ANY chat in the
/// list (which reorders the whole collection query and rebuilds every row)
/// also force every row to fully resubscribe its own listeners.
class _ChatRow extends StatefulWidget {
  final String chatId;
  final String myUid;
  final String otherUid;
  final String query;

  const _ChatRow({
    super.key,
    required this.chatId,
    required this.myUid,
    required this.otherUid,
    required this.query,
  });

  @override
  State<_ChatRow> createState() => _ChatRowState();
}

class _ChatRowState extends State<_ChatRow> {
  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _chatStream =
      FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.chatId)
          .snapshots();
  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _userStream =
      FirebaseFirestore.instance
          .collection('users')
          .doc(widget.otherUid)
          .snapshots();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _chatStream,
      builder: (context, chatSnap) {
        final chatData = chatSnap.data?.data();
        if (chatData == null) return const SizedBox.shrink();

        final lastMessage = (chatData['last_message'] as String?) ?? '';
        final lastSenderId = (chatData['last_sender_id'] as String?) ?? '';
        final lastMessageAt = chatData['last_message_at'] as Timestamp?;
        final unreadFor =
            (chatData['unread_for'] as List?)?.cast<String>() ?? [];
        final readAt = chatData['read_at'] as Map<String, dynamic>?;
        final isUnread = unreadFor.contains(widget.myUid);

        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: _userStream,
          builder: (context, userSnap) {
            final userData = userSnap.data?.data();
            final name = (userData?['name'] as String?)?.trim();
            final displayName = (name == null || name.isEmpty) ? 'User' : name;

            if (widget.query.isNotEmpty &&
                !displayName.toLowerCase().contains(widget.query)) {
              return const SizedBox.shrink();
            }

            final mineSent = lastSenderId == widget.myUid;
            final seen = mineSent
                ? MessagingService.hasRead(
                    readAt: readAt,
                    uid: widget.otherUid,
                    since: lastMessageAt,
                  )
                : false;

            return Dismissible(
              key: ValueKey('dismiss_${widget.chatId}'),
              direction: DismissDirection.endToStart,
              background: Container(
                margin: const EdgeInsets.only(bottom: 12),
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 24),
                decoration: BoxDecoration(
                  color: const Color(0xFF94A3B8),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(Icons.archive_outlined, color: Colors.white),
              ),
              confirmDismiss: (_) async {
                await MessagingService.hideChat(widget.chatId);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('Conversation archived'),
                      behavior: SnackBarBehavior.floating,
                      action: SnackBarAction(
                        label: 'Undo',
                        onPressed: () =>
                            MessagingService.unhideChat(widget.chatId),
                      ),
                    ),
                  );
                }
                return true;
              },
              child: _ChatTile(
                chatId: widget.chatId,
                otherUid: widget.otherUid,
                displayName: displayName,
                online: ChatAvatar.isOnline(userData),
                lastMessage: lastMessage,
                lastSenderId: lastSenderId,
                lastMessageAt: lastMessageAt,
                isUnread: isUnread,
                seen: seen,
                myUid: widget.myUid,
              ),
            );
          },
        );
      },
    );
  }
}

class _ChatTile extends StatelessWidget {
  final String chatId;
  final String otherUid;
  final String displayName;
  final String myUid;
  final bool online;
  final bool isUnread;
  final bool seen;
  final String lastMessage;
  final String lastSenderId;
  final Timestamp? lastMessageAt;

  const _ChatTile({
    required this.chatId,
    required this.otherUid,
    required this.displayName,
    required this.myUid,
    required this.online,
    required this.isUnread,
    required this.seen,
    required this.lastMessage,
    required this.lastSenderId,
    required this.lastMessageAt,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isUnread ? const Color(0xFFF8F9FF) : Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () async {
          if (isUnread) await MessagingService.markChatRead(chatId);
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
              color: isUnread
                  ? const Color(0xFF6366F1).withOpacity(0.2)
                  : const Color(0xFFE2E8F0),
            ),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: [
              ChatAvatar(uid: otherUid, size: 52, showOnlineDot: true),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: isUnread
                                  ? FontWeight.w900
                                  : FontWeight.w700,
                              color: const Color(0xFF0F172A),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          TimeFormat.relativeShort(lastMessageAt),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: isUnread
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: isUnread
                                ? const Color(0xFF6366F1)
                                : const Color(0xFF94A3B8),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (lastSenderId == myUid)
                          Text(
                            'You: ',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: isUnread
                                  ? FontWeight.w700
                                  : FontWeight.w600,
                              color: const Color(0xFF64748B),
                            ),
                          ),
                        Expanded(
                          child: Text(
                            lastMessage.isEmpty ? 'Say hi 👋' : lastMessage,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: isUnread
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: isUnread
                                  ? const Color(0xFF0F172A)
                                  : const Color(0xFF64748B),
                            ),
                          ),
                        ),
                        if (lastSenderId == myUid && lastMessage.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: Icon(
                              seen
                                  ? Icons.done_all_rounded
                                  : Icons.done_rounded,
                              size: 15,
                              color: seen
                                  ? const Color(0xFF6366F1)
                                  : const Color(0xFF94A3B8),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              if (isUnread)
                Container(
                  margin: const EdgeInsets.only(left: 8),
                  width: 10,
                  height: 10,
                  decoration: const BoxDecoration(
                    color: Color(0xFF6366F1),
                    shape: BoxShape.circle,
                  ),
                )
              else
                const Icon(
                  Icons.chevron_right_rounded,
                  color: Color(0xFFCBD5E1),
                  size: 22,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChatListSkeleton extends StatefulWidget {
  const _ChatListSkeleton();

  @override
  State<_ChatListSkeleton> createState() => _ChatListSkeletonState();
}

class _ChatListSkeletonState extends State<_ChatListSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final opacity = 0.4 + 0.3 * _c.value;
        return Column(
          children: List.generate(4, (i) {
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              height: 76,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(opacity),
                borderRadius: BorderRadius.circular(18),
              ),
            );
          }),
        );
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              color: Color(0xFFEEF2FF),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 40, color: const Color(0xFF6366F1)),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 16,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.grey.shade500,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}
