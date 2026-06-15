import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shimmer/shimmer.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AccommodationScreen extends StatefulWidget {
  final String? autoShowHotelId;
  final Map<String, dynamic>? autoShowHotelData;

  const AccommodationScreen({
    super.key,
    this.autoShowHotelId,
    this.autoShowHotelData,
  });

  @override
  State<AccommodationScreen> createState() => _AccommodationScreenState();
}

enum _AccommodationViewMode { grid, list }

class _AccommodationScreenState extends State<AccommodationScreen> {
  static const String _collectionName = 'accommodations_wembley';

  double? _minRating;
  _AccommodationViewMode _viewMode = _AccommodationViewMode.grid;

  Position? _currentPosition;
  bool _locationDenied = false;
  String _sortBy = 'distance'; // distance, rating, name, value, nearEvents

  // User's saved events for event-based recommendations
  List<Map<String, dynamic>> _userEvents = [];
  bool _loadingEvents = false;

  // Track saved accommodations
  Set<String> _savedAccommodationIds = {};

  final List<_RatingFilter> _ratingFilters = const [
    _RatingFilter(label: 'All ratings', min: null),
    _RatingFilter(label: 'Top rated (4.5+)', min: 4.5),
    _RatingFilter(label: '4★ & up (4.0+)', min: 4.0),
    _RatingFilter(label: '3★ & up (3.0+)', min: 3.0),
    _RatingFilter(label: 'Under 3★', min: -1),
  ];

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initLocation();
      _loadUserEvents();
      _loadSavedAccommodations();

