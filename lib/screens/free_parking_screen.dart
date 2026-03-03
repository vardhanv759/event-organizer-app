import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class FreeParkingZonesScreen extends StatefulWidget {
  const FreeParkingZonesScreen({super.key});

  @override
  State<FreeParkingZonesScreen> createState() => _FreeParkingZonesScreenState();
}

class _FreeParkingZonesScreenState extends State<FreeParkingZonesScreen> {
  // Change this if your Firestore collection name is different:
  static const String _collection = 'parking_free_zones';

  String _risk = 'all'; // all | safe | risky

  Stream<QuerySnapshot<Map<String, dynamic>>> _stream() {
    return FirebaseFirestore.instance
        .collection(_collection)
        .orderBy('updatedAt', descending: true)
        .limit(200)
        .snapshots();
  }

  List<_FreeZone> _filter(List<_FreeZone> zones) {
    if (_risk == 'all') return zones;
    return zones.where((z) => z.risk == _risk).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FF),
      appBar: AppBar(
        title: const Text('Free Parking Zones'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: const Color(0xFF0F172A),
      ),
      body: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: _DisclaimerCard(),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Row(
              children: [
                _RiskChip(
                  label: 'All',
                  selected: _risk == 'all',
                  onTap: () => setState(() => _risk = 'all'),
                ),
                const SizedBox(width: 8),
                _RiskChip(
                  label: 'Safe',
                  selected: _risk == 'safe',
                  onTap: () => setState(() => _risk = 'safe'),
                ),
                const SizedBox(width: 8),
                _RiskChip(
                  label: 'Risky',
                  selected: _risk == 'risky',
                  onTap: () => setState(() => _risk = 'risky'),
                ),
              ],
            ),
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
                  return const _EmptyState();
                }

                final zones = docs
                    .map((d) => _FreeZone.fromMap(d.id, d.data()))
                    .toList();
                final filtered = _filter(zones);

                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  itemCount: filtered.length,
                  itemBuilder: (context, i) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _FreeZoneCard(zone: filtered[i]),
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

class _DisclaimerCard extends StatelessWidget {
  const _DisclaimerCard();

  @override
  Widget build(BuildContext context) {
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
      child: const Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: Color(0xFFEF4444)),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Free zones may have restrictions by time/day. Always read local signage. This app provides guidance, not legal enforcement.',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: Color(0xFF334155),
                height: 1.25,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RiskChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _RiskChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color fg;
    Color border;

    if (!selected) {
      bg = Colors.white;
      fg = const Color(0xFF334155);
      border = const Color(0xFFE2E8F0);
    } else {
      if (label == 'Safe') {
        bg = const Color(0xFF22C55E);
        fg = Colors.white;
        border = const Color(0xFF22C55E);
      } else if (label == 'Risky') {
        bg = const Color(0xFFEF4444);
        fg = Colors.white;
        border = const Color(0xFFEF4444);
      } else {
        bg = const Color(0xFF111827);
        fg = Colors.white;
        border = const Color(0xFF111827);
      }
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: border),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: fg,
            fontWeight: FontWeight.w900,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}

class _FreeZoneCard extends StatelessWidget {
  final _FreeZone zone;

  const _FreeZoneCard({required this.zone});

  @override
  Widget build(BuildContext context) {
    final riskColor = zone.risk == 'safe'
        ? const Color(0xFF22C55E)
        : const Color(0xFFEF4444);
    final riskLabel = zone.risk == 'safe' ? 'SAFE' : 'RISKY';

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
                colors: [Color(0xFF111827), Color(0xFF334155)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: const Icon(Icons.map_rounded, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  zone.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF0F172A),
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: riskColor.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        riskLabel,
                        style: TextStyle(
                          color: riskColor,
                          fontWeight: FontWeight.w900,
                          fontSize: 11,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        zone.note,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF64748B),
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
  }
}

class _LoadingList extends StatelessWidget {
  const _LoadingList();

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
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
  const _EmptyState();

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
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.info_outline_rounded,
              color: Color(0xFF4F46E5),
              size: 28,
            ),
            SizedBox(height: 10),
            Text(
              'No free zones found',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 16,
                color: Color(0xFF0F172A),
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Add documents in Firestore collection "parking_free_zones" to see free zone listings.',
              textAlign: TextAlign.center,
              style: TextStyle(
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

class _FreeZone {
  final String id;
  final String name;
  final String risk; // safe | risky
  final String note;

  _FreeZone({
    required this.id,
    required this.name,
    required this.risk,
    required this.note,
  });

  factory _FreeZone.fromMap(String id, Map<String, dynamic> m) {
    final name = (m['name'] as String?)?.trim();
    final riskRaw = (m['risk'] as String?)?.trim().toLowerCase();

    return _FreeZone(
      id: id,
      name: (name == null || name.isEmpty) ? 'Free Parking Zone' : name,
      risk: (riskRaw == 'safe') ? 'safe' : 'risky',
      note: (m['note'] as String?)?.trim().isNotEmpty == true
          ? (m['note'] as String).trim()
          : 'Check signage and restrictions',
    );
  }
}
