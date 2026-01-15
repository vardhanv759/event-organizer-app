import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';

class DiningPlace {
  final String id;
  final String name;
  final String? placeId;
  final String? source;
  final String? address;
  final String? phone;
  final double? rating;
  final int? userRatingsTotal;
  final int? priceLevel;
  final double? latitude;
  final double? longitude;
  final String? types;
  final String? cuisine;
  final bool? openNow;
  final String? photoReference;
  final String? photoUrl;
  final String? website;
  final List<String>? photos;

  DiningPlace({
    required this.id,
    required this.name,
    this.placeId,
    this.source,
    this.address,
    this.phone,
    this.rating,
    this.userRatingsTotal,
    this.priceLevel,
    this.latitude,
    this.longitude,
    this.types,
    this.cuisine,
    this.openNow,
    this.photoReference,
    this.photoUrl,
    this.website,
    this.photos,
  });

  factory DiningPlace.fromFirestore(DocumentSnapshot doc) {
    final data = (doc.data() as Map<String, dynamic>?) ?? {};

    String? _getString(List<String> keys) {
      for (final k in keys) {
        if (data.containsKey(k) && data[k] != null) {
          return data[k].toString();
        }
      }
      return null;
    }

    num? _getNum(List<String> keys) {
      for (final k in keys) {
        if (data.containsKey(k) && data[k] is num) {
          return data[k] as num;
        }
      }
      return null;
    }

    bool? _getBool(List<String> keys) {
      for (final k in keys) {
        if (data.containsKey(k)) {
          final v = data[k];
          if (v is bool) return v;
          if (v is num) return v != 0;
          if (v is String) {
            if (v.toLowerCase() == 'true') return true;
            if (v.toLowerCase() == 'false') return false;
          }
        }
      }
      return null;
    }

    return DiningPlace(
      id: _getString(['id']) ?? doc.id,
      name: _getString(['name']) ?? 'Unknown',
      placeId: _getString(['placeId', 'place id']),
      source: _getString(['source']),
      address: _getString(['address', 'formatted_address']),
      phone: _getString(['phone', 'international_phone_number']),
      rating: _getNum(['rating'])?.toDouble(),
      userRatingsTotal: _getNum([
        'userRatingsTotal',
        'user_ratings_total',
      ])?.toInt(),
      priceLevel: _getNum(['priceLevel', 'price_level'])?.toInt(),
      latitude: _getNum(['latitude', 'lat'])?.toDouble(),
      longitude: _getNum(['longitude', 'lng'])?.toDouble(),
      types: _getString(['types']),
      cuisine: _getString(['cuisine', 'cuisineType']),
      openNow: _getBool(['openNow', 'open_now']),
      photoReference: _getString(['photoReference', 'photo_reference']),
      photoUrl: _getString(['photoUrl']),
      website: _getString(['website']),
      photos: (data['photos'] as List?)?.cast<String>(),
    );
  }

  String getPriceDisplay() {
    switch (priceLevel) {
      case 1:
        return '\$';
      case 2:
        return '\$\$';
      case 3:
        return '\$\$\$';
      case 4:
        return '\$\$\$\$';
      default:
        return 'N/A';
    }
  }

  bool get hasHighRating => (rating ?? 0) >= 4.5;
  bool get isPopular => (userRatingsTotal ?? 0) >= 100;
  bool get hasPhoto => (photoUrl ?? '').trim().isNotEmpty;
}

class AdvancedDiningScreen extends StatefulWidget {
  const AdvancedDiningScreen({Key? key}) : super(key: key);

  @override
  State<AdvancedDiningScreen> createState() => _AdvancedDiningScreenState();
}

