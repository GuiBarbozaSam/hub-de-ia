import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/transcription_models.dart';
import '../state/transcription_controller.dart';
import 'widgets/transcription_output_preview_dialog.dart';

class TranscriptionPage extends ConsumerStatefulWidget {
  const TranscriptionPage({super.key});

  @override
  ConsumerState<TranscriptionPage> createState() => _TranscriptionPageState();
}

class _TranscriptionPageState extends ConsumerState<TranscriptionPage> {
  static const Duration _tooltipWaitDuration = Duration(seconds: 3);
  static const double _contentGap = 16;
  static const double _cardPadding = 16;

  final TextEditingController _urlController = TextEditingController();
  final TextEditingController _serverPathController = TextEditingController();
  final TextEditingController _aiPromptController = TextEditingController();
  final TextEditingController _beamSizeController = TextEditingController();
  final TextEditingController _maxSubtitleCharsController =
      TextEditingController();
  final TextEditingController _aiMaxTokensController = TextEditingController();
  final TextEditingController _aiChunkCharsController = TextEditingController();
  final TextEditingController _aiFrameSampleSecondsController =
      TextEditingController();
  final TextEditingController _contextTitleController = TextEditingController();
  final TextEditingController _contextArtistController =
      TextEditingController();
  final TextEditingController _contextSeriesController =
      TextEditingController();
  final TextEditingController _contextEpisodeController =
      TextEditingController();
  final TextEditingController _contextUrlsController = TextEditingController();

  final FocusNode _urlFocusNode = FocusNode();
  final FocusNode _serverPathFocusNode = FocusNode();
  final FocusNode _aiPromptFocusNode = FocusNode();
  final FocusNode _beamSizeFocusNode = FocusNode();
  final FocusNode _maxSubtitleCharsFocusNode = FocusNode();
  final FocusNode _aiMaxTokensFocusNode = FocusNode();
  final FocusNode _aiChunkCharsFocusNode = FocusNode();
  final FocusNode _aiFrameSampleSecondsFocusNode = FocusNode();
  final FocusNode _contextTitleFocusNode = FocusNode();
  final FocusNode _contextArtistFocusNode = FocusNode();
  final FocusNode _contextSeriesFocusNode = FocusNode();
  final FocusNode _contextEpisodeFocusNode = FocusNode();
  final FocusNode _contextUrlsFocusNode = FocusNode();

  String? _selectedUploadPath;
  String? _selectedUploadName;
  String? _lastHydratedPreferenceSignature;

  @override
  void dispose() {
    _urlController.dispose();
    _serverPathController.dispose();
    _aiPromptController.dispose();
    _beamSizeController.dispose();
    _maxSubtitleCharsController.dispose();
    _aiMaxTokensController.dispose();
    _aiChunkCharsController.dispose();
    _aiFrameSampleSecondsController.dispose();
    _contextTitleController.dispose();
    _contextArtistController.dispose();
    _contextSeriesController.dispose();
    _contextEpisodeController.dispose();
    _contextUrlsController.dispose();

    _urlFocusNode.dispose();
    _serverPathFocusNode.dispose();
    _aiPromptFocusNode.dispose();
    _beamSizeFocusNode.dispose();
    _maxSubtitleCharsFocusNode.dispose();
    _aiMaxTokensFocusNode.dispose();
    _aiChunkCharsFocusNode.dispose();
    _aiFrameSampleSecondsFocusNode.dispose();
    _contextTitleFocusNode.dispose();
    _contextArtistFocusNode.dispose();
    _contextSeriesFocusNode.dispose();
    _contextEpisodeFocusNode.dispose();
    _contextUrlsFocusNode.dispose();
    super.dispose();
  }

  bool _isEnglish(BuildContext context) {
    return Localizations.localeOf(context).languageCode.toLowerCase() == 'en';
  }

  String _t(BuildContext context, String pt, String en) {
    return _isEnglish(context) ? en : pt;
  }

  void _syncTextController(
    TextEditingController controller,
    FocusNode focusNode,
    String value,
  ) {
    if (focusNode.hasFocus) return;
    if (controller.text == value) return;

    controller.value = controller.value.copyWith(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
      composing: TextRange.empty,
    );
  }

  String _preferenceHydrationSignature(TranscriptionPreference pref) {
    return <String>[
      pref.aiPrompt ?? '',
      pref.beamSize.toString(),
      pref.maxSubtitleChars?.toString() ?? '',
      pref.aiMaxTokens.toString(),
      pref.aiChunkChars.toString(),
      pref.aiFrameSampleSeconds.toString(),
      pref.aiRevisionPasses.toString(),
      pref.useAdvancedAlignment,
      pref.enableOnlineContext.toString(),
      pref.qualityProfile,
      pref.contextHints?.title ?? '',
      pref.contextHints?.artist ?? '',
      pref.contextHints?.series ?? '',
      pref.contextHints?.episode ?? '',
      pref.contextHints?.urls.join('\n') ?? '',
    ].join('|');
  }

