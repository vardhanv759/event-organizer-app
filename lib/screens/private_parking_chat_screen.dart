import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/messaging_service.dart';

class PrivateParkingChatScreen extends StatefulWidget {
  final String chatId;
  final String otherUid;

  const PrivateParkingChatScreen({
    super.key,
    required this.chatId,
    required this.otherUid,
  });

  @override
  State<PrivateParkingChatScreen> createState() =>
      _PrivateParkingChatScreenState();
}

class _PrivateParkingChatScreenState extends State<PrivateParkingChatScreen> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final myUid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FF),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('users')
              .doc(widget.otherUid)
              .snapshots(),
          builder: (context, snap) {
            if (!snap.hasData || !snap.data!.exists) {
              return const Text('Chat');
            }
            final data = snap.data!.data();
            final name = (data?['name'] as String?)?.trim();
            return Text(
              (name == null || name.isEmpty) ? 'Chat' : name,
              style: const TextStyle(fontWeight: FontWeight.w700),
            );
          },
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('chats')
                  .doc(widget.chatId)
                  .collection('messages')
                  .orderBy('created_at', descending: true)
                  .limit(80)
                  .snapshots(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final docs = snap.data?.docs ?? [];
                if (docs.isEmpty) {
                  return const Center(child: Text('No messages yet.'));
                }

                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  reverse: true,
                  itemCount: docs.length,
                  itemBuilder: (_, i) {
                    final d = docs[i].data();
                    final sender = (d['sender_id'] as String?) ?? '';
                    final text = (d['text'] as String?) ?? '';
                    final isMe = sender.isNotEmpty && sender == myUid;

                    return Align(
                      alignment: isMe
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        constraints: const BoxConstraints(maxWidth: 320),
                        decoration: BoxDecoration(
                          color: isMe ? const Color(0xFF6366F1) : Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.06),
                              blurRadius: 12,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Text(
                          text,
                          style: TextStyle(
                            color: isMe
                                ? Colors.white
                                : const Color(0xFF0F172A),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          _Composer(
            controller: _controller,
            onSend: () async {
              final text = _controller.text;
              _controller.clear();
              try {
                await MessagingService.sendMessage(
                  chatId: widget.chatId,
                  text: text,
                );
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text('Send failed: $e')));
              }
            },
          ),
        ],
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSend;

  const _Composer({required this.controller, required this.onSend});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 4,
                decoration: InputDecoration(
                  hintText: 'Type a message…',
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            ElevatedButton(
              onPressed: onSend,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Icon(Icons.send_rounded),
            ),
          ],
        ),
      ),
    );
  }
}
