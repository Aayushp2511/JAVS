import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class FirebaseService {
  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  /// Get Secure Vault Items from Firestore
  Stream<List<VaultItem>> vaultStream() {
    final user = _auth.currentUser;
    if (user == null) return Stream.value([]);
    
    return _db
        .collection('vault')
        .doc(user.uid)
        .collection('items')
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => VaultItem.fromFirestore(doc))
            .toList());
  }

  /// Get Global Contact List (Users who have the app)
  Stream<List<JAVSUser>> contactStream() {
    // Handling possible empty/missing collections gracefully
    return _db.collection('users').snapshots().map((snapshot) {
      if (snapshot.docs.isEmpty) return [];
      return snapshot.docs
          .map((doc) => JAVSUser.fromFirestore(doc))
          .where((u) => u.uid != _auth.currentUser?.uid) // Don't show self
          .toList();
    });
  }

  /// Chat Management
  Stream<List<JAVSMessage>> chatStream(String chatRoomId) {
    final user = _auth.currentUser;
    if (user == null) return Stream.value([]);

    return _db
        .collection('chats')
        .doc(chatRoomId)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => JAVSMessage.fromFirestore(doc))
            .toList());
  }

  Future<void> sendSecureMessage(String chatRoomId, String ciphertext) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final chatDoc = await _db.collection('chats').doc(chatRoomId).get();
    final chatData = chatDoc.data();
    final isGroupChat = chatData?['isGroup'] == true;
    final recipientUid = _getOtherParticipantUid(chatRoomId, user.uid);
    final recipient = recipientUid.isNotEmpty ? await getUserByUid(recipientUid) : null;

    if (!isGroupChat) {
      await _db.collection('chats').doc(chatRoomId).set({
        'participants': [user.uid, if (recipientUid.isNotEmpty) recipientUid],
        'isGroup': false,
        'createdBy': user.uid,
        'updatedAt': FieldValue.serverTimestamp(),
        'lastMessage': ciphertext,
        'lastMessageAt': FieldValue.serverTimestamp(),
        'lastSenderId': user.uid,
        'name': recipient?.displayName ?? recipient?.email ?? recipientUid,
      }, SetOptions(merge: true));
    }

    await _db.collection('chats').doc(chatRoomId).collection('messages').add({
      'senderId': user.uid,
      'recipientId': isGroupChat ? '' : recipientUid,
      'senderEmail': user.email ?? '',
      'recipientEmail': isGroupChat ? '' : (recipient?.email ?? ''),
      'content': ciphertext,
      'timestamp': FieldValue.serverTimestamp(),
      'status': 'sent',
      'messageType': isGroupChat ? 'group' : 'text',
    });
  }

  String _getOtherParticipantUid(String chatRoomId, String currentUserUid) {
    final participants = chatRoomId.split('_');
    if (participants.length != 2) return '';
    return participants.firstWhere((uid) => uid != currentUserUid, orElse: () => '');
  }

  /// Save Encrypted Payload to Vault
  Future<void> saveToVault(String title, String ciphertext) async {
    final user = _auth.currentUser;
    if (user == null) return;

    await _db.collection('vault').doc(user.uid).collection('items').add({
      'title': title,
      'content': ciphertext,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  /// Look up user by email
  Future<JAVSUser?> getUserByEmail(String email) async {
    try {
      final snapshot = await _db
          .collection('users')
          .where('email', isEqualTo: email.toLowerCase())
          .limit(1)
          .get();
      
      if (snapshot.docs.isNotEmpty) {
        return JAVSUser.fromFirestore(snapshot.docs.first);
      }
      return null;
    } catch (e) {
      print('Error looking up user by email: $e');
      return null;
    }
  }

  Future<JAVSUser?> getUserByUid(String uid) async {
    try {
      final doc = await _db.collection('users').doc(uid).get();
      if (!doc.exists) return null;
      return JAVSUser.fromFirestore(doc);
    } catch (e) {
      print('Error looking up user by uid: $e');
      return null;
    }
  }

  /// Send encrypted message to user by email
  Future<bool> sendEncryptedMessageToEmail(
    String email,
    String ciphertext,
    String encryptionKey, {
    String messageType = 'text',
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return false;

      // Look up recipient by email
      final recipient = await getUserByEmail(email);
      if (recipient == null) {
        print('User with email $email not found');
        return false;
      }

      // Create chat room ID (sorted UIDs for consistency)
      final uids = [user.uid, recipient.uid]..sort();
      final chatId = uids.join("_");

      await _db.collection('chats').doc(chatId).set({
        'participants': uids,
        'isGroup': false,
        'createdBy': user.uid,
        'updatedAt': FieldValue.serverTimestamp(),
        'lastMessage': ciphertext,
        'lastMessageAt': FieldValue.serverTimestamp(),
        'lastSenderId': user.uid,
        'name': recipient.displayName,
      }, SetOptions(merge: true));

      await _db.collection('chats').doc(chatId).collection('messages').add({
        'senderId': user.uid,
        'recipientId': recipient.uid,
        'senderEmail': user.email ?? '',
        'recipientEmail': recipient.email,
        'content': ciphertext,
        'encryptionKey': encryptionKey,
        'messageType': messageType,
        'timestamp': FieldValue.serverTimestamp(),
        'status': 'sent',
      });

      return true;
    } catch (e) {
      print('Error sending encrypted message: $e');
      return false;
    }
  }

  /// Create a group chat
  Future<String> createGroupChat(String groupName, List<String> participantUids) async {
    try {
      final user = _auth.currentUser;
      if (user == null) throw Exception('User not authenticated');

      final allParticipants = [user.uid, ...participantUids];

      final groupRef = _db.collection('chats').doc();
      await groupRef.set({
        'name': groupName,
        'participants': allParticipants,
        'isGroup': true,
        'createdBy': user.uid,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'lastMessage': '',
        'lastMessageAt': FieldValue.serverTimestamp(),
      });

      return groupRef.id;
    } catch (e) {
      print('Error creating group: $e');
      rethrow;
    }
  }

  /// Get user's chat conversations
  Stream<List<Map<String, dynamic>>> getUserChats() {
    final user = _auth.currentUser;
    if (user == null) return Stream.value([]);

    return _db
        .collection('chats')
        .where('participants', arrayContains: user.uid)
        .snapshots()
        .asyncMap((snapshot) async {
      final chats = await Future.wait(snapshot.docs.map((doc) async {
        final data = doc.data();
        final participants = List<String>.from(data['participants'] ?? const <String>[]);
        final otherUid = participants.firstWhere(
          (participant) => participant != user.uid,
          orElse: () => '',
        );
        final isGroup = data['isGroup'] == true;
        final rawTimestamp = data['lastMessageAt'] as Timestamp? ?? data['updatedAt'] as Timestamp? ?? data['createdAt'] as Timestamp?;
        final timestamp = rawTimestamp?.toDate() ?? DateTime.fromMillisecondsSinceEpoch(0);

        String displayName;
        String email;
        if (isGroup) {
          displayName = data['name'] as String? ?? 'Group Chat';
          email = '';
        } else {
          final otherUser = otherUid.isNotEmpty ? await getUserByUid(otherUid) : null;
          final fallbackDisplay = otherUid.isNotEmpty ? 'User_${otherUid.substring(0, 4)}' : 'Unknown';
          displayName = otherUser?.displayName.isNotEmpty == true
              ? otherUser!.displayName
              : fallbackDisplay;
          email = otherUser?.email ?? (data['email'] as String? ?? '');
        }

        return {
          'chatId': doc.id,
          'otherUid': otherUid,
          'displayName': displayName,
          'email': email,
          'lastMessage': data['lastMessage'] as String? ?? '',
          'timestamp': timestamp,
          'isGroup': isGroup,
        };
      }));

      chats.sort((a, b) => (b['timestamp'] as DateTime).compareTo(a['timestamp'] as DateTime));

      return chats;
    });
  }

  /// Get all users for suggestions
  Future<List<JAVSUser>> getAllUsers() async {
    try {
      final snapshot = await _db.collection('users').get();
      return snapshot.docs
          .map((doc) => JAVSUser.fromFirestore(doc))
          .where((u) => u.uid != _auth.currentUser?.uid)
          .toList();
    } catch (e) {
      print('Error getting users: $e');
      return [];
    }
  }

  /// Delivery history for Fast Deliver section
  Stream<List<DeliveryHistoryItem>> deliveryHistoryStream() {
    final user = _auth.currentUser;
    if (user == null) return Stream.value([]);

    return _db
        .collectionGroup('messages')
        .where('status', isEqualTo: 'sent')
        .where(
          Filter.or(
            Filter('senderId', isEqualTo: user.uid),
            Filter('recipientId', isEqualTo: user.uid),
          ),
        )
        .snapshots()
        .map((snapshot) {
      final history = snapshot.docs
          .map((doc) => DeliveryHistoryItem.fromFirestore(doc, user.uid))
          .toList();
      history.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return history;
    });
  }
}

class VaultItem {
  final String id;
  final String title;
  final String content;

  VaultItem({required this.id, required this.title, required this.content});

  factory VaultItem.fromFirestore(DocumentSnapshot doc) {
    final Map<String, dynamic> data = doc.data() as Map<String, dynamic>? ?? {};
    return VaultItem(
      id: doc.id,
      title: data['title'] ?? 'Untitled Node',
      content: data['content'] ?? '',
    );
  }
}

class JAVSUser {
  final String uid;
  final String email;
  final String displayName;

  JAVSUser({required this.uid, required this.email, required this.displayName});

  factory JAVSUser.fromFirestore(DocumentSnapshot doc) {
    final Map<String, dynamic> data = doc.data() as Map<String, dynamic>? ?? {};
    final email = (data['email'] as String?) ?? '';
    final fallbackName = email.contains('@')
        ? email.split('@').first
        : 'User_${doc.id.substring(0, 4)}';

    return JAVSUser(
      uid: doc.id,
      email: email,
      displayName: (data['displayName'] as String?)?.trim().isNotEmpty == true
          ? (data['displayName'] as String).trim()
          : fallbackName,
    );
  }
}

class JAVSMessage {
  final String id;
  final String senderId;
  final String content;
  final String? senderName;

  JAVSMessage({required this.id, required this.senderId, required this.content, this.senderName});

  factory JAVSMessage.fromFirestore(DocumentSnapshot doc) {
    final Map<String, dynamic> data = doc.data() as Map<String, dynamic>? ?? {};
    return JAVSMessage(
      id: doc.id,
      senderId: data['senderId'] ?? '',
      content: data['content'] ?? '',
      senderName: data['senderName'],
    );
  }
}

class DeliveryHistoryItem {
  final String id;
  final String email;
  final String type;
  final DateTime timestamp;
  final bool isSentByCurrentUser;

  DeliveryHistoryItem({
    required this.id,
    required this.email,
    required this.type,
    required this.timestamp,
    required this.isSentByCurrentUser,
  });

  factory DeliveryHistoryItem.fromFirestore(
    DocumentSnapshot doc,
    String currentUserUid,
  ) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    final senderId = data['senderId'] as String? ?? '';
    final isSent = senderId == currentUserUid;
    final fallbackTimestamp = DateTime.fromMillisecondsSinceEpoch(0);
    final firestoreTimestamp = data['timestamp'] as Timestamp?;

    return DeliveryHistoryItem(
      id: doc.id,
      email: isSent
          ? (data['recipientEmail'] as String? ?? 'Unknown')
          : (data['senderEmail'] as String? ?? 'Unknown'),
      type: (data['messageType'] as String? ?? 'text').toLowerCase(),
      timestamp: firestoreTimestamp?.toDate() ?? fallbackTimestamp,
      isSentByCurrentUser: isSent,
    );
  }
}

final firebaseServiceProvider = Provider((ref) => FirebaseService());

final vaultStreamProvider = StreamProvider<List<VaultItem>>((ref) {
  return ref.watch(firebaseServiceProvider).vaultStream();
});

final contactStreamProvider = StreamProvider<List<JAVSUser>>((ref) {
  return ref.watch(firebaseServiceProvider).contactStream();
});

final chatStreamProvider = StreamProvider.family<List<JAVSMessage>, String>((ref, otherUid) {
  return ref.watch(firebaseServiceProvider).chatStream(otherUid);
});

final deliveryHistoryStreamProvider = StreamProvider<List<DeliveryHistoryItem>>((ref) {
  return ref.watch(firebaseServiceProvider).deliveryHistoryStream();
});

final userChatsStreamProvider = StreamProvider<List<Map<String, dynamic>>>((ref) {
  return ref.watch(firebaseServiceProvider).getUserChats();
});
