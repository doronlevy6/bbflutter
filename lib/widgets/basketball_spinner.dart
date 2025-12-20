import 'package:flutter/material.dart';
import 'dart:math' as math;

class BasketballSpinner extends StatefulWidget {
  final double size;
  const BasketballSpinner({Key? key, this.size = 50.0}) : super(key: key);

  @override
  _BasketballSpinnerState createState() => _BasketballSpinnerState();
}

class _BasketballSpinnerState extends State<BasketballSpinner> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 2), // 2 seconds per full rotation
      vsync: this,
    )..repeat();
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
      builder: (_, child) {
        return Transform.rotate(
          angle: _controller.value * 2 * math.pi,
          child: child,
        );
      },
      child: Center(
        child: SizedBox(
          width: widget.size,
          height: widget.size,
          child: Image.asset('assets/images/basketball.png'),
        ),
      ),
    );
  }
}
