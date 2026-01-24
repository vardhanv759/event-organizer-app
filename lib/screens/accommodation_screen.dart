import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';

class AccommodationScreen extends StatefulWidget {
  const AccommodationScreen({super.key});

  @override
  State<AccommodationScreen> createState() => _AccommodationScreenState();
}

enum _AccommodationViewMode { grid, list }

class _AccommodationScreenState extends State<AccommodationScreen> {
  // IMPORTANT: Change this to your Firestore collection name if different.
  // Example alternatives you might be using: "hotels_wembley", "accommodation_wembley"
  static const String _collectionName = 'accommodations_wembley';

  double? _minRating; // null = all
  _AccommodationViewMode _viewMode = _AccommodationViewMode.grid;

  // Optional: quick “buckets” that feel like star filters
  final List<_RatingFilter> _ratingFilters = const [
    _RatingFilter(label: 'All ratings', min: null),
    _RatingFilter(label: 'Top rated (4.5+)', min: 4.5),
    _RatingFilter(label: '4★ & up (4.0+)', min: 4.0),
    _RatingFilter(label: '3★ & up (3.0+)', min: 3.0),
    _RatingFilter(label: 'Under 3★', min: -1), // handled in client filter
  ];

  Stream<QuerySnapshot<Map<String, dynamic>>> _stream() {
    // Fetch enough docs; we filter client-side for reliability and to avoid index headaches.
    return FirebaseFirestore.instance
        .collection(_collectionName)
        .orderBy('rating', descending: true)
        .limit(250)
        .snapshots();
  }

  Future<void> _openHotelLink(Map<String, dynamic> data) async {
    final website = (data['website'] as String?)?.trim();
    final placeId = (data['place_id'] as String?)?.trim();
    final name = (data['name'] as String?)?.trim();

    String url;

    if (website != null && website.isNotEmpty) {
      url = website;
    } else if (placeId != null && placeId.isNotEmpty) {
      // Opens Google Maps place page (user can click Website from there).
      final safeQuery = Uri.encodeComponent(name ?? 'hotel');
      url =
          'https://www.google.com/maps/search/?api=1&query=$safeQuery&query_place_id=$placeId';
    } else if (name != null && name.isNotEmpty) {
      // Fallback: search on Google Maps
      final safeQuery = Uri.encodeComponent('$name Wembley');
      url = 'https://www.google.com/maps/search/?api=1&query=$safeQuery';
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('No link available for this hotel.'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          margin: const EdgeInsets.all(16),
        ),
      );
      return;
    }

