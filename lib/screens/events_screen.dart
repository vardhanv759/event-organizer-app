import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import 'package:url_launcher/url_launcher.dart';

/// ===============================
/// EVENTS (Wembley) - Premium UI
/// ===============================
/// Today's Events: List View
/// Future Events: Grid View (2 per row)
class EventsListScreen extends StatefulWidget {
  // Parameters for auto-showing event detail from search
  final String? autoShowEventId;
  final Map<String, dynamic>? autoShowEventData;

  const EventsListScreen({
    super.key,
    this.autoShowEventId,
    this.autoShowEventData,
  });

  @override
  State<EventsListScreen> createState() => _EventsListScreenState();
}

class _EventsListScreenState extends State<EventsListScreen>
    with TickerProviderStateMixin {
  String _selectedCategory = 'All Categories';
  String _searchQuery = '';

  // You can add/remove categories any time.
  final List<String> _categories = const [
    'All Categories',
    'Sports',
    'Music',
    'Live Concerts',
    'Comedy',
    'Family',
    'Performance',
    'Theatre',
    'Festivals',
  ];

  @override
  void initState() {
    super.initState();

    // Auto-show event detail if data is provided from search
    if (widget.autoShowEventId != null && widget.autoShowEventData != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _autoShowEventDetail();
      });
    }
  }

  void _autoShowEventDetail() {
    if (widget.autoShowEventData == null) return;

    try {
      // Create _EventItem from the search result data
      final data = widget.autoShowEventData!;

      final eventItem = _EventItem(
        id: data['id']?.toString() ?? widget.autoShowEventId ?? '',
        title: data['title']?.toString() ?? 'Event',
        subtitle: data['subtitle']?.toString() ?? '',
        category: data['category']?.toString() ?? '',
        venueName:
            data['venueName']?.toString() ?? data['venue']?.toString() ?? '',
        city: data['city']?.toString() ?? '',
        address: data['address']?.toString() ?? '',
        start: data['start'] is Timestamp
            ? (data['start'] as Timestamp).toDate()
            : data['start'] is DateTime
            ? data['start'] as DateTime
            : null,
        imageUrl:
            data['imageUrl']?.toString() ?? data['photoUrl']?.toString() ?? '',
        url: data['url']?.toString() ?? '',
        source: data['source']?.toString() ?? 'search',
      );

      // Call the existing showEventDetails function
      showEventDetails(context, eventItem);
    } catch (e) {
      debugPrint('Error auto-showing event: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not load event details'),
            backgroundColor: Color(0xFFEF4444),
          ),
        );
      }
    }
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _eventsStream() {
    final now = Timestamp.now();
    final oneYearLater = Timestamp.fromDate(
      DateTime.now().add(const Duration(days: 365)),
    );

    return FirebaseFirestore.instance
        .collection('events_wembley')
        .where('startDateTime', isGreaterThanOrEqualTo: now)
        .where('startDateTime', isLessThanOrEqualTo: oneYearLater)
        .orderBy('startDateTime')
        .limit(200)
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // AppBar with only category dropdown (no grid/list toggle)
          SliverAppBar(
            pinned: true,
            elevation: 0,
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.white,
            toolbarHeight: 76,
            titleSpacing: 16,
            title: _CategoryDropdown(
              selectedCategory: _selectedCategory,
              categories: _categories,
              onCategoryChanged: (v) {
                setState(() => _selectedCategory = v);
              },
            ),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(92),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                child: _SearchBar(
                  value: _searchQuery,
                  onChanged: (v) => setState(() => _searchQuery = v),
                  onClear: () => setState(() => _searchQuery = ''),
                ),
              ),
            ),
          ),

          // "What's On" header
          SliverToBoxAdapter(
            child: Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    'Home',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF64748B),
                    ),
                  ),
                  Text(
                    'Browse upcoming events with verified listings.',
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.35,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF475569),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Events Stream with Today's (List) and Future (Grid) sections
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 110),
            sliver: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _eventsStream(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const _ListSkeletonSliver();
                }

                if (snapshot.hasError) {
                  return SliverToBoxAdapter(
                    child: _StateCard(
                      icon: Icons.error_outline_rounded,
                      title: 'Unable to load events',
                      subtitle:
                          'Please check your connection and try again.\n\n${snapshot.error}',
                      tone: _StateCardTone.danger,
                    ),
                  );
                }

                final docs = snapshot.data?.docs ?? [];
                if (docs.isEmpty) {
                  return const SliverToBoxAdapter(
                    child: _StateCard(
                      icon: Icons.event_busy_rounded,
                      title: 'No events found',
                      subtitle:
                          'Try a different category or check again later.',
                      tone: _StateCardTone.neutral,
                    ),
                  );
                }

                final events = docs.map((d) => _EventItem.fromDoc(d)).toList();
                final filtered = _applyFilters(events);

                if (filtered.isEmpty) {
                  return const SliverToBoxAdapter(
                    child: _StateCard(
                      icon: Icons.manage_search_rounded,
                      title: 'No matches',
                      subtitle:
                          'No events match your filters/search. Try clearing search or changing category.',
                      tone: _StateCardTone.neutral,
                    ),
                  );
                }

                // Split events into Today's and Future
                final now = DateTime.now();
                final todayStart = DateTime(now.year, now.month, now.day);
                final todayEnd = todayStart.add(const Duration(days: 1));

                final todaysEvents = filtered.where((e) {
                  if (e.start == null) return false;
                  return e.start!.isAfter(
                        todayStart.subtract(const Duration(seconds: 1)),
                      ) &&
                      e.start!.isBefore(todayEnd);
                }).toList();

                final futureEvents = filtered.where((e) {
                  if (e.start == null) return true; // TBA events go to future
                  return e.start!.isAfter(
                    todayEnd.subtract(const Duration(seconds: 1)),
                  );
                }).toList();

                // Build sections
                return SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      // Today's Events Section (List View)
                      if (index == 0 && todaysEvents.isNotEmpty) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _SectionHeader(
                              title: "Today's Events",
                              subtitle:
                                  '${todaysEvents.length} event${todaysEvents.length == 1 ? '' : 's'} happening today',
                            ),
                            const SizedBox(height: 12),
                            // List View for Today's Events
                            ListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: todaysEvents.length,
                              itemBuilder: (context, idx) {
                                final e = todaysEvents[idx];
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 14),
                                  child: _EventListCard(
                                    event: e,
                                    onTap: () => showEventDetails(context, e),
                                  ),
                                );
                              },
                            ),
                            const SizedBox(height: 26),
                          ],
                        );
                      }

                      // Future Events Section (Grid View)
                      final adjustedIndex = todaysEvents.isEmpty
                          ? index
                          : index - 1;
                      if (adjustedIndex == 0 && futureEvents.isNotEmpty) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _SectionHeader(
                              title: 'Future Events',
                              subtitle:
                                  '${futureEvents.length} upcoming event${futureEvents.length == 1 ? '' : 's'}',
                            ),
                            const SizedBox(height: 6),
                            // Grid View for Future Events (2 per row)
                            GridView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 2,
                                    mainAxisSpacing: 14,
                                    crossAxisSpacing: 14,
                                    childAspectRatio: 0.68,
                                  ),
                              itemCount: futureEvents.length,
                              itemBuilder: (context, idx) {
                                final e = futureEvents[idx];
                                return _EventGridCard(
                                  event: e,
                                  onTap: () => showEventDetails(context, e),
                                );
                              },
                            ),
                          ],
                        );
                      }

                      // No events message
                      if (todaysEvents.isEmpty && futureEvents.isEmpty) {
                        return const _StateCard(
                          icon: Icons.event_busy_rounded,
                          title: 'No events found',
                          subtitle: 'Check back later for upcoming events.',
                          tone: _StateCardTone.neutral,
                        );
                      }

                      return const SizedBox.shrink();
                    },
                    childCount:
                        (todaysEvents.isEmpty ? 0 : 1) +
                        (futureEvents.isEmpty ? 0 : 1),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  List<_EventItem> _applyFilters(List<_EventItem> events) {
    final q = _searchQuery.trim().toLowerCase();
    final cat = _selectedCategory.trim().toLowerCase();

    return events.where((e) {
      final matchesCategory = (cat == 'all categories')
          ? true
          : e.category.toLowerCase() == cat;

      final matchesSearch = q.isEmpty
          ? true
          : (e.title.toLowerCase().contains(q) ||
                e.subtitle.toLowerCase().contains(q) ||
                e.venueName.toLowerCase().contains(q));

      return matchesCategory && matchesSearch;
    }).toList();
  }
}

