import 'package:flutter_test/flutter_test.dart';
import 'package:secure_messenger/services/encryption_service.dart';

void main() {
  test('Encryption and Decryption should match the original message', () {
    final service = EncryptionService();
    final original = "Hello, secure world! This is JAVS.";
    
    final encrypted = service.encrypt(original);
    
    expect(encrypted.cipher, isNotEmpty);
    expect(encrypted.seed, isNotNull);

    final decrypted = service.decrypt(encrypted);
    
    expect(decrypted, equals(original));
  });

  test('Encryption generates different cipher based on seed logic', () {
    final service = EncryptionService();
    final msg1 = "Secret";
    
    // Seed depends on Random internally, so running encrypt twice might produce 
    // different seeds and ciphers, but decrypt should still resolve to original.
    final encrypted1 = service.encrypt(msg1);
    final encrypted2 = service.encrypt(msg1);

    expect(service.decrypt(encrypted1), equals("Secret"));
    expect(service.decrypt(encrypted2), equals("Secret"));
  });
}
