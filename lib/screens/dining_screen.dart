import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import 'package:firebase_auth/firebase_auth.dart';

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
  final bool isPromoted; // For future use (e.g., sponsored listings)

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
    this.isPromoted = false,
  });

  factory DiningPlace.fromFirestore(DocumentSnapshot doc) {
    final data = (doc.data() as Map<String, dynamic>?) ?? {};

    String? getString(List<String> keys) {
      for (final k in keys) {
        if (data.containsKey(k) && data[k] != null) {
          return data[k].toString();
        }
      }
      return null;
    }

    num? getNum(List<String> keys) {
      for (final k in keys) {
        if (data.containsKey(k) && data[k] is num) {
          return data[k] as num;
        }
      }
      return null;
    }

    bool? getBool(List<String> keys) {
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
      id: getString(['id']) ?? doc.id,
      name: getString(['name']) ?? 'Unknown',
      placeId: getString(['placeId', 'place id']),
      source: getString(['source']),
      address: getString(['address', 'formatted_address']),
      phone: getString(['phone', 'international_phone_number']),
      rating: getNum(['rating'])?.toDouble(),
      userRatingsTotal: getNum([
        'userRatingsTotal',
        'user_ratings_total',
      ])?.toInt(),
      priceLevel: getNum(['priceLevel', 'price_level'])?.toInt(),
      latitude: getNum(['latitude', 'lat'])?.toDouble(),
      longitude: getNum(['longitude', 'lng'])?.toDouble(),
      types: getString(['types']),
      cuisine: getString(['cuisine', 'cuisineType']),
      openNow: getBool(['openNow', 'open_now']),
      photoReference: getString(['photoReference', 'photo_reference']),
      photoUrl: getString(['cachedPhotoUrl']),
      website: getString(['website']),
      photos: (data['photos'] as List?)?.cast<String>(),
      isPromoted: getBool(['isPromoted', 'is_promoted']) ?? false,
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
  // Parameters for auto-showing restaurant detail from search
  final String? autoShowRestaurantId;
  final Map<String, dynamic>? autoShowRestaurantData;

  const AdvancedDiningScreen({
    super.key,
    this.autoShowRestaurantId,
    this.autoShowRestaurantData,
  });

  @override
  State<AdvancedDiningScreen> createState() => _AdvancedDiningScreenState();
}

class _RestaurantFavoriteButton extends StatefulWidget {
  final String restaurantId;
  final Map<String, dynamic> restaurantData;

  const _RestaurantFavoriteButton({
    required this.restaurantId,
    required this.restaurantData,
  });

  @override
  State<_RestaurantFavoriteButton> createState() =>
      _RestaurantFavoriteButtonState();
}

class _RestaurantFavoriteButtonState extends State<_RestaurantFavoriteButton> {
  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;
  bool _isSaved = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _checkIfSaved();
  }

  Future<void> _checkIfSaved() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    try {
      final doc = await _db
          .collection('users')
          .doc(uid)
          .collection('savedRestaurants')
          .doc(widget.restaurantId)
          .get();

      if (mounted) {
        setState(() => _isSaved = doc.exists);
      }
    } catch (e) {
      // Silent fail
    }
  }

  Future<void> _toggleSave() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null || _isLoading) return;

    setState(() => _isLoading = true);

    try {
      final docRef = _db
          .collection('users')
          .doc(uid)
          .collection('savedRestaurants')
          .doc(widget.restaurantId);

      if (_isSaved) {
        await docRef.delete();
        if (mounted) {
          setState(() => _isSaved = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Removed from saved restaurants'),
              backgroundColor: const Color(0xFF64748B),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          );
        }
      } else {
        await docRef.set({
          ...widget.restaurantData,
          'savedAt': FieldValue.serverTimestamp(),
        });
        if (mounted) {
          setState(() => _isSaved = true);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Saved to your restaurants'),
              backgroundColor: const Color(0xFF10B981),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: const Color(0xFFEF4444),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      elevation: 4,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: _isLoading ? null : _toggleSave,
        child: Container(
          padding: const EdgeInsets.all(8),
          child: _isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(
                  _isSaved
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  color: _isSaved
                      ? const Color(0xFFEF4444)
                      : const Color(0xFF64748B),
                  size: 20,
                ),
        ),
      ),
    );
  }
}

