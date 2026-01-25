import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../services/messaging_service.dart';
import 'private_parking_chat_screen.dart';

class PrivateParkingMessagesScreen extends StatelessWidget {
  const PrivateParkingMessagesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(body: Center(child: Text('Not signed in.')));
    }
    final myUid = user.uid;

    return Scaffold(
      appBar: AppBar(title: const Text('Messages'), centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SectionTitle('Incoming Requests'),
          _IncomingRequests(myUid: myUid),

          const SizedBox(height: 24),

          _SectionTitle('Outgoing Requests'),
          _OutgoingRequests(myUid: myUid),

          const SizedBox(height: 24),

          _SectionTitle('Chats'),
          _ChatsList(myUid: myUid),
        ],
      ),
    );
  }
}

/* -------------------------------------------------------------------------- */
/*                               INCOMING REQUESTS                            */
/* -------------------------------------------------------------------------- */

class _IncomingRequests extends StatelessWidget {
  final String myUid;
  const _IncomingRequests({required this.myUid});

  @override
  Widget build(BuildContext context) {
    final q = FirebaseFirestore.instance
        .collection('chat_requests')
        .where('to_uid', isEqualTo: myUid)
        .where('status', isEqualTo: 'pending');

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: q.snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return const _EmptyCard(text: 'Error loading requests');
        }
        if (snap.connectionState == ConnectionState.waiting) {
          return const _LoadingCard();
        }

        final docs = snap.data?.docs ?? const [];
        if (docs.isEmpty) return const _EmptyCard(text: 'No incoming requests');

        return Column(
          children: docs.map((d) {
            final data = d.data();
            final fromUid = (data['from_uid'] as String?)?.trim() ?? '';
            if (fromUid.isEmpty) return const SizedBox.shrink();

            return _IncomingRequestTile(requestId: d.id, fromUid: fromUid);
          }).toList(),
        );
      },
    );
  }
}

class _IncomingRequestTile extends StatefulWidget {
  final String requestId;
  final String fromUid;

  const _IncomingRequestTile({required this.requestId, required this.fromUid});

  @override
  State<_IncomingRequestTile> createState() => _IncomingRequestTileState();
}

class _IncomingRequestTileState extends State<_IncomingRequestTile> {
  bool _busy = false;

  Future<void> _reject() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await MessagingService.rejectChatRequest(widget.requestId);
    } catch (e) {
      if (mounted) _toast(context, 'Reject failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _accept() async {
    if (_busy) return;
    setState(() => _busy = true);

    try {
      final chatId = await MessagingService.acceptChatRequest(widget.requestId);

      if (!mounted) return;

      // Go straight to chat after accept
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PrivateParkingChatScreen(
            chatId: chatId,
            otherUid: widget.fromUid,
          ),
        ),
      );
    } catch (e) {
      if (mounted) _toast(context, 'Accept failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: const Icon(
          Icons.mark_unread_chat_alt_rounded,
          color: Color(0xFF4F46E5),
        ),
        title: _UserName(uid: widget.fromUid),
        subtitle: const Text('Wants to chat with you'),
        trailing: _busy
            ? const SizedBox(
                height: 22,
                width: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Reject',
                    icon: const Icon(Icons.close, color: Colors.red),
                    onPressed: _reject,
                  ),
                  IconButton(
                    tooltip: 'Accept',
                    icon: const Icon(Icons.check, color: Colors.green),
                    onPressed: _accept,
                  ),
                ],
              ),
      ),
    );
  }
}

/* -------------------------------------------------------------------------- */
/*                               OUTGOING REQUESTS                            */
/* -------------------------------------------------------------------------- */

class _OutgoingRequests extends StatelessWidget {
  final String myUid;
  const _OutgoingRequests({required this.myUid});

  @override
  Widget build(BuildContext context) {
    final q = FirebaseFirestore.instance
        .collection('chat_requests')
        .where('from_uid', isEqualTo: myUid)
        .where('status', isEqualTo: 'pending');

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: q.snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return const _EmptyCard(text: 'Error loading requests');
        }
        if (snap.connectionState == ConnectionState.waiting) {
          return const _LoadingCard();
        }

