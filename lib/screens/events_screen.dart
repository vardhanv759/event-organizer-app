// lib/screens/events_screen.dart
import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import 'package:url_launcher/url_launcher.dart';

/// ===============================
/// EVENTS (Wembley) - Premium UI
/// ===============================
/// Matches: category dropdown + grid/list toggle + 2 cards per row
class EventsListScreen extends StatefulWidget {
  const EventsListScreen({super.key});

  @override
  State<EventsListScreen> createState() => _EventsListScreenState();
}

class _EventsListScreenState extends State<EventsListScreen>
    with TickerProviderStateMixin {
  String _selectedCategory = 'All Categories';
  bool _isGrid = true;
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
          SliverAppBar(
            pinned: true,
            elevation: 0,
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.white,
            toolbarHeight: 76,
            titleSpacing: 16,
            title: _TopBar(
              isGrid: _isGrid,
              selectedCategory: _selectedCategory,
              categories: _categories,
              onCategoryChanged: (v) {
                setState(() => _selectedCategory = v);
              },
              onGridTap: () => setState(() => _isGrid = true),
              onListTap: () => setState(() => _isGrid = false),
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

          // “What’s On” header like screenshot
          SliverToBoxAdapter(
            child: Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Home',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF64748B),
                    ),
                  ),
                  const Text(
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

          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 110),
            sliver: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _eventsStream(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return _isGrid
                      ? const _GridSkeletonSliver()
                      : const _ListSkeletonSliver();
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

                if (_isGrid) {
                  // Always 2 per row as requested.
                  return SliverGrid(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: 14,
                          crossAxisSpacing: 14,
                          childAspectRatio: 0.76,
                        ),
                    delegate: SliverChildBuilderDelegate((context, index) {
                      final e = filtered[index];
                      return _EventGridCard(
                        event: e,
                        onTap: () => showEventDetails(context, e),
                      );
                    }, childCount: filtered.length),
                  );
                }

                // List mode
                return SliverList(
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final e = filtered[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: _EventListCard(
                        event: e,
                        onTap: () => showEventDetails(context, e),
                      ),
                    );
                  }, childCount: filtered.length),
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
/// Top filter row (dropdown + grid/list toggle)
/// ===============================
class _TopBar extends StatelessWidget {
  final bool isGrid;
  final String selectedCategory;
  final List<String> categories;
  final ValueChanged<String> onCategoryChanged;
  final VoidCallback onGridTap;
  final VoidCallback onListTap;

  const _TopBar({
    required this.isGrid,
    required this.selectedCategory,
    required this.categories,
    required this.onCategoryChanged,
    required this.onGridTap,
    required this.onListTap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Dropdown (like screenshot)
        Expanded(
          child: Container(
            height: 46,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE2E8F0), width: 1.2),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.tune_rounded,
                  size: 18,
                  color: Color(0xFF0F172A),
                ),
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
          ),
        ),

        const SizedBox(width: 12),

        // Grid / List toggle
        Container(
          height: 46,
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE2E8F0), width: 1.2),
          ),
          child: Row(
            children: [
              _ToggleIconButton(
                icon: Icons.grid_view_rounded,
                selected: isGrid,
                onTap: onGridTap,
              ),
              _ToggleIconButton(
                icon: Icons.view_list_rounded,
                selected: !isGrid,
                onTap: onListTap,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ToggleIconButton extends StatelessWidget {
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _ToggleIconButton({
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 48,
        height: 46,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF111827) : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(
          icon,
          size: 20,
          color: selected ? Colors.white : const Color(0xFF334155),
        ),
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
      'type',
    ], fallback: 'All Categories');

    final venue = pickString([
      'venueName',
      'venue',
      'locationName',
    ], fallback: 'Venue TBA');
    final city = pickString(['city'], fallback: 'London');

    final a1 = pickString(['addressLine1', 'address1'], fallback: '');
    final a2 = pickString(['addressLine2', 'address2'], fallback: '');
    final pc = pickString(['postalCode', 'postcode'], fallback: '');
    final addressParts = [
      a1,
      a2,
      city,
      pc,
    ].where((e) => e.trim().isNotEmpty).toList();
    final address = addressParts.isEmpty
        ? 'Wembley, London'
        : addressParts.join(', ');

    final imageUrl = pickString([
      'imageUrl',
      'thumbnailUrl',
      'image',
      'bannerUrl',
    ], fallback: '');

    final url = pickString(['url', 'ticketUrl', 'externalUrl'], fallback: '');
    final source = pickString(['source'], fallback: 'Ticketmaster');

    return _EventItem(
      id: pickString(['id'], fallback: doc.id),
      title: title,
      subtitle: subtitle,
      category: _normalizeCategory(rawCategory),
      venueName: venue,
      city: city,
      address: address,
      start: start,
      imageUrl: imageUrl,
      url: url,
      source: source,
    );
  }

  static String _normalizeCategory(String input) {
    final v = input.trim();
    if (v.isEmpty) return 'All Categories';

    // Normalize common variants to match dropdown labels.
    final lower = v.toLowerCase();
    if (lower.contains('sport')) return 'Sports';
    if (lower.contains('music')) return 'Music';
    if (lower.contains('concert')) return 'Live Concerts';
    if (lower.contains('comedy')) return 'Comedy';
    if (lower.contains('family')) return 'Family';
    if (lower.contains('theatre') || lower.contains('theater'))
      return 'Theatre';
    if (lower.contains('festival')) return 'Festivals';
    if (lower.contains('performance')) return 'Performance';

    // Title-case fallback
    return v;
  }
}

/// ===============================
/// Cards
/// ===============================
class _EventGridCard extends StatelessWidget {
  final _EventItem event;
  final VoidCallback onTap;

  const _EventGridCard({required this.event, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final dateLine = _formatDateLine(event.start);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 18,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Image
              AspectRatio(
                aspectRatio: 16 / 9,
                child: _EventImage(url: event.imageUrl),
              ),

              // Content
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _DateLine(text: dateLine),
                    const SizedBox(height: 10),
                    Text(
                      event.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.2,
                        color: Color(0xFF0F172A),
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      event.subtitle.isNotEmpty
                          ? event.subtitle
                          : event.venueName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF64748B),
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        _Pill(
                          icon: Icons.category_rounded,
                          text: event.category,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _Pill(
                            icon: Icons.location_on_rounded,
                            text: 'Wembley',
                            truncate: true,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EventListCard extends StatelessWidget {
  final _EventItem event;
  final VoidCallback onTap;

  const _EventListCard({required this.event, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final dateLine = _formatDateLine(event.start);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 18,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Row(
            children: [
              SizedBox(
                width: 150,
                child: AspectRatio(
                  aspectRatio: 4 / 3,
                  child: _EventImage(url: event.imageUrl),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _DateLine(text: dateLine),
                      const SizedBox(height: 10),
                      Text(
                        event.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.2,
                          color: Color(0xFF0F172A),
                          height: 1.15,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        event.subtitle.isNotEmpty
                            ? event.subtitle
                            : event.venueName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF64748B),
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _Pill(
                              icon: Icons.category_rounded,
                              text: event.category,
                              truncate: true,
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
      ),
    );
  }
}

class _EventImage extends StatelessWidget {
  final String url;

  const _EventImage({required this.url});

  @override
  Widget build(BuildContext context) {
    if (url.trim().isEmpty) {
      return Container(
        color: const Color(0xFFF1F5F9),
        child: const Center(
          child: Icon(
            Icons.image_not_supported_rounded,
            color: Color(0xFF94A3B8),
          ),
        ),
      );
    }

    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      fadeInDuration: const Duration(milliseconds: 180),
      placeholder: (_, __) => Shimmer.fromColors(
        baseColor: const Color(0xFFE2E8F0),
        highlightColor: const Color(0xFFF8FAFC),
        child: Container(color: const Color(0xFFE2E8F0)),
      ),
      errorWidget: (_, __, ___) => Container(
        color: const Color(0xFFF1F5F9),
        child: const Center(
          child: Icon(Icons.broken_image_rounded, color: Color(0xFF94A3B8)),
        ),
      ),
    );
  }
}

class _DateLine extends StatelessWidget {
  final String text;

  const _DateLine({required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(
          Icons.calendar_month_rounded,
          size: 16,
          color: Color(0xFF64748B),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: Color(0xFF334155),
            ),
          ),
        ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  final IconData icon;
  final String text;
  final bool truncate;

  const _Pill({required this.icon, required this.text, this.truncate = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: const Color(0xFF64748B)),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: truncate ? TextOverflow.ellipsis : TextOverflow.clip,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w900,
                color: Color(0xFF334155),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// ===============================
/// Bottom sheet (details)
/// ===============================
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

  Future<void> _launchExternalUrl(String url) async {
    if (url.trim().isEmpty) return;

    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {
      // silent fail
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateLine = _formatDateLine(event.start);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.74,
      maxChildSize: 0.92,
      minChildSize: 0.52,
      builder: (context, scrollController) {
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              color: Colors.white,
              child: SingleChildScrollView(
                controller: scrollController,
                physics: const BouncingScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // handle
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 12, bottom: 16),
                        child: Container(
                          width: 44,
                          height: 4,
                          decoration: BoxDecoration(
                            color: const Color(0xFFE2E8F0),
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                      ),
                    ),

                    // Hero image
                    AspectRatio(
                      aspectRatio: 16 / 9,
                      child: _EventImage(url: event.imageUrl),
                    ),

                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 22),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            event.title,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF0F172A),
                              letterSpacing: -0.4,
                              height: 1.15,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            event.subtitle.isNotEmpty
                                ? event.subtitle
                                : event.venueName,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF64748B),
                              height: 1.3,
                            ),
                          ),
                          const SizedBox(height: 16),

                          _DetailRow(
                            icon: Icons.calendar_month_rounded,
                            label: 'Date',
                            value: dateLine,
                          ),
                          const SizedBox(height: 12),
                          _DetailRow(
                            icon: Icons.location_on_rounded,
                            label: 'Venue',
                            value: event.venueName,
                          ),
                          const SizedBox(height: 12),
                          _DetailRow(
                            icon: Icons.home_work_rounded,
                            label: 'Address',
                            value: event.address,
                          ),
                          const SizedBox(height: 16),

                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              _Tag(
                                text: event.category,
                                icon: Icons.category_rounded,
                              ),
                              _Tag(
                                text: event.source,
                                icon: Icons.link_rounded,
                              ),
                              const _Tag(
                                text: 'Wembley',
                                icon: Icons.verified_rounded,
                              ),
                            ],
                          ),

                          const SizedBox(height: 18),

                          SizedBox(
                            width: double.infinity,
                            height: 54,
                            child: ElevatedButton.icon(
                              onPressed: event.url.trim().isEmpty
                                  ? null
                                  : () => _launchExternalUrl(event.url),
                              icon: const Icon(Icons.open_in_new_rounded),
                              label: Text(
                                'View on ${event.source}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF111827),
                                foregroundColor: Colors.white,
                                disabledBackgroundColor: const Color(
                                  0xFFE2E8F0,
                                ),
                                disabledForegroundColor: const Color(
                                  0xFF94A3B8,
                                ),
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          SizedBox(
                            width: double.infinity,
                            child: Text(
                              'Tip: In future, we can add “Save”, “Share”, and “Add to calendar”.',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF94A3B8),
                              ),
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
        );
      },
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
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, size: 18, color: const Color(0xFF334155)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label.toUpperCase(),
                style: const TextStyle(
                  fontSize: 11,
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
          const SizedBox(width: 8),
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
        childAspectRatio: 0.76,
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
