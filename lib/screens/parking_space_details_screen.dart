import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../services/messaging_service.dart';
import 'private_parking_chat_screen.dart';
import 'stripe_checkout_webview.dart';

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
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: Container(
          margin: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.9),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: IconButton(
            icon: const Icon(
              Icons.arrow_back_rounded,
              color: Color(0xFF0F172A),
            ),
            onPressed: () => Navigator.pop(context),
          ),
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
          final area = (data['area'] ?? '').toString();
          final type = (data['type'] ?? 'Driveway').toString();
          final hourlyRate = (data['hourly_rate_gbp'] ?? 0).toDouble();
          final statusLc = (data['status_lc'] ?? '').toString().toLowerCase();
          final providerUid = (data['provider_uid'] ?? '').toString();

          final isApproved = statusLc == 'approved';

          return Stack(
            children: [
              // Gradient Background
              Container(
                height: 320,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFF6366F1),
                      const Color(0xFF8B5CF6),
                      const Color(0xFFA855F7),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
              ),

              // Content
              Column(
                children: [
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 100, 20, 180),
                      children: [
                        _PremiumHeaderCard(
                          title: title,
                          subtitle: [
                            postcode,
                            area,
                          ].where((e) => e.trim().isNotEmpty).join(' • '),
                          typeChip: type,
                          approved: isApproved,
                        ),
                        const SizedBox(height: 20),
                        _GlassPriceCard(hourlyRate: hourlyRate),
                        const SizedBox(height: 20),
                        _ModernInfoCard(
                          title: 'What\'s Included',
                          icon: Icons.check_circle_rounded,
                          iconColor: const Color(0xFF10B981),
                          bullets: const [
                            'Private bay/driveway space',
                            'Verified provider (manual approval)',
                            'Secure payment via Stripe',
                            'Instant booking confirmation',
                          ],
                        ),
                        const SizedBox(height: 20),
                        _ModernInfoCard(
                          title: 'Safety & Security',
                          icon: Icons.shield_rounded,
                          iconColor: const Color(0xFF6366F1),
                          bullets: const [
                            'Encrypted payment processing',
                            'Provider identity verified',
                            'Direct messaging available',
                            '24/7 customer support',
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Bottom Floating Actions
                  _FloatingBottomActions(
                    hourlyRate: hourlyRate,
                    spaceId: spaceId,
                    spaceTitle: title,
                    providerUid: providerUid,
                    isApproved: isApproved,
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

// ============================================================================
// PREMIUM HEADER CARD (Glassmorphic)
// ============================================================================

class _PremiumHeaderCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String typeChip;
  final bool approved;

  const _PremiumHeaderCard({
    required this.title,
    required this.subtitle,
    required this.typeChip,
    required this.approved,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.15),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: Colors.white.withOpacity(0.3),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 30,
                offset: const Offset(0, 15),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.25),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.4),
                        width: 2,
                      ),
                    ),
                    child: const Icon(
                      Icons.local_parking_rounded,
                      color: Colors.white,
                      size: 36,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.3,
                            shadows: [
                              Shadow(color: Colors.black26, blurRadius: 8),
                            ],
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          subtitle,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.9),
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  _GlassChip(label: typeChip, icon: Icons.apartment_rounded),
                  const SizedBox(width: 10),
                  _GlassChip(
                    label: approved ? 'Verified' : 'Pending',
                    icon: approved
                        ? Icons.verified_rounded
                        : Icons.pending_rounded,
                    color: approved
                        ? const Color(0xFF10B981)
                        : const Color(0xFFF59E0B),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GlassChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color? color;

  const _GlassChip({required this.label, required this.icon, this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: (color ?? Colors.white).withOpacity(0.25),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: (color ?? Colors.white).withOpacity(0.4),
          width: 1.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 16),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// GLASS PRICE CARD
// ============================================================================

class _GlassPriceCard extends StatelessWidget {
  final double hourlyRate;
  const _GlassPriceCard({required this.hourlyRate});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.95),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: Colors.white.withOpacity(0.8),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF6366F1).withOpacity(0.1),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF6366F1).withOpacity(0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.payments_rounded,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Hourly Rate',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF64748B),
                        letterSpacing: 0.5,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Pay per hour',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF10B981), Color(0xFF059669)],
                  ),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF10B981).withOpacity(0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Text(
                  '£${hourlyRate.toStringAsFixed(2)}/hr',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// MODERN INFO CARD
// ============================================================================

class _ModernInfoCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color iconColor;
  final List<String> bullets;

  const _ModernInfoCard({
    required this.title,
    required this.icon,
    required this.iconColor,
    required this.bullets,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconColor, size: 24),
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
          ),
          const SizedBox(height: 16),
          ...bullets.map(
            (bullet) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 2),
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: iconColor.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.check_rounded,
                      color: iconColor,
                      size: 14,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      bullet,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF334155),
                        height: 1.4,
                      ),
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

// ============================================================================
// SMART FLOATING BOTTOM ACTIONS WITH CHAT REQUEST FLOW
// ============================================================================

class _FloatingBottomActions extends StatelessWidget {
  final double hourlyRate;
  final String spaceId;
  final String spaceTitle;
  final String providerUid;
  final bool isApproved;

  const _FloatingBottomActions({
    required this.hourlyRate,
    required this.spaceId,
    required this.spaceTitle,
    required this.providerUid,
    required this.isApproved,
  });

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final myUid = user?.uid ?? '';

    // Check if user can message
    final canMessage =
        providerUid.isNotEmpty && myUid.isNotEmpty && providerUid != myUid;

    if (!canMessage) {
      // Static bottom bar (no messaging)
      return _buildBottomBar(
        context,
        hourlyRate: hourlyRate,
        chatIcon: Icons.chat_bubble_rounded,
        chatLabel: 'Chat',
        chatColor: Colors.grey,
        onChatPressed: null,
        isApproved: isApproved,
        spaceId: spaceId,
        spaceTitle: spaceTitle,
        providerUid: providerUid,
      );
    }

    // Smart bottom bar with chat request flow
    return StreamBuilder<String?>(
      stream: MessagingService.chatExistsStream(providerUid),
      builder: (context, chatSnap) {
        final existingChatId = chatSnap.data;

        if (existingChatId != null) {
          // Chat exists - show chat button
          return _buildBottomBar(
            context,
            hourlyRate: hourlyRate,
            chatIcon: Icons.chat_bubble_rounded,
            chatLabel: 'Chat',
            chatColor: const Color(0xFF10B981), // Green
            onChatPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PrivateParkingChatScreen(
                    chatId: existingChatId,
                    otherUid: providerUid,
                  ),
                ),
              );
            },
            isApproved: isApproved,
            spaceId: spaceId,
            spaceTitle: spaceTitle,
            providerUid: providerUid,
          );
        }

        // No chat exists - check request status
        return StreamBuilder<Map<String, dynamic>?>(
          stream: MessagingService.requestStatusStream(
            otherUid: providerUid,
            contextType: 'private_parking',
            contextRefId: spaceId,
          ),
          builder: (context, reqSnap) {
            final requestData = reqSnap.data;
            final status = requestData?['status'] as String?;

            if (status == 'pending') {
              // Request pending
              return _PendingRequestBottomBar(
                hourlyRate: hourlyRate,
                requestId: requestData!['requestId'] as String,
                isApproved: isApproved,
                spaceId: spaceId,
                spaceTitle: spaceTitle,
                providerUid: providerUid,
              );
            }

            // No request - show request button
            return _RequestChatBottomBar(
              hourlyRate: hourlyRate,
              providerUid: providerUid,
              isApproved: isApproved,
              spaceId: spaceId,
              spaceTitle: spaceTitle,
            );
          },
        );
      },
    );
  }
}

