import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../services/booking_service.dart';
import '../services/messaging_service.dart';
import '../services/review_service.dart';
import '../utils/chat_avatar.dart';
import 'private_parking_chat_screen.dart';

class ParkingSpaceDetailsScreen extends StatelessWidget {
  final String spaceId;
  const ParkingSpaceDetailsScreen({super.key, required this.spaceId});

  @override
  Widget build(BuildContext context) {
    final ref = FirebaseFirestore.instance
        .collection('parking_spaces')
        .doc(spaceId);

    return Scaffold(
      backgroundColor: Colors.white, // ✅ WHITE BACKGROUND
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF0F172A)),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: ref.snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(
                strokeWidth: 3,
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF6366F1)),
              ),
            );
          }
          if (!snap.hasData || !snap.data!.exists) {
            return const Center(child: Text('Space not found'));
          }

          final data = snap.data!.data()!;
          final title = (data['title'] ?? 'Parking space').toString();
          final postcode = (data['postcode'] ?? '').toString();
          final area =
              ((data['approxArea'] ?? data['approx_area'] ?? data['area']) ??
                      '')
                  .toString();
          final exactAddress =
              (data['exactAddress'] ?? data['exact_address'] ?? '').toString();
          final type =
              ((data['spaceType'] ?? data['space_type'] ?? data['type']) ??
                      'Driveway')
                  .toString();
          final size = ((data['size'] ?? data['space_size']) ?? 'medium')
              .toString();
          final hourlyRateValue = data['hourlyRate'] ?? data['hourly_rate_gbp'];
          final hourlyRate = (hourlyRateValue is num)
              ? hourlyRateValue.toDouble()
              : 0.0;
          final availability = (data['availability'] ?? '24/7').toString();
          final statusLc = ((data['status'] ?? data['status_lc']) ?? '')
              .toString()
              .toLowerCase();
          final providerUid =
              ((data['providerId'] ?? data['provider_uid']) ?? '').toString();

          // Amenities
          final amenities = data['amenities'] as Map<String, dynamic>? ?? {};
          final isCovered = amenities['covered'] ?? false;
          final hasEVCharging = amenities['evCharging'] ?? false;
          final hasCCTV = amenities['cctv'] ?? false;
          final hasDisabledAccess = amenities['disabledAccess'] ?? false;

          // Additional info
          final accessInstructions = (data['accessInstructions'] ?? '')
              .toString();
          final vehicleRestrictions = (data['vehicleRestrictions'] ?? '')
              .toString();

          // Photos
          final photoUrls =
              (data['photoUrls'] ?? data['photo_urls'] ?? []) as List;

          final isApproved =
              (statusLc == 'approved' || data['approved'] == true);

          return StreamBuilder<String?>(
            stream: MessagingService.chatExistsStream(providerUid),
            builder: (context, chatExistsSnap) {
              final existingChatId = chatExistsSnap.data;
              final isConnected = existingChatId != null;

              return Stack(
                children: [
                  ListView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 90),
                    children: [
                      // ✅ Photo Gallery
                      if (photoUrls.isNotEmpty)
                        _SmoothPhotoGallery(photoUrls: photoUrls),
                      if (photoUrls.isNotEmpty) const SizedBox(height: 20),

                      // Title & Location
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(
                            Icons.location_on_rounded,
                            color: Color(0xFF6366F1),
                            size: 18,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            [
                              postcode,
                              area,
                            ].where((e) => e.trim().isNotEmpty).join(' • '),
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF64748B),
                            ),
                          ),
                          const Spacer(),
                          if (isApproved)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF10B981),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: const [
                                  Icon(
                                    Icons.verified_rounded,
                                    color: Colors.white,
                                    size: 14,
                                  ),
                                  SizedBox(width: 4),
                                  Text(
                                    'VERIFIED',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // Price Card
                      _WhiteCard(
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFF6366F1).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.attach_money_rounded,
                                color: Color(0xFF6366F1),
                                size: 28,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Hourly Rate',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF64748B),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '£${hourlyRate.toStringAsFixed(2)}/hour',
                                    style: const TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.w900,
                                      color: Color(0xFF0F172A),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Hosted By Card
                      _HostCard(providerUid: providerUid),
                      const SizedBox(height: 16),

                      // Space Details Card
                      _WhiteCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const _SectionTitle(
                              icon: Icons.info_outline_rounded,
                              title: 'Space Details',
                            ),
                            const SizedBox(height: 16),
                            _DetailRow(
                              icon: Icons.category_rounded,
                              label: 'Type',
                              value: type.replaceAll('_', ' ').toUpperCase(),
                            ),
                            const SizedBox(height: 12),
                            _DetailRow(
                              icon: Icons.straighten_rounded,
                              label: 'Size',
                              value: size[0].toUpperCase() + size.substring(1),
                            ),
                            const SizedBox(height: 12),
                            _DetailRow(
                              icon: Icons.access_time_rounded,
                              label: 'Availability',
                              value: _formatAvailability(availability),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Amenities Card (if any)
                      if (isCovered ||
                          hasEVCharging ||
                          hasCCTV ||
                          hasDisabledAccess)
                        _WhiteCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const _SectionTitle(
                                icon: Icons.star_rounded,
                                title: 'Amenities',
                              ),
                              const SizedBox(height: 16),
                              Wrap(
                                spacing: 10,
                                runSpacing: 10,
                                children: [
                                  if (isCovered)
                                    const _AmenityChip(
                                      icon: Icons.roofing_rounded,
                                      label: 'Covered',
                                    ),
                                  if (hasEVCharging)
                                    const _AmenityChip(
                                      icon: Icons.ev_station_rounded,
                                      label: 'EV Charging',
                                    ),
                                  if (hasCCTV)
                                    const _AmenityChip(
                                      icon: Icons.videocam_rounded,
                                      label: 'CCTV',
                                    ),
                                  if (hasDisabledAccess)
                                    const _AmenityChip(
                                      icon: Icons.accessible_rounded,
                                      label: 'Accessible',
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      if (isCovered ||
                          hasEVCharging ||
                          hasCCTV ||
                          hasDisabledAccess)
                        const SizedBox(height: 16),

                      // Location Card
                      _WhiteCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const _SectionTitle(
                              icon: Icons.location_on_rounded,
                              title: 'Location',
                            ),
                            const SizedBox(height: 16),
                            _DetailRow(
                              icon: Icons.pin_drop_rounded,
                              label: 'Postcode',
                              value: postcode,
                            ),
                            const SizedBox(height: 12),
                            _DetailRow(
                              icon: Icons.map_rounded,
                              label: 'Area',
                              value: area,
                            ),
                            if (exactAddress.isNotEmpty)
                              const SizedBox(height: 12),
                            if (exactAddress.isNotEmpty)
                              isConnected
                                  ? _DetailRow(
                                      icon: Icons.home_rounded,
                                      label: 'Address',
                                      value: exactAddress,
                                    )
                                  : const _LockedAddressNotice(),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Access & Restrictions (if provided)
                      if (accessInstructions.isNotEmpty ||
                          vehicleRestrictions.isNotEmpty)
                        _WhiteCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const _SectionTitle(
                                icon: Icons.info_rounded,
                                title: 'Important Information',
                              ),
                              if (accessInstructions.isNotEmpty)
                                const SizedBox(height: 16),
                              if (accessInstructions.isNotEmpty)
                                _InfoSection(
                                  icon: Icons.key_rounded,
                                  title: 'Access Instructions',
                                  content: accessInstructions,
                                ),
                              if (vehicleRestrictions.isNotEmpty &&
                                  accessInstructions.isNotEmpty)
                                const SizedBox(height: 16),
                              if (vehicleRestrictions.isNotEmpty)
                                _InfoSection(
                                  icon: Icons.local_shipping_rounded,
                                  title: 'Vehicle Restrictions',
                                  content: vehicleRestrictions,
                                ),
                            ],
                          ),
                        ),
                      if (accessInstructions.isNotEmpty ||
                          vehicleRestrictions.isNotEmpty)
                        const SizedBox(height: 16),

                      // What's Included
                      _WhiteCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const _SectionTitle(
                              icon: Icons.check_circle_rounded,
                              title: 'What\'s Included',
                            ),
                            const SizedBox(height: 16),
                            ...[
                              'Private bay/driveway space',
                              'Verified provider (manual approval)',
                              'Secure payment via Stripe',
                              'Instant booking confirmation',
                            ].map(
                              (text) => Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.check_circle,
                                      color: Color(0xFF10B981),
                                      size: 20,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        text,
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFF475569),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  // Bottom Bar
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: StreamBuilder<Map<String, dynamic>?>(
                      stream: MessagingService.requestStatusStream(
                        otherUid: providerUid,
                        contextType: 'private_parking',
                        contextRefId: spaceId,
                      ),
                      builder: (context, reqSnap) {
                        final requestData = reqSnap.data;
                        final requestStatus = requestData?['status'] as String?;

                        // A pending request takes priority over everything -
                        // the renter has already asked, show that status
                        // and let them cancel it before making another one.
                        if (requestStatus == 'pending') {
                          return _PendingRequestBar(
                            requestId: requestData!['requestId'] as String,
                            requestedAt:
                                requestData['requestedAt'] as Timestamp?,
                            durationHours:
                                (requestData['durationHours'] as num?)?.toInt(),
                          );
                        }

                        // A chat exists (from a previously accepted request)
                        // OR no prior connection at all - either way, show
                        // both actions. "Request to Book" is always available
                        // because a chat being open just means you've talked
                        // before, not that you never want to book again.
                        // "Message Provider" is only shown if a chat already
                        // exists (no point showing it if you've never
                        // connected - the request flow creates the chat).
                        return _DualActionBar(
                          isApproved: isApproved,
                          spaceId: spaceId,
                          spaceTitle: title,
                          providerUid: providerUid,
                          existingChatId: existingChatId,
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  String _formatAvailability(String availability) {
    switch (availability) {
      case '24/7':
        return '24/7 (Always Available)';
      case 'weekdays_only':
        return 'Weekdays Only (Mon-Fri)';
      case 'weekends_only':
        return 'Weekends Only (Sat-Sun)';
      case 'event_days_only':
        return 'Event Days Only';
      default:
        return availability;
    }
  }
}

// ============================================================================
// SMOOTH PHOTO GALLERY
// ============================================================================

class _SmoothPhotoGallery extends StatefulWidget {
  final List photoUrls;
  const _SmoothPhotoGallery({required this.photoUrls});

  @override
  State<_SmoothPhotoGallery> createState() => _SmoothPhotoGalleryState();
}

class _SmoothPhotoGalleryState extends State<_SmoothPhotoGallery> {
  late PageController _pageController;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Stack(
        children: [
          SizedBox(
            height: 240,
            child: PageView.builder(
              controller: _pageController,
              physics: const BouncingScrollPhysics(),
              onPageChanged: (index) => setState(() => _currentPage = index),
              itemCount: widget.photoUrls.length,
              itemBuilder: (context, index) {
                return Image.network(
                  widget.photoUrls[index].toString(),
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    color: const Color(0xFFF1F5F9),
                    child: const Icon(
                      Icons.local_parking_rounded,
                      color: Color(0xFF6366F1),
                      size: 60,
                    ),
                  ),
                );
              },
            ),
          ),
          if (widget.photoUrls.length > 1)
            Positioned(
              bottom: 12,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  widget.photoUrls.length,
                  (index) => AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: _currentPage == index ? 24 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: _currentPage == index
                          ? Colors.white
                          : Colors.white.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ),
            ),
          if (widget.photoUrls.length > 1)
            Positioned(
              top: 12,
              right: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${_currentPage + 1}/${widget.photoUrls.length}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ============================================================================
// WHITE CARD COMPONENT
// ============================================================================

class _WhiteCard extends StatelessWidget {
  final Widget child;
  const _WhiteCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1),
      ),
      child: child,
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final IconData icon;
  final String title;
  const _SectionTitle({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFF6366F1).withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: const Color(0xFF6366F1), size: 20),
        ),
        const SizedBox(width: 12),
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w900,
            color: Color(0xFF0F172A),
          ),
        ),
      ],
    );
  }
}

