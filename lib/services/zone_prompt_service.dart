import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ZonePromptService {
  static final _db = FirebaseFirestore.instance;
  static final _auth = FirebaseAuth.instance;

  static String _uid() {
    final u = _auth.currentUser?.uid;
    if (u == null) throw Exception('Not signed in');
    return u;
  }

  static Future<String?> getDecisionForZone(String zoneId) async {
    final uid = _uid();
    final doc = await _db
        .collection('users')
        .doc(uid)
        .collection('zone_prompts')
        .doc(zoneId)
        .get();

    if (!doc.exists) return null;
    return doc.data()?['decision'] as String?;
  }

  static Future<void> setDecision({
    required String zoneId,
    required String decision, // "accepted" | "rejected"
  }) async {
    final uid = _uid();
    await _db
        .collection('users')
        .doc(uid)
        .collection('zone_prompts')
        .doc(zoneId)
        .set({
          'zoneId': zoneId,
          'decision': decision,
          'decidedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
  }

  /// Join a zone and write membership + system message to chat
  static Future<void> joinZone({
    required String zoneId,
    required String displayName,
    required String photoUrl,
  }) async {
    final uid = _uid();

    // ✅ Fix: use 'displayName' field (not 'name') so MemberCard shows real name
    await _db
        .collection('zones')
        .doc(zoneId)
        .collection('members')
        .doc(uid)
        .set({
          'uid': uid,
          'role': 'user',
          'displayName': displayName, // ← was missing, caused "Member" bug
          'photoUrl': photoUrl,
          'joinedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

    // ✅ Post system message so chat shows join notification
    final firstName = displayName.split(' ').first;
    await _db.collection('zones').doc(zoneId).collection('messages').add({
      'text': '$firstName joined the zone 👋',
      'senderId': 'system',
      'senderName': 'System',
      'timestamp': FieldValue.serverTimestamp(),
      'isSystemMessage': true,
      'deletedAt': null,
    });

    // Record decision so we never prompt again
    await setDecision(zoneId: zoneId, decision: 'accepted');
  }

  /// Check if a user is currently muted in a zone
  static Future<bool> isUserMuted(String zoneId) async {
    final uid = _uid();
    try {
      final doc = await _db
          .collection('zones')
          .doc(zoneId)
          .collection('muted')
          .doc(uid)
          .get();

      if (!doc.exists) return false;
      final data = doc.data()!;
      final isPermanent = data['isPermanent'] == true;
      if (isPermanent) return true;

      final until = data['mutedUntil'] as Timestamp?;
      if (until == null) return false;
      return until.toDate().isAfter(DateTime.now());
    } catch (_) {
      return false;
    }
  }

  /// Check if a user is blocked from a zone
  static Future<bool> isUserBlocked(String zoneId) async {
    final uid = _uid();
    try {
      final doc = await _db
          .collection('zones')
          .doc(zoneId)
          .collection('blocked')
          .doc(uid)
          .get();
      return doc.exists;
    } catch (_) {
      return false;
    }
  }
}