// ============================================================================
// PENDING REQUEST BOTTOM BAR
// ============================================================================

class _PendingRequestBottomBar extends StatefulWidget {
  final double hourlyRate;
  final String requestId;
  final bool isApproved;
  final String spaceId;
  final String spaceTitle;
  final String providerUid;

  const _PendingRequestBottomBar({
    required this.hourlyRate,
    required this.requestId,
    required this.isApproved,
    required this.spaceId,
    required this.spaceTitle,
    required this.providerUid,
  });

  @override
  State<_PendingRequestBottomBar> createState() =>
      _PendingRequestBottomBarState();
}

class _PendingRequestBottomBarState extends State<_PendingRequestBottomBar> {
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
    return _buildBottomBar(
      context,
      hourlyRate: widget.hourlyRate,
      chatIcon: _busy ? Icons.hourglass_empty_rounded : Icons.schedule_rounded,
      chatLabel: _busy ? 'Cancelling...' : 'Pending',
      chatColor: const Color(0xFFF59E0B), // Orange
      onChatPressed: _busy ? null : _cancel,
      isApproved: widget.isApproved,
      spaceId: widget.spaceId,
      spaceTitle: widget.spaceTitle,
      providerUid: widget.providerUid,
    );
  }
}

// ============================================================================
// REQUEST CHAT BOTTOM BAR
// ============================================================================

