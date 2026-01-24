import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../services/messaging_service.dart';

class ParkingSpaceDetailsScreen extends StatelessWidget {
  final String spaceId;
  const ParkingSpaceDetailsScreen({super.key, required this.spaceId});

  @override
  Widget build(BuildContext context) {
    final ref = FirebaseFirestore.instance
        .collection('parking_spaces')
        .doc(spaceId);

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FF),
      appBar: AppBar(
        title: const Text('Space details'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: ref.snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snap.hasData || !snap.data!.exists) {
            return const Center(child: Text('Space not found.'));
          }

          // ✅ FIX: define d FIRST
          final d = snap.data!.data() ?? <String, dynamic>{};

          // Provider and current user IDs
          final providerUid = (d['provider_uid'] as String?)?.trim() ?? '';
          final myUid = FirebaseAuth.instance.currentUser?.uid ?? '';

          final canMessage =
              providerUid.isNotEmpty &&
              myUid.isNotEmpty &&
              providerUid != myUid;

          String s(String key, {String fallback = ''}) =>
              (d[key] as String?)?.trim().isNotEmpty == true
              ? (d[key] as String).trim()
              : fallback;

          double numVal(String key) {
            final v = d[key];
            if (v is num) return v.toDouble();
            return 0.0;
          }

          final title = s('title', fallback: 'Private parking');
          final postcode = s('postcode');
          final area = s('approx_area', fallback: 'Wembley');

          final type = s('space_type');
          final access = s('access_type');
          final size = s('vehicle_size_max');

          final hourly = numVal('hourly_rate_gbp');
          final status = s('status', fallback: 'pending');

          final chips = <String>[
            if (type.isNotEmpty) _pretty(type),
            if (access.isNotEmpty) _pretty(access),
            if (size.isNotEmpty) _pretty(size),
          ];

          return Stack(
            children: [
              SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 132),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _HeroCard(
                      title: title,
                      subtitle: postcode.isNotEmpty
                          ? '$postcode • $area'
                          : area,
                      chips: chips,
                      status: status,
                    ),
                    const SizedBox(height: 14),
                    _PriceCard(hourly: hourly),
                    const SizedBox(height: 14),
                    _SectionCard(
                      title: 'What you get',
                      children: const [
                        _Bullet('Private bay/driveway space'),
                        _Bullet('Verified provider (manual approval)'),
                        _Bullet('Clear hourly pricing'),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _SectionCard(
                      title: 'Privacy & safety',
                      children: const [
                        _Bullet(
                          'Exact address will be shown only after payment (Stripe phase).',
                        ),
                        _Bullet(
                          'Providers are manually verified before listings go live.',
                        ),
                        _Bullet(
                          'You can report issues directly from the booking (Phase 2).',
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _NoticeCard(
                      text:
                          'Booking UI + payment (Stripe) will be added in Phase 2/3. For now, this screen verifies listing display + details.',
                    ),
                  ],
                ),
              ),

              _BottomCTA(
                hourly: hourly,
                canMessage: canMessage,
                onMessageProvider: () async {
                  if (!canMessage) {
                    final reason = myUid.isEmpty
                        ? 'Please sign in to message the provider.'
                        : providerUid.isEmpty
                        ? 'Provider profile not available for this space.'
                        : 'You cannot message your own listing.';
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text(reason)));
                    return;
                  }

                  try {
                    await MessagingService.sendChatRequest(
                      toUid: providerUid,
                      contextType: 'private_parking',
                      contextRefId: spaceId,
                    );
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Request sent. Wait for acceptance to chat.',
                        ),
                      ),
                    );
                  } catch (e) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Failed to send request: $e')),
                    );
                  }
                },
                onBook: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Booking + Stripe will be added in Phase 2/3.',
                      ),
                    ),
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }

  static String _pretty(String v) => v.replaceAll('_', ' ').trim();
}

class _HeroCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<String> chips;
  final String status;

  const _HeroCard({
    required this.title,
    required this.subtitle,
    required this.chips,
    required this.status,
  });

  @override
  Widget build(BuildContext context) {
    final s = status.trim().toLowerCase();
    final isApproved = s == 'approved';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          colors: [Color(0xFF0EA5E9), Color(0xFF6366F1), Color(0xFF8B5CF6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
            blurRadius: 22,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                height: 46,
                width: 46,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withOpacity(0.22)),
                ),
                child: const Icon(
                  Icons.local_parking_rounded,
                  color: Colors.white,
                  size: 26,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                    height: 1.1,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            subtitle,
            style: TextStyle(
              color: Colors.white.withOpacity(0.9),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: isApproved
                      ? const Color(0xFFECFDF5).withOpacity(0.22)
                      : Colors.white.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: Colors.white.withOpacity(0.22)),
                ),
                child: Text(
                  isApproved ? 'Approved listing' : 'Pending approval',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                  ),
                ),
              ),
              ...chips.map(
                (c) => Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: Colors.white.withOpacity(0.22)),
                  ),
                  child: Text(
                    c,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 12,
                    ),
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

class _PriceCard extends StatelessWidget {
  final double hourly;
  const _PriceCard({required this.hourly});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
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
            height: 44,
            width: 44,
            decoration: BoxDecoration(
              color: const Color(0xFFEEF2FF),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.payments_rounded, color: Color(0xFF4F46E5)),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Hourly rate',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                color: Color(0xFF0F172A),
              ),
            ),
          ),
          Text(
            '£${hourly.toStringAsFixed(2)}/hr',
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              color: Color(0xFF1D4ED8),
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _SectionCard({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  final String text;
  const _Bullet(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.check_circle_rounded,
            size: 18,
            color: Color(0xFF22C55E),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: Color(0xFF334155),
                height: 1.25,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NoticeCard extends StatelessWidget {
  final String text;
  const _NoticeCard({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFDE68A)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontWeight: FontWeight.w800,
          color: Color(0xFF92400E),
          height: 1.25,
        ),
      ),
    );
  }
}

class _BottomCTA extends StatelessWidget {
  final double hourly;
  final VoidCallback onBook;

  final bool canMessage;
  final VoidCallback onMessageProvider;

  const _BottomCTA({
    required this.hourly,
    required this.onBook,
    required this.canMessage,
    required this.onMessageProvider,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.96),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 18,
              offset: const Offset(0, -8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '£${hourly.toStringAsFixed(2)}/hr',
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                ),
                Expanded(
                  child: ElevatedButton(
                    onPressed: onBook,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4F46E5),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: const Text(
                      'Book this space',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onMessageProvider,
                icon: const Icon(Icons.chat_bubble_rounded),
                label: Text(
                  canMessage
                      ? 'Message provider (request)'
                      : 'Message not available',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  side: BorderSide(
                    color: canMessage
                        ? const Color(0xFF4F46E5)
                        : const Color(0xFFCBD5E1),
                  ),
                  foregroundColor: canMessage
                      ? const Color(0xFF4F46E5)
                      : const Color(0xFF64748B),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
