import 'package:flutter/material.dart';

class AiPlannerScreen extends StatelessWidget {
  const AiPlannerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FF),
      appBar: AppBar(
        title: const Text('Plan Your Day (AI)'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: const Padding(
        padding: EdgeInsets.all(20),
        child: Text(
          'Later: AI itinerary builder using selected event + dining + parking + time windows.',
          style: TextStyle(fontSize: 14, color: Color(0xFF334155)),
        ),
      ),
    );
  }
}