    final uri = Uri.parse(url);
    final ok = await launchUrl(uri, mode: LaunchMode.platformDefault);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Could not open the link.'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          margin: const EdgeInsets.all(16),
        ),
      );
    }
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _applyFilters(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    // Under 3★ special handling
    final under3 = _minRating == -1;

    if (_minRating == null) return docs;

    return docs.where((d) {
      final data = d.data();
      final ratingNum = data['rating'];
      final rating = (ratingNum is num) ? ratingNum.toDouble() : 0.0;

      if (under3) return rating < 3.0;
      return rating >= (_minRating ?? 0.0);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FF),
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverAppBar(
            pinned: true,
            stretch: true,
            expandedHeight: 180,
            elevation: 0,
            backgroundColor: Colors.transparent,
            flexibleSpace: FlexibleSpaceBar(
              background: _PremiumHeader(
                title: 'Stay Nearby',
                subtitle: 'Wembley • Verified listings • Tap to open website',
                icon: Icons.hotel_rounded,
              ),
            ),
          ),

          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            sliver: SliverToBoxAdapter(
              child: _FilterRow(
                ratingFilters: _ratingFilters,
                currentMinRating: _minRating,
                viewMode: _viewMode,
                onChangedRating: (min) => setState(() => _minRating = min),
                onChangedView: (mode) => setState(() => _viewMode = mode),
              ),
            ),
          ),

          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 110),
            sliver: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _stream(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const _SkeletonSliver();
                }

                if (snapshot.hasError) {
                  return SliverToBoxAdapter(
                    child: _EmptyStateCard(
                      title: 'Could not load hotels',
                      subtitle:
                          'Please check Firestore collection name and indexes.',
                      cta: 'Retry',
                      onTap: () => setState(() {}),
                    ),
                  );
                }

                final docs = snapshot.data?.docs ?? [];
                final filtered = _applyFilters(docs);

                if (filtered.isEmpty) {
                  return SliverToBoxAdapter(
                    child: _EmptyStateCard(
                      title: 'No matches',
                      subtitle:
                          'Try changing the star filter to see more hotels.',
                      cta: 'Show all',
                      onTap: () => setState(() => _minRating = null),
                    ),
                  );
                }

                if (_viewMode == _AccommodationViewMode.list) {
                  return SliverList.separated(
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, i) {
                      final data = filtered[i].data();
                      return _HotelListCard(
                        data: data,
                        onTap: () => _openHotelLink(data),
                      );
                    },
                  );
                }

                return SliverGrid(
                  delegate: SliverChildBuilderDelegate((context, i) {
                    final data = filtered[i].data();
                    return _HotelGridCard(
                      data: data,
                      onTap: () => _openHotelLink(data),
                    );
                  }, childCount: filtered.length),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 0.74,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _RatingFilter {
  final String label;
  final double? min;
  const _RatingFilter({required this.label, required this.min});
}

class _FilterRow extends StatelessWidget {
  final List<_RatingFilter> ratingFilters;
  final double? currentMinRating;
  final _AccommodationViewMode viewMode;
  final ValueChanged<double?> onChangedRating;
  final ValueChanged<_AccommodationViewMode> onChangedView;

  const _FilterRow({
    required this.ratingFilters,
    required this.currentMinRating,
    required this.viewMode,
    required this.onChangedRating,
    required this.onChangedView,
  });

  @override
  Widget build(BuildContext context) {
    final border = BorderRadius.circular(18);

    return Row(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: border,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 18,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<double?>(
                value: currentMinRating,
                isExpanded: true,
                icon: const Icon(Icons.keyboard_arrow_down_rounded),
                style: const TextStyle(
                  color: Color(0xFF0F172A),
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
                items: ratingFilters.map((f) {
                  return DropdownMenuItem<double?>(
                    value: f.min,
                    child: Row(
                      children: [
                        const Icon(
                          Icons.star_rounded,
                          size: 18,
                          color: Color(0xFFF59E0B),
                        ),
                        const SizedBox(width: 8),
                        Expanded(child: Text(f.label)),
                      ],
                    ),
                  );
                }).toList(),
                onChanged: onChangedRating,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: border,
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
              _MiniToggleButton(
                selected: viewMode == _AccommodationViewMode.grid,
                icon: Icons.grid_view_rounded,
                onTap: () => onChangedView(_AccommodationViewMode.grid),
              ),
              _MiniToggleButton(
                selected: viewMode == _AccommodationViewMode.list,
                icon: Icons.view_agenda_rounded,
                onTap: () => onChangedView(_AccommodationViewMode.list),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MiniToggleButton extends StatelessWidget {
  final bool selected;
  final IconData icon;
  final VoidCallback onTap;

  const _MiniToggleButton({
    required this.selected,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFEEF2FF) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Icon(
          icon,
          size: 20,
          color: selected ? const Color(0xFF4F46E5) : const Color(0xFF64748B),
        ),
      ),
    );
  }
}

class _PremiumHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;

  const _PremiumHeader({
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF0EA5E9), Color(0xFF6366F1), Color(0xFF8B5CF6)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        Positioned(
          top: -70,
          right: -60,
          child: Container(
            height: 220,
            width: 220,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withOpacity(0.10),
            ),
          ),
        ),
        Positioned(
          bottom: -90,
          left: -70,
          child: Container(
            height: 250,
            width: 250,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withOpacity(0.08),
            ),
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Spacer(),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.14),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Colors.white.withOpacity(0.22)),
                  ),
                  child: Icon(icon, color: Colors.white, size: 22),
                ),
                const SizedBox(height: 12),
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.8,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.90),
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
                const Spacer(),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _HotelGridCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final VoidCallback onTap;

  const _HotelGridCard({required this.data, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final name = (data['name'] as String?)?.trim() ?? 'Hotel';
    final vicinity = (data['vicinity'] as String?)?.trim() ?? '';
    final rating = _toDouble(data['rating']);
    final reviews = _toInt(data['user_ratings_total']);

    final imageUrl = _bestImageUrl(data);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.07),
              blurRadius: 22,
              offset: const Offset(0, 14),
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
              child: SizedBox(
                height: 120,
                width: double.infinity,
                child: imageUrl == null
                    ? _ImageFallback(title: name)
                    : CachedNetworkImage(
                        imageUrl: imageUrl,
                        fit: BoxFit.cover,
                        placeholder: (_, __) =>
                            Container(color: const Color(0xFFF1F5F9)),
                        errorWidget: (_, __, ___) =>
                            _ImageFallback(title: name),
                      ),
              ),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF0F172A),
                      fontSize: 13,
                      height: 1.15,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _Stars(rating: rating),
                      const SizedBox(width: 6),
                      Text(
                        rating <= 0 ? 'N/A' : rating.toStringAsFixed(1),
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF0F172A),
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          reviews > 0 ? '($reviews)' : '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF64748B),
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (vicinity.isNotEmpty)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.location_on_rounded,
                          size: 16,
                          color: Color(0xFF64748B),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            vicinity,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF64748B),
                              fontSize: 12,
                              height: 1.2,
                            ),
                          ),
                        ),
                      ],
                    ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF4F46E5),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.open_in_new_rounded,
                          size: 16,
                          color: Colors.white,
                        ),
                        SizedBox(width: 6),
                        Text(
                          'Open website',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 12,
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
    );
  }
}

