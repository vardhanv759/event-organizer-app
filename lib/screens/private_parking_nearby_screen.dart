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

  Query<Map<String, dynamic>> _query() {
    Query<Map<String, dynamic>> q = FirebaseFirestore.instance
        .collection('parking_spaces')
        .where('status', isEqualTo: 'approved');

    if (_spaceType != 'All') {
      q = q.where('space_type', isEqualTo: _spaceType);
    }

    return q.orderBy('created_at', descending: true).limit(60);
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
                stream: _query().snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final docs = snapshot.data?.docs ?? [];
                  if (docs.isEmpty) {
                    return const _EmptyState();
                  }

                  if (_grid) {
                    return GridView.builder(
                      itemCount: docs.length,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                            childAspectRatio: 0.92,
                          ),
                      itemBuilder: (context, i) {
                        final d = docs[i];
                        return _SpaceCard(
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
                    itemCount: docs.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, i) {
                      final d = docs[i];
                      return _SpaceListTile(
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
    return Row(
      children: [
        const Icon(Icons.filter_list_rounded, color: Color(0xFF334155)),
        const SizedBox(width: 10),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 12,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
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
        ),
      ],
    );
  }
}

class _SpaceCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final VoidCallback onTap;

  const _SpaceCard({required this.data, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final title = (data['title'] as String?)?.trim() ?? 'Private parking';
    final area = (data['approx_area'] as String?)?.trim() ?? 'Wembley';
    final hourly = (data['hourly_rate_gbp'] is num)
        ? (data['hourly_rate_gbp'] as num).toDouble()
        : 0.0;
    final type = (data['space_type'] as String?)?.trim() ?? 'space';

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
                    size: 36,
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
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '$area • ${type.replaceAll('_', ' ')}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
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
                  borderRadius: BorderRadius.circular(14),
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

class _SpaceListTile extends StatelessWidget {
  final Map<String, dynamic> data;
  final VoidCallback onTap;

  const _SpaceListTile({required this.data, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final title = (data['title'] as String?)?.trim() ?? 'Private parking';
    final area = (data['approx_area'] as String?)?.trim() ?? 'Wembley';
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
                borderRadius: BorderRadius.circular(16),
                gradient: const LinearGradient(
                  colors: [Color(0xFF0EA5E9), Color(0xFF6366F1)],
                ),
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
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    area,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              '£${hourly.toStringAsFixed(2)}/hr',
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                color: Color(0xFF4F46E5),
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right_rounded, color: Color(0xFF94A3B8)),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        'No approved private parking spaces yet.\n\nIf you are a provider, apply to list your space.',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontWeight: FontWeight.w800,
          color: Color(0xFF334155),
          height: 1.4,
        ),
      ),
    );
  }
}
