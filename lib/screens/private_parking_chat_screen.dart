import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/booking_service.dart';
import '../services/messaging_service.dart';
import '../utils/time_format.dart';
import '../utils/chat_avatar.dart';

class PrivateParkingChatScreen extends StatefulWidget {
  final String chatId;
  final String otherUid;

  const PrivateParkingChatScreen({
    super.key,
    required this.chatId,
    required this.otherUid,
  });

  @override
  State<PrivateParkingChatScreen> createState() =>
      _PrivateParkingChatScreenState();
}

enum _SendStatus { sending, failed }

class _PendingMessage {
  final String id;
  final String text;
  final DateTime createdAt;
  _SendStatus status;

  _PendingMessage({
    required this.id,
    required this.text,
    required this.createdAt,
    this.status = _SendStatus.sending,
  });
}

class _PrivateParkingChatScreenState extends State<PrivateParkingChatScreen>
    with SingleTickerProviderStateMixin {
  static const int _pageSize = 30;

  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  late AnimationController _fabAnimController;
  late Animation<double> _fabScaleAnimation;
  bool _showScrollToBottom = false;

  // The messages stream is cached and only ever rebuilt when the user
  // explicitly taps "load earlier messages" (which grows _liveLimit).
  // Constructing a fresh Query/.snapshots() inline inside build() would
  // make StreamBuilder treat it as a brand-new stream on every rebuild
  // (e.g. every time this screen's setState fires for an unrelated
  // reason, such as the scroll listener or the chat-doc listener below),
  // causing constant resubscription. Caching it here avoids that.
  late Stream<QuerySnapshot<Map<String, dynamic>>> _messagesStream;
  int _liveLimit = _pageSize;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _lastDocs = [];

  // Chat-level metadata (read receipts) is read once via a subscription
  // rather than a nested StreamBuilder, for the same reason as above.
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _chatDocSub;
  Map<String, dynamic>? _readAt;
  Timestamp? _lastMessageAt;
  String? _lastSenderId;

  Timer? _presenceTimer;
  Timer? _typingTimer;
  bool _isTypingLocally = false;

  final List<_PendingMessage> _pending = [];

  String get _myUid => FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    _rebuildMessagesStream();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      MessagingService.markChatRead(widget.chatId);
    });

    _chatDocSub = FirebaseFirestore.instance
        .collection('chats')
        .doc(widget.chatId)
        .snapshots()
        .listen((snap) {
          if (!mounted) return;
          final data = snap.data();
          setState(() {
            _readAt = data?['read_at'] as Map<String, dynamic>?;
            _lastMessageAt = data?['last_message_at'] as Timestamp?;
            _lastSenderId = data?['last_sender_id'] as String?;
          });
        });

    MessagingService.heartbeat();
    _presenceTimer = Timer.periodic(
      const Duration(seconds: 20),
      (_) => MessagingService.heartbeat(),
    );

    _controller.addListener(_onTextChanged);

    _fabAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _fabScaleAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fabAnimController, curve: Curves.easeOut),
    );

    _scrollController.addListener(_scrollListener);
  }

  void _rebuildMessagesStream() {
    _messagesStream = FirebaseFirestore.instance
        .collection('chats')
        .doc(widget.chatId)
        .collection('messages')
        .orderBy('created_at', descending: true)
        .limit(_liveLimit)
        .snapshots();
  }

  void _loadMore() {
    setState(() {
      _liveLimit += _pageSize;
      _rebuildMessagesStream();
    });
  }

  void _onTextChanged() {
    final hasText = _controller.text.trim().isNotEmpty;

    if (hasText && !_isTypingLocally) {
      _isTypingLocally = true;
      MessagingService.setTyping(widget.chatId, true);
    }

    _typingTimer?.cancel();
    if (hasText) {
      _typingTimer = Timer(const Duration(seconds: 3), () {
        if (_isTypingLocally) {
          _isTypingLocally = false;
          MessagingService.setTyping(widget.chatId, false);
        }
      });
    } else if (_isTypingLocally) {
      _isTypingLocally = false;
      MessagingService.setTyping(widget.chatId, false);
    }
  }

  void _scrollListener() {
    if (_scrollController.hasClients) {
      final showButton = _scrollController.offset > 200;
      if (showButton != _showScrollToBottom) {
        setState(() => _showScrollToBottom = showButton);
        if (showButton) {
          _fabAnimController.forward();
        } else {
          _fabAnimController.reverse();
        }
      }
    }
  }

  @override
  void dispose() {
    _chatDocSub?.cancel();
    _presenceTimer?.cancel();
    _typingTimer?.cancel();
    MessagingService.setTyping(widget.chatId, false);
    MessagingService.goOffline();
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    _scrollController.dispose();
    _fabAnimController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    _controller.clear();
    _typingTimer?.cancel();
    if (_isTypingLocally) {
      _isTypingLocally = false;
      MessagingService.setTyping(widget.chatId, false);
    }

    final id = MessagingService.newMessageId(widget.chatId);
    setState(() {
      _pending.insert(
        0,
        _PendingMessage(id: id, text: text, createdAt: DateTime.now()),
      );
    });
    _scrollToBottom();

    try {
      await MessagingService.sendMessage(
        chatId: widget.chatId,
        text: text,
        messageId: id,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        final match = _pending.where((p) => p.id == id);
        if (match.isNotEmpty) match.first.status = _SendStatus.failed;
      });
    }
  }

  Future<void> _retry(_PendingMessage p) async {
    setState(() => p.status = _SendStatus.sending);
    try {
      await MessagingService.sendMessage(
        chatId: widget.chatId,
        text: p.text,
        messageId: p.id,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => p.status = _SendStatus.failed);
    }
  }

  void _discard(_PendingMessage p) {
    setState(() => _pending.removeWhere((x) => x.id == p.id));
  }

  bool _shouldShowDateSeparator(
    int index,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    if (index == docs.length - 1) return true; // oldest loaded message

    final currentTimestamp = docs[index].data()['created_at'] as Timestamp?;
    final previousTimestamp =
        docs[index + 1].data()['created_at'] as Timestamp?;

    if (currentTimestamp == null || previousTimestamp == null) return false;

    final currentDate = currentTimestamp.toDate();
    final previousDate = previousTimestamp.toDate();

    return currentDate.day != previousDate.day ||
        currentDate.month != previousDate.month ||
        currentDate.year != previousDate.year;
  }

  @override
  Widget build(BuildContext context) {
    final myUid = _myUid;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FF),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        shadowColor: Colors.black.withOpacity(0.05),
        title: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('users')
              .doc(widget.otherUid)
              .snapshots(),
          builder: (context, snap) {
            final name = (snap.data?.data()?['name'] as String?)?.trim();
            return Row(
              children: [
                ChatAvatar(uid: widget.otherUid, size: 40, showOnlineDot: true),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        (name == null || name.isEmpty) ? 'Chat' : name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF0F172A),
                          fontSize: 16,
                        ),
                      ),
                      _PresenceSubtitle(
                        chatId: widget.chatId,
                        otherUid: widget.otherUid,
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
      body: Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: _messagesStream,
                  builder: (context, snap) {
                    if (snap.hasData) _lastDocs = snap.data!.docs;
                    final docs = _lastDocs;

                    final isInitialLoading =
                        snap.connectionState == ConnectionState.waiting &&
                        !snap.hasData &&
                        docs.isEmpty;

                    if (isInitialLoading) {
                      return const Center(
                        child: CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Color(0xFF6366F1),
                          ),
                        ),
                      );
                    }

                    final liveIds = docs.map((d) => d.id).toSet();

                    if (_pending.any((p) => liveIds.contains(p.id))) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (!mounted) return;
                        setState(
                          () => _pending.removeWhere(
                            (p) => liveIds.contains(p.id),
                          ),
                        );
                      });
                    }

                    final visiblePending = _pending
                        .where((p) => !liveIds.contains(p.id))
                        .toList();

                    if (docs.isEmpty && visiblePending.isEmpty) {
                      return _EmptyChat();
                    }

                    final hasMore = docs.length >= _liveLimit;
                    final showFooter = docs.isNotEmpty;

                    return ListView.builder(
                      controller: _scrollController,
                      reverse: true,
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                      itemCount:
                          visiblePending.length +
                          docs.length +
                          (showFooter ? 1 : 0),
                      itemBuilder: (_, i) {
                        if (i < visiblePending.length) {
                          final p = visiblePending[i];
                          return _MessageBubble(
                            text: p.text,
                            isMe: true,
                            localTime: p.createdAt,
                            failed: p.status == _SendStatus.failed,
                            sending: p.status == _SendStatus.sending,
                            onRetry: () => _retry(p),
                            onDiscard: () => _discard(p),
                          );
                        }

                        final docIndex = i - visiblePending.length;

                        if (docIndex == docs.length) {
                          if (hasMore) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Center(
                                child: TextButton(
                                  onPressed: _loadMore,
                                  child: const Text('Load earlier messages'),
                                ),
                              ),
                            );
                          }
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 16),
                            child: Center(
                              child: Text(
                                'This is the start of your conversation',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF94A3B8),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          );
                        }

                        final d = docs[docIndex].data();
                        final msgType = (d['type'] as String?) ?? 'text';
                        final sender = (d['sender_id'] as String?) ?? '';
                        final text = (d['text'] as String?) ?? '';
                        final isMe = sender.isNotEmpty && sender == myUid;
                        final timestamp = d['created_at'] as Timestamp?;

                        // Booking request messages are rendered as a
                        // distinct card, not a plain bubble. They appear
                        // in the message stream just like any other
                        // message, so every accepted booking request
                        // between these two users is permanently
                        // visible and scrollable - not just the first one.
                        if (msgType == 'booking_request') {
                          final showDateSeparator = _shouldShowDateSeparator(
                            docIndex,
                            docs,
                          );
                          return Column(
                            children: [
                              _BookingRequestCard(
                                data: d,
                                myUid: myUid,
                                timestamp: timestamp,
                              ),
                              if (showDateSeparator)
                                _DateSeparator(timestamp: timestamp),
                            ],
                          );
                        }

                        if (msgType == 'cancellation_request' ||
                            msgType == 'cancellation_confirmed' ||
                            msgType == 'cancellation_declined') {
                          final showDateSeparator = _shouldShowDateSeparator(
                            docIndex,
                            docs,
                          );
                          return Column(
                            children: [
                              _CancellationCard(
                                data: d,
                                myUid: myUid,
                                msgType: msgType,
                                timestamp: timestamp,
                                otherUid: widget.otherUid,
                              ),
                              if (showDateSeparator)
                                _DateSeparator(timestamp: timestamp),
                            ],
                          );
                        }

                        final isMostRecent =
                            visiblePending.isEmpty && docIndex == 0;
                        String? seenLabel;
                        if (isMostRecent && isMe) {
                          final seen = MessagingService.hasRead(
                            readAt: _readAt,
                            uid: widget.otherUid,
                            since: _lastMessageAt,
                          );
                          seenLabel = seen ? 'Seen' : 'Sent';
                        }

                        final showDateSeparator = _shouldShowDateSeparator(
                          docIndex,
                          docs,
                        );

                        return Column(
                          children: [
                            _MessageBubble(
                              text: text,
                              isMe: isMe,
                              timestamp: timestamp,
                              seenLabel: seenLabel,
                            ),
                            if (showDateSeparator)
                              _DateSeparator(timestamp: timestamp),
                          ],
                        );
                      },
                    );
                  },
                ),
              ),
              StreamBuilder<bool>(
                stream: MessagingService.typingStream(
                  widget.chatId,
                  widget.otherUid,
                ),
                builder: (context, snap) {
                  final show = snap.data == true;
                  return AnimatedSize(
                    duration: const Duration(milliseconds: 150),
                    child: show
                        ? const _TypingBubble()
                        : const SizedBox.shrink(),
                  );
                },
              ),
              _Composer(controller: _controller, onSend: _send),
            ],
          ),
          if (_showScrollToBottom)
            Positioned(
              bottom: 90,
              right: 16,
              child: ScaleTransition(
                scale: _fabScaleAnimation,
                child: FloatingActionButton.small(
                  onPressed: _scrollToBottom,
                  backgroundColor: const Color(0xFF6366F1),
                  elevation: 4,
                  child: const Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// App bar subtitle: "Typing…" overrides "Active now" overrides
/// "Active {x} ago".
class _PresenceSubtitle extends StatelessWidget {
  final String chatId;
  final String otherUid;
  const _PresenceSubtitle({required this.chatId, required this.otherUid});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<bool>(
      stream: MessagingService.typingStream(chatId, otherUid),
      builder: (context, typingSnap) {
        if (typingSnap.data == true) {
          return const Text(
            'Typing…',
            style: TextStyle(
              fontSize: 12,
              color: Color(0xFF6366F1),
              fontWeight: FontWeight.w700,
            ),
          );
        }

        return StreamBuilder<bool>(
          stream: MessagingService.onlineStatusStream(otherUid),
          builder: (context, onlineSnap) {
            if (onlineSnap.data == true) {
              return const Text(
                'Active now',
                style: TextStyle(
                  fontSize: 12,
                  color: Color(0xFF10B981),
                  fontWeight: FontWeight.w600,
                ),
              );
            }

            return StreamBuilder<Timestamp?>(
              stream: MessagingService.lastSeenStream(otherUid),
              builder: (context, lastSeenSnap) {
                final ts = lastSeenSnap.data;
                if (ts == null) return const SizedBox.shrink();
                return Text(
                  TimeFormat.activeAgo(ts),
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF94A3B8),
                    fontWeight: FontWeight.w600,
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

class _TypingBubble extends StatefulWidget {
  const _TypingBubble();

  @override
  State<_TypingBubble> createState() => _TypingBubbleState();
}

class _TypingBubbleState extends State<_TypingBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            return AnimatedBuilder(
              animation: _c,
              builder: (context, _) {
                final t = (_c.value + i * 0.2) % 1.0;
                final scale =
                    0.5 + 0.5 * (1 - (t - 0.5).abs() * 2).clamp(0.0, 1.0);
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Transform.scale(
                    scale: scale,
                    child: Container(
                      width: 7,
                      height: 7,
                      decoration: const BoxDecoration(
                        color: Color(0xFF94A3B8),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                );
              },
            );
          }),
        ),
      ),
    );
  }
}

class _EmptyChat extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFEEF2FF), Color(0xFFFDF4FF)],
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(
              Icons.chat_bubble_outline_rounded,
              size: 64,
              color: Color(0xFF6366F1),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'No messages yet',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Start the conversation!',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xFF64748B),
            ),
          ),
        ],
      ),
    );
  }
}

