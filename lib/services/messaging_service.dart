import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class MessagingService {
  static final _db = FirebaseFirestore.instance;
  static final _auth = FirebaseAuth.instance;

  static String _requireUid() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw Exception('Not signed in.');
    return uid;
  }

  static String chatIdForUids(String a, String b) {
    final sorted = [a, b]..sort();
    return '${sorted[0]}_${sorted[1]}';
  }

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

  // -------------------------
  // BADGE STREAMS
  // -------------------------

  /// Count of pending requests for this user.
  static Stream<int> pendingRequestsCountStream(String uid) {
    return _db
        .collection('chat_requests')
        .where('to_uid', isEqualTo: uid)
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .map((s) => s.docs.length);
  }

  /// Count of chats where this user is in unread_for (1 per chat, not per msg).
  static Stream<int> unreadChatsCountStream(String uid) {
    return _db
        .collection('chats')
        .where('unread_for', arrayContains: uid)
        .snapshots()
        .map((s) => s.docs.length);
  }

  // -------------------------
  // REQUESTS
  // -------------------------

  /// Creates a request (idempotent).
  static Future<String> sendChatRequest({
    required String toUid,
    required String contextType,
    String? contextRefId,
  }) async {
    final fromUid = _requireUid();
    if (fromUid == toUid) throw Exception('You cannot message yourself.');

    final reqId = requestIdFor(
      fromUid: fromUid,
      toUid: toUid,
      contextType: contextType,
      contextRefId: contextRefId,
    );

    final ref = _db.collection('chat_requests').doc(reqId);

    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final now = FieldValue.serverTimestamp();

      if (!snap.exists) {
        tx.set(ref, {
          'from_uid': fromUid,
          'to_uid': toUid,
          'status': 'pending',
          'context_type': contextType,
          'context_ref_id': contextRefId,
          'created_at': now,
          'updated_at': now,
        });
      } else {
        final data = snap.data() as Map<String, dynamic>;
        final status = (data['status'] as String?)?.toLowerCase().trim();

        // If previously rejected/cancelled, allow resending.
        if (status != 'pending' && status != 'accepted') {
          tx.update(ref, {'status': 'pending', 'updated_at': now});
        }
      }
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
      if (d['from_uid'] != uid) return;

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
      if (d['to_uid'] != uid) return;

      tx.update(ref, {
        'status': 'rejected',
        'updated_at': FieldValue.serverTimestamp(),
      });
    });
  }

  /// Accept request + create chat if missing. Returns chatId.
  static Future<String> acceptChatRequest(String requestId) async {
    final uid = _requireUid();
    final reqRef = _db.collection('chat_requests').doc(requestId);

    return _db.runTransaction((tx) async {
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
      if (status == 'accepted') return chatIdForUids(fromUid, toUid);
      if (status != 'pending') throw Exception('Request is not pending.');

      // Update request status
      tx.update(reqRef, {
        'status': 'accepted',
        'updated_at': FieldValue.serverTimestamp(),
      });

      // Create chat (one per pair)
      final chatId = chatIdForUids(fromUid, toUid);
      final chatRef = _db.collection('chats').doc(chatId);
      final chatSnap = await tx.get(chatRef);

      if (!chatSnap.exists) {
        tx.set(chatRef, {
          'participants': [fromUid, toUid],
          'context_type': req['context_type'] ?? 'private_parking',
          'created_at': FieldValue.serverTimestamp(),
          'last_message': '',
          'last_message_at': FieldValue.serverTimestamp(),
          'last_sender_id': '',
          'unread_for': <String>[], // no unread on creation
          'read_at': {
            fromUid: FieldValue.serverTimestamp(),
            toUid: FieldValue.serverTimestamp(),
          },
        });
      }

      return chatId;
    });
  }

  // -------------------------
  // UNREAD LOGIC
  // -------------------------

  /// Call when opening a chat screen.
  static Future<void> markChatRead(String chatId) async {
    final uid = _requireUid();
    final chatRef = _db.collection('chats').doc(chatId);

    await chatRef.update({
      'unread_for': FieldValue.arrayRemove([uid]),
      'read_at.$uid': FieldValue.serverTimestamp(),
    });
  }

  // -------------------------
  // MESSAGES
  // -------------------------

  static Future<void> sendMessage({
    required String chatId,
    required String text,
  }) async {
    final uid = _requireUid();
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    final chatRef = _db.collection('chats').doc(chatId);
    final msgRef = chatRef.collection('messages').doc();

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

      // write message
      tx.set(msgRef, {
        'sender_id': uid,
        'text': trimmed,
        'created_at': now,
        'type': 'text',
      });

      // update chat summary + unread_for (ONE PER CHAT)
      tx.update(chatRef, {
        'last_message': trimmed,
        'last_message_at': now,
        'last_sender_id': uid,
        'unread_for': FieldValue.arrayUnion(receivers),
        'read_at.$uid': now, // sender read time
      });
    });
  }
}
