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
    final data = doc.data() as Map<String, dynamic>;

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

  // IMPORTANT FIX: do NOT auto-filter by 5km just because location is enabled.
  bool _nearbyOnly = false;
  double _nearbyRadiusKm = 5.0;

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
        desiredAccuracy: LocationAccuracy.medium, // medium is enough + faster
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
        place.longitude == null) {
      return null;
    }
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
        cleaned.startsWith('http://') || cleaned.startsWith('https://')
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
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _buildFilterSheet(ctx),
    );
  }

  Widget _buildFilterSheet(BuildContext sheetContext) {
    return StatefulBuilder(
      builder: (ctx, setSheetState) {
        return SingleChildScrollView(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 16,
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
                      fontWeight: FontWeight.bold,
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
              const SizedBox(height: 12),

              // Nearby only (THIS FIXES YOUR BLANK ISSUE)
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

              const SizedBox(height: 18),

              Text('Price Level', style: Theme.of(ctx).textTheme.titleMedium),
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
                      setState(() => _selectedPriceLevel = val ? price : null);
                    },
                  );
                }).toList(),
              ),

              const SizedBox(height: 18),

              Text(
                'Minimum Rating: ${_minRating?.toStringAsFixed(1) ?? "Any"}',
                style: Theme.of(ctx).textTheme.titleMedium,
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

              const SizedBox(height: 18),

              Text('Sort By', style: Theme.of(ctx).textTheme.titleMedium),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                children:
                    const [
                      ('distance', 'Distance'),
                      ('rating', 'Rating'),
                      ('name', 'Name'),
                    ].map((option) {
                      final selected = _sortBy == option.$1;
                      return FilterChip(
                        label: Text(option.$2),
                        selected: selected,
                        onSelected: (val) {
                          if (val) {
                            // Update both the sheet and the real widget state
                          }
                        },
                      );
                    }).toList(),
              ),

              const SizedBox(height: 12),
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

              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Apply',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        );
      },
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
        onCall: place.phone != null && place.phone!.isNotEmpty
            ? () => _callRestaurant(place.phone!)
            : null,
        onWebsite: place.website != null && place.website!.isNotEmpty
            ? () => _openWebsite(place.website!)
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _buildAdvancedAppBar(),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('Dining_wembley')
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError)
            return _buildErrorState(snapshot.error.toString());
          if (!snapshot.hasData) return _buildLoadingState();

          final docs = snapshot.data!.docs;
          if (docs.isEmpty) return _buildEmptyState();

          final places = docs.map((d) => DiningPlace.fromFirestore(d)).toList();

          final cuisines = <String>{
            for (final p in places)
              if ((p.cuisine ?? '').trim().isNotEmpty) p.cuisine!.trim(),
          }.toList()..sort();

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
                    (p.address?.toLowerCase().contains(query) ?? false);

                final matchesCuisine =
                    _selectedCuisine == null ||
                    (p.cuisine != null &&
                        p.cuisine!.toLowerCase() ==
                            _selectedCuisine!.toLowerCase());

                final matchesPrice =
                    _selectedPriceLevel == null ||
                    p.priceLevel == _selectedPriceLevel;

                final matchesRating =
                    _minRating == null || (p.rating ?? 0) >= _minRating!;

                // FIX: Nearby filter only if user explicitly enables it
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
                return a.place.name.compareTo(b.place.name);
              default:
                return 0;
            }
          });

          return RefreshIndicator(
            onRefresh: () async => _initLocation(),
            child: Column(
              children: [
                _buildSearchBar(),
                if (_locationDenied) _buildLocationDeniedBanner(),
                if (cuisines.isNotEmpty) _buildCuisineChips(cuisines),
                _buildActiveFiltersChips(),
                const SizedBox(height: 8),
                Expanded(
                  child: entries.isEmpty
                      ? _buildNoResultsState(
                          message: _nearbyOnly
                              ? 'No restaurants within ${_nearbyRadiusKm.toStringAsFixed(1)} km.\nTry increasing the radius or disable Nearby only.'
                              : 'No restaurants found.\nTry adjusting filters.',
                        )
                      : GridView.builder(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          controller: _scrollController,
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                crossAxisSpacing: 12,
                                mainAxisSpacing: 12,
                                childAspectRatio: 3 / 4.2,
                              ),
                          itemCount: entries.length,
                          itemBuilder: (ctx, index) =>
                              _buildRestaurantCard(entries[index], index),
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  PreferredSizeWidget _buildAdvancedAppBar() {
    return AppBar(
      title: const Text(
        'Dining',
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      centerTitle: true,
      elevation: 0,
      actions: [
        IconButton(
          onPressed: _showAdvancedFilterSheet,
          icon: const Icon(Icons.tune_rounded),
          tooltip: 'Filters',
        ),
      ],
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: TextField(
        controller: _searchController,
        onChanged: (value) => setState(() => _searchQuery = value),
        decoration: InputDecoration(
          hintText: 'Search restaurants...',
          prefixIcon: const Icon(Icons.search_rounded),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                )
              : null,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          filled: true,
        ),
      ),
    );
  }

  Widget _buildLocationDeniedBanner() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        border: Border.all(color: Colors.orange.shade300),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.location_off_rounded, color: Colors.orange.shade700),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Enable location to see distances and use Nearby only.',
              style: TextStyle(
                color: Colors.orange.shade700,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          TextButton(onPressed: _initLocation, child: const Text('Enable')),
        ],
      ),
    );
  }

  Widget _buildCuisineChips(List<String> cuisines) {
    return SizedBox(
      height: 42,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemBuilder: (ctx, index) {
          final cuisine = cuisines[index];
          final selected = cuisine == _selectedCuisine;
          return FilterChip(
            label: Text(cuisine),
            selected: selected,
            onSelected: (_) =>
                setState(() => _selectedCuisine = selected ? null : cuisine),
          );
        },
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemCount: cuisines.length,
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: active.map((label) {
          return Chip(
            label: Text(label, style: const TextStyle(fontSize: 12)),
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
    );
  }

  Widget _buildRestaurantCard(_PlaceEntry entry, int index) {
    final place = entry.place;
    final dist = entry.distanceMeters;
    final distKm = dist != null ? (dist / 1000.0) : null;

    return GestureDetector(
      onTap: () => _showRestaurantDetails(place, dist),
      child: Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        clipBehavior: Clip.antiAlias,
        elevation: 2,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                _buildRestaurantImage(place, height: 140),
                if (place.hasHighRating)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: _Badge(
                      text: '4.5+',
                      icon: Icons.star_rounded,
                      bg: Colors.amber,
                    ),
                  ),
                if (place.isPopular)
                  Positioned(
                    top: 8,
                    left: 8,
                    child: _Badge(text: 'Popular', bg: Colors.red),
                  ),
              ],
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      place.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    if ((place.cuisine ?? '').trim().isNotEmpty)
                      Text(
                        place.cuisine!.trim(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.grey.shade600,
                        ),
                      ),
                    const Spacer(),
                    Row(
                      children: [
                        if (place.rating != null) ...[
                          const Icon(
                            Icons.star_rounded,
                            size: 14,
                            color: Colors.amber,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            place.rating!.toStringAsFixed(1),
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          if (place.userRatingsTotal != null)
                            Padding(
                              padding: const EdgeInsets.only(left: 4),
                              child: Text(
                                '(${place.userRatingsTotal})',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(color: Colors.grey.shade600),
                              ),
                            ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (distKm != null) ...[
                          const Icon(
                            Icons.place_rounded,
                            size: 14,
                            color: Colors.red,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            '${distKm.toStringAsFixed(1)} km',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: Colors.grey.shade700),
                          ),
                        ],
                        if (place.priceLevel != null) ...[
                          const SizedBox(width: 8),
                          Text(
                            place.getPriceDisplay(),
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ],
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
    final url = place.photoUrl;
    if (url != null && url.isNotEmpty) {
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
          colors: [Colors.blue.shade100, Colors.purple.shade100],
        ),
      ),
      child: const Center(
        child: Icon(Icons.restaurant_rounded, size: 40, color: Colors.grey),
      ),
    );
  }

  Widget _buildLoadingState() {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 3 / 4.2,
      ),
      itemCount: 6,
      itemBuilder: (_, __) => Shimmer.fromColors(
        baseColor: Colors.grey.shade200,
        highlightColor: Colors.grey.shade100,
        child: Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Container(color: Colors.white),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return const Center(child: Text('No dining options available'));
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
              style: TextStyle(color: Colors.grey.shade700, height: 1.4),
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
              child: const Text('Clear filters'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(String error) {
    return Center(child: Text('Error: $error'));
  }
}

class _Badge extends StatelessWidget {
  final String text;
  final IconData? icon;
  final Color bg;

  const _Badge({required this.text, this.icon, required this.bg});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: Colors.white),
            const SizedBox(width: 3),
          ],
          Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 12,
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
    return DraggableScrollableSheet(
      initialChildSize: 0.72,
      minChildSize: 0.5,
      maxChildSize: 0.95,
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
                    height: 220,
                    width: double.infinity,
                    child: CachedNetworkImage(
                      imageUrl: place.photoUrl ?? '',
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
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  place.name,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                if ((place.address ?? '').trim().isNotEmpty)
                  Text(
                    place.address!,
                    style: TextStyle(color: Colors.grey.shade700),
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
                        icon: const Icon(Icons.map_outlined),
                        label: const Text('Maps'),
                      ),
                    ),
                    if (onCall != null) ...[
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: onCall,
                          icon: const Icon(Icons.call_outlined),
                          label: const Text('Call'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                if (onWebsite != null) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: onWebsite,
                      icon: const Icon(Icons.open_in_browser_outlined),
                      label: const Text('Website'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepPurple,
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
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 6),
          Text(text, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
