import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:secure_messenger/ui/theme.dart';
import 'package:secure_messenger/widgets/glass_container.dart';
import 'package:secure_messenger/services/encryption_service.dart';

class ChatMessage {
  final EncryptedMessage encryptedContent;
  final bool isMe;
  final String time;

  ChatMessage({required this.encryptedContent, required this.isMe, required this.time});
}

class ChatRoomScreen extends ConsumerStatefulWidget {
  final String contactName;
  const ChatRoomScreen({super.key, required this.contactName});

  @override
  ConsumerState<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

class _ChatRoomScreenState extends ConsumerState<ChatRoomScreen> {
  final TextEditingController _msgController = TextEditingController();
  final List<ChatMessage> _messages = [];
  final EncryptionService _encryptionService = EncryptionService();

  void _sendMessage() {
    if (_msgController.text.trim().isEmpty) return;

    final String rawMsg = _msgController.text.trim();
    final encrypted = _encryptionService.encrypt(rawMsg);

    setState(() {
      _messages.insert(0, ChatMessage(
        encryptedContent: encrypted,
        isMe: true,
        time: 'Now',
      ));
    });
    
    _msgController.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: AppTheme.neonMagenta.withOpacity(0.2),
              child: const Icon(Icons.security, size: 16, color: AppTheme.neonMagenta),
            ),
            const SizedBox(width: 8),
            Text(widget.contactName, style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          IconButton(icon: const Icon(Icons.call), onPressed: () {}),
          IconButton(icon: const Icon(Icons.more_vert), onPressed: () {}),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppTheme.background, Color(0xFF0F172A)],
          ),
        ),
        child: Column(
          children: [
            // E2E Encryption Banner
            Container(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
              margin: const EdgeInsets.only(top: 8),
              decoration: BoxDecoration(
                color: AppTheme.neonCyan.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.lock, size: 14, color: AppTheme.neonCyan),
                  SizedBox(width: 6),
                  Text(
                    'Messages are end-to-end encrypted',
                    style: TextStyle(color: AppTheme.neonCyan, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.builder(
                reverse: true, // starts from bottom
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                itemCount: _messages.length,
                itemBuilder: (context, index) {
                  final msg = _messages[index];
                  // DECRYPT on the fly
                  final String decryptedMsg = _encryptionService.decrypt(msg.encryptedContent);

                  return Align(
                    alignment: msg.isMe ? Alignment.centerRight : Alignment.centerLeft,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: MediaQuery.of(context).size.width * 0.75,
                      ),
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: msg.isMe 
                               ? AppTheme.neonCyan.withOpacity(0.15)
                               : Colors.white.withOpacity(0.05),
                          borderRadius: BorderRadius.only(
                            topLeft: const Radius.circular(16),
                            topRight: const Radius.circular(16),
                            bottomLeft: msg.isMe ? const Radius.circular(16) : const Radius.circular(4),
                            bottomRight: msg.isMe ? const Radius.circular(4) : const Radius.circular(16),
                          ),
                          border: Border.all(
                            color: msg.isMe ? AppTheme.neonCyan.withOpacity(0.3) : Colors.white.withOpacity(0.1),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              decryptedMsg,
                              style: const TextStyle(color: Colors.white, fontSize: 16),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  msg.time,
                                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: 10),
                                ),
                                if (msg.isMe) ...[
                                  const SizedBox(width: 4),
                                  const Icon(Icons.done_all, size: 14, color: AppTheme.neonCyan),
                                ]
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            
            // Input Area
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Row(
                  children: [
                    Expanded(
                      child: GlassContainer(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        borderRadius: 24,
                        child: TextField(
                          controller: _msgController,
                          style: const TextStyle(color: Colors.white),
                          decoration: const InputDecoration(
                            hintText: 'Type an encrypted message...',
                            hintStyle: TextStyle(color: AppTheme.textSecondary),
                            border: InputBorder.none,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    GestureDetector(
                      onTap: _sendMessage,
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppTheme.neonCyan,
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.neonCyan.withOpacity(0.4),
                              blurRadius: 12,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: const Icon(Icons.send, color: AppTheme.background),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