      if (widget.autoShowHotelId != null && widget.autoShowHotelData != null) {
        _autoOpenHotel();
      }
    });
  }

  // Clear image cache if needed (can be called from settings or on error)
  Future<void> _clearImageCache() async {
    try {
      await DefaultCacheManager().emptyCache();
      debugPrint('Image cache cleared successfully');
    } catch (e) {
      debugPrint('Error clearing cache: $e');
    }
  }

  Future<void> _loadUserEvents() async {
    setState(() => _loadingEvents = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      // Parse savedEventIds safely
      final savedEventsData = userDoc.data()?['savedEvents'];
      final List<String> savedEventIds;

      if (savedEventsData is List) {
        savedEventIds = List<String>.from(savedEventsData);
      } else {
        savedEventIds = [];
      }

      if (savedEventIds.isEmpty) {
        setState(() {
          _userEvents = [];
          _loadingEvents = false;
        });
        return;
      }

      // Get event details
      final events = <Map<String, dynamic>>[];
      for (final eventId in savedEventIds.take(10)) {
        final eventDoc = await FirebaseFirestore.instance
            .collection('events_wembley')
            .doc(eventId)
            .get();

        if (eventDoc.exists) {
          events.add({'id': eventDoc.id, ...eventDoc.data()!});
        }
      }

      setState(() {
        _userEvents = events;
        _loadingEvents = false;
      });
    } catch (e) {
      debugPrint('Error loading user events: $e');
      setState(() => _loadingEvents = false);
    }
  }

  // ========== LOAD SAVED ACCOMMODATIONS ==========
  Future<void> _loadSavedAccommodations() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('savedAccommodation')
          .get();

      if (!mounted) return;
      setState(() {
        _savedAccommodationIds = snapshot.docs.map((doc) => doc.id).toSet();
      });
    } catch (e) {
      debugPrint('Error loading saved accommodations: $e');
    }
  }

  // ========== CHECK IF ACCOMMODATION IS SAVED ==========
  bool _isSaved(Map<String, dynamic> data) {
    final placeId = data['place_id'] as String?;
    return placeId != null && _savedAccommodationIds.contains(placeId);
  }

  // ========== SAVE/UNSAVE ACCOMMODATION ==========
  Future<void> _toggleSaveAccommodation(Map<String, dynamic> data) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please log in to save accommodations'),
          backgroundColor: Color(0xFFEF4444),
        ),
      );
      return;
    }

    final placeId = data['place_id'] as String?;
    if (placeId == null) return;

    final isSaved = _isSaved(data);

    try {
      if (isSaved) {
        // Remove from saved
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('savedAccommodation')
            .doc(placeId)
            .delete();

        setState(() {
          _savedAccommodationIds.remove(placeId);
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.white),
                  SizedBox(width: 12),
                  Text('Removed from favorites'),
                ],
              ),
              backgroundColor: const Color(0xFF64748B),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          );
        }
      } else {
        // Save accommodation
        final name = data['name'] as String? ?? 'Hotel';
        final imageUrl = _bestImageUrl(data);
        final rating = _toDouble(data['rating']);

        // Safely handle types field - could be List or String
        List<String> typesList = [];
        final typesData = data['types'];
        if (typesData is List) {
          typesList = typesData.map((e) => e.toString()).toList();
        } else if (typesData is String) {
          typesList = [typesData];
        }

        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('savedAccommodation')
            .doc(placeId)
            .set({
              'name': name,
              'location': 'Wembley',
              'imageUrl': imageUrl ?? '',
              'rating': rating,
              'pricePerNight': 0, // You can add price if available in your data
              'types': typesList,
              'bookingUrl': data['website'] ?? '',
              'savedAt': FieldValue.serverTimestamp(),
              'place_id': placeId,
            });

        setState(() {
          _savedAccommodationIds.add(placeId);
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Row(
                children: [
                  Icon(Icons.favorite, color: Colors.white),
                  SizedBox(width: 12),
                  Text('Added to favorites'),
                ],
              ),
              backgroundColor: const Color(0xFFEF4444),
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

  double? _distanceFromUser(Map<String, dynamic> hotelData) {
    if (_currentPosition == null) return null;

    final lat = _toDouble(hotelData['lat']);
    final lng = _toDouble(hotelData['lng']);

    if (lat == 0 || lng == 0) return null;

    return Geolocator.distanceBetween(
      _currentPosition!.latitude,
      _currentPosition!.longitude,
      lat,
      lng,
    );
  }

  double? _distanceToEvent(
    Map<String, dynamic> hotelData,
    Map<String, dynamic> event,
  ) {
    final hotelLat = _toDouble(hotelData['lat']);
    final hotelLng = _toDouble(hotelData['lng']);
    final eventLat = _toDouble(event['latitude']);
    final eventLng = _toDouble(event['longitude']);

    if (hotelLat == 0 || hotelLng == 0 || eventLat == 0 || eventLng == 0) {
      return null;
    }

    return Geolocator.distanceBetween(hotelLat, hotelLng, eventLat, eventLng);
  }

  double? _closestEventDistance(Map<String, dynamic> hotelData) {
    if (_userEvents.isEmpty) return null;

    double? minDist;
    for (final event in _userEvents) {
      final dist = _distanceToEvent(hotelData, event);
      if (dist != null) {
        if (minDist == null || dist < minDist) {
          minDist = dist;
        }
      }
    }
    return minDist;
  }

  String _formatDistance(double? meters) {
    if (meters == null) return '';
    const metersToMiles = 0.000621371;
    final miles = meters * metersToMiles;
    return '${miles.toStringAsFixed(1)} mi';
  }

  double _calculateValueScore(Map<String, dynamic> hotelData) {
    final rating = _toDouble(hotelData['rating']);
    // Assume average price of £100/night if not available
    // Higher rating, lower price = better value
    // Simple formula: rating / (price/100)
    // For now, use rating as proxy since we don't have prices yet
    return rating;
  }

  void _autoOpenHotel() {
    if (widget.autoShowHotelData == null) return;

    try {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Opening: ${widget.autoShowHotelData!['name'] ?? 'Hotel'}',
          ),
          backgroundColor: const Color(0xFF06B6D4),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );

      _showHotelInfo(widget.autoShowHotelData!);
    } catch (e) {
      debugPrint('Error auto-opening hotel: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not open hotel details'),
            backgroundColor: Color(0xFFEF4444),
          ),
        );
      }
    }
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _stream() {
    // Limit to 50 hotels to prevent memory issues with too many images
    return FirebaseFirestore.instance
        .collection(_collectionName)
        .orderBy('rating', descending: true)
        .limit(50) // Reduced from 250 to prevent memory crashes
        .snapshots();
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _applyFilters(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final under3 = _minRating == -1;

    final filtered = _minRating == null
        ? docs
        : docs.where((d) {
            final data = d.data();
            final ratingNum = data['rating'];
            final rating = (ratingNum is num) ? ratingNum.toDouble() : 0.0;

            if (under3) return rating < 3.0;
            return rating >= (_minRating ?? 0.0);
          }).toList();

    filtered.sort((a, b) {
      final dataA = a.data();
      final dataB = b.data();

      switch (_sortBy) {
        case 'distance':
          final distA = _distanceFromUser(dataA) ?? double.infinity;
          final distB = _distanceFromUser(dataB) ?? double.infinity;
          return distA.compareTo(distB);
        case 'rating':
          final ratingA = _toDouble(dataA['rating']);
          final ratingB = _toDouble(dataB['rating']);
          return ratingB.compareTo(ratingA);
        case 'name':
          final nameA = (dataA['name'] as String? ?? '').toLowerCase();
          final nameB = (dataB['name'] as String? ?? '').toLowerCase();
          return nameA.compareTo(nameB);
        case 'value':
          final valueA = _calculateValueScore(dataA);
          final valueB = _calculateValueScore(dataB);
          return valueB.compareTo(valueA);
        case 'nearEvents':
          final distA = _closestEventDistance(dataA) ?? double.infinity;
          final distB = _closestEventDistance(dataB) ?? double.infinity;
          return distA.compareTo(distB);
        default:
          return 0;
      }
    });

    return filtered;
  }

  // ═══════════════════════════════════════════════════════════════
  // BOTTOM SHEET: HOTEL INFO
  // ═══════════════════════════════════════════════════════════════

  void _showHotelInfo(Map<String, dynamic> data) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _HotelInfoBottomSheet(
        hotelData: data,
        distanceText: _formatDistance(_distanceFromUser(data)),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // BOTTOM SHEET: DIRECTIONS
  // ═══════════════════════════════════════════════════════════════

  void _showDirections(Map<String, dynamic> data) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _DirectionsBottomSheet(hotelData: data),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // BOTTOM SHEET: BOOK NOW
  // ═══════════════════════════════════════════════════════════════

  void _showBookingOptions(Map<String, dynamic> data) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _BookingBottomSheet(hotelData: data),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: CustomScrollView(
        slivers: [
          // App Bar
          SliverAppBar(
            floating: true,
            snap: true,
            backgroundColor: Colors.white,
            elevation: 0,
            title: const Text(
              'Accommodation',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                color: Color(0xFF0F172A),
              ),
            ),
            actions: [
              // View mode toggle
              Container(
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    _buildViewModeButton(
                      icon: Icons.grid_view_rounded,
                      isSelected: _viewMode == _AccommodationViewMode.grid,
                      onTap: () => setState(
                        () => _viewMode = _AccommodationViewMode.grid,
                      ),
                    ),
                    _buildViewModeButton(
                      icon: Icons.view_list_rounded,
                      isSelected: _viewMode == _AccommodationViewMode.list,
                      onTap: () => setState(
                        () => _viewMode = _AccommodationViewMode.list,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          // Smart Sorting Pills
          SliverToBoxAdapter(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  _buildSortChip(
                    label: '📍 Nearest',
                    value: 'distance',
                    isEnabled: _currentPosition != null,
                    tooltip: _currentPosition == null
                        ? 'Enable location'
                        : null,
                  ),
                  const SizedBox(width: 8),
                  _buildSortChip(
                    label: '⭐ Top Rated',
                    value: 'rating',
                    isEnabled: true,
                  ),
                  const SizedBox(width: 8),
                  _buildSortChip(
                    label: '💎 Best Value',
                    value: 'value',
                    isEnabled: true,
                  ),
                  const SizedBox(width: 8),
                  _buildSortChip(
                    label: '🎫 Near Events',
                    value: 'nearEvents',
                    isEnabled: _userEvents.isNotEmpty,
                    tooltip: _userEvents.isEmpty ? 'Save events first' : null,
                  ),
                  const SizedBox(width: 8),
                  _buildSortChip(
                    label: '🔤 A-Z',
                    value: 'name',
                    isEnabled: true,
                  ),
                ],
              ),
            ),
          ),

          // Rating Filter
          SliverToBoxAdapter(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(left: 16, right: 16, bottom: 12),
              child: Row(
                children: _ratingFilters.map((filter) {
                  final selected = _minRating == filter.min;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      selected: selected,
                      label: Text(filter.label),
                      labelStyle: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: selected
                            ? Colors.white
                            : const Color(0xFF64748B),
                        fontSize: 13,
                      ),
                      backgroundColor: Colors.white,
                      selectedColor: const Color(0xFF4F46E5),
                      checkmarkColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 8,
                      ),
                      onSelected: (_) {
                        setState(() => _minRating = filter.min);
                      },
                    ),
                  );
                }).toList(),
              ),
            ),
          ),

          // Hotel Grid/List
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _stream(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: _EmptyStateCard(
                      title: 'Connection Error',
                      subtitle: 'Please check your internet and try again.',
                      cta: 'Retry',
                      onTap: () => setState(() {}),
                    ),
                  ),
                );
              }

              if (!snapshot.hasData) {
                return const _SkeletonSliver();
              }

              final allDocs = snapshot.data!.docs;
              final filtered = _applyFilters(allDocs);

              if (filtered.isEmpty) {
                return SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: _EmptyStateCard(
                      title: 'No hotels found',
                      subtitle:
                          'Try adjusting your filters or search criteria.',
                      cta: 'Clear Filters',
                      onTap: () => setState(() => _minRating = null),
                    ),
                  ),
                );
              }

              if (_viewMode == _AccommodationViewMode.grid) {
                return SliverPadding(
                  padding: const EdgeInsets.all(16),
                  sliver: SliverGrid(
                    delegate: SliverChildBuilderDelegate(
                      (context, i) => _buildGridCard(filtered[i].data(), i),
                      childCount: filtered.length,
                    ),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: 14,
                          crossAxisSpacing: 14,
                          childAspectRatio:
                              0.68, // Optimized for image aspect ratio 1.5
                        ),
                  ),
                );
              } else {
                return SliverPadding(
                  padding: const EdgeInsets.all(16),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, i) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _buildListCard(filtered[i].data()),
                      ),
                      childCount: filtered.length,
                    ),
                  ),
                );
              }
            },
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 20)),
        ],
      ),
    );
  }

  Widget _buildViewModeButton({
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF4F46E5) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          icon,
          color: isSelected ? Colors.white : const Color(0xFF94A3B8),
          size: 20,
        ),
      ),
    );
  }

  Widget _buildSortChip({
    required String label,
    required String value,
    required bool isEnabled,
    String? tooltip,
  }) {
    final selected = _sortBy == value;

    Widget chip = FilterChip(
      selected: selected,
      label: Text(label),
      labelStyle: TextStyle(
        fontWeight: FontWeight.w800,
        color: selected
            ? Colors.white
            : (isEnabled ? const Color(0xFF64748B) : const Color(0xFFCBD5E1)),
        fontSize: 13,
      ),
      backgroundColor: Colors.white,
      selectedColor: const Color(0xFF06B6D4),
      checkmarkColor: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      onSelected: isEnabled
          ? (_) {
              setState(() => _sortBy = value);
            }
          : null,
    );

    if (tooltip != null && !isEnabled) {
      return Tooltip(message: tooltip, child: chip);
    }

    return chip;
  }

  // ═══════════════════════════════════════════════════════════════
  // GRID CARD WITH ACTION ICONS
  // ═══════════════════════════════════════════════════════════════

  Widget _buildGridCard(Map<String, dynamic> data, int index) {
    final name = data['name'] as String? ?? 'Hotel';
    final rating = _toDouble(data['rating']);
    final reviewCount = _toInt(data['user_ratings_total']);
    final imageUrl = _bestImageUrl(data);
    final distanceText = _formatDistance(_distanceFromUser(data));

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Image with memory-efficient loading and error handling
          Stack(
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
                child: AspectRatio(
                  aspectRatio: 1.5, // User's working value
                  child: imageUrl != null
                      ? CachedNetworkImage(
                          imageUrl: imageUrl,
                          fit: BoxFit.cover,
                          maxHeightDiskCache: 400,
                          maxWidthDiskCache: 400,
                          memCacheHeight: 200,
                          memCacheWidth: 200,
                          fadeInDuration: const Duration(milliseconds: 200),
                          placeholder: (_, __) => Container(
                            color: Colors.grey.shade100,
                            child: Center(
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.grey.shade400,
                                ),
                              ),
                            ),
                          ),
                          errorWidget: (context, url, error) {
                            // Clear this specific image from cache on error
                            CachedNetworkImage.evictFromCache(url);
                            return _ImageFallback(title: name);
                          },
                        )
                      : _ImageFallback(title: name),
                ),
              ),
              // Favorite Button
              Positioned(
                top: 8,
                right: 8,
                child: GestureDetector(
                  onTap: () => _toggleSaveAccommodation(data),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Icon(
                      _isSaved(data) ? Icons.favorite : Icons.favorite_border,
                      color: const Color(0xFFEF4444),
                      size: 20,
                    ),
                  ),
                ),
              ),
            ],
          ),

          // Content with fixed height for alignment
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(10), // Reduced from 12
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Hotel name with FIXED HEIGHT (ensures consistency for 1-line or 2-line names)
                  SizedBox(
                    height: 34, // Reduced from 36 to save space
                    child: Text(
                      name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF0F172A),
                        fontSize: 13, // Slightly reduced from 14
                        height: 1.3,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4), // Reduced from 6
                  // Rating row
                  Row(
                    children: [
                      _Stars(rating: rating),
                      const SizedBox(width: 4),
                      Text(
                        rating.toStringAsFixed(1),
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF64748B),
                          fontSize: 11, // Reduced from 12
                        ),
                      ),
                      if (reviewCount > 0) ...[
                        Text(
                          ' (${reviewCount > 1000 ? '${(reviewCount / 1000).toStringAsFixed(1)}k' : reviewCount})',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF94A3B8),
                            fontSize: 10, // Reduced from 11
                          ),
                        ),
                      ],
                    ],
                  ),

                  // Distance badge
                  if (distanceText.isNotEmpty) ...[
                    const SizedBox(height: 4), // Reduced from 6
                    Row(
                      children: [
                        const Icon(
                          Icons.location_on,
                          size: 12, // Reduced from 14
                          color: Color(0xFF3B82F6),
                        ),
                        const SizedBox(width: 3),
                        Text(
                          distanceText,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF3B82F6),
                            fontSize: 11, // Reduced from 12
                          ),
                        ),
                      ],
                    ),
                  ],

                  const Spacer(),

                  // Action Icons Row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildActionIcon(
                        icon: Icons.info_outline_rounded,
                        label: 'Info',
                        color: const Color(0xFF4F46E5),
                        onTap: () => _showHotelInfo(data),
                      ),
                      _buildActionIcon(
                        icon: Icons.directions_rounded,
                        label: 'Route',
                        color: const Color(0xFF059669),
                        onTap: () => _showDirections(data),
                      ),
                      _buildActionIcon(
                        icon: Icons.hotel_rounded,
                        label: 'Book',
                        color: const Color(0xFF06B6D4),
                        onTap: () => _showBookingOptions(data),
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

  Widget _buildActionIcon({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: 2,
          vertical: 4,
        ), // Reduced padding
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(6), // Reduced from 8
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8), // Reduced from 10
              ),
              child: Icon(
                icon,
                color: color,
                size: 16, // Reduced from 18
              ),
            ),
            const SizedBox(height: 2), // Reduced from 3
            Text(
              label,
              style: TextStyle(
                fontSize: 9, // Reduced from 10
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // LIST CARD
  // ═══════════════════════════════════════════════════════════════

  Widget _buildListCard(Map<String, dynamic> data) {
    final name = data['name'] as String? ?? 'Hotel';
    final rating = _toDouble(data['rating']);
    final reviewCount = _toInt(data['user_ratings_total']);
    final imageUrl = _bestImageUrl(data);
    final distanceText = _formatDistance(_distanceFromUser(data));

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          // Image with memory-efficient loading and error handling
          ClipRRect(
            borderRadius: const BorderRadius.horizontal(
              left: Radius.circular(20),
            ),
            child: SizedBox(
              width: 110,
              height: 110,
              child: imageUrl != null
                  ? CachedNetworkImage(
                      imageUrl: imageUrl,
                      fit: BoxFit.cover,
                      maxHeightDiskCache: 300,
                      maxWidthDiskCache: 300,
                      memCacheHeight: 150,
                      memCacheWidth: 150,
                      fadeInDuration: const Duration(milliseconds: 200),
                      placeholder: (_, __) => Container(
                        color: Colors.grey.shade100,
                        child: Center(
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.grey.shade400,
                            ),
                          ),
                        ),
                      ),
                      errorWidget: (context, url, error) {
                        CachedNetworkImage.evictFromCache(url);
                        return _ImageFallback(title: name);
                      },
                    )
                  : _ImageFallback(title: name),
            ),
          ),

          // Content
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF0F172A),
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      _Stars(rating: rating),
                      const SizedBox(width: 6),
                      Text(
                        rating.toStringAsFixed(1),
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF64748B),
                          fontSize: 12,
                        ),
                      ),
                      if (reviewCount > 0)
                        Text(
                          ' ($reviewCount)',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF94A3B8),
                            fontSize: 11,
                          ),
                        ),
                    ],
                  ),
                  if (distanceText.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(
                          Icons.location_on,
                          size: 14,
                          color: Color(0xFF3B82F6),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          distanceText,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF3B82F6),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),

          // Action icons column
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  onPressed: () => _toggleSaveAccommodation(data),
                  icon: Icon(
                    _isSaved(data) ? Icons.favorite : Icons.favorite_border,
                  ),
                  color: const Color(0xFFEF4444),
                  iconSize: 22,
                ),
                IconButton(
                  onPressed: () => _showHotelInfo(data),
                  icon: const Icon(Icons.info_outline_rounded),
                  color: const Color(0xFF4F46E5),
                  iconSize: 22,
                ),
                IconButton(
                  onPressed: () => _showDirections(data),
                  icon: const Icon(Icons.directions_rounded),
                  color: const Color(0xFF059669),
                  iconSize: 22,
                ),
                IconButton(
                  onPressed: () => _showBookingOptions(data),
                  icon: const Icon(Icons.hotel_rounded),
                  color: const Color(0xFF06B6D4),
                  iconSize: 22,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// BOTTOM SHEET: HOTEL INFO
// ═══════════════════════════════════════════════════════════════

class _HotelInfoBottomSheet extends StatelessWidget {
  final Map<String, dynamic> hotelData;
  final String distanceText;

  const _HotelInfoBottomSheet({
    required this.hotelData,
    required this.distanceText,
  });

  @override
  Widget build(BuildContext context) {
    final name = hotelData['name'] as String? ?? 'Hotel';
    final rating = _toDouble(hotelData['rating']);
    final reviewCount = _toInt(hotelData['user_ratings_total']);
    final address =
        hotelData['vicinity'] as String? ??
        hotelData['formatted_address'] as String? ??
        'Wembley, London';
    final imageUrl = _bestImageUrl(hotelData);

    // Extract amenities if available
    // Parse amenities/types safely (handle both String and List)
    final typesData = hotelData['types'];
    final List<String> types;

    if (typesData is List) {
      types = List<String>.from(typesData);
    } else if (typesData is String && typesData.isNotEmpty) {
      // If it's a comma-separated string, split it
      types = typesData.split(',').map((e) => e.trim()).toList();
    } else {
      types = [];
    }

    final amenities = types
        .where(
          (t) => !['point_of_interest', 'establishment', 'lodging'].contains(t),
        )
        .toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            children: [
              // Handle
              Container(
                margin: const EdgeInsets.only(top: 12),
                height: 4,
                width: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFFCBD5E1),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(20),
                  children: [
                    // Hotel image with memory-efficient loading and error handling
                    if (imageUrl != null)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: AspectRatio(
                          aspectRatio: 16 / 9,
                          child: CachedNetworkImage(
                            imageUrl: imageUrl,
                            fit: BoxFit.cover,
                            maxHeightDiskCache: 600,
                            maxWidthDiskCache: 800,
                            memCacheHeight: 300,
                            memCacheWidth: 400,
                            fadeInDuration: const Duration(milliseconds: 200),
                            placeholder: (_, __) => Container(
                              color: Colors.grey.shade100,
                              child: Center(
                                child: CircularProgressIndicator(
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.grey.shade400,
                                  ),
                                ),
                              ),
                            ),
                            errorWidget: (context, url, error) {
                              CachedNetworkImage.evictFromCache(url);
                              return Container(
                                color: Colors.grey.shade200,
                                child: Icon(
                                  Icons.hotel_rounded,
                                  size: 48,
                                  color: Colors.grey.shade400,
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    const SizedBox(height: 16),

                    // Hotel name
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Rating
                    Row(
                      children: [
                        _Stars(rating: rating),
                        const SizedBox(width: 8),
                        Text(
                          rating.toStringAsFixed(1),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF64748B),
                          ),
                        ),
                        if (reviewCount > 0)
                          Text(
                            ' ($reviewCount reviews)',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF94A3B8),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Address
                    _InfoRow(
                      icon: Icons.location_on_outlined,
                      label: 'Address',
                      value: address,
                    ),
                    if (distanceText.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _InfoRow(
                        icon: Icons.directions_walk_rounded,
                        label: 'Distance',
                        value: distanceText,
                      ),
                    ],

                    // Amenities
                    if (amenities.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      const Text(
                        'Amenities',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: amenities.map((amenity) {
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEEF2FF),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              _formatAmenity(amenity),
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF4F46E5),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],

                    const SizedBox(height: 24),

                    // Action buttons
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () {
                              Navigator.pop(context);
                              _showDirectionsSheet(context, hotelData);
                            },
                            icon: const Icon(Icons.directions_rounded),
                            label: const Text('Directions'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF059669),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () {
                              Navigator.pop(context);
                              _showBookingSheet(context, hotelData);
                            },
                            icon: const Icon(Icons.hotel_rounded),
                            label: const Text('Book Now'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF06B6D4),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _formatAmenity(String amenity) {
    return amenity
        .replaceAll('_', ' ')
        .split(' ')
        .map(
          (word) =>
              word.isEmpty ? '' : word[0].toUpperCase() + word.substring(1),
        )
        .join(' ');
  }

  static void _showDirectionsSheet(
    BuildContext context,
    Map<String, dynamic> data,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _DirectionsBottomSheet(hotelData: data),
    );
  }

  static void _showBookingSheet(
    BuildContext context,
    Map<String, dynamic> data,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _BookingBottomSheet(hotelData: data),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow({
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
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 20, color: const Color(0xFF64748B)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF94A3B8),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 15,
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

// ═══════════════════════════════════════════════════════════════
// BOTTOM SHEET: DIRECTIONS
// ═══════════════════════════════════════════════════════════════

class _DirectionsBottomSheet extends StatelessWidget {
  final Map<String, dynamic> hotelData;

  const _DirectionsBottomSheet({required this.hotelData});

  Future<void> _openMaps(String type) async {
    final name = hotelData['name'] as String? ?? 'Hotel';
    final lat = _toDouble(hotelData['lat']);
    final lng = _toDouble(hotelData['lng']);
    final placeId = hotelData['place_id'] as String?;

    String url;

    switch (type) {
      case 'google':
        if (placeId != null && placeId.isNotEmpty) {
          url =
              'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(name)}&query_place_id=$placeId';
        } else {
          url = 'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng';
        }
        break;
      case 'waze':
        url = 'https://waze.com/ul?ll=$lat,$lng&navigate=yes';
        break;
      case 'apple':
        url = 'http://maps.apple.com/?daddr=$lat,$lng';
        break;
      default:
        return;
    }

    final uri = Uri.parse(url);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            height: 4,
            width: 40,
            decoration: BoxDecoration(
              color: const Color(0xFFCBD5E1),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),

          const Text(
            'Get Directions',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 20),

          // Google Maps
          _DirectionOption(
            icon: Icons.map_rounded,
            label: 'Google Maps',
            color: const Color(0xFF059669),
            onTap: () {
              Navigator.pop(context);
              _openMaps('google');
            },
          ),
          const SizedBox(height: 12),

          // Waze
          _DirectionOption(
            icon: Icons.navigation_rounded,
            label: 'Waze',
            color: const Color(0xFF06B6D4),
            onTap: () {
              Navigator.pop(context);
              _openMaps('waze');
            },
          ),
          const SizedBox(height: 12),

          // Apple Maps
          _DirectionOption(
            icon: Icons.map_outlined,
            label: 'Apple Maps',
            color: const Color(0xFF64748B),
            onTap: () {
              Navigator.pop(context);
              _openMaps('apple');
            },
          ),

          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

class _DirectionOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _DirectionOption({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: Colors.white, size: 24),
            ),
            const SizedBox(width: 16),
            Text(
              label,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
            const Spacer(),
            Icon(Icons.arrow_forward_ios_rounded, color: color, size: 18),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// BOTTOM SHEET: BOOKING OPTIONS
// ═══════════════════════════════════════════════════════════════

class _BookingBottomSheet extends StatelessWidget {
  final Map<String, dynamic> hotelData;

  const _BookingBottomSheet({required this.hotelData});

  Future<void> _openBookingSite(String type) async {
    final name = hotelData['name'] as String? ?? 'Hotel';
    final website = hotelData['website'] as String?;

    String url;

    switch (type) {
      case 'official':
        if (website != null && website.isNotEmpty) {
          url = website;
        } else {
          // Google search for official website
          url =
              'https://www.google.com/search?q=${Uri.encodeComponent('$name Wembley official website')}';
        }
        break;
      case 'booking':
        url =
            'https://www.booking.com/search.html?ss=${Uri.encodeComponent('$name Wembley')}';
        break;
      case 'expedia':
        url =
            'https://www.expedia.co.uk/Hotel-Search?destination=${Uri.encodeComponent('$name Wembley')}';
        break;
      case 'hotels':
        url =
            'https://www.hotels.com/search.do?q-destination=${Uri.encodeComponent('$name Wembley')}';
        break;
      case 'trivago':
        url =
            'https://www.trivago.co.uk/?search=200-${Uri.encodeComponent(name)}';
        break;
      default:
        return;
    }

    final uri = Uri.parse(url);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final name = hotelData['name'] as String? ?? 'Hotel';

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            height: 4,
            width: 40,
            decoration: BoxDecoration(
              color: const Color(0xFFCBD5E1),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),

          Text(
            'Book $name',
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: Color(0xFF0F172A),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          const Text(
            'Compare prices across booking sites',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 20),

          // Official Website
          _BookingOption(
            label: 'Official Website',
            icon: Icons.language_rounded,
            color: const Color(0xFF4F46E5),
            onTap: () {
              Navigator.pop(context);
              _openBookingSite('official');
            },
          ),
          const SizedBox(height: 10),

          // Booking.com
          _BookingOption(
            label: 'Booking.com',
            icon: Icons.hotel_rounded,
            color: const Color(0xFF003580),
            onTap: () {
              Navigator.pop(context);
              _openBookingSite('booking');
            },
          ),
          const SizedBox(height: 10),

          // Expedia
          _BookingOption(
            label: 'Expedia',
            icon: Icons.flight_takeoff_rounded,
            color: const Color(0xFFFFD133),
            onTap: () {
              Navigator.pop(context);
              _openBookingSite('expedia');
            },
          ),
          const SizedBox(height: 10),

          // Hotels.com
          _BookingOption(
            label: 'Hotels.com',
            icon: Icons.bed_rounded,
            color: const Color(0xFFD32F2F),
            onTap: () {
              Navigator.pop(context);
              _openBookingSite('hotels');
            },
          ),
          const SizedBox(height: 10),

          // Trivago
          _BookingOption(
            label: 'Trivago',
            icon: Icons.compare_arrows_rounded,
            color: const Color(0xFFEF6C00),
            onTap: () {
              Navigator.pop(context);
              _openBookingSite('trivago');
            },
          ),

          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

class _BookingOption extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _BookingOption({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.15)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: 14),
            Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
            const Spacer(),
            Icon(Icons.open_in_new_rounded, color: color, size: 18),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// HELPER WIDGETS
// ═══════════════════════════════════════════════════════════════

class _RatingFilter {
  final String label;
  final double? min;
  const _RatingFilter({required this.label, required this.min});
}

class _Stars extends StatelessWidget {
  final double rating;
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
        return Icon(
          icon,
          size: 14,
          color: const Color(0xFFF59E0B),
        ); // Reduced from 16
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
        mainAxisSpacing: 14,
        crossAxisSpacing: 14,
        childAspectRatio: 0.68,
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// HELPER FUNCTIONS
// ═══════════════════════════════════════════════════════════════

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

String? _bestImageUrl(Map<String, dynamic> data) {
  final cachedUrl = (data['cachedPhotoUrl'] as String?)?.trim();
  if (cachedUrl != null && cachedUrl.isNotEmpty) return cachedUrl;

  final photoUrl = (data['photoUrl'] as String?)?.trim();
  if (photoUrl != null && photoUrl.isNotEmpty) return photoUrl;

  final image = (data['imageUrl'] as String?)?.trim();
  if (image != null && image.isNotEmpty) return image;

  return null;
}