  void _scheduleFormHydration(TranscriptionControllerState state) {
    final pref = state.preference;
    final signature = _preferenceHydrationSignature(pref);
    if (_lastHydratedPreferenceSignature == signature) {
      return;
    }
    _lastHydratedPreferenceSignature = signature;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncTextController(
        _aiPromptController,
        _aiPromptFocusNode,
        pref.aiPrompt ?? '',
      );
      _syncTextController(
        _beamSizeController,
        _beamSizeFocusNode,
        pref.beamSize.toString(),
      );
      _syncTextController(
        _maxSubtitleCharsController,
        _maxSubtitleCharsFocusNode,
        pref.maxSubtitleChars?.toString() ?? '',
      );
      _syncTextController(
        _aiMaxTokensController,
        _aiMaxTokensFocusNode,
        pref.aiMaxTokens.toString(),
      );
      _syncTextController(
        _aiChunkCharsController,
        _aiChunkCharsFocusNode,
        pref.aiChunkChars.toString(),
      );
      _syncTextController(
        _aiFrameSampleSecondsController,
        _aiFrameSampleSecondsFocusNode,
        pref.aiFrameSampleSeconds.toString(),
      );
      _syncTextController(
        _contextTitleController,
        _contextTitleFocusNode,
        pref.contextHints?.title ?? '',
      );
      _syncTextController(
        _contextArtistController,
        _contextArtistFocusNode,
        pref.contextHints?.artist ?? '',
      );
      _syncTextController(
        _contextSeriesController,
        _contextSeriesFocusNode,
        pref.contextHints?.series ?? '',
      );
      _syncTextController(
        _contextEpisodeController,
        _contextEpisodeFocusNode,
        pref.contextHints?.episode ?? '',
      );
      _syncTextController(
        _contextUrlsController,
        _contextUrlsFocusNode,
        (pref.contextHints?.urls ?? const <String>[]).join('\n'),
      );
    });
  }

  void _updateContextHintsFromFields(TranscriptionController controller) {
    final urls = _contextUrlsController.text
        .split(RegExp(r'[\r\n]+'))
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
    final hints = TranscriptionContextHints(
      title: _contextTitleController.text.trim().isEmpty
          ? null
          : _contextTitleController.text.trim(),
      artist: _contextArtistController.text.trim().isEmpty
          ? null
          : _contextArtistController.text.trim(),
      series: _contextSeriesController.text.trim().isEmpty
          ? null
          : _contextSeriesController.text.trim(),
      episode: _contextEpisodeController.text.trim().isEmpty
          ? null
          : _contextEpisodeController.text.trim(),
      urls: urls,
    );
    controller.setContextHints(hints.hasAny ? hints : null);
  }

  Future<void> _pickUploadFile() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      withData: false,
      lockParentWindow: true,
      type: FileType.custom,
      allowedExtensions: const <String>[
        'mp4',
        'mkv',
        'mov',
        'avi',
        'webm',
        'mp3',
        'wav',
        'm4a',
        'flac',
        'ogg',
        'aac',
        'txt',
        'srt',
        'vtt',
        'ass',
      ],
    );

    final file = result?.files.single;
    final path = file?.path?.trim();
    if (path == null || path.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              context,
              'Nenhum arquivo foi selecionado.',
              'No file was selected.',
            ),
          ),
        ),
      );
      return;
    }

    final fileName = file?.name.trim();

    setState(() {
      _selectedUploadPath = path;
      _selectedUploadName = (fileName != null && fileName.isNotEmpty)
          ? fileName
          : path.split(RegExp(r'[\\/]')).last;
    });

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _t(
            context,
            'Arquivo selecionado. Clique em Rodar para iniciar o processamento.',
            'File selected. Click Run to start processing.',
          ),
        ),
      ),
    );
  }

  Future<void> _submitCurrentSource(TranscriptionSourceMode mode) async {
    final controller = ref.read(transcriptionControllerProvider.notifier);

    switch (mode) {
      case TranscriptionSourceMode.upload:
        final selectedPath = _selectedUploadPath?.trim();
        if (selectedPath == null || selectedPath.isEmpty) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                _t(
                  context,
                  'Selecione um arquivo antes de clicar em Rodar.',
                  'Select a file before clicking Run.',
                ),
              ),
            ),
          );
          return;
        }
        await controller.submitUpload(selectedPath);
        break;
      case TranscriptionSourceMode.url:
        await controller.submitUrl(_urlController.text);
        break;
      case TranscriptionSourceMode.filePath:
        await controller.submitServerPath(_serverPathController.text);
        break;
    }
  }

  Future<void> _openPreview(TranscriptionOutput output) async {
    if (!output.canPreviewInline) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              context,
              'Este arquivo não possui visualização inline disponível.',
              'This file does not have inline preview available.',
            ),
          ),
        ),
      );
      return;
    }

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) {
        final selectedJob = ref
            .read(transcriptionControllerProvider)
            .selectedJob;

        return TranscriptionOutputPreviewDialog(
          output: output,
          siblingOutputs: selectedJob?.outputs ?? const <TranscriptionOutput>[],
          preferRenderedPreview:
              TranscriptionPreviewPolicy.prefersRenderedPreviewForDetail(
                selectedJob,
              ),
        );
      },
    );
  }

  Future<void> _copyOutputLink(TranscriptionOutput output) async {
    final link =
        output.downloadUrl ?? output.previewUrl ?? output.previewPageUrl;
    if (link == null || link.trim().isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              context,
              'Este output não possui link disponível para cópia.',
              'This output does not have an available link to copy.',
            ),
          ),
        ),
      );
      return;
    }

    await Clipboard.setData(ClipboardData(text: link));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _t(
            context,
            'Link copiado para a área de transferência.',
            'Link copied to clipboard.',
          ),
        ),
      ),
    );
  }

  String _statusLabel(BuildContext context, String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return _t(context, 'Pendente', 'Pending');
      case 'processing':
        return _t(context, 'Processando', 'Processing');
      case 'completed':
        return _t(context, 'Concluído', 'Completed');
      case 'error':
        return _t(context, 'Erro', 'Error');
      case 'canceled':
        return _t(context, 'Cancelado', 'Canceled');
      default:
        return status;
    }
  }

  Color _statusColor(BuildContext context, String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return Colors.amber;
      case 'processing':
        return Colors.blue;
      case 'completed':
        return Colors.green;
      case 'error':
        return Theme.of(context).colorScheme.error;
      case 'canceled':
        return Colors.grey;
      default:
        return Theme.of(context).colorScheme.primary;
    }
  }

  String _sourceModeLabel(BuildContext context, TranscriptionSourceMode mode) {
    switch (mode) {
      case TranscriptionSourceMode.upload:
        return _t(context, 'Upload', 'Upload');
      case TranscriptionSourceMode.url:
        return _t(context, 'URL', 'URL');
      case TranscriptionSourceMode.filePath:
        return _t(context, 'Caminho no Servidor', 'Server Path');
    }
  }

  String _taskLabel(BuildContext context, String task) {
    switch (task) {
      case 'translate':
        return _t(context, 'Traduzir', 'Translate');
      case 'transcribe':
      default:
        return _t(context, 'Transcrever', 'Transcribe');
    }
  }

  String _aiModeLabel(BuildContext context, String mode) {
    switch (mode) {
      case 'correction':
        return _t(context, 'Correção', 'Correction');
      case 'semantic_translation':
        return _t(context, 'Tradução Semântica', 'Semantic Translation');
      case 'subtitle_styling':
        return _t(context, 'Estilização de Legenda', 'Subtitle Styling');
      default:
        return mode;
    }
  }

  String _languageLabel(BuildContext context, String code) {
    final normalized = code.trim().toLowerCase();
    final english = <String, String>{
      'pt-br': 'Portuguese (Brazil)',
      'pt': 'Portuguese',
      'en': 'English',
      'es': 'Spanish',
      'fr': 'French',
      'de': 'German',
      'it': 'Italian',
      'ja': 'Japanese',
      'ko': 'Korean',
      'zh-cn': 'Simplified Chinese',
      'zh': 'Chinese',
      'ru': 'Russian',
      'ar': 'Arabic',
      'hi': 'Hindi',
      'auto': 'Automatic',
    };
    final portuguese = <String, String>{
      'pt-br': 'Português (Brasil)',
      'pt': 'Português',
      'en': 'Inglês',
      'es': 'Espanhol',
      'fr': 'Francês',
      'de': 'Alemão',
      'it': 'Italiano',
      'ja': 'Japonês',
      'ko': 'Coreano',
      'zh-cn': 'Chinês Simplificado',
      'zh': 'Chinês',
      'ru': 'Russo',
      'ar': 'Árabe',
      'hi': 'Hindi',
      'auto': 'Automático',
    };
    return _isEnglish(context)
        ? (english[normalized] ?? code)
        : (portuguese[normalized] ?? code);
  }

  String _outputTypeLabel(BuildContext context, String outputType) {
    switch (outputType.toLowerCase()) {
      case 'txt':
        return 'TXT';
      case 'srt':
        return 'SRT';
      case 'vtt':
        return 'VTT';
      case 'ass':
        return 'ASS';
      case 'video_burned':
        return _t(context, 'Vídeo Legendado', 'Burned Video');
      case 'video_muxed':
        return _t(context, 'Vídeo com Trilhas', 'Muxed Video');
      case 'render_preview':
        return _t(context, 'Preview Renderizado', 'Rendered Preview');
      case 'karaoke_plan':
        return _t(context, 'Plano de Karaoke', 'Karaoke Plan');
      case 'translations_manifest':
        return _t(context, 'Manifesto de Traduções', 'Translations Manifest');
      default:
        return outputType;
    }
  }

  String _videoDeliveryLabel(BuildContext context, String value) {
    switch (value) {
      case 'standard':
        return _t(context, 'Padrão', 'Standard');
      case 'video_only':
        return _t(context, 'Somente vídeo', 'Video only');
      case 'mux_subtitles':
        return _t(
          context,
          'Vídeo com trilhas muxadas',
          'Muxed subtitle tracks',
        );
      case 'burned_video':
        return _t(
          context,
          'Vídeo com legenda queimada',
          'Burned subtitle video',
        );
      default:
        return value;
    }
  }

  String _presetLabel(BuildContext context, String preset) {
    switch (preset) {
      case 'default':
        return _t(context, 'Padrão', 'Default');
      case 'clean':
        return _t(context, 'Limpo', 'Clean');
      case 'highlight':
        return _t(context, 'Destaque', 'Highlight');
      case 'cinematic':
        return _t(context, 'Cinematográfico', 'Cinematic');
      case 'shorts_bold':
        return _t(context, 'Shorts Forte', 'Shorts Bold');
      case 'shorts_dynamic':
        return _t(context, 'Shorts Dinâmico', 'Shorts Dynamic');
      case 'shorts_neon':
        return _t(context, 'Shorts Neon', 'Shorts Neon');
      default:
        return preset;
    }
  }

  String _alignmentModeLabel(BuildContext context, String value) {
    switch (value) {
      case 'auto':
        return _t(context, 'Automático', 'Automatic');
      case 'on':
        return _t(context, 'Ativado', 'Enabled');
      case 'off':
        return _t(context, 'Desativado', 'Disabled');
      default:
        return value;
    }
  }

  String _qualityProfileLabel(BuildContext context, String value) {
    switch (value) {
      case 'safe':
        return _t(context, 'Seguro', 'Safe');
      case 'balanced':
        return _t(context, 'Balanceado', 'Balanced');
      case 'max':
        return _t(context, 'Máximo', 'Max');
      default:
        return value;
    }
  }

  String _contentModeLabel(BuildContext context, String value) {
    switch (value) {
      case 'auto':
        return _t(context, 'Auto', 'Auto');
      case 'episode':
        return _t(context, 'Episódio', 'Episode');
      case 'anime_song':
        return _t(context, 'Anime Song', 'Anime Song');
      default:
        return value;
    }
  }

  String _speakerStyleModeLabel(BuildContext context, String value) {
    switch (value) {
      case 'off':
        return _t(context, 'Desativado', 'Off');
      case 'heuristic':
        return _t(context, 'Heurística', 'Heuristic');
      case 'advanced':
        return _t(context, 'Avançada', 'Advanced');
      default:
        return value;
    }
  }

  String _styleIntensityLabel(BuildContext context, String value) {
    switch (value) {
      case 'subtle':
        return _t(context, 'Sutil', 'Subtle');
      case 'thematic':
        return _t(context, 'Temática', 'Thematic');
      case 'expressive':
        return _t(context, 'Expressiva', 'Expressive');
      default:
        return value;
    }
  }

  String _previewModeLabel(BuildContext context, String value) {
    switch (value) {
      case 'fast':
        return _t(context, 'Rápido', 'Fast');
      case 'rendered':
        return _t(context, 'Renderizado', 'Rendered');
      default:
        return value;
    }
  }

  String _animeSongLayoutLabel(BuildContext context, String value) {
    switch (value) {
      case 'off':
        return _t(context, 'Desativado', 'Off');
      case 'romaji_top_translation_bottom':
        return _t(
          context,
          'Romaji em cima + tradução embaixo',
          'Romaji on top + translation below',
        );
      default:
        return value;
    }
  }

  String _karaokeGranularityLabel(BuildContext context, String value) {
    switch (value) {
      case 'off':
        return _t(context, 'Desativado', 'Off');
      case 'word':
        return _t(context, 'Por palavra', 'Per word');
      case 'syllable':
        return _t(context, 'Por sílaba', 'Per syllable');
      default:
        return value;
    }
  }

  String _aiModelLabel(BuildContext context, String value) {
    switch (value.trim()) {
      case 'qwen2.5vl:7b':
        return '$value • ${_t(context, 'local/degradado', 'local/degraded')}';
      case 'qwen2.5vl:32b':
        return '$value • ${_t(context, 'alta qualidade', 'high quality')}';
      case 'qwen3-vl:30b-a3b-instruct-q4_K_M':
        return '$value • ${_t(context, 'alta qualidade', 'high quality')}';
      default:
        return value;
    }
  }

  String _currentStageLabel(BuildContext context, String? stage) {
    switch ((stage ?? '').trim().toLowerCase()) {
      case 'ingestion':
        return _t(context, 'Ingestão', 'Ingestion');
      case 'asr':
        return _t(context, 'ASR', 'ASR');
      case 'alignment':
        return _t(context, 'Alinhamento', 'Alignment');
      case 'cleanup':
        return _t(context, 'Limpeza', 'Cleanup');
      case 'translation':
      case 'semantic_translation':
        return _t(context, 'Tradução', 'Translation');
      case 'review':
      case 'review_score':
        return _t(context, 'Revisão', 'Review');
      case 'styling':
      case 'subtitle_styling':
        return _t(context, 'Estilização', 'Styling');
      case 'packaging':
        return _t(context, 'Empacotamento', 'Packaging');
      case 'completed':
        return _t(context, 'Concluído', 'Completed');
      case 'error':
        return _t(context, 'Erro', 'Error');
      default:
        return stage?.trim().isNotEmpty == true
            ? stage!.trim()
            : _t(context, 'Sem etapa', 'No stage');
    }
  }

  String _formatBytes(BuildContext context, int? bytes) {
    if (bytes == null || bytes <= 0) {
      return _t(context, 'Não informado', 'Not informed');
    }
    const units = <String>['B', 'KB', 'MB', 'GB', 'TB'];
    var value = bytes.toDouble();
    var index = 0;
    while (value >= 1024 && index < units.length - 1) {
      value /= 1024;
      index++;
    }
    return '${value.toStringAsFixed(value >= 10 || index == 0 ? 0 : 1)} ${units[index]}';
  }

  String _formatDate(BuildContext context, DateTime? value) {
    if (value == null) {
      return _t(context, '—', '—');
    }

    final local = value.toLocal();
    final dd = local.day.toString().padLeft(2, '0');
    final mm = local.month.toString().padLeft(2, '0');
    final yyyy = local.year.toString();
    final hh = local.hour.toString().padLeft(2, '0');
    final min = local.minute.toString().padLeft(2, '0');
    final ss = local.second.toString().padLeft(2, '0');
    return '$dd/$mm/$yyyy $hh:$min:$ss';
  }

  String _durationLabel(BuildContext context, double? seconds) {
    if (seconds == null) return _t(context, 'Não informado', 'Not informed');
    final total = seconds.round();
    final h = total ~/ 3600;
    final m = (total % 3600) ~/ 60;
    final s = total % 60;
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  String _safeJobTitle(TranscriptionJobListItem job) {
    final value = job.sourceValue.trim();
    if (value.isEmpty) return job.id;
    return value;
  }

  int? _parseNullableInt(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    return int.tryParse(trimmed);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(transcriptionControllerProvider);
    final controller = ref.read(transcriptionControllerProvider.notifier);
    final pref = state.preference;
    final options = state.options;
    final enabled = !state.isBootstrapping && !state.isSubmitting;
    final stylingEnabled =
        pref.aiEnhancementEnabled &&
        controller.selectedAiModes.contains('subtitle_styling');
    final multiTargetTranslate =
        pref.task == 'translate' && pref.targetLanguages.length > 1;
    final canSubmit = !state.isSubmitting && !state.isBootstrapping;

    _scheduleFormHydration(state);

    final modelOptions = (options?.models ?? const <String>['large-v3']);
    final taskOptions =
        (options?.tasks ?? const <String>['transcribe', 'translate']);
    final languageOptions =
        (options?.languages ?? const <String>['auto', 'pt', 'en', 'es']);
    final deviceOptions =
        (options?.devices ?? const <String>['auto', 'cpu', 'gpu:0']);
    final computeOptions =
        (options?.computeTypes ??
        const <String>['float16', 'int8', 'int8_float16']);
    final subtitlePresetOptions =
        options?.subtitleVisualPresets.isNotEmpty == true
        ? options!.subtitleVisualPresets
        : UiTranscriptionConstants.subtitleVisualPresets;
    final aiModelOptions = options?.aiModels.isNotEmpty == true
        ? options!.aiModels
        : UiTranscriptionConstants.aiModelOptions;
    final targetLanguageOptions = options?.targetLanguages.isNotEmpty == true
        ? options!.targetLanguages
        : UiTranscriptionConstants.targetLanguageOptions;
    final videoDeliveryOptions = UiTranscriptionConstants.videoDeliveryModes;

    return Scaffold(
      appBar: AppBar(
        title: Text(_t(context, 'Transcrição', 'Transcription')),
        actions: <Widget>[
          IconButton(
            tooltip: _t(
              context,
              'Atualizar opções e execuções',
              'Refresh options and runs',
            ),
            onPressed: state.isBootstrapping
                ? null
                : () => controller.bootstrap(force: true),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            if (state.isBootstrapping)
              const LinearProgressIndicator(minHeight: 2),
            Expanded(
              child: LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  final showSidePane = constraints.maxWidth >= 1360;
                  if (showSidePane) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Expanded(
                          flex: 8,
                          child: _buildMainPane(
                            context,
                            state,
                            pref,
                            enabled,
                            canSubmit,
                            stylingEnabled,
                            multiTargetTranslate,
                            modelOptions,
                            taskOptions,
                            languageOptions,
                            deviceOptions,
                            computeOptions,
                            subtitlePresetOptions,
                            aiModelOptions,
                            targetLanguageOptions,
                            videoDeliveryOptions,
                          ),
                        ),
                        const VerticalDivider(width: 1),
                        SizedBox(
                          width: 420,
                          child: _buildJobsPane(
                            context,
                            state,
                            fixedSplit: true,
                          ),
                        ),
                      ],
                    );
                  }

                  return _buildMainPane(
                    context,
                    state,
                    pref,
                    enabled,
                    canSubmit,
                    stylingEnabled,
                    multiTargetTranslate,
                    modelOptions,
                    taskOptions,
                    languageOptions,
                    deviceOptions,
                    computeOptions,
                    subtitlePresetOptions,
                    aiModelOptions,
                    targetLanguageOptions,
                    videoDeliveryOptions,
                    includeJobsBelow: true,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMainPane(
    BuildContext context,
    TranscriptionControllerState state,
    TranscriptionPreference pref,
    bool enabled,
    bool canSubmit,
    bool stylingEnabled,
    bool multiTargetTranslate,
    List<String> modelOptions,
    List<String> taskOptions,
    List<String> languageOptions,
    List<String> deviceOptions,
    List<String> computeOptions,
    List<String> subtitlePresetOptions,
    List<String> aiModelOptions,
    List<String> targetLanguageOptions,
    List<String> videoDeliveryOptions, {
    bool includeJobsBelow = false,
  }) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _buildTopSummaryBar(context, state),
          const SizedBox(height: _contentGap),
          _buildMessageBanner(context, state),
          _buildSourceCard(context, state, enabled, canSubmit),
          const SizedBox(height: _contentGap),
          _buildTranscriptionConfigCard(
            context,
            state,
            pref,
            enabled,
            modelOptions,
            taskOptions,
            languageOptions,
            deviceOptions,
            computeOptions,
          ),
          const SizedBox(height: _contentGap),
          _buildOutputsCard(
            context,
            state,
            pref,
            enabled,
            stylingEnabled,
            multiTargetTranslate,
            subtitlePresetOptions,
            targetLanguageOptions,
            videoDeliveryOptions,
          ),
          const SizedBox(height: _contentGap),
          _buildCapabilitiesCard(context, state),
          const SizedBox(height: _contentGap),
          _buildAiCard(context, state, pref, enabled, aiModelOptions),
          const SizedBox(height: _contentGap),
          _buildFooterActions(context, state),
          if (includeJobsBelow) ...<Widget>[
            const SizedBox(height: _contentGap),
            _buildJobsPane(context, state),
          ],
        ],
      ),
    );
  }

  Widget _buildTopSummaryBar(
    BuildContext context,
    TranscriptionControllerState state,
  ) {
    final tiles = <_SummaryTile>[
      _SummaryTile(
        icon: Icons.settings_suggest_outlined,
        title: _t(context, 'Modelo de ASR', 'ASR Model'),
        value: state.preference.model,
        accent: const Color(0xFF4DD0E1),
      ),
      _SummaryTile(
        icon: Icons.auto_awesome_outlined,
        title: _t(context, 'Modelo de IA', 'AI Model'),
        value: state.preference.aiEnhancementEnabled
            ? state.preference.aiModel
            : _t(context, 'Desativado', 'Disabled'),
        accent: const Color(0xFFF5B86C),
      ),
      _SummaryTile(
        icon: Icons.translate_outlined,
        title: _t(context, 'Idiomas de Saída', 'Target Languages'),
        value: state.preference.targetLanguages.isEmpty
            ? _t(context, 'Nenhum', 'None')
            : state.preference.targetLanguages
                  .map((code) => _languageLabel(context, code))
                  .join(', '),
        accent: const Color(0xFF7EE081),
      ),
      _SummaryTile(
        icon: Icons.movie_creation_outlined,
        title: _t(context, 'Entrega de Vídeo', 'Video Delivery'),
        value: _videoDeliveryLabel(context, state.preference.videoDeliveryMode),
        accent: const Color(0xFFB39DFF),
      ),
    ];

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: tiles
          .asMap()
          .entries
          .map(
            (entry) => SizedBox(
              width: 220,
              child: _AnimatedEntrance(
                delay: Duration(milliseconds: 50 * entry.key),
                child: Builder(
                  builder: (context) {
                    final tile = entry.value;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        gradient: LinearGradient(
                          colors: <Color>[
                            tile.accent.withValues(alpha: 0.18),
                            Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest
                                .withValues(alpha: 0.22),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        border: Border.all(
                          color: tile.accent.withValues(alpha: 0.28),
                        ),
                        boxShadow: <BoxShadow>[
                          BoxShadow(
                            color: tile.accent.withValues(alpha: 0.12),
                            blurRadius: 18,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        child: Row(
                          children: <Widget>[
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: tile.accent.withValues(alpha: 0.16),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Icon(tile.icon, color: tile.accent),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Text(
                                    tile.title,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.labelMedium,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    tile.value,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleMedium,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _buildMessageBanner(
    BuildContext context,
    TranscriptionControllerState state,
  ) {
    if (state.errorMessage == null && state.successMessage == null) {
      return const SizedBox.shrink();
    }

    final bool isError = state.errorMessage != null;
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final Color background = isError
        ? colorScheme.errorContainer
        : colorScheme.secondaryContainer;
    final Color foreground = isError
        ? colorScheme.onErrorContainer
        : colorScheme.onSecondaryContainer;
    final String message = state.errorMessage ?? state.successMessage ?? '';

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: _AnimatedEntrance(
        triggerKey: message,
        child: Material(
          color: background,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: <Widget>[
                Icon(
                  isError ? Icons.error_outline : Icons.check_circle_outline,
                  color: foreground,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    message,
                    style: TextStyle(
                      color: foreground,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => ref
                      .read(transcriptionControllerProvider.notifier)
                      .clearMessages(),
                  child: Text(_t(context, 'Fechar', 'Dismiss')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSourceCard(
    BuildContext context,
    TranscriptionControllerState state,
    bool enabled,
    bool canSubmit,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(_cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _SectionHeader(
              title: _t(context, 'Origem', 'Source'),
              subtitle: _t(
                context,
                'Escolha como a transcrição será iniciada.',
                'Choose how the transcription will be started.',
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: TranscriptionSourceMode.values.map((
                TranscriptionSourceMode mode,
              ) {
                final bool selected = state.sourceMode == mode;
                return ChoiceChip(
                  label: Text(_sourceModeLabel(context, mode)),
                  selected: selected,
                  onSelected: enabled
                      ? (_) => ref
                            .read(transcriptionControllerProvider.notifier)
                            .setSourceMode(mode)
                      : null,
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: switch (state.sourceMode) {
                TranscriptionSourceMode.upload => _buildUploadSourceContent(
                  context,
                  state,
                  canSubmit,
                ),
                TranscriptionSourceMode.url => _buildUrlSourceContent(
                  context,
                  state,
                  canSubmit,
                ),
                TranscriptionSourceMode.filePath => _buildFilePathSourceContent(
                  context,
                  state,
                  canSubmit,
                ),
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUploadSourceContent(
    BuildContext context,
    TranscriptionControllerState state,
    bool canSubmit,
  ) {
    final bool hasFile = (_selectedUploadPath ?? '').trim().isNotEmpty;

    return Column(
      key: const ValueKey<String>('source-upload'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          _t(
            context,
            'Selecione um vídeo ou áudio local. O arquivo só será enviado e processado quando você clicar em Rodar.',
            'Select a local video or audio file. The file will only be uploaded and processed after you click Run.',
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: <Widget>[
            OutlinedButton.icon(
              onPressed: canSubmit ? _pickUploadFile : null,
              icon: const Icon(Icons.attach_file_outlined),
              label: Text(_t(context, 'Selecionar Arquivo', 'Select File')),
            ),
            FilledButton.icon(
              onPressed: canSubmit && hasFile
                  ? () => _submitCurrentSource(TranscriptionSourceMode.upload)
                  : null,
              icon: state.isSubmitting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.play_arrow_rounded),
              label: Text(_t(context, 'Rodar', 'Run')),
            ),
          ],
        ),
        const SizedBox(height: 12),
        AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Theme.of(context).dividerColor),
            color: Theme.of(
              context,
            ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
          ),
          child: Text(
            hasFile
                ? '${_t(context, 'Arquivo selecionado', 'Selected file')}: ${_selectedUploadName ?? _selectedUploadPath!}'
                : _t(
                    context,
                    'Nenhum arquivo selecionado ainda.',
                    'No file selected yet.',
                  ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildUrlSourceContent(
    BuildContext context,
    TranscriptionControllerState state,
    bool canSubmit,
  ) {
    return Column(
      key: const ValueKey<String>('source-url'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        TextFormField(
          controller: _urlController,
          focusNode: _urlFocusNode,
          decoration: InputDecoration(
            labelText: _t(context, 'URL de Origem', 'Source URL'),
            border: const OutlineInputBorder(),
            hintText: 'https://...',
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: canSubmit
              ? () => _submitCurrentSource(TranscriptionSourceMode.url)
              : null,
          icon: state.isSubmitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.link_outlined),
          label: Text(
            _t(
              context,
              'Criar Execução a partir de URL',
              'Create Run from URL',
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFilePathSourceContent(
    BuildContext context,
    TranscriptionControllerState state,
    bool canSubmit,
  ) {
    return Column(
      key: const ValueKey<String>('source-file-path'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        TextFormField(
          controller: _serverPathController,
          focusNode: _serverPathFocusNode,
          decoration: InputDecoration(
            labelText: _t(
              context,
              'Caminho do Arquivo no Servidor',
              'Server File Path',
            ),
            border: const OutlineInputBorder(),
            hintText: r'D:\Uploads\video.mp4',
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: canSubmit
              ? () => _submitCurrentSource(TranscriptionSourceMode.filePath)
              : null,
          icon: state.isSubmitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.folder_open_outlined),
          label: Text(
            _t(
              context,
              'Criar Execução a partir de Caminho no Servidor',
              'Create Run from Server Path',
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTranscriptionConfigCard(
    BuildContext context,
    TranscriptionControllerState state,
    TranscriptionPreference pref,
    bool enabled,
    List<String> modelOptions,
    List<String> taskOptions,
    List<String> languageOptions,
    List<String> deviceOptions,
    List<String> computeOptions,
  ) {
    final controller = ref.read(transcriptionControllerProvider.notifier);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(_cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _SectionHeader(
              title: _t(
                context,
                'Configuração de Transcrição',
                'Transcription Configuration',
              ),
              subtitle: _t(
                context,
                'Defina modelo, tarefa, idioma e parâmetros base do ASR.',
                'Define model, task, language and core ASR parameters.',
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: <Widget>[
                _dropdownField(
                  context: context,
                  width: 240,
                  label: _t(context, 'Modelo de ASR', 'ASR Model'),
                  value: pref.model,
                  items: modelOptions,
                  itemLabelBuilder: (value) => value,
                  onChanged: enabled ? controller.setModel : null,
                ),
                _dropdownField(
                  context: context,
                  width: 240,
                  label: _t(context, 'Tarefa', 'Task'),
                  value: pref.task,
                  items: taskOptions,
                  itemLabelBuilder: (value) => _taskLabel(context, value),
                  onChanged: enabled ? controller.setTask : null,
                ),
                _dropdownField(
                  context: context,
                  width: 220,
                  label: _t(context, 'Idioma de Entrada', 'Input Language'),
                  value: pref.language,
                  items: languageOptions,
                  itemLabelBuilder: (value) => _languageLabel(context, value),
                  onChanged: enabled ? controller.setLanguage : null,
                ),
                _dropdownField(
                  context: context,
                  width: 220,
                  label: _t(context, 'Dispositivo', 'Device'),
                  value: pref.devicePreference,
                  items: deviceOptions,
                  itemLabelBuilder: (value) => value,
                  onChanged: enabled ? controller.setDevicePreference : null,
                ),
                _dropdownField(
                  context: context,
                  width: 220,
                  label: _t(context, 'Tipo de Cômputo', 'Compute Type'),
                  value: pref.computeType,
                  items: computeOptions,
                  itemLabelBuilder: (value) => value,
                  onChanged: enabled ? controller.setComputeType : null,
                ),
                _numberField(
                  context: context,
                  width: 180,
                  label: _t(context, 'Tamanho do Beam', 'Beam Size'),
                  controller: _beamSizeController,
                  focusNode: _beamSizeFocusNode,
                  onChanged: enabled
                      ? (value) {
                          final parsed = _parseNullableInt(value);
                          if (parsed != null) {
                            controller.setBeamSize(parsed);
                          }
                        }
                      : null,
                ),
                _numberField(
                  context: context,
                  width: 180,
                  label: _t(
                    context,
                    'Máx. Caracteres por Legenda',
                    'Max Subtitle Characters',
                  ),
                  controller: _maxSubtitleCharsController,
                  focusNode: _maxSubtitleCharsFocusNode,
                  onChanged: enabled
                      ? (value) => controller.setMaxSubtitleChars(
                          _parseNullableInt(value),
                        )
                      : null,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: <Widget>[
                _switchCard(
                  context,
                  title: _t(context, 'Manter timestamps', 'Keep timestamps'),
                  subtitle: _t(
                    context,
                    'Preserva a estrutura temporal do ASR.',
                    'Preserves the temporal structure of the ASR.',
                  ),
                  value: pref.keepTimestamps,
                  onChanged: enabled ? controller.setKeepTimestamps : null,
                ),
                _switchCard(
                  context,
                  title: _t(
                    context,
                    'Quebrar por sentença',
                    'Split by sentence',
                  ),
                  subtitle: _t(
                    context,
                    'Tenta segmentar melhor as legendas.',
                    'Attempts to segment subtitles more naturally.',
                  ),
                  value: pref.splitBySentence,
                  onChanged: enabled ? controller.setSplitBySentence : null,
                ),
                _switchCard(
                  context,
                  title: _t(
                    context,
                    'Timestamps por palavra',
                    'Word timestamps',
                  ),
                  subtitle: _t(
                    context,
                    'Útil para estilização, karaokê e destaque por palavra.',
                    'Useful for styling, karaoke and word-level emphasis.',
                  ),
                  value: pref.wordTimestamps,
                  onChanged: enabled ? controller.setWordTimestamps : null,
                ),
                _switchCard(
                  context,
                  title: _t(context, 'Filtro VAD', 'VAD filter'),
                  subtitle: _t(
                    context,
                    'Reduz trechos de silêncio antes da segmentação.',
                    'Reduces silent spans before segmentation.',
                  ),
                  value: pref.vadFilter,
                  onChanged: enabled ? controller.setVadFilter : null,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOutputsCard(
    BuildContext context,
    TranscriptionControllerState state,
    TranscriptionPreference pref,
    bool enabled,
    bool stylingEnabled,
    bool multiTargetTranslate,
    List<String> subtitlePresetOptions,
    List<String> targetLanguageOptions,
    List<String> videoDeliveryOptions,
  ) {
    final controller = ref.read(transcriptionControllerProvider.notifier);
    final allTextOutputsSelected =
        pref.selectedTextOutputs.length ==
        UiTranscriptionConstants.textOutputOptions.length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(_cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _SectionHeader(
              title: _t(
                context,
                'Saídas, Tradução e Vídeo',
                'Outputs, Translation and Video',
              ),
              subtitle: _t(
                context,
                'Controle os formatos gerados, os idiomas de saída e o modo de entrega do vídeo.',
                'Control generated formats, target languages and video delivery mode.',
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _t(context, 'Saídas textuais', 'Text outputs'),
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                FilterChip(
                  label: Text(_t(context, 'Todas as Opções', 'All Options')),
                  selected: allTextOutputsSelected,
                  onSelected: enabled ? controller.setAllTextOutputs : null,
                  tooltip: _t(
                    context,
                    'Seleciona TXT, SRT, VTT e ASS em um único clique.',
                    'Selects TXT, SRT, VTT and ASS in one action.',
                  ),
                ),
                ...UiTranscriptionConstants.textOutputOptions.map(
                  (String output) => FilterChip(
                    label: Text(_outputTypeLabel(context, output)),
                    selected:
                        pref.selectedTextOutputs.contains(output) ||
                        (stylingEnabled && output == 'ass'),
                    onSelected:
                        enabled && !controller.isTextOutputLocked(output)
                        ? (_) => controller.toggleTextOutput(output)
                        : null,
                    tooltip: output == 'ass'
                        ? _t(
                            context,
                            'Formato ASS recomendado quando a estilização visual estiver ativa.',
                            'ASS format is recommended when visual subtitle styling is enabled.',
                          )
                        : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            AnimatedOpacity(
              duration: const Duration(milliseconds: 180),
              opacity: stylingEnabled ? 1 : 0.85,
              child: Text(
                stylingEnabled
                    ? _t(
                        context,
                        'Com Estilização de Legenda ativa, o backend força ASS para preservar o visual no vídeo e nas trilhas.',
                        'With Subtitle Styling enabled, the backend forces ASS to preserve visual styling in video and subtitle tracks.',
                      )
                    : _t(
                        context,
                        'Você pode solicitar ASS manualmente ou deixar o backend forçar ASS quando a estilização visual estiver ativa.',
                        'You can request ASS manually or let the backend force ASS when visual styling is enabled.',
                      ),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: <Widget>[
                _dropdownField(
                  context: context,
                  width: 220,
                  label: _t(
                    context,
                    'Preset Visual da Legenda',
                    'Subtitle Visual Preset',
                  ),
                  value: pref.subtitleVisualPreset,
                  items: subtitlePresetOptions,
                  itemLabelBuilder: (value) => _presetLabel(context, value),
                  onChanged: enabled
                      ? controller.setSubtitleVisualPreset
                      : null,
                ),
                _dropdownField(
                  context: context,
                  width: 300,
                  label: _t(context, 'Entrega de Vídeo', 'Video Delivery'),
                  value: pref.videoDeliveryMode,
                  items: videoDeliveryOptions,
                  itemLabelBuilder: (value) =>
                      _videoDeliveryLabel(context, value),
                  onChanged: enabled ? controller.setVideoDeliveryMode : null,
                ),
                SizedBox(
                  width: 340,
                  child: _switchCard(
                    context,
                    title: _t(
                      context,
                      'Solicitar vídeo com legenda queimada',
                      'Request burned subtitle video',
                    ),
                    subtitle: multiTargetTranslate
                        ? _t(
                            context,
                            'Desativado automaticamente quando há tradução para múltiplos idiomas.',
                            'Automatically disabled when translating into multiple target languages.',
                          )
                        : _t(
                            context,
                            'Gera uma versão final do vídeo com a legenda embutida na imagem.',
                            'Generates a final video with subtitles burned into the picture.',
                          ),
                    value: pref.requestVideoBurned,
                    onChanged: enabled && !multiTargetTranslate
                        ? controller.setRequestVideoBurned
                        : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              _t(context, 'Idiomas de saída', 'Target languages'),
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            if (pref.task != 'translate')
              Text(
                _t(
                  context,
                  'Os idiomas de saída são usados quando a tarefa estiver em Traduzir.',
                  'Target languages are used when the task is set to Translate.',
                ),
                style: Theme.of(context).textTheme.bodyMedium,
              )
            else ...<Widget>[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: targetLanguageOptions.map((String language) {
                  return FilterChip(
                    label: Text(_languageLabel(context, language)),
                    selected: pref.targetLanguages.contains(language),
                    onSelected: enabled
                        ? (_) => controller.toggleTargetLanguage(language)
                        : null,
                  );
                }).toList(),
              ),
              const SizedBox(height: 8),
              Text(
                pref.targetLanguages.isEmpty
                    ? _t(
                        context,
                        'Nenhum idioma selecionado.',
                        'No target language selected.',
                      )
                    : _t(
                        context,
                        'Idiomas selecionados: ${pref.targetLanguages.map((code) => _languageLabel(context, code)).join(', ')}',
                        'Selected languages: ${pref.targetLanguages.map((code) => _languageLabel(context, code)).join(', ')}',
                      ),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCapabilitiesCard(
    BuildContext context,
    TranscriptionControllerState state,
  ) {
    final controller = ref.read(transcriptionControllerProvider.notifier);
    final capabilities = state.capabilities;
    if (capabilities == null) {
      return const SizedBox.shrink();
    }

    final hardware = capabilities.hardware;
    final recommended = capabilities.profiles[capabilities.recommendedProfile];
    final providerSummaries = capabilities.providers
        .map((provider) {
          final installed = provider.installedModels.join(', ');
          final downloadable = provider.downloadableModels.join(', ');
          return '${provider.label} [${provider.id}]'
              '${provider.available ? '' : ' • ${_t(context, 'indisponível', 'unavailable')}'}\n'
              '${_t(context, 'Instalados', 'Installed')}: ${installed.isEmpty ? _t(context, 'Nenhum', 'None') : installed}\n'
              '${_t(context, 'Baixáveis', 'Downloadable')}: ${downloadable.isEmpty ? _t(context, 'Nenhum', 'None') : downloadable}';
        })
        .join('\n\n');
    final projectRuntime = capabilities.projectRuntime;
    final hostRuntime = capabilities.hostRuntime;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(_cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _SectionHeader(
              title: _t(context, 'Capacidade do Sistema', 'System Capacity'),
              subtitle: _t(
                context,
                'Recursos detectados localmente e perfil sugerido para o pipeline de IA.',
                'Locally detected resources and suggested profile for the AI pipeline.',
              ),
              trailing: recommended == null
                  ? null
                  : FilledButton.icon(
                      onPressed: controller.applyRecommendedProfile,
                      icon: const Icon(Icons.auto_fix_high_outlined),
                      label: Text(_t(context, 'Aplicar Ideal', 'Apply Ideal')),
                    ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: <Widget>[
                _MiniPill(
                  label:
                      '${_t(context, 'Perfil recomendado', 'Recommended profile')}: ${_qualityProfileLabel(context, capabilities.recommendedProfile)}',
                ),
                _MiniPill(
                  label:
                      '${_t(context, 'Dispositivo', 'Device')}: ${hardware.device}',
                ),
                _MiniPill(
                  label:
                      '${_t(context, 'Compute', 'Compute')}: ${capabilities.computeTypeMode}',
                ),
                _MiniPill(
                  label:
                      '${_t(context, 'RAM livre', 'Free RAM')}: ${_formatBytes(context, hardware.ramAvailableBytes)}',
                ),
                if (capabilities.jobTimeoutMinutes != null)
                  _MiniPill(
                    label:
                        '${_t(context, 'Timeout do job', 'Job timeout')}: ${capabilities.jobTimeoutMinutes} min',
                  ),
                if (capabilities.structuredTimeoutSeconds != null)
                  _MiniPill(
                    label:
                        '${_t(context, 'Timeout estruturado', 'Structured timeout')}: ${capabilities.structuredTimeoutSeconds}s',
                  ),
                if (capabilities.styleTimeoutSeconds != null)
                  _MiniPill(
                    label:
                        '${_t(context, 'Timeout visual', 'Style timeout')}: ${capabilities.styleTimeoutSeconds}s',
                  ),
                if (hardware.advancedAlignmentAvailable)
                  _MiniPill(
                    label: _t(
                      context,
                      'Alinhamento avançado disponível',
                      'Advanced alignment available',
                    ),
                  ),
                if (capabilities.diarizationAvailable)
                  _MiniPill(
                    label: _t(
                      context,
                      'Diarização disponível',
                      'Diarization available',
                    ),
                  ),
                if (capabilities.voiceAnalysisAvailable)
                  _MiniPill(
                    label: _t(
                      context,
                      'Análise de vozes ativa',
                      'Voice analysis active',
                    ),
                  ),
                if (capabilities.sceneAnalysisAvailable)
                  _MiniPill(
                    label: _t(
                      context,
                      'Análise de cenas ativa',
                      'Scene analysis active',
                    ),
                  ),
                _MiniPill(
                  label:
                      '${_t(context, 'Karaokê máximo', 'Max karaoke')}: ${_karaokeGranularityLabel(context, capabilities.maxSupportedKaraokeGranularity)}',
                ),
              ],
            ),
            const SizedBox(height: 14),
            _DetailGrid(
              children: <_DetailField>[
                _DetailField(
                  label: _t(context, 'CPU', 'CPU'),
                  value:
                      '${hardware.cpuName} • ${hardware.physicalCores}/${hardware.logicalCores}',
                ),
                _DetailField(
                  label: _t(context, 'RAM Total', 'Total RAM'),
                  value: _formatBytes(context, hardware.ramTotalBytes),
                ),
                _DetailField(
                  label: _t(context, 'GPU(s)', 'GPU(s)'),
                  value: hardware.gpus.isEmpty
                      ? _t(context, 'Nenhuma detectada', 'None detected')
                      : hardware.gpus
                            .map(
                              (gpu) =>
                                  '${gpu.name}${gpu.memoryTotalBytes == null ? '' : ' (${_formatBytes(context, gpu.memoryTotalBytes)})'}',
                            )
                            .join('\n'),
                ),
                _DetailField(
                  label: _t(context, 'Perfis', 'Profiles'),
                  value: capabilities.profiles.values
                      .map(
                        (profile) =>
                            '${_qualityProfileLabel(context, profile.key)} • ${profile.aiRevisionPasses} ${_t(context, 'passes', 'passes')} • ${_alignmentModeLabel(context, profile.useAdvancedAlignment)} • ${_karaokeGranularityLabel(context, profile.maxSupportedKaraokeGranularity)}',
                      )
                      .join('\n'),
                ),
                _DetailField(
                  label: _t(context, 'Modelos instalados', 'Installed models'),
                  value: capabilities.installedModels.isEmpty
                      ? _t(context, 'Nenhum detectado', 'None detected')
                      : capabilities.installedModels.join('\n'),
                ),
                _DetailField(
                  label: _t(context, 'Runtime do Projeto', 'Project Runtime'),
                  value: projectRuntime == null
                      ? _t(context, 'N/D', 'N/A')
                      : '${projectRuntime.label} [${projectRuntime.id}]'
                            '${projectRuntime.baseUrl?.trim().isNotEmpty == true ? '\n${projectRuntime.baseUrl}' : ''}'
                            '${projectRuntime.modelStorePath?.trim().isNotEmpty == true ? '\n${projectRuntime.modelStorePath}' : ''}',
                ),
                _DetailField(
                  label: _t(context, 'Runtime do Host', 'Host Runtime'),
                  value: hostRuntime == null
                      ? _t(context, 'N/D', 'N/A')
                      : '${hostRuntime.label} [${hostRuntime.id}]'
                            '${hostRuntime.baseUrl?.trim().isNotEmpty == true ? '\n${hostRuntime.baseUrl}' : ''}'
                            '${hostRuntime.modelStorePath?.trim().isNotEmpty == true ? '\n${hostRuntime.modelStorePath}' : ''}',
                ),
                _DetailField(
                  label: _t(
                    context,
                    'Store de Modelos Ativo',
                    'Active Model Store',
                  ),
                  value:
                      capabilities.activeModelStorePath?.trim().isNotEmpty ==
                          true
                      ? capabilities.activeModelStorePath!
                      : _t(context, 'N/D', 'N/A'),
                ),
                _DetailField(
                  label: _t(context, 'Providers de IA', 'AI Providers'),
                  value: providerSummaries.trim().isEmpty
                      ? _t(context, 'Nenhum detectado', 'None detected')
                      : providerSummaries,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAiCard(
    BuildContext context,
    TranscriptionControllerState state,
    TranscriptionPreference pref,
    bool enabled,
    List<String> aiModelOptions,
  ) {
    final controller = ref.read(transcriptionControllerProvider.notifier);
    final aiEnabled = pref.aiEnhancementEnabled;
    final providerOptions =
        state.capabilities?.providers.map((provider) => provider.id).toList() ??
        (state.options?.aiProviders.isNotEmpty == true
            ? state.options!.aiProviders
            : UiTranscriptionConstants.aiProviders);
    final selectedProviderInfo = state.capabilities?.providerById(
      pref.aiProvider,
    );
    final installedAiModels = controller.installedAiModelsForProvider(
      pref.aiProvider,
    );
    final downloadableAiModels = controller
        .downloadableAiModelsForProvider(pref.aiProvider)
        .where((model) => !installedAiModels.contains(model))
        .toList();
    final selectedModelItems = <String>[
      ...installedAiModels,
      if (pref.aiModel.trim().isNotEmpty &&
          !installedAiModels.contains(pref.aiModel))
        pref.aiModel,
    ];
    final selectedModelInstalled = controller.isAiModelInstalled(
      pref.aiProvider,
      pref.aiModel,
    );
    final activeDownload = state.activeModelDownload;
    final hasDownloadForProvider =
        activeDownload != null && activeDownload.provider == pref.aiProvider;
    final qualityProfiles = state.options?.qualityProfiles.isNotEmpty == true
        ? state.options!.qualityProfiles
        : UiTranscriptionConstants.qualityProfiles;
    final alignmentModes = state.options?.alignmentModes.isNotEmpty == true
        ? state.options!.alignmentModes
        : UiTranscriptionConstants.alignmentModeOptions;
    final contentModes = state.options?.contentModes.isNotEmpty == true
        ? state.options!.contentModes
        : UiTranscriptionConstants.contentModes;
    final speakerStyleModes =
        state.options?.speakerStyleModes.isNotEmpty == true
        ? state.options!.speakerStyleModes
        : UiTranscriptionConstants.speakerStyleModes;
    final styleIntensities = state.options?.styleIntensities.isNotEmpty == true
        ? state.options!.styleIntensities
        : UiTranscriptionConstants.styleIntensities;
    final renderedPreviewModes =
        state.options?.renderedPreviewModes.isNotEmpty == true
        ? state.options!.renderedPreviewModes
        : UiTranscriptionConstants.renderedPreviewModes;
    final animeSongLayoutModes =
        state.options?.animeSongLayoutModes.isNotEmpty == true
        ? state.options!.animeSongLayoutModes
        : UiTranscriptionConstants.animeSongLayoutModes;
    final karaokeGranularities =
        state.options?.karaokeGranularities.isNotEmpty == true
        ? state.options!.karaokeGranularities
        : UiTranscriptionConstants.karaokeGranularities;
    final recommendedProfile = state.capabilities?.recommendedProfile;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(_cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _SectionHeader(
              title: _t(context, 'Camada de IA', 'AI Layer'),
              subtitle: _t(
                context,
                'Aplique correção, tradução semântica e estilização visual com o pipeline Ollama.',
                'Apply correction, semantic translation and visual subtitle styling using the Ollama pipeline.',
              ),
            ),
            const SizedBox(height: 16),
            _switchCard(
              context,
              title: _t(context, 'Ativar IA', 'Enable AI'),
              subtitle: _t(
                context,
                'Quando ativada, a pipeline de IA passa a complementar o ASR.',
                'When enabled, the AI pipeline complements the ASR output.',
              ),
              value: aiEnabled,
              onChanged: enabled ? controller.setAiEnhancementEnabled : null,
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: <Widget>[
                _dropdownField(
                  context: context,
                  width: 220,
                  label: _t(context, 'Provedor', 'Provider'),
                  value: pref.aiProvider,
                  items: providerOptions,
                  itemLabelBuilder: (value) {
                    final info = state.capabilities?.providerById(value);
                    if (info == null) return value;
                    return info.available
                        ? '${info.label} [${info.id}]'
                        : '${info.label} [${info.id}] • ${_t(context, 'indisponível', 'unavailable')}';
                  },
                  onChanged: enabled && aiEnabled
                      ? controller.setAiProvider
                      : null,
                ),
                _dropdownField(
                  context: context,
                  width: 340,
                  label: _t(context, 'Modelo de IA', 'AI Model'),
                  value: pref.aiModel,
                  items: selectedModelItems.isEmpty
                      ? aiModelOptions
                      : selectedModelItems,
                  itemLabelBuilder: (value) =>
                      controller.isAiModelInstalled(pref.aiProvider, value)
                      ? _aiModelLabel(context, value)
                      : '${_aiModelLabel(context, value)} • ${_t(context, 'não instalado', 'not installed')}',
                  onChanged: enabled && aiEnabled
                      ? controller.setAiModel
                      : null,
                ),
              ],
            ),
            if (aiEnabled) ...<Widget>[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  _MiniPill(
                    label:
                        '${_t(context, 'Runtime', 'Runtime')}: ${selectedProviderInfo?.label ?? pref.aiProvider}',
                  ),
                  if (selectedProviderInfo != null && !selectedProviderInfo.available)
                    _MiniPill(
                      label: _t(
                        context,
                        'Provider indisponível',
                        'Provider unavailable',
                      ),
                    ),
                  _MiniPill(
                    label:
                        '${_t(context, 'Status do modelo', 'Model status')}: ${selectedModelInstalled ? _t(context, 'Instalado', 'Installed') : _t(context, 'Pendente', 'Pending')}',
                  ),
                  if (selectedProviderInfo?.defaultModel?.trim().isNotEmpty ==
                      true)
                    _MiniPill(
                      label:
                          '${_t(context, 'Padrão do provider', 'Provider default')}: ${selectedProviderInfo!.defaultModel!}',
                    ),
                ],
              ),
              if (!selectedModelInstalled) ...<Widget>[
                const SizedBox(height: 12),
                Material(
                  color: Theme.of(context).colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(16),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Icon(
                          Icons.warning_amber_rounded,
                          color: Theme.of(context).colorScheme.onErrorContainer,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _t(
                              context,
                              'O modelo selecionado não está instalado no runtime ativo. A execução será bloqueada até o download concluir.',
                              'The selected model is not installed in the active runtime. Execution will be blocked until the download completes.',
                            ),
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onErrorContainer,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              if (hasDownloadForProvider) ...<Widget>[
                const SizedBox(height: 12),
                Material(
                  color: Theme.of(
                    context,
                  ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.28),
                  borderRadius: BorderRadius.circular(16),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          '${_t(context, 'Download em andamento', 'Download in progress')}: ${activeDownload!.model}',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 8),
                        LinearProgressIndicator(
                          value: activeDownload.progress.clamp(0, 100) / 100,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${activeDownload.progress}% • ${activeDownload.detail ?? activeDownload.status}',
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              if (downloadableAiModels.isNotEmpty) ...<Widget>[
                const SizedBox(height: 16),
                Text(
                  _t(
                    context,
                    'Modelos disponíveis para baixar',
                    'Models available to download',
                  ),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: downloadableAiModels.map((model) {
                    final downloadingThisModel =
                        activeDownload != null &&
                        activeDownload.provider == pref.aiProvider &&
                        activeDownload.model == model &&
                        !activeDownload.isTerminal;
                    return ActionChip(
                      avatar: Icon(
                        downloadingThisModel
                            ? Icons.downloading_outlined
                            : Icons.download_outlined,
                        size: 18,
                      ),
                      label: Text(_aiModelLabel(context, model)),
                      onPressed: enabled && aiEnabled && !state.isDownloading
                          ? () => controller.downloadAiModel(
                              provider: pref.aiProvider,
                              model: model,
                            )
                          : null,
                    );
                  }).toList(),
                ),
              ],
            ],
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: <Widget>[
                _dropdownField(
                  context: context,
                  width: 220,
                  label: _t(context, 'Conteúdo', 'Content'),
                  value: pref.contentMode,
                  items: contentModes,
                  itemLabelBuilder: (value) =>
                      _contentModeLabel(context, value),
                  onChanged: enabled && aiEnabled
                      ? controller.setContentMode
                      : null,
                ),
                _dropdownField(
                  context: context,
                  width: 220,
                  label: _t(context, 'Perfil de Qualidade', 'Quality Profile'),
                  value: pref.qualityProfile,
                  items: qualityProfiles,
                  itemLabelBuilder: (value) =>
                      _qualityProfileLabel(context, value),
                  onChanged: enabled && aiEnabled
                      ? controller.setQualityProfile
                      : null,
                ),
                _dropdownField(
                  context: context,
                  width: 220,
                  label: _t(context, 'Alinhamento', 'Alignment'),
                  value: pref.useAdvancedAlignment,
                  items: alignmentModes,
                  itemLabelBuilder: (value) =>
                      _alignmentModeLabel(context, value),
                  onChanged: enabled && aiEnabled
                      ? controller.setUseAdvancedAlignment
                      : null,
                ),
                _dropdownField(
                  context: context,
                  width: 220,
                  label: _t(context, 'Passes de Revisão', 'Review Passes'),
                  value: pref.aiRevisionPasses.toString(),
                  items: List<String>.generate(11, (index) => '$index'),
                  itemLabelBuilder: (value) => value,
                  onChanged: enabled && aiEnabled
                      ? (value) => controller.setAiRevisionPasses(
                          int.tryParse(value) ?? 0,
                        )
                      : null,
                ),
                if (recommendedProfile != null)
                  _MiniPill(
                    label:
                        '${_t(context, 'Ideal', 'Ideal')}: ${_qualityProfileLabel(context, recommendedProfile)}',
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: <Widget>[
                _dropdownField(
                  context: context,
                  width: 220,
                  label: _t(context, 'Separação de vozes', 'Speaker Styling'),
                  value: pref.speakerStyleMode,
                  items: speakerStyleModes,
                  itemLabelBuilder: (value) =>
                      _speakerStyleModeLabel(context, value),
                  onChanged: enabled && aiEnabled
                      ? controller.setSpeakerStyleMode
                      : null,
                ),
                _dropdownField(
                  context: context,
                  width: 220,
                  label: _t(context, 'Intensidade Visual', 'Style Intensity'),
                  value: pref.styleIntensity,
                  items: styleIntensities,
                  itemLabelBuilder: (value) =>
                      _styleIntensityLabel(context, value),
                  onChanged: enabled && aiEnabled
                      ? controller.setStyleIntensity
                      : null,
                ),
                _dropdownField(
                  context: context,
                  width: 220,
                  label: _t(context, 'Preview', 'Preview'),
                  value: pref.renderedPreviewMode,
                  items: renderedPreviewModes,
                  itemLabelBuilder: (value) =>
                      _previewModeLabel(context, value),
                  onChanged: enabled ? controller.setRenderedPreviewMode : null,
                ),
                _dropdownField(
                  context: context,
                  width: 320,
                  label: _t(context, 'Layout Anime Song', 'Anime Song Layout'),
                  value: pref.animeSongLayoutMode,
                  items: animeSongLayoutModes,
                  itemLabelBuilder: (value) =>
                      _animeSongLayoutLabel(context, value),
                  onChanged: enabled && aiEnabled
                      ? controller.setAnimeSongLayoutMode
                      : null,
                ),
                _dropdownField(
                  context: context,
                  width: 220,
                  label: _t(context, 'Karaokê', 'Karaoke'),
                  value: pref.karaokeGranularity,
                  items: karaokeGranularities,
                  itemLabelBuilder: (value) =>
                      _karaokeGranularityLabel(context, value),
                  onChanged: enabled && aiEnabled
                      ? controller.setKaraokeGranularity
                      : null,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              _t(context, 'Etapas de IA', 'AI stages'),
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: UiTranscriptionConstants.aiModes.map((String mode) {
                return FilterChip(
                  label: Text(_aiModeLabel(context, mode)),
                  selected: controller.selectedAiModes.contains(mode),
                  onSelected: enabled && aiEnabled
                      ? (_) => controller.toggleAiMode(mode)
                      : null,
                );
              }).toList(),
            ),
            const SizedBox(height: 8),
            Text(
              _t(
                context,
                'Ordem efetiva do pipeline: ${controller.selectedAiModes.map((mode) => _aiModeLabel(context, mode)).join(' → ')}',
                'Effective pipeline order: ${controller.selectedAiModes.map((mode) => _aiModeLabel(context, mode)).join(' → ')}',
              ),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            Tooltip(
              waitDuration: _tooltipWaitDuration,
              message: _t(
                context,
                'Instruções adicionais para a IA. Use este campo para orientar tom, prioridade semântica, estilo visual, tratamento de nomes, linguagem formal ou informal e detalhes desejados na legenda.',
                'Additional instructions for the AI. Use this field to guide tone, semantic priority, visual style, name handling, formality level and subtitle details.',
              ),
              child: TextField(
                controller: _aiPromptController,
                focusNode: _aiPromptFocusNode,
                enabled: enabled && aiEnabled,
                maxLines: 6,
                minLines: 4,
                onChanged: controller.setAiPrompt,
                decoration: InputDecoration(
                  labelText: _t(
                    context,
                    'Prompt do Usuário para a IA',
                    'User Prompt for AI',
                  ),
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: <Widget>[
                _numberField(
                  context: context,
                  width: 240,
                  label: _t(context, 'Máx. Tokens da IA', 'AI Max Tokens'),
                  controller: _aiMaxTokensController,
                  focusNode: _aiMaxTokensFocusNode,
                  tooltip: _t(
                    context,
                    'Limita o tamanho máximo da resposta da IA por chamada. Valores maiores tendem a permitir respostas mais completas, mas aumentam custo, tempo e risco de instabilidade.',
                    'Limits the maximum response size per AI call. Larger values usually allow more complete answers, but increase cost, latency and instability risk.',
                  ),
                  onChanged: enabled && aiEnabled
                      ? (value) {
                          final parsed = _parseNullableInt(value);
                          if (parsed != null) {
                            controller.setAiMaxTokens(parsed);
                          }
                        }
                      : null,
                ),
                _numberField(
                  context: context,
                  width: 240,
                  label: _t(context, 'Chars por Bloco da IA', 'AI Chunk Chars'),
                  controller: _aiChunkCharsController,
                  focusNode: _aiChunkCharsFocusNode,
                  tooltip: _t(
                    context,
                    'Define o tamanho do bloco textual enviado para a IA por iteração. Valores maiores reduzem o número de chamadas, mas exigem mais contexto do modelo.',
                    'Defines the text chunk size sent to the AI per iteration. Larger values reduce the number of calls, but require more model context.',
                  ),
                  onChanged: enabled && aiEnabled
                      ? (value) {
                          final parsed = _parseNullableInt(value);
                          if (parsed != null) {
                            controller.setAiChunkChars(parsed);
                          }
                        }
                      : null,
                ),
                _numberField(
                  context: context,
                  width: 240,
                  label: _t(
                    context,
                    'Amostragem Visual (s)',
                    'Visual Sampling (s)',
                  ),
                  controller: _aiFrameSampleSecondsController,
                  focusNode: _aiFrameSampleSecondsFocusNode,
                  tooltip: _t(
                    context,
                    'Intervalo, em segundos, entre frames extraídos quando o contexto visual estiver ativado. Valores menores aumentam a fidelidade visual e o tempo de processamento.',
                    'Interval, in seconds, between extracted frames when visual context is enabled. Lower values improve visual fidelity and also increase processing time.',
                  ),
                  onChanged: enabled && aiEnabled
                      ? (value) {
                          final parsed = _parseNullableInt(value);
                          if (parsed != null) {
                            controller.setAiFrameSampleSeconds(parsed);
                          }
                        }
                      : null,
                ),
              ],
            ),
            const SizedBox(height: 16),
            _sliderField(
              context: context,
              label: _t(context, 'Temperatura', 'Temperature'),
              value: pref.aiTemperature,
              min: 0,
              max: 2,
              divisions: 20,
              valueLabel: pref.aiTemperature.toStringAsFixed(2),
              tooltip: _t(
                context,
                'Controla o nível de criatividade da IA. Valores baixos favorecem consistência e previsibilidade; valores mais altos aumentam variedade, mas também o risco de deriva.',
                'Controls the AI creativity level. Lower values favor consistency and predictability; higher values increase variety, but also the risk of drift.',
              ),
              onChanged: enabled && aiEnabled
                  ? controller.setAiTemperature
                  : null,
            ),
            const SizedBox(height: 8),
            _sliderField(
              context: context,
              label: 'Top P',
              value: pref.aiTopP,
              min: 0,
              max: 1,
              divisions: 20,
              valueLabel: pref.aiTopP.toStringAsFixed(2),
              tooltip: _t(
                context,
                'Restringe a massa de probabilidade considerada pelo modelo. Normalmente é ajustado junto com a temperatura para equilibrar precisão e diversidade.',
                'Restricts the probability mass considered by the model. It is typically tuned together with temperature to balance accuracy and diversity.',
              ),
              onChanged: enabled && aiEnabled ? controller.setAiTopP : null,
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: <Widget>[
                _switchCard(
                  context,
                  title: _t(
                    context,
                    'Usar Contexto Visual',
                    'Use Visual Context',
                  ),
                  subtitle: _t(
                    context,
                    'Extrai frames do vídeo para orientar correção, tradução e estilo visual.',
                    'Extracts video frames to guide correction, translation and visual styling.',
                  ),
                  value: pref.aiUseVisualContext,
                  onChanged: enabled && aiEnabled
                      ? controller.setAiUseVisualContext
                      : null,
                ),
                _switchCard(
                  context,
                  title: _t(
                    context,
                    'Preservar Timestamps',
                    'Preserve Timestamps',
                  ),
                  subtitle: _t(
                    context,
                    'Mantém a estrutura temporal original sempre que possível durante o pós-processamento.',
                    'Keeps the original timing structure whenever possible during post-processing.',
                  ),
                  value: pref.preserveTimestamps,
                  onChanged: enabled && aiEnabled
                      ? controller.setPreserveTimestamps
                      : null,
                ),
                _switchCard(
                  context,
                  title: _t(context, 'Contexto Online', 'Online Context'),
                  subtitle: _t(
                    context,
                    'Quando ativado, usa URLs e contexto fornecido pelo usuário para revisão e correção.',
                    'When enabled, uses user-provided URLs and context for review and correction.',
                  ),
                  value: pref.enableOnlineContext,
                  onChanged: enabled && aiEnabled
                      ? controller.setEnableOnlineContext
                      : null,
                ),
              ],
            ),
            if (pref.enableOnlineContext) ...<Widget>[
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: <Widget>[
                  _textField(
                    context: context,
                    width: 250,
                    label: _t(context, 'Título', 'Title'),
                    controller: _contextTitleController,
                    focusNode: _contextTitleFocusNode,
                    enabled: enabled && aiEnabled,
                    onChanged: (_) => _updateContextHintsFromFields(controller),
                  ),
                  _textField(
                    context: context,
                    width: 250,
                    label: _t(context, 'Artista', 'Artist'),
                    controller: _contextArtistController,
                    focusNode: _contextArtistFocusNode,
                    enabled: enabled && aiEnabled,
                    onChanged: (_) => _updateContextHintsFromFields(controller),
                  ),
                  _textField(
                    context: context,
                    width: 250,
                    label: _t(context, 'Série', 'Series'),
                    controller: _contextSeriesController,
                    focusNode: _contextSeriesFocusNode,
                    enabled: enabled && aiEnabled,
                    onChanged: (_) => _updateContextHintsFromFields(controller),
                  ),
                  _textField(
                    context: context,
                    width: 250,
                    label: _t(context, 'Episódio', 'Episode'),
                    controller: _contextEpisodeController,
                    focusNode: _contextEpisodeFocusNode,
                    enabled: enabled && aiEnabled,
                    onChanged: (_) => _updateContextHintsFromFields(controller),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _textField(
                context: context,
                width: double.infinity,
                label: _t(context, 'URLs de Referência', 'Reference URLs'),
                controller: _contextUrlsController,
                focusNode: _contextUrlsFocusNode,
                enabled: enabled && aiEnabled,
                maxLines: 4,
                onChanged: (_) => _updateContextHintsFromFields(controller),
                helperText: _t(
                  context,
                  'Uma URL por linha. Use apenas fontes oficiais ou curadas.',
                  'One URL per line. Use only official or curated sources.',
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFooterActions(
    BuildContext context,
    TranscriptionControllerState state,
  ) {
    final controller = ref.read(transcriptionControllerProvider.notifier);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(_cardPadding),
        child: Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            FilledButton.icon(
              onPressed: state.isSavingPreferences
                  ? null
                  : controller.savePreferences,
              icon: state.isSavingPreferences
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: Text(
                _t(context, 'Salvar Preferências', 'Save Preferences'),
              ),
            ),
            OutlinedButton.icon(
              onPressed: state.isResettingPreferences
                  ? null
                  : controller.resetPreferences,
              icon: state.isResettingPreferences
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.restart_alt_outlined),
              label: Text(
                _t(context, 'Restaurar Padrões', 'Reset to Defaults'),
              ),
            ),
            OutlinedButton.icon(
              onPressed: state.isRefreshingJobs ? null : controller.refreshJobs,
              icon: state.isRefreshingJobs
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.history_outlined),
              label: Text(_t(context, 'Atualizar Execuções', 'Refresh Runs')),
            ),
            if (state.lastUpdatedAt != null)
              Text(
                _t(
                  context,
                  'Atualizado em ${_formatDate(context, state.lastUpdatedAt)}',
                  'Updated at ${_formatDate(context, state.lastUpdatedAt)}',
                ),
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildJobsPane(
    BuildContext context,
    TranscriptionControllerState state, {
    bool fixedSplit = false,
  }) {
    final controller = ref.read(transcriptionControllerProvider.notifier);

    final recentRunsCard = Card(
      child: Padding(
        padding: const EdgeInsets.all(_cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _SectionHeader(
              title: _t(context, 'Execuções Recentes', 'Recent Runs'),
              subtitle: _t(
                context,
                'Selecione uma execução para ver detalhes e outputs gerados.',
                'Select a run to inspect details and generated outputs.',
              ),
              trailing: IconButton(
                tooltip: _t(context, 'Atualizar execuções', 'Refresh runs'),
                onPressed: state.isRefreshingJobs
                    ? null
                    : controller.refreshJobs,
                icon: state.isRefreshingJobs
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh),
              ),
            ),
            const SizedBox(height: 12),
            if (!state.hasJobs)
              Text(
                _t(
                  context,
                  'Nenhuma execução encontrada.',
                  'No runs were found.',
                ),
              )
            else
              Expanded(
                child: ListView.separated(
                  itemCount: state.jobs.length,
                  itemBuilder: (BuildContext context, int index) {
                    final job = state.jobs[index];
                    final bool selected = state.selectedJobId == job.id;
                    final Color statusColor = _statusColor(context, job.status);

                    return _AnimatedEntrance(
                      delay: Duration(milliseconds: 45 * (index % 6)),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(18),
                        onTap: () => controller.selectJob(job.id),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: selected
                                  ? statusColor.withValues(alpha: 0.95)
                                  : Theme.of(context).dividerColor,
                            ),
                            color: selected
                                ? statusColor.withValues(alpha: 0.08)
                                : Theme.of(context).colorScheme.surface,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Expanded(
                                    child: Text(
                                      _safeJobTitle(job),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  _StatusBadge(
                                    label: _statusLabel(context, job.status),
                                    color: statusColor,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Text(
                                '${_t(context, 'Modelo', 'Model')}: ${job.model} • ${_t(context, 'Tarefa', 'Task')}: ${_taskLabel(context, job.task)}',
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                              const SizedBox(height: 8),
                              LinearProgressIndicator(
                                value: job.progressPercent.clamp(0, 100) / 100,
                                minHeight: 4,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '${_t(context, 'Progresso', 'Progress')}: ${job.progressPercent}% • ${_t(context, 'Criado em', 'Created at')}: ${_formatDate(context, job.createdAtUtc)}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                  separatorBuilder: (BuildContext context, int index) =>
                      const SizedBox(height: 10),
                ),
              ),
          ],
        ),
      ),
    );

    final detailsCard = Card(
      child: Padding(
        padding: const EdgeInsets.all(_cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _SectionHeader(
              title: _t(context, 'Detalhes da Execução', 'Run Details'),
              subtitle: _t(
                context,
                'Resumo técnico da execução selecionada e seus outputs.',
                'Technical summary of the selected run and its outputs.',
              ),
              trailing: IconButton(
                tooltip: _t(context, 'Atualizar detalhes', 'Refresh details'),
                onPressed: state.isRefreshingSelectedJob
                    ? null
                    : () => controller.refreshSelectedJob(),
                icon: state.isRefreshingSelectedJob
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh),
              ),
            ),
            const SizedBox(height: 12),
            if (state.selectedJob == null)
              Text(
                _t(
                  context,
                  'Selecione uma execução para visualizar os detalhes.',
                  'Select a run to inspect the details.',
                ),
              )
            else
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 260),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  child: SingleChildScrollView(
                    key: ValueKey<String>(state.selectedJob!.id),
                    child: _AnimatedEntrance(
                      triggerKey: state.selectedJob!.id,
                      child: _SelectedJobDetails(
                        context: context,
                        detail: state.selectedJob!,
                        formatDate: _formatDate,
                        durationLabel: _durationLabel,
                        languageLabel: _languageLabel,
                        taskLabel: _taskLabel,
                        outputTypeLabel: _outputTypeLabel,
                        videoDeliveryLabel: _videoDeliveryLabel,
                        aiModeLabel: _aiModeLabel,
                        qualityProfileLabel: _qualityProfileLabel,
                        contentModeLabel: _contentModeLabel,
                        speakerStyleModeLabel: _speakerStyleModeLabel,
                        styleIntensityLabel: _styleIntensityLabel,
                        previewModeLabel: _previewModeLabel,
                        animeSongLayoutLabel: _animeSongLayoutLabel,
                        karaokeGranularityLabel: _karaokeGranularityLabel,
                        currentStageLabel: _currentStageLabel,
                        statusLabel: _statusLabel,
                        statusColor: _statusColor,
                        onPreview: _openPreview,
                        onCopyLink: _copyOutputLink,
                        onDownload: (output) =>
                            controller.downloadOutput(output),
                        t: _t,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );

    if (fixedSplit) {
      return Column(
        children: <Widget>[
          Expanded(flex: 5, child: recentRunsCard),
          const SizedBox(height: 14),
          Expanded(flex: 6, child: detailsCard),
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SizedBox(height: 420, child: recentRunsCard),
        const SizedBox(height: 14),
        SizedBox(height: 560, child: detailsCard),
      ],
    );
  }

  Widget _dropdownField({
    required BuildContext context,
    required double width,
    required String label,
    required String value,
    required List<String> items,
    required String Function(String) itemLabelBuilder,
    required ValueChanged<String>? onChanged,
  }) {
    final effectiveValue = items.contains(value)
        ? value
        : (items.isNotEmpty ? items.first : value);

    return SizedBox(
      width: width,
      child: DropdownButtonFormField<String>(
        key: ValueKey<String>('dropdown-$label-$effectiveValue'),
        isExpanded: true,
        initialValue: effectiveValue,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        items: items
            .map(
              (item) => DropdownMenuItem<String>(
                value: item,
                child: Text(
                  itemLabelBuilder(item),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            )
            .toList(),
        onChanged: onChanged == null
            ? null
            : (value) {
                if (value != null) {
                  onChanged(value);
                }
              },
      ),
    );
  }

  Widget _numberField({
    required BuildContext context,
    required double width,
    required String label,
    required TextEditingController controller,
    required FocusNode focusNode,
    required ValueChanged<String>? onChanged,
    String? tooltip,
  }) {
    final child = SizedBox(
      width: width,
      child: TextFormField(
        controller: controller,
        focusNode: focusNode,
        enabled: onChanged != null,
        keyboardType: TextInputType.number,
        inputFormatters: <TextInputFormatter>[
          FilteringTextInputFormatter.allow(RegExp(r'[0-9]')),
        ],
        onChanged: onChanged,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
      ),
    );

    if (tooltip == null || tooltip.trim().isEmpty) {
      return child;
    }

    return Tooltip(
      waitDuration: _tooltipWaitDuration,
      message: tooltip,
      child: child,
    );
  }

  Widget _textField({
    required BuildContext context,
    required double width,
    required String label,
    required TextEditingController controller,
    required FocusNode focusNode,
    required bool enabled,
    required ValueChanged<String> onChanged,
    int maxLines = 1,
    String? helperText,
  }) {
    return SizedBox(
      width: width,
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        enabled: enabled,
        maxLines: maxLines,
        onChanged: onChanged,
        decoration: InputDecoration(
          labelText: label,
          helperText: helperText,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  Widget _sliderField({
    required BuildContext context,
    required String label,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String valueLabel,
    required String tooltip,
    required ValueChanged<double>? onChanged,
  }) {
    final normalizedValue = value.clamp(min, max).toDouble();

    return Tooltip(
      waitDuration: _tooltipWaitDuration,
      message: tooltip,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(label, style: Theme.of(context).textTheme.titleSmall),
          Row(
            children: <Widget>[
              Expanded(
                child: Slider(
                  value: normalizedValue,
                  min: min,
                  max: max,
                  divisions: divisions,
                  label: valueLabel,
                  onChanged: onChanged,
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 52,
                child: Text(
                  valueLabel,
                  textAlign: TextAlign.end,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _switchCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool>? onChanged,
  }) {
    return SizedBox(
      width: 292,
      child: Material(
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(title, style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Switch(value: value, onChanged: onChanged),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.subtitle,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(title, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 6),
            Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    ];

    if (trailing != null) {
      children.add(trailing!);
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }
}

class _SummaryTile {
  const _SummaryTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.accent,
  });

  final IconData icon;
  final String title;
  final String value;
  final Color accent;
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(
          label,
          style: TextStyle(color: color, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

class _SelectedJobDetails extends StatelessWidget {
  const _SelectedJobDetails({
    required this.context,
    required this.detail,
    required this.formatDate,
    required this.durationLabel,
    required this.languageLabel,
    required this.taskLabel,
    required this.outputTypeLabel,
    required this.videoDeliveryLabel,
    required this.aiModeLabel,
    required this.qualityProfileLabel,
    required this.contentModeLabel,
    required this.speakerStyleModeLabel,
    required this.styleIntensityLabel,
    required this.previewModeLabel,
    required this.animeSongLayoutLabel,
    required this.karaokeGranularityLabel,
    required this.currentStageLabel,
    required this.statusLabel,
    required this.statusColor,
    required this.onPreview,
    required this.onCopyLink,
    required this.onDownload,
    required this.t,
  });

  final BuildContext context;
  final TranscriptionJobDetail detail;
  final String Function(BuildContext, DateTime?) formatDate;
  final String Function(BuildContext, double?) durationLabel;
  final String Function(BuildContext, String) languageLabel;
  final String Function(BuildContext, String) taskLabel;
  final String Function(BuildContext, String) outputTypeLabel;
  final String Function(BuildContext, String) videoDeliveryLabel;
  final String Function(BuildContext, String) aiModeLabel;
  final String Function(BuildContext, String) qualityProfileLabel;
  final String Function(BuildContext, String) contentModeLabel;
  final String Function(BuildContext, String) speakerStyleModeLabel;
  final String Function(BuildContext, String) styleIntensityLabel;
  final String Function(BuildContext, String) previewModeLabel;
  final String Function(BuildContext, String) animeSongLayoutLabel;
  final String Function(BuildContext, String) karaokeGranularityLabel;
  final String Function(BuildContext, String?) currentStageLabel;
  final String Function(BuildContext, String) statusLabel;
  final Color Function(BuildContext, String) statusColor;
  final Future<void> Function(TranscriptionOutput) onPreview;
  final Future<void> Function(TranscriptionOutput) onCopyLink;
  final Future<String?> Function(TranscriptionOutput) onDownload;
  final String Function(BuildContext, String, String) t;

  @override
  Widget build(BuildContext context) {
    final Color status = statusColor(context, detail.status);
    List<String> readStringList(dynamic value) {
      if (value is List) {
        return value
            .map((item) => item.toString().trim())
            .where((item) => item.isNotEmpty)
            .toList();
      }
      return const <String>[];
    }

    final publishedLanguages = readStringList(
      detail.qualitySummary?['publishedLanguages'],
    );
    final failedLanguages = readStringList(
      detail.qualitySummary?['failedLanguages'],
    );
    final fallbackLabels = detail.fallbacks
        .map(
          (item) =>
              item['fallbackUsed']?.toString() ??
              item['message']?.toString() ??
              '',
        )
        .where((item) => item.trim().isNotEmpty)
        .toList();
    final musicalDurations = detail.musicalSegmentDurations.map((item) {
      final title = item['title']?.toString();
      final type = item['type']?.toString();
      final duration = durationLabel(
        context,
        (item['durationSeconds'] as num?)?.toDouble(),
      );
      final prefix = title?.trim().isNotEmpty == true
          ? title!.trim()
          : (type?.trim().isNotEmpty == true
                ? type!.trim()
                : t(context, 'Bloco musical', 'Song block'));
      return '$prefix • $duration';
    }).toList();
    final String? styleSourceLabel = switch ((detail.styleSource ?? '')
        .trim()) {
      'ai_plan' => t(context, 'Estilo por IA', 'AI styling'),
      'local_preset' => t(context, 'Preset local', 'Local preset'),
      _ => null,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            _StatusBadge(
              label: statusLabel(context, detail.status),
              color: status,
            ),
            _MiniPill(label: '${detail.progressPercent}%'),
            if ((detail.currentStage ?? '').trim().isNotEmpty)
              _MiniPill(label: currentStageLabel(context, detail.currentStage)),
            if ((detail.totalPasses ?? 0) > 0)
              _MiniPill(
                label:
                    '${t(context, 'Passe', 'Pass')} ${detail.currentPass ?? 0}/${detail.totalPasses}',
              ),
            _MiniPill(label: taskLabel(context, detail.task)),
            _MiniPill(
              label: languageLabel(
                context,
                detail.languageDetected ?? detail.language,
              ),
            ),
            if (detail.sourceDurationSeconds != null ||
                detail.durationSeconds != null)
              _MiniPill(
                label:
                    '${t(context, 'Fonte', 'Source')}: ${durationLabel(context, detail.sourceDurationSeconds ?? detail.durationSeconds)}',
              ),
            if (detail.outputDurationSeconds != null)
              _MiniPill(
                label:
                    '${t(context, 'Output', 'Output')}: ${durationLabel(context, detail.outputDurationSeconds)}',
              ),
            if (styleSourceLabel != null) _MiniPill(label: styleSourceLabel),
          ],
        ),
        const SizedBox(height: 14),
        _DetailGrid(
          children: <_DetailField>[
            _DetailField(
              label: t(context, 'Fonte', 'Source'),
              value: detail.sourceValue,
            ),
            _DetailField(
              label: t(context, 'Modelo de ASR', 'ASR Model'),
              value: detail.model,
            ),
            _DetailField(
              label: t(context, 'Tarefa', 'Task'),
              value: taskLabel(context, detail.task),
            ),
            _DetailField(
              label: t(context, 'Idioma de Entrada', 'Input Language'),
              value: languageLabel(context, detail.language),
            ),
            _DetailField(
              label: t(context, 'Idiomas de Saída', 'Target Languages'),
              value: detail.targetLanguages.isEmpty
                  ? t(context, 'Nenhum', 'None')
                  : detail.targetLanguages
                        .map((code) => languageLabel(context, code))
                        .join(', '),
            ),
            _DetailField(
              label: t(context, 'Outputs Solicitados', 'Requested Outputs'),
              value: detail.requestedOutputs.isEmpty
                  ? t(context, 'Nenhum', 'None')
                  : detail.requestedOutputs
                        .map((e) => outputTypeLabel(context, e))
                        .join(', '),
            ),
            _DetailField(
              label: t(context, 'Entrega de Vídeo', 'Video Delivery'),
              value: videoDeliveryLabel(context, detail.videoDeliveryMode),
            ),
            _DetailField(
              label: t(context, 'Perfil de Qualidade', 'Quality Profile'),
              value: qualityProfileLabel(context, detail.qualityProfile),
            ),
            _DetailField(
              label: t(context, 'Conteúdo', 'Content'),
              value: contentModeLabel(context, detail.contentMode),
            ),
            _DetailField(
              label: t(context, 'Alinhamento', 'Alignment'),
              value: detail.useAdvancedAlignment,
            ),
            _DetailField(
              label: t(context, 'Separação de vozes', 'Speaker Styling'),
              value: speakerStyleModeLabel(context, detail.speakerStyleMode),
            ),
            _DetailField(
              label: t(context, 'Intensidade Visual', 'Style Intensity'),
              value: styleIntensityLabel(context, detail.styleIntensity),
            ),
            _DetailField(
              label: t(context, 'Preview', 'Preview'),
              value: previewModeLabel(context, detail.renderedPreviewMode),
            ),
            _DetailField(
              label: t(context, 'Layout Anime Song', 'Anime Song Layout'),
              value: animeSongLayoutLabel(context, detail.animeSongLayoutMode),
            ),
            _DetailField(
              label: t(context, 'Karaokê', 'Karaoke'),
              value: karaokeGranularityLabel(
                context,
                detail.karaokeGranularity,
              ),
            ),
            _DetailField(
              label: t(context, 'Passes de Revisão', 'Review Passes'),
              value: detail.aiRevisionPasses.toString(),
            ),
            _DetailField(
              label: t(context, 'Modelo de IA', 'AI Model'),
              value: detail.aiEnhancementEnabled
                  ? detail.aiModel
                  : t(context, 'Desativado', 'Disabled'),
            ),
            _DetailField(
              label: t(context, 'Provider solicitado', 'Requested Provider'),
              value: detail.requestedAiProvider ?? t(context, 'N/D', 'N/A'),
            ),
            _DetailField(
              label: t(context, 'Modelo solicitado', 'Requested Model'),
              value: detail.requestedAiModel ?? t(context, 'N/D', 'N/A'),
            ),
            _DetailField(
              label: t(context, 'Provider executado', 'Effective Provider'),
              value: detail.effectiveAiProvider ?? t(context, 'N/D', 'N/A'),
            ),
            _DetailField(
              label: t(context, 'Modelo executado', 'Effective Model'),
              value: detail.effectiveAiModel ?? t(context, 'N/D', 'N/A'),
            ),
            _DetailField(
              label: t(context, 'Runtime executado', 'Runtime Target'),
              value: detail.runtimeTarget ?? t(context, 'N/D', 'N/A'),
            ),
            _DetailField(
              label: t(
                context,
                'Instalado na submissão',
                'Installed at submission',
              ),
              value: detail.modelInstalledAtSubmission == null
                  ? t(context, 'N/D', 'N/A')
                  : (detail.modelInstalledAtSubmission!
                        ? t(context, 'Sim', 'Yes')
                        : t(context, 'Não', 'No')),
            ),
            _DetailField(
              label: t(context, 'Fallbacks', 'Fallbacks'),
              value: fallbackLabels.isEmpty
                  ? t(context, 'Nenhum', 'None')
                  : fallbackLabels.join('\n'),
            ),
            _DetailField(
              label: t(context, 'Duração da Fonte', 'Source Duration'),
              value: durationLabel(
                context,
                detail.sourceDurationSeconds ?? detail.durationSeconds,
              ),
            ),
            _DetailField(
              label: t(context, 'Duração do Output', 'Output Duration'),
              value: durationLabel(context, detail.outputDurationSeconds),
            ),
            _DetailField(
              label: t(
                context,
                'Blocos Musicais Detectados',
                'Detected Musical Segments',
              ),
              value: musicalDurations.isEmpty
                  ? t(context, 'Nenhum', 'None')
                  : musicalDurations.join('\n'),
            ),
            _DetailField(
              label: t(context, 'Modos de IA', 'AI Modes'),
              value:
                  detail.aiMode
                      .split(',')
                      .map((e) => e.trim())
                      .where((e) => e.isNotEmpty)
                      .map((e) => aiModeLabel(context, e))
                      .join(' → ')
                      .trim()
                      .isEmpty
                  ? t(context, 'Nenhum', 'None')
                  : detail.aiMode
                        .split(',')
                        .map((e) => e.trim())
                        .where((e) => e.isNotEmpty)
                        .map((e) => aiModeLabel(context, e))
                        .join(' → '),
            ),
            _DetailField(
              label: t(context, 'Etapa Atual', 'Current Stage'),
              value: currentStageLabel(context, detail.currentStage),
            ),
            _DetailField(
              label: t(context, 'Conteúdo Detectado', 'Detected Content'),
              value: detail.detectedContentType == null
                  ? t(context, 'N/D', 'N/A')
                  : contentModeLabel(context, detail.detectedContentType!),
            ),
            _DetailField(
              label: t(
                context,
                'Confiança da Detecção',
                'Detection Confidence',
              ),
              value: detail.contentDetectionConfidence == null
                  ? t(context, 'N/D', 'N/A')
                  : '${(detail.contentDetectionConfidence! * 100).toStringAsFixed(0)}%',
            ),
            _DetailField(
              label: t(context, 'Modo de Voz Aplicado', 'Applied Speaker Mode'),
              value: detail.speakerModeApplied == null
                  ? t(context, 'N/D', 'N/A')
                  : speakerStyleModeLabel(context, detail.speakerModeApplied!),
            ),
            _DetailField(
              label: t(context, 'Karaokê Aplicado', 'Applied Karaoke'),
              value: detail.karaokeModeApplied == null
                  ? t(context, 'N/D', 'N/A')
                  : karaokeGranularityLabel(
                      context,
                      detail.karaokeModeApplied!,
                    ),
            ),
            _DetailField(
              label: t(context, 'Preview Aplicado', 'Applied Preview'),
              value: detail.previewModeApplied == null
                  ? t(context, 'N/D', 'N/A')
                  : previewModeLabel(context, detail.previewModeApplied!),
            ),
            _DetailField(
              label: t(context, 'Perfil de Timeout', 'Timeout Profile'),
              value: detail.timeoutProfileApplied ?? t(context, 'N/D', 'N/A'),
            ),
            _DetailField(
              label: t(context, 'Timeout do Job', 'Job Timeout'),
              value: detail.jobTimeoutMinutes == null
                  ? t(context, 'N/D', 'N/A')
                  : '${detail.jobTimeoutMinutes} min',
            ),
            _DetailField(
              label: t(context, 'Timeout Estruturado', 'Structured Timeout'),
              value: detail.structuredTimeoutSeconds == null
                  ? t(context, 'N/D', 'N/A')
                  : '${detail.structuredTimeoutSeconds}s',
            ),
            _DetailField(
              label: t(context, 'Timeout Visual', 'Style Timeout'),
              value: detail.styleTimeoutSeconds == null
                  ? t(context, 'N/D', 'N/A')
                  : '${detail.styleTimeoutSeconds}s',
            ),
            _DetailField(
              label: t(context, 'Criado em', 'Created at'),
              value: formatDate(context, detail.createdAtUtc),
            ),
            _DetailField(
              label: t(context, 'Iniciado em', 'Started at'),
              value: formatDate(context, detail.startedAtUtc),
            ),
            _DetailField(
              label: t(context, 'Finalizado em', 'Finished at'),
              value: formatDate(context, detail.finishedAtUtc),
            ),
          ],
        ),
        if ((detail.aiPrompt ?? '').trim().isNotEmpty) ...<Widget>[
          const SizedBox(height: 14),
          Text(
            t(context, 'Prompt Aplicado', 'Applied Prompt'),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          Material(
            color: Theme.of(
              context,
            ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.22),
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: SelectableText(detail.aiPrompt!.trim()),
            ),
          ),
        ],
        if (detail.qualitySummary != null ||
            detail.translationStatuses != null ||
            detail.capabilityProfile != null) ...<Widget>[
          const SizedBox(height: 14),
          Text(
            t(context, 'Resumo de Qualidade', 'Quality Summary'),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 10),
          _DetailGrid(
            children: <_DetailField>[
              _DetailField(
                label: t(context, 'Idiomas Publicados', 'Published Languages'),
                value: publishedLanguages.isEmpty
                    ? t(context, 'Nenhum', 'None')
                    : publishedLanguages.join(', '),
              ),
              _DetailField(
                label: t(context, 'Idiomas Reprovados', 'Failed Languages'),
                value: failedLanguages.isEmpty
                    ? t(context, 'Nenhum', 'None')
                    : failedLanguages.join(', '),
              ),
              _DetailField(
                label: t(context, 'Perfil Efetivo', 'Effective Profile'),
                value:
                    detail.capabilityProfile?['effectiveQualityProfile']
                        ?.toString() ??
                    detail.qualityProfile,
              ),
              _DetailField(
                label: t(context, 'Referências Online', 'Online References'),
                value:
                    detail.capabilityProfile?['onlineReferencesUsed']
                        ?.toString() ??
                    '0',
              ),
              _DetailField(
                label: t(context, 'Scene map', 'Scene map'),
                value: detail.sceneMapPath?.trim().isNotEmpty == true
                    ? detail.sceneMapPath!
                    : t(context, 'N/D', 'N/A'),
              ),
              _DetailField(
                label: t(context, 'Speaker map', 'Speaker map'),
                value: detail.speakerMapPath?.trim().isNotEmpty == true
                    ? detail.speakerMapPath!
                    : t(context, 'N/D', 'N/A'),
              ),
              _DetailField(
                label: t(context, 'Lyric alignment', 'Lyric alignment'),
                value: detail.lyricAlignmentPath?.trim().isNotEmpty == true
                    ? detail.lyricAlignmentPath!
                    : t(context, 'N/D', 'N/A'),
              ),
              _DetailField(
                label: t(context, 'Fonte de Vozes', 'Voice Analysis Source'),
                value: detail.voiceAnalysisSource ?? t(context, 'N/D', 'N/A'),
              ),
              _DetailField(
                label: t(context, 'Fonte de Cenas', 'Scene Analysis Source'),
                value: detail.sceneAnalysisSource ?? t(context, 'N/D', 'N/A'),
              ),
              _DetailField(
                label: t(context, 'Modelo do Planner', 'Planner Model'),
                value: detail.plannerModelUsed ?? t(context, 'N/D', 'N/A'),
              ),
              _DetailField(
                label: t(context, 'Modelo de Revisão', 'Review Model'),
                value: detail.reviewModelUsed ?? t(context, 'N/D', 'N/A'),
              ),
            ],
          ),
        ],
        if ((detail.errorMessage ?? '').trim().isNotEmpty) ...<Widget>[
          const SizedBox(height: 14),
          Material(
            color: detail.status == 'error'
                ? Theme.of(context).colorScheme.errorContainer
                : Theme.of(context).colorScheme.tertiaryContainer,
            borderRadius: BorderRadius.circular(18),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(
                    detail.status == 'error'
                        ? Icons.error_outline
                        : Icons.warning_amber_rounded,
                    color: detail.status == 'error'
                        ? Theme.of(context).colorScheme.onErrorContainer
                        : Theme.of(context).colorScheme.onTertiaryContainer,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      detail.errorMessage!.trim(),
                      style: TextStyle(
                        color: detail.status == 'error'
                            ? Theme.of(context).colorScheme.onErrorContainer
                            : Theme.of(context).colorScheme.onTertiaryContainer,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        if (detail.translationStatuses != null &&
            detail.translationStatuses!.isNotEmpty) ...<Widget>[
          const SizedBox(height: 14),
          Text(
            t(context, 'Status por Idioma', 'Status by Language'),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: detail.translationStatuses!.entries.map((entry) {
              final data = entry.value is Map
                  ? Map<String, dynamic>.from(entry.value as Map)
                  : const <String, dynamic>{};
              final languageStatus = data['status']?.toString() ?? 'unknown';
              final failureReason = data['failureReason']?.toString();
              final source = data['source']?.toString();
              final score = data['quality'] is Map
                  ? (data['quality'] as Map)['averageScore']?.toString()
                  : null;
              return SizedBox(
                width: 320,
                child: Material(
                  color: Theme.of(
                    context,
                  ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(16),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: Text(
                                entry.key,
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                            ),
                            _StatusBadge(
                              label: languageStatus,
                              color: languageStatus == 'published'
                                  ? Colors.green
                                  : Theme.of(context).colorScheme.error,
                            ),
                          ],
                        ),
                        if (score != null) ...<Widget>[
                          const SizedBox(height: 8),
                          Text('Score: $score'),
                        ],
                        if (source != null) ...<Widget>[
                          const SizedBox(height: 4),
                          Text('Source: $source'),
                        ],
                        if (failureReason != null &&
                            failureReason.trim().isNotEmpty) ...<Widget>[
                          const SizedBox(height: 8),
                          Text(failureReason),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
        if (detail.diagnostics.isNotEmpty) ...<Widget>[
          const SizedBox(height: 14),
          Text(
            t(context, 'Diagnóstico por Etapa', 'Stage Diagnostics'),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: detail.diagnostics
                .asMap()
                .entries
                .map(
                  (entry) => SizedBox(
                    width: 320,
                    child: _AnimatedEntrance(
                      delay: Duration(milliseconds: 45 * entry.key),
                      child: _DiagnosticCard(diagnostic: entry.value, t: t),
                    ),
                  ),
                )
                .toList(),
          ),
        ],
        const SizedBox(height: 16),
        Text(
          t(context, 'Outputs', 'Outputs'),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 10),
        if (detail.outputs.isEmpty)
          Text(
            t(
              context,
              'Nenhum output disponível ainda.',
              'No output available yet.',
            ),
          )
        else
          Column(
            children: detail.outputs
                .asMap()
                .entries
                .map(
                  (entry) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _AnimatedEntrance(
                      delay: Duration(milliseconds: 24 * entry.key),
                      child: Builder(
                        builder: (context) {
                          final output = entry.value;
                          return Material(
                            borderRadius: BorderRadius.circular(16),
                            color: Theme.of(context).colorScheme.surface,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: output.canPreviewInline
                                  ? () => onPreview(output)
                                  : null,
                              child: Padding(
                                padding: const EdgeInsets.all(14),
                                child: Row(
                                  children: <Widget>[
                                    const Icon(
                                      Icons.insert_drive_file_outlined,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: <Widget>[
                                          Text(
                                            output.fileName
                                                        ?.trim()
                                                        .isNotEmpty ==
                                                    true
                                                ? output.fileName!.trim()
                                                : outputTypeLabel(
                                                    context,
                                                    output.outputType,
                                                  ),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: Theme.of(
                                              context,
                                            ).textTheme.titleSmall,
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            '${outputTypeLabel(context, output.outputType)} • ${output.contentType}',
                                            style: Theme.of(
                                              context,
                                            ).textTheme.bodySmall,
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    IconButton(
                                      tooltip: t(
                                        context,
                                        'Visualizar',
                                        'Preview',
                                      ),
                                      onPressed: output.canPreviewInline
                                          ? () => onPreview(output)
                                          : null,
                                      icon: const Icon(
                                        Icons.visibility_outlined,
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: t(
                                        context,
                                        'Copiar link',
                                        'Copy link',
                                      ),
                                      onPressed: () => onCopyLink(output),
                                      icon: const Icon(Icons.link_outlined),
                                    ),
                                    IconButton(
                                      tooltip: t(context, 'Baixar', 'Download'),
                                      onPressed: () => onDownload(output),
                                      icon: const Icon(Icons.download_outlined),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
      ],
    );
  }
}

class _AnimatedEntrance extends StatefulWidget {
  const _AnimatedEntrance({
    required this.child,
    this.delay = Duration.zero,
    this.triggerKey,
  });

  final Widget child;
  final Duration delay;
  final Object? triggerKey;

  @override
  State<_AnimatedEntrance> createState() => _AnimatedEntranceState();
}

class _AnimatedEntranceState extends State<_AnimatedEntrance> {
  Timer? _timer;
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    _scheduleReveal();
  }

  @override
  void didUpdateWidget(covariant _AnimatedEntrance oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.triggerKey != widget.triggerKey) {
      _timer?.cancel();
      _visible = false;
      _scheduleReveal();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _scheduleReveal() {
    if (widget.delay == Duration.zero) {
      _visible = true;
      return;
    }

    _timer = Timer(widget.delay, () {
      if (!mounted) return;
      setState(() => _visible = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    const duration = Duration(milliseconds: 320);
    const offsetY = 16.0;
    return AnimatedOpacity(
      duration: duration,
      curve: Curves.easeOutCubic,
      opacity: _visible ? 1 : 0,
      child: AnimatedContainer(
        duration: duration,
        curve: Curves.easeOutCubic,
        transform: Matrix4.translationValues(0, _visible ? 0 : offsetY, 0),
        child: widget.child,
      ),
    );
  }
}

class _MiniPill extends StatelessWidget {
  const _MiniPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.28),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(label),
      ),
    );
  }
}

class _DiagnosticCard extends StatelessWidget {
  const _DiagnosticCard({required this.diagnostic, required this.t});

  final TranscriptionJobDiagnostic diagnostic;
  final String Function(BuildContext, String, String) t;

  @override
  Widget build(BuildContext context) {
    final normalizedSeverity = diagnostic.severity.trim().toLowerCase();
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final (
      Color background,
      Color foreground,
      IconData icon,
    ) = switch (normalizedSeverity) {
      'error' => (
        colorScheme.errorContainer,
        colorScheme.onErrorContainer,
        Icons.error_outline_rounded,
      ),
      'warning' => (
        colorScheme.tertiaryContainer,
        colorScheme.onTertiaryContainer,
        Icons.warning_amber_rounded,
      ),
      _ => (
        colorScheme.secondaryContainer,
        colorScheme.onSecondaryContainer,
        Icons.info_outline_rounded,
      ),
    };

    final meta = <String>[
      if ((diagnostic.language ?? '').trim().isNotEmpty) diagnostic.language!,
      if ((diagnostic.model ?? '').trim().isNotEmpty) diagnostic.model!,
      if ((diagnostic.fallbackUsed ?? '').trim().isNotEmpty)
        diagnostic.fallbackUsed!,
    ];

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(18),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: background.withValues(alpha: 0.18),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(icon, color: foreground),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _diagnosticStageLabel(context, diagnostic.stage, t),
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: foreground,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            diagnostic.message,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: foreground),
          ),
          if (meta.isNotEmpty) ...<Widget>[
            const SizedBox(height: 10),
            Text(
              meta.join(' • '),
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: foreground),
            ),
          ],
          if ((diagnostic.rawExcerpt ?? '').trim().isNotEmpty) ...<Widget>[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: foreground.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: SelectableText(
                diagnostic.rawExcerpt!,
                maxLines: 5,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: foreground),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

String _diagnosticStageLabel(
  BuildContext context,
  String stage,
  String Function(BuildContext, String, String) t,
) {
  switch (stage.trim().toLowerCase()) {
    case 'alignment':
      return t(context, 'Alinhamento', 'Alignment');
    case 'cleanup':
      return t(context, 'Limpeza', 'Cleanup');
    case 'review':
    case 'review_score':
      return t(context, 'Revisão', 'Review');
    case 'asr':
      return 'ASR';
    case 'correction':
      return t(context, 'Correção', 'Correction');
    case 'subtitle_styling':
      return t(context, 'Plano Visual', 'Visual Plan');
    case 'semantic_translation':
      return t(context, 'Tradução', 'Translation');
    case 'packaging':
      return t(context, 'Empacotamento', 'Packaging');
    default:
      return stage;
  }
}

class _DetailGrid extends StatelessWidget {
  const _DetailGrid({required this.children});

  final List<_DetailField> children;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: children
          .map(
            (field) => SizedBox(
              width: 280,
              child: Material(
                color: Theme.of(
                  context,
                ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(16),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        field.label,
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      const SizedBox(height: 6),
                      SelectableText(
                        field.value.trim().isEmpty ? '—' : field.value,
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          )
          .toList(),
    );
  }
}

class _DetailField {
  const _DetailField({required this.label, required this.value});

  final String label;
  final String value;
}
