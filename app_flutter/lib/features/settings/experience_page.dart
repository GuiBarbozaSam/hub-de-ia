import 'package:flutter/material.dart';
import '../../core/widgets/gear_3d_button.dart';

class ExperiencePage extends StatelessWidget {
  const ExperiencePage({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Stack(
      children: [
        Container(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(0.0, -0.35),
              radius: 1.2,
              colors: [
                cs.primary.withOpacity(0.18),
                Theme.of(context).scaffoldBackgroundColor,
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Technology Experience',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 6),
              Text(
                'Interações imersivas (tilt/zoom) + atalhos para módulos.',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: cs.onSurface.withOpacity(0.7)),
              ),
              const SizedBox(height: 18),
              Expanded(
                child: Center(
                  child: Gear3DButton(
                    size: 96,
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Core acionado.')),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}