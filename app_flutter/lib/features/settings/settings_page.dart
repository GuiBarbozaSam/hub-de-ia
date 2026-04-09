import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/app_strings.dart';
import '../../core/i18n/locale_controller.dart';
import '../../core/theme/theme_controller.dart';
import 'experience_page.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appStringsProvider);
    final mode = ref.watch(themeControllerProvider);
    final locale = ref.watch(localeControllerProvider);

    String themeLabel(ThemeMode m) {
      switch (m) {
        case ThemeMode.dark:
          return s.t('dark');
        case ThemeMode.light:
          return s.t('light');
        case ThemeMode.system:
          return s.t('system');
      }
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.t('appearance'), style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),

                Row(
                  children: [
                    Expanded(child: ListTile(
                      leading: const Icon(Icons.contrast_rounded),
                      title: Text(s.t('theme')),
                      subtitle: Text(themeLabel(mode)),
                      contentPadding: EdgeInsets.zero,
                    )),
                    DropdownButton<ThemeMode>(
                      value: mode,
                      onChanged: (v) {
                        if (v != null) ref.read(themeControllerProvider.notifier).setMode(v);
                      },
                      items: [
                        DropdownMenuItem(value: ThemeMode.dark, child: Text(s.t('dark'))),
                        DropdownMenuItem(value: ThemeMode.light, child: Text(s.t('light'))),
                        DropdownMenuItem(value: ThemeMode.system, child: Text(s.t('system'))),
                      ],
                    ),
                  ],
                ),

                const Divider(height: 22),

                Row(
                  children: [
                    Expanded(child: ListTile(
                      leading: const Icon(Icons.language_rounded),
                      title: Text(s.t('language')),
                      subtitle: Text(locale.languageCode == 'pt' ? s.t('pt_br') : s.t('en')),
                      contentPadding: EdgeInsets.zero,
                    )),
                    DropdownButton<Locale>(
                      value: locale.languageCode == 'pt' ? const Locale('pt', 'BR') : const Locale('en'),
                      onChanged: (v) {
                        if (v == null) return;
                        ref.read(localeControllerProvider.notifier).setLocale(v);
                      },
                      items: const [
                        DropdownMenuItem(value: Locale('pt', 'BR'), child: Text('Português (BR)')),
                        DropdownMenuItem(value: Locale('en'), child: Text('English')),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 14),

        Card(
          child: ListTile(
            leading: const Icon(Icons.auto_awesome_rounded),
            title: Text(s.t('technology_experience')),
            subtitle: Text(s.t('technology_experience_sub')),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ExperiencePage()),
              );
            },
          ),
        ),

        const SizedBox(height: 14),

        Card(
          child: ListTile(
            leading: const Icon(Icons.info_outline_rounded),
            title: Text(s.t('about')),
            subtitle: Text(s.t('about_sub')),
            onTap: () => showAboutDialog(
              context: context,
              applicationName: s.t('app_title'),
              applicationVersion: '0.1.0',
            ),
          ),
        ),
      ],
    );
  }
}