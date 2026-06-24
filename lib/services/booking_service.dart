import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'messaging_service.dart';
import 'review_service.dart';

/// Confirmed parking bookings, created automatically the moment a
/// provider accepts a "Request to Book" chat request (see
/// MessagingService.acceptChatRequest). A booking is what blocks a
/// slot for everyone else - a chat_request is just someone asking.
///
/// ---------------------------------------------------------------------
/// LIFECYCLE
/// ---------------------------------------------------------------------
///
///   confirmed
///     -> cancellation_requested   (renter asks to cancel <24h out;
///                                   provider must accept/decline)
///     -> cancelled                (renter cancels >24h out, instantly;
///                                   or provider cancels, any time; or
///                                   provider accepts a late request)
///   cancellation_requested
///     -> cancelled                (provider accepts the request)
///     -> confirmed                (provider declines - booking just
///                                   stands, no penalty for asking)
///   confirmed (after `end` has passed)
///     -> completed                (provider confirms the renter showed
///                                   up and paid - this is also the one
///                                   moment the provider's rating of the
///                                   renter gets submitted)
///     -> no_show                  (provider confirms they didn't)
///     -> completed_unconfirmed    (provider never responded for 7+
///                                   days - see autoResolveStaleBookings)
///
/// Deliberately NOT automatic: a declined cancellation request does not
/// dock the renter's rating by itself. Only a confirmed no-show does -
/// ratings should reflect what actually happened, not an assumption.
///
/// ---------------------------------------------------------------------
/// FIRESTORE SHAPE
/// ---------------------------------------------------------------------
///
/// bookings/{bookingId}
///   space_id, space_title, provider_uid, renter_uid
///   start, end: Timestamp
///   hourly_rate: number          // snapshotted at creation, so a later
///                                 // price change never retroactively
///                                 // changes past earnings
///   status: 'confirmed' | 'cancellation_requested' | 'cancelled' |
///           'completed' | 'no_show' | 'completed_unconfirmed'
///   cancelled_by: 'renter' | 'provider' | null
///   cancelled_late: bool | null  // record-keeping only, not a penalty
///   request_id, note, created_at, updated_at
///
/// parking_spaces/{spaceId}/busy_slots/{bookingId}
///   start, end, booking_id
///   - Mirrors the booking's time range so ANY signed-in user can check
///     availability without seeing who booked it. Deleted the moment a
///     booking is cancelled; left alone once its time has passed, since
///     a slot in the past can never overlap a new (future) request
///     anyway - no cleanup needed there.
class BookingService {
  BookingService._();

  static final _db = FirebaseFirestore.instance;
  static final _auth = FirebaseAuth.instance;

  /// Renter cancellations inside this window need the provider's
  /// approval instead of happening instantly.
  static const Duration lateCancellationWindow = Duration(hours: 24);

  /// How long a provider can go silent on "did they show up?" before a
  /// booking auto-resolves with no rating. See autoResolveStaleBookings
  /// for why this is currently a client-side fallback rather than a
  /// true scheduled job.
  static const Duration autoResolveAfter = Duration(days: 7);