class _HotelListCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final VoidCallback onTap;

  const _HotelListCard({required this.data, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final name = (data['name'] as String?)?.trim() ?? 'Hotel';
    final vicinity = (data['vicinity'] as String?)?.trim() ?? '';
    final rating = _toDouble(data['rating']);
    final reviews = _toInt(data['user_ratings_total']);
    final imageUrl = _bestImageUrl(data);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.07),
              blurRadius: 22,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: SizedBox(
                width: 92,
                height: 92,
                child: imageUrl == null
                    ? _ImageFallback(title: name)
                    : CachedNetworkImage(
                        imageUrl: imageUrl,
                        fit: BoxFit.cover,
                        placeholder: (_, __) =>
                            Container(color: const Color(0xFFF1F5F9)),
                        errorWidget: (_, __, ___) =>
                            _ImageFallback(title: name),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF0F172A),
                      fontSize: 14,
                      height: 1.15,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _Stars(rating: rating),
                      const SizedBox(width: 8),
                      Text(
                        rating <= 0 ? 'N/A' : rating.toStringAsFixed(1),
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF0F172A),
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        reviews > 0 ? '($reviews)' : '',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF64748B),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (vicinity.isNotEmpty)
                    Row(
                      children: [
                        const Icon(
                          Icons.location_on_rounded,
                          size: 16,
                          color: Color(0xFF64748B),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            vicinity,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF64748B),
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFEEF2FF),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(
                Icons.open_in_new_rounded,
                color: Color(0xFF4F46E5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Stars extends StatelessWidget {
  final double rating; // 0..5
  const _Stars({required this.rating});

  @override
  Widget build(BuildContext context) {
    final r = rating.clamp(0.0, 5.0);
    final full = r.floor();
    final half = (r - full) >= 0.5;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        IconData icon;
        if (i < full) {
          icon = Icons.star_rounded;
        } else if (i == full && half) {
          icon = Icons.star_half_rounded;
        } else {
          icon = Icons.star_outline_rounded;
        }
        return Icon(icon, size: 16, color: const Color(0xFFF59E0B));
      }),
    );
  }
}

class _ImageFallback extends StatelessWidget {
  final String title;
  const _ImageFallback({required this.title});

  @override
  Widget build(BuildContext context) {
    final initial = title.trim().isNotEmpty
        ? title.trim()[0].toUpperCase()
        : 'H';

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF0EA5E9), Color(0xFF6366F1)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -40,
            right: -30,
            child: Container(
              height: 140,
              width: 140,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.14),
              ),
            ),
          ),
          Center(
            child: Container(
              height: 46,
              width: 46,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.18),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withOpacity(0.22)),
              ),
              child: Center(
                child: Text(
                  initial,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyStateCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String cta;
  final VoidCallback onTap;

  const _EmptyStateCard({
    required this.title,
    required this.subtitle,
    required this.cta,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
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
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFEEF2FF),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.hotel_rounded, color: Color(0xFF4F46E5)),
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
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF64748B),
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          ElevatedButton(
            onPressed: onTap,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4F46E5),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: Text(
              cta,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }
}

class _SkeletonSliver extends StatelessWidget {
  const _SkeletonSliver();

  @override
  Widget build(BuildContext context) {
    Widget box() => Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.7),
        borderRadius: BorderRadius.circular(20),
      ),
    );

    return SliverGrid(
      delegate: SliverChildBuilderDelegate(
        (context, i) => box(),
        childCount: 6,
      ),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.74,
      ),
    );
  }
}

// ---------------- helpers ----------------

double _toDouble(dynamic v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? 0.0;
  return 0.0;
}

int _toInt(dynamic v) {
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? 0;
  return 0;
}

/// Best-effort image selection.
/// If you store `photoUrl`, this will use it.
/// (Your current sheet shows `photo_references`, but those need a Google API key
/// to convert to a real photo URL, so we cannot reliably build that here.)
String? _bestImageUrl(Map<String, dynamic> data) {
  final photoUrl = (data['photoUrl'] as String?)?.trim();
  if (photoUrl != null && photoUrl.isNotEmpty) return photoUrl;

  final image = (data['imageUrl'] as String?)?.trim();
  if (image != null && image.isNotEmpty) return image;

  // If you later store computed photo URLs, add more keys here.
  return null;
}