class _AdvancedDiningScreenState extends State<AdvancedDiningScreen> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  Position? _currentPosition;
  bool _locationDenied = false;

  String _searchQuery = '';
  String? _selectedCuisine;
  int? _selectedPriceLevel;
  double? _minRating;
  String _sortBy = 'distance'; // distance, rating, name

  // Nearby filter is opt-in to avoid "blank list" when location is enabled.
  bool _nearbyOnly = false;
  double _nearbyRadiusKm = 5.0;

  // UI: Grid/List toggle
  bool _isGridView = true;

  @override
  void initState() {
    super.initState();
    _initLocation();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _initLocation() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (!mounted) return;
        setState(() {
          _locationDenied = true;
          _currentPosition = null;
        });
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (!mounted) return;
        setState(() {
          _locationDenied = true;
          _currentPosition = null;
        });
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
      );

      if (!mounted) return;
      setState(() {
        _currentPosition = pos;
        _locationDenied = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _locationDenied = true;
        _currentPosition = null;
      });
    }
  }

  double? _distanceFromUser(DiningPlace place) {
    if (_currentPosition == null ||
        place.latitude == null ||
        place.longitude == null)
      return null;
    return Geolocator.distanceBetween(
      _currentPosition!.latitude,
      _currentPosition!.longitude,
      place.latitude!,
      place.longitude!,
    );
  }

  Future<void> _openInMaps(DiningPlace place) async {
    if (place.latitude == null || place.longitude == null) return;

    final url = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=${place.latitude},${place.longitude}',
    );

    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _callRestaurant(String phone) async {
    final url = Uri.parse('tel:$phone');
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    }
  }

  Future<void> _openWebsite(String website) async {
    final cleaned = website.trim();
    if (cleaned.isEmpty) return;

    final finalUrl =
        (cleaned.startsWith('http://') || cleaned.startsWith('https://'))
        ? cleaned
        : 'https://$cleaned';

    final uri = Uri.tryParse(finalUrl);
    if (uri == null) return;

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _showAdvancedFilterSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _buildFilterSheet(ctx),
    );
  }

  Widget _buildFilterSheet(BuildContext sheetContext) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: StatefulBuilder(
        builder: (ctx, setSheetState) {
          return SingleChildScrollView(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 14,
              bottom: 20 + MediaQuery.of(ctx).viewInsets.bottom,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    const Icon(Icons.tune_rounded),
                    const SizedBox(width: 10),
                    Text(
                      'Filters',
                      style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _selectedCuisine = null;
                          _selectedPriceLevel = null;
                          _minRating = null;
                          _sortBy = 'distance';
                          _nearbyOnly = false;
                          _nearbyRadiusKm = 5.0;
                        });
                        Navigator.pop(ctx);
                      },
                      child: const Text('Reset'),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Nearby only'),
                  subtitle: Text(
                    _currentPosition == null
                        ? 'Enable location to use this'
                        : 'Show places within ${_nearbyRadiusKm.toStringAsFixed(1)} km',
                  ),
                  value: _nearbyOnly,
                  onChanged: (_currentPosition == null)
                      ? null
                      : (val) {
                          setSheetState(() => _nearbyOnly = val);
                          setState(() => _nearbyOnly = val);
                        },
                ),

                if (_nearbyOnly && _currentPosition != null) ...[
                  const SizedBox(height: 6),
                  Slider(
                    value: _nearbyRadiusKm,
                    min: 1,
                    max: 50,
                    divisions: 49,
                    label: '${_nearbyRadiusKm.toStringAsFixed(0)} km',
                    onChanged: (v) {
                      setSheetState(() => _nearbyRadiusKm = v);
                      setState(() => _nearbyRadiusKm = v);
                    },
                  ),
                ],

                const SizedBox(height: 14),
                Text(
                  'Price Level',
                  style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  children: [1, 2, 3, 4].map((price) {
                    final selected = _selectedPriceLevel == price;
                    return FilterChip(
                      label: Text('\$' * price),
                      selected: selected,
                      onSelected: (val) {
                        setSheetState(
                          () => _selectedPriceLevel = val ? price : null,
                        );
                        setState(
                          () => _selectedPriceLevel = val ? price : null,
                        );
                      },
                    );
                  }).toList(),
                ),

                const SizedBox(height: 16),
                Text(
                  'Minimum Rating: ${_minRating?.toStringAsFixed(1) ?? "Any"}',
                  style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Slider(
                  value: _minRating ?? 0,
                  min: 0,
                  max: 5,
                  divisions: 10,
                  label: (_minRating ?? 0).toStringAsFixed(1),
                  onChanged: (val) {
                    final newVal = val <= 0 ? null : val;
                    setSheetState(() => _minRating = newVal);
                    setState(() => _minRating = newVal);
                  },
                ),

                const SizedBox(height: 16),
                Text(
                  'Sort By',
                  style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  children: [
                    _SortChip(
                      label: 'Distance',
                      selected: _sortBy == 'distance',
                      onTap: () => setState(() => _sortBy = 'distance'),
                    ),
                    _SortChip(
                      label: 'Rating',
                      selected: _sortBy == 'rating',
                      onTap: () => setState(() => _sortBy = 'rating'),
                    ),
                    _SortChip(
                      label: 'Name',
                      selected: _sortBy == 'name',
                      onTap: () => setState(() => _sortBy = 'name'),
                    ),
                  ],
                ),

                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 0,
                    ),
                    child: const Text(
                      'Apply',
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
        },
      ),
    );
  }

  void _showRestaurantDetails(DiningPlace place, double? distanceMeters) {
    final distanceKm = distanceMeters != null
        ? (distanceMeters / 1000.0)
        : null;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _AdvancedRestaurantDetailModal(
        place: place,
        distanceKm: distanceKm,
        onOpenMaps: () => _openInMaps(place),
        onCall: (place.phone ?? '').trim().isNotEmpty
            ? () => _callRestaurant(place.phone!.trim())
            : null,
        onWebsite: (place.website ?? '').trim().isNotEmpty
            ? () => _openWebsite(place.website!.trim())
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FF),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('Dining_wembley')
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _buildErrorState(snapshot.error.toString());
          }
          if (!snapshot.hasData) {
            return _buildPremiumLoading();
          }

          final docs = snapshot.data!.docs;
          if (docs.isEmpty) {
            return _buildEmptyState();
          }

          final places = docs.map((d) => DiningPlace.fromFirestore(d)).toList();

          // Build dropdown categories from cuisines
          final cuisines =
              <String>{
                  for (final p in places)
                    if ((p.cuisine ?? '').trim().isNotEmpty) p.cuisine!.trim(),
                }.toList()
                ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

          // Ensure selected cuisine is valid
          if (_selectedCuisine != null &&
              !cuisines.contains(_selectedCuisine)) {
            _selectedCuisine = null;
          }

          final entries = places
              .map(
                (p) =>
                    _PlaceEntry(place: p, distanceMeters: _distanceFromUser(p)),
              )
              .where((entry) {
                final p = entry.place;
                final dist = entry.distanceMeters;

                final query = _searchQuery.toLowerCase();
                final matchesSearch =
                    query.isEmpty ||
                    p.name.toLowerCase().contains(query) ||
                    (p.address?.toLowerCase().contains(query) ?? false) ||
                    (p.cuisine?.toLowerCase().contains(query) ?? false);

                final matchesCuisine =
                    _selectedCuisine == null ||
                    ((p.cuisine ?? '').trim().toLowerCase() ==
                        _selectedCuisine!.trim().toLowerCase());

                final matchesPrice =
                    _selectedPriceLevel == null ||
                    p.priceLevel == _selectedPriceLevel;
                final matchesRating =
                    _minRating == null || (p.rating ?? 0) >= _minRating!;

                final withinRadius =
                    !_nearbyOnly ||
                    _currentPosition == null ||
                    dist == null ||
                    dist <= (_nearbyRadiusKm * 1000);

                return matchesSearch &&
                    matchesCuisine &&
                    matchesPrice &&
                    matchesRating &&
                    withinRadius;
              })
              .toList();

          // Sort
          entries.sort((a, b) {
            switch (_sortBy) {
              case 'distance':
                final da = a.distanceMeters ?? double.infinity;
                final db = b.distanceMeters ?? double.infinity;
                return da.compareTo(db);
              case 'rating':
                return (b.place.rating ?? 0).compareTo(a.place.rating ?? 0);
              case 'name':
                return a.place.name.toLowerCase().compareTo(
                  b.place.name.toLowerCase(),
                );
              default:
                return 0;
            }
          });

          return RefreshIndicator(
            onRefresh: () async => _initLocation(),
            child: CustomScrollView(
              controller: _scrollController,
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              slivers: [
                _buildPremiumSliverAppBar(context),

                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
                    child: Column(
                      children: [
                        _buildPremiumTopControls(cuisines),
                        const SizedBox(height: 10),
                        if (_locationDenied) _buildLocationBanner(),
                        _buildActiveFiltersChips(),
                      ],
                    ),
                  ),
                ),

                if (entries.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _buildNoResultsState(
                      message: _nearbyOnly
                          ? 'No restaurants within ${_nearbyRadiusKm.toStringAsFixed(1)} km.\nTry increasing the radius or disable Nearby only.'
                          : 'No restaurants found.\nTry adjusting filters.',
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 110),
                    sliver: _isGridView
                        ? SliverGrid(
                            delegate: SliverChildBuilderDelegate(
                              (ctx, index) =>
                                  _buildPremiumGridCard(entries[index]),
                              childCount: entries.length,
                            ),
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 2,
                                  crossAxisSpacing: 12,
                                  mainAxisSpacing: 12,
                                  childAspectRatio: 0.76,
                                ),
                          )
                        : SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (ctx, index) => Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: _buildPremiumListCard(entries[index]),
                              ),
                              childCount: entries.length,
                            ),
                          ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  SliverAppBar _buildPremiumSliverAppBar(BuildContext context) {
    return SliverAppBar(
      pinned: true,
      stretch: true,
      expandedHeight: 220,
      backgroundColor: const Color(0xFFF8F9FF),
      elevation: 0,
      title: const Text(
        'Dining',
        style: TextStyle(
          fontWeight: FontWeight.w900,
          letterSpacing: -0.2,
          color: Color(0xFF0F172A),
        ),
      ),
      actions: [
        IconButton(
          tooltip: 'Filters',
          onPressed: _showAdvancedFilterSheet,
          icon: const Icon(Icons.tune_rounded, color: Color(0xFF0F172A)),
        ),
        const SizedBox(width: 6),
      ],
      flexibleSpace: FlexibleSpaceBar(
        background: _DiningHeroHeader(
          controller: _searchController,
          onChanged: (v) => setState(() => _searchQuery = v),
          onClear: () {
            _searchController.clear();
            setState(() => _searchQuery = '');
          },
        ),
      ),
    );
  }

  Widget _buildPremiumTopControls(List<String> cuisines) {
    final items = <String>['All Categories', ...cuisines];

    final selected = (_selectedCuisine == null)
        ? 'All Categories'
        : _selectedCuisine!;
    final safeSelected = items.contains(selected) ? selected : 'All Categories';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 20,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Row(
        children: [
          // Category dropdown
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: safeSelected,
                  isExpanded: true,
                  icon: const Icon(Icons.keyboard_arrow_down_rounded),
                  items: items
                      .map(
                        (v) => DropdownMenuItem<String>(
                          value: v,
                          child: Text(
                            v,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    if (v == null) return;
                    setState(
                      () =>
                          _selectedCuisine = (v == 'All Categories') ? null : v,
                    );
                  },
                ),
              ),
            ),
          ),

          const SizedBox(width: 10),

          // Layout toggle (Grid / List)
          _LayoutToggle(
            isGrid: _isGridView,
            onGrid: () => setState(() => _isGridView = true),
            onList: () => setState(() => _isGridView = false),
          ),
        ],
      ),
    );
  }

  Widget _buildLocationBanner() {
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFDE68A)),
      ),
      child: Row(
        children: [
          const Icon(Icons.location_off_rounded, color: Color(0xFFB45309)),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Enable location to show distances and use Nearby only.',
              style: TextStyle(
                color: Color(0xFF92400E),
                fontWeight: FontWeight.w700,
                height: 1.25,
              ),
            ),
          ),
          TextButton(
            onPressed: _initLocation,
            child: const Text(
              'Enable',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveFiltersChips() {
    final active = <String>[];

    if (_selectedPriceLevel != null)
      active.add('Price: ${'\$' * _selectedPriceLevel!}');
    if (_minRating != null)
      active.add('Rating: ${_minRating!.toStringAsFixed(1)}+');
    if (_nearbyOnly)
      active.add('Nearby: ${_nearbyRadiusKm.toStringAsFixed(1)}km');
    if (_sortBy != 'distance')
      active.add('Sort: ${_sortBy[0].toUpperCase()}${_sortBy.substring(1)}');

    if (active.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: active.map((label) {
            return Chip(
              label: Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
              onDeleted: () {
                setState(() {
                  if (label.startsWith('Price')) _selectedPriceLevel = null;
                  if (label.startsWith('Rating')) _minRating = null;
                  if (label.startsWith('Nearby')) _nearbyOnly = false;
                  if (label.startsWith('Sort')) _sortBy = 'distance';
                });
              },
            );
          }).toList(),
        ),
      ),
    );
  }

  // -------------------- PREMIUM GRID CARD --------------------
  Widget _buildPremiumGridCard(_PlaceEntry entry) {
    final place = entry.place;
    final dist = entry.distanceMeters;
    final distKm = dist != null ? (dist / 1000.0) : null;

    return InkWell(
      onTap: () => _showRestaurantDetails(place, dist),
      borderRadius: BorderRadius.circular(18),
      child: Container(
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
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image + badges
            SizedBox(
              height: 120,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _buildRestaurantImage(place, height: 120),

                  // soft gradient overlay for premium contrast
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.black.withOpacity(0.00),
                          Colors.black.withOpacity(0.35),
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),

                  if (place.hasHighRating)
                    const Positioned(
                      top: 10,
                      right: 10,
                      child: _MiniBadge(icon: Icons.star_rounded, text: '4.5+'),
                    ),
                  if (place.isPopular)
                    const Positioned(
                      top: 10,
                      left: 10,
                      child: _MiniBadge(
                        icon: Icons.trending_up_rounded,
                        text: 'Popular',
                      ),
                    ),

                  Positioned(
                    left: 12,
                    bottom: 10,
                    right: 12,
                    child: Row(
                      children: [
                        if ((place.cuisine ?? '').trim().isNotEmpty)
                          _Tag(text: place.cuisine!.trim()),
                        const SizedBox(width: 8),
                        if (place.priceLevel != null)
                          _Tag(text: place.getPriceDisplay()),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      place.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF0F172A),
                        letterSpacing: -0.2,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 6),
                    if ((place.address ?? '').trim().isNotEmpty)
                      Text(
                        place.address!.trim(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF64748B),
                          fontSize: 12,
                        ),
                      ),
                    const Spacer(),
                    Row(
                      children: [
                        if (place.rating != null) ...[
                          const Icon(
                            Icons.star_rounded,
                            size: 16,
                            color: Color(0xFFF59E0B),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            place.rating!.toStringAsFixed(1),
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          if (place.userRatingsTotal != null) ...[
                            const SizedBox(width: 6),
                            Text(
                              '(${place.userRatingsTotal})',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF64748B),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ],
                        const Spacer(),
                        if (distKm != null)
                          Row(
                            children: [
                              const Icon(
                                Icons.place_rounded,
                                size: 16,
                                color: Color(0xFFEF4444),
                              ),
                              const SizedBox(width: 3),
                              Text(
                                '${distKm.toStringAsFixed(1)} km',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF334155),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => _showRestaurantDetails(place, dist),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF111827),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Text(
                          'View',
                          style: TextStyle(fontWeight: FontWeight.w900),
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

  // -------------------- PREMIUM LIST CARD --------------------
  Widget _buildPremiumListCard(_PlaceEntry entry) {
    final place = entry.place;
    final dist = entry.distanceMeters;
    final distKm = dist != null ? (dist / 1000.0) : null;

    return InkWell(
      onTap: () => _showRestaurantDetails(place, dist),
      borderRadius: BorderRadius.circular(18),
      child: Container(
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
        clipBehavior: Clip.antiAlias,
        child: Row(
          children: [
            SizedBox(
              width: 128,
              height: 120,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _buildRestaurantImage(place, height: 120),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.black.withOpacity(0.00),
                          Colors.black.withOpacity(0.30),
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                  if (place.hasHighRating)
                    const Positioned(
                      top: 10,
                      left: 10,
                      child: _MiniBadge(icon: Icons.star_rounded, text: '4.5+'),
                    ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      place.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF0F172A),
                        letterSpacing: -0.2,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        if ((place.cuisine ?? '').trim().isNotEmpty)
                          _Tag(text: place.cuisine!.trim()),
                        const SizedBox(width: 8),
                        if (place.priceLevel != null)
                          _Tag(text: place.getPriceDisplay()),
                        const Spacer(),
                        if (distKm != null)
                          Row(
                            children: [
                              const Icon(
                                Icons.place_rounded,
                                size: 16,
                                color: Color(0xFFEF4444),
                              ),
                              const SizedBox(width: 3),
                              Text(
                                '${distKm.toStringAsFixed(1)} km',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF334155),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                    const Spacer(),
                    Row(
                      children: [
                        if (place.rating != null) ...[
                          const Icon(
                            Icons.star_rounded,
                            size: 16,
                            color: Color(0xFFF59E0B),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            place.rating!.toStringAsFixed(1),
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          if (place.userRatingsTotal != null) ...[
                            const SizedBox(width: 6),
                            Text(
                              '(${place.userRatingsTotal})',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF64748B),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ],
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF111827),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Text(
                            'View',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 12,
                            ),
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

  Widget _buildRestaurantImage(DiningPlace place, {double height = 140}) {
    final url = (place.photoUrl ?? '').trim();
    if (url.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: url,
        fit: BoxFit.cover,
        width: double.infinity,
        height: height,
        placeholder: (_, __) => _buildImagePlaceholder(height),
        errorWidget: (_, __, ___) => _buildImageFallback(height),
      );
    }
    return _buildImageFallback(height);
  }

  Widget _buildImagePlaceholder(double height) {
    return SizedBox(
      height: height,
      child: Shimmer.fromColors(
        baseColor: Colors.grey.shade200,
        highlightColor: Colors.grey.shade100,
        child: Container(color: Colors.white),
      ),
    );
  }

  Widget _buildImageFallback(double height) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [const Color(0xFFFFEDD5), const Color(0xFFFEE2E2)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: const Center(
        child: Icon(
          Icons.restaurant_rounded,
          size: 42,
          color: Color(0xFF9CA3AF),
        ),
      ),
    );
  }

  Widget _buildPremiumLoading() {
    return CustomScrollView(
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      slivers: [
        SliverAppBar(
          pinned: true,
          expandedHeight: 220,
          backgroundColor: const Color(0xFFF8F9FF),
          elevation: 0,
          title: const Text(
            'Dining',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              color: Color(0xFF0F172A),
            ),
          ),
          flexibleSpace: const FlexibleSpaceBar(
            background: _DiningHeroHeader.loading(),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 110),
          sliver: SliverGrid(
            delegate: SliverChildBuilderDelegate(
              (ctx, i) => Shimmer.fromColors(
                baseColor: Colors.grey.shade200,
                highlightColor: Colors.grey.shade100,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
              ),
              childCount: 8,
            ),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 0.76,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return const Center(
      child: Text(
        'No dining options available',
        style: TextStyle(fontWeight: FontWeight.w800),
      ),
    );
  }

  Widget _buildNoResultsState({required String message}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off_rounded,
              size: 64,
              color: Colors.grey.shade300,
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.grey.shade700,
                height: 1.4,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _searchQuery = '';
                  _selectedCuisine = null;
                  _selectedPriceLevel = null;
                  _minRating = null;
                  _nearbyOnly = false;
                  _nearbyRadiusKm = 5.0;
                  _searchController.clear();
                });
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF111827),
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text(
                'Clear filters',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(String error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Text(
          'Error: $error',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

class _LayoutToggle extends StatelessWidget {
  final bool isGrid;
  final VoidCallback onGrid;
  final VoidCallback onList;

  const _LayoutToggle({
    required this.isGrid,
    required this.onGrid,
    required this.onList,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          _ToggleIcon(
            selected: isGrid,
            icon: Icons.grid_view_rounded,
            onTap: onGrid,
          ),
          _ToggleIcon(
            selected: !isGrid,
            icon: Icons.view_list_rounded,
            onTap: onList,
          ),
        ],
      ),
    );
  }
}

class _ToggleIcon extends StatelessWidget {
  final bool selected;
  final IconData icon;
  final VoidCallback onTap;

  const _ToggleIcon({
    required this.selected,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 10,
                    offset: const Offset(0, 8),
                  ),
                ]
              : null,
        ),
        child: Icon(
          icon,
          color: selected ? const Color(0xFF0F172A) : const Color(0xFF64748B),
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final String text;
  const _Tag({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.20),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withOpacity(0.25)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w900,
          fontSize: 11,
        ),
      ),
    );
  }
}

class _MiniBadge extends StatelessWidget {
  final IconData icon;
  final String text;

  const _MiniBadge({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.45),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withOpacity(0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class _SortChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SortChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
    );
  }
}

class _PlaceEntry {
  final DiningPlace place;
  final double? distanceMeters;
  _PlaceEntry({required this.place, required this.distanceMeters});
}

class _DiningHeroHeader extends StatelessWidget {
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onClear;

  const _DiningHeroHeader({this.controller, this.onChanged, this.onClear});

  const _DiningHeroHeader.loading()
    : controller = null,
      onChanged = null,
      onClear = null;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFF97316), Color(0xFFEF4444), Color(0xFF8B5CF6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 56, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Discover Dining',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.8,
                  height: 1.05,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Verified places • Better choices • Faster planning',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.90),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              _HeroSearchBar(
                controller: controller,
                onChanged: onChanged,
                onClear: onClear,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeroSearchBar extends StatelessWidget {
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onClear;

  const _HeroSearchBar({
    required this.controller,
    required this.onChanged,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = controller != null && onChanged != null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.18),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.22)),
      ),
      child: Row(
        children: [
          const Icon(Icons.search_rounded, color: Colors.white, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              enabled: enabled,
              controller: controller,
              onChanged: onChanged,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
              decoration: InputDecoration(
                hintText: 'Search restaurants, cuisine…',
                hintStyle: TextStyle(
                  color: Colors.white.withOpacity(0.85),
                  fontWeight: FontWeight.w700,
                ),
                border: InputBorder.none,
                isCollapsed: true,
              ),
            ),
          ),
          if (enabled && (controller!.text.isNotEmpty))
            InkWell(
              onTap: onClear,
              borderRadius: BorderRadius.circular(999),
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Icon(
                  Icons.close_rounded,
                  color: Colors.white,
                  size: 18,
                ),
              ),
            )
          else
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.18),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.restaurant_menu_rounded,
                color: Colors.white,
                size: 18,
              ),
            ),
        ],
      ),
    );
  }
}

class _AdvancedRestaurantDetailModal extends StatelessWidget {
  final DiningPlace place;
  final double? distanceKm;
  final VoidCallback onOpenMaps;
  final VoidCallback? onCall;
  final VoidCallback? onWebsite;

  const _AdvancedRestaurantDetailModal({
    required this.place,
    required this.distanceKm,
    required this.onOpenMaps,
    this.onCall,
    this.onWebsite,
  });

  @override
  Widget build(BuildContext context) {
    final photo = (place.photoUrl ?? '').trim();

    return DraggableScrollableSheet(
      initialChildSize: 0.74,
      minChildSize: 0.55,
      maxChildSize: 0.96,
      builder: (context, scrollController) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SingleChildScrollView(
          controller: scrollController,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: SizedBox(
                    height: 230,
                    width: double.infinity,
                    child: photo.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: photo,
                            fit: BoxFit.cover,
                            placeholder: (_, __) => Shimmer.fromColors(
                              baseColor: Colors.grey.shade200,
                              highlightColor: Colors.grey.shade100,
                              child: Container(color: Colors.white),
                            ),
                            errorWidget: (_, __, ___) => Container(
                              color: Colors.grey.shade200,
                              child: const Center(
                                child: Icon(Icons.restaurant_rounded, size: 60),
                              ),
                            ),
                          )
                        : Container(
                            color: Colors.grey.shade200,
                            child: const Center(
                              child: Icon(Icons.restaurant_rounded, size: 60),
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  place.name,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 8),
                if ((place.address ?? '').trim().isNotEmpty)
                  Text(
                    place.address!.trim(),
                    style: TextStyle(
                      color: Colors.grey.shade700,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    if (place.rating != null)
                      _pill(
                        icon: Icons.star_rounded,
                        text: place.rating!.toStringAsFixed(1),
                      ),
                    if (distanceKm != null)
                      _pill(
                        icon: Icons.place_rounded,
                        text: '${distanceKm!.toStringAsFixed(1)} km',
                      ),
                    if (place.priceLevel != null)
                      _pill(
                        icon: Icons.payments_outlined,
                        text: place.getPriceDisplay(),
                      ),
                    if (place.openNow != null)
                      _pill(
                        icon: Icons.schedule,
                        text: place.openNow! ? 'Open' : 'Closed',
                      ),
                  ],
                ),
                const SizedBox(height: 18),

                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: onOpenMaps,
                        icon: const Icon(Icons.map_rounded),
                        label: const Text('Open in Maps'),
                        style: ElevatedButton.styleFrom(
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                    if (onCall != null) ...[
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: onCall,
                          icon: const Icon(Icons.call_rounded),
                          label: const Text('Call'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),

                if (onWebsite != null) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: onWebsite,
                      icon: const Icon(Icons.public_rounded),
                      label: const Text('Website'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _pill({required IconData icon, required String text}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: const Color(0xFF475569)),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              color: Color(0xFF0F172A),
            ),
          ),
        ],
      ),
    );
  }
}
