import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class PaymentSuccessScreen extends StatefulWidget {
  const PaymentSuccessScreen({super.key});

  @override
  State<PaymentSuccessScreen> createState() => _PaymentSuccessScreenState();
}

class _PaymentSuccessScreenState extends State<PaymentSuccessScreen> {
  DocumentSnapshot<Map<String, dynamic>>? booking;
  bool loading = true;
  String? error;

  Timer? _timer;
  int _ticks = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // Extract bookingId from either normal URL query or hash fragment query.
    String? bookingId = Uri.base.queryParameters['bookingId'];
    bookingId ??= Uri.tryParse(
      'https://dummy${Uri.base.fragment}',
    )?.queryParameters['bookingId'];

    if (bookingId == null || bookingId.trim().isEmpty) {
      setState(() {
        loading = false;
        error = 'Missing bookingId in redirect URL.';
      });
      return;
    }

    _pollBooking(bookingId);
  }

  void _pollBooking(String bookingId) {
    _timer?.cancel();
    _ticks = 0;

    _timer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      _ticks++;

      try {
        final snap = await FirebaseFirestore.instance
            .collection('parking_bookings')
            .doc(bookingId)
            .get();

        if (!snap.exists) {
          // Keep polling for a bit in case the doc write is delayed
          if (_ticks >= 15) {
            // ~30 seconds
            timer.cancel();
            setState(() {
              loading = false;
              error = 'Booking not found. If you paid, please contact support.';
            });
          }
          return;
        }

        final data = snap.data();
        final status = (data?['status'] ?? '').toString();

        if (status == 'confirmed') {
          timer.cancel();
          setState(() {
            booking = snap;
            loading = false;
            error = null;
          });
          return;
        }

        // Stop polling after ~45 seconds
        if (_ticks >= 23) {
          timer.cancel();
          setState(() {
            loading = false;
            error =
                'Payment is still processing. Please refresh this page in a moment.';
          });
        }
      } catch (e) {
        timer.cancel();
        setState(() {
          loading = false;
          error = 'Error confirming payment: $e';
        });
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return _buildLoading();
    if (error != null) return _buildError();
    return _buildSuccess();
  }

  Widget _buildLoading() {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 20),
            Text('Confirming your payment...', style: TextStyle(fontSize: 16)),
          ],
        ),
      ),
    );
  }

  Widget _buildError() {
    return Scaffold(
      appBar: AppBar(title: const Text('Payment Status')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Card(
            elevation: 6,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.info_outline_rounded, size: 56),
                  const SizedBox(height: 12),
                  Text(
                    error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () =>
                        Navigator.of(context).pushReplacementNamed('/'),
                    child: const Text('Back to Home'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSuccess() {
    return Scaffold(
      appBar: AppBar(title: const Text('Booking Confirmed')),
      body: Center(
        child: Card(
          elevation: 6,
          margin: const EdgeInsets.all(24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.check_circle, color: Colors.green, size: 72),
                const SizedBox(height: 16),
                const Text(
                  'Payment Successful',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Text(
                  'Booking ID:\n${booking!.id}',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () =>
                      Navigator.of(context).pushReplacementNamed('/'),
                  child: const Text('Back to Home'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