class _AdvancedDiningScreenState extends State<AdvancedDiningScreen> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final PageController _promoPageController =
      PageController(); // For promotional slider

  Position? _currentPosition;
  bool _locationDenied = false;

  String _searchQuery = '';
  String? _selectedCuisine;
  int? _selectedPriceLevel;
  double? _minRating;
  String _sortBy = 'distance'; // distance, rating, name, price_low, price_high

  // Nearby filter is opt-in to avoid "blank list" when location is enabled.
  bool _nearbyOnly = false;
  double _nearbyRadiusKm = 5.0;

  @override
  void initState() {
    super.initState();
    // ✅ Important: request location after first frame (prevents occasional build timing issues)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initLocation();

      // Auto-show restaurant detail if data is provided from search
      if (widget.autoShowRestaurantId != null &&
          widget.autoShowRestaurantData != null) {
        _autoShowRestaurantDetail();
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    _promoPageController.dispose();
    super.dispose();
  }

  // Helper method to determine grid columns based on screen size
  int _getGridCrossAxisCount() {
    final screenWidth = MediaQuery.of(context).size.width;
    if (screenWidth >= 900) {
      return 4; // Tablets in landscape
    } else if (screenWidth >= 600) {
      return 3; // Tablets in portrait or large phones
    } else {
      return 2; // Regular phones
    }
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

  void _autoShowRestaurantDetail() {
    if (widget.autoShowRestaurantData == null) return;

    try {
      final data = widget.autoShowRestaurantData!;

      final place = DiningPlace(
        id: data['id']?.toString() ?? widget.autoShowRestaurantId ?? '',
        name: data['name']?.toString() ?? 'Restaurant',
        address: data['address']?.toString() ?? '',
        cuisine: data['cuisine']?.toString() ?? data['types']?.toString() ?? '',
        rating: data['rating'] is num
            ? (data['rating'] as num).toDouble()
            : null,
        priceLevel: data['priceLevel'] is int
            ? data['priceLevel'] as int
            : data['priceLevel'] is num
            ? (data['priceLevel'] as num).toInt()
            : null,
        photoUrl:
            data['photoUrl']?.toString() ??
            data['photoReference']?.toString() ??
            '',
        phone: data['phone']?.toString() ?? '',
        website: data['website']?.toString() ?? '',
        latitude: data['latitude'] is num
            ? (data['latitude'] as num).toDouble()
            : data['lat'] is num
            ? (data['lat'] as num).toDouble()
            : 51.5560,
        longitude: data['longitude'] is num
            ? (data['longitude'] as num).toDouble()
            : data['lng'] is num
            ? (data['lng'] as num).toDouble()
            : -0.2795,
        openNow: data['openNow'] as bool?,
        placeId: data['placeId']?.toString() ?? data['place_id']?.toString(),
        source: data['source']?.toString() ?? 'search',
        userRatingsTotal: data['userRatingsTotal'] is int
            ? data['userRatingsTotal'] as int
            : null,
        types: data['types']?.toString(),
        photoReference: data['photoReference']?.toString(),
        photos: data['photos'] is List
            ? (data['photos'] as List).map((e) => e.toString()).toList()
            : null,
      );

      final distance = data['distance'] is num
          ? (data['distance'] as num).toDouble()
          : _distanceFromUser(place);

      _showRestaurantDetails(place, distance);
    } catch (e) {
      debugPrint('Error auto-showing restaurant: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not load restaurant details'),
            backgroundColor: Color(0xFFEF4444),
          ),
        );
      }
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

  String _formatDistance(double? meters) {
    if (meters == null) return '';
    const metersToMiles = 0.000621371;
    final miles = meters * metersToMiles;
    return '${miles.toStringAsFixed(1)} mi';
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
          if (!snapshot.hasData) return _buildPremiumLoading();

          final docs = snapshot.data!.docs;
          if (docs.isEmpty) return _buildEmptyState();

          final places = docs.map((d) => DiningPlace.fromFirestore(d)).toList();

          // Build dropdown categories from cuisines
          final cuisines =
              <String>{
                  for (final p in places)
                    if ((p.cuisine ?? '').trim().isNotEmpty) p.cuisine!.trim(),
                }.toList()
                ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

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

          // ✅ Sort (distance works ONLY when location is granted; null distances go last)
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
              case 'price_low':
                final pa = a.place.priceLevel ?? 999;
                final pb = b.place.priceLevel ?? 999;
                return pa.compareTo(pb);
              case 'price_high':
                final pa = a.place.priceLevel ?? -1;
                final pb = b.place.priceLevel ?? -1;
                return pb.compareTo(pa);
              default:
                return 0;
            }
          });

          // Get promoted places for the banner
          final promotedPlaces = places.where((p) => p.isPromoted).toList();

          return RefreshIndicator(
            onRefresh: () async => _initLocation(),
            child: CustomScrollView(
              controller: _scrollController,
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              slivers: [
                _buildPremiumSliverAppBar(context),
                // Promotional Slider - only shows if there are promoted restaurants
                if (promotedPlaces.isNotEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: _buildPromotionalSlider(promotedPlaces),
                    ),
                  ),
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
                    sliver: SliverGrid(
                      key: const PageStorageKey('dining_grid'),
                      delegate: SliverChildBuilderDelegate(
                        (ctx, index) => _buildPremiumGridCard(entries[index]),
                        childCount: entries.length,
                      ),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: _getGridCrossAxisCount(),
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        childAspectRatio: 0.67,
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

  Widget _buildPromotionalSlider(List<DiningPlace> promotedPlaces) {
    // Responsive height for promotional banner
    final screenWidth = MediaQuery.of(context).size.width;
    final promoHeight = (screenWidth - 32) * 0.45; // 45% of available width

    return SizedBox(
      height: promoHeight.clamp(140.0, 180.0), // Min 140, Max 180
      child: PageView.builder(
        controller: _promoPageController,
        itemCount: promotedPlaces.length,
        itemBuilder: (context, index) {
          final place = promotedPlaces[index];
          final distance = _distanceFromUser(place);

          return GestureDetector(
            onTap: () => _showRestaurantDetails(place, distance),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: _buildRestaurantImage(
                      place,
                      height: promoHeight.clamp(140.0, 180.0),
                    ),
                  ),
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withOpacity(0.1),
                          Colors.black.withOpacity(0.7),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    top: 12,
                    left: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFBBF24),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.star_rounded,
                            size: 14,
                            color: Colors.white,
                          ),
                          SizedBox(width: 4),
                          Text(
                            'PROMOTED',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 10,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 16,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          place.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            if (place.rating != null) ...[
                              const Icon(
                                Icons.star_rounded,
                                size: 14,
                                color: Color(0xFFFBBF24),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                place.rating!.toStringAsFixed(1),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(width: 12),
                            ],
                            if (distance != null) ...[
                              const Icon(
                                Icons.place_rounded,
                                size: 14,
                                color: Colors.white70,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                _formatDistance(distance),
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
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
        },
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
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _sortBy,
                icon: const Icon(Icons.sort_rounded, size: 18),
                items: const [
                  DropdownMenuItem(
                    value: 'distance',
                    child: Text(
                      'Distance',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  DropdownMenuItem(
                    value: 'price_low',
                    child: Text(
                      'Low to High',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  DropdownMenuItem(
                    value: 'price_high',
                    child: Text(
                      'High to Low',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => _sortBy = v);
                },
              ),
            ),
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

    if (_selectedPriceLevel != null) {
      active.add('Price: ${'\$' * _selectedPriceLevel!}');
    }
    if (_minRating != null) {
      active.add('Rating: ${_minRating!.toStringAsFixed(1)}+');
    }
    if (_nearbyOnly) {
      active.add('Nearby: ${_nearbyRadiusKm.toStringAsFixed(1)}km');
    }
    if (_sortBy != 'distance') {
      active.add('Sort: ${_sortBy[0].toUpperCase()}${_sortBy.substring(1)}');
    }

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

  // -------------------- PREMIUM GRID CARD (✅ FIXED: no Expanded/Spacer -> no crash) --------------------
  Widget _buildPremiumGridCard(_PlaceEntry entry) {
    final place = entry.place;
    final dist = entry.distanceMeters;
    final distKm = dist != null ? (dist / 1000.0) : null;

    // Calculate responsive image height based on screen width
    final screenWidth = MediaQuery.of(context).size.width;
    final cardWidth =
        (screenWidth - 44) / 2; // 44 = 16 left + 16 right + 12 gap
    final imageHeight = cardWidth * 0.55; // Consistent aspect ratio

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
            // Image + badges - using responsive height
            SizedBox(
              height: imageHeight,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _buildRestaurantImage(place, height: imageHeight),

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
                  // Heart button
                  Positioned(
                    top: 10,
                    left: 10,
                    child: _RestaurantFavoriteButton(
                      restaurantId: place.id,
                      restaurantData: {
                        'name': place.name,
                        'address': place.address,
                        'cuisine': place.cuisine,
                        'rating': place.rating,
                        'priceLevel': place.priceLevel,
                        'photoUrl': place.photoUrl ?? place.photoReference,
                        'website': place.website,
                      },
                    ),
                  ),
                  if (place.isPopular)
                    const Positioned(
                      top: 10,
                      right: 10,
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

            // ✅ FIX: No Expanded/Spacer here (Grid children must not use flex with unbounded constraints)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min, // ✅ important
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

                  const SizedBox(height: 8),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
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
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    '(${place.userRatingsTotal})',
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF64748B),
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ],
                        ),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.place_rounded,
                            size: 16,
                            color: Color(0xFFEF4444),
                          ),
                          const SizedBox(width: 3),
                          Text(
                            dist != null ? _formatDistance(dist) : '—',
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

                  const SizedBox(height: 8),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => _showRestaurantDetails(place, dist),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF111827),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 8),
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
          ],
        ),
      ),
    );
  }

  Widget _buildRestaurantImage(DiningPlace place, {double height = 140}) {
    final url = (place.photoUrl ?? '').trim();
    if (url.isNotEmpty) {
      return ClipRect(
        child: CachedNetworkImage(
          imageUrl: url,
          fit: BoxFit.cover,
          width: double.infinity,
          height: height,
          alignment:
              Alignment.center, // Center-crop to potentially hide watermarks
          placeholder: (_, __) => _buildImagePlaceholder(height),
          errorWidget: (_, __, ___) => _buildImageFallback(height),
          imageBuilder: (context, imageProvider) => Container(
            decoration: BoxDecoration(
              image: DecorationImage(
                image: imageProvider,
                fit: BoxFit.cover,
                alignment: Alignment.center,
                // Slight color adjustment to reduce watermark visibility
                colorFilter: ColorFilter.mode(
                  Colors.black.withOpacity(0.02),
                  BlendMode.darken,
                ),
              ),
            ),
          ),
        ),
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
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFFFEDD5), Color(0xFFFEE2E2)],
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
            '',
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
              childAspectRatio: 0.60,
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
                  _sortBy = 'distance';
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
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
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
                  height: 2.0,
                ),
              ),
              const SizedBox(height: 60),
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