/// Pinned summary of the original "Request to Book" ask, shown at the
/// true start of the conversation. This is intentionally NOT a chat
/// bubble - it's denormalized data read straight off the chat document
/// (see MessagingService.acceptChatRequest), because writing it as a
/// `messages` document would require the accepter to create a message
/// with someone else's sender_id, which the security rules correctly
/// reject.
/// A booking request card rendered inline in the message stream.
/// Every time a provider accepts a "Request to Book", one of these
/// appears as a real, permanent, scrollable message — so both parties
/// always have a clear record of every booking request that was made
/// and accepted, even if there have been five of them.
///
/// Unlike regular bubbles (_MessageBubble), this is center-aligned and
/// full-width so it reads as a system/structural event in the
/// conversation rather than a one-sided message.
class _BookingRequestCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final String myUid;
  final Timestamp? timestamp;

  const _BookingRequestCard({
    required this.data,
    required this.myUid,
    required this.timestamp,
  });

  @override
  Widget build(BuildContext context) {
    final fromUid = (data['from_uid'] as String?) ?? '';
    final requestedAt = data['requested_at'] as Timestamp?;
    final durationHours = (data['duration_hours'] as num?)?.toInt() ?? 1;
    final note = (data['note'] as String?)?.trim();
    final contextTitle = (data['context_title'] as String?)?.trim();

    if (requestedAt == null) return const SizedBox.shrink();

    final start = requestedAt.toDate();
    final end = start.add(Duration(hours: durationHours));
    final isRequester = fromUid == myUid;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFEEF2FF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF6366F1).withOpacity(0.2),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFF6366F1).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.event_available_rounded,
                  size: 16,
                  color: Color(0xFF6366F1),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'BOOKING REQUEST ACCEPTED',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF6366F1),
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    if (fromUid.isNotEmpty)
                      isRequester
                          ? const Text(
                              'Your request was accepted',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF4338CA),
                              ),
                            )
                          : Row(
                              children: [
                                ChatUserName(
                                  uid: fromUid,
                                  fallback: 'Renter',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF4338CA),
                                  ),
                                ),
                                const Text(
                                  '\'s request accepted',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF4338CA),
                                  ),
                                ),
                              ],
                            ),
                  ],
                ),
              ),
              if (timestamp != null)
                Text(
                  TimeFormat.clock(timestamp!.toDate()),
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF94A3B8),
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1, color: Color(0xFFDDD6FE)),
          const SizedBox(height: 12),

          // Listing name
          if (contextTitle?.isNotEmpty == true) ...[
            Row(
              children: [
                const Icon(
                  Icons.local_parking_rounded,
                  size: 14,
                  color: Color(0xFF6366F1),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    contextTitle!,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],

          // Date & time range
          Row(
            children: [
              const Icon(
                Icons.access_time_rounded,
                size: 14,
                color: Color(0xFF6366F1),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${TimeFormat.date(start)}'
                  '  ${TimeFormat.clock(start)} – ${TimeFormat.clock(end)}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF334155),
                  ),
                ),
              ),
            ],
          ),

          // Optional note from the renter
          if (note?.isNotEmpty == true) ...[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.notes_rounded,
                  size: 14,
                  color: Color(0xFF94A3B8),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    note!,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF475569),
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Inline chat card for cancellation-related events. Three variants:
///
/// cancellation_request  — renter asking to cancel (within 24h window).
///   Provider sees Accept/Decline buttons directly in the chat thread.
///
/// cancellation_confirmed — booking has been cancelled (by either party,
///   or provider accepting the renter's request).
///
/// cancellation_declined — provider declined the renter's request;
///   booking still stands.
class _CancellationCard extends StatefulWidget {
  final Map<String, dynamic> data;
  final String myUid;
  final String msgType;
  final Timestamp? timestamp;
  final String otherUid;

  const _CancellationCard({
    required this.data,
    required this.myUid,
    required this.msgType,
    required this.timestamp,
    required this.otherUid,
  });

  @override
  State<_CancellationCard> createState() => _CancellationCardState();
}

class _CancellationCardState extends State<_CancellationCard> {
  bool _busy = false;

  Future<void> _decide(bool accept) async {
    final bookingId = widget.data['booking_id'] as String?;
    if (bookingId == null) return;
    setState(() => _busy = true);
    try {
      await BookingService.decideCancellationRequest(
        bookingId: bookingId,
        accept: accept,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final spaceTitle = (widget.data['space_title'] as String?)?.trim();
    final startTs = widget.data['start'] as Timestamp?;
    final endTs = widget.data['end'] as Timestamp?;
    final start = startTs?.toDate();
    final end = endTs?.toDate();

    // Sender of this message (the one who triggered the event)
    final senderId = (widget.data['sender_id'] as String?) ?? '';
    final isSenderMe = senderId == widget.myUid;

    // Whether I'm the provider (other party is the renter who requested)
    final isProvider = !isSenderMe && widget.msgType == 'cancellation_request';

    Color borderColor;
    Color bgColor;
    Color labelColor;
    IconData icon;
    String label;
    String sublabel;

    switch (widget.msgType) {
      case 'cancellation_request':
        borderColor = const Color(0xFFF59E0B).withOpacity(0.4);
        bgColor = const Color(0xFFFFFBEB);
        labelColor = const Color(0xFF92400E);
        icon = Icons.cancel_schedule_send_rounded;
        label = 'CANCELLATION REQUESTED';
        sublabel = isSenderMe
            ? 'You requested to cancel this booking'
            : 'Renter is requesting to cancel';
        break;
      case 'cancellation_confirmed':
        borderColor = const Color(0xFF94A3B8).withOpacity(0.4);
        bgColor = const Color(0xFFF8F9FF);
        labelColor = const Color(0xFF475569);
        icon = Icons.cancel_rounded;
        label = 'BOOKING CANCELLED';
        sublabel = isSenderMe
            ? 'You cancelled this booking'
            : 'Host cancelled this booking';
        break;
      case 'cancellation_declined':
      default:
        borderColor = const Color(0xFF6366F1).withOpacity(0.3);
        bgColor = const Color(0xFFEEF2FF);
        labelColor = const Color(0xFF4338CA);
        icon = Icons.event_available_rounded;
        label = 'CANCELLATION DECLINED';
        sublabel = 'Booking still confirmed';
        break;
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: labelColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 16, color: labelColor),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        color: labelColor,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      sublabel,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: labelColor,
                      ),
                    ),
                  ],
                ),
              ),
              if (widget.timestamp != null)
                Text(
                  TimeFormat.clock(widget.timestamp!.toDate()),
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF94A3B8),
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1, color: Color(0xFFE2E8F0)),
          const SizedBox(height: 12),

          // Slot details
          if (spaceTitle?.isNotEmpty == true) ...[
            Row(
              children: [
                const Icon(
                  Icons.local_parking_rounded,
                  size: 14,
                  color: Color(0xFF94A3B8),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    spaceTitle!,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          if (start != null)
            Row(
              children: [
                const Icon(
                  Icons.access_time_rounded,
                  size: 14,
                  color: Color(0xFF94A3B8),
                ),
                const SizedBox(width: 6),
                Text(
                  '${TimeFormat.date(start)}  '
                  '${TimeFormat.clock(start)}'
                  '${end != null ? ' – ${TimeFormat.clock(end)}' : ''}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF334155),
                  ),
                ),
              ],
            ),

          // Provider action buttons — only on an unresolved cancellation request
          if (isProvider && widget.msgType == 'cancellation_request') ...[
            const SizedBox(height: 14),
            const Divider(height: 1, color: Color(0xFFE2E8F0)),
            const SizedBox(height: 12),
            StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: widget.data['booking_id'] != null
                  ? FirebaseFirestore.instance
                        .collection('bookings')
                        .doc(widget.data['booking_id'] as String)
                        .snapshots()
                  : const Stream.empty(),
              builder: (context, bookingSnap) {
                final bookingStatus =
                    bookingSnap.data?.data()?['status'] as String?;
                // Only show buttons while the request is still pending
                if (bookingStatus != 'cancellation_requested') {
                  return Text(
                    bookingStatus == 'cancelled'
                        ? '✅ You approved this cancellation'
                        : bookingStatus == 'confirmed'
                        ? '❌ You declined this cancellation request'
                        : '',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey.shade600,
                    ),
                  );
                }
                if (_busy) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 4),
                      child: SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  );
                }
                return Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _decide(false),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF64748B),
                          side: const BorderSide(
                            color: Color(0xFFE2E8F0),
                            width: 1.4,
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: const Text(
                          'Decline',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => _decide(true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFEF4444),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: const Text(
                          'Approve cancellation',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}

class _DateSeparator extends StatelessWidget {
  final Timestamp? timestamp;
  const _DateSeparator({this.timestamp});

  @override
  Widget build(BuildContext context) {
    if (timestamp == null) return const SizedBox.shrink();
    final label = TimeFormat.dayLabel(timestamp!.toDate());

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          Expanded(child: Divider(color: Colors.grey.shade300, thickness: 1)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Colors.grey.shade600,
              ),
            ),
          ),
          Expanded(child: Divider(color: Colors.grey.shade300, thickness: 1)),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final String text;
  final bool isMe;
  final Timestamp? timestamp;
  final DateTime? localTime;
  final bool failed;
  final bool sending;
  final VoidCallback? onRetry;
  final VoidCallback? onDiscard;
  final String? seenLabel;

  const _MessageBubble({
    required this.text,
    required this.isMe,
    this.timestamp,
    this.localTime,
    this.failed = false,
    this.sending = false,
    this.onRetry,
    this.onDiscard,
    this.seenLabel,
  });

  @override
  Widget build(BuildContext context) {
    final dt = timestamp?.toDate() ?? localTime;
    final time = dt != null ? TimeFormat.clock(dt) : '';

    final bubble = Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.75,
      ),
      decoration: BoxDecoration(
        gradient: isMe
            ? const LinearGradient(
                colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
        color: isMe ? null : Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(20),
          topRight: const Radius.circular(20),
          bottomLeft: Radius.circular(isMe ? 20 : 4),
          bottomRight: Radius.circular(isMe ? 4 : 20),
        ),
        border: failed
            ? Border.all(color: const Color(0xFFEF4444), width: 1.4)
            : null,
        boxShadow: [
          BoxShadow(
            color: isMe
                ? const Color(0xFF6366F1).withOpacity(failed ? 0.0 : 0.3)
                : Colors.black.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: isMe
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          Text(
            text,
            style: TextStyle(
              color: isMe ? Colors.white : const Color(0xFF0F172A),
              fontWeight: FontWeight.w600,
              fontSize: 15,
              height: 1.4,
            ),
          ),
          if (time.isNotEmpty || sending || failed) ...[
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (sending) ...[
                  SizedBox(
                    width: 10,
                    height: 10,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.6,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        isMe ? Colors.white70 : const Color(0xFF94A3B8),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                if (failed) ...[
                  const Icon(
                    Icons.error_outline_rounded,
                    size: 13,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 4),
                ],
                Text(
                  failed ? 'Failed to send · tap to retry' : time,
                  style: TextStyle(
                    color: isMe
                        ? Colors.white.withOpacity(0.7)
                        : const Color(0xFF94A3B8),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );

    final content = failed
        ? GestureDetector(onTap: onRetry, onLongPress: onDiscard, child: bubble)
        : bubble;

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: isMe
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          content,
          Padding(
            padding: const EdgeInsets.only(right: 4, bottom: 10, top: 2),
            child: seenLabel != null
                ? Text(
                    seenLabel!,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF94A3B8),
                    ),
                  )
                : const SizedBox(height: 0),
          ),
        ],
      ),
    );
  }
}

class _Composer extends StatefulWidget {
  final TextEditingController controller;
  final VoidCallback onSend;

  const _Composer({required this.controller, required this.onSend});

  @override
  State<_Composer> createState() => _ComposerState();
}

class _ComposerState extends State<_Composer> {
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_textListener);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_textListener);
    super.dispose();
  }

  void _textListener() {
    final hasText = widget.controller.text.trim().isNotEmpty;
    if (hasText != _hasText) {
      setState(() => _hasText = hasText);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: _hasText
                          ? const Color(0xFF6366F1).withOpacity(0.3)
                          : Colors.transparent,
                    ),
                  ),
                  child: TextField(
                    controller: widget.controller,
                    minLines: 1,
                    maxLines: 5,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      hintText: 'Type a message...',
                      hintStyle: TextStyle(
                        color: Colors.grey.shade500,
                        fontWeight: FontWeight.w600,
                      ),
                      filled: false,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                    ),
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Container(
                decoration: BoxDecoration(
                  gradient: _hasText
                      ? const LinearGradient(
                          colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        )
                      : null,
                  color: _hasText ? null : const Color(0xFFE2E8F0),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: _hasText
                      ? [
                          BoxShadow(
                            color: const Color(0xFF6366F1).withOpacity(0.4),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ]
                      : null,
                ),
                child: IconButton(
                  onPressed: _hasText ? widget.onSend : null,
                  icon: Icon(
                    Icons.send_rounded,
                    color: _hasText ? Colors.white : Colors.grey.shade400,
                  ),
                  padding: const EdgeInsets.all(12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