/// ===============================
/// Section Header Widget
/// ===============================
class _SectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;

  const _SectionHeader({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 4,
                height: 24,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF16A34A), Color(0xFF0F766E)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF0F172A),
                  letterSpacing: -0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 14),
            child: Text(
              subtitle,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF64748B),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// ===============================
/// Category Dropdown (no toggle)
/// ===============================
class _CategoryDropdown extends StatelessWidget {
  final String selectedCategory;
  final List<String> categories;
  final ValueChanged<String> onCategoryChanged;

  const _CategoryDropdown({
    required this.selectedCategory,
    required this.categories,
    required this.onCategoryChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1.2),
      ),
      child: Row(
        children: [
          const Icon(Icons.tune_rounded, size: 18, color: Color(0xFF0F172A)),
          const SizedBox(width: 10),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                isExpanded: true,
                value: selectedCategory,
                icon: const Icon(Icons.keyboard_arrow_down_rounded),
                items: categories
                    .map(
                      (c) => DropdownMenuItem(
                        value: c,
                        child: Text(
                          c,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  if (v != null) onCategoryChanged(v);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// ===============================
/// Search
/// ===============================
class _SearchBar extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  const _SearchBar({
    required this.value,
    required this.onChanged,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1.2),
      ),
      child: Row(
        children: [
          const Icon(Icons.search_rounded, color: Color(0xFF64748B)),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              onChanged: onChanged,
              controller: TextEditingController(text: value)
                ..selection = TextSelection.collapsed(offset: value.length),
              decoration: const InputDecoration(
                border: InputBorder.none,
                hintText: 'Search events, venue, keywords…',
                hintStyle: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF94A3B8),
                ),
              ),
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: Color(0xFF0F172A),
              ),
            ),
          ),
          if (value.trim().isNotEmpty)
            IconButton(
              onPressed: onClear,
              icon: const Icon(Icons.close_rounded),
              color: const Color(0xFF64748B),
              tooltip: 'Clear',
            ),
        ],
      ),
    );
  }
}