/// Who the renter is actually dealing with - previously this screen never
/// showed the provider's name or avatar at all until you'd already messaged
/// them. The "Verified" badge here means the PROVIDER's identity/license
/// was checked during their provider application (parkingProviderStatus on
/// their user doc) - it's deliberately separate from the green "VERIFIED"
/// pill above, which only means the listing itself was approved.
/// Who the renter is actually dealing with. The rating shown here is
/// the provider's HOST reputation specifically - kept separate from
/// their reputation as a renter elsewhere in the app, since the two say
/// nothing about each other. There is deliberately no "rate this host"
/// action on this screen anymore: rating now only becomes available
/// once a real booking has actually completed (see MyBookingsScreen),
/// rather than being available to anyone who's simply messaged them.
class _HostCard extends StatelessWidget {
  final String providerUid;
  const _HostCard({required this.providerUid});

  @override
  Widget build(BuildContext context) {
    if (providerUid.isEmpty) return const SizedBox.shrink();

    return _WhiteCard(
      child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(providerUid)
            .snapshots(),
        builder: (context, snap) {
          final data = snap.data?.data();
          final providerStatus =
              (data?['parkingProviderStatus'] ??
                      data?['parkingProvider_status'])
                  ?.toString();
          final isIdVerified = providerStatus == 'approved';

          return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: ReviewService.statsStream(providerUid),
            builder: (context, statsSnap) {
              final statsData = statsSnap.data?.data();
              final ratingAvg = ReviewService.hostAverageFrom(statsData);
              final ratingCount = ReviewService.hostCountFrom(statsData);

              return _HostCardContent(
                providerUid: providerUid,
                isIdVerified: isIdVerified,
                ratingAvg: ratingAvg,
                ratingCount: ratingCount,
              );
            },
          );
        },
      ),
    );
  }
}

