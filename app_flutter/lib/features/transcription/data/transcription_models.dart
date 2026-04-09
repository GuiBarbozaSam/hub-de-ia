import 'dart:convert';

const Object _copySentinel = Object();
const Object transcriptionPreferenceCopySentinel = _copySentinel;

String _parseString(dynamic value, {String fallback = ''}) {
  if (value == null) return fallback;
  final text = value.toString().trim();
  return text.isEmpty ? fallback : text;
}

bool _parseBool(dynamic value, {bool fallback = false}) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  final text = value?.toString().trim().toLowerCase();
  if (text == null || text.isEmpty) return fallback;
  if (text == 'true' || text == '1' || text == 'yes' || text == 'sim') {
    return true;
  }
  if (text == 'false' ||
      text == '0' ||
      text == 'no' ||
      text == 'nao' ||
      text == 'não') {
    return false;
  }
  return fallback;
}

int _parseInt(dynamic value, {int fallback = 0}) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}

int _clampIntValue(int value, {required int min, required int max}) {
  if (value < min) return min;
  if (value > max) return max;
  return value;
}

double? _parseDoubleNullable(dynamic value) {
  if (value == null) return null;
  if (value is double) return value;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString().replaceAll(',', '.'));
}

DateTime? _parseDate(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  return DateTime.tryParse(value.toString());
}

Map<String, dynamic>? _parseJsonMap(dynamic value) {
  if (value == null) return null;
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map((key, item) => MapEntry(key.toString(), item));
  }
  if (value is String && value.trim().isNotEmpty) {
    try {
      final decoded = jsonDecode(value);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return decoded.map((key, item) => MapEntry(key.toString(), item));
      }
    } catch (_) {}
  }
  return null;
}

