import 'dart:async';
import 'dart:typed_data';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import '../../core/crypto/idmc_engine.dart';
import '../../core/ml/igmh_synchronizer.dart';
import '../../core/mtd/react_module.dart';
import '../../services/firebase_service.dart';
import '../theme/cyber_theme.dart';
import '../chat/chat_screen.dart';

import '../../widgets/graph_visualizer.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  int _currentIndex = 0;
  final _textController = TextEditingController();
  final _sessionController = TextEditingController(text: "JAVS-SIGMA-9");
  final _emailController = TextEditingController();
  final _messageController = TextEditingController();
  final _keyController = TextEditingController();
  String _output = "";
  bool _isProcessing = false;
  bool _isDecryptMode = false;
  bool _isSendingMessage = false;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  int _unreadCount = 0;
  StreamSubscription? _chatSubscription;
  PlatformFile? _selectedFile;
  String? _fileContent;

  void _runIDMC() async {
    String inputText = _textController.text;
    
    // If file is selected, use file content instead of text input
    if (_selectedFile != null && _fileContent != null) {
      inputText = _fileContent!;
    }
    
    if (inputText.isEmpty) return;

    setState(() => _isProcessing = true);
    await Future.delayed(const Duration(milliseconds: 800));

    final seed = IGMHSynchronizer.generate512BitSeed(_sessionController.text);
    
    String result;
    if (_isDecryptMode) {
      result = IDMCEngine.decryptText(inputText, seed);
    } else {
      result = IDMCEngine.encryptText(inputText, seed);
      // Trigger MTD Audit only on encryption
      ref.read(reactProvider.notifier).audit(Uint8List.fromList(result.codeUnits));
    }
    
    setState(() {
      _output = result;
      _isProcessing = false;
    });
  }

  Future<void> _pickFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'doc', 'docx', 'txt', 'jpg', 'jpeg', 'png', 'gif', 'bmp'],
        allowMultiple: false,
      );

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        
        setState(() {
          _selectedFile = file;
        });

        // Read file content based on type
        if (file.path != null) {
          final bytes = await File(file.path!).readAsBytes();
          
          // For text-based files, read as string
          if (file.extension == 'txt' || file.extension == 'doc' || file.extension == 'docx') {
            _fileContent = String.fromCharCodes(bytes);
          } else {
            // For binary files (images, pdfs), convert to base64
            _fileContent = base64Encode(bytes);
          }
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('File loaded: ${file.name}'),
              backgroundColor: CyberTheme.primaryNeon,
            ),
          );
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error picking file: $e'),
          backgroundColor: CyberTheme.errorNeon,
        ),
      );
    }
  }

  void _saveToVault() async {
    if (_output.isEmpty) return;
    await ref.read(firebaseServiceProvider).saveToVault(
      "Secure_Payload_${DateTime.now().millisecondsSinceEpoch}.idmc",
      _output
    );
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Cloud Node Synced Successfully")),
    );
  }

  void _sendEncryptedMessage() async {
    final email = _emailController.text.trim();
    final message = _messageController.text.trim();
    final key = _keyController.text.trim();

    if (email.isEmpty || message.isEmpty || key.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please fill in all fields: email, message, and encryption key")),
      );
      return;
    }

    // Basic email validation
    if (!RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(email)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter a valid email address")),
      );
      return;
    }

    setState(() => _isSendingMessage = true);

    try {
      // Encrypt the message using the provided key
      final seed = IGMHSynchronizer.generate512BitSeed(key);
      final encryptedMessage = IDMCEngine.encryptText(message, seed);

      // Send the encrypted message to the user by email
      final success = await ref.read(firebaseServiceProvider).sendEncryptedMessageToEmail(
        email,
        encryptedMessage,
        key,
      );

      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Encrypted message sent successfully!")),
        );
        // Clear the input fields
        _emailController.clear();
        _messageController.clear();
        _keyController.clear();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Failed to send message. User may not exist.")),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error sending message: $e")),
      );
    } finally {
      setState(() => _isSendingMessage = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _listenForMessages();
  }

  @override
  void dispose() {
    _chatSubscription?.cancel();
    super.dispose();
  }

  void _listenForMessages() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    _chatSubscription = FirebaseFirestore.instance
        .collection('chats')
        .snapshots()
        .listen((snapshot) {
      int unread = 0;
      
      for (var doc in snapshot.docs) {
        final chatId = doc.id;
        final participants = chatId.split('_');
        
        if (participants.contains(user.uid)) {
          final messagesRef = doc.reference.collection('messages');
          messagesRef
              .where('recipientId', isEqualTo: user.uid)
              .where('status', isEqualTo: 'sent')
              .snapshots()
              .listen((msgSnapshot) {
            unread += msgSnapshot.docs.length;
            
            if (msgSnapshot.docs.isNotEmpty && mounted) {
              setState(() => _unreadCount = unread);
              
              // Show notification for new message
              final latestMsg = msgSnapshot.docs.last;
              final senderId = latestMsg['senderId'];
              
              if (senderId != user.uid) {
                _showNotification(latestMsg['content'] ?? 'New message');
              }
            }
          });
        }
      }
    });
  }

  void _showNotification(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.notifications, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'New message: $message',
                style: const TextStyle(fontSize: 12),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        backgroundColor: CyberTheme.primaryNeon,
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: 'View',
          textColor: Colors.black,
          onPressed: () {
            setState(() => _currentIndex = 2); // Navigate to Agents tab
          },
        ),
      ),
    );
  }

  void _showNotifications() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: CyberTheme.surface,
        title: const Text('Notifications'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_unreadCount > 0)
                Text(
                  'You have $_unreadCount unread message(s)',
                  style: const TextStyle(fontSize: 14),
                )
              else
                const Text('No new notifications'),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  setState(() {
                    _currentIndex = 2; // Go to Agents tab
                    _unreadCount = 0; // Reset count
                  });
                },
                child: const Text('View Messages'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mtd = ref.watch(reactProvider);
    final user = FirebaseAuth.instance.currentUser;
    
    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        backgroundColor: CyberTheme.background,
        elevation: 0,
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu, color: CyberTheme.primaryNeon),
            onPressed: () => _scaffoldKey.currentState?.openDrawer(),
          ),
        ),
        title: Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: CyberTheme.primaryNeon.withOpacity(0.2),
              child: Text(
                user?.email?.substring(0, 1).toUpperCase() ?? 'U',
                style: const TextStyle(
                  color: CyberTheme.primaryNeon,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'JAVS Secure Vault',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    user?.email ?? 'Not set',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Colors.grey,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          Stack(
            children: [
              IconButton(
                icon: const Icon(Icons.notifications, color: Colors.grey),
                onPressed: _showNotifications,
              ),
              if (_unreadCount > 0)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 16,
                      minHeight: 16,
                    ),
                    child: Text(
                      _unreadCount > 99 ? '99+' : '$_unreadCount',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.grey),
            onPressed: () => FirebaseAuth.instance.signOut(),
          ),
        ],
      ),
      drawer: _buildSideNavigation(user),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (val) => setState(() => _currentIndex = val),
        backgroundColor: CyberTheme.background,
        selectedItemColor: CyberTheme.primaryNeon,
        unselectedItemColor: Colors.white24,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.security), label: "IDMC"),
          BottomNavigationBarItem(icon: Icon(Icons.storage), label: "Vault"),
          BottomNavigationBarItem(icon: Icon(Icons.people), label: "Agents"),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.topRight,
            radius: 1.5,
            colors: [CyberTheme.primaryNeon.withOpacity(0.05), CyberTheme.background],
          ),
        ),
        child: SafeArea(
          child: IndexedStack(
            index: _currentIndex,
            children: [
              _buildCryptoTab(mtd),
              _buildVaultTab(),
              _buildAgentsTab(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSideNavigation(User? user) {
    return Drawer(
      backgroundColor: CyberTheme.background,
      child: Column(
        children: [
          UserAccountsDrawerHeader(
            decoration: const BoxDecoration(
              color: CyberTheme.surface,
            ),
            accountName: Text(
              user?.email ?? 'Not set',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            accountEmail: Text(
              user?.email ?? 'Not set',
              style: const TextStyle(fontSize: 12),
            ),
            currentAccountPicture: CircleAvatar(
              backgroundColor: CyberTheme.primaryNeon.withOpacity(0.2),
              child: Text(
                user?.email?.substring(0, 1).toUpperCase() ?? 'U',
                style: const TextStyle(
                  color: CyberTheme.primaryNeon,
                  fontWeight: FontWeight.bold,
                  fontSize: 24,
                ),
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.home, color: CyberTheme.primaryNeon),
            title: const Text('Home'),
            onTap: () {
              Navigator.pop(context);
              setState(() => _currentIndex = 0);
            },
          ),
          ListTile(
            leading: const Icon(Icons.analytics, color: CyberTheme.primaryNeon),
            title: const Text('Analytics'),
            onTap: () {
              Navigator.pop(context);
              _showAnalytics();
            },
          ),
          ListTile(
            leading: const Icon(Icons.person, color: CyberTheme.primaryNeon),
            title: const Text('Profile'),
            onTap: () {
              Navigator.pop(context);
              _showProfile();
            },
          ),
          ListTile(
            leading: const Icon(Icons.settings, color: CyberTheme.primaryNeon),
            title: const Text('Settings'),
            onTap: () {
              Navigator.pop(context);
              _showSettings();
            },
          ),
          const Spacer(),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text('Logout', style: TextStyle(color: Colors.red)),
            onTap: () {
              Navigator.pop(context);
              FirebaseAuth.instance.signOut();
            },
          ),
        ],
      ),
    );
  }

  void _showAnalytics() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: CyberTheme.surface,
        title: const Text('Analytics'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Total Messages: 12'),
            SizedBox(height: 8),
            Text('Vault Items: 5'),
            SizedBox(height: 8),
            Text('Active Contacts: 8'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showProfile() {
    final user = FirebaseAuth.instance.currentUser;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: CyberTheme.surface,
        title: const Text('Profile'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 40,
              backgroundColor: CyberTheme.primaryNeon.withOpacity(0.2),
              child: Text(
                user?.email?.substring(0, 1).toUpperCase() ?? 'U',
                style: const TextStyle(
                  color: CyberTheme.primaryNeon,
                  fontWeight: FontWeight.bold,
                  fontSize: 32,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('Email: ${user?.email ?? 'N/A'}'),
            const SizedBox(height: 8),
            Text('User ID: ${user?.uid ?? 'N/A'}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showSettings() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: CyberTheme.surface,
        title: const Text('Settings'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Notifications: Enabled'),
            SizedBox(height: 8),
            Text('Encryption: IDMC Engine'),
            SizedBox(height: 8),
            Text('Storage: Cloud Vault'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildCryptoTab(REACTState mtd) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader("IDMC.ENGINE"),
          const SizedBox(height: 24),
          _buildMTDStatus(mtd),
          const SizedBox(height: 24),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  Row(
                    children: [
                      _modeToggle("ENCRYPT", !_isDecryptMode, () => setState(() => _isDecryptMode = false)),
                      const SizedBox(width: 12),
                      _modeToggle("DECRYPT", _isDecryptMode, () => setState(() => _isDecryptMode = true)),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _buildInputCard(),
                  const SizedBox(height: 20),
                  GraphVisualizer(isActive: _isProcessing || _output.isNotEmpty),
                  const SizedBox(height: 24),
                  _buildActionCenter(),
                  if (_output.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    _buildOutputCard(),
                  ]
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _modeToggle(String label, bool active, VoidCallback onTap) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: active ? CyberTheme.primaryNeon.withOpacity(0.1) : CyberTheme.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: active ? CyberTheme.primaryNeon : Colors.transparent),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: active ? CyberTheme.primaryNeon : Colors.grey,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVaultTab() {
    final vaultAsync = ref.watch(vaultStreamProvider);
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader("CLOUD.VAULT"),
          const SizedBox(height: 24),
          // Send Encrypted Message Section
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: CyberTheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: CyberTheme.primaryNeon.withOpacity(0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "SEND ENCRYPTED MESSAGE",
                  style: TextStyle(
                    color: CyberTheme.primaryNeon,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _emailController,
                  decoration: const InputDecoration(
                    labelText: "RECIPIENT EMAIL",
                    hintText: "Enter recipient's email address",
                    prefixIcon: Icon(Icons.email, color: CyberTheme.primaryNeon),
                  ),
                  keyboardType: TextInputType.emailAddress,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _messageController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: "PLAINTEXT MESSAGE",
                    hintText: "Enter message to encrypt and send",
                    prefixIcon: Icon(Icons.message, color: CyberTheme.primaryNeon),
                  ),
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _keyController,
                  decoration: const InputDecoration(
                    labelText: "ENCRYPTION KEY",
                    hintText: "Enter encryption key",
                    prefixIcon: Icon(Icons.key, color: CyberTheme.primaryNeon),
                  ),
                  obscureText: true,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _isSendingMessage ? null : _sendEncryptedMessage,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: CyberTheme.primaryNeon,
                    minimumSize: const Size(double.infinity, 48),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _isSendingMessage
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.black),
                          ),
                        )
                      : const Text(
                          "SEND ENCRYPTED MESSAGE",
                          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
                        ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          // Existing vault items section
          Expanded(
            child: vaultAsync.when(
              data: (items) => items.isEmpty 
                ? const Center(child: Text("Vault Empty. Sync nodes to start."))
                : ListView.builder(
                    itemCount: items.length,
                    itemBuilder: (context, index) => _buildVaultItem(items[index]),
                  ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, r) => Center(child: Text("Sync Error: $e")),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAgentsTab() {
    final agentsAsync = ref.watch(contactStreamProvider);
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader("MESSAGES"),
          const SizedBox(height: 16),
          // Add User and Create Group buttons
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _showAddUserDialog,
                  icon: const Icon(Icons.person_add, size: 18),
                  label: const Text('Add User'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: CyberTheme.primaryNeon,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _showCreateGroupDialog,
                  icon: const Icon(Icons.group_add, size: 18),
                  label: const Text('Create Group'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: CyberTheme.primaryNeon,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const Text(
            'RECENT CHATS',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: CyberTheme.primaryNeon,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 12),
          // Chat list
          Expanded(
            child: agentsAsync.when(
              data: (agents) {
                if (agents.isEmpty) {
                  return const Center(
                    child: Text(
                      "No chats yet.\nAdd a user to start messaging.",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  );
                }
                return ListView.builder(
                  itemCount: agents.length,
                  itemBuilder: (context, index) {
                    final agent = agents[index];
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: CyberTheme.primaryNeon.withOpacity(0.2),
                        child: Text(
                          agent.displayName.isNotEmpty 
                              ? agent.displayName.substring(0, 1).toUpperCase()
                              : 'U',
                          style: const TextStyle(
                            color: CyberTheme.primaryNeon,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      title: Text(agent.displayName),
                      subtitle: Text(
                        agent.email,
                        style: const TextStyle(fontSize: 10, color: Colors.grey),
                      ),
                      trailing: const Icon(Icons.chevron_right, color: CyberTheme.primaryNeon),
                      onTap: () {
                        final currentUserId = FirebaseAuth.instance.currentUser?.uid;
                        if (currentUserId == null) return;
                        
                        final uids = [currentUserId, agent.uid]..sort();
                        final chatRoomId = uids.join('_');
                        
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => ChatScreen(
                              chatRoomId: chatRoomId,
                              chatName: agent.displayName,
                            ),
                          ),
                        );
                      },
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, r) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline, size: 48, color: Colors.red),
                      const SizedBox(height: 16),
                      Text(
                        "Unable to load users",
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "Please check your internet connection",
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showAddUserDialog() {
    final emailController = TextEditingController();
    final usernameController = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: CyberTheme.surface,
        title: const Text('Add User'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: emailController,
              decoration: const InputDecoration(
                labelText: 'Email Address',
                hintText: 'Enter user email',
                prefixIcon: Icon(Icons.email, size: 20),
              ),
            ),
            const SizedBox(height: 12),
            const Text('OR', style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 12),
            TextField(
              controller: usernameController,
              decoration: const InputDecoration(
                labelText: 'Username',
                hintText: 'Enter username',
                prefixIcon: Icon(Icons.person, size: 20),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final email = emailController.text.trim();
              final username = usernameController.text.trim();
              
              if (email.isEmpty && username.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please enter email or username')),
                );
                return;
              }
              
              // Try to find user by email first
              JAVSUser? user;
              if (email.isNotEmpty) {
                user = await ref.read(firebaseServiceProvider).getUserByEmail(email);
              }
              
              if (user != null) {
                Navigator.pop(context);
                // Navigate to chat with this user
                final currentUserId = FirebaseAuth.instance.currentUser?.uid;
                if (currentUserId == null) return;
                
                final uids = [currentUserId, user!.uid]..sort();
                final chatRoomId = uids.join('_');
                
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ChatScreen(
                      chatRoomId: chatRoomId,
                      chatName: user!.displayName,
                    ),
                  ),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('User not found')),
                );
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _showCreateGroupDialog() async {
    final groupNameController = TextEditingController();
    final selectedUsers = <String>[];
    final allUsers = await ref.read(firebaseServiceProvider).getAllUsers();
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: CyberTheme.surface,
          title: const Text('Create Group'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: groupNameController,
                  decoration: const InputDecoration(
                    labelText: 'Group Name',
                    hintText: 'Enter group name',
                    prefixIcon: Icon(Icons.group, size: 20),
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Select Members:', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                SizedBox(
                  height: 200,
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: allUsers.length,
                    itemBuilder: (context, index) {
                      final user = allUsers[index];
                      final isSelected = selectedUsers.contains(user.uid);
                      
                      return CheckboxListTile(
                        title: Text(user.displayName),
                        subtitle: Text(user.email),
                        value: isSelected,
                        onChanged: (value) {
                          setDialogState(() {
                            if (value == true) {
                              selectedUsers.add(user.uid);
                            } else {
                              selectedUsers.remove(user.uid);
                            }
                          });
                        },
                        activeColor: CyberTheme.primaryNeon,
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (groupNameController.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please enter a group name')),
                  );
                  return;
                }
                
                if (selectedUsers.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please select at least one member')),
                  );
                  return;
                }
                
                try {
                  final groupId = await ref.read(firebaseServiceProvider).createGroupChat(
                    groupNameController.text.trim(),
                    selectedUsers,
                  );
                  
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Group created successfully!')),
                  );
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error creating group: $e')),
                  );
                }
              },
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(String title) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.displayLarge?.copyWith(fontSize: 28),
            ),
            Text(
              "Autonomous Security Perimeter",
              style: TextStyle(color: Colors.white.withOpacity(0.5), letterSpacing: 1.2, fontSize: 10),
            ),
          ],
        ),
        IconButton(
          icon: const Icon(Icons.logout, color: Colors.grey, size: 18),
          onPressed: () => FirebaseAuth.instance.signOut(),
        ),
      ],
    );
  }

  Widget _buildMTDStatus(REACTState mtd) {
    return Container(
      height: 110,
      width: double.infinity,
      decoration: BoxDecoration(
        color: CyberTheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: CyberTheme.primaryNeon.withOpacity(0.3), width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 60,
                  height: 60,
                  child: CircularProgressIndicator(
                    value: mtd.currentEntropy / 8.0,
                    color: mtd.isAuditPassed ? CyberTheme.primaryNeon : CyberTheme.errorNeon,
                    strokeWidth: 3,
                  ),
                ),
                Text("${mtd.currentEntropy.toStringAsFixed(1)}", 
                  style: TextStyle(fontWeight: FontWeight.bold, color: mtd.isAuditPassed ? Colors.white : CyberTheme.errorNeon)),
              ],
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("MTD SECURITY AUDIT", style: TextStyle(fontSize: 10, color: CyberTheme.primaryNeon, letterSpacing: 1.5)),
                  const SizedBox(height: 4),
                  Text(mtd.systemStatus.toUpperCase(), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 2),
                  Text(
                    "Rotates keys automatically if entropy < 7.5",
                    style: TextStyle(fontSize: 9, color: Colors.white.withOpacity(0.4)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputCard() {
    return Column(
      children: [
        TextField(
          controller: _sessionController,
          decoration: const InputDecoration(labelText: "IGMH SESSION TOKEN"),
          style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
        ),
        const SizedBox(height: 12),
        // File attachment section
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: CyberTheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: CyberTheme.primaryNeon.withOpacity(0.3)),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  const Icon(Icons.attach_file, color: CyberTheme.primaryNeon, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _selectedFile != null 
                          ? 'Attached: ${_selectedFile!.name}'
                          : 'Attach PDF, Document, or Image',
                      style: TextStyle(
                        fontSize: 12,
                        color: _selectedFile != null 
                            ? CyberTheme.primaryNeon 
                            : Colors.grey,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      _selectedFile != null ? Icons.check_circle : Icons.upload_file,
                      color: CyberTheme.primaryNeon,
                      size: 20,
                    ),
                    onPressed: _pickFile,
                  ),
                  if (_selectedFile != null)
                    IconButton(
                      icon: const Icon(Icons.clear, color: Colors.red, size: 20),
                      onPressed: () {
                        setState(() {
                          _selectedFile = null;
                          _fileContent = null;
                        });
                      },
                    ),
                ],
              ),
              if (_selectedFile != null) ...[
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: 1.0,
                  backgroundColor: Colors.grey[800],
                  valueColor: const AlwaysStoppedAnimation<Color>(CyberTheme.primaryNeon),
                ),
                const SizedBox(height: 4),
                Text(
                  'Size: ${(_selectedFile!.size / 1024).toStringAsFixed(2)} KB',
                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _textController,
          maxLines: 4,
          decoration: InputDecoration(
            labelText: _isDecryptMode ? "CIPHERTEXT" : "PLAINTEXT",
            hintText: _selectedFile != null 
                ? "Or enter text manually (file will be used)"
                : "Enter payload or attach file...",
          ),
        ),
      ],
    );
  }

  Widget _buildActionCenter() {
    return ElevatedButton(
      onPressed: _runIDMC,
      style: ElevatedButton.styleFrom(
        backgroundColor: CyberTheme.primaryNeon,
        minimumSize: const Size(double.infinity, 56),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Text(
        _isDecryptMode ? "RECONSTRUCT DATA" : "SYNTHESIZE NODES",
        style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildOutputCard() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: CyberTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_isDecryptMode ? "RECONSTRUCTED" : "SYNTHESIZED", style: const TextStyle(fontSize: 10)),
                Row(
                  children: [
                    IconButton(icon: const Icon(Icons.copy, size: 16), onPressed: () => Clipboard.setData(ClipboardData(text: _output))),
                    if (!_isDecryptMode) IconButton(icon: const Icon(Icons.cloud_upload_outlined, size: 16), onPressed: _saveToVault),
                  ],
                ),
              ],
            ),
            const Divider(),
            SelectableText(_output, style: const TextStyle(fontFamily: 'monospace', fontSize: 14)),
          ],
        ),
      ),
    );
  }

  Widget _buildVaultItem(VaultItem item) {
    return ListTile(
      leading: const Icon(Icons.all_inclusive, color: CyberTheme.primaryNeon),
      title: Text(item.title, style: const TextStyle(fontSize: 14)),
      subtitle: Text("Size: ${item.content.length} bytes", style: const TextStyle(fontSize: 10)),
      trailing: const Icon(Icons.download, size: 18),
      onTap: () {
        setState(() {
          _isDecryptMode = true;
          _textController.text = item.content;
          _currentIndex = 0;
        });
      },
    );
  }
}