class _HostCardContent extends StatelessWidget {
  final String providerUid;
  final bool isIdVerified;
  final double ratingAvg;
  final int ratingCount;

  const _HostCardContent({
    required this.providerUid,
    required this.isIdVerified,
    required this.ratingAvg,
    required this.ratingCount,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        ChatAvatar(uid: providerUid, size: 52),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Hosted by',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade500,
                ),
              ),
              const SizedBox(height: 2),
              ChatUserName(
                uid: providerUid,
                fallback: 'Provider',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF0F172A),
                ),
              ),
              if (ratingCount > 0) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(
                      Icons.star_rounded,
                      size: 16,
                      color: Color(0xFFF59E0B),
                    ),
                    const SizedBox(width: 3),
                    Text(
                      '${ratingAvg.toStringAsFixed(1)} '
                      '($ratingCount ${ratingCount == 1 ? 'review' : 'reviews'})',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        if (isIdVerified)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFEEF2FF),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: const Color(0xFF6366F1).withOpacity(0.3),
              ),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.shield_rounded, color: Color(0xFF6366F1), size: 14),
                SizedBox(width: 4),
                Text(
                  'ID Verified',
                  style: TextStyle(
                    color: Color(0xFF6366F1),
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Shown in place of the exact address until the provider has accepted a
/// request from this user. The address used to be displayed to anyone who
/// opened the listing - this makes the "reveal after connecting" rule
/// visible instead of just silently withholding the field.
class _LockedAddressNotice extends StatelessWidget {
  const _LockedAddressNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          const Icon(Icons.lock_rounded, size: 16, color: Color(0xFF94A3B8)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'The exact address is shared once the provider accepts your request',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade600,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFF94A3B8), size: 18),
        const SizedBox(width: 10),
        Text(
          '$label:',
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Color(0xFF64748B),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w900,
              color: Color(0xFF0F172A),
            ),
          ),
        ),
      ],
    );
  }
}

