import 'dart:math';

class EncryptedMessage {
  final List<int> cipher;
  final int seed;

  EncryptedMessage({
    required this.cipher,
    required this.seed,
  });

  Map<String, dynamic> toMap() {
    return {
      'cipher': cipher,
      'seed': seed,
    };
  }

  factory EncryptedMessage.fromMap(Map<String, dynamic> map) {
    return EncryptedMessage(
      cipher: List<int>.from(map['cipher']),
      seed: map['seed'] as int,
    );
  }
}

class EncryptionService {
  List<int> sbox = List<int>.filled(256, 0);
  List<int> invSbox = List<int>.filled(256, 0);

  void _generateSbox(int seed) {
    // We use a predefined sequence or Dart's seeded Random to ensure identical shuffling
    var rng = Random(seed);
    
    for (int i = 0; i < 256; i++) {
      sbox[i] = i;
    }

    for (int i = 255; i > 0; i--) {
      int j = rng.nextInt(i + 1);
      int temp = sbox[i];
      sbox[i] = sbox[j];
      sbox[j] = temp;
    }

    for (int i = 0; i < 256; i++) {
      invSbox[sbox[i]] = i;
    }
  }

  int _generateSeed(String msg) {
    int sum = 0;
    for (int i = 0; i < msg.length; i++) {
      sum += msg.codeUnitAt(i);
    }

    var rng = Random();
    int mcs = rng.nextInt(100);
    int randomVal = rng.nextInt(256);

    int seed = (sum + mcs * 13 + randomVal) % 256;
    return seed;
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

  EncryptedMessage encrypt(String message) {
    if (message.isEmpty) {
      return EncryptedMessage(cipher: [], seed: 0);
    }

    int seed = _generateSeed(message);
    _generateSbox(seed);

    int len = message.length;
    List<int> key = _generateKey(len, seed);
    List<int> cipher = List<int>.filled(len, 0);

    int prev = seed;

    for (int i = 0; i < len; i++) {
      int charCode = message.codeUnitAt(i);
      int x = charCode ^ key[i];
      int z = sbox[x];
      int omega = (i * seed + 3 * i * i) % 256;
      int y = (z + omega) % 256;
      cipher[i] = y ^ prev;
      prev = cipher[i];
    }

    return EncryptedMessage(cipher: cipher, seed: seed);
  }

  String decrypt(EncryptedMessage encryptedMessage) {
    if (encryptedMessage.cipher.isEmpty) {
      return "";
    }

    int seed = encryptedMessage.seed;
    List<int> cipher = encryptedMessage.cipher;
    int len = cipher.length;

    _generateSbox(seed);
    List<int> key = _generateKey(len, seed);
    
    List<int> decryptedCodes = List<int>.filled(len, 0);
    int prev = seed;

    for (int i = 0; i < len; i++) {
      int y = cipher[i] ^ prev;
      int omega = (i * seed + 3 * i * i) % 256;
      // Added +256 to ensure positive modulo as in C
      int z = ((y - omega) % 256 + 256) % 256;
      int x = invSbox[z];
      decryptedCodes[i] = x ^ key[i];
      prev = cipher[i];
    }

    return String.fromCharCodes(decryptedCodes);
  }
}
