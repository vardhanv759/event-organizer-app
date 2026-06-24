import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'booking_service.dart';
import '../utils/time_format.dart';

/// Centralized service for the private messaging system: chat requests,
/// chats, messages, typing indicators, presence and read receipts.
///
/// This is the ONLY place that should write to `chats` or `chat_requests` -
/// screens should never mutate Firestore documents directly, so there is a
/// single source of truth for the schema and for who's allowed to do what.
///
/// Firestore shape (every field below is additive / backward compatible
/// with documents that predate it):
///
/// chat_requests/{fromUid_toUid_contextType_contextRefId}
///   from_uid, to_uid, status ('pending'|'accepted'|'rejected'|'cancelled'),
///   context_type, context_ref_id, context_title, created_at, updated_at
///   requested_at: Timestamp?  // the date/time the renter wants to park -
///                             // present when this request came from the
///                             // "Request to Book" flow on a parking listing
///   note: String?             // optional free-text the renter added
///
/// chats/{sortedUidA_sortedUidB}
///   participants: [uidA, uidB]
///   context_type, created_at
///   last_message, last_message_at, last_sender_id
///   unread_for: [uid]            // who currently has unread messages
///   read_at: { uid: Timestamp }  // last time each participant opened chat
///   hidden_for: [uid]            // who archived this chat for themselves
///   typing:  { uid: Timestamp }  // last keystroke time -> "typing..."
///
/// chats/{chatId}/messages/{messageId}
///   sender_id, text, created_at, type
///
/// users/{uid}
///   name, email, photoUrl, is_online, last_seen
class MessagingService {
  MessagingService._();

  static final _db = FirebaseFirestore.instance;
  static final _auth = FirebaseAuth.instance;

  /// How long a "typing" timestamp is considered still valid.
  static const Duration typingTtl = Duration(seconds: 5);

  /// How long a "last_seen" timestamp is considered still "online".
  /// Keeping this short avoids a user looking permanently online if the
  /// app was killed without a clean dispose.
  static const Duration onlineTtl = Duration(seconds: 35);