class _AmenityChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _AmenityChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF6366F1).withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF6366F1).withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: const Color(0xFF6366F1), size: 16),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Color(0xFF6366F1),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoSection extends StatelessWidget {
  final IconData icon;
  final String title;
  final String content;
  const _InfoSection({
    required this.icon,
    required this.title,
    required this.content,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: const Color(0xFF6366F1), size: 18),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF0F172A),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            content,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF475569),
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// BOTTOM BAR
// ============================================================================

// ============================================================================
// CONNECTED - chat already exists, just open it
// ============================================================================

/// The main CTA bar. Shows:
/// - One "Request to Book" button when there's no prior chat (first
///   contact - the request creates the chat on accept).
/// - Two buttons side by side once a chat exists: "Request to Book"
///   (always available, for booking again or booking a new slot) AND
///   "Message Provider" (to continue the existing conversation).
///
/// The key design principle: a chat being open just means you've
/// talked before. It does NOT mean you're permanently booked or
/// permanently done booking. The "Request to Book" option must always
/// be available so a returning renter can request a new slot.
class _DualActionBar extends StatelessWidget {
  final bool isApproved;
  final String spaceId;
  final String spaceTitle;
  final String providerUid;
  final String? existingChatId;

  const _DualActionBar({
    required this.isApproved,
    required this.spaceId,
    required this.spaceTitle,
    required this.providerUid,
    required this.existingChatId,
  });

