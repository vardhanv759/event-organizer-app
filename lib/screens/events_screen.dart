import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:ui';

/// ===============================
/// WEMBLEY EVENTS (now -> +1 year)
/// ===============================
class EventsListScreen extends StatefulWidget {
  const EventsListScreen({super.key});

  @override
  State<EventsListScreen> createState() => _EventsListScreenState();
}

class _EventsListScreenState extends State<EventsListScreen>
    with TickerProviderStateMixin {
  late AnimationController _fadeController;
  String _selectedCategory = 'All';
  String _searchQuery = '';

  final List<String> categories = [
    'All',
    'Music',
    'Sports',
    'Theater',
    'Comedy',
    'Festivals',
  ];

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeController.forward();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _eventsStream() {
    final now = Timestamp.now();
    final oneYearLater = Timestamp.fromDate(
      DateTime.now().add(const Duration(days: 365)),
    );

    var query = FirebaseFirestore.instance
        .collection('events_wembley')
        .where('startDateTime', isGreaterThanOrEqualTo: now)
        .where('startDateTime', isLessThanOrEqualTo: oneYearLater)
        .orderBy('startDateTime');

    return query.snapshots();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FF),
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // Premium Header
          SliverAppBar(
            expandedHeight: 260,
            pinned: true,
            elevation: 0,
            backgroundColor: Colors.transparent,
            flexibleSpace: FlexibleSpaceBar(background: _buildModernHeader()),
          ),

          // Filter & Search Section
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                _buildSearchBar(),
                const SizedBox(height: 16),
                _buildCategoryChips(),
              ]),
            ),
          ),

          // Events List
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
            sliver: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _eventsStream(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return SliverToBoxAdapter(child: _buildLoadingState());
                }

                if (snapshot.hasError) {
                  return SliverToBoxAdapter(
                    child: _buildErrorState(snapshot.error),
                  );
                }

                final docs = snapshot.data?.docs ?? [];
                if (docs.isEmpty) {
                  return SliverToBoxAdapter(child: _buildEmptyState());
                }

                final events = docs.map((doc) {
                  final data = doc.data();
                  return _EventItem(
                    id: data['id']?.toString() ?? doc.id,
                    name: data['title'] as String? ?? 'Unnamed event',
                    venueName: data['venueName'] as String? ?? 'Venue TBA',
                    city: data['city'] as String? ?? 'London',
                    addressLine1: data['addressLine1'] as String? ?? '',
                    addressLine2: data['addressLine2'] as String?,
                    postalCode: data['postalCode'] as String? ?? '',
                    startDateTime: data['startDateTime'] as Timestamp?,
                    timezone: data['timezone'] as String? ?? 'Europe/London',
                    imageUrl:
                        data['imageUrl'] as String? ??
                        data['thumbnailUrl'] as String?,
                    url: data['url'] as String?,
                    isFamilyEvent: (data['isFamilyEvent'] as bool?) ?? false,
                    source: (data['source'] as String? ?? 'Ticketmaster')
                        .trim(),
                  );
                }).toList();

                return SliverList(
                  delegate: SliverChildBuilderDelegate((context, index) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: FadeTransition(
                        opacity: Tween<double>(begin: 0, end: 1).animate(
                          CurvedAnimation(
                            parent: _fadeController,
                            curve: Interval(
                              (index * 0.1).clamp(0, 1),
                              ((index + 1) * 0.1).clamp(0, 1),
                            ),
                          ),
                        ),
                        child: SlideTransition(
                          position:
                              Tween<Offset>(
                                begin: const Offset(0, 0.3),
                                end: Offset.zero,
                              ).animate(
                                CurvedAnimation(
                                  parent: _fadeController,
                                  curve: Curves.easeOutCubic,
                                ),
                              ),
                          child: _EventCard(event: events[index]),
                        ),
                      ),
                    );
                  }, childCount: events.length),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModernHeader() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF667EEA), Color(0xFF764BA2), Color(0xFF8B5CF6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        children: [
          // Animated background circles
          Positioned(
            right: -50,
            top: -50,
            child: Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Positioned(
            left: -80,
            bottom: -40,
            child: Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.08),
                shape: BoxShape.circle,
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Icon(
                          Icons.event_rounded,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Wembley Events',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                                letterSpacing: -0.5,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Discover amazing events near you',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
                              ),
                            ),
                          ],
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
    );
  }

  Widget _buildSearchBar() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF667EEA).withOpacity(0.15),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: TextField(
        onChanged: (value) => setState(() => _searchQuery = value),
        decoration: InputDecoration(
          hintText: 'Search events...',
          hintStyle: TextStyle(color: Colors.grey.shade400),
          border: InputBorder.none,
          prefixIcon: Padding(
            padding: const EdgeInsets.only(left: 16, right: 8),
            child: Icon(
              Icons.search_rounded,
              color: Colors.grey.shade400,
              size: 24,
            ),
          ),
          suffixIcon: _searchQuery.isNotEmpty
              ? Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: IconButton(
                    icon: const Icon(Icons.close_rounded),
                    color: Colors.grey.shade400,
                    onPressed: () => setState(() => _searchQuery = ''),
                  ),
                )
              : null,
          contentPadding: const EdgeInsets.symmetric(vertical: 16),
        ),
      ),
    );
  }

  Widget _buildCategoryChips() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: List.generate(categories.length, (index) {
          final category = categories[index];
          final isSelected = _selectedCategory == category;

          return Padding(
            padding: EdgeInsets.only(
              right: index == categories.length - 1 ? 0 : 8,
            ),
            child: GestureDetector(
              onTap: () => setState(() => _selectedCategory = category),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  gradient: isSelected
                      ? const LinearGradient(
                          colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
                        )
                      : null,
                  color: isSelected ? null : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: isSelected
                      ? null
                      : Border.all(color: Colors.grey.shade200, width: 1.5),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: const Color(0xFF667EEA).withOpacity(0.3),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ]
                      : null,
                ),
                child: Text(
                  category,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isSelected ? Colors.white : Colors.grey.shade700,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildLoadingState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 80),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF667EEA).withOpacity(0.2),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF667EEA)),
              strokeWidth: 3,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Loading amazing events...',
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(Object? error) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 80),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.1),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Icon(
              Icons.error_outline_rounded,
              size: 48,
              color: Colors.red.shade400,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Unable to load events',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Please check your connection and try again',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 80),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
              ),
              borderRadius: BorderRadius.circular(28),
            ),
            child: const Icon(
              Icons.event_available_rounded,
              size: 48,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'No events found',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Check back later for upcoming Wembley events',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _EventItem {
  final String id;
  final String name;
  final String venueName;
  final String city;
  final String addressLine1;
  final String? addressLine2;
  final String postalCode;
  final Timestamp? startDateTime;
  final String timezone;
  final String? imageUrl;
  final String? url;
  final bool isFamilyEvent;
  final String source;

  _EventItem({
    required this.id,
    required this.name,
    required this.venueName,
    required this.city,
    required this.addressLine1,
    required this.addressLine2,
    required this.postalCode,
    required this.startDateTime,
    required this.timezone,
    required this.imageUrl,
    required this.url,
    required this.isFamilyEvent,
    required this.source,
  });
}

