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
  Stream<List<JAVSMessage>> chatStream(String otherUid) {
    final user = _auth.currentUser;
    if (user == null) return Stream.value([]);
    
    // Sort UIDs to create a consistent Chat ID between two participants
    final uids = [user.uid, otherUid]..sort();
    final chatId = uids.join("_");

    return _db
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => JAVSMessage.fromFirestore(doc))
            .toList());
  }

  Future<void> sendSecureMessage(String recipientUid, String ciphertext) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final uids = [user.uid, recipientUid]..sort();
    final chatId = uids.join("_");

    await _db.collection('chats').doc(chatId).collection('messages').add({
      'senderId': user.uid,
      'content': ciphertext,
      'timestamp': FieldValue.serverTimestamp(),
    });
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

      // Send the encrypted message with the encryption key
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

      final groupRef = await _db.collection('groups').add({
        'name': groupName,
        'participants': allParticipants,
        'createdBy': user.uid,
        'createdAt': FieldValue.serverTimestamp(),
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

    return _db.collection('chats').snapshots().map((snapshot) {
      final chats = <Map<String, dynamic>>[];
      
      for (var doc in snapshot.docs) {
        final chatId = doc.id;
        final participants = chatId.split('_');
        
        if (participants.contains(user.uid)) {
          final otherUid = participants.firstWhere(
            (p) => p != user.uid,
            orElse: () => '',
          );
          
          chats.add({
            'chatId': chatId,
            'otherUid': otherUid,
            'lastMessage': doc['lastMessage'] ?? '',
            'timestamp': doc['timestamp'],
          });
        }
      }
      
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
    return JAVSUser(
      uid: doc.id,
      email: data['email'] ?? '',
      displayName: data['displayName'] ?? 'Agent_${doc.id.substring(0, 4)}',
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
