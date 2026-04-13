import 'dart:math';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';

class EncryptedMessage {
  // cipher is Base64 encoded string of the encrypted bytes
  final String cipher;
  final int seed;

  EncryptedMessage({
    required this.cipher,
    required this.seed,
  });

  Map<String, dynamic> toMap() {
    return {'cipher': cipher, 'seed': seed};
  }

  factory EncryptedMessage.fromMap(Map<String, dynamic> map) {
    final dynamic c = map['cipher'];
    String base64Cipher;
    if (c is String) {
      base64Cipher = c;
    } else if (c is List) {
      base64Cipher = base64Encode(List<int>.from(c));
    } else {
      base64Cipher = '';
    }

    return EncryptedMessage(cipher: base64Cipher, seed: map['seed'] as int);
  }
}

class EncryptionService {
  List<int> sbox = List<int>.filled(256, 0);
  List<int> invSbox = List<int>.filled(256, 0);

  void _generateSbox(int seed) {
    var rng = Random(seed);
    for (int i = 0; i < 256; i++) sbox[i] = i;
    for (int i = 255; i > 0; i--) {
      int j = rng.nextInt(i + 1);
      int temp = sbox[i];
      sbox[i] = sbox[j];
      sbox[j] = temp;
    }
    for (int i = 0; i < 256; i++) invSbox[sbox[i]] = i;
  }

  int _generateSeedFromString(String msg) {
    int sum = 0;
    for (int i = 0; i < msg.length; i++) sum += msg.codeUnitAt(i);
    var rng = Random();
    int mcs = rng.nextInt(100);
    int randomVal = rng.nextInt(256);
    return (sum + mcs * 13 + randomVal) % 256;
  }

  List<int> _generateKey(int len, int seed) {
    List<int> key = List<int>.filled(len, 0);
    int current = seed;
    for (int i = 0; i < len; i++) {
      current = (current * 131 + seed + i) % 256;
      key[i] = current ^ (i * 7);
    }
    return key;
  }

  // Encrypt raw bytes: compress -> encrypt -> base64
  EncryptedMessage encryptBytes(Uint8List data, {int? seed}) {
    if (data.isEmpty) return EncryptedMessage(cipher: '', seed: 0);

    final int usedSeed = seed ?? Random().nextInt(256);
    _generateSbox(usedSeed);

    // compress
    final List<int> compressed = gzip.encode(data);
    final int len = compressed.length;
    final List<int> key = _generateKey(len, usedSeed);
    final List<int> cipher = List<int>.filled(len, 0);

    int prev = usedSeed;
    for (int i = 0; i < len; i++) {
      int b = compressed[i];
      int x = b ^ key[i];
      int z = sbox[x];
      int omega = (i * usedSeed + 3 * i * i) % 256;
      int y = (z + omega) % 256;
      cipher[i] = y ^ prev;
      prev = cipher[i];
    }

    return EncryptedMessage(cipher: base64Encode(cipher), seed: usedSeed);
  }

  // Decrypt to raw bytes: base64 -> decrypt -> decompress
  Uint8List decryptToBytes(EncryptedMessage encrypted) {
    if (encrypted.cipher.isEmpty) return Uint8List(0);

    final List<int> cipher = base64Decode(encrypted.cipher);
    final int len = cipher.length;
    final int seed = encrypted.seed;

    _generateSbox(seed);
    final List<int> key = _generateKey(len, seed);

    final List<int> decrypted = List<int>.filled(len, 0);
    int prev = seed;

    for (int i = 0; i < len; i++) {
      int y = cipher[i] ^ prev;
      int omega = (i * seed + 3 * i * i) % 256;
      int z = ((y - omega) % 256 + 256) % 256;
      int x = invSbox[z];
      decrypted[i] = x ^ key[i];
      prev = cipher[i];
    }

    // decompress
    final List<int> decompressed = gzip.decode(decrypted);
    return Uint8List.fromList(decompressed);
  }

  // Convenience: encrypt a UTF-8 String
  EncryptedMessage encrypt(String message) {
    if (message.isEmpty) return EncryptedMessage(cipher: '', seed: 0);
    final bytes = utf8.encode(message);
    return encryptBytes(Uint8List.fromList(bytes));
  }

  // Convenience: decrypt to String
  String decrypt(EncryptedMessage encryptedMessage) {
    final bytes = decryptToBytes(encryptedMessage);
    if (bytes.isEmpty) return '';
    return utf8.decode(bytes);
  }
}