class _EventCard extends StatefulWidget {
  final _EventItem event;

  const _EventCard({required this.event});

  @override
  State<_EventCard> createState() => _EventCardState();
}

class _EventCardState extends State<_EventCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _hoverController;
  bool _isSaved = false;

  @override
  void initState() {
    super.initState();
    _hoverController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
  }

  @override
  void dispose() {
    _hoverController.dispose();
    super.dispose();
  }

  String _formatDateTime(Timestamp? ts, String timezone) {
    if (ts == null) return 'Date / time TBA';
    final dt = ts.toDate();
    String two(int v) => v.toString().padLeft(2, '0');
    final date = '${two(dt.day)}/${two(dt.month)}/${dt.year}';
    final time = '${two(dt.hour)}:${two(dt.minute)}';
    return '$date  •  $time';
  }

  String _buildAddress() {
    final parts = <String>[
      widget.event.addressLine1,
      if ((widget.event.addressLine2 ?? '').trim().isNotEmpty)
        widget.event.addressLine2!.trim(),
      widget.event.city,
      widget.event.postalCode,
    ].where((p) => p.trim().isNotEmpty).toList();

    return parts.isEmpty ? 'Wembley, London' : parts.join(', ');
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => _hoverController.forward(),
      onExit: (_) => _hoverController.reverse(),
      child: GestureDetector(
        onTap: () {
          showEventDetails(context, widget.event);
        },
        child: AnimatedBuilder(
          animation: _hoverController,
          builder: (context, child) {
            return Transform.translate(
              offset: Offset(0, -_hoverController.value * 4),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(
                        0xFF667EEA,
                      ).withOpacity(0.1 + (_hoverController.value * 0.15)),
                      blurRadius: 20 + (_hoverController.value * 10),
                      offset: Offset(0, 8 + (_hoverController.value * 4)),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Image Section
                      Stack(
                        children: [
                          AspectRatio(
                            aspectRatio: 16 / 9,
                            child:
                                widget.event.imageUrl == null ||
                                    widget.event.imageUrl!.isEmpty
                                ? Container(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [
                                          Colors.grey.shade200,
                                          Colors.grey.shade100,
                                        ],
                                      ),
                                    ),
                                    child: Center(
                                      child: Icon(
                                        Icons.image_not_supported_rounded,
                                        size: 48,
                                        color: Colors.grey.shade400,
                                      ),
                                    ),
                                  )
                                : Image.network(
                                    widget.event.imageUrl!,
                                    fit: BoxFit.cover,
                                    filterQuality: FilterQuality
                                        .high, // Better image quality
                                    errorBuilder: (_, __, ___) => Container(
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          colors: [
                                            Colors.grey.shade200,
                                            Colors.grey.shade100,
                                          ],
                                        ),
                                      ),
                                      child: Center(
                                        child: Icon(
                                          Icons.image_not_supported_rounded,
                                          size: 48,
                                          color: Colors.grey.shade400,
                                        ),
                                      ),
                                    ),
                                  ),
                          ),

                          // Gradient Overlay
                          Positioned.fill(
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.transparent,
                                    Colors.black.withOpacity(0.3),
                                  ],
                                ),
                              ),
                            ),
                          ),

                          // Save Button
                          Positioned(
                            top: 12,
                            right: 12,
                            child: GestureDetector(
                              onTap: () => setState(() => _isSaved = !_isSaved),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: _isSaved
                                      ? const Color(0xFFEF4444)
                                      : Colors.white.withOpacity(0.9),
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.2),
                                      blurRadius: 12,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Icon(
                                  _isSaved
                                      ? Icons.favorite_rounded
                                      : Icons.favorite_border_rounded,
                                  color: _isSaved
                                      ? Colors.white
                                      : Colors.grey.shade700,
                                  size: 20,
                                ),
                              ),
                            ),
                          ),

                          // Badge - FIX #1: Smaller icon
                          Positioned(
                            bottom: 12,
                            left: 12,
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.95),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.location_on_rounded,
                                      size: 13, // FIX: Reduced from 14 to 13
                                      color: const Color(0xFF667EEA),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Wembley',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF667EEA),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),

                      // Content Section - Reduced padding for better image visibility
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Title
                            Text(
                              widget.event.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 17,
                                color: Color(0xFF0F172A),
                                letterSpacing: -0.3,
                              ),
                            ),
                            const SizedBox(height: 10),

                            // Venue - MEDIUM sized icon (13px)
                            Row(
                              children: [
                                Icon(
                                  Icons.location_on_rounded,
                                  size: 13, // Medium icon size
                                  color: Colors.grey.shade500,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    widget.event.venueName,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),

                            // Date & Time - MEDIUM sized icon (13px)
                            Row(
                              children: [
                                Icon(
                                  Icons.access_time_rounded,
                                  size: 13, // Medium icon size
                                  color: Colors.grey.shade500,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    _formatDateTime(
                                      widget.event.startDateTime,
                                      widget.event.timezone,
                                    ),
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade600,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),

                            // Address - MEDIUM sized icon (13px)
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  Icons.home_work_rounded,
                                  size: 13, // Medium icon size
                                  color: Colors.grey.shade500,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    _buildAddress(),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade600,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),

                            // Chips
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              physics: const BouncingScrollPhysics(),
                              child: Row(
                                children: [
                                  _buildChip(
                                    label: widget.event.source,
                                    icon: Icons.link_rounded,
                                    color: const Color(0xFF667EEA),
                                  ),
                                  const SizedBox(width: 6),
                                  if (widget.event.isFamilyEvent)
                                    _buildChip(
                                      label: 'Family Friendly',
                                      icon: Icons.family_restroom_rounded,
                                      color: const Color(0xFFF59E0B),
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
            );
          },
        ),
      ),
    );
  }

  Widget _buildChip({
    required String label,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.3), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color), // FIX #1: Reduced from default
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// Event Details Bottom Sheet
void showEventDetails(BuildContext context, _EventItem event) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => _EventDetailsSheet(event: event),
  );
}

