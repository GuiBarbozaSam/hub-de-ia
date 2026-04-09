import 'package:flutter/material.dart';

class HomePage extends StatelessWidget {
  const HomePage({
    super.key,
    this.onOpenTranscription,
  });

  final VoidCallback? onOpenTranscription;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    Widget tile({
      required IconData icon,
      required String title,
      required String subtitle,
      VoidCallback? onTap,
    }) {
      return Card(
        elevation: 0,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap ??
                  () {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Módulo "$title" disponível em breve.')),
                );
              },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer.withOpacity(0.9),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(icon, color: scheme.onPrimaryContainer),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
              ],
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: LayoutBuilder(
        builder: (context, c) {
          final width = c.maxWidth;
          final crossAxisCount = width >= 1100 ? 3 : (width >= 700 ? 2 : 1);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Centralize seus fluxos de IA em um único ambiente.',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Históricos, preferências por usuário, processamento multimídia e integrações avançadas.',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: GridView.count(
                  crossAxisCount: crossAxisCount,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 1.85,
                  children: [
                    tile(
                      icon: Icons.subtitles_rounded,
                      title: 'Transcrição',
                      subtitle: 'Transcrição, tradução, preview e download de saídas.',
                      onTap: onOpenTranscription,
                    ),
                    tile(
                      icon: Icons.smart_toy_outlined,
                      title: 'Ollama',
                      subtitle: 'Chat local, ferramentas e gerenciamento de modelos.',
                    ),
                    tile(
                      icon: Icons.image_outlined,
                      title: 'Imagem',
                      subtitle: 'Geração, histórico e ajustes visuais.',
                    ),
                    tile(
                      icon: Icons.movie_outlined,
                      title: 'Vídeo',
                      subtitle: 'Geração, composição e fluxos automatizados.',
                    ),
                    tile(
                      icon: Icons.graphic_eq_rounded,
                      title: 'Áudio',
                      subtitle: 'TTS, efeitos sonoros, mixagem e processamento.',
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