  static String _requireUid() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw Exception('Not signed in.');
    return uid;
  }

  static String chatIdForUids(String a, String b) {
    final sorted = [a, b]..sort();
    return '${sorted[0]}_${sorted[1]}';
  }

  /// Base request ID — deterministic, used for looking up whether a
  /// PENDING request exists between these two people for this context.
  /// Do NOT use this as the actual document ID when creating new
  /// requests — see [newRequestId] below.
  static String requestIdFor({
    required String fromUid,
    required String toUid,
    required String contextType,
    String? contextRefId,
  }) {
    final ctx = contextRefId?.trim().isNotEmpty == true
        ? contextRefId!.trim()
        : 'global';
    return '${fromUid}_${toUid}_${contextType}_$ctx';
  }

  /// Unique request ID for a brand-new request. Appends a timestamp so
  /// each booking request for the same space by the same renter creates
  /// its own document instead of overwriting the previous one.
  ///
  /// Without this, the second request for the same space hits the
  /// existing `accepted` document and is silently swallowed — the
  /// status check `if (status != 'pending' && status != 'accepted')`
  /// correctly guards against re-sending when already pending, but
  /// `accepted` means "done once", not "done forever". A renter booking
  /// a second slot on the same space is a completely valid new request.
  static String newRequestId({
    required String fromUid,
    required String toUid,
    required String contextType,
    String? contextRefId,
  }) {
    final base = requestIdFor(
      fromUid: fromUid,
      toUid: toUid,
      contextType: contextType,
      contextRefId: contextRefId,
    );
    final ts = DateTime.now().millisecondsSinceEpoch;
    return '${base}_$ts';
  }

  // ---------------------------------------------------------------------
  // Existence checks
  // ---------------------------------------------------------------------

  /// Check if an accepted chat exists between current user and another user.
  static Future<String?> getExistingChatId(String otherUid) async {
    final myUid = _requireUid();
    final chatId = chatIdForUids(myUid, otherUid);
    final chatDoc = await _db.collection('chats').doc(chatId).get();
    return chatDoc.exists ? chatId : null;
  }

  /// Stream version of [getExistingChatId], for real-time UI updates.
  static Stream<String?> chatExistsStream(String otherUid) {
    final myUid = _auth.currentUser?.uid;
    if (myUid == null) return Stream.value(null);
    final chatId = chatIdForUids(myUid, otherUid);
    return _db
        .collection('chats')
        .doc(chatId)
        .snapshots()
        .map((snap) => snap.exists ? chatId : null);
  }

  /// Status of the most recent pending request from the current user to
  /// [otherUid] for this context. Queries rather than watches a single
  /// doc, because each booking request now creates its own document
  /// (see [sendChatRequest] and [newRequestId]).
  static Stream<Map<String, dynamic>?> requestStatusStream({
    required String otherUid,
    required String contextType,
    String? contextRefId,
  }) {
    final myUid = _auth.currentUser?.uid;
    if (myUid == null) return Stream.value(null);

    // Watch for any pending request from me to this provider for this
    // space. If none exist, returns null (shows Request to Book button).
    // Using a query rather than a single doc now that each request has
    // its own timestamped ID.
    return _db
        .collection('chat_requests')
        .where('from_uid', isEqualTo: myUid)
        .where('to_uid', isEqualTo: otherUid)
        .where('context_ref_id', isEqualTo: contextRefId ?? 'global')
        .where('status', isEqualTo: 'pending')
        .limit(1)
        .snapshots()
        .map((snap) {
          if (snap.docs.isEmpty) return null;
          final doc = snap.docs.first;
          final data = doc.data();
          return {
            'status': data['status'],
            'requestId': doc.id,
            'requestedAt': data['requested_at'],
            'durationHours': data['requested_duration_hours'],
            'note': data['note'],
            'contextTitle': data['context_title'],
          };
        });
  }

  // ---------------------------------------------------------------------
  // Badge streams
  // ---------------------------------------------------------------------

  /// Count of pending requests for this user.
  static Stream<int> pendingRequestsCountStream(String uid) {
    return _db
        .collection('chat_requests')
        .where('to_uid', isEqualTo: uid)
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .map((s) => s.docs.length);
  }

  /// Count of chats where this user is in unread_for (1 per chat, not per
  /// message - matches how the badge is displayed in the UI).
  static Stream<int> unreadChatsCountStream(String uid) {
    return _db
        .collection('chats')
        .where('unread_for', arrayContains: uid)
        .snapshots()
        .map((s) => s.docs.length);
  }

  /// Combined notification count (requests + unread chats).
  static Stream<int> totalNotificationCountStream(String uid) {
    return pendingRequestsCountStream(uid).asyncExpand((requests) {
      return unreadChatsCountStream(uid).map((unread) => requests + unread);
    });
  }

  // ---------------------------------------------------------------------
  // Requests
  // ---------------------------------------------------------------------

  /// The single source of truth for how a "Request to Book" reads as
  /// text - used for the live preview before sending, for the request
  /// cards the provider sees, and for the message seeded into the chat
  /// once accepted. Keeping this in one place means all three always
  /// say exactly the same thing.
  static String composeBookingRequestMessage({
    required DateTime requestedAt,
    int durationHours = 1,
    String? note,
  }) {
    final end = requestedAt.add(Duration(hours: durationHours));
    final text =
        "I'd like to book a slot on ${TimeFormat.date(requestedAt)} "
        'from ${TimeFormat.clock(requestedAt)} to ${TimeFormat.clock(end)}.';
    final trimmedNote = note?.trim() ?? '';
    return trimmedNote.isEmpty ? text : '$text\n\n$trimmedNote';
  }

  /// Other pending/accepted requests sent TO the current user for the
  /// same [contextRefId] (a space) whose time range overlaps the one
  /// being checked. This is informational, not a hard block - an
  /// accepted chat request isn't a confirmed booking the way a paid
  /// reservation would be, so the provider is still the one who decides
  /// who actually gets the slot when more than one person is interested.
  ///
  /// This can only ever check requests sent to yourself (i.e. it's for a
  /// provider comparing requests they've received). Your `chat_requests`
  /// security rule only allows reading documents where you are `from_uid`
  /// or `to_uid` - Firestore rejects an entire list query with
  /// PERMISSION_DENIED if it can't prove every possible match satisfies
  /// the rule, so a query that filtered only by `context_ref_id` would
  /// try to return strangers' requests and fail outright. There's no
  /// secure client-side way to show a renter "N other people asked about
  /// this slot" before they send - that would need a Cloud Function
  /// running with elevated (Admin SDK) access to return just a count
  /// without exposing whose requests they are.
  static Future<List<Map<String, dynamic>>> findOverlappingRequests({
    required String contextRefId,
    required DateTime requestedAt,
    required int durationHours,
    String? excludeRequestId,
  }) async {
    final myUid = _requireUid();
    final start = requestedAt;
    final end = requestedAt.add(Duration(hours: durationHours));

    final snap = await _db
        .collection('chat_requests')
        .where('context_ref_id', isEqualTo: contextRefId)
        .where('to_uid', isEqualTo: myUid)
        .where('status', whereIn: ['pending', 'accepted'])
        .get();

    final overlaps = <Map<String, dynamic>>[];
    for (final doc in snap.docs) {
      if (doc.id == excludeRequestId) continue;

      final data = doc.data();
      final otherStart = (data['requested_at'] as Timestamp?)?.toDate();
      if (otherStart == null) continue;

      final otherDuration =
          (data['requested_duration_hours'] as num?)?.toInt() ?? 1;
      final otherEnd = otherStart.add(Duration(hours: otherDuration));

      final isOverlapping =
          start.isBefore(otherEnd) && otherStart.isBefore(end);
      if (isOverlapping) {
        overlaps.add({...data, 'requestId': doc.id});
      }
    }
    return overlaps;
  }

  /// Creates a new chat request. Each call always produces a new
  /// document — using [newRequestId] which appends a timestamp — so a
  /// renter booking a second (or third) slot on the same space always
  /// gets its own request rather than being silently swallowed by the
  /// existing `accepted` document.
  ///
  /// The old approach used a deterministic ID ([requestIdFor]) and tried
  /// to be idempotent: if a document already existed with status
  /// `accepted`, it was a no-op. That was the correct behaviour when
  /// "one pair of people + one space = one relationship forever", but
  /// broke immediately the second time someone tried to book the same
  /// space for a different slot.
  static Future<String> sendChatRequest({
    required String toUid,
    required String contextType,
    String? contextRefId,
    String? contextTitle,
    DateTime? requestedAt,
    int? durationHours,
    String? note,
  }) async {
    final fromUid = _requireUid();
    if (fromUid == toUid) throw Exception('You cannot message yourself.');

    // Check for a genuinely duplicate in-flight request: if there's
    // already a PENDING request from this renter for this exact space,
    // don't create another one — show them the pending bar instead.
    // Accepted/rejected/cancelled requests are deliberately not blocked
    // here, since those mean the previous booking cycle is complete and
    // a new request for a new slot is exactly what should happen.
    if (contextRefId != null) {
      final existingPending = await _db
          .collection('chat_requests')
          .where('from_uid', isEqualTo: fromUid)
          .where('to_uid', isEqualTo: toUid)
          .where('context_ref_id', isEqualTo: contextRefId)
          .where('status', isEqualTo: 'pending')
          .limit(1)
          .get();
      if (existingPending.docs.isNotEmpty) {
        return existingPending.docs.first.id;
      }
    }

    final reqId = newRequestId(
      fromUid: fromUid,
      toUid: toUid,
      contextType: contextType,
      contextRefId: contextRefId,
    );

    final now = FieldValue.serverTimestamp();
    await _db.collection('chat_requests').doc(reqId).set({
      'from_uid': fromUid,
      'to_uid': toUid,
      'status': 'pending',
      'context_type': contextType,
      'context_ref_id': contextRefId,
      'created_at': now,
      'updated_at': now,
      if (contextTitle != null) 'context_title': contextTitle,
      if (requestedAt != null) 'requested_at': Timestamp.fromDate(requestedAt),
      if (durationHours != null) 'requested_duration_hours': durationHours,
      if (note != null) 'note': note.trim(),
    });

    return reqId;
  }

  static Future<void> cancelChatRequest(String requestId) async {
    final uid = _requireUid();
    final ref = _db.collection('chat_requests').doc(requestId);

    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) return;

      final d = snap.data() as Map<String, dynamic>;
      if (d['from_uid'] != uid) {
        throw Exception('Not authorized to cancel this request.');
      }

      tx.update(ref, {
        'status': 'cancelled',
        'updated_at': FieldValue.serverTimestamp(),
      });
    });
  }

  static Future<void> rejectChatRequest(String requestId) async {
    final uid = _requireUid();
    final ref = _db.collection('chat_requests').doc(requestId);

    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) return;

      final d = snap.data() as Map<String, dynamic>;
      if (d['to_uid'] != uid) {
        throw Exception('Not authorized to decline this request.');
      }

      tx.update(ref, {
        'status': 'rejected',
        'updated_at': FieldValue.serverTimestamp(),
      });
    });
  }

  /// Accept request + create chat if missing. Returns chatId.
  ///
  /// IMPORTANT: Firestore transactions require every read to happen before
  /// any write. An earlier version of this method read the request,
  /// wrote to it, then tried to read the chat doc - which throws at
  /// runtime. Both reads now happen up front, then both writes.
  ///
  /// If the request carries a requested_at (i.e. it came from "Request
  /// to Book" on a parking listing), accepting it also creates a real
  /// booking via BookingService - see that file for why booking creation
  /// happens as a second step after this transaction commits, rather
  /// than inside it.
  static Future<String> acceptChatRequest(String requestId) async {
    final uid = _requireUid();
    final reqRef = _db.collection('chat_requests').doc(requestId);

    // Conflict pre-check, before touching anything. This is what
    // actually prevents double-booking: if someone else's overlapping
    // request was already accepted (and so already has a busy_slot),
    // this blocks the accept outright rather than silently creating a
    // second confirmed booking for the same slot.
    //
    // This check necessarily happens BEFORE the transaction below
    // rather than inside it, since Firestore transactions can't run an
    // arbitrary subcollection query as one of their reads. In the rare
    // case where two accepts for genuinely overlapping requests are
    // submitted within milliseconds of each other, it's theoretically
    // possible for both to pass this check before either's busy_slot
    // exists yet. For the realistic case - a provider reviewing
    // requests one at a time - this is effectively instant and
    // reliable. A fully airtight guarantee against that narrow race
    // would need a Cloud Function.
    final preSnap = await reqRef.get();
    if (!preSnap.exists) throw Exception('Request not found.');
    final preData = preSnap.data() as Map<String, dynamic>;
    final preRequestedAt = preData['requested_at'] as Timestamp?;
    final preSpaceId = preData['context_ref_id'] as String?;
    final preDurationHours =
        (preData['requested_duration_hours'] as num?)?.toInt() ?? 1;

    if (preRequestedAt != null && preSpaceId != null) {
      final start = preRequestedAt.toDate();
      final end = start.add(Duration(hours: preDurationHours));
      final conflicts = await BookingService.findConflicts(
        spaceId: preSpaceId,
        start: start,
        end: end,
      );
      if (conflicts.isNotEmpty) {
        throw Exception(
          'This time slot was already booked by someone else. You can '
          'decline this request or message them to arrange a different '
          'time.',
        );
      }
    }

    final chatId = await _db.runTransaction((tx) async {
      // ---- reads ----
      final reqSnap = await tx.get(reqRef);
      if (!reqSnap.exists) throw Exception('Request not found.');

      final req = reqSnap.data() as Map<String, dynamic>;
      final fromUid = req['from_uid'] as String;
      final toUid = req['to_uid'] as String;
      final status =
          (req['status'] as String?)?.toLowerCase().trim() ?? 'pending';

      if (toUid != uid) {
        throw Exception('Not authorized to accept this request.');
      }

      final chatId = chatIdForUids(fromUid, toUid);

      if (status == 'accepted') return chatId; // already done, no-op
      if (status != 'pending') throw Exception('Request is no longer pending.');

      final chatRef = _db.collection('chats').doc(chatId);
      final chatSnap = await tx.get(chatRef); // second (and last) read

      // ---- writes ----
      final now = FieldValue.serverTimestamp();

      tx.update(reqRef, {'status': 'accepted', 'updated_at': now});

      final requestedAt = req['requested_at'] as Timestamp?;
      final durationHours =
          (req['requested_duration_hours'] as num?)?.toInt() ?? 1;
      final note = req['note'] as String?;
      final contextTitle = req['context_title'] as String?;

      // Compose the booking-request message text. This is what both
      // participants will see in the message thread.
      final messageText = requestedAt != null
          ? composeBookingRequestMessage(
              requestedAt: requestedAt.toDate(),
              durationHours: durationHours,
              note: note,
            )
          : null;

      if (!chatSnap.exists) {
        tx.set(chatRef, {
          'participants': [fromUid, toUid],
          'context_type': req['context_type'] ?? 'private_parking',
          'created_at': now,
          'last_message': messageText ?? 'Booking request accepted',
          'last_message_at': now,
          // The provider (uid = toUid here) is the sender of the
          // booking_request system message - see below.
          'last_sender_id': uid,
          'unread_for': [fromUid], // renter hasn't seen the accept yet
          'hidden_for': <String>[],
          'read_at': {toUid: now},
        });
      } else {
        // Chat already exists from a previous booking - update the
        // summary so the inbox shows the new booking request text
        // instead of whatever the last regular message was.
        tx.update(chatRef, {
          'hidden_for': <String>[],
          'last_message': messageText ?? 'Booking request accepted',
          'last_message_at': now,
          'last_sender_id': uid,
          'unread_for': FieldValue.arrayUnion([fromUid]),
          'read_at.$uid': now,
        });
      }

      // Write the booking request as a real message in the thread.
      //
      // Earlier versions stored this as an `initial_request` field on
      // the chat document and rendered it as a pinned card at the very
      // bottom of the conversation. That worked for the first booking,
      // but every subsequent booking just silently overwrote the same
      // field - nothing new appeared in the thread, and there was no
      // record that a second booking had ever been requested. This is
      // why the user saw the first request but never the second.
      //
      // The fix: write a real messages/{id} document. This requires the
      // writer's own uid as sender_id (security rule: sender_id ==
      // request.auth.uid). The provider (uid = toUid) is performing
      // this accept, so they write it under their own uid - which is
      // valid. The type 'booking_request' lets the chat screen render
      // it as a distinct booking card rather than a plain bubble,
      // regardless of which side of the conversation you're on.
      if (messageText != null) {
        final msgRef = chatRef.collection('messages').doc();
        tx.set(msgRef, {
          'sender_id': uid, // provider - the one accepting, valid under rules
          'type': 'booking_request',
          'text': messageText,
          'from_uid': fromUid, // the renter who made the request
          'requested_at': requestedAt,
          'duration_hours': durationHours,
          'context_title': contextTitle,
          'note': note,
          'created_at': now,
        });
      }

      return chatId;
    });

    // Now that the request is confirmed accepted, create the real
    // booking + busy slot. Run as a second step (see BookingService's
    // doc comment for why this can't live inside the transaction
    // above). The chat already exists at this point regardless of
    // whether this succeeds, so the two people can still coordinate
    // manually even in the rare case this step fails.
    if (preRequestedAt != null && preSpaceId != null) {
      try {
        // Snapshot the space's CURRENT rate onto the booking - read at
        // accept time, not whatever it might be later when earnings get
        // computed. Otherwise a provider raising their price next month
        // would retroactively inflate what past bookings appear to have
        // earned.
        final spaceSnap = await _db
            .collection('parking_spaces')
            .doc(preSpaceId)
            .get();
        final spaceData = spaceSnap.data();
        final hourlyRate =
            ((spaceData?['hourlyRate'] ?? spaceData?['hourly_rate_gbp'] ?? 0)
                    as num)
                .toDouble();

        await BookingService.createBookingAndBusySlot(
          requestId: requestId,
          spaceId: preSpaceId,
          providerUid: uid,
          renterUid: preData['from_uid'] as String,
          start: preRequestedAt,
          durationHours: preDurationHours,
          hourlyRate: hourlyRate,
          spaceTitle: preData['context_title'] as String?,
          note: preData['note'] as String?,
        );
      } catch (e) {
        throw Exception(
          'Request accepted and chat created, but the booking record '
          'could not be saved ($e). The chat is still available - '
          'please confirm the slot with them directly.',
        );
      }
    }

    return chatId;
  }

  // ---------------------------------------------------------------------
  // Unread / read receipts
  // ---------------------------------------------------------------------

  /// Call when opening a chat screen.
  static Future<void> markChatRead(String chatId) async {
    final uid = _requireUid();
    await _db.collection('chats').doc(chatId).update({
      'unread_for': FieldValue.arrayRemove([uid]),
      'read_at.$uid': FieldValue.serverTimestamp(),
    });
  }

  /// True if [uid] has a read_at timestamp at or after [since] - used to
  /// show "Seen" under your most recent message, the same way Messenger
  /// only marks the very last bubble rather than every message.
  static bool hasRead({
    required Map<String, dynamic>? readAt,
    required String uid,
    required Timestamp? since,
  }) {
    if (readAt == null || since == null) return false;
    final ts = readAt[uid] as Timestamp?;
    if (ts == null) return false;
    return !ts.toDate().isBefore(since.toDate());
  }

  // ---------------------------------------------------------------------
  // Archive (hide) - per-user only, never deletes shared data.
  // ---------------------------------------------------------------------

  static Future<void> hideChat(String chatId) async {
    final uid = _requireUid();
    await _db.collection('chats').doc(chatId).update({
      'hidden_for': FieldValue.arrayUnion([uid]),
    });
  }

  static Future<void> unhideChat(String chatId) async {
    final uid = _requireUid();
    await _db.collection('chats').doc(chatId).update({
      'hidden_for': FieldValue.arrayRemove([uid]),
    });
  }

  // ---------------------------------------------------------------------
  // Typing indicators
  // ---------------------------------------------------------------------

  static Future<void> setTyping(String chatId, bool isTyping) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    try {
      await _db.collection('chats').doc(chatId).update({
        'typing.$uid': isTyping ? FieldValue.serverTimestamp() : null,
      });
    } catch (_) {
      // Never let a typing-indicator write crash the UI - it's a nicety,
      // not core functionality.
    }
  }

  /// Emits true while [otherUid] has typed in this chat within [typingTtl].
  static Stream<bool> typingStream(String chatId, String otherUid) {
    return _db.collection('chats').doc(chatId).snapshots().map((snap) {
      final typing = snap.data()?['typing'] as Map<String, dynamic>?;
      final ts = typing?[otherUid] as Timestamp?;
      if (ts == null) return false;
      return DateTime.now().difference(ts.toDate()) < typingTtl;
    });
  }

  // ---------------------------------------------------------------------
  // Presence (best-effort). Accurate while a messaging screen is open and
  // calling heartbeat()/goOffline() from initState/dispose. A fully
  // accurate app-wide "online" status would additionally need a
  // WidgetsBindingObserver at the app root to call goOffline() when the
  // app is backgrounded - that's outside the scope of these 3 files.
  // ---------------------------------------------------------------------

  static Future<void> heartbeat() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    try {
      await _db.collection('users').doc(uid).set({
        'is_online': true,
        'last_seen': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  static Future<void> goOffline() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    try {
      await _db.collection('users').doc(uid).set({
        'is_online': false,
        'last_seen': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  /// Emits true only while is_online is set AND last_seen is recent.
  static Stream<bool> onlineStatusStream(String uid) {
    return _db.collection('users').doc(uid).snapshots().map((snap) {
      final data = snap.data();
      if (data == null) return false;
      final isOnline = data['is_online'] == true;
      final lastSeen = data['last_seen'] as Timestamp?;
      if (!isOnline || lastSeen == null) return false;
      return DateTime.now().difference(lastSeen.toDate()) < onlineTtl;
    });
  }

  static Stream<Timestamp?> lastSeenStream(String uid) {
    return _db
        .collection('users')
        .doc(uid)
        .snapshots()
        .map((snap) => snap.data()?['last_seen'] as Timestamp?);
  }

  // ---------------------------------------------------------------------
  // Messages
  // ---------------------------------------------------------------------

  /// Generates a message id up front so the UI can show an optimistic
  /// bubble immediately, then reconcile it once the real document streams
  /// back from Firestore (see PrivateParkingChatScreen).
  static String newMessageId(String chatId) {
    return _db.collection('chats').doc(chatId).collection('messages').doc().id;
  }

  static Future<void> sendMessage({
    required String chatId,
    required String text,
    String? messageId,
  }) async {
    final uid = _requireUid();
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    final chatRef = _db.collection('chats').doc(chatId);
    final msgRef = messageId != null
        ? chatRef.collection('messages').doc(messageId)
        : chatRef.collection('messages').doc();

    await _db.runTransaction((tx) async {
      final chatSnap = await tx.get(chatRef);
      if (!chatSnap.exists) throw Exception('Chat not found.');

      final chat = chatSnap.data() as Map<String, dynamic>;
      final participants =
          (chat['participants'] as List?)?.cast<String>() ?? <String>[];

      if (!participants.contains(uid)) {
        throw Exception('Not authorized to send messages in this chat.');
      }

      final receivers = participants.where((p) => p != uid).toList();
      final now = FieldValue.serverTimestamp();

      tx.set(msgRef, {
        'sender_id': uid,
        'text': trimmed,
        'created_at': now,
        'type': 'text',
      });

      tx.update(chatRef, {
        'last_message': trimmed,
        'last_message_at': now,
        'last_sender_id': uid,
        'unread_for': FieldValue.arrayUnion(receivers),
        'hidden_for': <String>[], // a new message un-archives for everyone
        'read_at.$uid':
            now, // sender has, by definition, "read" their own message
        'typing.$uid': null, // sending implicitly stops "typing..."
      });
    });
  }
}
