import 'package:flutter/material.dart';
import 'saved_events_screen.dart';
import 'saved_restaurants_screen.dart';
import 'saved_accommodation_screen.dart';

class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FF),
      appBar: AppBar(
        title: const Text(
          'Favorites',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            color: Color(0xFF0F172A),
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(50),
          child: Container(
            color: Colors.white,
            child: TabBar(
              controller: _tabController,
              labelColor: const Color(0xFF4F46E5),
              unselectedLabelColor: const Color(0xFF64748B),
              indicator: const UnderlineTabIndicator(
                borderSide: BorderSide(color: Color(0xFF4F46E5), width: 4),
                insets: EdgeInsets.symmetric(horizontal: 16),
              ),
              labelStyle: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 14,
              ),
              unselectedLabelStyle: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
              tabs: const [
                Tab(icon: Icon(Icons.event_rounded, size: 22), text: 'Events'),
                Tab(
                  icon: Icon(Icons.restaurant_rounded, size: 22),
                  text: 'Dining',
                ),
                Tab(icon: Icon(Icons.hotel_rounded, size: 22), text: 'Stay'),
              ],
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          SavedEventsScreen(embedded: true),
          SavedRestaurantsScreen(embedded: true),
          SavedAccommodationScreen(embedded: true),
        ],
      ),
    );
  }
}
