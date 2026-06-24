import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../services/messaging_service.dart';

/// Avatar (+ optional online dot) for a `users/{uid}` document.
///
/// Deliberately opens exactly ONE Firestore listener per instance - the
/// avatar image, the initial-letter fallback, and the online dot are all
/// derived from the same snapshot. Call sites that previously opened a
/// separate StreamBuilder for the avatar and another for the name/online
/// status were tripling the number of active listeners per row.
class ChatAvatar extends StatelessWidget {
  final String uid;
  final double size;
  final bool showOnlineDot;

  const ChatAvatar({
    super.key,
    required this.uid,
    this.size = 44,
    this.showOnlineDot = false,
  });

  /// Shared online-ness check, also used directly by screens that already
  /// have a `users/{uid}` snapshot in hand (e.g. inbox rows) so they don't
  /// need to open a second listener just to ask "is this person online?".
  static bool isOnline(Map<String, dynamic>? data) {
    if (data == null || data['is_online'] != true) return false;
    final lastSeen = data['last_seen'] as Timestamp?;
    if (lastSeen == null) return false;
    return DateTime.now().difference(lastSeen.toDate()) <
        MessagingService.onlineTtl;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .snapshots(),
      builder: (context, snap) {
        final data = snap.data?.data();
        final name = (data?['name'] as String?)?.trim();
        final photo = (data?['photoUrl'] as String?)?.trim();
        final initial = (name == null || name.isEmpty)
            ? '?'
            : name[0].toUpperCase();
        final online = showOnlineDot && isOnline(data);

        final avatar = ClipRRect(
          borderRadius: BorderRadius.circular(size * 0.32),
          child: Container(
            height: size,
            width: size,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: (photo != null && photo.isNotEmpty)
                ? Image.network(
                    photo,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _Initial(initial, size),
                  )
                : _Initial(initial, size),
          ),
        );

        if (!showOnlineDot) return avatar;

        return Stack(
          clipBehavior: Clip.none,
          children: [
            avatar,
            Positioned(
              right: -1,
              bottom: -1,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity: online ? 1 : 0,
                child: Container(
                  width: size * 0.28,
                  height: size * 0.28,
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Initial extends StatelessWidget {
  final String text;
  final double size;
  const _Initial(this.text, this.size);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        text,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w900,
          fontSize: size * 0.38,
        ),
      ),
    );
  }
}

/// Display name only - for call sites (like a request card) that need the
/// name but render their own avatar/layout separately.
class ChatUserName extends StatelessWidget {
  final String uid;
  final TextStyle? style;
  final String fallback;

  const ChatUserName({
    super.key,
    required this.uid,
    this.style,
    this.fallback = 'User',
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .snapshots(),
      builder: (context, snap) {
        final name = (snap.data?.data()?['name'] as String?)?.trim();
        return Text(
          (name == null || name.isEmpty) ? fallback : name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: style ?? const TextStyle(fontWeight: FontWeight.w900),
        );
      },
    );
  }
}