  static String _requireUid() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw Exception('Not signed in.');
    return uid;
  }

  static CollectionReference<Map<String, dynamic>> _busySlotsRef(
    String spaceId,
  ) => _db.collection('parking_spaces').doc(spaceId).collection('busy_slots');

  static bool isLate(DateTime start) =>
      DateTime.now().isAfter(start.subtract(lateCancellationWindow));

  // ---------------------------------------------------------------------
  // Availability checking
  // ---------------------------------------------------------------------

  /// Every busy slot for [spaceId] that overlaps [start]-[end]. Used both
  /// as a live UX check before a renter sends a request, and as the
  /// authoritative guard inside acceptChatRequest right before a booking
  /// is actually created.
  static Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
  findConflicts({
    required String spaceId,
    required DateTime start,
    required DateTime end,
  }) async {
    final snap = await _busySlotsRef(
      spaceId,
    ).where('start', isLessThan: Timestamp.fromDate(end)).get();

    return snap.docs.where((doc) {
      final data = doc.data();
      final slotStart = (data['start'] as Timestamp?)?.toDate();
      final slotEnd = (data['end'] as Timestamp?)?.toDate();
      if (slotStart == null || slotEnd == null) return false;
      return start.isBefore(slotEnd) && slotStart.isBefore(end);
    }).toList();
  }

  static Future<bool> hasConflict({
    required String spaceId,
    required DateTime start,
    required DateTime end,
  }) async {
    final conflicts = await findConflicts(
      spaceId: spaceId,
      start: start,
      end: end,
    );
    return conflicts.isNotEmpty;
  }

  // ---------------------------------------------------------------------
  // Creation (called by MessagingService.acceptChatRequest)
  // ---------------------------------------------------------------------

  /// Creates the booking + its mirrored busy slot. Deliberately NOT part
  /// of the same Firestore transaction that accepts the chat_request:
  /// the bookings security rule needs to read the request's `accepted`
  /// status to authorize this write, and a security rule evaluated
  /// inside a transaction can't see that same transaction's own
  /// not-yet-committed writes - so this has to run as a second, separate
  /// step after the accept transaction has actually committed.
  static Future<void> createBookingAndBusySlot({
    required String requestId,
    required String spaceId,
    required String providerUid,
    required String renterUid,
    required Timestamp start,
    required int durationHours,
    required double hourlyRate,
    String? spaceTitle,
    String? note,
  }) async {
    final end = Timestamp.fromDate(
      start.toDate().add(Duration(hours: durationHours)),
    );
    final bookingRef = _db.collection('bookings').doc();
    final now = FieldValue.serverTimestamp();

    await bookingRef.set({
      'space_id': spaceId,
      'space_title': spaceTitle,
      'provider_uid': providerUid,
      'renter_uid': renterUid,
      'start': start,
      'end': end,
      'hourly_rate': hourlyRate,
      'status': 'confirmed',
      'cancelled_by': null,
      'cancelled_late': null,
      'request_id': requestId,
      'note': note,
      'created_at': now,
      'updated_at': now,
    });

    await _busySlotsRef(spaceId).doc(bookingRef.id).set({
      'start': start,
      'end': end,
      'booking_id': bookingRef.id,
    });
  }

  // ---------------------------------------------------------------------
  // Streams for "My Bookings" / "Manage My Spaces"
  // ---------------------------------------------------------------------

  static Stream<QuerySnapshot<Map<String, dynamic>>> myBookingsAsRenter() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return const Stream.empty();
    return _db
        .collection('bookings')
        .where('renter_uid', isEqualTo: uid)
        .orderBy('start', descending: true)
        .snapshots();
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> myBookingsAsProvider() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return const Stream.empty();
    return _db
        .collection('bookings')
        .where('provider_uid', isEqualTo: uid)
        .orderBy('start', descending: true)
        .snapshots();
  }

  /// Bookings for one specific space - what "Manage My Spaces" shows in
  /// a single listing's Bookings tab.
  static Stream<QuerySnapshot<Map<String, dynamic>>> bookingsForSpace(
    String spaceId,
  ) {
    return _db
        .collection('bookings')
        .where('space_id', isEqualTo: spaceId)
        .orderBy('start', descending: true)
        .snapshots();
  }

  /// Count of bookings, across every space this provider owns, that are
  /// waiting on a "did they arrive?" answer (their slot has ended but
  /// they're still sitting in `confirmed`). Drives the dashboard banner.
  static Stream<int> needsConfirmationCountStream(String uid) {
    return _db
        .collection('bookings')
        .where('provider_uid', isEqualTo: uid)
        .where('status', isEqualTo: 'confirmed')
        .where('end', isLessThan: Timestamp.now())
        .snapshots()
        .map((s) => s.docs.length);
  }

  // ---------------------------------------------------------------------
  // Renter cancellation
  // ---------------------------------------------------------------------

  /// Cancels instantly if more than 24h before the slot, or files a
  /// cancellation request awaiting the provider's decision if inside
  /// that window. Returns 'cancelled' or 'requested' so the UI can show
  /// the right confirmation message.
  static Future<String> requestOrCancelBooking(String bookingId) async {
    final uid = _requireUid();
    final ref = _db.collection('bookings').doc(bookingId);

    String result = 'cancelled';
    Map<String, dynamic>? bookingData;

    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) throw Exception('Booking not found.');
      final data = snap.data() as Map<String, dynamic>;
      bookingData = data;

      if (data['renter_uid'] != uid) {
        throw Exception('Not authorized to cancel this booking.');
      }
      if (data['status'] != 'confirmed') {
        throw Exception('This booking can no longer be cancelled.');
      }

      final start = (data['start'] as Timestamp).toDate();
      final now = FieldValue.serverTimestamp();

      if (isLate(start)) {
        tx.update(ref, {'status': 'cancellation_requested', 'updated_at': now});
        result = 'requested';
      } else {
        tx.update(ref, {
          'status': 'cancelled',
          'cancelled_by': 'renter',
          'cancelled_late': false,
          'updated_at': now,
        });
        final spaceId = data['space_id'] as String?;
        if (spaceId != null) {
          tx.delete(_busySlotsRef(spaceId).doc(bookingId));
        }
        result = 'cancelled';
      }
    });

    // Write a message to the shared chat so the provider sees the
    // cancellation action inline, without needing to open Manage Spaces.
    // This runs AFTER the transaction so the booking status is already
    // committed and consistent when the provider reads it.
    if (bookingData != null) {
      final providerUid = bookingData!['provider_uid'] as String?;
      if (providerUid != null) {
        final chatId = MessagingService.chatIdForUids(uid, providerUid);
        final chatRef = _db.collection('chats').doc(chatId);
        final chatSnap = await chatRef.get();

        if (chatSnap.exists) {
          final msgRef = chatRef.collection('messages').doc();
          final now = FieldValue.serverTimestamp();

          if (result == 'requested') {
            // Renter is writing this — sender_id = renter uid = caller uid.
            // Security rule: sender_id == request.auth.uid ✓
            await msgRef.set({
              'sender_id': uid,
              'type': 'cancellation_request',
              'text': 'Cancellation request for this booking',
              'booking_id': bookingId,
              'space_title': bookingData!['space_title'],
              'start': bookingData!['start'],
              'end': bookingData!['end'],
              'created_at': now,
            });
            await chatRef.update({
              'last_message': '⚠️ Cancellation requested',
              'last_message_at': now,
              'last_sender_id': uid,
              'unread_for': FieldValue.arrayUnion([providerUid]),
            });
          } else {
            // Instant cancel (>24h out) — write a simple notice.
            await msgRef.set({
              'sender_id': uid,
              'type': 'cancellation_confirmed',
              'text': 'Booking cancelled',
              'booking_id': bookingId,
              'space_title': bookingData!['space_title'],
              'start': bookingData!['start'],
              'end': bookingData!['end'],
              'created_at': now,
            });
            await chatRef.update({
              'last_message': '🚫 Booking cancelled',
              'last_message_at': now,
              'last_sender_id': uid,
              'unread_for': FieldValue.arrayUnion([providerUid]),
            });
          }
        }
      }
    }

    return result;
  }

  // ---------------------------------------------------------------------
  // Provider actions
  // ---------------------------------------------------------------------

  /// Provider accepts or declines a renter's late-cancellation request.
  /// Declining just reverts the booking to confirmed - it's the
  /// renter's right to ask, and asking isn't itself a strike against
  /// them.
  static Future<void> decideCancellationRequest({
    required String bookingId,
    required bool accept,
  }) async {
    final uid = _requireUid();
    final ref = _db.collection('bookings').doc(bookingId);
    Map<String, dynamic>? bookingData;

    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) throw Exception('Booking not found.');
      final data = snap.data() as Map<String, dynamic>;
      bookingData = data;

      if (data['provider_uid'] != uid) {
        throw Exception('Not authorized.');
      }
      if (data['status'] != 'cancellation_requested') {
        throw Exception('This booking has no pending cancellation request.');
      }

      final now = FieldValue.serverTimestamp();

      if (accept) {
        tx.update(ref, {
          'status': 'cancelled',
          'cancelled_by': 'renter',
          'cancelled_late': true,
          'updated_at': now,
        });
        final spaceId = data['space_id'] as String?;
        if (spaceId != null) {
          tx.delete(_busySlotsRef(spaceId).doc(bookingId));
        }
      } else {
        tx.update(ref, {'status': 'confirmed', 'updated_at': now});
      }
    });

    // Write the provider's decision back into the chat thread so both
    // parties have a clear record of what happened without either side
    // having to check Manage Spaces or My Bookings separately.
    if (bookingData != null) {
      final renterUid = bookingData!['renter_uid'] as String?;
      if (renterUid != null) {
        final chatId = MessagingService.chatIdForUids(uid, renterUid);
        final chatRef = _db.collection('chats').doc(chatId);
        final chatSnap = await chatRef.get();
        if (chatSnap.exists) {
          final msgRef = chatRef.collection('messages').doc();
          final now = FieldValue.serverTimestamp();
          // Provider is writing this — sender_id = provider uid = caller uid ✓
          await msgRef.set({
            'sender_id': uid,
            'type': accept ? 'cancellation_confirmed' : 'cancellation_declined',
            'text': accept
                ? 'Cancellation approved'
                : 'Cancellation request declined — booking still stands',
            'booking_id': bookingId,
            'space_title': bookingData!['space_title'],
            'start': bookingData!['start'],
            'end': bookingData!['end'],
            'created_at': now,
          });
          await chatRef.update({
            'last_message': accept
                ? '✅ Booking cancelled'
                : '❌ Cancellation declined',
            'last_message_at': now,
            'last_sender_id': uid,
            'unread_for': FieldValue.arrayUnion([renterUid]),
          });
        }
      }
    }
  }

  /// Provider cancels unilaterally - no approval step, since it's their
  /// space. `cancelled_late` is kept purely as a record of whether this
  /// happened inside the renter's 24h window, not as an automatic
  /// penalty against the provider.
  static Future<void> providerCancelBooking(String bookingId) async {
    final uid = _requireUid();
    final ref = _db.collection('bookings').doc(bookingId);
    Map<String, dynamic>? bookingData;

    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) throw Exception('Booking not found.');
      final data = snap.data() as Map<String, dynamic>;
      bookingData = data;

      if (data['provider_uid'] != uid) {
        throw Exception('Not authorized.');
      }
      if (data['status'] != 'confirmed' &&
          data['status'] != 'cancellation_requested') {
        throw Exception('This booking can no longer be cancelled.');
      }

      final start = (data['start'] as Timestamp).toDate();
      final now = FieldValue.serverTimestamp();

      tx.update(ref, {
        'status': 'cancelled',
        'cancelled_by': 'provider',
        'cancelled_late': isLate(start),
        'updated_at': now,
      });
      final spaceId = data['space_id'] as String?;
      if (spaceId != null) {
        tx.delete(_busySlotsRef(spaceId).doc(bookingId));
      }
    });

    // Notify the renter in the chat that the provider has cancelled.
    if (bookingData != null) {
      final renterUid = bookingData!['renter_uid'] as String?;
      if (renterUid != null) {
        final chatId = MessagingService.chatIdForUids(uid, renterUid);
        final chatRef = _db.collection('chats').doc(chatId);
        final chatSnap = await chatRef.get();
        if (chatSnap.exists) {
          final msgRef = chatRef.collection('messages').doc();
          final now = FieldValue.serverTimestamp();
          await msgRef.set({
            'sender_id': uid,
            'type': 'cancellation_confirmed',
            'text': 'The host has cancelled this booking',
            'booking_id': bookingId,
            'space_title': bookingData!['space_title'],
            'start': bookingData!['start'],
            'end': bookingData!['end'],
            'created_at': now,
          });
          await chatRef.update({
            'last_message': '🚫 Host cancelled booking',
            'last_message_at': now,
            'last_sender_id': uid,
            'unread_for': FieldValue.arrayUnion([renterUid]),
          });
        }
      }
    }
  }

  // ---------------------------------------------------------------------
  // Post-booking: attendance + rating
  // ---------------------------------------------------------------------

  /// The provider's answer to "did they arrive and pay?" - only valid
  /// once the slot's end time has passed. Answering "yes" requires
  /// rating the renter in the same step, since that rating is what
  /// actually marks the booking as a verified, completed transaction.
  /// Answering "no" just closes it out as a no-show, nothing to rate.
  static Future<void> confirmAttendance({
    required String bookingId,
    required bool arrived,
    int? renterRating,
    String? renterRatingComment,
  }) async {
    final uid = _requireUid();
    final ref = _db.collection('bookings').doc(bookingId);

    final snap = await ref.get();
    if (!snap.exists) throw Exception('Booking not found.');
    final data = snap.data() as Map<String, dynamic>;

    if (data['provider_uid'] != uid) {
      throw Exception('Not authorized.');
    }
    if (data['status'] != 'confirmed') {
      throw Exception('This booking has already been resolved.');
    }
    final end = (data['end'] as Timestamp).toDate();
    if (DateTime.now().isBefore(end)) {
      throw Exception('This booking hasn\'t ended yet.');
    }

    if (arrived) {
      if (renterRating == null || renterRating < 1 || renterRating > 5) {
        throw Exception('Please rate the renter (1-5 stars).');
      }
      await ref.update({
        'status': 'completed',
        'updated_at': FieldValue.serverTimestamp(),
      });
      await ReviewService.submitBookingReview(
        revieweeUid: data['renter_uid'] as String,
        bookingId: bookingId,
        type: ReviewType.renter,
        rating: renterRating,
        comment: renterRatingComment,
      );
    } else {
      await ref.update({
        'status': 'no_show',
        'updated_at': FieldValue.serverTimestamp(),
      });
    }
  }

  /// Opportunistic fallback for the "auto-resolve after a week of
  /// silence" rule. This is NOT a true scheduled job - it only runs
  /// when called, typically when a provider opens their bookings view -
  /// so a booking won't actually flip to completed_unconfirmed the
  /// instant 7 days elapse, only the next time this happens to run. A
  /// real guarantee needs a Cloud Function with a scheduled trigger;
  /// this exists so the feature works correctly today without one.
  static Future<void> autoResolveStaleBookings(String providerUid) async {
    final cutoff = Timestamp.fromDate(
      DateTime.now().subtract(autoResolveAfter),
    );
    final snap = await _db
        .collection('bookings')
        .where('provider_uid', isEqualTo: providerUid)
        .where('status', isEqualTo: 'confirmed')
        .where('end', isLessThan: cutoff)
        .get();

    if (snap.docs.isEmpty) return;

    final batch = _db.batch();
    for (final doc in snap.docs) {
      batch.update(doc.reference, {
        'status': 'completed_unconfirmed',
        'updated_at': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }

  // ---------------------------------------------------------------------
  // Earnings (self-reported - see hourly_rate snapshot above)
  // ---------------------------------------------------------------------

  /// Sum of rate x duration across every booking this provider has
  /// marked completed. "Self-reported" because there's no payment
  /// processor behind this right now - it reflects what the provider
  /// told the app happened, not a verified transaction.
  static double totalEarningsFrom(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> bookings,
  ) {
    double total = 0;
    for (final doc in bookings) {
      final data = doc.data();
      if (data['status'] != 'completed') continue;
      final rate = (data['hourly_rate'] as num?)?.toDouble() ?? 0;
      final start = (data['start'] as Timestamp?)?.toDate();
      final end = (data['end'] as Timestamp?)?.toDate();
      if (start == null || end == null) continue;
      final hours = end.difference(start).inMinutes / 60.0;
      total += rate * hours;
    }
    return total;
  }
}
