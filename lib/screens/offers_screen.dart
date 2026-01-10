import 'package:flutter/material.dart';

class OffersScreen extends StatelessWidget {
  const OffersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FF),
      appBar: AppBar(
        title: const Text('Offers for Today'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: const Padding(
        padding: EdgeInsets.all(20),
        child: Text(
          'Later: event-linked promos, dining discounts, parking bundles, affiliate offers.',
          style: TextStyle(fontSize: 14, color: Color(0xFF334155)),
        ),
      ),
    );
  }
}