  void _openRequestSheet(BuildContext context) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please sign in to send a request.')),
      );
      return;
    }
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _RequestToBookSheet(
        spaceId: spaceId,
        spaceTitle: spaceTitle,
        providerUid: providerUid,
      ),
    );
  }

  void _openChat(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PrivateParkingChatScreen(
          chatId: existingChatId!,
          otherUid: providerUid,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasChat = existingChatId != null;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: hasChat
            ? Row(
                children: [
                  // Message button (secondary) - only shown when chat
                  // already exists
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _openChat(context),
                      icon: const Icon(
                        Icons.chat_bubble_outline_rounded,
                        size: 18,
                      ),
                      label: const Text(
                        'Message',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF6366F1),
                        side: const BorderSide(
                          color: Color(0xFF6366F1),
                          width: 1.6,
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Request to Book button (primary) - always available
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: isApproved
                          ? () => _openRequestSheet(context)
                          : null,
                      icon: const Icon(Icons.event_available_rounded, size: 18),
                      label: Text(
                        isApproved ? 'Request to Book' : 'Not Available',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6366F1),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ),
                ],
              )
            // No chat yet - single prominent "Request to Book" button
            : _ModernButton(
                icon: isApproved
                    ? Icons.event_available_rounded
                    : Icons.lock_rounded,
                label: isApproved ? 'Request to Book' : 'Not Available',
                onPressed: isApproved ? () => _openRequestSheet(context) : null,
              ),
      ),
    );
  }
}

// ============================================================================
// PENDING - a request is already awaiting the provider's decision
// ============================================================================

class _PendingRequestBar extends StatefulWidget {
  final String requestId;
  final Timestamp? requestedAt;
  final int? durationHours;

  const _PendingRequestBar({
    required this.requestId,
    this.requestedAt,
    this.durationHours,
  });

  @override
  State<_PendingRequestBar> createState() => _PendingRequestBarState();
}

class _PendingRequestBarState extends State<_PendingRequestBar> {
  bool _busy = false;

