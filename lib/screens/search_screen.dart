import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';

// Import your screens (update paths as needed)
import 'events_screen.dart';
import 'dining_screen.dart';
import 'accommodation_screen.dart';

// Import your screens (update paths as needed)

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  final _db = FirebaseFirestore.instance;

  List<SearchResult> _results = [];
  bool _isSearching = false;
  String _selectedCategory = 'all'; // all, events, dining, accommodation

  @override
  void initState() {
    super.initState();
    _searchFocus.requestFocus();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _performSearch(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _results = [];
        _isSearching = false;
      });
      return;
    }

    setState(() => _isSearching = true);

    try {
      final results = <SearchResult>[];
      final lowerQuery = query.toLowerCase().trim();

      // Search Events
      if (_selectedCategory == 'all' || _selectedCategory == 'events') {
        final eventsSnapshot = await _db
            .collection('events_wembley')
            .limit(50)
            .get();

        for (final doc in eventsSnapshot.docs) {
          final data = doc.data();
          final title = (data['title'] ?? '').toString().toLowerCase();
          final venue = (data['venueName'] ?? data['venue'] ?? '')
              .toString()
              .toLowerCase();
          final category = (data['category'] ?? '').toString().toLowerCase();

          if (title.contains(lowerQuery) ||
              venue.contains(lowerQuery) ||
              category.contains(lowerQuery)) {
            results.add(SearchResult.fromEvent(doc.id, data));
          }
        }
      }

      // Search Dining
      if (_selectedCategory == 'all' || _selectedCategory == 'dining') {
        final diningSnapshot = await _db
            .collection('Dining_wembley')
            .limit(50)
            .get();

        for (final doc in diningSnapshot.docs) {
          final data = doc.data();
          final name = (data['name'] ?? '').toString().toLowerCase();
          final cuisine = (data['cuisine'] ?? data['types'] ?? '')
              .toString()
              .toLowerCase();
          final address = (data['address'] ?? '').toString().toLowerCase();

          if (name.contains(lowerQuery) ||
              cuisine.contains(lowerQuery) ||
              address.contains(lowerQuery)) {
            results.add(SearchResult.fromDining(doc.id, data));
          }
        }
      }

      // Search Accommodation
      if (_selectedCategory == 'all' || _selectedCategory == 'accommodation') {
        final accommodationSnapshot = await _db
            .collection('accommodations_wembley')
            .limit(50)
            .get();

        for (final doc in accommodationSnapshot.docs) {
          final data = doc.data();
          final name = (data['name'] ?? data['title'] ?? '')
              .toString()
              .toLowerCase();
          final type = (data['type'] ?? data['category'] ?? '')
              .toString()
              .toLowerCase();
          final address = (data['address'] ?? '').toString().toLowerCase();

          if (name.contains(lowerQuery) ||
              type.contains(lowerQuery) ||
              address.contains(lowerQuery)) {
            results.add(SearchResult.fromAccommodation(doc.id, data));
          }
        }
      }

      // Sort by relevance (exact matches first, then contains)
      results.sort((a, b) {
        final aExact = a.title.toLowerCase() == lowerQuery;
        final bExact = b.title.toLowerCase() == lowerQuery;
        if (aExact && !bExact) return -1;
        if (!aExact && bExact) return 1;
        return 0;
      });

      if (mounted) {
        setState(() {
          _results = results;
          _isSearching = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSearching = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Search failed: $e'),
            backgroundColor: const Color(0xFFEF4444),
          ),
        );
      }
    }
  }

  void _onResultTap(SearchResult result) {
    // OPTION 1: Show detail sheet first (current behavior)
    // Navigate based on result type
    switch (result.type) {
      case SearchResultType.event:
        _showEventDetail(result);
        break;
      case SearchResultType.dining:
        _showDiningDetail(result);
        break;
      case SearchResultType.accommodation:
        _showAccommodationDetail(result);
        break;
    }

    // OPTION 2: Direct navigation (skip detail sheet)
    // Uncomment this and comment out the switch above if you want immediate navigation:
    /*
    Navigator.pop(context); // Close search
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Opening ${result.type.label} → ${result.title}'),
        backgroundColor: result.type.color,
        behavior: SnackBarBehavior.floating,
      ),
    );
    // Add your navigation here:
    // Navigator.pushNamed(context, '/events'); // or /dining or /accommodation
    */
  }

  void _showEventDetail(SearchResult result) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.all(24),
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              if (result.imageUrl != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: CachedNetworkImage(
                    imageUrl: result.imageUrl!,
                    height: 200,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                ),
              const SizedBox(height: 16),
              Text(
                result.title,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 8),
              if (result.subtitle != null)
                Text(
                  result.subtitle!,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF64748B),
                  ),
                ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  // Close detail sheet
                  Navigator.pop(context);
                  // Close search screen
                  Navigator.pop(context);

                  // Navigate to Events screen with auto-show parameters
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => EventsListScreen(
                        autoShowEventId: result.id,
                        autoShowEventData: result.data,
                      ),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7C3AED),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'View in Events',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDiningDetail(SearchResult result) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.all(24),
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              if (result.imageUrl != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: CachedNetworkImage(
                    imageUrl: result.imageUrl!,
                    height: 200,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                ),
              const SizedBox(height: 16),
              Text(
                result.title,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 8),
              if (result.subtitle != null)
                Row(
                  children: [
                    const Icon(
                      Icons.place_rounded,
                      size: 16,
                      color: Color(0xFF64748B),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        result.subtitle!,
                        style: const TextStyle(
                          fontSize: 14,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  // Close detail sheet
                  Navigator.pop(context);
                  // Close search screen
                  Navigator.pop(context);

                  // Navigate to Dining screen with auto-show parameters
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AdvancedDiningScreen(
                        autoShowRestaurantId: result.id,
                        autoShowRestaurantData: result.data,
                      ),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7C3AED),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'View in Dining',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAccommodationDetail(SearchResult result) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.all(24),
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              if (result.imageUrl != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: CachedNetworkImage(
                    imageUrl: result.imageUrl!,
                    height: 200,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                ),
              const SizedBox(height: 16),
              Text(
                result.title,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 8),
              if (result.subtitle != null)
                Text(
                  result.subtitle!,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF64748B),
                  ),
                ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  // Close detail sheet
                  Navigator.pop(context);
                  // Close search screen
                  Navigator.pop(context);

                  // Navigate to Accommodation screen with auto-show parameters
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AccommodationScreen(
                        autoShowHotelId: result.id,
                        autoShowHotelData: result.data,
                      ),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7C3AED),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'View in Accommodation',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FF),
      body: SafeArea(
        child: Column(
          children: [
            // Search Header
            Container(
              padding: const EdgeInsets.all(16),
              color: Colors.white,
              child: Column(
                children: [
                  // Search Bar
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back_rounded),
                        onPressed: () => Navigator.pop(context),
                      ),
                      Expanded(
                        child: Container(
                          height: 48,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: TextField(
                            controller: _searchController,
                            focusNode: _searchFocus,
                            onChanged: (value) {
                              _performSearch(value);
                            },
                            decoration: InputDecoration(
                              hintText:
                                  'Search events, dining, accommodation...',
                              hintStyle: const TextStyle(
                                color: Color(0xFF94A3B8),
                                fontSize: 14,
                              ),
                              prefixIcon: const Icon(
                                Icons.search_rounded,
                                color: Color(0xFF64748B),
                              ),
                              suffixIcon: _searchController.text.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(
                                        Icons.clear_rounded,
                                        color: Color(0xFF64748B),
                                      ),
                                      onPressed: () {
                                        _searchController.clear();
                                        _performSearch('');
                                      },
                                    )
                                  : null,
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Category Filter
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildCategoryChip('All', 'all', Icons.apps_rounded),
                        const SizedBox(width: 8),
                        _buildCategoryChip(
                          'Events',
                          'events',
                          Icons.event_rounded,
                        ),
                        const SizedBox(width: 8),
                        _buildCategoryChip(
                          'Dining',
                          'dining',
                          Icons.restaurant_rounded,
                        ),
                        const SizedBox(width: 8),
                        _buildCategoryChip(
                          'Stay',
                          'accommodation',
                          Icons.hotel_rounded,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Results
            Expanded(
              child: _isSearching
                  ? _buildLoadingState()
                  : _searchController.text.isEmpty
                  ? _buildEmptyState()
                  : _results.isEmpty
                  ? _buildNoResultsState()
                  : _buildResultsList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryChip(String label, String value, IconData icon) {
    final isSelected = _selectedCategory == value;
    return GestureDetector(
      onTap: () {
        setState(() => _selectedCategory = value);
        _performSearch(_searchController.text);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF7C3AED) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF7C3AED)
                : const Color(0xFFE2E8F0),
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected ? Colors.white : const Color(0xFF64748B),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: isSelected ? Colors.white : const Color(0xFF64748B),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: 5,
      itemBuilder: (context, index) {
        return Shimmer.fromColors(
          baseColor: Colors.grey.shade200,
          highlightColor: Colors.grey.shade100,
          child: Container(
            height: 80,
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: const BoxDecoration(
                color: Color(0xFFEEF2FF),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.search_rounded,
                size: 64,
                color: Color(0xFF7C3AED),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Search Wembley',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Find events, restaurants, and places to stay',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Color(0xFF64748B)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoResultsState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: const BoxDecoration(
                color: Color(0xFFFEF2F2),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.search_off_rounded,
                size: 64,
                color: Color(0xFFEF4444),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'No results found',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Try searching for "${_searchController.text}" with different keywords',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: Color(0xFF64748B)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultsList() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _results.length,
      itemBuilder: (context, index) {
        final result = _results[index];
        return _buildResultCard(result);
      },
    );
  }

  Widget _buildResultCard(SearchResult result) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _onResultTap(result),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                // Image or Icon
                if (result.imageUrl != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: CachedNetworkImage(
                      imageUrl: result.imageUrl!,
                      width: 60,
                      height: 60,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => Container(
                        width: 60,
                        height: 60,
                        color: Colors.grey.shade200,
                      ),
                      errorWidget: (context, url, error) => Container(
                        width: 60,
                        height: 60,
                        color: Colors.grey.shade200,
                        child: Icon(
                          result.type.icon,
                          color: Colors.grey.shade400,
                        ),
                      ),
                    ),
                  )
                else
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: result.type.color.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      result.type.icon,
                      color: result.type.color,
                      size: 28,
                    ),
                  ),
                const SizedBox(width: 12),

                // Content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: result.type.color.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              result.type.label,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: result.type.color,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        result.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      if (result.subtitle != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          result.subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                // Arrow
                const Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 16,
                  color: Color(0xFF94A3B8),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Search Result Model
class SearchResult {
  final String id;
  final String title;
  final String? subtitle;
  final String? imageUrl;
  final SearchResultType type;
  final Map<String, dynamic> data;

  SearchResult({
    required this.id,
    required this.title,
    this.subtitle,
    this.imageUrl,
    required this.type,
    required this.data,
  });

  factory SearchResult.fromEvent(String id, Map<String, dynamic> data) {
    return SearchResult(
      id: id,
      title: data['title'] ?? 'Untitled Event',
      subtitle: data['venueName'] ?? data['venue'],
      imageUrl: data['imageUrl'] ?? data['photoUrl'],
      type: SearchResultType.event,
      data: data,
    );
  }

  factory SearchResult.fromDining(String id, Map<String, dynamic> data) {
    return SearchResult(
      id: id,
      title: data['name'] ?? 'Untitled Restaurant',
      subtitle: data['address'] ?? data['cuisine'],
      imageUrl: data['photoUrl'] ?? data['photoReference'],
      type: SearchResultType.dining,
      data: data,
    );
  }

  factory SearchResult.fromAccommodation(String id, Map<String, dynamic> data) {
    return SearchResult(
      id: id,
      title: data['name'] ?? data['title'] ?? 'Untitled Accommodation',
      subtitle: data['address'] ?? data['type'],
      imageUrl: data['imageUrl'] ?? data['photoUrl'],
      type: SearchResultType.accommodation,
      data: data,
    );
  }
}

// Search Result Type Enum
enum SearchResultType {
  event,
  dining,
  accommodation;

  String get label {
    switch (this) {
      case SearchResultType.event:
        return 'EVENT';
      case SearchResultType.dining:
        return 'DINING';
      case SearchResultType.accommodation:
        return 'STAY';
    }
  }

  IconData get icon {
    switch (this) {
      case SearchResultType.event:
        return Icons.event_rounded;
      case SearchResultType.dining:
        return Icons.restaurant_rounded;
      case SearchResultType.accommodation:
        return Icons.hotel_rounded;
    }
  }

  Color get color {
    switch (this) {
      case SearchResultType.event:
        return const Color(0xFF7C3AED);
      case SearchResultType.dining:
        return const Color(0xFFEF4444);
      case SearchResultType.accommodation:
        return const Color(0xFF06B6D4);
    }
  }
}
