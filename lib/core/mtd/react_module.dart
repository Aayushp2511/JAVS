import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:state_notifier/state_notifier.dart';

/// REACT: Real-time Entropy Audit & Cryptographic Trigger
/// A Moving Target Defense (MTD) module inspired by DRL agents.
class REACTModule extends Notifier<REACTState> {
  @override
  REACTState build() {
    return REACTState(
      currentEntropy: 0.0,
      isAuditPassed: true,
      keyCycle: 0,
      systemStatus: "Operational",
    );
  }

  /// Internal Shannon Entropy Logic
  double _calculateEntropy(Uint8List data) {
    if (data.isEmpty) return 0.0;
    
    final counts = <int, int>{};
    for (var byte in data) {
      counts[byte] = (counts[byte] ?? 0) + 1;
    }

    double entropy = 0.0;
    int len = data.length;
    for (var count in counts.values) {
      double p = count / len;
      entropy -= p * (log(p) / log(2));
    }
    return entropy;
  }

  /// Perform security audit on ciphertext
  void audit(Uint8List ciphertext) {
    final entropy = _calculateEntropy(ciphertext);
    final passed = entropy > 7.5;
    
    if (!passed) {
      // Trigger MTD: Rotate Key Cycle
      state = state.copyWith(
        currentEntropy: entropy,
        isAuditPassed: false,
        keyCycle: state.keyCycle + 1,
        systemStatus: "RE-KEYING IN PROGRESS (Entropy Low)",
      );
      
      // Reset status after short delay
      Future.delayed(const Duration(seconds: 2), () {
        state = state.copyWith(systemStatus: "New Key Plane Synced");
      });
    } else {
      state = state.copyWith(
        currentEntropy: entropy,
        isAuditPassed: true,
        systemStatus: "Operational (High Entropy)",
      );
    }
  }
}

class REACTState {
  final double currentEntropy;
  final bool isAuditPassed;
  final int keyCycle;
  final String systemStatus;

  REACTState({
    required this.currentEntropy,
    required this.isAuditPassed,
    required this.keyCycle,
    required this.systemStatus,
  });

  REACTState copyWith({
    double? currentEntropy,
    bool? isAuditPassed,
    int? keyCycle,
    String? systemStatus,
  }) {
    return REACTState(
      currentEntropy: currentEntropy ?? this.currentEntropy,
      isAuditPassed: isAuditPassed ?? this.isAuditPassed,
      keyCycle: keyCycle ?? this.keyCycle,
      systemStatus: systemStatus ?? this.systemStatus,
    );
  }
}

final reactProvider = NotifierProvider<REACTModule, REACTState>(() {
  return REACTModule();
});
