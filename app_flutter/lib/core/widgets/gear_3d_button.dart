import 'dart:math' as math;
import 'package:flutter/material.dart';

class Gear3DButton extends StatefulWidget {
  const Gear3DButton({
    super.key,
    required this.onPressed,
    this.size = 72,
    this.tooltip,
  });

  final VoidCallback onPressed;
  final double size;
  final String? tooltip;

  @override
  State<Gear3DButton> createState() => _Gear3DButtonState();
}

class _Gear3DButtonState extends State<Gear3DButton> with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final Animation<double> _spin;
  bool _hover = false;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 950));
    _spin = CurvedAnimation(parent: _c, curve: Curves.easeInOutCubic);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _tap() {
    _c.forward(from: 0);
    widget.onPressed();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final size = widget.size;

    return Tooltip(
      message: widget.tooltip ?? '',
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: _tap,
          child: AnimatedScale(
            duration: const Duration(milliseconds: 160),
            scale: _hover ? 1.04 : 1.0,
            child: AnimatedBuilder(
              animation: _spin,
              builder: (context, _) {
                final t = _spin.value;
                final rot = (t * 2.2) * math.pi;
                final tilt = (_hover ? 0.12 : 0.06);

                return Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()
                    ..setEntry(3, 2, 0.0016)
                    ..rotateX(tilt)
                    ..rotateY(-tilt)
                    ..rotateZ(rot),
                  child: Container(
                    width: size,
                    height: size,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(size * 0.28),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          scheme.primary.withOpacity(0.32),
                          scheme.surfaceContainerHighest.withOpacity(0.12),
                        ],
                      ),
                      border: Border.all(color: scheme.primary.withOpacity(0.28)),
                      boxShadow: [
                        BoxShadow(
                          blurRadius: 24,
                          spreadRadius: 1,
                          offset: const Offset(0, 10),
                          color: Colors.black.withOpacity(0.22),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Icon(Icons.settings_rounded, color: scheme.primary, size: size * 0.46),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}