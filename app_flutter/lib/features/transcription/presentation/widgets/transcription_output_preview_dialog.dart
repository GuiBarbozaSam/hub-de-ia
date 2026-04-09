import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/transcription_api_service.dart';
import '../../data/transcription_models.dart';

class TranscriptionOutputPreviewDialog extends ConsumerStatefulWidget {
  const TranscriptionOutputPreviewDialog({
    super.key,
    required this.output,
    this.siblingOutputs = const <TranscriptionOutput>[],
    this.preferRenderedPreview = false,
  });

  final TranscriptionOutput output;
  final List<TranscriptionOutput> siblingOutputs;
  final bool preferRenderedPreview;

  @override
  ConsumerState<TranscriptionOutputPreviewDialog> createState() =>
      _TranscriptionOutputPreviewDialogState();
}

class _SubtitleOption {
  const _SubtitleOption.auto()
    : key = 'auto',
      label = 'Legenda auto',
      source = _SubtitleOptionSource.auto,
      embeddedIndex = null,
      output = null,
      languageCode = null;

  const _SubtitleOption.none()
    : key = 'none',
      label = 'Sem legenda',
      source = _SubtitleOptionSource.none,
      embeddedIndex = null,
      output = null,
      languageCode = null;

  const _SubtitleOption.embedded({
    required this.key,
    required this.label,
    required this.embeddedIndex,
  }) : source = _SubtitleOptionSource.embedded,
       output = null,
       languageCode = null;

  const _SubtitleOption.external({
    required this.key,
    required this.label,
    required this.output,
    this.languageCode,
  }) : source = _SubtitleOptionSource.external,
       embeddedIndex = null;

  final String key;
  final String label;
  final _SubtitleOptionSource source;
  final int? embeddedIndex;
  final TranscriptionOutput? output;
  final String? languageCode;
}

enum _SubtitleOptionSource { auto, none, embedded, external }

