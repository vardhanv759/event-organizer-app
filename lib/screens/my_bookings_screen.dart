import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/booking_service.dart';
import '../services/messaging_service.dart';
import '../services/review_service.dart';
import '../utils/time_format.dart';
import '../utils/chat_avatar.dart';
import 'private_parking_chat_screen.dart';

/// My Bookings - the renter's view of every booking they've made,
/// driven entirely by the `bookings` collection (see BookingService for
/// the full lifecycle). This used to read the old Stripe-era
/// `parking_bookings` collection, which nothing writes to anymore now
/// that booking happens through Request-to-Book + accept instead of
/// payment.
class MyBookingsScreen extends StatefulWidget {
  const MyBookingsScreen({super.key});

  @override
  State<MyBookingsScreen> createState() => _MyBookingsScreenState();
}

class _MyBookingsScreenState extends State<MyBookingsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    // NOTE: this used to be length: 2 while the TabBarView below had 3
    // children ('upcoming', 'past', 'all') - a mismatch that throws a
    // Flutter assertion at runtime. Fixed to 2, matching the 2 tabs and
    // 2 views actually present.
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
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
              Icon(
                Icons.lock_outline_rounded,
                size: 80,
                color: Colors.grey.shade400,
              ),
              const SizedBox(height: 20),
              const Text(
                'Please sign in to view bookings',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF64748B),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FF),
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverAppBar(
            expandedHeight: 214,
            floating: false,
            pinned: true,
            backgroundColor: const Color(0xFF6366F1),
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Color(0xFF6366F1),
                      Color(0xFF8B5CF6),
                      Color(0xFFEC4899),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Stack(
                  children: [
                    Positioned(
                      right: -50,
                      top: -50,
                      child: Container(
                        width: 200,
                        height: 200,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withOpacity(0.1),
                        ),
                      ),
                    ),
                    Positioned(
                      left: -30,
                      bottom: -30,
                      child: Container(
                        width: 150,
                        height: 150,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withOpacity(0.08),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 80, 20, 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.3),
                                width: 2,
                              ),
                            ),
                            child: const Icon(
                              Icons.receipt_long_rounded,
                              color: Colors.white,
                              size: 32,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'My Bookings',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 32,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.5,
                              shadows: [
                                Shadow(
                                  color: Colors.black26,
                                  blurRadius: 10,
                                  offset: Offset(0, 4),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
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
                  Tab(text: 'Upcoming'),
                  Tab(text: 'Past'),
                ],
              ),
            ),
          ),
          SliverFillRemaining(
            child: TabBarView(
              controller: _tabController,
              children: [
                _BookingsListView(userId: user.uid, filter: 'upcoming'),
                _BookingsListView(userId: user.uid, filter: 'past'),
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

/// 'upcoming' = booking's start time is still ahead, regardless of
/// status, so a cancelled-but-still-future booking is still visible
/// here (with a Cancelled badge) rather than silently disappearing.
/// 'past' = start time has already passed.
class _BookingsListView extends StatelessWidget {
  final String userId;
  final String filter;

  const _BookingsListView({required this.userId, required this.filter});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: BookingService.myBookingsAsRenter(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF6366F1)),
            ),
          );
        }

        if (snapshot.hasError) {
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
                  'Error loading bookings',
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

        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) return _buildEmptyState();

        final now = DateTime.now();
        final filtered = docs.where((doc) {
          final data = doc.data();
          final start = (data['start'] as Timestamp?)?.toDate();
          final status = (data['status'] as String?) ?? 'confirmed';
          if (start == null) return false;
          // Cancelled bookings always appear in Past regardless of their
          // scheduled start time. A booking cancelled before it started
          // is still a past event from the renter's perspective — showing
          // it in Upcoming would be confusing since the slot is gone.
          if (status == 'cancelled') return filter == 'past';
          return filter == 'upcoming'
              ? start.isAfter(now)
              : !start.isAfter(now);
        }).toList();

        if (filtered.isEmpty) return _buildEmptyState();

        return ListView.builder(
          padding: const EdgeInsets.all(20),
          itemCount: filtered.length,
          itemBuilder: (context, index) {
            return _BookingCard(
              booking: filtered[index].data(),
              bookingId: filtered[index].id,
              myUid: userId,
            );
          },
        );
      },
    );
  }

  Widget _buildEmptyState() {
    final isUpcoming = filter == 'upcoming';
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
            child: Icon(
              isUpcoming ? Icons.event_busy_rounded : Icons.history_rounded,
              size: 64,
              color: const Color(0xFF94A3B8),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            isUpcoming ? 'No upcoming bookings' : 'No past bookings',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            isUpcoming
                ? 'Request to book a parking space to get started'
                : 'Your booking history will appear here',
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

class _StatusInfo {
  final Color color;
  final IconData icon;
  final String label;
  const _StatusInfo(this.color, this.icon, this.label);
}

_StatusInfo _statusInfoFor(String status) {
  switch (status) {
    case 'confirmed':
      return const _StatusInfo(
        Color(0xFF10B981),
        Icons.check_circle_rounded,
        'Confirmed',
      );
    case 'cancellation_requested':
      return const _StatusInfo(
        Color(0xFFF59E0B),
        Icons.schedule_rounded,
        'Cancellation requested',
      );
    case 'cancelled':
      return const _StatusInfo(
        Color(0xFF94A3B8),
        Icons.cancel_rounded,
        'Cancelled',
      );
    case 'completed':
      return const _StatusInfo(
        Color(0xFF6366F1),
        Icons.task_alt_rounded,
        'Completed',
      );
    case 'no_show':
      return const _StatusInfo(
        Color(0xFFEF4444),
        Icons.report_problem_rounded,
        'No-show recorded',
      );
    case 'completed_unconfirmed':
      return const _StatusInfo(
        Color(0xFF8B5CF6),
        Icons.check_circle_outline_rounded,
        'Completed',
      );
    default:
      return _StatusInfo(
        Colors.grey.shade500,
        Icons.help_outline_rounded,
        status,
      );
  }
}

class _BookingCard extends StatefulWidget {
  final Map<String, dynamic> booking;
  final String bookingId;
  final String myUid;

  const _BookingCard({
    required this.booking,
    required this.bookingId,
    required this.myUid,
  });

  @override
  State<_BookingCard> createState() => _BookingCardState();
}

class _BookingCardState extends State<_BookingCard> {
  bool _busy = false;

  Future<void> _cancel() async {
    final start = (widget.booking['start'] as Timestamp?)?.toDate();
    if (start == null) return;

    final isLate = BookingService.isLate(start);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(isLate ? 'Request cancellation?' : 'Cancel booking?'),
        content: Text(
          isLate
              ? 'This booking starts within 24 hours, so cancelling now '
                    'needs the host\'s approval. They\'ll be notified right '
                    'away.'
              : 'This will free up the slot for someone else. This can\'t '
                    'be undone.',
          style: const TextStyle(fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Never mind'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
            ),
            child: Text(isLate ? 'Request cancellation' : 'Cancel booking'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    try {
      final result = await BookingService.requestOrCancelBooking(
        widget.bookingId,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result == 'requested'
                ? 'Cancellation request sent to the host'
                : 'Booking cancelled',
          ),
          backgroundColor: const Color(0xFF111827),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Couldn\'t cancel: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _messageHost(String providerUid) async {
    final chatId = MessagingService.chatIdForUids(widget.myUid, providerUid);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            PrivateParkingChatScreen(chatId: chatId, otherUid: providerUid),
      ),
    );
  }

  Future<void> _rateHost(String providerUid) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _RateBookingSheet(
        revieweeUid: providerUid,
        bookingId: widget.bookingId,
        type: ReviewType.host,
        title: 'Rate this host',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.booking;
    final status = (b['status'] ?? 'confirmed').toString();
    final start = (b['start'] as Timestamp?)?.toDate();
    final end = (b['end'] as Timestamp?)?.toDate();
    final spaceTitle = (b['space_title'] as String?)?.trim();
    final providerUid = (b['provider_uid'] as String?) ?? '';
    final note = (b['note'] as String?)?.trim();
    final cancelledBy = b['cancelled_by'] as String?;
    final cancelledLate = b['cancelled_late'] as bool?;

    final statusInfo = _statusInfoFor(status);
    final canCancel = status == 'confirmed';
    final canMessage = status != 'cancelled';
    final canRate =
        (status == 'completed' || status == 'completed_unconfirmed');

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: status == 'cancelled'
                      ? [Colors.grey.shade400, Colors.grey.shade500]
                      : [const Color(0xFF6366F1), const Color(0xFF8B5CF6)],
                ),
              ),
              child: Row(
                children: [
                  if (providerUid.isNotEmpty)
                    ChatAvatar(uid: providerUid, size: 48)
                  else
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.local_parking_rounded,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          spaceTitle?.isNotEmpty == true
                              ? spaceTitle!
                              : 'Parking space',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.25),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.5),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                statusInfo.icon,
                                color: Colors.white,
                                size: 14,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                statusInfo.label,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Details
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _InfoRow(
                    icon: Icons.calendar_today_rounded,
                    label: 'Date & Time',
                    value: start != null
                        ? '${TimeFormat.date(start)} · ${TimeFormat.clock(start)}'
                              '${end != null ? ' – ${TimeFormat.clock(end)}' : ''}'
                        : 'N/A',
                    color: const Color(0xFF6366F1),
                  ),
                  if (providerUid.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFF8B5CF6).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.person_rounded,
                            color: Color(0xFF8B5CF6),
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Host',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey.shade500,
                                ),
                              ),
                              const SizedBox(height: 2),
                              ChatUserName(
                                uid: providerUid,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w900,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (note?.isNotEmpty == true) ...[
                    const SizedBox(height: 16),
                    _InfoRow(
                      icon: Icons.edit_note_rounded,
                      label: 'Your note',
                      value: note!,
                      color: const Color(0xFF0EA5E9),
                    ),
                  ],
                  if (status == 'cancelled' && cancelledBy != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      cancelledBy == 'renter'
                          ? (cancelledLate == true
                                ? 'You requested a late cancellation and the host approved it.'
                                : 'You cancelled this booking.')
                          : (cancelledLate == true
                                ? 'The host cancelled this booking close to the start time.'
                                : 'The host cancelled this booking.'),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade600,
                        height: 1.3,
                      ),
                    ),
                  ],
                  if (status == 'cancellation_requested') ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFFBEB),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFFDE68A)),
                      ),
                      child: const Text(
                        'Waiting for the host to respond to your '
                        'cancellation request.',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF92400E),
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 20),

                  if (_busy)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    )
                  else
                    Row(
                      children: [
                        if (canMessage && providerUid.isNotEmpty)
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _messageHost(providerUid),
                              icon: const Icon(
                                Icons.chat_bubble_outline_rounded,
                                size: 16,
                              ),
                              label: const Text('Message'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFF6366F1),
                                side: const BorderSide(
                                  color: Color(0xFF6366F1),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                        if (canCancel) ...[
                          if (canMessage) const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _cancel,
                              icon: const Icon(Icons.close_rounded, size: 16),
                              label: const Text('Cancel'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFFEF4444),
                                side: const BorderSide(
                                  color: Color(0xFFEF4444),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                        ],
                        if (canRate && providerUid.isNotEmpty) ...[
                          if (canMessage) const SizedBox(width: 10),
                          Expanded(
                            child: FutureBuilder<bool>(
                              future: ReviewService.hasReviewedBooking(
                                providerUid,
                                widget.bookingId,
                              ),
                              builder: (context, snap) {
                                final alreadyRated = snap.data == true;
                                return ElevatedButton.icon(
                                  onPressed: alreadyRated
                                      ? null
                                      : () => _rateHost(providerUid),
                                  icon: Icon(
                                    alreadyRated
                                        ? Icons.star_rounded
                                        : Icons.star_outline_rounded,
                                    size: 16,
                                  ),
                                  label: Text(
                                    alreadyRated ? 'Rated' : 'Rate host',
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFFF59E0B),
                                    foregroundColor: Colors.white,
                                    elevation: 0,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
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
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0F172A),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Shared 1-5 star + optional comment sheet, used by the renter to rate
/// the host once a booking is genuinely complete. (The provider's
/// rating of the renter happens inline as part of confirming attendance
/// instead - see BookingService.confirmAttendance.)
class _RateBookingSheet extends StatefulWidget {
  final String revieweeUid;
  final String bookingId;
  final ReviewType type;
  final String title;

  const _RateBookingSheet({
    required this.revieweeUid,
    required this.bookingId,
    required this.type,
    required this.title,
  });

  @override
  State<_RateBookingSheet> createState() => _RateBookingSheetState();
}

class _RateBookingSheetState extends State<_RateBookingSheet> {
  final _commentCtrl = TextEditingController();
  int _rating = 0;
  bool _submitting = false;

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_rating == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a star rating.')),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      await ReviewService.submitBookingReview(
        revieweeUid: widget.revieweeUid,
        bookingId: widget.bookingId,
        type: widget.type,
        rating: _rating,
        comment: _commentCtrl.text,
      );
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Thanks for your feedback!'),
          backgroundColor: Color(0xFF10B981),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Couldn\'t submit: $e')));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(12),
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(32),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 50,
              height: 5,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: const Color(0xFFE2E8F0),
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          Text(
            widget.title,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 20),
          Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(5, (i) {
                final starValue = i + 1;
                final filled = starValue <= _rating;
                return IconButton(
                  onPressed: () => setState(() => _rating = starValue),
                  icon: Icon(
                    filled ? Icons.star_rounded : Icons.star_outline_rounded,
                    color: const Color(0xFFF59E0B),
                    size: 36,
                  ),
                );
              }),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _commentCtrl,
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Comment (optional)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: _submitting ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6366F1),
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
              child: _submitting
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Text(
                      'Submit Rating',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