class _RequestChatBottomBar extends StatefulWidget {
  final double hourlyRate;
  final String providerUid;
  final bool isApproved;
  final String spaceId;
  final String spaceTitle;

  const _RequestChatBottomBar({
    required this.hourlyRate,
    required this.providerUid,
    required this.isApproved,
    required this.spaceId,
    required this.spaceTitle,
  });

  @override
  State<_RequestChatBottomBar> createState() => _RequestChatBottomBarState();
}

class _RequestChatBottomBarState extends State<_RequestChatBottomBar> {
  bool _busy = false;

  Future<void> _sendRequest() async {
    if (_busy) return;
    setState(() => _busy = true);

    try {
      await MessagingService.sendChatRequest(
        toUid: widget.providerUid,
        contextType: 'private_parking',
        contextRefId: widget.spaceId,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✉️ Chat request sent! Wait for acceptance.'),
          backgroundColor: Color(0xFF6366F1),
          duration: Duration(seconds: 3),
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
    return _buildBottomBar(
      context,
      hourlyRate: widget.hourlyRate,
      chatIcon: _busy ? Icons.send_rounded : Icons.chat_bubble_outline_rounded,
      chatLabel: _busy ? 'Sending...' : 'Request Chat',
      chatColor: const Color(0xFF6366F1), // Blue
      onChatPressed: _busy ? null : _sendRequest,
      isApproved: widget.isApproved,
      spaceId: widget.spaceId,
      spaceTitle: widget.spaceTitle,
      providerUid: widget.providerUid,
    );
  }
}

// ============================================================================
// BOTTOM BAR BUILDER (Shared)
// ============================================================================

Widget _buildBottomBar(
  BuildContext context, {
  required double hourlyRate,
  required IconData chatIcon,
  required String chatLabel,
  required Color chatColor,
  required VoidCallback? onChatPressed,
  required bool isApproved,
  required String spaceId,
  required String spaceTitle,
  required String providerUid,
}) {
  return Container(
    margin: const EdgeInsets.all(20),
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(28),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.1),
          blurRadius: 30,
          offset: const Offset(0, -10),
        ),
      ],
    ),
    child: SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(
                Icons.local_parking_rounded,
                color: Color(0xFF6366F1),
                size: 24,
              ),
              const SizedBox(width: 8),
              Text(
                '£${hourlyRate.toStringAsFixed(2)}/hour',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF0F172A),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _ModernButton(
                  onPressed: onChatPressed,
                  icon: chatIcon,
                  label: chatLabel,
                  isSecondary: false,
                  buttonColor: chatColor,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: _ModernButton(
                  onPressed: isApproved
                      ? () async {
                          final user = FirebaseAuth.instance.currentUser;
                          if (user == null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Please sign in to book.'),
                              ),
                            );
                            return;
                          }

                          await showModalBottomSheet(
                            context: context,
                            isScrollControlled: true,
                            backgroundColor: Colors.transparent,
                            builder: (_) => _PremiumBookingSheet(
                              spaceId: spaceId,
                              spaceTitle: spaceTitle,
                              hourlyRate: hourlyRate,
                              providerUid: providerUid,
                            ),
                          );
                        }
                      : null,
                  icon: isApproved
                      ? Icons.event_available_rounded
                      : Icons.lock_rounded,
                  label: isApproved ? 'Book Now' : 'Not Available',
                  isSecondary: false,
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
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
// PREMIUM BOOKING SHEET
// ============================================================================

