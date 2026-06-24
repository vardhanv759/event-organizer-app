import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Whether a review is rating someone's performance as a host (the
/// person who owns the space) or as a renter (the person who booked
/// it). A single person can hold both reputations independently - being
/// a great renter says nothing about whether they're a reliable host,
/// and blending the two into one number would be misleading to anyone
/// deciding whether to book with them or accept their request.
enum ReviewType {
  host,
  renter;

  String get field => this == ReviewType.host ? 'host' : 'renter';
}

/// Reviews for parking bookings - tied to the specific booking that
/// generated them, not to "your overall opinion of this person." Two
/// people who've booked together three times can leave three honest,
/// independent reviews instead of the second one silently overwriting
/// the first.
///
/// Firestore shape:
///
/// users/{uid}/rating_stats/summary
///   host_rating_count, host_rating_total     // reputation as a host
///   renter_rating_count, renter_rating_total // reputation as a renter
///   - Deliberately NOT on the main users/{uid} document. That document
///     can only ever be written by uid themselves (allow update: if
///     isMe(uid)) - which is exactly right for a profile, but means a
///     reviewer (who is never uid) could never legitimately bump
///     someone else's rating there. This small sub-document gets its
///     own narrow rule instead: anyone can increment THESE FOUR FIELDS
///     specifically, and nothing else - so a review can update your
///     reputation without ever being able to touch your name, photo, or
///     any other profile field.
///
/// users/{uid}/reviews/{bookingId}
///   type: 'host' | 'renter'  // which of uid's two reputations this is
///   rating (1-5), comment, rater_uid, booking_id, created_at
///   - Write-once per booking. An earlier version allowed editing a
///     review in place, which meant computing a net delta (old rating
///     subtracted, new rating added) for the aggregate update - that's
///     only safe to validate in security rules inside a transaction,
///     but the aggregate write needs to happen as a SEPARATE step after
///     the review commits (see submitBookingReview), where rules can no
///     longer see what the "old" rating was to compute a delta against.
///     Making reviews final removes the ambiguity entirely: every
///     review is always a fixed +1 count, +rating total.
///
/// A uid only ever appears in one role per booking (they're either the
/// provider or the renter on it, never both), so {bookingId} is always
/// an unambiguous key within a single user's reviews subcollection -
/// there's no risk of a host review and a renter review for the same
/// booking colliding on the same document id.
class ReviewService {
  ReviewService._();

  static final _db = FirebaseFirestore.instance;
  static final _auth = FirebaseAuth.instance;

  static String _requireUid() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw Exception('Not signed in.');
    return uid;
  }

  static CollectionReference<Map<String, dynamic>> _reviewsRef(String uid) =>
      _db.collection('users').doc(uid).collection('reviews');

  static DocumentReference<Map<String, dynamic>> _statsRef(String uid) => _db
      .collection('users')
      .doc(uid)
      .collection('rating_stats')
      .doc('summary');

  /// Submit a review of [revieweeUid]'s [type] performance on
  /// [bookingId]. One review per booking, permanently - see the class
  /// doc comment for why reviews can't be edited after submitting.
  ///
  /// This is deliberately TWO separate writes, not one transaction:
  /// the review doc first, then the aggregate bump. The aggregate's
  /// security rule needs to read the just-created review (via get()) to
  /// confirm it's legitimate before allowing the increment - and a
  /// security rule evaluated inside a transaction can't see that same
  /// transaction's own not-yet-committed writes, so the review has to
  /// actually be committed first.
  static Future<void> submitBookingReview({
    required String revieweeUid,
    required String bookingId,
    required ReviewType type,
    required int rating,
    String? comment,
  }) async {
    final uid = _requireUid();
    if (uid == revieweeUid) throw Exception('You cannot review yourself.');
    if (rating < 1 || rating > 5) throw Exception('Rating must be 1-5.');

    final reviewRef = _reviewsRef(revieweeUid).doc(bookingId);

    final existing = await reviewRef.get();
    if (existing.exists) {
      throw Exception('You\'ve already reviewed this booking.');
    }

    await reviewRef.set({
      'type': type.field,
      'rater_uid': uid,
      'booking_id': bookingId,
      'rating': rating,
      'comment': (comment?.trim().isEmpty ?? true) ? null : comment!.trim(),
      'created_at': FieldValue.serverTimestamp(),
    });

    final countField = '${type.field}_rating_count';
    final totalField = '${type.field}_rating_total';

    await _statsRef(revieweeUid).set({
      countField: FieldValue.increment(1),
      totalField: FieldValue.increment(rating),
    }, SetOptions(merge: true));
  }

  static Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
  reviewsStream(String uid, {ReviewType? type, int limit = 20}) {
    Query<Map<String, dynamic>> q = _reviewsRef(
      uid,
    ).orderBy('created_at', descending: true).limit(limit);
    if (type != null) {
      q = _reviewsRef(uid)
          .where('type', isEqualTo: type.field)
          .orderBy('created_at', descending: true)
          .limit(limit);
    }
    return q.snapshots().map((s) => s.docs);
  }

  /// Whether [bookingId] already has a review of [revieweeUid] on file -
  /// used to decide whether "Rate this booking" should show a fresh
  /// form or a disabled "Rated" state.
  static Future<bool> hasReviewedBooking(
    String revieweeUid,
    String bookingId,
  ) async {
    final snap = await _reviewsRef(revieweeUid).doc(bookingId).get();
    return snap.exists;
  }

  /// Live stream of [uid]'s rating_stats/summary doc - the call sites
  /// that show a rating (Host card, dashboard, analytics) should stream
  /// this directly rather than reusing whatever snapshot they already
  /// have of the main users/{uid} document, since the ratings no longer
  /// live there.
  static Stream<DocumentSnapshot<Map<String, dynamic>>> statsStream(
    String uid,
  ) {
    return _statsRef(uid).snapshots();
  }

  static double hostAverageFrom(Map<String, dynamic>? statsData) {
    final count = (statsData?['host_rating_count'] as num?)?.toInt() ?? 0;
    final total = (statsData?['host_rating_total'] as num?)?.toInt() ?? 0;
    if (count == 0) return 0;
    return total / count;
  }

  static int hostCountFrom(Map<String, dynamic>? statsData) {
    return (statsData?['host_rating_count'] as num?)?.toInt() ?? 0;
  }

  static double renterAverageFrom(Map<String, dynamic>? statsData) {
    final count = (statsData?['renter_rating_count'] as num?)?.toInt() ?? 0;
    final total = (statsData?['renter_rating_total'] as num?)?.toInt() ?? 0;
    if (count == 0) return 0;
    return total / count;
  }

  static int renterCountFrom(Map<String, dynamic>? statsData) {
    return (statsData?['renter_rating_count'] as num?)?.toInt() ?? 0;
  }
}
