import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:secure_messenger/ui/theme.dart';
import 'package:secure_messenger/widgets/glass_container.dart';
import 'package:secure_messenger/core/crypto/idmc_engine.dart';
import 'package:secure_messenger/core/ml/igmh_synchronizer.dart';

class ChatMessage {
  final String encryptedContent;
  final bool isMe;
  final String time;
  final String messageType;
  final String? attachmentName;

  ChatMessage({
    required this.encryptedContent,
    required this.isMe,
    required this.time,
    this.messageType = 'text',
    this.attachmentName,
  });
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
  PlatformFile? _attachedFile;

  Future<void> _pickAttachment() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: false,
      withData: true,
    );

    if (result == null || result.files.isEmpty) return;

    setState(() {
      _attachedFile = result.files.first;
    });
  }

  bool _isImageFile(String? name) {
    if (name == null) return false;
    final lower = name.toLowerCase();
    return lower.endsWith('.png') || lower.endsWith('.jpg') || lower.endsWith('.jpeg') || lower.endsWith('.gif') || lower.endsWith('.webp');
  }

  void _sendMessage() {
    if (_attachedFile == null && _msgController.text.trim().isEmpty) return;

    final seed = IGMHSynchronizer.generate512BitSeed('default-session');
    if (_attachedFile != null && _attachedFile!.bytes != null) {
      final data = _attachedFile!.bytes!;
      final encryptedBytes = IDMCEngine.processBytes(Uint8List.fromList(data), seed);
      final encrypted = base64.encode(encryptedBytes);

      setState(() {
        _messages.insert(0, ChatMessage(
          encryptedContent: encrypted,
          isMe: true,
          time: 'Now',
          messageType: 'file',
          attachmentName: _attachedFile!.name,
        ));
        _attachedFile = null;
      });
    } else {
      final String rawMsg = _msgController.text.trim();
      final encrypted = IDMCEngine.encryptText(rawMsg, seed);

      setState(() {
        _messages.insert(0, ChatMessage(
          encryptedContent: encrypted,
          isMe: true,
          time: 'Now',
          messageType: 'text',
        ));
      });
      _msgController.clear();
    }
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
                  final seed = IGMHSynchronizer.generate512BitSeed('default-session');
                  Widget contentWidget;

                  if (msg.messageType == 'file') {
                    final encryptedBytes = base64.decode(msg.encryptedContent);
                    final decryptedBytes = IDMCEngine.processBytes(Uint8List.fromList(encryptedBytes), seed, decrypt: true);
                    if (_isImageFile(msg.attachmentName)) {
                      contentWidget = Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.memory(
                              decryptedBytes,
                              fit: BoxFit.cover,
                              width: MediaQuery.of(context).size.width * 0.65,
                              height: 180,
                              errorBuilder: (_, __, ___) => Container(
                                height: 180,
                                color: Colors.black12,
                                child: const Center(child: Text('Unable to render image', style: TextStyle(color: Colors.white70))),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            msg.attachmentName ?? 'Encrypted image',
                            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                          ),
                        ],
                      );
                    } else {
                      contentWidget = Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            msg.attachmentName ?? 'Encrypted file',
                            style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Decrypted ${msg.attachmentName ?? 'file'} • ${decryptedBytes.lengthInBytes} bytes',
                            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                          ),
                        ],
                      );
                    }
                  } else {
                    final String decryptedMsg = IDMCEngine.decryptText(msg.encryptedContent, seed);
                    contentWidget = Text(
                      decryptedMsg,
                      style: const TextStyle(color: Colors.white, fontSize: 16),
                    );
                  }

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
                            contentWidget,
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
            
            if (_attachedFile != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppTheme.surface.withOpacity(0.9),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.neonCyan.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.attach_file, size: 18, color: AppTheme.neonCyan),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _attachedFile!.name,
                          style: const TextStyle(color: Colors.white, fontSize: 14),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 18, color: AppTheme.textSecondary),
                        onPressed: () => setState(() => _attachedFile = null),
                      ),
                    ],
                  ),
                ),
              ),
            // Input Area
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: _pickAttachment,
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppTheme.surface,
                          border: Border.all(color: AppTheme.neonCyan.withOpacity(0.4)),
                        ),
                        child: const Icon(Icons.attach_file, color: AppTheme.neonCyan),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: GlassContainer(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        borderRadius: 24,
                        child: TextField(
                          controller: _msgController,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            hintText: _attachedFile != null ? 'Ready to encrypt attached file...' : 'Type an encrypted message...',
                            hintStyle: const TextStyle(color: AppTheme.textSecondary),
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