/// ===============================
/// Models
/// ===============================
class _EventItem {
  final String id;
  final String title;
  final String subtitle;
  final String category;
  final String venueName;
  final String city;
  final String address;
  final DateTime? start;
  final String imageUrl;
  final String url;
  final String source;

  _EventItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.category,
    required this.venueName,
    required this.city,
    required this.address,
    required this.start,
    required this.imageUrl,
    required this.url,
    required this.source,
  });

  factory _EventItem.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? <String, dynamic>{};

    String pickString(List<String> keys, {String fallback = ''}) {
      for (final k in keys) {
        final v = d[k];
        if (v is String && v.trim().isNotEmpty) return v.trim();
      }
      return fallback;
    }

    final ts = d['startDateTime'];
    DateTime? start;
    if (ts is Timestamp) start = ts.toDate();

    final title = pickString(['title', 'name'], fallback: 'Unnamed event');
    final subtitle = pickString([
      'subtitle',
      'tagline',
      'descriptionShort',
    ], fallback: pickString(['venueName'], fallback: ''));

    final rawCategory = pickString([
      'category',
      'classificationName',
      'segment',
    ]);

    final category = rawCategory.isEmpty ? 'General' : rawCategory;

    return _EventItem(
      id: doc.id,
      title: title,
      subtitle: subtitle,
      category: category,
      venueName: pickString(['venueName', 'venue'], fallback: 'Wembley'),
      city: pickString(['city'], fallback: 'London'),
      address: pickString(['address'], fallback: ''),
      start: start,
      imageUrl: pickString(['photoUrl', 'imageUrl']),
      url: pickString(['url'], fallback: ''),
      source: d['source']?.toString() ?? 'firebase',
    );
  }
}

/// ===============================
/// Grid Card (for Future Events)
/// ===============================
class _EventGridCard extends StatelessWidget {
  final _EventItem event;
  final VoidCallback onTap;

  const _EventGridCard({required this.event, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
              child: event.imageUrl.isEmpty
                  ? Container(
                      height: 140,
                      color: const Color(0xFFE2E8F0),
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.event_rounded,
                        size: 46,
                        color: Color(0xFF94A3B8),
                      ),
                    )
                  : CachedNetworkImage(
                      imageUrl: event.imageUrl,
                      height: 140,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => Container(
                        height: 140,
                        color: const Color(0xFFE2E8F0),
                      ),
                      errorWidget: (context, url, error) => Container(
                        height: 140,
                        color: const Color(0xFFE2E8F0),
                        alignment: Alignment.center,
                        child: const Icon(
                          Icons.broken_image_rounded,
                          size: 40,
                          color: Color(0xFF94A3B8),
                        ),
                      ),
                    ),
            ),

