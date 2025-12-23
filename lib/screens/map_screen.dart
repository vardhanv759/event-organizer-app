import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with TickerProviderStateMixin {
  static const String _googleApiKey = 'AIzaSyBFiXKXDIPcHGAg_0zwFze_D1xsmWn8GkU';

  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  GoogleMapController? _mapController;

  static const LatLng _initialPosition = LatLng(51.5074, -0.1278);

  LatLng? _currentLocation;
  LatLng? _searchedPosition;
  String? _searchedAddress;
  bool _isSearching = false;
  bool _showSearchSuggestions = false;
  bool _isLocating = false;

  List<AddressSuggestion> _suggestions = [];
  Set<Marker> _markers = {};

  late AnimationController _slideController;

  @override
  void initState() {
    super.initState();
    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _initLocation();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    _slideController.dispose();
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _initLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.always ||
          permission == LocationPermission.whileInUse) {
        final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        );
        setState(() {
          _currentLocation = LatLng(position.latitude, position.longitude);
        });
        _updateMarkers();
      }
    } catch (_) {}
  }

  Future<void> _getCurrentLocation() async {
    setState(() => _isLocating = true);

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _showSnackBar('Location service is disabled', Colors.red);
        setState(() => _isLocating = false);
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _showSnackBar('Location permission denied', Colors.red);
        setState(() => _isLocating = false);
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      setState(() {
        _currentLocation = LatLng(position.latitude, position.longitude);
        _isLocating = false;
      });

      _updateMarkers();

      if (_mapController != null) {
        await _mapController!.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(target: _currentLocation!, zoom: 16),
          ),
        );
      }

      _showSnackBar('📍 Your location', Colors.green);
    } catch (e) {
      _showSnackBar('Failed to get location: $e', Colors.red);
      setState(() => _isLocating = false);
    }
  }

  Future<void> _searchAddress(String query) async {
    if (query.isEmpty) {
      setState(() => _suggestions = []);
      return;
    }

    setState(() => _isSearching = true);

    try {
      final encoded = Uri.encodeComponent(query);
      final uri = Uri.parse(
        'https://maps.googleapis.com/maps/api/geocode/json'
        '?address=$encoded&key=$_googleApiKey',
      );

      final resp = await http.get(uri);
      if (resp.statusCode != 200) {
        throw Exception('Search failed');
      }

      final data = json.decode(resp.body) as Map<String, dynamic>;
      final results = data['results'] as List<dynamic>;

      final suggestions = results.map((result) {
        final location = result['geometry']['location'] as Map<String, dynamic>;
        final lat = (location['lat'] as num).toDouble();
        final lng = (location['lng'] as num).toDouble();
        final address = result['formatted_address'] as String;

        return AddressSuggestion(
          address: address,
          latitude: lat,
          longitude: lng,
        );
      }).toList();

      setState(() {
        _suggestions = suggestions;
        _showSearchSuggestions = true;
        _isSearching = false;
      });

      _slideController.forward(from: 0.0);
    } catch (e) {
      _showSnackBar('Search failed: $e', Colors.red);
      setState(() => _isSearching = false);
    }
  }

  void _selectSuggestion(AddressSuggestion suggestion) {
    setState(() {
      _searchedPosition = LatLng(suggestion.latitude, suggestion.longitude);
      _searchedAddress = suggestion.address;
      _showSearchSuggestions = false;
      _searchController.clear();
    });

    _updateMarkers();

    if (_mapController != null) {
      _mapController!.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: _searchedPosition!, zoom: 16),
        ),
      );
    }

    _showSnackBar('✅ Location selected: ${suggestion.address}', Colors.green);
    _searchFocus.unfocus();
  }

  void _updateMarkers() {
    final markers = <Marker>{};

    if (_currentLocation != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('current_location'),
          position: _currentLocation!,
          infoWindow: const InfoWindow(title: '📍 Your Location'),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueAzure,
          ),
        ),
      );
    }

    if (_searchedPosition != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('search_result'),
          position: _searchedPosition!,
          infoWindow: InfoWindow(
            title: 'Selected Location',
            snippet: _searchedAddress,
          ),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        ),
      );
    }

    setState(() => _markers = markers);
  }

  Future<void> _openDirections() async {
    if (_searchedPosition == null) return;

    final dest = _searchedPosition!;
    String url;

    if (_currentLocation != null) {
      url =
          'https://www.google.com/maps/dir/?api=1'
          '&origin=${_currentLocation!.latitude},${_currentLocation!.longitude}'
          '&destination=${dest.latitude},${dest.longitude}'
          '&travelmode=driving';
    } else {
      url =
          'https://www.google.com/maps/dir/?api=1'
          '&destination=${dest.latitude},${dest.longitude}'
          '&travelmode=driving';
    }

    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
    }
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              color == Colors.green
                  ? Icons.check_circle_rounded
                  : Icons.error_rounded,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Google Map
          GoogleMap(
            initialCameraPosition: const CameraPosition(
              target: _initialPosition,
              zoom: 11,
            ),
            onMapCreated: (controller) => _mapController = controller,
            myLocationEnabled: false,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            markers: _markers,
          ),

          // Top Header with Search
          Positioned(top: 0, left: 0, right: 0, child: _buildHeader()),

          // Search Suggestions Dropdown
          if (_showSearchSuggestions)
            Positioned(
              top: 120,
              left: 12,
              right: 12,
              child: _buildSuggestionsList(),
            ),

          // Bottom Right Controls
          Positioned(right: 16, bottom: 32, child: _buildBottomControls()),

          // Search Result Info Card
          if (_searchedPosition != null && !_showSearchSuggestions)
            Positioned(
              left: 16,
              right: 16,
              bottom: 24,
              child: _buildSearchResultCard(),
            ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return SafeArea(
      bottom: false,
      child: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF667EEA).withOpacity(0.25),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.map_rounded,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Map & Directions',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          letterSpacing: -0.5,
                        ),
                      ),
                      Text(
                        'Find places and navigate',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildSearchField(),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchField() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          const SizedBox(width: 16),
          const Icon(Icons.search_rounded, color: Color(0xFF64748B), size: 24),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocus,
              textInputAction: TextInputAction.search,
              onChanged: (value) {
                if (value.isNotEmpty) {
                  _searchAddress(value);
                } else {
                  setState(() => _showSearchSuggestions = false);
                }
              },
              onSubmitted: (query) {
                if (query.isNotEmpty && _suggestions.isNotEmpty) {
                  _selectSuggestion(_suggestions.first);
                }
              },
              decoration: const InputDecoration(
                hintText: 'Search place, venue or postcode',
                hintStyle: TextStyle(color: Color(0xFFCBD5E1), fontSize: 14),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 14),
              ),
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF0F172A),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (_isSearching)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF667EEA)),
                ),
              ),
            )
          else if (_searchController.text.isNotEmpty)
            IconButton(
              onPressed: () {
                _searchController.clear();
                setState(() => _showSearchSuggestions = false);
              },
              icon: const Icon(Icons.close_rounded, color: Color(0xFF94A3B8)),
            )
          else
            const SizedBox(width: 12),
        ],
      ),
    );
  }

  Widget _buildSuggestionsList() {
    return SlideTransition(
      position: Tween<Offset>(begin: const Offset(0, -0.5), end: Offset.zero)
          .animate(
            CurvedAnimation(parent: _slideController, curve: Curves.easeOut),
          ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.95),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: Colors.white.withOpacity(0.3),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF667EEA).withOpacity(0.15),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            constraints: const BoxConstraints(maxHeight: 350),
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              shrinkWrap: true,
              itemCount: _suggestions.length,
              itemBuilder: (context, index) {
                final suggestion = _suggestions[index];
                return _buildSuggestionTile(suggestion);
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSuggestionTile(AddressSuggestion suggestion) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _selectSuggestion(suggestion),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF667EEA).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.location_on_rounded,
                  color: Color(0xFF667EEA),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      suggestion.address.split(',').first,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0F172A),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      suggestion.address,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.arrow_forward_rounded,
                color: Colors.grey.shade400,
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomControls() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      spacing: 12,
      children: [
        // My Location Button
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _getCurrentLocation,
              borderRadius: BorderRadius.circular(50),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: _isLocating
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Color(0xFF667EEA),
                          ),
                        ),
                      )
                    : Icon(
                        Icons.my_location_rounded,
                        color: const Color(0xFF667EEA),
                        size: 24,
                      ),
              ),
            ),
          ),
        ),

        // Zoom Controls
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () async {
                    await _mapController?.animateCamera(CameraUpdate.zoomIn());
                  },
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(12),
                  ),
                  child: const Padding(
                    padding: EdgeInsets.all(12),
                    child: Icon(
                      Icons.add_rounded,
                      color: Color(0xFF667EEA),
                      size: 24,
                    ),
                  ),
                ),
              ),
              Divider(height: 1, color: Colors.grey.shade200),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () async {
                    await _mapController?.animateCamera(CameraUpdate.zoomOut());
                  },
                  borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(12),
                  ),
                  child: const Padding(
                    padding: EdgeInsets.all(12),
                    child: Icon(
                      Icons.remove_rounded,
                      color: Color(0xFF667EEA),
                      size: 24,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        // Layers Button
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                _showSnackBar('Layers feature coming soon', Colors.blue);
              },
              borderRadius: BorderRadius.circular(50),
              child: const Padding(
                padding: EdgeInsets.all(12),
                child: Icon(
                  Icons.layers_rounded,
                  color: Color(0xFF667EEA),
                  size: 24,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSearchResultCard() {
    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0, 1),
        end: Offset.zero,
      ).animate(_slideController),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFFFFBFE), Color(0xFFF3E8FF)],
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: const Color(0xFF8B5CF6).withOpacity(0.25),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF667EEA).withOpacity(0.2),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
                ),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF667EEA).withOpacity(0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Icon(
                Icons.place_rounded,
                color: Colors.white,
                size: 24,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Selected Location',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF64748B),
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _searchedAddress ?? 'Location',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
                ),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF667EEA).withOpacity(0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _openDirections,
                  borderRadius: BorderRadius.circular(12),
                  child: const Padding(
                    padding: EdgeInsets.all(10),
                    child: Icon(
                      Icons.directions_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AddressSuggestion {
  final String address;
  final double latitude;
  final double longitude;

  AddressSuggestion({
    required this.address,
    required this.latitude,
    required this.longitude,
  });
}
