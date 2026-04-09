import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'locale_controller.dart';

final appStringsProvider = Provider<AppStrings>((ref) {
  final locale = ref.watch(localeControllerProvider);
  return AppStrings(locale);
});

class AppStrings {
  final Locale locale;
  AppStrings(this.locale);

  String t(String key) {
    final lang = locale.languageCode.toLowerCase();
    return _map[lang]?[key] ?? _map['en']?[key] ?? key;
  }

  static const Map<String, Map<String, String>> _map = {
    'pt': {
      'app_title': 'Hub de IA',
      'dashboard': 'Dashboard',
      'home': 'Home',
      'ai': 'IA',
      'settings': 'Configurações',
      'everything_one_place': 'Tudo em um só lugar.',
      'subtitle': 'Configurações por usuário • históricos • presets • integrações IA',
      'transcription': 'Transcrição',
      'transcription_sub': 'Link / arquivo • presets por usuário',
      'ollama': 'Ollama',
      'ollama_sub': 'Chat local, tools, modelos',
      'image': 'Imagem',
      'image_sub': 'Geração • histórico',
      'video': 'Vídeo',
      'video_sub': 'Geração • presets',
      'audio': 'Áudio',
      'audio_sub': 'TTS / SFX / mix',

      'appearance': 'Aparência',
      'theme': 'Tema',
      'language': 'Idioma',
      'dark': 'Escuro',
      'light': 'Claro',
      'system': 'Sistema',
      'pt_br': 'Português (BR)',
      'en': 'English',

      'technology_experience': 'Technology Experience',
      'technology_experience_sub': 'Tela imersiva com efeitos 3D/zoom',
      'about': 'Sobre',
      'about_sub': 'Versão, build, links, licença',

      'profile': 'Perfil',
      'profile_sub': 'Nome, email, senha',
      'name': 'Nome',
      'email': 'Email',
      'save': 'Salvar',
      'change_password': 'Trocar senha',
      'current_password': 'Senha atual',
      'new_password': 'Nova senha',
      'confirm_password': 'Confirmar nova senha',
      'update_password': 'Atualizar senha',
      'logout': 'Sair',

      'coming_soon': 'Em breve',
      'tap_hotspots': 'Clique nos hotspots para abrir módulos.',
      'open_image_module': 'Abrir módulo de Imagem',
      'open_audio_module': 'Abrir módulo de Áudio',
      'open_video_module': 'Abrir módulo de Vídeo',
      'open_transcription_module': 'Abrir Transcrição',
      'open_ollama_module': 'Abrir Ollama',
    },
    'en': {
      'app_title': 'AI Hub',
      'dashboard': 'Dashboard',
      'home': 'Home',
      'ai': 'AI',
      'settings': 'Settings',
      'everything_one_place': 'Everything in one place.',
      'subtitle': 'Per-user settings • history • presets • AI integrations',
      'transcription': 'Transcription',
      'transcription_sub': 'Link / file • per-user presets',
      'ollama': 'Ollama',
      'ollama_sub': 'Local chat, tools, models',
      'image': 'Image',
      'image_sub': 'Generation • history',
      'video': 'Video',
      'video_sub': 'Generation • presets',
      'audio': 'Audio',
      'audio_sub': 'TTS / SFX / mix',

      'appearance': 'Appearance',
      'theme': 'Theme',
      'language': 'Language',
      'dark': 'Dark',
      'light': 'Light',
      'system': 'System',
      'pt_br': 'Portuguese (BR)',
      'en': 'English',

      'technology_experience': 'Technology Experience',
      'technology_experience_sub': 'Immersive screen with 3D/zoom effects',
      'about': 'About',
      'about_sub': 'Version, build, links, license',

      'profile': 'Profile',
      'profile_sub': 'Name, email, password',
      'name': 'Name',
      'email': 'Email',
      'save': 'Save',
      'change_password': 'Change password',
      'current_password': 'Current password',
      'new_password': 'New password',
      'confirm_password': 'Confirm new password',
      'update_password': 'Update password',
      'logout': 'Logout',

      'coming_soon': 'Coming soon',
      'tap_hotspots': 'Click hotspots to open modules.',
      'open_image_module': 'Open Image module',
      'open_audio_module': 'Open Audio module',
      'open_video_module': 'Open Video module',
      'open_transcription_module': 'Open Transcription',
      'open_ollama_module': 'Open Ollama',
    },
  };
}