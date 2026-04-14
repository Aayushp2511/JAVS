import 'dart:convert';
import 'dart:typed_data';

/// JAVS: IDMC Engine (Universal Unicode Edition)
/// Updated for multi-language support (Hindi, Arabic, etc.) via UTF-8 processing.
class IDMCEngine {
  static const int modBytes = 256;

  /// Centipede Graph Omega Labeling: floor(i/2)
  static int _calculateVL(int index) {
    return index ~/ 2;
  }

  /// Universal Text Encryption (Supports all languages)
  /// Converts string to UTF-8 bytes, encrypts bytes, then converts back to Base64 (Safe for transmission)
  static String encryptText(String plaintext, List<int> seed) {
    if (plaintext.isEmpty) return "";
    
    // 1. Convert to bytes (UTF-8)
    final bytes = utf8.encode(plaintext);
    
    // 2. Encrypt bytes using IDMC algorithm
    final result = Uint8List(bytes.length);
    for (int i = 0; i < bytes.length; i++) {
      final vl = _calculateVL(seed[i % seed.length]);
      result[i] = (bytes[i] - vl) % modBytes;
    }
    
    // 3. Return Base64 for safe "Aesthetic" transmission
    return base64.encode(result);
  }

  /// Universal Text Decryption
  static String decryptText(String ciphertext, List<int> seed) {
    if (ciphertext.isEmpty) return "";
    
    try {
      // Clean the ciphertext - remove whitespace and newlines
      String cleaned = ciphertext.trim();
      cleaned = cleaned.replaceAll('\n', '');
      cleaned = cleaned.replaceAll('\r', '');
      cleaned = cleaned.replaceAll(' ', '');
      
      // Fix Base64 padding
      while (cleaned.length % 4 != 0) {
        cleaned += '=';
      }
      
      // 1. Decode Base64
      final bytes = base64.decode(cleaned);
      
      // 2. Decrypt bytes
      final result = Uint8List(bytes.length);
      for (int i = 0; i < bytes.length; i++) {
        final vl = _calculateVL(seed[i % seed.length]);
        result[i] = (bytes[i] + vl) % modBytes;
      }
      
      // 3. Convert back to UTF-8 String
      return utf8.decode(result);
    } catch (e) {
      return "ERROR: CORRUPT_PAYLOAD_OR_WRONG_SEED";
    }
  }

  /// Binary Encryption Workflow (O(n) complexity)
  static Uint8List processBytes(Uint8List data, List<int> seed, {bool decrypt = false}) {
    final result = Uint8List(data.length);
    for (int i = 0; i < data.length; i++) {
      final vl = _calculateVL(seed[i % seed.length]);
      if (decrypt) {
        result[i] = (data[i] + vl) % modBytes;
      } else {
        result[i] = (data[i] - vl) % modBytes;
      }
    }
    return result;
  }
}
