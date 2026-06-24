import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../services/messaging_service.dart';
import '../utils/time_format.dart';
import '../utils/chat_avatar.dart';
import 'private_parking_chat_screen.dart';

/// Message requests, split into two tabs:
///  - Incoming: pending requests sent TO me (accept opens the chat).
///  - Sent: every request I've sent, with its current status; pending
///    ones can be cancelled.
///
/// Every status change here goes through [MessagingService] - this used
/// to duplicate the accept/reject logic with its own direct Firestore
/// writes, which meant the two code paths could drift out of sync. Now
/// there is exactly one place that knows how to accept a request.
class PremiumChatRequestsScreen extends StatefulWidget {
  const PremiumChatRequestsScreen({super.key});

  @override
  State<PremiumChatRequestsScreen> createState() =>
      _PremiumChatRequestsScreenState();
}

class _PremiumChatRequestsScreenState extends State<PremiumChatRequestsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController = TabController(
    length: 2,
    vsync: this,
  );

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final myUid = FirebaseAuth.instance.currentUser?.uid ?? '';

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FF),
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverAppBar(
            expandedHeight: 170,
            pinned: true,
            backgroundColor: const Color(0xFF6366F1),
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: const Padding(
                  padding: EdgeInsets.fromLTRB(20, 70, 20, 20),
                  child: Align(
                    alignment: Alignment.bottomLeft,
                    child: Text(
                      'Message requests',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.4,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          SliverPersistentHeader(
            pinned: true,
            delegate: _StickyTabBarDelegate(
              TabBar(
                controller: _tabController,
                labelColor: const Color(0xFF6366F1),
                unselectedLabelColor: const Color(0xFF94A3B8),
                indicatorColor: const Color(0xFF6366F1),
                indicatorWeight: 3,
                labelStyle: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                ),
                unselectedLabelStyle: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
                tabs: const [
                  Tab(text: 'Incoming'),
                  Tab(text: 'Sent'),
                ],
              ),
            ),
          ),
          SliverFillRemaining(
            child: TabBarView(
              controller: _tabController,
              children: [
                _IncomingTab(myUid: myUid),
                _SentTab(myUid: myUid),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StickyTabBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;
  _StickyTabBarDelegate(this.tabBar);

  @override
  double get minExtent => tabBar.preferredSize.height;
  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(color: Colors.white, child: tabBar);
  }

  @override
  bool shouldRebuild(_StickyTabBarDelegate oldDelegate) => false;
}

/* -------------------------------------------------------------------------- */
/*                                  INCOMING                                  */
/* -------------------------------------------------------------------------- */

class _IncomingTab extends StatelessWidget {
  final String myUid;
  const _IncomingTab({required this.myUid});

  @override
  Widget build(BuildContext context) {
    final q = FirebaseFirestore.instance
        .collection('chat_requests')
        .where('to_uid', isEqualTo: myUid)
        .where('status', isEqualTo: 'pending')
        .orderBy('created_at', descending: true);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: q.snapshots(),
      builder: (context, snap) {
        if (snap.hasError) return const _RequestsError();
        if (snap.connectionState == ConnectionState.waiting) {
          return const _RequestsLoading();
        }

        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) {
          return const _RequestsEmpty(
            icon: Icons.inbox_rounded,
            title: 'No pending requests',
            subtitle: 'New requests will appear here',
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(20),
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final d = docs[i];
            final data = d.data();
            final fromUid = (data['from_uid'] as String?) ?? '';
            if (fromUid.isEmpty) return const SizedBox.shrink();
            return _IncomingRequestCard(
              requestId: d.id,
              fromUid: fromUid,
              createdAt: data['created_at'] as Timestamp?,
              requestedAt: data['requested_at'] as Timestamp?,
              durationHours: (data['requested_duration_hours'] as num?)
                  ?.toInt(),
              note: data['note'] as String?,
              contextTitle: data['context_title'] as String?,
              contextRefId: data['context_ref_id'] as String?,
            );
          },
        );
      },
    );
  }
}

class _IncomingRequestCard extends StatefulWidget {
  final String requestId;
  final String fromUid;
  final Timestamp? createdAt;
  final Timestamp? requestedAt;
  final int? durationHours;
  final String? note;
  final String? contextTitle;
  final String? contextRefId;

  const _IncomingRequestCard({
    required this.requestId,
    required this.fromUid,
    required this.createdAt,
    this.requestedAt,
    this.durationHours,
    this.note,
    this.contextTitle,
    this.contextRefId,
  });

  @override
  State<_IncomingRequestCard> createState() => _IncomingRequestCardState();
}

class _IncomingRequestCardState extends State<_IncomingRequestCard> {
  bool _busy = false;

  Future<void> _accept() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final chatId = await MessagingService.acceptChatRequest(widget.requestId);
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => PrivateParkingChatScreen(
            chatId: chatId,
            otherUid: widget.fromUid,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _toast(context, 'Couldn\'t accept: $e', isError: true);
    }
  }

  Future<void> _reject() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await MessagingService.rejectChatRequest(widget.requestId);
      if (!mounted) return;
      _toast(context, 'Request declined');
    } catch (e) {
      if (!mounted) return;
      _toast(context, 'Couldn\'t decline: $e', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ChatAvatar(uid: widget.fromUid, size: 52, showOnlineDot: true),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ChatUserName(
                      uid: widget.fromUid,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.contextTitle?.trim().isNotEmpty == true
                          ? 'Wants to book "${widget.contextTitle}"'
                          : 'Wants to chat about parking',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      TimeFormat.relativeLong(widget.createdAt),
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade400,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (widget.requestedAt != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFEEF2FF),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.event_available_rounded,
                    size: 18,
                    color: Color(0xFF6366F1),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Requested for ${TimeFormat.date(widget.requestedAt!.toDate())} '
                          'from ${TimeFormat.clock(widget.requestedAt!.toDate())} '
                          'to ${TimeFormat.clock(widget.requestedAt!.toDate().add(Duration(hours: widget.durationHours ?? 1)))}',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF312E81),
                          ),
                        ),
                        if ((widget.note ?? '').trim().isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            widget.note!.trim(),
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF4338CA),
                              height: 1.3,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (widget.contextRefId != null)
              FutureBuilder<List<Map<String, dynamic>>>(
                future: MessagingService.findOverlappingRequests(
                  contextRefId: widget.contextRefId!,
                  requestedAt: widget.requestedAt!.toDate(),
                  durationHours: widget.durationHours ?? 1,
                  excludeRequestId: widget.requestId,
                ),
                builder: (context, snap) {
                  final overlaps = snap.data ?? [];
                  if (overlaps.isEmpty) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.info_outline_rounded,
                          size: 14,
                          color: Color(0xFFB45309),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '${overlaps.length} other ${overlaps.length == 1 ? 'request' : 'requests'} '
                            'overlap this time slot',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFFB45309),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
          ],
          const SizedBox(height: 16),
          if (_busy)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: SizedBox(
                  height: 22,
                  width: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _reject,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFEF4444),
                      side: const BorderSide(
                        color: Color(0xFFEF4444),
                        width: 1.6,
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text(
                      'Decline',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: _accept,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text(
                      'Accept & chat',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/* -------------------------------------------------------------------------- */
/*                                    SENT                                    */
/* -------------------------------------------------------------------------- */

class _SentTab extends StatelessWidget {
  final String myUid;
  const _SentTab({required this.myUid});

  @override
  Widget build(BuildContext context) {
    final q = FirebaseFirestore.instance
        .collection('chat_requests')
        .where('from_uid', isEqualTo: myUid)
        .orderBy('created_at', descending: true);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: q.snapshots(),
      builder: (context, snap) {
        if (snap.hasError) return const _RequestsError();
        if (snap.connectionState == ConnectionState.waiting) {
          return const _RequestsLoading();
        }

        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) {
          return const _RequestsEmpty(
            icon: Icons.outbox_rounded,
            title: 'No sent requests',
            subtitle: 'Requests you send will appear here',
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(20),
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final d = docs[i];
            final data = d.data();
            final toUid = (data['to_uid'] as String?) ?? '';
            if (toUid.isEmpty) return const SizedBox.shrink();
            return _SentRequestCard(
              requestId: d.id,
              toUid: toUid,
              status: (data['status'] as String?) ?? 'pending',
              createdAt: data['created_at'] as Timestamp?,
              updatedAt: data['updated_at'] as Timestamp?,
              requestedAt: data['requested_at'] as Timestamp?,
              durationHours: (data['requested_duration_hours'] as num?)
                  ?.toInt(),
              contextTitle: data['context_title'] as String?,
            );
          },
        );
      },
    );
  }
}

class _SentRequestCard extends StatefulWidget {
  final String requestId;
  final String toUid;
  final String status;
  final Timestamp? createdAt;
  final Timestamp? updatedAt;
  final Timestamp? requestedAt;
  final int? durationHours;
  final String? contextTitle;

  const _SentRequestCard({
    required this.requestId,
    required this.toUid,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.requestedAt,
    this.durationHours,
    this.contextTitle,
  });

  @override
  State<_SentRequestCard> createState() => _SentRequestCardState();
}

class _SentRequestCardState extends State<_SentRequestCard> {
  bool _busy = false;

  Future<void> _cancel() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await MessagingService.cancelChatRequest(widget.requestId);
      if (!mounted) return;
      _toast(context, 'Request cancelled');
    } catch (e) {
      if (!mounted) return;
      _toast(context, 'Couldn\'t cancel: $e', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isPending = widget.status == 'pending';

    Color statusColor;
    IconData statusIcon;
    String statusText;

    switch (widget.status) {
      case 'accepted':
        statusColor = const Color(0xFF10B981);
        statusIcon = Icons.check_circle_rounded;
        statusText = 'Accepted';
        break;
      case 'rejected':
        statusColor = const Color(0xFFEF4444);
        statusIcon = Icons.cancel_rounded;
        statusText = 'Declined';
        break;
      case 'cancelled':
        statusColor = const Color(0xFF64748B);
        statusIcon = Icons.block_rounded;
        statusText = 'Cancelled';
        break;
      default:
        statusColor = const Color(0xFFF59E0B);
        statusIcon = Icons.schedule_rounded;
        statusText = 'Pending';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          ChatAvatar(uid: widget.toUid, size: 46, showOnlineDot: true),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ChatUserName(
                  uid: widget.toUid,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (widget.contextTitle?.trim().isNotEmpty == true) ...[
                  const SizedBox(height: 2),
                  Text(
                    widget.contextTitle!.trim(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
                if (widget.requestedAt != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    'For ${TimeFormat.date(widget.requestedAt!.toDate())} '
                    '${TimeFormat.clock(widget.requestedAt!.toDate())}–'
                    '${TimeFormat.clock(widget.requestedAt!.toDate().add(Duration(hours: widget.durationHours ?? 1)))}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF6366F1),
                    ),
                  ),
                ],
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(statusIcon, size: 14, color: statusColor),
                    const SizedBox(width: 4),
                    Text(
                      statusText,
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      TimeFormat.relativeShort(
                        isPending ? widget.createdAt : widget.updatedAt,
                      ),
                      style: TextStyle(
                        color: Colors.grey.shade400,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (isPending)
            _busy
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : TextButton(onPressed: _cancel, child: const Text('Cancel')),
        ],
      ),
    );
  }
}

/* -------------------------------------------------------------------------- */
/*                                 SHARED UI                                  */
/* -------------------------------------------------------------------------- */

class _RequestsLoading extends StatelessWidget {
  const _RequestsLoading();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: CircularProgressIndicator(
        valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF6366F1)),
      ),
    );
  }
}

class _RequestsError extends StatelessWidget {
  const _RequestsError();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.error_outline_rounded,
            size: 64,
            color: Colors.red.shade400,
          ),
          const SizedBox(height: 16),
          Text(
            'Error loading requests',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }
}

class _RequestsEmpty extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _RequestsEmpty({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFFF8F9FF),
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFFE2E8F0), width: 2),
            ),
            child: Icon(icon, size: 64, color: const Color(0xFF94A3B8)),
          ),
          const SizedBox(height: 20),
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade500,
            ),
          ),
        ],
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
