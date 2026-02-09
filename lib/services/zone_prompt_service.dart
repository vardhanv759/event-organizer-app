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

  static Future<void> joinZone({
    required String zoneId,
    required String displayName,
    required String photoUrl,
  }) async {
    final uid = _uid();

    // Write membership
    await _db
        .collection('zones')
        .doc(zoneId)
        .collection('members')
        .doc(uid)
        .set({
          'uid': uid,
          'role': 'user',
          'displayName': displayName,
          'photoUrl': photoUrl,
          'joinedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

    // Record decision so we never prompt again
    await setDecision(zoneId: zoneId, decision: 'accepted');
  }
}
