import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:typed_data';

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
          .where((u) => u.uid != _auth.currentUser?.uid && u.email.isNotEmpty) // Don't show self
          .toList();
    });
  }

  /// Chat Management
  Stream<List<JAVSMessage>> chatStream(String chatId) {
    final user = _auth.currentUser;
    if (user == null) return Stream.value([]);
    
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

  Future<void> sendSecureMessage(
    String chatId,
    String ciphertext, {
    String messageType = 'text',
    String? attachmentName,
    String? encryptionKey,
    Uint8List? encryptedBytes,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return;

    // Extract recipient from chatId for notification streams
    final parts = chatId.split('_');
    final recipientUid = parts.firstWhere((id) => id != user.uid, orElse: () => '');

    final chatRef = _db.collection('chats').doc(chatId);
    final messagePayload = {
      'senderId': user.uid,
      'recipientId': recipientUid,
      'senderEmail': user.email ?? '',
      'content': ciphertext,
      'messageType': messageType,
      'timestamp': FieldValue.serverTimestamp(),
      'status': 'sent',
      if (attachmentName != null) 'attachmentName': attachmentName,
      if (encryptionKey != null && encryptionKey.isNotEmpty)
        'encryptionKey': encryptionKey,
      if (encryptedBytes != null) 'contentBytes': Blob(encryptedBytes),
    };

    await chatRef.set({
      'participants': parts,
      'lastMessage': messageType == 'text' ? ciphertext : '[${messageType.toUpperCase()}]',
      'lastMessageType': messageType,
      'lastSenderId': user.uid,
      'timestamp': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await chatRef.collection('messages').add(messagePayload);
  }

  /// Save Encrypted Payload to Vault
  Future<void> saveToVault(
    String title,
    String ciphertext, {
    String payloadType = 'text',
    String? sessionToken,
    String? attachmentName,
    Uint8List? binaryPayload,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return;

    await _db.collection('vault').doc(user.uid).collection('items').add({
      'title': title,
      'content': ciphertext,
      'payloadType': payloadType,
      'sessionToken': sessionToken,
      'attachmentName': attachmentName,
      if (binaryPayload != null) 'binaryContent': Blob(binaryPayload),
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  /// Look up user by email
  Future<JAVSUser?> getUserByEmail(String email) async {
    try {
      final normalized = email.trim().toLowerCase();

      final snapshot = await _db
          .collection('users')
          .where('email', isEqualTo: normalized)
          .limit(1)
          .get();
      
      if (snapshot.docs.isNotEmpty) {
        return JAVSUser.fromFirestore(snapshot.docs.first);
      }

      // Fallback for old records where email may not be normalized.
      final raw = email.trim();
      if (raw != normalized) {
        final rawSnapshot = await _db
            .collection('users')
            .where('email', isEqualTo: raw)
            .limit(1)
            .get();
        if (rawSnapshot.docs.isNotEmpty) {
          return JAVSUser.fromFirestore(rawSnapshot.docs.first);
        }
      }

      // Final fallback: client-side normalization for legacy datasets.
      final broadSnapshot = await _db.collection('users').limit(300).get();
      for (final doc in broadSnapshot.docs) {
        final data = doc.data();
        final docEmail = (data['email'] as String? ?? '').trim().toLowerCase();
        if (docEmail == normalized) {
          return JAVSUser.fromFirestore(doc);
        }
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
    String? attachmentName,
    Uint8List? encryptedBytes,
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
      final chatRef = _db.collection('chats').doc(chatId);

      await chatRef.set({
        'participants': uids,
        'lastMessage': messageType == 'text' ? ciphertext : '[${messageType.toUpperCase()}]',
        'lastMessageType': messageType,
        'lastSenderId': user.uid,
        'timestamp': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // Send the encrypted message with the encryption key
      await chatRef.collection('messages').add({
        'senderId': user.uid,
        'recipientId': recipient.uid,
        'senderEmail': user.email ?? '',
        'recipientEmail': recipient.email,
        'content': ciphertext,
        'encryptionKey': encryptionKey,
        'messageType': messageType,
        if (attachmentName != null) 'attachmentName': attachmentName,
        if (encryptedBytes != null) 'contentBytes': Blob(encryptedBytes),
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
        final data = doc.data();
        final participants = chatId.split('_');
        
        if (participants.contains(user.uid)) {
          final otherUid = participants.firstWhere(
            (p) => p != user.uid,
            orElse: () => '',
          );
          
          chats.add({
            'chatId': chatId,
            'otherUid': otherUid,
            'lastMessage': data['lastMessage'] ?? '',
            'timestamp': data['timestamp'],
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
  Stream<List<DeliveryHistoryItem>> deliveryHistoryStream() async* {
    final user = _auth.currentUser;
    if (user == null) {
      yield <DeliveryHistoryItem>[];
      return;
    }

    try {
      await for (final chatSnapshot in _db
          .collection('chats')
          .where('participants', arrayContains: user.uid)
          .snapshots()) {
        if (chatSnapshot.docs.isEmpty) {
          yield <DeliveryHistoryItem>[];
          continue;
        }

        final messageSnapshots = await Future.wait(
          chatSnapshot.docs.map(
            (chatDoc) => chatDoc.reference
                .collection('messages')
                .where('status', isEqualTo: 'sent')
                .get(),
          ),
        );

        final history = <DeliveryHistoryItem>[];
        for (final messageSnapshot in messageSnapshots) {
          for (final doc in messageSnapshot.docs) {
            final data = doc.data();
            final senderId = data['senderId'] as String? ?? '';
            final recipientId = data['recipientId'] as String? ?? '';
            if (senderId == user.uid || recipientId == user.uid) {
              history.add(DeliveryHistoryItem.fromFirestore(doc, user.uid));
            }
          }
        }

        history.sort((a, b) => b.timestamp.compareTo(a.timestamp));
        yield history;
      }
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        yield <DeliveryHistoryItem>[];
        return;
      }
      rethrow;
    }
  }
}

class VaultItem {
  final String id;
  final String title;
  final String content;
  final String payloadType;
  final String? sessionToken;
  final String? attachmentName;
  final Uint8List? binaryContent;

  VaultItem({
    required this.id,
    required this.title,
    required this.content,
    required this.payloadType,
    this.sessionToken,
    this.attachmentName,
    this.binaryContent,
  });

  factory VaultItem.fromFirestore(DocumentSnapshot doc) {
    final Map<String, dynamic> data = doc.data() as Map<String, dynamic>? ?? {};
    return VaultItem(
      id: doc.id,
      title: data['title'] ?? 'Untitled Node',
      content: data['content'] ?? '',
      payloadType: (data['payloadType'] as String? ?? 'text').toLowerCase(),
      sessionToken: data['sessionToken'] as String?,
      attachmentName: data['attachmentName'] as String?,
      binaryContent: (data['binaryContent'] as Blob?)?.bytes,
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
  final Uint8List? contentBytes;
  final String messageType;
  final String? attachmentName;
  final String? encryptionKey;
  final String? senderName;

  JAVSMessage({
    required this.id,
    required this.senderId,
    required this.content,
    this.contentBytes,
    this.messageType = 'text',
    this.attachmentName,
    this.encryptionKey,
    this.senderName,
  });

  factory JAVSMessage.fromFirestore(DocumentSnapshot doc) {
    final Map<String, dynamic> data = doc.data() as Map<String, dynamic>? ?? {};
    return JAVSMessage(
      id: doc.id,
      senderId: data['senderId'] ?? '',
      content: data['content'] ?? '',
      contentBytes: (data['contentBytes'] as Blob?)?.bytes,
      messageType: (data['messageType'] as String? ?? 'text').toLowerCase(),
      attachmentName: data['attachmentName'] as String?,
      encryptionKey: data['encryptionKey'] as String?,
      senderName: data['senderName'] as String?,
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

final chatStreamProvider = StreamProvider.family<List<JAVSMessage>, String>((ref, chatId) {
  return ref.watch(firebaseServiceProvider).chatStream(chatId);
});

final deliveryHistoryStreamProvider = StreamProvider<List<DeliveryHistoryItem>>((ref) {
  return ref.watch(firebaseServiceProvider).deliveryHistoryStream();
});