List<String> _parseStringList(
  dynamic value, {
  List<String> fallback = const [],
}) {
  if (value is List) {
    return value
        .map((e) => e.toString().trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  if (value is Map) {
    final indexed = value.entries.toList()
      ..sort((a, b) => a.key.toString().compareTo(b.key.toString()));
    return indexed
        .map((entry) => entry.value.toString().trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  if (value is String && value.trim().isNotEmpty) {
    final normalized = value.trim();
    if (normalized.startsWith('[') && normalized.endsWith(']')) {
      try {
        final decoded = jsonDecode(normalized);
        if (decoded is List) {
          return decoded
              .map((e) => e.toString().trim())
              .where((e) => e.isNotEmpty)
              .toList();
        }
      } catch (_) {}
    }

    return normalized
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  return fallback;
}

Map<String, List<String>> _parseStringListMap(dynamic value) {
  final map = _parseJsonMap(value);
  if (map == null) return const <String, List<String>>{};

  final result = <String, List<String>>{};
  for (final entry in map.entries) {
    final key = entry.key.trim();
    if (key.isEmpty) continue;
    result[key] = _parseStringList(entry.value);
  }
  return result;
}

dynamic _firstNonNull(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    if (json.containsKey(key) && json[key] != null) {
      return json[key];
    }
  }
  return null;
}

String _readStringByKeys(
  Map<String, dynamic> json,
  List<String> keys, {
  String fallback = '',
}) {
  return _parseString(_firstNonNull(json, keys), fallback: fallback);
}

List<String> _readStringListByKeys(
  Map<String, dynamic> json,
  List<String> keys, {
  List<String> fallback = const [],
}) {
  for (final key in keys) {
    if (!json.containsKey(key)) continue;
    final parsed = _parseStringList(json[key]);
    final raw = json[key];
    final hadValue =
        raw != null &&
        ((raw is String && raw.trim().isNotEmpty) || raw is List || raw is Map);
    if (parsed.isNotEmpty || hadValue) {
      return parsed;
    }
  }
  return fallback;
}

String? _nullIfBlank(String? value) {
  if (value == null) return null;
  final normalized = value.trim();
  return normalized.isEmpty ? null : normalized;
}

String? _readNullableStringByKeys(
  Map<String, dynamic> json,
  List<String> keys,
) {
  return _nullIfBlank(_readStringByKeys(json, keys));
}

List<String> _normalizeTextOutputs(List<String> values) {
  const order = ['txt', 'srt', 'vtt', 'ass'];
  final set = <String>{};

  for (final raw in values) {
    var normalized = raw.trim().toLowerCase();
    if (normalized == 'text') {
      normalized = 'txt';
    }
    if (order.contains(normalized)) {
      set.add(normalized);
    }
  }

  return order.where(set.contains).toList();
}

List<String> _normalizeRequestedOutputs(List<String> values) {
  const order = ['txt', 'srt', 'vtt', 'ass', 'video_burned'];
  final set = <String>{};

  for (final raw in values) {
    var normalized = raw.trim().toLowerCase();
    if (normalized == 'text') normalized = 'txt';
    if (normalized == 'video-burned') normalized = 'video_burned';
    if (order.contains(normalized)) {
      set.add(normalized);
    }
  }

  return order.where(set.contains).toList();
}

String _canonicalTargetLanguage(String value) {
  switch (value.trim().toLowerCase()) {
    case 'pt-br':
      return 'pt-BR';
    case 'zh-cn':
      return 'zh-CN';
    default:
      return value.trim();
  }
}

List<String> _normalizeTargetLanguages(List<String> values) {
  const order = [
    'pt-BR',
    'en',
    'es',
    'fr',
    'de',
    'it',
    'ja',
    'ko',
    'zh-CN',
    'ru',
    'ar',
    'hi',
  ];

  final set = <String>{};

  for (final raw in values) {
    final normalized = _canonicalTargetLanguage(raw);
    if (normalized.isNotEmpty) {
      set.add(normalized);
    }
  }

  final ordered = <String>[];
  for (final item in order) {
    if (set.contains(item)) {
      ordered.add(item);
    }
  }

  for (final item in set) {
    if (!ordered.contains(item)) {
      ordered.add(item);
    }
  }

  return ordered;
}

String _buildOutputFormat(
  List<String> selectedTextOutputs,
  bool requestVideoBurned,
) {
  final ordered = _normalizeTextOutputs(selectedTextOutputs);
  final legacy = ordered
      .where((item) => item == 'txt' || item == 'srt' || item == 'vtt')
      .toList();

  if (legacy.isEmpty) {
    return requestVideoBurned ? 'video_only' : 'srt';
  }
  if (legacy.length == 3) return 'all';
  return legacy.join('+');
}

List<String> _buildRequestedOutputs(
  List<String> selectedTextOutputs,
  bool requestVideoBurned,
) {
  final outputs = <String>[..._normalizeTextOutputs(selectedTextOutputs)];
  if (requestVideoBurned) {
    outputs.add('video_burned');
  }

  return _normalizeRequestedOutputs(outputs);
}

class UiTranscriptionConstants {
  static const List<String> textOutputOptions = ['txt', 'srt', 'vtt', 'ass'];

  static const List<String> aiModelOptions = [
    'qwen2.5vl:7b',
    'qwen2.5vl:32b',
    'qwen3-vl:30b-a3b-instruct-q4_K_M',
  ];

  static const List<String> subtitleVisualPresets = [
    'default',
    'clean',
    'highlight',
    'cinematic',
    'shorts_bold',
    'shorts_dynamic',
    'shorts_neon',
  ];

  static const List<String> targetLanguageOptions = [
    'pt-BR',
    'en',
    'es',
    'fr',
    'de',
    'it',
    'ja',
    'ko',
    'zh-CN',
    'ru',
    'ar',
    'hi',
  ];

  static const List<String> aiModes = [
    'correction',
    'semantic_translation',
    'subtitle_styling',
  ];

  static const List<String> aiProviders = ['ollama_project', 'remote_api'];

  static const List<String> videoDeliveryModes = [
    'standard',
    'video_only',
    'mux_subtitles',
    'burned_video',
  ];

  static const List<String> alignmentModeOptions = ['auto', 'on', 'off'];

  static const List<String> qualityProfiles = ['safe', 'balanced', 'max'];

  static const List<String> contentModes = ['auto', 'episode', 'anime_song'];

  static const List<String> speakerStyleModes = [
    'off',
    'heuristic',
    'advanced',
  ];

  static const List<String> styleIntensities = [
    'subtle',
    'thematic',
    'expressive',
  ];

  static const List<String> renderedPreviewModes = ['fast', 'rendered'];

  static const List<String> animeSongLayoutModes = [
    'off',
    'romaji_top_translation_bottom',
  ];

  static const List<String> karaokeGranularities = ['off', 'word', 'syllable'];
}

class TranscriptionOptions {
  final List<String> sourceTypes;
  final List<String> jobCreationModes;
  final List<String> models;
  final List<String> tasks;
  final List<String> languages;
  final List<String> outputFormats;
  final List<String> deliveryModes;
  final List<String> devices;
  final List<String> computeTypes;
  final List<String> statuses;
  final List<String> subtitleStyles;
  final List<String> subtitleVisualPresets;
  final List<String> aiProviders;
  final List<String> aiModes;
  final List<String> aiModels;
  final List<String> targetLanguages;
  final List<String> alignmentModes;
  final List<String> qualityProfiles;
  final List<String> contentModes;
  final List<String> speakerStyleModes;
  final List<String> styleIntensities;
  final List<String> renderedPreviewModes;
  final List<String> animeSongLayoutModes;
  final List<String> karaokeGranularities;

  const TranscriptionOptions({
    required this.sourceTypes,
    required this.jobCreationModes,
    required this.models,
    required this.tasks,
    required this.languages,
    required this.outputFormats,
    required this.deliveryModes,
    required this.devices,
    required this.computeTypes,
    required this.statuses,
    required this.subtitleStyles,
    required this.subtitleVisualPresets,
    required this.aiProviders,
    required this.aiModes,
    required this.aiModels,
    required this.targetLanguages,
    required this.alignmentModes,
    required this.qualityProfiles,
    required this.contentModes,
    required this.speakerStyleModes,
    required this.styleIntensities,
    required this.renderedPreviewModes,
    required this.animeSongLayoutModes,
    required this.karaokeGranularities,
  });

  factory TranscriptionOptions.fromJson(Map<String, dynamic> json) {
    List<String> readList(List<String> keys, List<String> fallback) {
      final parsed = _readStringListByKeys(json, keys);
      return parsed.isNotEmpty ? parsed : fallback;
    }

    return TranscriptionOptions(
      sourceTypes: readList(
        const ['sourceTypes', 'SourceTypes'],
        const ['url', 'file_path'],
      ),
      jobCreationModes: readList(
        const ['jobCreationModes', 'JobCreationModes'],
        const ['upload', 'url', 'file_path'],
      ),
      models: readList(
        const ['models', 'Models'],
        const ['tiny', 'base', 'small', 'medium', 'large-v3'],
      ),
      tasks: readList(
        const ['tasks', 'Tasks'],
        const ['transcribe', 'translate'],
      ),
      languages: readList(
        const ['languages', 'Languages'],
        const ['auto', 'pt', 'en', 'es'],
      ),
      outputFormats: readList(
        const ['outputFormats', 'OutputFormats'],
        const ['txt', 'srt', 'vtt', 'ass', 'all', 'video_only'],
      ),
      deliveryModes: readList(const [
        'deliveryModes',
        'DeliveryModes',
      ], UiTranscriptionConstants.videoDeliveryModes),
      devices: readList(
        const ['devices', 'Devices'],
        const ['auto', 'cpu', 'gpu:0', 'gpu:1'],
      ),
      computeTypes: readList(
        const ['computeTypes', 'ComputeTypes'],
        const ['float16', 'int8', 'int8_float16'],
      ),
      statuses: readList(
        const ['statuses', 'Statuses'],
        const ['pending', 'processing', 'completed', 'error', 'canceled'],
      ),
      subtitleStyles: readList(const [
        'subtitleStyles',
        'SubtitleStyles',
      ], UiTranscriptionConstants.subtitleVisualPresets),
      subtitleVisualPresets: readList(const [
        'subtitleVisualPresets',
        'SubtitleVisualPresets',
      ], UiTranscriptionConstants.subtitleVisualPresets),
      aiProviders: readList(const [
        'aiProviders',
        'AiProviders',
      ], UiTranscriptionConstants.aiProviders),
      aiModes: readList(const [
        'aiModes',
        'AiModes',
      ], UiTranscriptionConstants.aiModes),
      aiModels: readList(const [
        'aiModels',
        'AiModels',
      ], UiTranscriptionConstants.aiModelOptions),
      targetLanguages: _normalizeTargetLanguages(
        readList(const [
          'targetLanguages',
          'TargetLanguages',
        ], UiTranscriptionConstants.targetLanguageOptions),
      ),
      alignmentModes: readList(const [
        'alignmentModes',
        'AlignmentModes',
      ], UiTranscriptionConstants.alignmentModeOptions),
      qualityProfiles: readList(const [
        'qualityProfiles',
        'QualityProfiles',
      ], UiTranscriptionConstants.qualityProfiles),
      contentModes: readList(const [
        'contentModes',
        'ContentModes',
      ], UiTranscriptionConstants.contentModes),
      speakerStyleModes: readList(const [
        'speakerStyleModes',
        'SpeakerStyleModes',
      ], UiTranscriptionConstants.speakerStyleModes),
      styleIntensities: readList(const [
        'styleIntensities',
        'StyleIntensities',
      ], UiTranscriptionConstants.styleIntensities),
      renderedPreviewModes: readList(const [
        'renderedPreviewModes',
        'RenderedPreviewModes',
      ], UiTranscriptionConstants.renderedPreviewModes),
      animeSongLayoutModes: readList(const [
        'animeSongLayoutModes',
        'AnimeSongLayoutModes',
      ], UiTranscriptionConstants.animeSongLayoutModes),
      karaokeGranularities: readList(const [
        'karaokeGranularities',
        'KaraokeGranularities',
      ], UiTranscriptionConstants.karaokeGranularities),
    );
  }
}

class TranscriptionContextHints {
  final String? title;
  final String? artist;
  final String? series;
  final String? episode;
  final List<String> urls;

  const TranscriptionContextHints({
    required this.title,
    required this.artist,
    required this.series,
    required this.episode,
    required this.urls,
  });

  factory TranscriptionContextHints.empty() {
    return const TranscriptionContextHints(
      title: null,
      artist: null,
      series: null,
      episode: null,
      urls: <String>[],
    );
  }

  factory TranscriptionContextHints.fromJson(dynamic json) {
    final map = _parseJsonMap(json) ?? const <String, dynamic>{};
    return TranscriptionContextHints(
      title: _readNullableStringByKeys(map, const ['title', 'Title']),
      artist: _readNullableStringByKeys(map, const ['artist', 'Artist']),
      series: _readNullableStringByKeys(map, const ['series', 'Series']),
      episode: _readNullableStringByKeys(map, const ['episode', 'Episode']),
      urls: _parseStringList(map['urls']),
    );
  }

  bool get hasAny =>
      title != null ||
      artist != null ||
      series != null ||
      episode != null ||
      urls.isNotEmpty;

  Map<String, dynamic>? toJsonOrNull() {
    if (!hasAny) return null;
    return <String, dynamic>{
      if (title != null) 'title': title,
      if (artist != null) 'artist': artist,
      if (series != null) 'series': series,
      if (episode != null) 'episode': episode,
      if (urls.isNotEmpty) 'urls': urls,
    };
  }

  TranscriptionContextHints copyWith({
    Object? title = _copySentinel,
    Object? artist = _copySentinel,
    Object? series = _copySentinel,
    Object? episode = _copySentinel,
    List<String>? urls,
  }) {
    return TranscriptionContextHints(
      title: identical(title, _copySentinel)
          ? this.title
          : _nullIfBlank(title as String?),
      artist: identical(artist, _copySentinel)
          ? this.artist
          : _nullIfBlank(artist as String?),
      series: identical(series, _copySentinel)
          ? this.series
          : _nullIfBlank(series as String?),
      episode: identical(episode, _copySentinel)
          ? this.episode
          : _nullIfBlank(episode as String?),
      urls: urls ?? this.urls,
    );
  }
}

class TranscriptionGpuInfo {
  final String name;
  final String vendor;
  final int? memoryTotalBytes;
  final int? memoryAvailableBytes;

  const TranscriptionGpuInfo({
    required this.name,
    required this.vendor,
    required this.memoryTotalBytes,
    required this.memoryAvailableBytes,
  });

  factory TranscriptionGpuInfo.fromJson(Map<String, dynamic> json) {
    return TranscriptionGpuInfo(
      name: _readStringByKeys(json, const ['name', 'Name'], fallback: 'GPU'),
      vendor: _readStringByKeys(json, const ['vendor', 'Vendor']),
      memoryTotalBytes: json['memoryTotalBytes'] == null
          ? null
          : _parseInt(json['memoryTotalBytes']),
      memoryAvailableBytes: json['memoryAvailableBytes'] == null
          ? null
          : _parseInt(json['memoryAvailableBytes']),
    );
  }
}

class TranscriptionHardwareInfo {
  final String device;
  final String provider;
  final String cpuName;
  final int logicalCores;
  final int physicalCores;
  final int ramTotalBytes;
  final int ramAvailableBytes;
  final bool advancedAlignmentAvailable;
  final bool diarizationAvailable;
  final bool voiceAnalysisAvailable;
  final bool sceneAnalysisAvailable;
  final String maxSupportedKaraokeGranularity;
  final List<TranscriptionGpuInfo> gpus;
  final List<String> supportedComputeTypes;

  const TranscriptionHardwareInfo({
    required this.device,
    required this.provider,
    required this.cpuName,
    required this.logicalCores,
    required this.physicalCores,
    required this.ramTotalBytes,
    required this.ramAvailableBytes,
    required this.advancedAlignmentAvailable,
    required this.diarizationAvailable,
    required this.voiceAnalysisAvailable,
    required this.sceneAnalysisAvailable,
    required this.maxSupportedKaraokeGranularity,
    required this.gpus,
    required this.supportedComputeTypes,
  });

  factory TranscriptionHardwareInfo.fromJson(dynamic json) {
    final map = _parseJsonMap(json) ?? const <String, dynamic>{};
    final gpusRaw = map['gpus'];
    return TranscriptionHardwareInfo(
      device: _readStringByKeys(map, const [
        'device',
        'Device',
      ], fallback: 'cpu'),
      provider: _readStringByKeys(map, const ['provider', 'Provider']),
      cpuName: _readStringByKeys(map, const [
        'cpuName',
        'CpuName',
      ], fallback: 'CPU'),
      logicalCores: _parseInt(map['logicalCores'], fallback: 0),
      physicalCores: _parseInt(map['physicalCores'], fallback: 0),
      ramTotalBytes: _parseInt(map['ramTotalBytes'], fallback: 0),
      ramAvailableBytes: _parseInt(map['ramAvailableBytes'], fallback: 0),
      advancedAlignmentAvailable: _parseBool(
        _firstNonNull(map, const [
          'advancedAlignmentAvailable',
          'AdvancedAlignmentAvailable',
        ]),
        fallback: false,
      ),
      diarizationAvailable: _parseBool(
        _firstNonNull(map, const [
          'diarizationAvailable',
          'DiarizationAvailable',
        ]),
        fallback: false,
      ),
      voiceAnalysisAvailable: _parseBool(
        _firstNonNull(map, const [
          'voiceAnalysisAvailable',
          'VoiceAnalysisAvailable',
        ]),
        fallback: true,
      ),
      sceneAnalysisAvailable: _parseBool(
        _firstNonNull(map, const [
          'sceneAnalysisAvailable',
          'SceneAnalysisAvailable',
        ]),
        fallback: true,
      ),
      maxSupportedKaraokeGranularity: _readStringByKeys(map, const [
        'maxSupportedKaraokeGranularity',
        'MaxSupportedKaraokeGranularity',
      ], fallback: 'word'),
      gpus: gpusRaw is List
          ? gpusRaw
                .whereType<Map>()
                .map(
                  (item) => TranscriptionGpuInfo.fromJson(
                    Map<String, dynamic>.from(item),
                  ),
                )
                .toList()
          : const <TranscriptionGpuInfo>[],
      supportedComputeTypes: _parseStringList(
        map['supported_compute_types'] ?? map['supportedComputeTypes'],
      ),
    );
  }
}

class TranscriptionCapabilityPreset {
  final String key;
  final int aiRevisionPasses;
  final String useAdvancedAlignment;
  final bool aiUseVisualContext;
  final int aiChunkChars;
  final int? structuredTimeoutSeconds;
  final int? styleTimeoutSeconds;
  final String? textModel;
  final String? visualModel;
  final String maxSupportedKaraokeGranularity;

  const TranscriptionCapabilityPreset({
    required this.key,
    required this.aiRevisionPasses,
    required this.useAdvancedAlignment,
    required this.aiUseVisualContext,
    required this.aiChunkChars,
    required this.structuredTimeoutSeconds,
    required this.styleTimeoutSeconds,
    required this.textModel,
    required this.visualModel,
    required this.maxSupportedKaraokeGranularity,
  });

  factory TranscriptionCapabilityPreset.fromJson(String key, dynamic json) {
    final map = _parseJsonMap(json) ?? const <String, dynamic>{};
    return TranscriptionCapabilityPreset(
      key: key,
      aiRevisionPasses: _parseInt(map['aiRevisionPasses'], fallback: 3),
      useAdvancedAlignment: _parseString(
        map['useAdvancedAlignment'],
        fallback: 'auto',
      ),
      aiUseVisualContext: _parseBool(map['aiUseVisualContext']),
      aiChunkChars: _parseInt(map['aiChunkChars'], fallback: 1800),
      structuredTimeoutSeconds: map['structuredTimeoutSeconds'] == null
          ? null
          : _parseInt(map['structuredTimeoutSeconds']),
      styleTimeoutSeconds: map['styleTimeoutSeconds'] == null
          ? null
          : _parseInt(map['styleTimeoutSeconds']),
      textModel: _readNullableStringByKeys(map, const [
        'textModel',
        'TextModel',
      ]),
      visualModel: _readNullableStringByKeys(map, const [
        'visualModel',
        'VisualModel',
      ]),
      maxSupportedKaraokeGranularity: _readStringByKeys(map, const [
        'maxSupportedKaraokeGranularity',
        'MaxSupportedKaraokeGranularity',
      ], fallback: 'word'),
    );
  }
}

class TranscriptionRuntimeInfo {
  final String id;
  final String label;
  final bool available;
  final String? baseUrl;
  final String? minimumVersion;
  final List<String> installedModels;
  final List<String> downloadableModels;
  final List<String> multimodalModels;
  final String? modelStorePath;

  const TranscriptionRuntimeInfo({
    required this.id,
    required this.label,
    required this.available,
    required this.baseUrl,
    required this.minimumVersion,
    required this.installedModels,
    required this.downloadableModels,
    required this.multimodalModels,
    required this.modelStorePath,
  });

  factory TranscriptionRuntimeInfo.fromJson(dynamic json) {
    final map = _parseJsonMap(json) ?? const <String, dynamic>{};
    return TranscriptionRuntimeInfo(
      id: _readStringByKeys(map, const ['id', 'Id'], fallback: 'runtime'),
      label: _readStringByKeys(map, const [
        'label',
        'Label',
      ], fallback: 'Runtime'),
      available: _parseBool(
        _firstNonNull(map, const ['available', 'Available']),
      ),
      baseUrl: _readNullableStringByKeys(map, const ['baseUrl', 'BaseUrl']),
      minimumVersion: _readNullableStringByKeys(map, const [
        'minimumVersion',
        'MinimumVersion',
      ]),
      installedModels: _readStringListByKeys(map, const [
        'installedModels',
        'InstalledModels',
      ]),
      downloadableModels: _readStringListByKeys(map, const [
        'downloadableModels',
        'DownloadableModels',
      ]),
      multimodalModels: _readStringListByKeys(map, const [
        'multimodalModels',
        'MultimodalModels',
      ]),
      modelStorePath: _readNullableStringByKeys(map, const [
        'modelStorePath',
        'ModelStorePath',
      ]),
    );
  }
}

class TranscriptionAiProviderInfo {
  final String id;
  final String label;
  final String type;
  final bool available;
  final List<String> installedModels;
  final List<String> downloadableModels;
  final List<String> multimodalModels;
  final String? defaultModel;

  const TranscriptionAiProviderInfo({
    required this.id,
    required this.label,
    required this.type,
    required this.available,
    required this.installedModels,
    required this.downloadableModels,
    required this.multimodalModels,
    required this.defaultModel,
  });

  factory TranscriptionAiProviderInfo.fromJson(dynamic json) {
    final map = _parseJsonMap(json) ?? const <String, dynamic>{};
    return TranscriptionAiProviderInfo(
      id: _readStringByKeys(map, const [
        'id',
        'Id',
      ], fallback: 'ollama_project'),
      label: _readStringByKeys(map, const [
        'label',
        'Label',
      ], fallback: 'Provider'),
      type: _readStringByKeys(map, const ['type', 'Type'], fallback: 'ollama'),
      available: _parseBool(
        _firstNonNull(map, const ['available', 'Available']),
      ),
      installedModels: _readStringListByKeys(map, const [
        'installedModels',
        'InstalledModels',
      ]),
      downloadableModels: _readStringListByKeys(map, const [
        'downloadableModels',
        'DownloadableModels',
      ]),
      multimodalModels: _readStringListByKeys(map, const [
        'multimodalModels',
        'MultimodalModels',
      ]),
      defaultModel: _readNullableStringByKeys(map, const [
        'defaultModel',
        'DefaultModel',
      ]),
    );
  }
}

class TranscriptionCapabilities {
  final String service;
  final bool fasterWhisperInstalled;
  final String defaultModel;
  final String deviceMode;
  final String computeTypeMode;
  final TranscriptionHardwareInfo hardware;
  final Map<String, TranscriptionCapabilityPreset> profiles;
  final String recommendedProfile;
  final bool diarizationAvailable;
  final bool advancedAlignmentAvailable;
  final bool voiceAnalysisAvailable;
  final bool sceneAnalysisAvailable;
  final String maxSupportedKaraokeGranularity;
  final List<String> installedModels;
  final int? jobTimeoutMinutes;
  final int? structuredTimeoutSeconds;
  final int? styleTimeoutSeconds;
  final String? timeoutProfileApplied;
  final TranscriptionRuntimeInfo? projectRuntime;
  final TranscriptionRuntimeInfo? hostRuntime;
  final List<TranscriptionAiProviderInfo> providers;
  final Map<String, List<String>> installedModelsByProvider;
  final Map<String, List<String>> downloadableModelsByProvider;
  final String? activeModelStorePath;

  const TranscriptionCapabilities({
    required this.service,
    required this.fasterWhisperInstalled,
    required this.defaultModel,
    required this.deviceMode,
    required this.computeTypeMode,
    required this.hardware,
    required this.profiles,
    required this.recommendedProfile,
    required this.diarizationAvailable,
    required this.advancedAlignmentAvailable,
    required this.voiceAnalysisAvailable,
    required this.sceneAnalysisAvailable,
    required this.maxSupportedKaraokeGranularity,
    required this.installedModels,
    required this.jobTimeoutMinutes,
    required this.structuredTimeoutSeconds,
    required this.styleTimeoutSeconds,
    required this.timeoutProfileApplied,
    required this.projectRuntime,
    required this.hostRuntime,
    required this.providers,
    required this.installedModelsByProvider,
    required this.downloadableModelsByProvider,
    required this.activeModelStorePath,
  });

  factory TranscriptionCapabilities.fromJson(Map<String, dynamic> json) {
    final profilesRaw =
        _parseJsonMap(_firstNonNull(json, const ['profiles', 'Profiles'])) ??
        const <String, dynamic>{};
    final hardware = TranscriptionHardwareInfo.fromJson(
      _firstNonNull(json, const ['hardware', 'Hardware']),
    );
    return TranscriptionCapabilities(
      service: _readStringByKeys(json, const [
        'service',
        'Service',
      ], fallback: 'transcription'),
      fasterWhisperInstalled: _parseBool(
        _firstNonNull(json, const [
          'fasterWhisperInstalled',
          'FasterWhisperInstalled',
        ]),
      ),
      defaultModel: _readStringByKeys(json, const [
        'defaultModel',
        'DefaultModel',
      ], fallback: 'large-v3'),
      deviceMode: _readStringByKeys(json, const [
        'deviceMode',
        'DeviceMode',
      ], fallback: 'auto'),
      computeTypeMode: _readStringByKeys(json, const [
        'computeTypeMode',
        'ComputeTypeMode',
      ], fallback: 'auto'),
      hardware: hardware,
      profiles: profilesRaw.map(
        (key, value) =>
            MapEntry(key, TranscriptionCapabilityPreset.fromJson(key, value)),
      ),
      recommendedProfile: _readStringByKeys(json, const [
        'recommendedProfile',
        'RecommendedProfile',
      ], fallback: 'balanced'),
      diarizationAvailable: _parseBool(
        _firstNonNull(json, const [
          'diarizationAvailable',
          'DiarizationAvailable',
        ]),
        fallback: hardware.diarizationAvailable,
      ),
      advancedAlignmentAvailable: _parseBool(
        _firstNonNull(json, const [
          'advancedAlignmentAvailable',
          'AdvancedAlignmentAvailable',
        ]),
        fallback: hardware.advancedAlignmentAvailable,
      ),
      voiceAnalysisAvailable: _parseBool(
        _firstNonNull(json, const [
          'voiceAnalysisAvailable',
          'VoiceAnalysisAvailable',
        ]),
        fallback: hardware.voiceAnalysisAvailable,
      ),
      sceneAnalysisAvailable: _parseBool(
        _firstNonNull(json, const [
          'sceneAnalysisAvailable',
          'SceneAnalysisAvailable',
        ]),
        fallback: hardware.sceneAnalysisAvailable,
      ),
      maxSupportedKaraokeGranularity: _readStringByKeys(json, const [
        'maxSupportedKaraokeGranularity',
        'MaxSupportedKaraokeGranularity',
      ], fallback: hardware.maxSupportedKaraokeGranularity),
      installedModels: _readStringListByKeys(json, const [
        'installedModels',
        'InstalledModels',
      ]),
      projectRuntime:
          _parseJsonMap(
                _firstNonNull(json, const ['projectRuntime', 'ProjectRuntime']),
              ) ==
              null
          ? null
          : TranscriptionRuntimeInfo.fromJson(
              _firstNonNull(json, const ['projectRuntime', 'ProjectRuntime']),
            ),
      hostRuntime:
          _parseJsonMap(
                _firstNonNull(json, const ['hostRuntime', 'HostRuntime']),
              ) ==
              null
          ? null
          : TranscriptionRuntimeInfo.fromJson(
              _firstNonNull(json, const ['hostRuntime', 'HostRuntime']),
            ),
      providers:
          ((_firstNonNull(json, const ['providers', 'Providers']) as List?) ??
                  const <dynamic>[])
              .map((item) => TranscriptionAiProviderInfo.fromJson(item))
              .toList(),
      installedModelsByProvider: _parseStringListMap(
        _firstNonNull(json, const [
          'installedModelsByProvider',
          'InstalledModelsByProvider',
        ]),
      ),
      downloadableModelsByProvider: _parseStringListMap(
        _firstNonNull(json, const [
          'downloadableModelsByProvider',
          'DownloadableModelsByProvider',
        ]),
      ),
      activeModelStorePath: _readNullableStringByKeys(json, const [
        'activeModelStorePath',
        'ActiveModelStorePath',
      ]),
      jobTimeoutMinutes:
          _firstNonNull(json, const [
                'jobTimeoutMinutes',
                'JobTimeoutMinutes',
              ]) ==
              null
          ? null
          : _parseInt(
              _firstNonNull(json, const [
                'jobTimeoutMinutes',
                'JobTimeoutMinutes',
              ]),
            ),
      structuredTimeoutSeconds:
          _firstNonNull(json, const [
                'structuredTimeoutSeconds',
                'StructuredTimeoutSeconds',
              ]) ==
              null
          ? null
          : _parseInt(
              _firstNonNull(json, const [
                'structuredTimeoutSeconds',
                'StructuredTimeoutSeconds',
              ]),
            ),
      styleTimeoutSeconds:
          _firstNonNull(json, const [
                'styleTimeoutSeconds',
                'StyleTimeoutSeconds',
              ]) ==
              null
          ? null
          : _parseInt(
              _firstNonNull(json, const [
                'styleTimeoutSeconds',
                'StyleTimeoutSeconds',
              ]),
            ),
      timeoutProfileApplied: _readNullableStringByKeys(json, const [
        'timeoutProfileApplied',
        'TimeoutProfileApplied',
      ]),
    );
  }

  List<String> installedModelsForProvider(String provider) =>
      installedModelsByProvider[provider] ?? const <String>[];

  List<String> downloadableModelsForProvider(String provider) =>
      downloadableModelsByProvider[provider] ?? const <String>[];

  TranscriptionAiProviderInfo? providerById(String provider) {
    for (final item in providers) {
      if (item.id == provider) return item;
    }
    return null;
  }
}

class TranscriptionPreference {
  final String sourceTypeDefault;
  final String model;
  final String task;
  final String language;
  final String outputFormat;
  final bool generateSubtitles;
  final bool burnSubtitlesIntoVideo;
  final bool keepTimestamps;
  final bool splitBySentence;
  final bool wordTimestamps;
  final bool vadFilter;
  final String devicePreference;
  final String computeType;
  final int beamSize;
  final int? maxSubtitleChars;
  final String subtitleStyle;
  final String subtitleVisualPreset;
  final List<String> selectedTextOutputs;
  final bool requestVideoBurned;

  final List<String> targetLanguages;
  final String videoDeliveryMode;

  final bool aiEnhancementEnabled;
  final String aiProvider;
  final String aiModel;
  final String aiMode;
  final String? aiPrompt;
  final double aiTemperature;
  final double aiTopP;
  final int aiMaxTokens;
  final int aiChunkChars;
  final bool aiUseVisualContext;
  final int aiFrameSampleSeconds;
  final bool preserveTimestamps;
  final int aiRevisionPasses;
  final String useAdvancedAlignment;
  final bool enableOnlineContext;
  final TranscriptionContextHints? contextHints;
  final String qualityProfile;
  final String contentMode;
  final String speakerStyleMode;
  final String styleIntensity;
  final String renderedPreviewMode;
  final String animeSongLayoutMode;
  final String karaokeGranularity;

  const TranscriptionPreference({
    required this.sourceTypeDefault,
    required this.model,
    required this.task,
    required this.language,
    required this.outputFormat,
    required this.generateSubtitles,
    required this.burnSubtitlesIntoVideo,
    required this.keepTimestamps,
    required this.splitBySentence,
    required this.wordTimestamps,
    required this.vadFilter,
    required this.devicePreference,
    required this.computeType,
    required this.beamSize,
    required this.maxSubtitleChars,
    required this.subtitleStyle,
    required this.subtitleVisualPreset,
    required this.selectedTextOutputs,
    required this.requestVideoBurned,
    required this.targetLanguages,
    required this.videoDeliveryMode,
    required this.aiEnhancementEnabled,
    required this.aiProvider,
    required this.aiModel,
    required this.aiMode,
    required this.aiPrompt,
    required this.aiTemperature,
    required this.aiTopP,
    required this.aiMaxTokens,
    required this.aiChunkChars,
    required this.aiUseVisualContext,
    required this.aiFrameSampleSeconds,
    required this.preserveTimestamps,
    required this.aiRevisionPasses,
    required this.useAdvancedAlignment,
    required this.enableOnlineContext,
    required this.contextHints,
    required this.qualityProfile,
    required this.contentMode,
    required this.speakerStyleMode,
    required this.styleIntensity,
    required this.renderedPreviewMode,
    required this.animeSongLayoutMode,
    required this.karaokeGranularity,
  });

  factory TranscriptionPreference.defaults() {
    return const TranscriptionPreference(
      sourceTypeDefault: 'file_path',
      model: 'large-v3',
      task: 'transcribe',
      language: 'auto',
      outputFormat: 'srt',
      generateSubtitles: true,
      burnSubtitlesIntoVideo: false,
      keepTimestamps: true,
      splitBySentence: true,
      wordTimestamps: false,
      vadFilter: true,
      devicePreference: 'auto',
      computeType: 'float16',
      beamSize: 5,
      maxSubtitleChars: 42,
      subtitleStyle: 'default',
      subtitleVisualPreset: 'default',
      selectedTextOutputs: ['srt'],
      requestVideoBurned: false,
      targetLanguages: [],
      videoDeliveryMode: 'standard',
      aiEnhancementEnabled: false,
      aiProvider: 'ollama_project',
      aiModel: 'qwen2.5vl:7b',
      aiMode: 'correction',
      aiPrompt: null,
      aiTemperature: 0.2,
      aiTopP: 0.9,
      aiMaxTokens: 1024,
      aiChunkChars: 6000,
      aiUseVisualContext: false,
      aiFrameSampleSeconds: 12,
      preserveTimestamps: true,
      aiRevisionPasses: 3,
      useAdvancedAlignment: 'auto',
      enableOnlineContext: false,
      contextHints: null,
      qualityProfile: 'balanced',
      contentMode: 'episode',
      speakerStyleMode: 'heuristic',
      styleIntensity: 'thematic',
      renderedPreviewMode: 'fast',
      animeSongLayoutMode: 'off',
      karaokeGranularity: 'off',
    );
  }

  factory TranscriptionPreference.fromJson(Map<String, dynamic> json) {
    final requestedOutputs = _normalizeRequestedOutputs(
      _readStringListByKeys(json, const [
        'requestedOutputs',
        'RequestedOutputs',
        'requested_outputs',
        'requestedOutputsCsv',
        'RequestedOutputsCsv',
        'requested_outputs_csv',
      ]),
    );

    final outputFormat = _readStringByKeys(json, const [
      'outputFormat',
      'OutputFormat',
      'output_format',
    ], fallback: 'srt');

    final requestedTextOutputs = _normalizeTextOutputs(
      requestedOutputs.isNotEmpty
          ? requestedOutputs.where((item) => item != 'video_burned').toList()
          : switch (outputFormat.toLowerCase()) {
              'all' => const ['txt', 'srt', 'vtt'],
              'video_only' || 'video_burned' => const <String>[],
              final value when value.contains('+') => value.split('+'),
              final value => [value],
            },
    );

    final requestVideo =
        requestedOutputs.contains('video_burned') ||
        _parseBool(
          _firstNonNull(json, const [
            'burnSubtitlesIntoVideo',
            'BurnSubtitlesIntoVideo',
            'burn_subtitles_into_video',
          ]),
          fallback: false,
        ) ||
        outputFormat.toLowerCase() == 'video_only';

    final subtitleVisualPreset = _readStringByKeys(json, const [
      'subtitleVisualPreset',
      'SubtitleVisualPreset',
      'subtitle_visual_preset',
      'subtitleStyle',
      'SubtitleStyle',
      'subtitle_style',
    ], fallback: 'default');

    final resolvedOutputFormat = _buildOutputFormat(
      requestedTextOutputs,
      requestVideo,
    );
    final resolvedGenerateSubtitles =
        requestVideo || requestedTextOutputs.any((x) => x != 'txt');

    return TranscriptionPreference(
      sourceTypeDefault: _readStringByKeys(json, const [
        'sourceTypeDefault',
        'SourceTypeDefault',
        'source_type_default',
      ], fallback: 'file_path'),
      model: _readStringByKeys(json, const [
        'model',
        'Model',
      ], fallback: 'large-v3'),
      task: _readStringByKeys(json, const [
        'task',
        'Task',
      ], fallback: 'transcribe'),
      language: _readStringByKeys(json, const [
        'language',
        'Language',
      ], fallback: 'auto'),
      outputFormat: resolvedOutputFormat,
      generateSubtitles: resolvedGenerateSubtitles,
      burnSubtitlesIntoVideo: requestVideo,
      keepTimestamps: _parseBool(
        _firstNonNull(json, const [
          'keepTimestamps',
          'KeepTimestamps',
          'keep_timestamps',
        ]),
        fallback: true,
      ),
      splitBySentence: _parseBool(
        _firstNonNull(json, const [
          'splitBySentence',
          'SplitBySentence',
          'split_by_sentence',
        ]),
        fallback: true,
      ),
      wordTimestamps: _parseBool(
        _firstNonNull(json, const [
          'wordTimestamps',
          'WordTimestamps',
          'word_timestamps',
        ]),
        fallback: false,
      ),
      vadFilter: _parseBool(
        _firstNonNull(json, const ['vadFilter', 'VadFilter', 'vad_filter']),
        fallback: true,
      ),
      devicePreference: _readStringByKeys(json, const [
        'devicePreference',
        'DevicePreference',
        'device_preference',
      ], fallback: 'auto'),
      computeType: _readStringByKeys(json, const [
        'computeType',
        'ComputeType',
        'compute_type',
      ], fallback: 'float16'),
      beamSize: _parseInt(
        _firstNonNull(json, const ['beamSize', 'BeamSize', 'beam_size']),
        fallback: 5,
      ),
      maxSubtitleChars:
          _firstNonNull(json, const [
                'maxSubtitleChars',
                'MaxSubtitleChars',
                'max_subtitle_chars',
              ]) ==
              null
          ? null
          : _parseInt(
              _firstNonNull(json, const [
                'maxSubtitleChars',
                'MaxSubtitleChars',
                'max_subtitle_chars',
              ]),
              fallback: 42,
            ),
      subtitleStyle: _readStringByKeys(json, const [
        'subtitleStyle',
        'SubtitleStyle',
        'subtitle_style',
      ], fallback: subtitleVisualPreset),
      subtitleVisualPreset: subtitleVisualPreset,
      selectedTextOutputs: requestedTextOutputs,
      requestVideoBurned: requestVideo,
      targetLanguages: _normalizeTargetLanguages(
        _readStringListByKeys(json, const [
          'targetLanguages',
          'TargetLanguages',
          'target_languages',
          'targetLanguagesCsv',
          'TargetLanguagesCsv',
          'target_languages_csv',
        ]),
      ),
      videoDeliveryMode: _readStringByKeys(json, const [
        'videoDeliveryMode',
        'VideoDeliveryMode',
        'video_delivery_mode',
        'deliveryMode',
        'DeliveryMode',
        'delivery_mode',
      ], fallback: requestVideo ? 'burned_video' : 'standard'),
      aiEnhancementEnabled: _parseBool(
        _firstNonNull(json, const [
          'aiEnhancementEnabled',
          'AiEnhancementEnabled',
          'ai_enhancement_enabled',
        ]),
        fallback: false,
      ),
      aiProvider: _readStringByKeys(json, const [
        'aiProvider',
        'AiProvider',
        'ai_provider',
      ], fallback: 'ollama_project'),
      aiModel: _readStringByKeys(json, const [
        'aiModel',
        'AiModel',
        'ai_model',
      ], fallback: 'qwen2.5vl:7b'),
      aiMode: _readStringByKeys(
        json,
        const ['aiMode', 'AiMode', 'ai_mode'],
        fallback:
            _readStringByKeys(json, const [
                  'task',
                  'Task',
                ], fallback: 'transcribe') ==
                'translate'
            ? 'semantic_translation'
            : 'correction',
      ),
      aiPrompt: _readNullableStringByKeys(json, const [
        'aiPrompt',
        'AiPrompt',
        'ai_prompt',
      ]),
      aiTemperature:
          _parseDoubleNullable(
            _firstNonNull(json, const [
              'aiTemperature',
              'AiTemperature',
              'ai_temperature',
            ]),
          ) ??
          0.2,
      aiTopP:
          _parseDoubleNullable(
            _firstNonNull(json, const ['aiTopP', 'AiTopP', 'ai_top_p']),
          ) ??
          0.9,
      aiMaxTokens: _parseInt(
        _firstNonNull(json, const [
          'aiMaxTokens',
          'AiMaxTokens',
          'ai_max_tokens',
        ]),
        fallback: 1024,
      ),
      aiChunkChars: _parseInt(
        _firstNonNull(json, const [
          'aiChunkChars',
          'AiChunkChars',
          'ai_chunk_chars',
        ]),
        fallback: 6000,
      ),
      aiUseVisualContext: _parseBool(
        _firstNonNull(json, const [
          'aiUseVisualContext',
          'AiUseVisualContext',
          'ai_use_visual_context',
        ]),
        fallback: false,
      ),
      aiFrameSampleSeconds: _parseInt(
        _firstNonNull(json, const [
          'aiFrameSampleSeconds',
          'AiFrameSampleSeconds',
          'ai_frame_sample_seconds',
        ]),
        fallback: 12,
      ),
      preserveTimestamps: _parseBool(
        _firstNonNull(json, const [
          'preserveTimestamps',
          'PreserveTimestamps',
          'preserve_timestamps',
        ]),
        fallback: true,
      ),
      aiRevisionPasses: _clampIntValue(
        _parseInt(
          _firstNonNull(json, const [
            'aiRevisionPasses',
            'AiRevisionPasses',
            'ai_revision_passes',
          ]),
          fallback: 3,
        ),
        min: 0,
        max: 10,
      ),
      useAdvancedAlignment: _readStringByKeys(json, const [
        'useAdvancedAlignment',
        'UseAdvancedAlignment',
        'use_advanced_alignment',
      ], fallback: 'auto'),
      enableOnlineContext: _parseBool(
        _firstNonNull(json, const [
          'enableOnlineContext',
          'EnableOnlineContext',
          'enable_online_context',
        ]),
        fallback: false,
      ),
      contextHints:
          _parseJsonMap(
                _firstNonNull(json, const [
                  'contextHints',
                  'ContextHints',
                  'context_hints',
                ]),
              ) ==
              null
          ? null
          : TranscriptionContextHints.fromJson(
              _firstNonNull(json, const [
                'contextHints',
                'ContextHints',
                'context_hints',
              ]),
            ),
      qualityProfile: _readStringByKeys(json, const [
        'qualityProfile',
        'QualityProfile',
        'quality_profile',
      ], fallback: 'balanced'),
      contentMode: _readStringByKeys(json, const [
        'contentMode',
        'ContentMode',
        'content_mode',
      ], fallback: 'episode'),
      speakerStyleMode: _readStringByKeys(json, const [
        'speakerStyleMode',
        'SpeakerStyleMode',
        'speaker_style_mode',
      ], fallback: 'heuristic'),
      styleIntensity: _readStringByKeys(json, const [
        'styleIntensity',
        'StyleIntensity',
        'style_intensity',
      ], fallback: 'thematic'),
      renderedPreviewMode: _readStringByKeys(json, const [
        'renderedPreviewMode',
        'RenderedPreviewMode',
        'rendered_preview_mode',
      ], fallback: 'fast'),
      animeSongLayoutMode: _readStringByKeys(json, const [
        'animeSongLayoutMode',
        'AnimeSongLayoutMode',
        'anime_song_layout_mode',
      ], fallback: 'off'),
      karaokeGranularity: _readStringByKeys(json, const [
        'karaokeGranularity',
        'KaraokeGranularity',
        'karaoke_granularity',
      ], fallback: 'off'),
    );
  }

  Map<String, dynamic> toBackendJson() {
    final selectedTexts = _normalizeTextOutputs(selectedTextOutputs);
    final normalizedTargets = _normalizeTargetLanguages(targetLanguages);
    final requestVideo = requestVideoBurned;
    final resolvedOutputFormat = _buildOutputFormat(
      selectedTexts,
      requestVideo,
    );
    final requestedOutputs = _buildRequestedOutputs(
      selectedTexts,
      requestVideo,
    );
    final resolvedGenerateSubtitles =
        requestVideo || selectedTexts.any((item) => item != 'txt');

    return {
      'sourceTypeDefault': sourceTypeDefault,
      'model': model,
      'task': task,
      'language': language,
      'outputFormat': resolvedOutputFormat,
      'requestedOutputs': requestedOutputs,
      'requestedOutputsCsv': requestedOutputs.join(','),
      'deliveryMode': videoDeliveryMode,
      'generateSubtitles': resolvedGenerateSubtitles,
      'burnSubtitlesIntoVideo': requestVideo,
      'keepTimestamps': keepTimestamps,
      'splitBySentence': splitBySentence,
      'wordTimestamps': wordTimestamps,
      'vadFilter': vadFilter,
      'devicePreference': devicePreference,
      'computeType': computeType,
      'beamSize': beamSize,
      'maxSubtitleChars': maxSubtitleChars,
      'subtitleStyle': subtitleStyle,
      'subtitleVisualPreset': subtitleVisualPreset,
      'targetLanguages': normalizedTargets,
      'targetLanguagesCsv': normalizedTargets.join(','),
      'videoDeliveryMode': videoDeliveryMode,
      'aiEnhancementEnabled': aiEnhancementEnabled,
      'aiProvider': aiProvider,
      'aiModel': aiModel,
      'aiMode': aiMode,
      'aiPrompt': aiPrompt,
      'aiTemperature': aiTemperature,
      'aiTopP': aiTopP,
      'aiMaxTokens': aiMaxTokens,
      'aiChunkChars': aiChunkChars,
      'aiUseVisualContext': aiUseVisualContext,
      'aiFrameSampleSeconds': aiFrameSampleSeconds,
      'preserveTimestamps': preserveTimestamps,
      'aiRevisionPasses': _clampIntValue(aiRevisionPasses, min: 0, max: 10),
      'useAdvancedAlignment': useAdvancedAlignment,
      'enableOnlineContext': enableOnlineContext,
      'contextHints': contextHints?.toJsonOrNull(),
      'qualityProfile': qualityProfile,
      'contentMode': contentMode,
      'speakerStyleMode': speakerStyleMode,
      'styleIntensity': styleIntensity,
      'renderedPreviewMode': renderedPreviewMode,
      'animeSongLayoutMode': animeSongLayoutMode,
      'karaokeGranularity': karaokeGranularity,
    };
  }

  Map<String, dynamic> toJson() => toBackendJson();

  Map<String, dynamic> toUiOverlayJson() {
    return {
      'selectedTextOutputs': selectedTextOutputs,
      'requestVideoBurned': requestVideoBurned,
      'subtitleVisualPreset': subtitleVisualPreset,
      'targetLanguages': targetLanguages,
      'videoDeliveryMode': videoDeliveryMode,
      'aiEnhancementEnabled': aiEnhancementEnabled,
      'aiProvider': aiProvider,
      'aiModel': aiModel,
      'aiMode': aiMode,
      'aiPrompt': aiPrompt,
      'aiTemperature': aiTemperature,
      'aiTopP': aiTopP,
      'aiMaxTokens': aiMaxTokens,
      'aiChunkChars': aiChunkChars,
      'aiUseVisualContext': aiUseVisualContext,
      'aiFrameSampleSeconds': aiFrameSampleSeconds,
      'preserveTimestamps': preserveTimestamps,
      'aiRevisionPasses': aiRevisionPasses,
      'useAdvancedAlignment': useAdvancedAlignment,
      'enableOnlineContext': enableOnlineContext,
      'contextHints': contextHints?.toJsonOrNull(),
      'qualityProfile': qualityProfile,
      'contentMode': contentMode,
      'speakerStyleMode': speakerStyleMode,
      'styleIntensity': styleIntensity,
      'renderedPreviewMode': renderedPreviewMode,
      'animeSongLayoutMode': animeSongLayoutMode,
      'karaokeGranularity': karaokeGranularity,
      'maxSubtitleChars': maxSubtitleChars,
    };
  }

  TranscriptionPreference applyUiOverlay(Map<String, dynamic> overlay) {
    final hasPrompt = overlay.containsKey('aiPrompt');
    final hasMaxSubtitleChars = overlay.containsKey('maxSubtitleChars');
    final hasContextHints = overlay.containsKey('contextHints');

    return copyWith(
      selectedTextOutputs: _normalizeTextOutputs(
        _parseStringList(
          overlay['selectedTextOutputs'],
          fallback: selectedTextOutputs,
        ),
      ),
      requestVideoBurned: _parseBool(
        overlay['requestVideoBurned'],
        fallback: requestVideoBurned,
      ),
      subtitleVisualPreset: _parseString(
        overlay['subtitleVisualPreset'],
        fallback: subtitleVisualPreset,
      ),
      targetLanguages: _normalizeTargetLanguages(
        _parseStringList(overlay['targetLanguages'], fallback: targetLanguages),
      ),
      videoDeliveryMode: _parseString(
        overlay['videoDeliveryMode'],
        fallback: videoDeliveryMode,
      ),
      aiEnhancementEnabled: _parseBool(
        overlay['aiEnhancementEnabled'],
        fallback: aiEnhancementEnabled,
      ),
      aiProvider: _parseString(overlay['aiProvider'], fallback: aiProvider),
      aiModel: _parseString(overlay['aiModel'], fallback: aiModel),
      aiMode: _parseString(overlay['aiMode'], fallback: aiMode),
      aiPrompt: hasPrompt
          ? _nullIfBlank(_parseString(overlay['aiPrompt']))
          : _copySentinel,
      aiTemperature:
          _parseDoubleNullable(overlay['aiTemperature']) ?? aiTemperature,
      aiTopP: _parseDoubleNullable(overlay['aiTopP']) ?? aiTopP,
      aiMaxTokens: _parseInt(overlay['aiMaxTokens'], fallback: aiMaxTokens),
      aiChunkChars: _parseInt(overlay['aiChunkChars'], fallback: aiChunkChars),
      aiUseVisualContext: _parseBool(
        overlay['aiUseVisualContext'],
        fallback: aiUseVisualContext,
      ),
      aiFrameSampleSeconds: _parseInt(
        overlay['aiFrameSampleSeconds'],
        fallback: aiFrameSampleSeconds,
      ),
      preserveTimestamps: _parseBool(
        overlay['preserveTimestamps'],
        fallback: preserveTimestamps,
      ),
      aiRevisionPasses: _clampIntValue(
        _parseInt(overlay['aiRevisionPasses'], fallback: aiRevisionPasses),
        min: 0,
        max: 10,
      ),
      useAdvancedAlignment: _parseString(
        overlay['useAdvancedAlignment'],
        fallback: useAdvancedAlignment,
      ),
      enableOnlineContext: _parseBool(
        overlay['enableOnlineContext'],
        fallback: enableOnlineContext,
      ),
      contextHints: hasContextHints
          ? (_parseJsonMap(overlay['contextHints']) == null
                ? null
                : TranscriptionContextHints.fromJson(overlay['contextHints']))
          : contextHints,
      qualityProfile: _parseString(
        overlay['qualityProfile'],
        fallback: qualityProfile,
      ),
      contentMode: _parseString(overlay['contentMode'], fallback: contentMode),
      speakerStyleMode: _parseString(
        overlay['speakerStyleMode'],
        fallback: speakerStyleMode,
      ),
      styleIntensity: _parseString(
        overlay['styleIntensity'],
        fallback: styleIntensity,
      ),
      renderedPreviewMode: _parseString(
        overlay['renderedPreviewMode'],
        fallback: renderedPreviewMode,
      ),
      animeSongLayoutMode: _parseString(
        overlay['animeSongLayoutMode'],
        fallback: animeSongLayoutMode,
      ),
      karaokeGranularity: _parseString(
        overlay['karaokeGranularity'],
        fallback: karaokeGranularity,
      ),
      maxSubtitleChars: hasMaxSubtitleChars
          ? (overlay['maxSubtitleChars'] == null
                ? null
                : _parseInt(
                    overlay['maxSubtitleChars'],
                    fallback: maxSubtitleChars ?? 42,
                  ))
          : _copySentinel,
    );
  }

  TranscriptionPreference normalizedForUi() {
    final normalizedAiModes = _parseStringList(aiMode)
        .map((item) => item.trim().toLowerCase())
        .where((item) => item.isNotEmpty)
        .toSet();
    final stylingEnabled =
        aiEnhancementEnabled && normalizedAiModes.contains('subtitle_styling');
    final normalizedTexts = _normalizeTextOutputs([
      ...selectedTextOutputs,
      if (stylingEnabled) 'ass',
    ]);
    final normalizedTargets = _normalizeTargetLanguages(targetLanguages);

    var normalizedRequestVideo = requestVideoBurned;
    var normalizedVideoDeliveryMode = videoDeliveryMode;
    var normalizedAlignment = useAdvancedAlignment.trim().toLowerCase();
    var normalizedQualityProfile = qualityProfile.trim().toLowerCase();
    var normalizedContentMode = contentMode.trim().toLowerCase();
    var normalizedSpeakerStyleMode = speakerStyleMode.trim().toLowerCase();
    var normalizedStyleIntensity = styleIntensity.trim().toLowerCase();
    var normalizedRenderedPreviewMode = renderedPreviewMode
        .trim()
        .toLowerCase();
    var normalizedAnimeSongLayoutMode = animeSongLayoutMode
        .trim()
        .toLowerCase();
    var normalizedKaraokeGranularity = karaokeGranularity.trim().toLowerCase();

    if (task == 'translate' && normalizedTargets.length > 1) {
      normalizedRequestVideo = false;
      if (normalizedVideoDeliveryMode == 'burned_video' ||
          normalizedVideoDeliveryMode == 'standard') {
        normalizedVideoDeliveryMode = 'mux_subtitles';
      }
    }

    if (!UiTranscriptionConstants.videoDeliveryModes.contains(
      normalizedVideoDeliveryMode,
    )) {
      normalizedVideoDeliveryMode = normalizedRequestVideo
          ? 'burned_video'
          : 'standard';
    }

    if (!UiTranscriptionConstants.alignmentModeOptions.contains(
      normalizedAlignment,
    )) {
      normalizedAlignment = 'auto';
    }

    if (!UiTranscriptionConstants.qualityProfiles.contains(
      normalizedQualityProfile,
    )) {
      normalizedQualityProfile = 'balanced';
    }

    if (!UiTranscriptionConstants.contentModes.contains(
      normalizedContentMode,
    )) {
      normalizedContentMode = 'episode';
    }
    if (!UiTranscriptionConstants.speakerStyleModes.contains(
      normalizedSpeakerStyleMode,
    )) {
      normalizedSpeakerStyleMode = 'heuristic';
    }
    if (!UiTranscriptionConstants.styleIntensities.contains(
      normalizedStyleIntensity,
    )) {
      normalizedStyleIntensity = 'thematic';
    }
    if (!UiTranscriptionConstants.renderedPreviewModes.contains(
      normalizedRenderedPreviewMode,
    )) {
      normalizedRenderedPreviewMode = 'fast';
    }
    if (normalizedContentMode == 'anime_song') {
      normalizedAnimeSongLayoutMode = 'romaji_top_translation_bottom';
      if (!UiTranscriptionConstants.karaokeGranularities.contains(
            normalizedKaraokeGranularity,
          ) ||
          normalizedKaraokeGranularity == 'off') {
        normalizedKaraokeGranularity = 'syllable';
      }
    } else if (normalizedContentMode == 'auto') {
      if (!UiTranscriptionConstants.karaokeGranularities.contains(
        normalizedKaraokeGranularity,
      )) {
        normalizedKaraokeGranularity = 'off';
      }
      if (!UiTranscriptionConstants.animeSongLayoutModes.contains(
        normalizedAnimeSongLayoutMode,
      )) {
        normalizedAnimeSongLayoutMode = 'off';
      }
    } else if (!UiTranscriptionConstants.animeSongLayoutModes.contains(
      normalizedAnimeSongLayoutMode,
    )) {
      normalizedAnimeSongLayoutMode = 'off';
      normalizedKaraokeGranularity = 'off';
    } else {
      normalizedKaraokeGranularity = 'off';
    }

    return copyWith(
      selectedTextOutputs: normalizedTexts,
      requestVideoBurned: normalizedRequestVideo,
      burnSubtitlesIntoVideo: normalizedRequestVideo,
      outputFormat: _buildOutputFormat(normalizedTexts, normalizedRequestVideo),
      generateSubtitles:
          normalizedRequestVideo || normalizedTexts.any((x) => x != 'txt'),
      targetLanguages: normalizedTargets,
      videoDeliveryMode: normalizedVideoDeliveryMode,
      aiRevisionPasses: _clampIntValue(aiRevisionPasses, min: 0, max: 10),
      useAdvancedAlignment: normalizedAlignment,
      qualityProfile: normalizedQualityProfile,
      contentMode: normalizedContentMode,
      speakerStyleMode: normalizedSpeakerStyleMode,
      styleIntensity: normalizedStyleIntensity,
      renderedPreviewMode: normalizedRenderedPreviewMode,
      animeSongLayoutMode: normalizedAnimeSongLayoutMode,
      karaokeGranularity: normalizedKaraokeGranularity,
    );
  }

  TranscriptionPreference copyWith({
    String? sourceTypeDefault,
    String? model,
    String? task,
    String? language,
    String? outputFormat,
    bool? generateSubtitles,
    bool? burnSubtitlesIntoVideo,
    bool? keepTimestamps,
    bool? splitBySentence,
    bool? wordTimestamps,
    bool? vadFilter,
    String? devicePreference,
    String? computeType,
    int? beamSize,
    Object? maxSubtitleChars = _copySentinel,
    String? subtitleStyle,
    String? subtitleVisualPreset,
    List<String>? selectedTextOutputs,
    bool? requestVideoBurned,
    List<String>? targetLanguages,
    String? videoDeliveryMode,
    bool? aiEnhancementEnabled,
    String? aiProvider,
    String? aiModel,
    String? aiMode,
    Object? aiPrompt = _copySentinel,
    double? aiTemperature,
    double? aiTopP,
    int? aiMaxTokens,
    int? aiChunkChars,
    bool? aiUseVisualContext,
    int? aiFrameSampleSeconds,
    bool? preserveTimestamps,
    int? aiRevisionPasses,
    String? useAdvancedAlignment,
    bool? enableOnlineContext,
    Object? contextHints = _copySentinel,
    String? qualityProfile,
    String? contentMode,
    String? speakerStyleMode,
    String? styleIntensity,
    String? renderedPreviewMode,
    String? animeSongLayoutMode,
    String? karaokeGranularity,
  }) {
    return TranscriptionPreference(
      sourceTypeDefault: sourceTypeDefault ?? this.sourceTypeDefault,
      model: model ?? this.model,
      task: task ?? this.task,
      language: language ?? this.language,
      outputFormat: outputFormat ?? this.outputFormat,
      generateSubtitles: generateSubtitles ?? this.generateSubtitles,
      burnSubtitlesIntoVideo:
          burnSubtitlesIntoVideo ?? this.burnSubtitlesIntoVideo,
      keepTimestamps: keepTimestamps ?? this.keepTimestamps,
      splitBySentence: splitBySentence ?? this.splitBySentence,
      wordTimestamps: wordTimestamps ?? this.wordTimestamps,
      vadFilter: vadFilter ?? this.vadFilter,
      devicePreference: devicePreference ?? this.devicePreference,
      computeType: computeType ?? this.computeType,
      beamSize: beamSize ?? this.beamSize,
      maxSubtitleChars: identical(maxSubtitleChars, _copySentinel)
          ? this.maxSubtitleChars
          : maxSubtitleChars as int?,
      subtitleStyle: subtitleStyle ?? this.subtitleStyle,
      subtitleVisualPreset: subtitleVisualPreset ?? this.subtitleVisualPreset,
      selectedTextOutputs: selectedTextOutputs ?? this.selectedTextOutputs,
      requestVideoBurned: requestVideoBurned ?? this.requestVideoBurned,
      targetLanguages: targetLanguages ?? this.targetLanguages,
      videoDeliveryMode: videoDeliveryMode ?? this.videoDeliveryMode,
      aiEnhancementEnabled: aiEnhancementEnabled ?? this.aiEnhancementEnabled,
      aiProvider: aiProvider ?? this.aiProvider,
      aiModel: aiModel ?? this.aiModel,
      aiMode: aiMode ?? this.aiMode,
      aiPrompt: identical(aiPrompt, _copySentinel)
          ? this.aiPrompt
          : aiPrompt as String?,
      aiTemperature: aiTemperature ?? this.aiTemperature,
      aiTopP: aiTopP ?? this.aiTopP,
      aiMaxTokens: aiMaxTokens ?? this.aiMaxTokens,
      aiChunkChars: aiChunkChars ?? this.aiChunkChars,
      aiUseVisualContext: aiUseVisualContext ?? this.aiUseVisualContext,
      aiFrameSampleSeconds: aiFrameSampleSeconds ?? this.aiFrameSampleSeconds,
      preserveTimestamps: preserveTimestamps ?? this.preserveTimestamps,
      aiRevisionPasses: aiRevisionPasses ?? this.aiRevisionPasses,
      useAdvancedAlignment: useAdvancedAlignment ?? this.useAdvancedAlignment,
      enableOnlineContext: enableOnlineContext ?? this.enableOnlineContext,
      contextHints: identical(contextHints, _copySentinel)
          ? this.contextHints
          : contextHints as TranscriptionContextHints?,
      qualityProfile: qualityProfile ?? this.qualityProfile,
      contentMode: contentMode ?? this.contentMode,
      speakerStyleMode: speakerStyleMode ?? this.speakerStyleMode,
      styleIntensity: styleIntensity ?? this.styleIntensity,
      renderedPreviewMode: renderedPreviewMode ?? this.renderedPreviewMode,
      animeSongLayoutMode: animeSongLayoutMode ?? this.animeSongLayoutMode,
      karaokeGranularity: karaokeGranularity ?? this.karaokeGranularity,
    );
  }
}

class CreateJobInput {
  final String sourceType;
  final String sourceValue;
  final String model;
  final String task;
  final String language;
  final String outputFormat;
  final List<String> requestedOutputs;
  final String deliveryMode;
  final bool generateSubtitles;
  final bool burnSubtitlesIntoVideo;
  final bool keepTimestamps;
  final bool splitBySentence;
  final bool wordTimestamps;
  final bool vadFilter;
  final String devicePreference;
  final String computeType;
  final int beamSize;
  final int? maxSubtitleChars;
  final String subtitleStyle;
  final String subtitleVisualPreset;

  final List<String> targetLanguages;
  final String videoDeliveryMode;
  final bool aiEnhancementEnabled;
  final String aiProvider;
  final String aiModel;
  final String aiMode;
  final String? aiPrompt;
  final double aiTemperature;
  final double aiTopP;
  final int aiMaxTokens;
  final int aiChunkChars;
  final bool aiUseVisualContext;
  final int aiFrameSampleSeconds;
  final bool preserveTimestamps;
  final int aiRevisionPasses;
  final String useAdvancedAlignment;
  final bool enableOnlineContext;
  final TranscriptionContextHints? contextHints;
  final String qualityProfile;
  final String contentMode;
  final String speakerStyleMode;
  final String styleIntensity;
  final String renderedPreviewMode;
  final String animeSongLayoutMode;
  final String karaokeGranularity;

  const CreateJobInput({
    required this.sourceType,
    required this.sourceValue,
    required this.model,
    required this.task,
    required this.language,
    required this.outputFormat,
    required this.requestedOutputs,
    required this.deliveryMode,
    required this.generateSubtitles,
    required this.burnSubtitlesIntoVideo,
    required this.keepTimestamps,
    required this.splitBySentence,
    required this.wordTimestamps,
    required this.vadFilter,
    required this.devicePreference,
    required this.computeType,
    required this.beamSize,
    required this.maxSubtitleChars,
    required this.subtitleStyle,
    required this.subtitleVisualPreset,
    required this.targetLanguages,
    required this.videoDeliveryMode,
    required this.aiEnhancementEnabled,
    required this.aiProvider,
    required this.aiModel,
    required this.aiMode,
    required this.aiPrompt,
    required this.aiTemperature,
    required this.aiTopP,
    required this.aiMaxTokens,
    required this.aiChunkChars,
    required this.aiUseVisualContext,
    required this.aiFrameSampleSeconds,
    required this.preserveTimestamps,
    required this.aiRevisionPasses,
    required this.useAdvancedAlignment,
    required this.enableOnlineContext,
    required this.contextHints,
    required this.qualityProfile,
    required this.contentMode,
    required this.speakerStyleMode,
    required this.styleIntensity,
    required this.renderedPreviewMode,
    required this.animeSongLayoutMode,
    required this.karaokeGranularity,
  });

  Map<String, dynamic> toJson() {
    return {
      'sourceType': sourceType,
      'sourceValue': sourceValue,
      'model': model,
      'task': task,
      'language': language,
      'outputFormat': outputFormat,
      'requestedOutputs': requestedOutputs,
      'requestedOutputsCsv': requestedOutputs.join(','),
      'deliveryMode': deliveryMode,
      'generateSubtitles': generateSubtitles,
      'burnSubtitlesIntoVideo': burnSubtitlesIntoVideo,
      'keepTimestamps': keepTimestamps,
      'splitBySentence': splitBySentence,
      'wordTimestamps': wordTimestamps,
      'vadFilter': vadFilter,
      'devicePreference': devicePreference,
      'computeType': computeType,
      'beamSize': beamSize,
      'maxSubtitleChars': maxSubtitleChars,
      'subtitleStyle': subtitleStyle,
      'subtitleVisualPreset': subtitleVisualPreset,
      'targetLanguages': targetLanguages,
      'videoDeliveryMode': videoDeliveryMode,
      'aiEnhancementEnabled': aiEnhancementEnabled,
      'aiProvider': aiProvider,
      'aiModel': aiModel,
      'aiMode': aiMode,
      'aiPrompt': aiPrompt,
      'aiTemperature': aiTemperature,
      'aiTopP': aiTopP,
      'aiMaxTokens': aiMaxTokens,
      'aiChunkChars': aiChunkChars,
      'aiUseVisualContext': aiUseVisualContext,
      'aiFrameSampleSeconds': aiFrameSampleSeconds,
      'preserveTimestamps': preserveTimestamps,
      'aiRevisionPasses': aiRevisionPasses,
      'useAdvancedAlignment': useAdvancedAlignment,
      'enableOnlineContext': enableOnlineContext,
      'contextHints': contextHints?.toJsonOrNull(),
      'qualityProfile': qualityProfile,
      'contentMode': contentMode,
      'speakerStyleMode': speakerStyleMode,
      'styleIntensity': styleIntensity,
      'renderedPreviewMode': renderedPreviewMode,
      'animeSongLayoutMode': animeSongLayoutMode,
      'karaokeGranularity': karaokeGranularity,
    };
  }
}

class CreateUploadJobInput {
  final String filePath;
  final String model;
  final String task;
  final String language;
  final String outputFormat;
  final List<String> requestedOutputs;
  final String deliveryMode;
  final bool generateSubtitles;
  final bool burnSubtitlesIntoVideo;
  final bool keepTimestamps;
  final bool splitBySentence;
  final bool wordTimestamps;
  final bool vadFilter;
  final String devicePreference;
  final String computeType;
  final int beamSize;
  final int? maxSubtitleChars;
  final String subtitleStyle;
  final String subtitleVisualPreset;

  final List<String> targetLanguages;
  final String videoDeliveryMode;
  final bool aiEnhancementEnabled;
  final String aiProvider;
  final String aiModel;
  final String aiMode;
  final String? aiPrompt;
  final double aiTemperature;
  final double aiTopP;
  final int aiMaxTokens;
  final int aiChunkChars;
  final bool aiUseVisualContext;
  final int aiFrameSampleSeconds;
  final bool preserveTimestamps;
  final int aiRevisionPasses;
  final String useAdvancedAlignment;
  final bool enableOnlineContext;
  final TranscriptionContextHints? contextHints;
  final String qualityProfile;
  final String contentMode;
  final String speakerStyleMode;
  final String styleIntensity;
  final String renderedPreviewMode;
  final String animeSongLayoutMode;
  final String karaokeGranularity;

  const CreateUploadJobInput({
    required this.filePath,
    required this.model,
    required this.task,
    required this.language,
    required this.outputFormat,
    required this.requestedOutputs,
    required this.deliveryMode,
    required this.generateSubtitles,
    required this.burnSubtitlesIntoVideo,
    required this.keepTimestamps,
    required this.splitBySentence,
    required this.wordTimestamps,
    required this.vadFilter,
    required this.devicePreference,
    required this.computeType,
    required this.beamSize,
    required this.maxSubtitleChars,
    required this.subtitleStyle,
    required this.subtitleVisualPreset,
    required this.targetLanguages,
    required this.videoDeliveryMode,
    required this.aiEnhancementEnabled,
    required this.aiProvider,
    required this.aiModel,
    required this.aiMode,
    required this.aiPrompt,
    required this.aiTemperature,
    required this.aiTopP,
    required this.aiMaxTokens,
    required this.aiChunkChars,
    required this.aiUseVisualContext,
    required this.aiFrameSampleSeconds,
    required this.preserveTimestamps,
    required this.aiRevisionPasses,
    required this.useAdvancedAlignment,
    required this.enableOnlineContext,
    required this.contextHints,
    required this.qualityProfile,
    required this.contentMode,
    required this.speakerStyleMode,
    required this.styleIntensity,
    required this.renderedPreviewMode,
    required this.animeSongLayoutMode,
    required this.karaokeGranularity,
  });
}

class TranscriptionJobListItem {
  final String id;
  final String sourceType;
  final String sourceValue;
  final String model;
  final String task;
  final String status;
  final int progressPercent;
  final DateTime createdAtUtc;
  final DateTime? finishedAtUtc;

  const TranscriptionJobListItem({
    required this.id,
    required this.sourceType,
    required this.sourceValue,
    required this.model,
    required this.task,
    required this.status,
    required this.progressPercent,
    required this.createdAtUtc,
    required this.finishedAtUtc,
  });

  factory TranscriptionJobListItem.fromJson(Map<String, dynamic> json) {
    return TranscriptionJobListItem(
      id: _parseString(json['id']),
      sourceType: _parseString(json['sourceType']),
      sourceValue: _parseString(json['sourceValue']),
      model: _parseString(json['model']),
      task: _parseString(json['task']),
      status: _parseString(json['status']),
      progressPercent: _parseInt(json['progressPercent']),
      createdAtUtc: _parseDate(json['createdAtUtc']) ?? DateTime.now(),
      finishedAtUtc: _parseDate(json['finishedAtUtc']),
    );
  }

  bool get isActive => status == 'pending' || status == 'processing';
}

class TranscriptionOutput {
  final String id;
  final String outputType;
  final bool hasTextContent;
  final int? contentLength;
  final String? fileName;
  final String? previewUrl;
  final String? previewPageUrl;
  final String? downloadUrl;
  final String contentType;
  final String previewKind;
  final bool canPreviewInline;
  final DateTime createdAtUtc;

  const TranscriptionOutput({
    required this.id,
    required this.outputType,
    required this.hasTextContent,
    required this.contentLength,
    required this.fileName,
    required this.previewUrl,
    required this.previewPageUrl,
    required this.downloadUrl,
    required this.contentType,
    required this.previewKind,
    required this.canPreviewInline,
    required this.createdAtUtc,
  });

  factory TranscriptionOutput.fromJson(Map<String, dynamic> json) {
    return TranscriptionOutput(
      id: _parseString(json['id']),
      outputType: _parseString(json['outputType']),
      hasTextContent: _parseBool(json['hasTextContent']),
      contentLength: json['contentLength'] == null
          ? null
          : _parseInt(json['contentLength']),
      fileName: json['fileName']?.toString(),
      previewUrl: json['previewUrl']?.toString(),
      previewPageUrl: json['previewPageUrl']?.toString(),
      downloadUrl: json['downloadUrl']?.toString(),
      contentType: _parseString(
        json['contentType'],
        fallback: 'application/octet-stream',
      ),
      previewKind: _parseString(json['previewKind'], fallback: 'file'),
      canPreviewInline: _parseBool(json['canPreviewInline']),
      createdAtUtc: _parseDate(json['createdAtUtc']) ?? DateTime.now(),
    );
  }
}

class TranscriptionJobDetail {
  final String id;
  final String sourceType;
  final String sourceValue;
  final String model;
  final String task;
  final String language;
  final String outputFormat;
  final List<String> requestedOutputs;
  final String deliveryMode;
  final bool generateSubtitles;
  final bool burnSubtitlesIntoVideo;
  final bool keepTimestamps;
  final bool splitBySentence;
  final bool wordTimestamps;
  final bool vadFilter;
  final String devicePreference;
  final String computeType;
  final int beamSize;
  final int? maxSubtitleChars;
  final String subtitleStyle;

  final List<String> targetLanguages;
  final String videoDeliveryMode;
  final bool aiEnhancementEnabled;
  final String aiProvider;
  final String aiModel;
  final String aiMode;
  final String? aiPrompt;
  final double? aiTemperature;
  final double? aiTopP;
  final int? aiMaxTokens;
  final int? aiChunkChars;
  final bool aiUseVisualContext;
  final int? aiFrameSampleSeconds;
  final bool preserveTimestamps;
  final int aiRevisionPasses;
  final String useAdvancedAlignment;
  final bool enableOnlineContext;
  final TranscriptionContextHints? contextHints;
  final String qualityProfile;
  final String contentMode;
  final String speakerStyleMode;
  final String styleIntensity;
  final String renderedPreviewMode;
  final String animeSongLayoutMode;
  final String karaokeGranularity;

  final String status;
  final int progressPercent;
  final String? currentStage;
  final int? currentPass;
  final int? totalPasses;
  final String? errorMessage;
  final String? styleSource;
  final String? detectedContentType;
  final double? contentDetectionConfidence;
  final String? speakerModeApplied;
  final String? karaokeModeApplied;
  final String? renderPreviewPath;
  final String? sceneMapPath;
  final String? speakerMapPath;
  final String? lyricAlignmentPath;
  final String? voiceAnalysisSource;
  final String? sceneAnalysisSource;
  final String? previewModeApplied;
  final String? plannerModelUsed;
  final String? reviewModelUsed;
  final String? timeoutProfileApplied;
  final String? requestedAiProvider;
  final String? requestedAiModel;
  final String? effectiveAiProvider;
  final String? effectiveAiModel;
  final String? runtimeTarget;
  final bool? modelInstalledAtSubmission;
  final int? jobTimeoutMinutes;
  final int? structuredTimeoutSeconds;
  final int? styleTimeoutSeconds;
  final double? sourceDurationSeconds;
  final double? outputDurationSeconds;
  final List<Map<String, dynamic>> musicalSegmentDurations;
  final List<Map<String, dynamic>> fallbacks;
  final Map<String, dynamic>? qualitySummary;
  final Map<String, dynamic>? translationStatuses;
  final Map<String, dynamic>? capabilityProfile;
  final List<TranscriptionJobDiagnostic> diagnostics;
  final String? languageDetected;
  final double? durationSeconds;
  final DateTime createdAtUtc;
  final DateTime? startedAtUtc;
  final DateTime? finishedAtUtc;
  final List<TranscriptionOutput> outputs;

  const TranscriptionJobDetail({
    required this.id,
    required this.sourceType,
    required this.sourceValue,
    required this.model,
    required this.task,
    required this.language,
    required this.outputFormat,
    required this.requestedOutputs,
    required this.deliveryMode,
    required this.generateSubtitles,
    required this.burnSubtitlesIntoVideo,
    required this.keepTimestamps,
    required this.splitBySentence,
    required this.wordTimestamps,
    required this.vadFilter,
    required this.devicePreference,
    required this.computeType,
    required this.beamSize,
    required this.maxSubtitleChars,
    required this.subtitleStyle,
    required this.targetLanguages,
    required this.videoDeliveryMode,
    required this.aiEnhancementEnabled,
    required this.aiProvider,
    required this.aiModel,
    required this.aiMode,
    required this.aiPrompt,
    required this.aiTemperature,
    required this.aiTopP,
    required this.aiMaxTokens,
    required this.aiChunkChars,
    required this.aiUseVisualContext,
    required this.aiFrameSampleSeconds,
    required this.preserveTimestamps,
    required this.aiRevisionPasses,
    required this.useAdvancedAlignment,
    required this.enableOnlineContext,
    required this.contextHints,
    required this.qualityProfile,
    required this.contentMode,
    required this.speakerStyleMode,
    required this.styleIntensity,
    required this.renderedPreviewMode,
    required this.animeSongLayoutMode,
    required this.karaokeGranularity,
    required this.status,
    required this.progressPercent,
    required this.currentStage,
    required this.currentPass,
    required this.totalPasses,
    required this.errorMessage,
    required this.styleSource,
    required this.detectedContentType,
    required this.contentDetectionConfidence,
    required this.speakerModeApplied,
    required this.karaokeModeApplied,
    required this.renderPreviewPath,
    required this.sceneMapPath,
    required this.speakerMapPath,
    required this.lyricAlignmentPath,
    required this.voiceAnalysisSource,
    required this.sceneAnalysisSource,
    required this.previewModeApplied,
    required this.plannerModelUsed,
    required this.reviewModelUsed,
    required this.timeoutProfileApplied,
    required this.requestedAiProvider,
    required this.requestedAiModel,
    required this.effectiveAiProvider,
    required this.effectiveAiModel,
    required this.runtimeTarget,
    required this.modelInstalledAtSubmission,
    required this.jobTimeoutMinutes,
    required this.structuredTimeoutSeconds,
    required this.styleTimeoutSeconds,
    required this.sourceDurationSeconds,
    required this.outputDurationSeconds,
    required this.musicalSegmentDurations,
    required this.fallbacks,
    required this.qualitySummary,
    required this.translationStatuses,
    required this.capabilityProfile,
    required this.diagnostics,
    required this.languageDetected,
    required this.durationSeconds,
    required this.createdAtUtc,
    required this.startedAtUtc,
    required this.finishedAtUtc,
    required this.outputs,
  });

  factory TranscriptionJobDetail.fromJson(Map<String, dynamic> json) {
    final outputsRaw = _firstNonNull(json, const ['outputs', 'Outputs']);
    final outputs = (outputsRaw is List)
        ? outputsRaw
              .map(
                (e) =>
                    TranscriptionOutput.fromJson(Map<String, dynamic>.from(e)),
              )
              .toList()
        : <TranscriptionOutput>[];
    final diagnosticsRaw = _firstNonNull(json, const [
      'diagnostics',
      'Diagnostics',
    ]);
    final diagnostics = (diagnosticsRaw is List)
        ? diagnosticsRaw
              .whereType<Map>()
              .map(
                (e) => TranscriptionJobDiagnostic.fromJson(
                  Map<String, dynamic>.from(e),
                ),
              )
              .toList()
        : <TranscriptionJobDiagnostic>[];

    final requestedRaw = _normalizeRequestedOutputs(
      _readStringListByKeys(json, const [
        'requestedOutputs',
        'RequestedOutputs',
        'requested_outputs',
        'requestedOutputsCsv',
        'RequestedOutputsCsv',
        'requested_outputs_csv',
      ]),
    );

    final derivedRequested = requestedRaw.isNotEmpty
        ? requestedRaw
        : _buildRequestedOutputs(
            _normalizeTextOutputs(switch (_readStringByKeys(json, const [
              'outputFormat',
              'OutputFormat',
              'output_format',
            ], fallback: 'srt').toLowerCase()) {
              'all' => const ['txt', 'srt', 'vtt'],
              'video_only' || 'video_burned' => const <String>[],
              final value when value.contains('+') => value.split('+'),
              final value => [value],
            }),
            _parseBool(
              _firstNonNull(json, const [
                'burnSubtitlesIntoVideo',
                'BurnSubtitlesIntoVideo',
                'burn_subtitles_into_video',
              ]),
            ),
          );

    return TranscriptionJobDetail(
      id: _readStringByKeys(json, const ['id', 'Id']),
      sourceType: _readStringByKeys(json, const ['sourceType', 'SourceType']),
      sourceValue: _readStringByKeys(json, const [
        'sourceValue',
        'SourceValue',
      ]),
      model: _readStringByKeys(json, const ['model', 'Model']),
      task: _readStringByKeys(json, const ['task', 'Task']),
      language: _readStringByKeys(json, const ['language', 'Language']),
      outputFormat: _readStringByKeys(json, const [
        'outputFormat',
        'OutputFormat',
        'output_format',
      ]),
      requestedOutputs: derivedRequested,
      deliveryMode: _readStringByKeys(json, const [
        'deliveryMode',
        'DeliveryMode',
        'delivery_mode',
      ], fallback: 'standard'),
      generateSubtitles: _parseBool(
        _firstNonNull(json, const ['generateSubtitles', 'GenerateSubtitles']),
      ),
      burnSubtitlesIntoVideo: _parseBool(
        _firstNonNull(json, const [
          'burnSubtitlesIntoVideo',
          'BurnSubtitlesIntoVideo',
        ]),
      ),
      keepTimestamps: _parseBool(
        _firstNonNull(json, const ['keepTimestamps', 'KeepTimestamps']),
      ),
      splitBySentence: _parseBool(
        _firstNonNull(json, const ['splitBySentence', 'SplitBySentence']),
      ),
      wordTimestamps: _parseBool(
        _firstNonNull(json, const ['wordTimestamps', 'WordTimestamps']),
      ),
      vadFilter: _parseBool(
        _firstNonNull(json, const ['vadFilter', 'VadFilter']),
      ),
      devicePreference: _readStringByKeys(json, const [
        'devicePreference',
        'DevicePreference',
      ]),
      computeType: _readStringByKeys(json, const [
        'computeType',
        'ComputeType',
      ]),
      beamSize: _parseInt(_firstNonNull(json, const ['beamSize', 'BeamSize'])),
      maxSubtitleChars:
          _firstNonNull(json, const ['maxSubtitleChars', 'MaxSubtitleChars']) ==
              null
          ? null
          : _parseInt(
              _firstNonNull(json, const [
                'maxSubtitleChars',
                'MaxSubtitleChars',
              ]),
            ),
      subtitleStyle: _readStringByKeys(json, const [
        'subtitleStyle',
        'SubtitleStyle',
      ]),
      targetLanguages: _normalizeTargetLanguages(
        _readStringListByKeys(json, const [
          'targetLanguages',
          'TargetLanguages',
          'target_languages',
          'targetLanguagesCsv',
          'TargetLanguagesCsv',
        ]),
      ),
      videoDeliveryMode: _readStringByKeys(json, const [
        'videoDeliveryMode',
        'VideoDeliveryMode',
        'video_delivery_mode',
        'deliveryMode',
        'DeliveryMode',
      ], fallback: 'standard'),
      aiEnhancementEnabled: _parseBool(
        _firstNonNull(json, const [
          'aiEnhancementEnabled',
          'AiEnhancementEnabled',
        ]),
      ),
      aiProvider: _readStringByKeys(json, const [
        'aiProvider',
        'AiProvider',
      ], fallback: 'ollama_project'),
      aiModel: _readStringByKeys(json, const ['aiModel', 'AiModel']),
      aiMode: _readStringByKeys(json, const ['aiMode', 'AiMode']),
      aiPrompt: _readNullableStringByKeys(json, const ['aiPrompt', 'AiPrompt']),
      aiTemperature: _parseDoubleNullable(
        _firstNonNull(json, const ['aiTemperature', 'AiTemperature']),
      ),
      aiTopP: _parseDoubleNullable(
        _firstNonNull(json, const ['aiTopP', 'AiTopP']),
      ),
      aiMaxTokens:
          _firstNonNull(json, const ['aiMaxTokens', 'AiMaxTokens']) == null
          ? null
          : _parseInt(
              _firstNonNull(json, const ['aiMaxTokens', 'AiMaxTokens']),
            ),
      aiChunkChars:
          _firstNonNull(json, const ['aiChunkChars', 'AiChunkChars']) == null
          ? null
          : _parseInt(
              _firstNonNull(json, const ['aiChunkChars', 'AiChunkChars']),
            ),
      aiUseVisualContext: _parseBool(
        _firstNonNull(json, const ['aiUseVisualContext', 'AiUseVisualContext']),
      ),
      aiFrameSampleSeconds:
          _firstNonNull(json, const [
                'aiFrameSampleSeconds',
                'AiFrameSampleSeconds',
              ]) ==
              null
          ? null
          : _parseInt(
              _firstNonNull(json, const [
                'aiFrameSampleSeconds',
                'AiFrameSampleSeconds',
              ]),
            ),
      preserveTimestamps: _parseBool(
        _firstNonNull(json, const ['preserveTimestamps', 'PreserveTimestamps']),
        fallback: true,
      ),
      aiRevisionPasses: _parseInt(
        _firstNonNull(json, const ['aiRevisionPasses', 'AiRevisionPasses']),
        fallback: 3,
      ),
      useAdvancedAlignment: _readStringByKeys(json, const [
        'useAdvancedAlignment',
        'UseAdvancedAlignment',
      ], fallback: 'auto'),
      enableOnlineContext: _parseBool(
        _firstNonNull(json, const [
          'enableOnlineContext',
          'EnableOnlineContext',
        ]),
      ),
      contextHints:
          _parseJsonMap(
                _firstNonNull(json, const ['contextHints', 'ContextHints']),
              ) ==
              null
          ? null
          : TranscriptionContextHints.fromJson(
              _firstNonNull(json, const ['contextHints', 'ContextHints']),
            ),
      qualityProfile: _readStringByKeys(json, const [
        'qualityProfile',
        'QualityProfile',
      ], fallback: 'balanced'),
      contentMode: _readStringByKeys(json, const [
        'contentMode',
        'ContentMode',
      ], fallback: 'episode'),
      speakerStyleMode: _readStringByKeys(json, const [
        'speakerStyleMode',
        'SpeakerStyleMode',
      ], fallback: 'heuristic'),
      styleIntensity: _readStringByKeys(json, const [
        'styleIntensity',
        'StyleIntensity',
      ], fallback: 'thematic'),
      renderedPreviewMode: _readStringByKeys(json, const [
        'renderedPreviewMode',
        'RenderedPreviewMode',
      ], fallback: 'fast'),
      animeSongLayoutMode: _readStringByKeys(json, const [
        'animeSongLayoutMode',
        'AnimeSongLayoutMode',
      ], fallback: 'off'),
      karaokeGranularity: _readStringByKeys(json, const [
        'karaokeGranularity',
        'KaraokeGranularity',
      ], fallback: 'off'),
      status: _readStringByKeys(json, const ['status', 'Status']),
      progressPercent: _parseInt(
        _firstNonNull(json, const ['progressPercent', 'ProgressPercent']),
      ),
      currentStage: _readNullableStringByKeys(json, const [
        'currentStage',
        'CurrentStage',
      ]),
      currentPass:
          _firstNonNull(json, const ['currentPass', 'CurrentPass']) == null
          ? null
          : _parseInt(
              _firstNonNull(json, const ['currentPass', 'CurrentPass']),
            ),
      totalPasses:
          _firstNonNull(json, const ['totalPasses', 'TotalPasses']) == null
          ? null
          : _parseInt(
              _firstNonNull(json, const ['totalPasses', 'TotalPasses']),
            ),
      errorMessage: _readNullableStringByKeys(json, const [
        'errorMessage',
        'ErrorMessage',
      ]),
      styleSource: _readNullableStringByKeys(json, const [
        'styleSource',
        'StyleSource',
      ]),
      detectedContentType: _readNullableStringByKeys(json, const [
        'detectedContentType',
        'DetectedContentType',
      ]),
      contentDetectionConfidence: _parseDoubleNullable(
        _firstNonNull(json, const [
          'contentDetectionConfidence',
          'ContentDetectionConfidence',
        ]),
      ),
      speakerModeApplied: _readNullableStringByKeys(json, const [
        'speakerModeApplied',
        'SpeakerModeApplied',
      ]),
      karaokeModeApplied: _readNullableStringByKeys(json, const [
        'karaokeModeApplied',
        'KaraokeModeApplied',
      ]),
      renderPreviewPath: _readNullableStringByKeys(json, const [
        'renderPreviewPath',
        'RenderPreviewPath',
      ]),
      sceneMapPath: _readNullableStringByKeys(json, const [
        'sceneMapPath',
        'SceneMapPath',
      ]),
      speakerMapPath: _readNullableStringByKeys(json, const [
        'speakerMapPath',
        'SpeakerMapPath',
      ]),
      lyricAlignmentPath: _readNullableStringByKeys(json, const [
        'lyricAlignmentPath',
        'LyricAlignmentPath',
      ]),
      voiceAnalysisSource: _readNullableStringByKeys(json, const [
        'voiceAnalysisSource',
        'VoiceAnalysisSource',
      ]),
      sceneAnalysisSource: _readNullableStringByKeys(json, const [
        'sceneAnalysisSource',
        'SceneAnalysisSource',
      ]),
      previewModeApplied: _readNullableStringByKeys(json, const [
        'previewModeApplied',
        'PreviewModeApplied',
      ]),
      plannerModelUsed: _readNullableStringByKeys(json, const [
        'plannerModelUsed',
        'PlannerModelUsed',
      ]),
      reviewModelUsed: _readNullableStringByKeys(json, const [
        'reviewModelUsed',
        'ReviewModelUsed',
      ]),
      timeoutProfileApplied: _readNullableStringByKeys(json, const [
        'timeoutProfileApplied',
        'TimeoutProfileApplied',
      ]),
      requestedAiProvider: _readNullableStringByKeys(json, const [
        'requestedAiProvider',
        'RequestedAiProvider',
      ]),
      requestedAiModel: _readNullableStringByKeys(json, const [
        'requestedAiModel',
        'RequestedAiModel',
      ]),
      effectiveAiProvider: _readNullableStringByKeys(json, const [
        'effectiveAiProvider',
        'EffectiveAiProvider',
      ]),
      effectiveAiModel: _readNullableStringByKeys(json, const [
        'effectiveAiModel',
        'EffectiveAiModel',
      ]),
      runtimeTarget: _readNullableStringByKeys(json, const [
        'runtimeTarget',
        'RuntimeTarget',
      ]),
      modelInstalledAtSubmission:
          _firstNonNull(json, const [
                'modelInstalledAtSubmission',
                'ModelInstalledAtSubmission',
              ]) ==
              null
          ? null
          : _parseBool(
              _firstNonNull(json, const [
                'modelInstalledAtSubmission',
                'ModelInstalledAtSubmission',
              ]),
            ),
      jobTimeoutMinutes:
          _firstNonNull(json, const [
                'jobTimeoutMinutes',
                'JobTimeoutMinutes',
              ]) ==
              null
          ? null
          : _parseInt(
              _firstNonNull(json, const [
                'jobTimeoutMinutes',
                'JobTimeoutMinutes',
              ]),
            ),
      structuredTimeoutSeconds:
          _firstNonNull(json, const [
                'structuredTimeoutSeconds',
                'StructuredTimeoutSeconds',
              ]) ==
              null
          ? null
          : _parseInt(
              _firstNonNull(json, const [
                'structuredTimeoutSeconds',
                'StructuredTimeoutSeconds',
              ]),
            ),
      styleTimeoutSeconds:
          _firstNonNull(json, const [
                'styleTimeoutSeconds',
                'StyleTimeoutSeconds',
              ]) ==
              null
          ? null
          : _parseInt(
              _firstNonNull(json, const [
                'styleTimeoutSeconds',
                'StyleTimeoutSeconds',
              ]),
            ),
      sourceDurationSeconds: _parseDoubleNullable(
        _firstNonNull(json, const [
          'sourceDurationSeconds',
          'SourceDurationSeconds',
        ]),
      ),
      outputDurationSeconds: _parseDoubleNullable(
        _firstNonNull(json, const [
          'outputDurationSeconds',
          'OutputDurationSeconds',
        ]),
      ),
      musicalSegmentDurations:
          ((_firstNonNull(json, const [
                        'musicalSegmentDurations',
                        'MusicalSegmentDurations',
                      ])
                      as List?) ??
                  const <dynamic>[])
              .map((item) => _parseJsonMap(item) ?? const <String, dynamic>{})
              .toList(),
      fallbacks:
          ((_firstNonNull(json, const ['fallbacks', 'Fallbacks']) as List?) ??
                  const <dynamic>[])
              .map((item) => _parseJsonMap(item) ?? const <String, dynamic>{})
              .toList(),
      qualitySummary: _parseJsonMap(
        _firstNonNull(json, const ['qualitySummary', 'QualitySummary']),
      ),
      translationStatuses: _parseJsonMap(
        _firstNonNull(json, const [
          'translationStatuses',
          'TranslationStatuses',
        ]),
      ),
      capabilityProfile: _parseJsonMap(
        _firstNonNull(json, const ['capabilityProfile', 'CapabilityProfile']),
      ),
      diagnostics: diagnostics,
      languageDetected: _readNullableStringByKeys(json, const [
        'languageDetected',
        'LanguageDetected',
      ]),
      durationSeconds: _parseDoubleNullable(
        _firstNonNull(json, const ['durationSeconds', 'DurationSeconds']),
      ),
      createdAtUtc:
          _parseDate(
            _firstNonNull(json, const ['createdAtUtc', 'CreatedAtUtc']),
          ) ??
          DateTime.now(),
      startedAtUtc: _parseDate(
        _firstNonNull(json, const ['startedAtUtc', 'StartedAtUtc']),
      ),
      finishedAtUtc: _parseDate(
        _firstNonNull(json, const ['finishedAtUtc', 'FinishedAtUtc']),
      ),
      outputs: outputs,
    );
  }
}

class TranscriptionPreviewPolicy {
  static bool prefersRenderedPreviewForDetail(TranscriptionJobDetail? detail) {
    if (detail == null) return false;
    return detail.renderedPreviewMode == 'rendered' ||
        detail.contentMode == 'anime_song' ||
        (detail.karaokeModeApplied ?? 'off') != 'off' ||
        detail.speakerModeApplied == 'advanced' ||
        (detail.renderPreviewPath?.trim().isNotEmpty ?? false);
  }
}

class AiModelDownloadStatus {
  final String id;
  final String provider;
  final String model;
  final String status;
  final int progress;
  final String? detail;
  final String? error;

  const AiModelDownloadStatus({
    required this.id,
    required this.provider,
    required this.model,
    required this.status,
    required this.progress,
    required this.detail,
    required this.error,
  });

  bool get isTerminal => status == 'completed' || status == 'error';
  bool get isCompleted => status == 'completed';

  factory AiModelDownloadStatus.fromJson(Map<String, dynamic> json) {
    return AiModelDownloadStatus(
      id: _readStringByKeys(json, const ['id', 'Id']),
      provider: _readStringByKeys(json, const ['provider', 'Provider']),
      model: _readStringByKeys(json, const ['model', 'Model']),
      status: _readStringByKeys(json, const ['status', 'Status']),
      progress: _parseInt(_firstNonNull(json, const ['progress', 'Progress'])),
      detail: _readNullableStringByKeys(json, const ['detail', 'Detail']),
      error: _readNullableStringByKeys(json, const ['error', 'Error']),
    );
  }
}

class TranscriptionJobDiagnostic {
  final String stage;
  final String severity;
  final String message;
  final String? model;
  final String? language;
  final String? fallbackUsed;
  final String? rawExcerpt;
  final String? sourceField;
  final int? durationMs;

  const TranscriptionJobDiagnostic({
    required this.stage,
    required this.severity,
    required this.message,
    required this.model,
    required this.language,
    required this.fallbackUsed,
    required this.rawExcerpt,
    required this.sourceField,
    required this.durationMs,
  });

  factory TranscriptionJobDiagnostic.fromJson(Map<String, dynamic> json) {
    return TranscriptionJobDiagnostic(
      stage: _readStringByKeys(json, const ['stage', 'Stage']),
      severity: _readStringByKeys(json, const ['severity', 'Severity']),
      message: _readStringByKeys(json, const ['message', 'Message']),
      model: _readNullableStringByKeys(json, const ['model', 'Model']),
      language: _readNullableStringByKeys(json, const ['language', 'Language']),
      fallbackUsed: _readNullableStringByKeys(json, const [
        'fallbackUsed',
        'FallbackUsed',
      ]),
      rawExcerpt: _readNullableStringByKeys(json, const [
        'rawExcerpt',
        'RawExcerpt',
      ]),
      sourceField: _readNullableStringByKeys(json, const [
        'sourceField',
        'SourceField',
      ]),
      durationMs:
          _firstNonNull(json, const ['durationMs', 'DurationMs']) == null
          ? null
          : _parseInt(_firstNonNull(json, const ['durationMs', 'DurationMs'])),
    );
  }
}