class _PremiumBookingSheet extends StatefulWidget {
  final String spaceId;
  final String spaceTitle;
  final double hourlyRate;
  final String providerUid;

  const _PremiumBookingSheet({
    required this.spaceId,
    required this.spaceTitle,
    required this.hourlyRate,
    required this.providerUid,
  });

  @override
  State<_PremiumBookingSheet> createState() => _PremiumBookingSheetState();
}

class _PremiumBookingSheetState extends State<_PremiumBookingSheet>
    with SingleTickerProviderStateMixin {
  final _vehicleCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  int _hours = 1;
  DateTime _startAt = DateTime.now().add(const Duration(hours: 1));
  bool _loading = false;
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
  }

  @override
  void dispose() {
    _vehicleCtrl.dispose();
    _phoneCtrl.dispose();
    _animController.dispose();
    super.dispose();
  }

  double get _total => widget.hourlyRate * _hours;

  Future<void> _pickStartAt() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      firstDate: now,
      lastDate: now.add(const Duration(days: 30)),
      initialDate: _startAt,
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
      initialTime: TimeOfDay.fromDateTime(_startAt),
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
      _startAt = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  Future<void> _startPayment() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final vehicleReg = _vehicleCtrl.text.trim();
    if (vehicleReg.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter your vehicle registration.'),
        ),
      );
      return;
    }

    setState(() => _loading = true);

    try {
      final bookingRef = FirebaseFirestore.instance
          .collection('parking_bookings')
          .doc();
      final expiresAt = DateTime.now().add(const Duration(minutes: 15));

      await bookingRef.set({
        'bookingId': bookingRef.id,
        'spaceId': widget.spaceId,
        'userId': user.uid,
        'providerId': widget.providerUid,
        'hours': _hours,
        'startAt': Timestamp.fromDate(_startAt),
        'vehicleReg': vehicleReg,
        'phone': _phoneCtrl.text.trim(),
        'status': 'pending_payment',
        'paymentStatus': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
        'expiresAt': Timestamp.fromDate(expiresAt),
      });

      final callable = FirebaseFunctions.instanceFor(
        region: 'us-central1',
      ).httpsCallable('createCheckoutSession');
      final result = await callable.call({'bookingId': bookingRef.id});
      final url = (result.data['url'] ?? '').toString();

      if (url.isEmpty) throw Exception('Stripe checkout URL is empty');

      if (!mounted) return;

      final paid = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => StripeCheckoutWebView(initialUrl: url),
        ),
      );

      if (!mounted) return;

      if (paid != true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Payment cancelled. Booking not confirmed.'),
          ),
        );
        setState(() => _loading = false);
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Payment received. Confirming booking...'),
        ),
      );

      final confirmed = await _waitForBookingConfirmation(bookingRef);

      if (!mounted) return;

      if (confirmed) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Booking confirmed! Check "My Bookings".'),
            backgroundColor: Color(0xFF10B981),
          ),
        );
        Navigator.pop(context);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Payment done, but confirmation is pending. Check "My Bookings" shortly.',
            ),
          ),
        );
        setState(() => _loading = false);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Booking/payment failed: $e')));
      }
      setState(() => _loading = false);
    }
  }

  Future<bool> _waitForBookingConfirmation(DocumentReference bookingRef) async {
    const timeout = Duration(seconds: 30);
    final end = DateTime.now().add(timeout);

    while (DateTime.now().isBefore(end)) {
      final snap = await bookingRef.get();
      final data = snap.data() as Map<String, dynamic>?;
      final status = (data?['status'] ?? '').toString();
      if (status == 'confirmed') return true;
      if (status == 'expired') return false;
      await Future.delayed(const Duration(seconds: 2));
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
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
                            Icons.event_available_rounded,
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
                                'Book Parking',
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

                    // Vehicle Registration
                    _ModernTextField(
                      controller: _vehicleCtrl,
                      label: 'Vehicle Registration',
                      icon: Icons.directions_car_rounded,
                      hint: 'e.g., AB12 CDE',
                      textCapitalization: TextCapitalization.characters,
                    ),
                    const SizedBox(height: 16),

                    // Phone
                    _ModernTextField(
                      controller: _phoneCtrl,
                      label: 'Phone (Optional)',
                      icon: Icons.phone_rounded,
                      hint: 'For contact if needed',
                      keyboardType: TextInputType.phone,
                    ),
                    const SizedBox(height: 16),

                    // Start Time
                    _ModernDateTimePicker(
                      startAt: _startAt,
                      onTap: _pickStartAt,
                      loading: _loading,
                    ),
                    const SizedBox(height: 16),

                    // Duration
                    _ModernDurationPicker(
                      hours: _hours,
                      onDecrease: _hours > 1 && !_loading
                          ? () => setState(() => _hours--)
                          : null,
                      onIncrease: _hours < 24 && !_loading
                          ? () => setState(() => _hours++)
                          : null,
                    ),
                    const SizedBox(height: 24),

                    // Total
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
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
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Total Amount',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'Including all fees',
                                style: TextStyle(
                                  color: Colors.white60,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          Text(
                            '£${_total.toStringAsFixed(2)}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 32,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Book Button
                    SizedBox(
                      width: double.infinity,
                      height: 60,
                      child: ElevatedButton(
                        onPressed: _loading ? null : _startPayment,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF10B981),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                          shadowColor: const Color(0xFF10B981).withOpacity(0.5),
                        ),
                        child: _loading
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
                                  Icon(Icons.lock_rounded, size: 20),
                                  SizedBox(width: 8),
                                  Text(
                                    'Proceed to Payment',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Security note
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.shield_rounded,
                          size: 16,
                          color: Colors.grey.shade600,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Secure payment via Stripe',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
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

  const _ModernTextField({
    required this.controller,
    required this.label,
    required this.icon,
    required this.hint,
    this.textCapitalization,
    this.keyboardType,
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

class _ModernDurationPicker extends StatelessWidget {
  final int hours;
  final VoidCallback? onDecrease;
  final VoidCallback? onIncrease;

  const _ModernDurationPicker({
    required this.hours,
    required this.onDecrease,
    required this.onIncrease,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Duration',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: Color(0xFF0F172A),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFF8F9FF),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Row(
            children: [
              const Icon(Icons.timelapse_rounded, color: Color(0xFF6366F1)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '$hours ${hours == 1 ? "hour" : "hours"}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ),
              Row(
                children: [
                  IconButton(
                    onPressed: onDecrease,
                    icon: const Icon(Icons.remove_circle_rounded),
                    color: const Color(0xFF6366F1),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: onIncrease,
                    icon: const Icon(Icons.add_circle_rounded),
                    color: const Color(0xFF6366F1),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