  Future<void> _cancel() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await MessagingService.cancelChatRequest(widget.requestId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Request cancelled'),
          backgroundColor: Color(0xFF64748B),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final requestedAt = widget.requestedAt;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 16,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFBEB),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFFDE68A)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.schedule_rounded,
                      color: Color(0xFFF59E0B),
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'Request pending',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF92400E),
                            ),
                          ),
                          if (requestedAt != null)
                            Text(
                              () {
                                final start = requestedAt.toDate();
                                final end = start.add(
                                  Duration(hours: widget.durationHours ?? 1),
                                );
                                String hm(DateTime d) =>
                                    '${d.hour.toString().padLeft(2, '0')}:'
                                    '${d.minute.toString().padLeft(2, '0')}';
                                return 'For ${start.day}/${start.month} '
                                    '${hm(start)}–${hm(end)}';
                              }(),
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF92400E),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            _busy
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : TextButton(
                    onPressed: _cancel,
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFFEF4444),
                    ),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
          ],
        ),
      ),
    );
  }
}

class _ModernButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final IconData icon;
  final String label;
  final bool isSecondary;
  final Color? buttonColor;

  const _ModernButton({
    required this.onPressed,
    required this.icon,
    required this.label,
    this.isSecondary = false,
    this.buttonColor,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final baseColor = buttonColor ?? const Color(0xFF6366F1);

    return Container(
      height: 56,
      decoration: BoxDecoration(
        gradient: isSecondary
            ? null
            : enabled
            ? LinearGradient(colors: [baseColor, baseColor.withOpacity(0.8)])
            : LinearGradient(
                colors: [Colors.grey.shade300, Colors.grey.shade400],
              ),
        color: isSecondary ? const Color(0xFFF8F9FF) : null,
        borderRadius: BorderRadius.circular(16),
        border: isSecondary
            ? Border.all(color: const Color(0xFFE2E8F0), width: 2)
            : null,
        boxShadow: isSecondary
            ? null
            : enabled
            ? [
                BoxShadow(
                  color: baseColor.withOpacity(0.3),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(16),
          child: Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  color: isSecondary ? const Color(0xFF6366F1) : Colors.white,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: isSecondary
                          ? const Color(0xFF6366F1)
                          : Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.3,
                    ),
                    overflow: TextOverflow.ellipsis,
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

// ============================================================================
// REQUEST TO BOOK SHEET
// ============================================================================

class _RequestToBookSheet extends StatefulWidget {
  final String spaceId;
  final String spaceTitle;
  final String providerUid;

  const _RequestToBookSheet({
    required this.spaceId,
    required this.spaceTitle,
    required this.providerUid,
  });

  @override
  State<_RequestToBookSheet> createState() => _RequestToBookSheetState();
}

class _RequestToBookSheetState extends State<_RequestToBookSheet>
    with SingleTickerProviderStateMixin {
  final _noteCtrl = TextEditingController();
  DateTime _requestedAt = DateTime.now().add(const Duration(hours: 1));
  int _durationHours = 1;
  bool _sending = false;
  bool _checkingAvailability = false;
  bool _isUnavailable = false;
  late AnimationController _animController;
  late Animation<double> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _slideAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
    );
    _animController.forward();
    // Rebuild on every keystroke so the "provider will see" preview below
    // stays in sync with what's typed in the note field.
    _noteCtrl.addListener(_onNoteChanged);
    _checkAvailability();
  }

  void _onNoteChanged() => setState(() {});

  @override
  void dispose() {
    _noteCtrl.removeListener(_onNoteChanged);
    _noteCtrl.dispose();
    _animController.dispose();
    super.dispose();
  }

  /// Live check against confirmed bookings (not just other pending
  /// requests) for this exact space and time range. Re-run any time the
  /// date, time, or duration changes, so the warning is accurate before
  /// the person even attempts to send.
  Future<void> _checkAvailability() async {
    setState(() => _checkingAvailability = true);
    try {
      final taken = await BookingService.hasConflict(
        spaceId: widget.spaceId,
        start: _requestedAt,
        end: _requestedAt.add(Duration(hours: _durationHours)),
      );
      if (!mounted) return;
      setState(() {
        _isUnavailable = taken;
        _checkingAvailability = false;
      });
    } catch (_) {
      // Non-critical for the live indicator - the authoritative check
      // still runs again in _send() right before anything is sent, and
      // again server-side the moment a provider tries to accept.
      if (mounted) setState(() => _checkingAvailability = false);
    }
  }

  Future<void> _showSlotTakenDialog() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Row(
          children: [
            Icon(Icons.event_busy_rounded, color: Color(0xFFEF4444)),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Slot already booked',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
              ),
            ),
          ],
        ),
        content: const Text(
          'Someone else already has a confirmed booking that overlaps '
          'this time. Please choose a different date or time.',
          style: TextStyle(fontSize: 13, color: Color(0xFF475569), height: 1.4),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF6366F1),
            ),
            child: const Text('Choose another time'),
          ),
        ],
      ),
    );
  }

  Future<void> _pickRequestedAt() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      firstDate: now,
      lastDate: now.add(const Duration(days: 60)),
      initialDate: _requestedAt.isBefore(now) ? now : _requestedAt,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(primary: Color(0xFF6366F1)),
          ),
          child: child!,
        );
      },
    );
    if (date == null) return;

    if (!mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_requestedAt),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(primary: Color(0xFF6366F1)),
          ),
          child: child!,
        );
      },
    );
    if (time == null) return;

    setState(() {
      _requestedAt = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
    _checkAvailability();
  }

  void _setDuration(int hours) {
    setState(() => _durationHours = hours);
    _checkAvailability();
  }

  Future<void> _send() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    if (_requestedAt.isBefore(DateTime.now())) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please choose a time in the future.')),
      );
      return;
    }

    // Final authoritative check, right before sending - the live
    // indicator above is just UX guidance; this is what actually
    // prevents the request from going out if someone else's booking
    // beat them to it in the meantime.
    setState(() => _sending = true);

    try {
      final stillConflicts = await BookingService.hasConflict(
        spaceId: widget.spaceId,
        start: _requestedAt,
        end: _requestedAt.add(Duration(hours: _durationHours)),
      );
      if (stillConflicts) {
        if (!mounted) return;
        setState(() => _isUnavailable = true);
        await _showSlotTakenDialog();
        return;
      }

      await MessagingService.sendChatRequest(
        toUid: widget.providerUid,
        contextType: 'private_parking',
        contextRefId: widget.spaceId,
        contextTitle: widget.spaceTitle,
        requestedAt: _requestedAt,
        durationHours: _durationHours,
        note: _noteCtrl.text,
      );

      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✉️ Request sent! The provider will be notified.'),
          backgroundColor: Color(0xFF6366F1),
          duration: Duration(seconds: 3),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Couldn\'t send request: $e')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = MessagingService.composeBookingRequestMessage(
      requestedAt: _requestedAt,
      durationHours: _durationHours,
      note: _noteCtrl.text,
    );

    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0, 1),
        end: Offset.zero,
      ).animate(_slideAnimation),
      child: Container(
        margin: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(32),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 40,
              offset: const Offset(0, -10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              width: 50,
              height: 5,
              margin: const EdgeInsets.only(top: 16, bottom: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFE2E8F0),
                borderRadius: BorderRadius.circular(10),
              ),
            ),

            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.only(
                  left: 24,
                  right: 24,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 24,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                            ),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Icon(
                            Icons.chat_bubble_rounded,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Request to Book',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w900,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                              Text(
                                widget.spaceTitle,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF64748B),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Date & time
                    _ModernDateTimePicker(
                      startAt: _requestedAt,
                      onTap: _pickRequestedAt,
                      loading: _sending,
                    ),
                    const SizedBox(height: 16),

                    // Duration
                    const Text(
                      'Duration',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [1, 2, 4, 8, 24].map((h) {
                        final selected = h == _durationHours;
                        return ChoiceChip(
                          label: Text(h == 24 ? 'All day' : '$h hr'),
                          selected: selected,
                          onSelected: _sending ? null : (_) => _setDuration(h),
                          selectedColor: const Color(0xFF6366F1),
                          labelStyle: TextStyle(
                            color: selected
                                ? Colors.white
                                : const Color(0xFF334155),
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                          backgroundColor: const Color(0xFFF8F9FF),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(999),
                            side: BorderSide(
                              color: selected
                                  ? Colors.transparent
                                  : const Color(0xFFE2E8F0),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 12),

                    // Live availability indicator
                    if (_checkingAvailability)
                      Row(
                        children: [
                          const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Checking availability…',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey.shade500,
                            ),
                          ),
                        ],
                      )
                    else if (_isUnavailable)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF2F2),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: const Color(0xFFEF4444).withOpacity(0.25),
                          ),
                        ),
                        child: const Row(
                          children: [
                            Icon(
                              Icons.event_busy_rounded,
                              size: 16,
                              color: Color(0xFFEF4444),
                            ),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'This time is already booked. Choose a '
                                'different date or time.',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFFB91C1C),
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      Row(
                        children: [
                          Icon(
                            Icons.check_circle_rounded,
                            size: 14,
                            color: Colors.green.shade600,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'This slot is free',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Colors.green.shade700,
                            ),
                          ),
                        ],
                      ),
                    const SizedBox(height: 16),

                    // Optional note
                    _ModernTextField(
                      controller: _noteCtrl,
                      label: 'Message (optional)',
                      icon: Icons.edit_note_rounded,
                      hint: "e.g. I'll arrive in a blue Honda Civic",
                      textCapitalization: TextCapitalization.sentences,
                      maxLines: 3,
                    ),
                    const SizedBox(height: 20),

                    // Live preview of what the provider will see
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8F9FF),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'THE PROVIDER WILL SEE',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              color: Colors.grey.shade500,
                              letterSpacing: 0.6,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            preview,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF334155),
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Send button
                    SizedBox(
                      width: double.infinity,
                      height: 60,
                      child: ElevatedButton(
                        onPressed: (_sending || _isUnavailable) ? null : _send,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF6366F1),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                          shadowColor: const Color(0xFF6366F1).withOpacity(0.5),
                        ),
                        child: _sending
                            ? const SizedBox(
                                height: 24,
                                width: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 3,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.white,
                                  ),
                                ),
                              )
                            : const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.send_rounded, size: 20),
                                  SizedBox(width: 10),
                                  Text(
                                    'Send Request',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// MODERN FORM COMPONENTS
// ============================================================================

class _ModernTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final String hint;
  final TextCapitalization? textCapitalization;
  final TextInputType? keyboardType;
  final int maxLines;

  const _ModernTextField({
    required this.controller,
    required this.label,
    required this.icon,
    required this.hint,
    this.textCapitalization,
    this.keyboardType,
    this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: Color(0xFF0F172A),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          textCapitalization: textCapitalization ?? TextCapitalization.none,
          keyboardType: keyboardType,
          maxLines: maxLines,
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: Icon(icon, color: const Color(0xFF6366F1)),
            filled: true,
            fillColor: const Color(0xFFF8F9FF),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Color(0xFF6366F1), width: 2),
            ),
          ),
        ),
      ],
    );
  }
}

class _ModernDateTimePicker extends StatelessWidget {
  final DateTime startAt;
  final VoidCallback onTap;
  final bool loading;

  const _ModernDateTimePicker({
    required this.startAt,
    required this.onTap,
    required this.loading,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Start Date & Time',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: Color(0xFF0F172A),
          ),
        ),
        const SizedBox(height: 8),
        InkWell(
          onTap: loading ? null : onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF8F9FF),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              children: [
                const Icon(Icons.schedule_rounded, color: Color(0xFF6366F1)),
                const SizedBox(width: 12),
                Text(
                  '${startAt.day}/${startAt.month}/${startAt.year} at '
                  '${startAt.hour.toString().padLeft(2, '0')}:'
                  '${startAt.minute.toString().padLeft(2, '0')}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const Spacer(),
                const Icon(
                  Icons.edit_rounded,
                  color: Color(0xFF94A3B8),
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