class _EventDetailsSheet extends StatelessWidget {
  final _EventItem event;

  const _EventDetailsSheet({required this.event});

  // FIX #2: Open URL properly
  Future<void> _launchUrl(String? url) async {
    if (url == null || url.isEmpty) {
      print('❌ No URL available');
      return;
    }

    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        print('❌ Could not launch URL: $url');
      }
    } catch (e) {
      print('❌ Error launching URL: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.9,
      minChildSize: 0.5,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
          ),
          child: SingleChildScrollView(
            controller: scrollController,
            physics: const BouncingScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Handle
                Center(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 12, bottom: 24),
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),

                // Content
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        event.name,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // FIX #1: Reduced icon size in detail rows
                      _detailRow(
                        icon: Icons.location_on_rounded,
                        title: 'Venue',
                        content: event.venueName,
                      ),
                      const SizedBox(height: 16),
                      _detailRow(
                        icon: Icons.access_time_rounded,
                        title: 'Date & Time',
                        content: event.startDateTime != null
                            ? '${event.startDateTime!.toDate()}'
                            : 'TBA',
                      ),
                      const SizedBox(height: 16),
                      _detailRow(
                        icon: Icons.home_work_rounded,
                        title: 'Address',
                        content: '${event.addressLine1}, ${event.city}',
                      ),
                      const SizedBox(height: 24),

                      // FIX #2 & #3: Dynamic button with working URL and source detection
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            _launchUrl(event.url);
                          },
                          icon: const Icon(Icons.open_in_new_rounded),
                          label: Text(
                            'View on ${event.source}',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF667EEA),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                            elevation: 0,
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _detailRow({
    required IconData icon,
    required String title,
    required String content,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFF667EEA).withOpacity(0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            icon,
            size: 16, // Medium icon size (was 20)
            color: const Color(0xFF667EEA),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade500,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                content,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
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
