import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../services/firebase_service.dart';
import '../../core/crypto/idmc_engine.dart';
import '../../core/ml/igmh_synchronizer.dart';
import '../theme/cyber_theme.dart';

class ChatScreen extends ConsumerStatefulWidget {
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
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final TextEditingController _textController = TextEditingController();
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

  void _sendMessage() {
    if (_attachedFile == null && _textController.text.trim().isEmpty) return;

    final seed = IGMHSynchronizer.generate512BitSeed('default-session');

    if (_attachedFile != null && _attachedFile!.bytes != null) {
      final encryptedBytes = IDMCEngine.processBytes(Uint8List.fromList(_attachedFile!.bytes!), seed);
      final ciphertext = base64.encode(encryptedBytes);
      ref.read(firebaseServiceProvider).sendSecureMessage(
        widget.chatRoomId,
        ciphertext,
        messageType: 'file',
        attachmentName: _attachedFile!.name,
      );
      setState(() => _attachedFile = null);
    } else {
      final ciphertext = IDMCEngine.encryptText(_textController.text.trim(), seed);
      ref.read(firebaseServiceProvider).sendSecureMessage(widget.chatRoomId, ciphertext);
      _textController.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final chatAsync = ref.watch(chatStreamProvider(widget.chatRoomId));
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      backgroundColor: CyberTheme.background,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.chatName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            Text(widget.isGroup ? 'Group Chat' : 'Direct Message', style: const TextStyle(fontSize: 10, color: CyberTheme.primaryNeon)),
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
                    isGroup: widget.isGroup,
                  );
                },
              ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, r) => Center(child: Text("Error: $e", style: const TextStyle(color: Colors.red))),
            ),
          ),
          _buildInputArea(ref),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Widget _buildInputArea(WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: CyberTheme.surface,
        border: Border(top: BorderSide(color: Colors.white10)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_attachedFile != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: CyberTheme.background.withOpacity(0.95),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: CyberTheme.primaryNeon.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.attach_file, size: 18, color: CyberTheme.primaryNeon),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _attachedFile!.name,
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18, color: Colors.white70),
                      onPressed: () => setState(() => _attachedFile = null),
                    ),
                  ],
                ),
              ),
            ),
          Row(
            children: [
              GestureDetector(
                onTap: _pickAttachment,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: CyberTheme.surface,
                    border: Border.all(color: CyberTheme.primaryNeon.withOpacity(0.4)),
                  ),
                  child: const Icon(Icons.attach_file, color: CyberTheme.primaryNeon),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _textController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: _attachedFile != null ? 'Ready to encrypt attached file...' : 'Enter message...',
                    hintStyle: const TextStyle(color: Colors.grey),
                    border: InputBorder.none,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.send, color: CyberTheme.primaryNeon),
                onPressed: _sendMessage,
              ),
            ],
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
  Uint8List? _decryptedBytes;

  bool _isImageFile(String? name) {
    if (name == null) return false;
    final lower = name.toLowerCase();
    return lower.endsWith('.png') || lower.endsWith('.jpg') || lower.endsWith('.jpeg') || lower.endsWith('.gif') || lower.endsWith('.webp');
  }

  void _decrypt() {
    final seed = IGMHSynchronizer.generate512BitSeed("default-session");
    if (widget.message.messageType == 'file') {
      try {
        final encryptedBytes = base64.decode(widget.message.content);
        _decryptedBytes = IDMCEngine.processBytes(Uint8List.fromList(encryptedBytes), seed, decrypt: true);
      } catch (_) {
        _decryptedText = 'Unable to decrypt attachment';
      }
    } else {
      _decryptedText = IDMCEngine.decryptText(widget.message.content, seed);
    }

    setState(() {
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
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.message.messageType == 'file'
                        ? 'Encrypted attachment${widget.message.attachmentName != null ? ': ${widget.message.attachmentName}' : ''}\nTap to decrypt.'
                        : widget.message.content,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: Colors.grey),
                  ),
                ],
              )
            else if (widget.message.messageType == 'file')
              _decryptedBytes != null
                  ? _isImageFile(widget.message.attachmentName)
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.memory(
                            _decryptedBytes!,
                            fit: BoxFit.cover,
                            width: MediaQuery.of(context).size.width * 0.65,
                            height: 180,
                            errorBuilder: (_, __, ___) => Container(
                              height: 180,
                              color: Colors.black12,
                              child: const Center(
                                child: Text('Unable to render image', style: TextStyle(color: Colors.white70)),
                              ),
                            ),
                          ),
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.message.attachmentName ?? 'Decrypted file',
                              style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'File size: ${_decryptedBytes!.lengthInBytes} bytes',
                              style: const TextStyle(color: Colors.white70, fontSize: 12),
                            ),
                          ],
                        )
                  : Text(
                      _decryptedText ?? 'Unable to decrypt attachment',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
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
