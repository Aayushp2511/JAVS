import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../ui/theme/cyber_theme.dart';

/// JAVS: Centipede Graph Structural Visualizer
/// Visualizes P_n \odot 2k_1 graph mapping for Index Difference Cryptography
class GraphVisualizer extends StatefulWidget {
  final bool isActive;
  const GraphVisualizer({super.key, required this.isActive});

  @override
  State<GraphVisualizer> createState() => _GraphVisualizerState();
}

class _GraphVisualizerState extends State<GraphVisualizer> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 10))..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return CustomPaint(
          size: const Size(double.infinity, 120),
          painter: CentipedePainter(
            animationValue: _controller.value,
            isActive: widget.isActive,
          ),
        );
      },
    );
  }
}

class CentipedePainter extends CustomPainter {
  final double animationValue;
  final bool isActive;

  CentipedePainter({required this.animationValue, required this.isActive});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = CyberTheme.primaryNeon.withOpacity(isActive ? 0.3 : 0.05)
      ..strokeWidth = 1.0;

    final glowPaint = Paint()
      ..color = CyberTheme.primaryNeon.withOpacity(isActive ? 0.6 : 0.1)
      ..style = PaintingStyle.fill
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);

    final dotPaint = Paint()
      ..color = CyberTheme.primaryNeon.withOpacity(isActive ? 1.0 : 0.2)
      ..style = PaintingStyle.fill;

    // Centipede Path (P_n nodes)
    const int nodeCount = 12;
    double spacing = size.width / (nodeCount + 1);
    
    List<Offset> centers = [];
    for (int i = 0; i < nodeCount; i++) {
        double x = spacing * (i + 1);
        // Structural oscillation to simulate MTD rotation
        double wave = math.sin((animationValue * 2 * math.pi) + (i * 0.8)) * 8;
        centers.add(Offset(x, size.height / 2 + wave));
    }

    // Draw edges between Path nodes
    for (int i = 0; i < centers.length - 1; i++) {
        canvas.drawLine(centers[i], centers[i + 1], paint);
    }

    // Draw pendant vertices (2k_1) and connection edges
    for (int i = 0; i < centers.length; i++) {
        double phase = animationValue * 4 * math.pi + i;
        double legOffset = 30 + (math.cos(phase) * 6);
        
        Offset upperNode = Offset(centers[i].dx + (math.sin(phase)*2), centers[i].dy - legOffset);
        Offset lowerNode = Offset(centers[i].dx - (math.sin(phase)*2), centers[i].dy + legOffset);
        
        // Identity mapping edges
        canvas.drawLine(centers[i], upperNode, paint);
        canvas.drawLine(centers[i], lowerNode, paint);
        
        // Structural nodes
        if (isActive) canvas.drawCircle(centers[i], 4, glowPaint);
        canvas.drawCircle(centers[i], 2, dotPaint);
        canvas.drawCircle(upperNode, 1.5, dotPaint);
        canvas.drawCircle(lowerNode, 1.5, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CentipedePainter oldDelegate) => true;
}