            // Content
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Category Badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0FDF4),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFF86EFAC)),
                      ),
                      child: Text(
                        event.category.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF16A34A),
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),

                    const SizedBox(height: 8),

                    // Title
                    Text(
                      event.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF0F172A),
                        height: 1.2,
                        letterSpacing: -0.3,
                      ),
                    ),

                    const Spacer(),

                    // Date
                    Row(
                      children: [
                        const Icon(
                          Icons.calendar_today_rounded,
                          size: 12,
                          color: Color(0xFF64748B),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _formatDateLine(event.start),
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF64748B),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
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

/// ===============================
/// List Card (for Today's Events)
/// ===============================
class _EventListCard extends StatelessWidget {
  final _EventItem event;
  final VoidCallback onTap;

  const _EventListCard({required this.event, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 120,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            // Image
            ClipRRect(
              borderRadius: const BorderRadius.horizontal(
                left: Radius.circular(20),
              ),
              child: event.imageUrl.isEmpty
                  ? Container(
                      width: 120,
                      color: const Color(0xFFE2E8F0),
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.event_rounded,
                        size: 40,
                        color: Color(0xFF94A3B8),
                      ),
                    )
                  : CachedNetworkImage(
                      imageUrl: event.imageUrl,
                      width: 120,
                      height: 120,
                      fit: BoxFit.cover,
                      placeholder: (context, url) =>
                          Container(width: 120, color: const Color(0xFFE2E8F0)),
                      errorWidget: (context, url, error) => Container(
                        width: 120,
                        color: const Color(0xFFE2E8F0),
                        alignment: Alignment.center,
                        child: const Icon(
                          Icons.broken_image_rounded,
                          size: 32,
                          color: Color(0xFF94A3B8),
                        ),
                      ),
                    ),
            ),

            // Content
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Category Badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0FDF4),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFF86EFAC)),
                      ),
                      child: Text(
                        event.category.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF16A34A),
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),

                    const SizedBox(height: 8),

                    // Title
                    Text(
                      event.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF0F172A),
                        height: 1.2,
                        letterSpacing: -0.3,
                      ),
                    ),

                    const Spacer(),

                    // Date + Venue
                    Row(
                      children: [
                        const Icon(
                          Icons.calendar_today_rounded,
                          size: 12,
                          color: Color(0xFF64748B),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _formatDateLine(event.start),
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF64748B),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(width: 8),

            // Arrow
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: Icon(
                Icons.arrow_forward_ios_rounded,
                size: 16,
                color: Color(0xFF94A3B8),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// ===============================
/// Bottom Sheet - Event Detail
/// ===============================
void showEventDetails(BuildContext context, _EventItem event) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => _EventDetailSheet(event: event),
  );
}

class _EventDetailSheet extends StatelessWidget {
  final _EventItem event;

  const _EventDetailSheet({required this.event});

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            children: [
              // Drag handle
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFE2E8F0),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(20),
                  children: [
                    // Image Hero
                    ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: event.imageUrl.isEmpty
                          ? Container(
                              height: 220,
                              color: const Color(0xFFE2E8F0),
                              alignment: Alignment.center,
                              child: const Icon(
                                Icons.event_rounded,
                                size: 64,
                                color: Color(0xFF94A3B8),
                              ),
                            )
                          : CachedNetworkImage(
                              imageUrl: event.imageUrl,
                              height: 220,
                              width: double.infinity,
                              fit: BoxFit.cover,
                              placeholder: (context, url) => Container(
                                height: 220,
                                color: const Color(0xFFE2E8F0),
                              ),
                              errorWidget: (context, url, error) => Container(
                                height: 220,
                                color: const Color(0xFFE2E8F0),
                                alignment: Alignment.center,
                                child: const Icon(
                                  Icons.broken_image_rounded,
                                  size: 48,
                                  color: Color(0xFF94A3B8),
                                ),
                              ),
                            ),
                    ),

                    const SizedBox(height: 20),

                    // Category Badge
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF0FDF4),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFF86EFAC)),
                        ),
                        child: Text(
                          event.category.toUpperCase(),
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF16A34A),
                            letterSpacing: 0.6,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 14),

                    // Title
                    Text(
                      event.title,
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF0F172A),
                        height: 1.2,
                        letterSpacing: -0.6,
                      ),
                    ),

                    if (event.subtitle.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        event.subtitle,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF64748B),
                          height: 1.4,
                        ),
                      ),
                    ],

                    const SizedBox(height: 24),

                    // Info Grid
                    _InfoRow(
                      label: 'Date',
                      value: _formatDateLine(event.start),
                    ),
                    const SizedBox(height: 14),
                    _InfoRow(
                      label: 'Venue',
                      value: event.venueName.isEmpty ? 'TBA' : event.venueName,
                    ),
                    const SizedBox(height: 14),
                    _InfoRow(
                      label: 'Location',
                      value: event.city.isEmpty
                          ? 'London'
                          : '${event.city}, UK',
                    ),
                    if (event.address.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      _InfoRow(label: 'Address', value: event.address),
                    ],

                    const SizedBox(height: 28),

                    // Tags
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        _Tag(
                          text: event.category,
                          icon: Icons.category_rounded,
                        ),
                        if (event.venueName.isNotEmpty)
                          _Tag(
                            text: event.venueName,
                            icon: Icons.location_on_rounded,
                          ),
                      ],
                    ),

                    const SizedBox(height: 28),

                    // Book button
                    if (event.url.isNotEmpty)
                      SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: ElevatedButton(
                          onPressed: () async {
                            final uri = Uri.tryParse(event.url);
                            if (uri != null && await canLaunchUrl(uri)) {
                              await launchUrl(
                                uri,
                                mode: LaunchMode.externalApplication,
                              );
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF111827),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.confirmation_number_rounded, size: 20),
                              SizedBox(width: 10),
                              Text(
                                'Get Tickets',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF94A3B8),
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value.trim().isEmpty ? 'TBA' : value,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A),
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final String text;
  final IconData icon;

  const _Tag({required this.text, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: const Color(0xFF64748B)),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              color: Color(0xFF334155),
            ),
          ),
        ],
      ),
    );
  }
}

