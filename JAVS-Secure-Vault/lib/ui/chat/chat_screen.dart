import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../services/firebase_service.dart';
import '../../core/crypto/idmc_engine.dart';
import '../../core/ml/igmh_synchronizer.dart';
import '../theme/cyber_theme.dart';

class ChatScreen extends ConsumerWidget {
  final String chatRoomId;
  final String chatName;
  final bool isGroup;

  const ChatScreen({
    super.key,
    required this.chatRoomId,
    required this.chatName,
    this.isGroup = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chatAsync = ref.watch(chatStreamProvider(chatRoomId));
    final textController = TextEditingController();
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      backgroundColor: CyberTheme.background,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(chatName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            Text(isGroup ? 'Group Chat' : 'Direct Message', style: const TextStyle(fontSize: 10, color: CyberTheme.primaryNeon)),
          ],
        ),
        backgroundColor: CyberTheme.surface,
        elevation: 0,
      ),
      body: Column(
        children: [
          Expanded(
            child: chatAsync.when(
              data: (messages) => ListView.builder(
                reverse: false,
                padding: const EdgeInsets.all(16),
                itemCount: messages.length,
                itemBuilder: (context, index) {
                  final msg = messages[index];
                  final isMe = msg.senderId == currentUserId;
                  return _MessageBubble(
                    message: msg, 
                    isMe: isMe,
                    isGroup: isGroup,
                  );
                },
              ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, r) => Center(child: Text("Error: $e", style: const TextStyle(color: Colors.red))),
            ),
          ),
          _buildInputArea(ref, textController),
        ],
      ),
    );
  }

  Widget _buildInputArea(WidgetRef ref, TextEditingController controller) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: CyberTheme.surface,
        border: Border(top: BorderSide(color: Colors.white10)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                hintText: "Enter message...",
                border: InputBorder.none,
                filled: false,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.send, color: CyberTheme.primaryNeon),
            onPressed: () {
              if (controller.text.isEmpty) return;
              final seed = IGMHSynchronizer.generate512BitSeed("default-session");
              final ciphertext = IDMCEngine.encryptText(controller.text, seed);
              ref.read(firebaseServiceProvider).sendSecureMessage(chatRoomId, ciphertext);
              controller.clear();
            },
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatefulWidget {
  final JAVSMessage message;
  final bool isMe;
  final bool isGroup;

  const _MessageBubble({required this.message, required this.isMe, this.isGroup = false});

  @override
  State<_MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<_MessageBubble> {
  bool _isDecrypted = false;
  String? _decryptedText;

  void _decrypt() {
    final seed = IGMHSynchronizer.generate512BitSeed("default-session");
    final result = IDMCEngine.decryptText(widget.message.content, seed);
    setState(() {
      _decryptedText = result;
      _isDecrypted = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: widget.isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(12),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        decoration: BoxDecoration(
          color: widget.isMe ? CyberTheme.primaryNeon.withOpacity(0.1) : CyberTheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: widget.isMe ? CyberTheme.primaryNeon : Colors.white10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.isMe == false && widget.isGroup)
              Text(
                widget.message.senderName ?? 'Unknown',
                style: const TextStyle(
                  fontSize: 10,
                  color: CyberTheme.primaryNeon,
                  fontWeight: FontWeight.bold,
                ),
              ),
            if (!_isDecrypted)
              Text(
                widget.message.content,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: Colors.grey),
              )
            else
              Text(
                _decryptedText ?? "",
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            const SizedBox(height: 8),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: _decrypt,
                  child: Text(
                    _isDecrypted ? "RECONSTRUCTED" : "INITIATE RECONSTRUCTION",
                    style: TextStyle(
                      fontSize: 9, 
                      fontWeight: FontWeight.bold, 
                      color: _isDecrypted ? Colors.blue : CyberTheme.primaryNeon
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => Clipboard.setData(ClipboardData(text: widget.message.content)),
                  child: const Icon(Icons.copy, size: 10, color: Colors.grey),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