        final docs = snap.data?.docs ?? const [];
        if (docs.isEmpty) return const _EmptyCard(text: 'No outgoing requests');

        return Column(
          children: docs.map((d) {
            final data = d.data();
            final toUid = (data['to_uid'] as String?)?.trim() ?? '';
            if (toUid.isEmpty) return const SizedBox.shrink();

            return _OutgoingRequestTile(requestId: d.id, toUid: toUid);
          }).toList(),
        );
      },
    );
  }
}

class _OutgoingRequestTile extends StatefulWidget {
  final String requestId;
  final String toUid;

  const _OutgoingRequestTile({required this.requestId, required this.toUid});

  @override
  State<_OutgoingRequestTile> createState() => _OutgoingRequestTileState();
}

class _OutgoingRequestTileState extends State<_OutgoingRequestTile> {
  bool _busy = false;

  Future<void> _cancel() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await MessagingService.cancelChatRequest(widget.requestId);
    } catch (e) {
      if (mounted) _toast(context, 'Cancel failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: const Icon(
          Icons.call_made_rounded, // safe icon
          color: Color(0xFF4F46E5),
        ),
        title: _UserName(uid: widget.toUid),
        subtitle: const Text('Request pending'),
        trailing: _busy
            ? const SizedBox(
                height: 22,
                width: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : TextButton.icon(
                onPressed: _cancel,
                icon: const Icon(Icons.cancel_outlined),
                label: const Text('Cancel'),
              ),
      ),
    );
  }
}

/* -------------------------------------------------------------------------- */
/*                                    CHATS                                   */
/* -------------------------------------------------------------------------- */

class _ChatsList extends StatelessWidget {
  final String myUid;
  const _ChatsList({required this.myUid});

  @override
  Widget build(BuildContext context) {
    // NOTE: Avoid orderBy here to prevent composite-index friction during dev.
    final q = FirebaseFirestore.instance
        .collection('chats')
        .where('participants', arrayContains: myUid);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: q.snapshots(),
      builder: (context, snap) {
        if (snap.hasError) return const _EmptyCard(text: 'Error loading chats');
        if (snap.connectionState == ConnectionState.waiting) {
          return const _LoadingCard();
        }

        final docs = snap.data?.docs ?? const [];
        if (docs.isEmpty) return const _EmptyCard(text: 'No active chats');

        return Column(
          children: docs.map((d) {
            final data = d.data();
            final participants =
                (data['participants'] as List?)?.cast<String>() ?? <String>[];
            if (!participants.contains(myUid) || participants.length < 2) {
              return const SizedBox.shrink();
            }
            final otherUid = participants.firstWhere(
              (u) => u != myUid,
              orElse: () => '',
            );
            if (otherUid.isEmpty) return const SizedBox.shrink();

            final last = (data['last_message'] as String?)?.trim() ?? '';

            return _ChatTile(
              chatId: d.id,
              otherUid: otherUid,
              lastMessage: last,
            );
          }).toList(),
        );
      },
    );
  }
}

class _ChatTile extends StatelessWidget {
  final String chatId;
  final String otherUid;
  final String lastMessage;

  const _ChatTile({
    required this.chatId,
    required this.otherUid,
    required this.lastMessage,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: const Icon(Icons.chat_bubble_outline),
        title: _UserName(uid: otherUid),
        subtitle: Text(lastMessage.isEmpty ? 'Tap to open chat' : lastMessage),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) =>
                  PrivateParkingChatScreen(chatId: chatId, otherUid: otherUid),
            ),
          );
        },
      ),
    );
  }
}

/* -------------------------------------------------------------------------- */
/*                                   HELPERS                                  */
/* -------------------------------------------------------------------------- */

class _UserName extends StatelessWidget {
  final String uid;
  const _UserName({required this.uid});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData || !(snap.data?.exists ?? false)) {
          return Text(uid); // fallback
        }
        final data = snap.data!.data() ?? <String, dynamic>{};
        final name = (data['name'] as String?)?.trim();
        return Text((name == null || name.isEmpty) ? uid : name);
      },
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  final String text;
  const _EmptyCard({required this.text});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(padding: const EdgeInsets.all(16), child: Text(text)),
    );
  }
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      ),
    );
  }
}

void _toast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
}
