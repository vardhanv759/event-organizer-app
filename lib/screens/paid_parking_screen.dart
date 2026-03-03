import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

class PaidParkingScreen extends StatefulWidget {
  const PaidParkingScreen({super.key});

  @override
  State<PaidParkingScreen> createState() => _PaidParkingScreenState();
}

class _PaidParkingScreenState extends State<PaidParkingScreen> {
  // Change this if your Firestore collection name is different:
  static const String _collection = 'parking_paid';

  String _sort = 'closest'; // closest | cheapest
  bool _onlyEv = false;
  bool _onlyCctv = false;
  bool _onlyAccessible = false;

  Position? _userPos;
  bool _locating = false;

  @override
  void initState() {
    super.initState();
    _tryGetUserLocation();
  }

  Future<void> _tryGetUserLocation() async {
    setState(() => _locating = true);
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        setState(() => _locating = false);
        return;
      }

      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }

      if (perm == LocationPermission.always ||
          perm == LocationPermission.whileInUse) {
        final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        );
        if (!mounted) return;
        setState(() => _userPos = pos);
      }
    } catch (_) {
      // silent; screen still works without location
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _stream() {
    // We keep it simple: fetch latest items, then do sorting/filtering locally.
    // This avoids complex composite indexes at MVP stage.
    return FirebaseFirestore.instance
        .collection(_collection)
        .orderBy('updatedAt', descending: true)
        .limit(200)
        .snapshots();
  }

  List<_ParkingSpot> _applyFilters(List<_ParkingSpot> spots) {
    var out = spots;

    if (_onlyEv) out = out.where((s) => s.ev).toList();
    if (_onlyCctv) out = out.where((s) => s.cctv).toList();
    if (_onlyAccessible) out = out.where((s) => s.accessible).toList();

    if (_sort == 'closest') {
      out.sort((a, b) => (a.distanceM ?? 1e18).compareTo(b.distanceM ?? 1e18));
    } else if (_sort == 'cheapest') {
      out.sort(
        (a, b) => (a.pricePerHour ?? 1e18).compareTo(b.pricePerHour ?? 1e18),
      );
    }
    return out;
  }

  double? _distanceMeters(double? lat, double? lng) {
    final p = _userPos;
    if (p == null || lat == null || lng == null) return null;
    return Geolocator.distanceBetween(p.latitude, p.longitude, lat, lng);
  }

  Future<void> _openDirections(_ParkingSpot spot) async {
    if (spot.lat == null || spot.lng == null) return;

    final dest = '${spot.lat},${spot.lng}';
    String url;

    if (_userPos != null) {
      url =
          'https://www.google.com/maps/dir/?api=1'
          '&origin=${_userPos!.latitude},${_userPos!.longitude}'
          '&destination=$dest'
          '&travelmode=driving';
    } else {
      url =
          'https://www.google.com/maps/dir/?api=1'
          '&destination=$dest'
          '&travelmode=driving';
    }

    final uri = Uri.parse(url);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FF),
      appBar: AppBar(
        title: const Text('Paid Parking'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: const Color(0xFF0F172A),
        actions: [
          IconButton(
            tooltip: 'Refresh location',
            onPressed: _locating ? null : _tryGetUserLocation,
            icon: _locating
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.my_location_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          _FilterBar(
            sort: _sort,
            onlyEv: _onlyEv,
            onlyCctv: _onlyCctv,
            onlyAccessible: _onlyAccessible,
            onSortChanged: (v) => setState(() => _sort = v),
            onToggleEv: () => setState(() => _onlyEv = !_onlyEv),
            onToggleCctv: () => setState(() => _onlyCctv = !_onlyCctv),
            onToggleAccessible: () =>
                setState(() => _onlyAccessible = !_onlyAccessible),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _stream(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const _LoadingList();
                }

                final docs = snapshot.data?.docs ?? [];
                if (docs.isEmpty) {
                  return const _EmptyState(
                    title: 'No paid parking found',
                    subtitle:
                        'Add documents in Firestore collection "parking_paid" to see results.',
                  );
                }

                final spots = docs.map((d) {
                  final m = d.data();
                  final spot = _ParkingSpot.fromMap(id: d.id, m: m);
                  spot.distanceM = _distanceMeters(spot.lat, spot.lng);
                  return spot;
                }).toList();

                final filtered = _applyFilters(spots);

                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  itemCount: filtered.length,
                  itemBuilder: (context, i) {
                    final s = filtered[i];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _ParkingSpotCard(
                        spot: s,
                        onDirections: () => _openDirections(s),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  final String sort;
  final bool onlyEv;
  final bool onlyCctv;
  final bool onlyAccessible;

  final ValueChanged<String> onSortChanged;
  final VoidCallback onToggleEv;
  final VoidCallback onToggleCctv;
  final VoidCallback onToggleAccessible;

  const _FilterBar({
    required this.sort,
    required this.onlyEv,
    required this.onlyCctv,
    required this.onlyAccessible,
    required this.onSortChanged,
    required this.onToggleEv,
    required this.onToggleCctv,
    required this.onToggleAccessible,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF8F9FF),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _ChoiceChip(
              label: 'Closest',
              selected: sort == 'closest',
              onTap: () => onSortChanged('closest'),
            ),
            const SizedBox(width: 8),
            _ChoiceChip(
              label: 'Cheapest',
              selected: sort == 'cheapest',
              onTap: () => onSortChanged('cheapest'),
            ),
            const SizedBox(width: 12),
            _ToggleChip(label: 'EV', selected: onlyEv, onTap: onToggleEv),
            const SizedBox(width: 8),
            _ToggleChip(label: 'CCTV', selected: onlyCctv, onTap: onToggleCctv),
            const SizedBox(width: 8),
            _ToggleChip(
              label: 'Accessible',
              selected: onlyAccessible,
              onTap: onToggleAccessible,
            ),
          ],
        ),
      ),
    );
  }
}

class _ParkingSpotCard extends StatelessWidget {
  final _ParkingSpot spot;
  final VoidCallback onDirections;

  const _ParkingSpotCard({required this.spot, required this.onDirections});

  @override
  Widget build(BuildContext context) {
    final distance = spot.distanceM == null
        ? null
        : (spot.distanceM! >= 1000)
        ? '${(spot.distanceM! / 1000).toStringAsFixed(1)} km'
        : '${spot.distanceM!.toStringAsFixed(0)} m';

    final price = spot.pricePerHour == null
        ? '—'
        : '£${spot.pricePerHour!.toStringAsFixed(2)}/hr';

    return Container(
      padding: const EdgeInsets.all(14),
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
      child: Row(
        children: [
          Container(
            height: 54,
            width: 54,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: const LinearGradient(
                colors: [Color(0xFF0EA5E9), Color(0xFF6366F1)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: const Icon(Icons.local_parking_rounded, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  spot.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF0F172A),
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _MetaChip(icon: Icons.payments_rounded, text: price),
                    if (distance != null)
                      _MetaChip(
                        icon: Icons.directions_walk_rounded,
                        text: distance,
                      ),
                    if (spot.ev)
                      const _MetaChip(
                        icon: Icons.ev_station_rounded,
                        text: 'EV',
                      ),
                    if (spot.cctv)
                      const _MetaChip(
                        icon: Icons.videocam_rounded,
                        text: 'CCTV',
                      ),
                    if (spot.accessible)
                      const _MetaChip(
                        icon: Icons.accessible_rounded,
                        text: 'Accessible',
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          InkWell(
            onTap: onDirections,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF4F46E5),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Text(
                'Directions',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String text;

  const _MetaChip({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: const Color(0xFF64748B)),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: Color(0xFF334155),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChoiceChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ChoiceChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFEEF2FF) : Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? const Color(0xFF4F46E5) : const Color(0xFFE2E8F0),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? const Color(0xFF4F46E5) : const Color(0xFF334155),
            fontWeight: FontWeight.w900,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}

class _ToggleChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ToggleChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF111827) : Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? const Color(0xFF111827) : const Color(0xFFE2E8F0),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : const Color(0xFF334155),
            fontWeight: FontWeight.w900,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}

class _LoadingList extends StatelessWidget {
  const _LoadingList();

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      itemCount: 6,
      itemBuilder: (_, _) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Container(
          height: 92,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.65),
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String title;
  final String subtitle;

  const _EmptyState({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(18),
        padding: const EdgeInsets.all(18),
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFEEF2FF),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(
                Icons.info_outline_rounded,
                color: Color(0xFF4F46E5),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 16,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: Color(0xFF64748B),
                height: 1.25,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ParkingSpot {
  final String id;
  final String name;
  final double? lat;
  final double? lng;
  final double? pricePerHour;
  final bool ev;
  final bool cctv;
  final bool accessible;

  double? distanceM;

  _ParkingSpot({
    required this.id,
    required this.name,
    required this.lat,
    required this.lng,
    required this.pricePerHour,
    required this.ev,
    required this.cctv,
    required this.accessible,
  });

  factory _ParkingSpot.fromMap({
    required String id,
    required Map<String, dynamic> m,
  }) {
    double? toD(dynamic v) {
      if (v == null) return null;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString());
    }

    bool toB(dynamic v) {
      if (v == null) return false;
      if (v is bool) return v;
      final s = v.toString().toLowerCase().trim();
      return s == 'true' || s == '1' || s == 'yes';
    }

    return _ParkingSpot(
      id: id,
      name: (m['name'] as String?)?.trim().isNotEmpty == true
          ? (m['name'] as String).trim()
          : 'Paid Parking',
      lat: toD(m['lat']),
      lng: toD(m['lng']),
      pricePerHour: toD(m['pricePerHour']),
      ev: toB(m['ev']),
      cctv: toB(m['cctv']),
      accessible: toB(m['accessible']),
    );
  }
}