class _TranscriptionOutputPreviewDialogState
    extends ConsumerState<TranscriptionOutputPreviewDialog> {
  final ScrollController _textScrollController = ScrollController();

  Player? _player;
  VideoController? _videoController;
  Widget? _videoSurface;
  StreamSubscription<Tracks>? _tracksSubscription;
  StreamSubscription<Track>? _trackSubscription;
  StreamSubscription<bool>? _playingSubscription;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<Duration>? _durationSubscription;

  bool _isLoading = true;
  bool _isReloading = false;
  bool _isTextPreview = false;
  bool _isMediaPreview = false;
  bool _isDisposed = false;
  bool _isPlaying = false;

  String? _textPreview;
  String? _errorMessage;
  String? _temporaryMediaFilePath;

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  double _playbackRate = 1.0;
  int _lastPositionUiMillis = -1;

  List<AudioTrack> _audioTracks = const <AudioTrack>[];
  List<SubtitleTrack> _subtitleTracks = const <SubtitleTrack>[];
  List<_SubtitleOption> _subtitleOptions = const <_SubtitleOption>[
    _SubtitleOption.auto(),
    _SubtitleOption.none(),
  ];
  final Map<String, String> _cachedSubtitleFiles = <String, String>{};
  AudioTrack? _selectedAudioTrack;
  SubtitleTrack? _selectedSubtitleTrack;
  String _selectedSubtitleOptionKey = 'auto';

  static const List<double> _playbackRates = <double>[
    0.5,
    0.75,
    1.0,
    1.25,
    1.5,
    1.75,
    2.0,
  ];
  static const Duration _mediaOpenTimeout = Duration(seconds: 20);

  @override
  void initState() {
    super.initState();
    unawaited(_loadPreview(isReload: false));
  }

  TranscriptionOutput get _previewOutput {
    if (!widget.preferRenderedPreview) {
      return widget.output;
    }

    final preferred = widget.siblingOutputs.firstWhere(
      (item) => item.outputType.toLowerCase() == 'render_preview',
      orElse: () => widget.output,
    );
    return preferred;
  }

  @override
  void dispose() {
    _isDisposed = true;
    _tracksSubscription?.cancel();
    _trackSubscription?.cancel();
    _playingSubscription?.cancel();
    _positionSubscription?.cancel();
    _durationSubscription?.cancel();
    _player?.dispose();
    _videoSurface = null;
    _deleteTemporaryMediaFile();
    _deleteCachedSubtitleFiles();
    _textScrollController.dispose();
    super.dispose();
  }

  Future<void> _loadPreview({required bool isReload}) async {
    _safeSetState(() {
      _isLoading = !isReload;
      _isReloading = isReload;
      _isTextPreview = false;
      _isMediaPreview = false;
      _textPreview = null;
      _errorMessage = null;
      _position = Duration.zero;
      _duration = Duration.zero;
      _playbackRate = 1.0;
      _selectedSubtitleOptionKey = 'auto';
    });

    try {
      if (_shouldLoadAsText(widget.output)) {
        await _loadTextPreview();
      } else {
        await _loadMediaPreview();
      }
    } catch (error) {
      _safeSetState(() {
        _errorMessage = error.toString();
      });
    } finally {
      _safeSetState(() {
        _isLoading = false;
        _isReloading = false;
      });
    }
  }

  Future<void> _loadTextPreview() async {
    final api = ref.read(transcriptionApiServiceProvider);
    final preview = await api.fetchTextPreview(widget.output);

    _safeSetState(() {
      _isTextPreview = true;
      _textPreview = preview;
    });
  }

  Future<void> _loadMediaPreview() async {
    final api = ref.read(transcriptionApiServiceProvider);
    final previewOutput = _previewOutput;
    final mediaUrl = _resolveMediaUrl(previewOutput);
    final embeddedOnly = _shouldUseEmbeddedSubtitles(previewOutput);

    if (mediaUrl == null || mediaUrl.trim().isEmpty) {
      throw Exception(
        'Este output não possui uma URL de mídia utilizável para preview.',
      );
    }

    await _disposePlayerState();

    final headers = await api.authorizedHeaders(
      includeJson: false,
      accept: '*/*',
    );

    final player = Player();
    final isVideo = _isVideoOutput(widget.output);
    final videoController = isVideo ? VideoController(player) : null;

    _player = player;
    _videoController = videoController;
    _videoSurface = videoController == null
        ? null
        : RepaintBoundary(child: Video(controller: videoController));
    _bindPlayerStreams(player, preferExternal: !embeddedOnly);

    final prefersLocalOpen = _shouldOpenLocallyFirst(previewOutput);
    if (prefersLocalOpen) {
      final tempPath = await _cacheOutputLocally(api, previewOutput);
      _temporaryMediaFilePath = tempPath;
      await _openMedia(player, Media(tempPath));
    } else {
      try {
        await _openMedia(
          player,
          Media(api.resolveUri(mediaUrl).toString(), httpHeaders: headers),
        );
      } catch (_) {
        final tempPath = await _cacheOutputLocally(api, previewOutput);
        _temporaryMediaFilePath = tempPath;
        await _openMedia(player, Media(tempPath));
      }
    }

    await _rebuildSubtitleOptions(preferExternal: !embeddedOnly);

    _safeSetState(() {
      _isMediaPreview = true;
    });
  }

  Future<void> _openMedia(Player player, Media media) async {
    await player
        .open(media, play: false)
        .timeout(
          _mediaOpenTimeout,
          onTimeout: () => throw TimeoutException(
            'O preview demorou demais para iniciar. Tente recarregar ou abrir externamente.',
          ),
        );
  }

  void _bindPlayerStreams(Player player, {required bool preferExternal}) {
    _tracksSubscription?.cancel();
    _trackSubscription?.cancel();
    _playingSubscription?.cancel();
    _positionSubscription?.cancel();
    _durationSubscription?.cancel();

    _tracksSubscription = player.stream.tracks.listen((Tracks tracks) {
      _safeSetState(() {
        _audioTracks = tracks.audio;
        _subtitleTracks = tracks.subtitle;
      });
      unawaited(_rebuildSubtitleOptions(preferExternal: preferExternal));
    });

    _trackSubscription = player.stream.track.listen((Track track) {
      _safeSetState(() {
        _selectedAudioTrack = track.audio;
        _selectedSubtitleTrack = track.subtitle;
      });
    });

    _playingSubscription = player.stream.playing.listen((bool playing) {
      _safeSetState(() {
        _isPlaying = playing;
      });
    });

    _positionSubscription = player.stream.position.listen((Duration position) {
      final millis = position.inMilliseconds;
      final shouldUpdate =
          _lastPositionUiMillis < 0 ||
          (millis - _lastPositionUiMillis).abs() >= 320 ||
          millis == 0 ||
          (_duration.inMilliseconds > 0 &&
              (_duration.inMilliseconds - millis).abs() <= 220);
      if (!shouldUpdate) {
        return;
      }
      _lastPositionUiMillis = millis;
      _safeSetState(() {
        _position = position;
      });
    });

    _durationSubscription = player.stream.duration.listen((Duration duration) {
      _safeSetState(() {
        _duration = duration;
      });
    });
  }

  Future<void> _disposePlayerState() async {
    _tracksSubscription?.cancel();
    _trackSubscription?.cancel();
    _playingSubscription?.cancel();
    _positionSubscription?.cancel();
    _durationSubscription?.cancel();
    _tracksSubscription = null;
    _trackSubscription = null;
    _playingSubscription = null;
    _positionSubscription = null;
    _durationSubscription = null;

    _player?.dispose();
    _player = null;
    _videoController = null;
    _videoSurface = null;

    _audioTracks = const <AudioTrack>[];
    _subtitleTracks = const <SubtitleTrack>[];
    _selectedAudioTrack = null;
    _selectedSubtitleTrack = null;
    _isPlaying = false;
    _position = Duration.zero;
    _duration = Duration.zero;
    _lastPositionUiMillis = -1;

    _deleteTemporaryMediaFile();
    _deleteCachedSubtitleFiles();
  }

  void _deleteTemporaryMediaFile() {
    final path = _temporaryMediaFilePath;
    _temporaryMediaFilePath = null;
    if (path == null || path.trim().isEmpty) {
      return;
    }

    try {
      final file = File(path);
      if (file.existsSync()) {
        file.deleteSync();
      }
    } catch (_) {}
  }

  void _deleteCachedSubtitleFiles() {
    for (final path in _cachedSubtitleFiles.values) {
      try {
        final file = File(path);
        if (file.existsSync()) {
          file.deleteSync();
        }
      } catch (_) {}
    }
    _cachedSubtitleFiles.clear();
  }

  Future<String> _cacheOutputLocally(
    TranscriptionApiService api,
    TranscriptionOutput output,
  ) async {
    final bytes = await api.fetchOutputBytes(output);
    final extension = _inferExtension(output);
    final file = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}hub_ia_preview_${DateTime.now().microsecondsSinceEpoch}$extension',
    );
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  Future<void> _togglePlayPause() async {
    final player = _player;
    if (player == null) return;

    if (_isPlaying) {
      await player.pause();
    } else {
      await player.play();
    }
  }

  Future<void> _setPlaybackRate(double rate) async {
    final player = _player;
    if (player == null) return;

    await player.setRate(rate);
    _safeSetState(() {
      _playbackRate = rate;
    });
  }

  Future<void> _selectAudioTrack(String value) async {
    final player = _player;
    if (player == null) return;

    if (value == 'auto') {
      await player.setAudioTrack(AudioTrack.auto());
      return;
    }

    final index = int.tryParse(value);
    if (index == null || index < 0 || index >= _audioTracks.length) {
      return;
    }

    await player.setAudioTrack(_audioTracks[index]);
  }

  Future<void> _selectSubtitleTrack(String value) async {
    final player = _player;
    if (player == null) return;

    _SubtitleOption? option;
    for (final item in _subtitleOptions) {
      if (item.key == value) {
        option = item;
        break;
      }
    }
    if (option == null) return;

    switch (option.source) {
      case _SubtitleOptionSource.auto:
        await player.setSubtitleTrack(SubtitleTrack.auto());
        break;
      case _SubtitleOptionSource.none:
        await player.setSubtitleTrack(SubtitleTrack.no());
        break;
      case _SubtitleOptionSource.embedded:
        final index = option.embeddedIndex;
        if (index == null || index < 0 || index >= _subtitleTracks.length) {
          return;
        }
        await player.setSubtitleTrack(_subtitleTracks[index]);
        break;
      case _SubtitleOptionSource.external:
        final output = option.output;
        if (output == null) return;
        final filePath = await _ensureSubtitleOutputCached(output);
        await player.setSubtitleTrack(
          SubtitleTrack.uri(
            Uri.file(filePath).toString(),
            title: option.label,
            language: option.languageCode,
          ),
        );
        break;
    }

    _safeSetState(() {
      _selectedSubtitleOptionKey = option!.key;
    });
  }

  Future<String> _ensureSubtitleOutputCached(TranscriptionOutput output) async {
    final cached = _cachedSubtitleFiles[output.id];
    if (cached != null &&
        cached.trim().isNotEmpty &&
        File(cached).existsSync()) {
      return cached;
    }

    final api = ref.read(transcriptionApiServiceProvider);
    final bytes = await api.fetchOutputBytes(output);
    final extension = _inferExtension(output);
    final file = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}hub_ia_subtitle_${output.id}$extension',
    );
    await file.writeAsBytes(bytes, flush: true);
    _cachedSubtitleFiles[output.id] = file.path;
    return file.path;
  }

  List<TranscriptionOutput> _explicitSubtitleOutputs() {
    if (_shouldUseEmbeddedSubtitles(widget.output)) {
      return const <TranscriptionOutput>[];
    }

    final grouped = <String, List<TranscriptionOutput>>{};

    for (final output in widget.siblingOutputs) {
      if (!_isEligibleExternalSubtitleOutput(output)) {
        continue;
      }

      final languageKey = _subtitleLanguageGroupKey(output);
      grouped
          .putIfAbsent(languageKey, () => <TranscriptionOutput>[])
          .add(output);
    }

    final selected = <TranscriptionOutput>[];
    for (final entries in grouped.values) {
      entries.sort(_compareSubtitleCandidates);
      if (entries.isNotEmpty) {
        selected.add(entries.first);
      }
    }

    selected.sort((a, b) {
      final aKey = _subtitleLanguageGroupKey(a);
      final bKey = _subtitleLanguageGroupKey(b);
      if (aKey == '__original__' && bKey != '__original__') return -1;
      if (aKey != '__original__' && bKey == '__original__') return 1;
      return _subtitleOutputLabel(
        a,
      ).toLowerCase().compareTo(_subtitleOutputLabel(b).toLowerCase());
    });

    return selected;
  }

  bool _isEligibleExternalSubtitleOutput(TranscriptionOutput output) {
    final type = output.outputType.toLowerCase();
    final format = _subtitleFormat(output);
    if (format == null) {
      return false;
    }

    if (type == 'ass' || type == 'srt' || type == 'vtt') {
      return true;
    }

    if (type.startsWith('translation_')) {
      return true;
    }

    if (type.startsWith('enhanced_')) {
      return true;
    }

    return false;
  }

  int _compareSubtitleCandidates(TranscriptionOutput a, TranscriptionOutput b) {
    final stageDiff = _subtitleStageRank(b).compareTo(_subtitleStageRank(a));
    if (stageDiff != 0) return stageDiff;

    final formatDiff = _subtitleFormatRank(b).compareTo(_subtitleFormatRank(a));
    if (formatDiff != 0) return formatDiff;

    return b.createdAtUtc.compareTo(a.createdAtUtc);
  }

  int _subtitleStageRank(TranscriptionOutput output) {
    final type = output.outputType.toLowerCase();
    if (type.startsWith('translation_')) return 300;
    if (type.startsWith('enhanced_')) return 200;
    return 100;
  }

  int _subtitleFormatRank(TranscriptionOutput output) {
    switch (_subtitleFormat(output)) {
      case 'ass':
        return 30;
      case 'srt':
        return 20;
      case 'vtt':
        return 10;
      default:
        return 0;
    }
  }

  String? _subtitleFormat(TranscriptionOutput output) {
    final type = output.outputType.toLowerCase();
    if (type == 'ass' ||
        type.contains('_ass_') ||
        type.endsWith('_ass') ||
        type.startsWith('enhanced_ass')) {
      return 'ass';
    }
    if (type == 'srt' ||
        type.contains('_srt_') ||
        type.endsWith('_srt') ||
        type.startsWith('enhanced_srt')) {
      return 'srt';
    }
    if (type == 'vtt' ||
        type.contains('_vtt_') ||
        type.endsWith('_vtt') ||
        type.startsWith('enhanced_vtt')) {
      return 'vtt';
    }

    final fileName = output.fileName?.toLowerCase() ?? '';
    if (fileName.endsWith('.ass')) return 'ass';
    if (fileName.endsWith('.srt')) return 'srt';
    if (fileName.endsWith('.vtt')) return 'vtt';
    return null;
  }

  String _subtitleLanguageGroupKey(TranscriptionOutput output) {
    final languageCode = _extractLanguageCode(output)?.trim();
    if (languageCode == null || languageCode.isEmpty) {
      return '__original__';
    }
    return languageCode.toLowerCase();
  }

  String? _extractLanguageCode(TranscriptionOutput output) {
    final type = output.outputType;
    if (type.startsWith('translation_')) {
      final parts = type.split('_');
      if (parts.length >= 3) {
        return parts.sublist(2).join('_');
      }
    }

    final fileName = output.fileName ?? '';
    final match = RegExp(
      r'(pt-BR|en|es|fr|de|it|ja|ko|zh-CN|ru|ar|hi)',
      caseSensitive: false,
    ).firstMatch(fileName);
    return match?.group(0);
  }

  String _subtitleOutputLabel(TranscriptionOutput output) {
    final groupKey = _subtitleLanguageGroupKey(output);
    if (groupKey == '__original__') {
      return _t('Idioma original', 'Original language');
    }

    return _languageLabelFromCode(_extractLanguageCode(output) ?? groupKey);
  }

  String _t(String pt, String en) {
    final locale = Localizations.maybeLocaleOf(context);
    final isEnglish = locale?.languageCode.toLowerCase() == 'en';
    return isEnglish ? en : pt;
  }

  String _languageLabelFromCode(String code) {
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
    };

    final locale = Localizations.maybeLocaleOf(context);
    final isEnglish = locale?.languageCode.toLowerCase() == 'en';
    return isEnglish
        ? (english[normalized] ?? code)
        : (portuguese[normalized] ?? code);
  }

  bool _isGenericEmbeddedSubtitle(SubtitleTrack track, int index) {
    final label = _describeSubtitleTrack(track, index).trim().toLowerCase();
    if (label.isEmpty) return true;
    final generic = <String>{
      'legenda ${index + 1}',
      'subtitle ${index + 1}',
      'subtitles ${index + 1}',
      'track ${index + 1}',
      'faixa ${index + 1}',
    };
    return generic.contains(label);
  }

  Future<void> _rebuildSubtitleOptions({required bool preferExternal}) async {
    final explicitOutputs = _explicitSubtitleOutputs();
    final options = <_SubtitleOption>[
      const _SubtitleOption.auto(),
      const _SubtitleOption.none(),
    ];

    if (preferExternal && explicitOutputs.isNotEmpty) {
      for (final output in explicitOutputs) {
        final languageCode = _extractLanguageCode(output);
        options.add(
          _SubtitleOption.external(
            key: 'external:${output.id}',
            label: _subtitleOutputLabel(output),
            output: output,
            languageCode: languageCode,
          ),
        );
      }
    } else {
      final nonGeneric = <_SubtitleOption>[];
      final generic = <_SubtitleOption>[];
      for (var index = 0; index < _subtitleTracks.length; index++) {
        final track = _subtitleTracks[index];
        final option = _SubtitleOption.embedded(
          key: 'embedded:$index',
          label: _describeSubtitleTrack(track, index),
          embeddedIndex: index,
        );
        if (_isGenericEmbeddedSubtitle(track, index)) {
          generic.add(option);
        } else {
          nonGeneric.add(option);
        }
      }
      options.addAll(nonGeneric.isNotEmpty ? nonGeneric : generic);
    }

    final hasCurrentSelection = options.any(
      (item) => item.key == _selectedSubtitleOptionKey,
    );

    if (!hasCurrentSelection) {
      _selectedSubtitleOptionKey = explicitOutputs.isNotEmpty
          ? options[1].key
          : 'auto';
    }

    if (preferExternal &&
        explicitOutputs.isNotEmpty &&
        _selectedSubtitleOptionKey == 'auto') {
      await _player?.setSubtitleTrack(SubtitleTrack.no());
      _selectedSubtitleOptionKey = 'none';
    }

    _safeSetState(() {
      _subtitleOptions = options;
    });
  }

  Future<void> _copyPreferredLink() async {
    final link =
        widget.output.downloadUrl ??
        _previewOutput.downloadUrl ??
        _previewOutput.previewUrl ??
        _previewOutput.previewPageUrl ??
        widget.output.previewUrl ??
        widget.output.previewPageUrl;

    if (link == null || link.trim().isEmpty) {
      _showSnackBar('Este output não possui link disponível para cópia.');
      return;
    }

    await Clipboard.setData(ClipboardData(text: link));
    _showSnackBar('Link copiado para a área de transferência.');
  }

  Future<void> _downloadOutput() async {
    try {
      final path = await ref
          .read(transcriptionApiServiceProvider)
          .downloadOutput(widget.output);
      if (path == null || path.trim().isEmpty) {
        return;
      }
      _showSnackBar('Arquivo salvo em: $path');
    } catch (error) {
      _showSnackBar(error.toString());
    }
  }

  Future<void> _openExternally() async {
    try {
      Uri? uri;
      final existingTempPath = _temporaryMediaFilePath;
      if (existingTempPath != null &&
          existingTempPath.trim().isNotEmpty &&
          File(existingTempPath).existsSync()) {
        uri = Uri.file(existingTempPath);
      } else if (_isMediaPreview || _isVideoOutput(_previewOutput)) {
        final api = ref.read(transcriptionApiServiceProvider);
        final localPath = await _cacheOutputLocally(api, _previewOutput);
        _temporaryMediaFilePath = localPath;
        uri = Uri.file(localPath);
      } else {
        final link =
            _previewOutput.previewPageUrl ??
            _previewOutput.downloadUrl ??
            _previewOutput.previewUrl ??
            widget.output.previewPageUrl ??
            widget.output.downloadUrl ??
            widget.output.previewUrl;
        if (link != null && link.trim().isNotEmpty) {
          uri = Uri.tryParse(link.trim());
        }
      }

      if (uri == null) {
        throw Exception('Nenhum caminho externo disponível para este output.');
      }

      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        throw Exception('Não foi possível abrir o preview externamente.');
      }
    } catch (error) {
      _showSnackBar(error.toString());
    }
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _safeSetState(VoidCallback fn) {
    if (_isDisposed || !mounted) return;
    setState(fn);
  }

  String? _resolveMediaUrl(TranscriptionOutput output) {
    final candidates = <String?>[output.previewUrl, output.downloadUrl];

    for (final candidate in candidates) {
      final normalized = candidate?.trim();
      if (normalized != null && normalized.isNotEmpty) {
        return normalized;
      }
    }

    return null;
  }

  bool _isMuxedVideoOutput(TranscriptionOutput output) {
    final type = output.outputType.toLowerCase();
    if (type == 'video_muxed') {
      return true;
    }

    final fileName = output.fileName?.toLowerCase() ?? '';
    return fileName.endsWith('.mkv');
  }

  bool _shouldUseEmbeddedSubtitles(TranscriptionOutput output) {
    return _isMuxedVideoOutput(output);
  }

  bool _shouldOpenLocallyFirst(TranscriptionOutput output) {
    return _isMuxedVideoOutput(output);
  }

  bool _shouldLoadAsText(TranscriptionOutput output) {
    final previewKind = output.previewKind.toLowerCase();
    if (previewKind == 'text') {
      return true;
    }

    final type = output.outputType.toLowerCase();
    if (type == 'text' ||
        type.contains('txt') ||
        type.contains('srt') ||
        type.contains('vtt') ||
        type.contains('ass')) {
      return true;
    }

    final contentType = output.contentType.toLowerCase();
    return contentType.startsWith('text/') ||
        contentType.contains('subrip') ||
        contentType.contains('webvtt') ||
        contentType.contains('ass');
  }

  bool _isVideoOutput(TranscriptionOutput output) {
    final previewKind = output.previewKind.toLowerCase();
    if (previewKind == 'video') {
      return true;
    }

    final type = output.outputType.toLowerCase();
    if (type.contains('video')) {
      return true;
    }

    final contentType = output.contentType.toLowerCase();
    if (contentType.startsWith('video/')) {
      return true;
    }

    final fileName = output.fileName?.toLowerCase() ?? '';
    return fileName.endsWith('.mp4') ||
        fileName.endsWith('.mkv') ||
        fileName.endsWith('.mov') ||
        fileName.endsWith('.avi') ||
        fileName.endsWith('.webm');
  }

  String _inferExtension(TranscriptionOutput output) {
    final fileName = output.fileName?.trim();
    if (fileName != null && fileName.isNotEmpty) {
      final ext = fileName.contains('.')
          ? fileName.substring(fileName.lastIndexOf('.'))
          : '';
      if (ext.isNotEmpty) {
        return ext;
      }
    }

    final type = output.outputType.toLowerCase();
    if (type.contains('ass')) return '.ass';
    if (type.contains('srt')) return '.srt';
    if (type.contains('vtt')) return '.vtt';
    if (type.contains('txt')) return '.txt';
    if (type.contains('mkv') || type.contains('video_muxed')) return '.mkv';
    if (type.contains('mp4') || type.contains('video')) return '.mp4';
    if (type.contains('mp3')) return '.mp3';
    if (type.contains('wav')) return '.wav';
    return '.bin';
  }

  String _outputTitle(TranscriptionOutput output) {
    final fileName = output.fileName?.trim();
    if (fileName != null && fileName.isNotEmpty) {
      return fileName;
    }

    switch (output.outputType.toLowerCase()) {
      case 'text':
        return 'Texto';
      case 'srt':
        return 'Legenda SRT';
      case 'vtt':
        return 'Legenda VTT';
      case 'ass':
        return 'Legenda ASS';
      case 'video_burned':
        return 'Vídeo com legenda queimada';
      case 'video_muxed':
        return 'Vídeo com trilhas';
      default:
        return output.outputType;
    }
  }

  String _audioSelectionValue() {
    final selected = _selectedAudioTrack;
    if (selected == null) return 'auto';

    final index = _audioTracks.indexOf(selected);
    if (index < 0) return 'auto';
    return '$index';
  }

  String _subtitleSelectionValue() {
    if (_subtitleOptions.any(
      (item) => item.key == _selectedSubtitleOptionKey,
    )) {
      return _selectedSubtitleOptionKey;
    }
    return _subtitleOptions.any((item) => item.key == 'auto')
        ? 'auto'
        : _subtitleOptions.first.key;
  }

  String _describeAudioTrack(AudioTrack track, int index) {
    final pieces = <String>[];
    final dynamic dynamicTrack = track;

    try {
      final title = dynamicTrack.title?.toString().trim();
      if (title != null && title.isNotEmpty) {
        pieces.add(title);
      }
    } catch (_) {}

    try {
      final language = dynamicTrack.language?.toString().trim();
      if (language != null && language.isNotEmpty) {
        pieces.add(language);
      }
    } catch (_) {}

    if (pieces.isEmpty) {
      pieces.add('Áudio ${index + 1}');
    }

    return pieces.join(' • ');
  }

  String _describeSubtitleTrack(SubtitleTrack track, int index) {
    final pieces = <String>[];
    final dynamic dynamicTrack = track;

    try {
      final title = dynamicTrack.title?.toString().trim();
      if (title != null && title.isNotEmpty) {
        pieces.add(title);
      }
    } catch (_) {}

    try {
      final language = dynamicTrack.language?.toString().trim();
      if (language != null && language.isNotEmpty) {
        pieces.add(language);
      }
    } catch (_) {}

    if (pieces.isEmpty) {
      pieces.add('Legenda ${index + 1}');
    }

    return pieces.join(' • ');
  }

  String _formatDuration(Duration value) {
    final totalSeconds = value.inSeconds;
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;

    final two = (int v) => v.toString().padLeft(2, '0');

    if (hours > 0) {
      return '${two(hours)}:${two(minutes)}:${two(seconds)}';
    }
    return '${two(minutes)}:${two(seconds)}';
  }

  @override
  Widget build(BuildContext context) {
    final title = _outputTitle(_previewOutput);

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1200, maxHeight: 860),
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(24),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 30,
                offset: const Offset(0, 18),
              ),
            ],
          ),
          child: Column(
            children: <Widget>[
              _buildHeader(context, title),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  child: _buildBody(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, String title) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Preview do Output',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Tipo: ${_previewOutput.outputType} • ${_previewOutput.previewKind}',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Recarregar preview',
                onPressed: _isReloading
                    ? null
                    : () => _loadPreview(isReload: true),
                icon: _isReloading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_rounded),
              ),
              IconButton(
                tooltip: 'Copiar link',
                onPressed: _copyPreferredLink,
                icon: const Icon(Icons.link_rounded),
              ),
              IconButton(
                tooltip: 'Baixar',
                onPressed: _downloadOutput,
                icon: const Icon(Icons.download_rounded),
              ),
              IconButton(
                tooltip: 'Abrir externamente',
                onPressed: _openExternally,
                icon: const Icon(Icons.open_in_new_rounded),
              ),
              IconButton(
                tooltip: 'Fechar',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            widget.preferRenderedPreview &&
                    _previewOutput.outputType != widget.output.outputType
                ? '$title • Preview renderizado'
                : title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (_isMediaPreview) ...<Widget>[
            const SizedBox(height: 16),
            _buildMediaToolbar(context),
          ],
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null && _errorMessage!.trim().isNotEmpty) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Icon(
                      Icons.error_outline_rounded,
                      color: Theme.of(context).colorScheme.onErrorContainer,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Falha ao abrir o preview',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: Theme.of(
                                context,
                              ).colorScheme.onErrorContainer,
                            ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                SelectableText(
                  _errorMessage!,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onErrorContainer,
                  ),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: <Widget>[
                    FilledButton.icon(
                      onPressed: _isReloading
                          ? null
                          : () => _loadPreview(isReload: true),
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Tentar novamente'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _openExternally,
                      icon: const Icon(Icons.open_in_new_rounded),
                      label: const Text('Abrir externamente'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _copyPreferredLink,
                      icon: const Icon(Icons.link_rounded),
                      label: const Text('Copiar link'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_isTextPreview) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(
            context,
          ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        child: Scrollbar(
          controller: _textScrollController,
          thumbVisibility: true,
          child: SingleChildScrollView(
            controller: _textScrollController,
            padding: const EdgeInsets.all(18),
            child: SelectableText(
              _textPreview ?? '',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(height: 1.55),
            ),
          ),
        ),
      );
    }

    if (_isMediaPreview) {
      if (_isVideoOutput(widget.output) && _videoController != null) {
        return Center(
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final width = constraints.maxWidth;
              final height = constraints.maxHeight;
              final targetHeight = height.isFinite ? height : 560.0;
              final targetWidth = width.isFinite ? width : 980.0;

              return Container(
                width: targetWidth,
                height: targetHeight,
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(20),
                ),
                clipBehavior: Clip.antiAlias,
                child: Center(
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child:
                        _videoSurface ?? Video(controller: _videoController!),
                  ),
                ),
              );
            },
          ),
        );
      }

      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 780),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Theme.of(context).dividerColor),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  Icons.graphic_eq_rounded,
                  size: 64,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 18),
                Text(
                  _isPlaying
                      ? 'Reprodução em andamento'
                      : 'Preview de áudio pronto',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  '${_formatDuration(_position)} / ${_formatDuration(_duration)}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: _togglePlayPause,
                  icon: Icon(
                    _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  ),
                  label: Text(_isPlaying ? 'Pausar' : 'Reproduzir'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildMediaToolbar(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        FilledButton.icon(
          onPressed: _togglePlayPause,
          icon: Icon(
            _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
          ),
          label: Text(_isPlaying ? 'Pausar' : 'Reproduzir'),
        ),
        _buildRateDropdown(context),
        _buildAudioDropdown(context),
        _buildSubtitleDropdown(context),
      ],
    );
  }

  Widget _buildRateDropdown(BuildContext context) {
    return SizedBox(
      width: 140,
      child: InputDecorator(
        decoration: const InputDecoration(
          labelText: 'Velocidade',
          border: OutlineInputBorder(),
          isDense: true,
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<double>(
            isExpanded: true,
            value: _playbackRate,
            items: _playbackRates
                .map(
                  (double rate) => DropdownMenuItem<double>(
                    value: rate,
                    child: Text(
                      rate == 1.0
                          ? '1x'
                          : '${rate.toStringAsFixed(2).replaceAll('.00', '')}x',
                    ),
                  ),
                )
                .toList(growable: false),
            onChanged: (double? value) {
              if (value == null) return;
              unawaited(_setPlaybackRate(value));
            },
          ),
        ),
      ),
    );
  }

  Widget _buildAudioDropdown(BuildContext context) {
    final items = <DropdownMenuItem<String>>[
      const DropdownMenuItem<String>(value: 'auto', child: Text('Áudio auto')),
      ..._audioTracks.asMap().entries.map(
        (entry) => DropdownMenuItem<String>(
          value: '${entry.key}',
          child: Text(_describeAudioTrack(entry.value, entry.key)),
        ),
      ),
    ];

    return SizedBox(
      width: 230,
      child: InputDecorator(
        decoration: const InputDecoration(
          labelText: 'Faixa de Áudio',
          border: OutlineInputBorder(),
          isDense: true,
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            isExpanded: true,
            value: _audioSelectionValue(),
            items: items,
            onChanged: _audioTracks.isEmpty
                ? null
                : (String? value) {
                    if (value == null) return;
                    unawaited(_selectAudioTrack(value));
                  },
          ),
        ),
      ),
    );
  }

  Widget _buildSubtitleDropdown(BuildContext context) {
    final items = <DropdownMenuItem<String>>[
      const DropdownMenuItem<String>(
        value: 'auto',
        child: Text('Legenda auto'),
      ),
      const DropdownMenuItem<String>(value: 'none', child: Text('Sem legenda')),
      ..._subtitleOptions
          .where((item) => item.key != 'auto' && item.key != 'none')
          .map(
            (item) => DropdownMenuItem<String>(
              value: item.key,
              child: Text(item.label),
            ),
          ),
    ];

    return SizedBox(
      width: 260,
      child: InputDecorator(
        decoration: const InputDecoration(
          labelText: 'Faixa de Legenda',
          border: OutlineInputBorder(),
          isDense: true,
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            isExpanded: true,
            value: _subtitleSelectionValue(),
            items: items,
            onChanged: (String? value) {
              if (value == null) return;
              unawaited(_selectSubtitleTrack(value));
            },
          ),
        ),
      ),
    );
  }
}
