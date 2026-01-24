import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'parking_space_details_screen.dart';

class PrivateParkingNearbyScreen extends StatefulWidget {
  const PrivateParkingNearbyScreen({super.key});

  @override
  State<PrivateParkingNearbyScreen> createState() =>
      _PrivateParkingNearbyScreenState();
}

class _PrivateParkingNearbyScreenState
    extends State<PrivateParkingNearbyScreen> {
  bool _grid = true;
  String _spaceType = 'All';

  final _types = const [
    'All',
    'driveway',
    'allocated_bay',
    'underground',
    'gated',
    'open_lot',
  ];

  Stream<QuerySnapshot<Map<String, dynamic>>> _stream() {
    // MVP: Avoid composite indexes; filter/sort client-side.
    return FirebaseFirestore.instance
        .collection('parking_spaces')
        .where('status_lc', isEqualTo: 'approved')
        .limit(200)
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FF),
      appBar: AppBar(
        title: const Text('Private Parking Nearby'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: _grid ? 'Switch to list' : 'Switch to grid',
            onPressed: () => setState(() => _grid = !_grid),
            icon: Icon(
              _grid ? Icons.view_list_rounded : Icons.grid_view_rounded,
            ),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
        child: Column(
          children: [
            _TopFilterRow(
              value: _spaceType,
              types: _types,
              onChanged: (v) => setState(() => _spaceType = v),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _stream(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const _LoadingSkeleton();
                  }

                  final docs = snapshot.data?.docs ?? [];

                  // Filter approved client-side (handles Approved/approved/APPROVED)
                  final approved = docs.where((d) {
                    final m = d.data();
                    final status = (m['status_lower'] ?? m['status'] ?? '')
                        .toString()
                        .trim()
                        .toLowerCase();
                    if (status != 'approved') return false;

                    if (_spaceType == 'All') return true;
                    final t = (m['space_type'] ?? '')
                        .toString()
                        .trim()
                        .toLowerCase();
                    return t == _spaceType.toLowerCase();
                  }).toList();

                  // Sort newest first (client-side)
                  approved.sort((a, b) {
                    final ta = (a.data()['created_at'] as Timestamp?)?.toDate();
                    final tb = (b.data()['created_at'] as Timestamp?)?.toDate();
                    return (tb ?? DateTime.fromMillisecondsSinceEpoch(0))
                        .compareTo(
                          ta ?? DateTime.fromMillisecondsSinceEpoch(0),
                        );
                  });

                  if (approved.isEmpty) {
                    return const _EmptyState();
                  }

                  if (_grid) {
                    return GridView.builder(
                      itemCount: approved.length,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                            childAspectRatio: 0.92,
                          ),
                      itemBuilder: (context, i) {
                        final d = approved[i];
                        return _SpaceCardPremium(
                          data: d.data(),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    ParkingSpaceDetailsScreen(spaceId: d.id),
                              ),
                            );
                          },
                        );
                      },
                    );
                  }

                  return ListView.separated(
                    itemCount: approved.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, i) {
                      final d = approved[i];
                      return _SpaceListTilePremium(
                        data: d.data(),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  ParkingSpaceDetailsScreen(spaceId: d.id),
                            ),
                          );
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopFilterRow extends StatelessWidget {
  final String value;
  final List<String> types;
  final ValueChanged<String> onChanged;

  const _TopFilterRow({
    required this.value,
    required this.types,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 14,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.tune_rounded, color: Color(0xFF334155)),
          const SizedBox(width: 10),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: value,
                isExpanded: true,
                items: types
                    .map(
                      (t) => DropdownMenuItem(
                        value: t,
                        child: Text(
                          t == 'All'
                              ? 'All space types'
                              : t.replaceAll('_', ' '),
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  if (v != null) onChanged(v);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SpaceCardPremium extends StatelessWidget {
  final Map<String, dynamic> data;
  final VoidCallback onTap;

  const _SpaceCardPremium({required this.data, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final title = (data['title'] as String?)?.trim() ?? 'Private parking';
    final area = (data['approx_area'] as String?)?.trim() ?? 'Wembley';
    final type = (data['space_type'] as String?)?.trim() ?? 'space';
    final hourly = (data['hourly_rate_gbp'] is num)
        ? (data['hourly_rate_gbp'] as num).toDouble()
        : 0.0;

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
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
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 92,
                width: double.infinity,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  gradient: const LinearGradient(
                    colors: [Color(0xFF0EA5E9), Color(0xFF6366F1)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: const Center(
                  child: Icon(
                    Icons.local_parking_rounded,
                    color: Colors.white,
                    size: 38,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF0F172A),
                  height: 1.15,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '$area • ${type.replaceAll('_', ' ')}',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF64748B),
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFEEF2FF),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '£${hourly.toStringAsFixed(2)}/hr',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF4F46E5),
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

class _SpaceListTilePremium extends StatelessWidget {
  final Map<String, dynamic> data;
  final VoidCallback onTap;

  const _SpaceListTilePremium({required this.data, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final title = (data['title'] as String?)?.trim() ?? 'Private parking';
    final area = (data['approx_area'] as String?)?.trim() ?? 'Wembley';
    final type = (data['space_type'] as String?)?.trim() ?? 'space';
    final hourly = (data['hourly_rate_gbp'] is num)
        ? (data['hourly_rate_gbp'] as num).toDouble()
        : 0.0;

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
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
                gradient: const LinearGradient(
                  colors: [Color(0xFF0EA5E9), Color(0xFF6366F1)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(
                Icons.local_parking_rounded,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$area • ${type.replaceAll('_', ' ')}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFEEF2FF),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '£${hourly.toStringAsFixed(2)}/hr',
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF4F46E5),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadingSkeleton extends StatelessWidget {
  const _LoadingSkeleton();

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      itemCount: 6,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.92,
      ),
      itemBuilder: (_, __) => Container(
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.6),
          borderRadius: BorderRadius.circular(18),
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
        padding: const EdgeInsets.all(16),
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
        child: const Text(
          'No approved private spaces yet.\nIf you are a provider, submit your space for review.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: Color(0xFF334155),
            height: 1.25,
          ),
        ),
      ),
    );
  }
}