/// ===============================
/// Skeletons + State cards
/// ===============================
class _GridSkeletonSliver extends StatelessWidget {
  const _GridSkeletonSliver();

  @override
  Widget build(BuildContext context) {
    return SliverGrid(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 14,
        crossAxisSpacing: 14,
        childAspectRatio: 0.68,
      ),
      delegate: SliverChildBuilderDelegate(
        (context, index) => Shimmer.fromColors(
          baseColor: const Color(0xFFE2E8F0),
          highlightColor: const Color(0xFFF8FAFC),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFFE2E8F0),
              borderRadius: BorderRadius.circular(20),
            ),
          ),
        ),
        childCount: 6,
      ),
    );
  }
}

class _ListSkeletonSliver extends StatelessWidget {
  const _ListSkeletonSliver();

  @override
  Widget build(BuildContext context) {
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) => Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Shimmer.fromColors(
            baseColor: const Color(0xFFE2E8F0),
            highlightColor: const Color(0xFFF8FAFC),
            child: Container(
              height: 120,
              decoration: BoxDecoration(
                color: const Color(0xFFE2E8F0),
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ),
        ),
        childCount: 6,
      ),
    );
  }
}

enum _StateCardTone { neutral, danger }

class _StateCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final _StateCardTone tone;

  const _StateCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.tone,
  });

  @override
  Widget build(BuildContext context) {
    final isDanger = tone == _StateCardTone.danger;
    final bg = isDanger ? const Color(0xFFFEF2F2) : Colors.white;
    final iconColor = isDanger
        ? const Color(0xFFEF4444)
        : const Color(0xFF111827);

    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 16,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Icon(icon, color: iconColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF0F172A),
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF64748B),
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// ===============================
/// Title styling helper
/// ===============================
class _GradientTitle extends StatelessWidget {
  final String text;

  const _GradientTitle({required this.text});

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback: (rect) => const LinearGradient(
        colors: [Color(0xFF16A34A), Color(0xFF0F766E)],
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
      ).createShader(rect),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 44,
          fontWeight: FontWeight.w900,
          color: Colors.white,
          letterSpacing: -1.2,
        ),
      ),
    );
  }
}

/// ===============================
/// Date formatting (no intl needed)
/// ===============================
String _formatDateLine(DateTime? dt) {
  if (dt == null) return 'Date TBA';

  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  final dd = dt.day.toString().padLeft(2, '0');
  final m = months[(dt.month - 1).clamp(0, 11)];
  final yyyy = dt.year.toString();

  // Matches your screenshot style (e.g., "16 Jan / 2026")
  return '$dd  $m / $yyyy';
}
