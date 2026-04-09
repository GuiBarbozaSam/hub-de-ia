import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/presentation/login_page.dart';
import '../../features/auth/state/auth_controller.dart';
import '../../features/home/home_page.dart';
import '../../features/settings/experience_page.dart';
import '../../features/settings/settings_page.dart';
import '../../features/settings/user_profile_page.dart';
import '../../features/transcription/presentation/transcription_page.dart';

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  static const int _homeIndex = 0;
  static const int _transcriptionIndex = 1;
  static const int _settingsIndex = 2;
  static const int _experienceIndex = 3;

  int _index = _homeIndex;

  void _goTo(int index) {
    if (!mounted) return;
    setState(() => _index = index);
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);

    if (auth.loading && (auth.token == null || auth.token!.isEmpty)) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (auth.token == null || auth.token!.isEmpty) {
      return const LoginPage();
    }

    final pages = <Widget>[
      HomePage(onOpenTranscription: () => _goTo(_transcriptionIndex)),
      const TranscriptionPage(),
      const SettingsPage(),
      const ExperiencePage(),
    ];

    final titles = <String>[
      'Painel Inicial',
      'Transcrição',
      'Configurações',
      'Experiência',
    ];

    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            NavigationRail(
              selectedIndex: _index,
              onDestinationSelected: _goTo,
              labelType: NavigationRailLabelType.all,
              leading: Padding(
                padding: const EdgeInsets.only(top: 10, bottom: 12),
                child: Column(
                  children: const [
                    CircleAvatar(
                      radius: 18,
                      child: Text('IA'),
                    ),
                    SizedBox(height: 10),
                    Text('Hub de IA'),
                  ],
                ),
              ),
              destinations: const [
                NavigationRailDestination(
                  icon: Icon(Icons.dashboard_rounded),
                  label: Text('Início'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.subtitles_rounded),
                  label: Text('Transcrição'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.settings_rounded),
                  label: Text('Configurações'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.auto_awesome_rounded),
                  label: Text('Experiência'),
                ),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: Column(
                children: [
                  SizedBox(
                    height: 56,
                    child: Row(
                      children: [
                        const SizedBox(width: 12),
                        Text(
                          titles[_index],
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const Spacer(),
                        IconButton(
                          tooltip: 'Perfil do usuário',
                          icon: const Icon(Icons.person_rounded),
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const UserProfilePage(),
                              ),
                            );
                          },
                        ),
                        IconButton(
                          tooltip: 'Abrir configurações',
                          icon: const Icon(Icons.settings_rounded),
                          onPressed: () => _goTo(_settingsIndex),
                        ),
                        IconButton(
                          tooltip: 'Encerrar sessão',
                          icon: const Icon(Icons.logout_rounded),
                          onPressed: () async {
                            await ref.read(authControllerProvider.notifier).logout();
                            if (!mounted) return;
                            _goTo(_homeIndex);
                          },
                        ),
                        const SizedBox(width: 8),
                      ],
                    ),
                  ),
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 260),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      child: KeyedSubtree(
                        key: ValueKey(_index),
                        child: pages[_index],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
