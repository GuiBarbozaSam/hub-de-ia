import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../../../core/di/providers.dart';
import '../../../core/http/auth_service.dart';
import 'transcription_models.dart';

final transcriptionApiServiceProvider = Provider<TranscriptionApiService>((
  ref,
) {
  final auth = ref.read(authServiceProvider);
  return TranscriptionApiService(
    client: ref.read(httpClientProvider),
    secureStorage: ref.read(secureStorageProvider),
    authService: auth,
    baseUrl: auth.baseUrl,
  );
});

class TranscriptionApiService {
  TranscriptionApiService({
    http.Client? client,
    FlutterSecureStorage? secureStorage,
    required AuthService authService,
    String? baseUrl,
  }) : _client = client ?? http.Client(),
       _secureStorage = secureStorage ?? const FlutterSecureStorage(),
       _authService = authService,
       baseUrl = (baseUrl ?? _defaultBaseUrl).replaceAll(RegExp(r'/+$'), '');

  static const String _defaultBaseUrl = 'http://localhost:5045';
  static const String _uiPreferenceKey = 'transcription_ui_preferences_v4';

  static const Duration _defaultRequestTimeout = Duration(seconds: 45);
  static const Duration _defaultUploadTimeout = Duration(minutes: 20);
  static const Duration _defaultDownloadTimeout = Duration(minutes: 10);

  final http.Client _client;
  final FlutterSecureStorage _secureStorage;
  final AuthService _authService;
  final String baseUrl;

  Uri resolveUri(String url) => _resolveUri(url);

  Uri _resolveUri(String url) {
    final normalized = url.trim();

    if (normalized.startsWith('http://') || normalized.startsWith('https://')) {
      return Uri.parse(normalized);
    }

    if (normalized.startsWith('/')) {
      return Uri.parse('$baseUrl$normalized');
    }

    return Uri.parse('$baseUrl/$normalized');
  }

  Future<Map<String, String>> authorizedHeaders({
    bool includeJson = true,
    String accept = '*/*',
  }) async {
    final token = await _authService.readValidAccessToken();
    if (token == null || token.isEmpty) {
      throw ApiException(
        'AuthorizedHeaders',
        401,
        'Nenhum token salvo na sessão atual.',
      );
    }

    return <String, String>{
      if (includeJson) 'Content-Type': 'application/json',
      'Accept': accept,
      'Authorization': 'Bearer $token',
    };
  }

  Future<Map<String, dynamic>> _readUiPreferenceOverlay() async {
    final raw = await _secureStorage.read(key: _uiPreferenceKey);
    if (raw == null || raw.trim().isEmpty) {
      return <String, dynamic>{};
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return decoded.map((key, value) => MapEntry(key.toString(), value));
      }
    } catch (_) {}

    return <String, dynamic>{};
  }

  Future<void> _saveUiPreferenceOverlay(
    TranscriptionPreference preference,
  ) async {
    await _secureStorage.write(
      key: _uiPreferenceKey,
      value: jsonEncode(preference.toUiOverlayJson()),
    );
  }

  Future<void> _clearUiPreferenceOverlay() async {
    await _secureStorage.delete(key: _uiPreferenceKey);
  }

  Future<TranscriptionPreference> _mergePreferenceOverlay(
    TranscriptionPreference preference,
  ) async {
    final overlay = await _readUiPreferenceOverlay();
    return preference.applyUiOverlay(overlay).normalizedForUi();
  }

  Map<String, dynamic> _toStringKeyMap(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return value.map((key, item) => MapEntry(key.toString(), item));
    }
    throw Exception('Resposta inválida do servidor.');
  }

  List<dynamic> _toDynamicList(dynamic value) {
    if (value is List) {
      return value;
    }
    throw Exception('Resposta de lista inválida do servidor.');
  }

  dynamic _decodeResponseBody(http.Response response) {
    final body = utf8.decode(response.bodyBytes, allowMalformed: true).trim();
    if (body.isEmpty) {
      return <String, dynamic>{};
    }
    return jsonDecode(body);
  }

  Exception _buildHttpError(http.Response response) {
    try {
      final decoded = _decodeResponseBody(response);
      if (decoded is Map) {
        final map = _toStringKeyMap(decoded);

        String? readText(String key) {
          final value = map[key]?.toString().trim();
          if (value == null || value.isEmpty) return null;
          return value;
        }

        final message =
            readText('message') ??
            readText('Message') ??
            readText('title') ??
            readText('Title') ??
            readText('detail') ??
            readText('Detail') ??
            readText('error') ??
            readText('Error') ??
            readText('reason') ??
            readText('Reason');

        final errors = map['errors'];
        if (errors is Map && errors.isNotEmpty) {
          final details = <String>[];
          for (final entry in errors.entries) {
            final key = entry.key.toString();
            final value = entry.value;
            if (value is List) {
              final joined = value
                  .map((e) => e.toString())
                  .where((e) => e.trim().isNotEmpty)
                  .join(' | ');
              if (joined.isNotEmpty) {
                details.add('$key: $joined');
              }
            } else if (value != null && value.toString().trim().isNotEmpty) {
              details.add('$key: ${value.toString().trim()}');
            }
          }

          if (details.isNotEmpty) {
            final prefix = message == null ? '' : '$message | ';
            return Exception(
              'Erro HTTP ${response.statusCode}: $prefix${details.join(' || ')}',
            );
          }
        }

        if (message != null) {
          return Exception('Erro HTTP ${response.statusCode}: $message');
        }
      }
    } catch (_) {}

    final body = utf8.decode(response.bodyBytes, allowMalformed: true).trim();
    if (body.isNotEmpty) {
      return Exception('Erro HTTP ${response.statusCode}: $body');
    }

    return Exception('Erro HTTP ${response.statusCode}.');
  }

  Future<http.Response> _sendAuthorized(
    String operation,
    Future<http.Response> Function(Map<String, String> headers) sender, {
    bool includeJson = true,
    String accept = '*/*',
  }) async {
    Future<http.Response> runRequest() async {
      return sender(
        await authorizedHeaders(includeJson: includeJson, accept: accept),
      );
    }

    var response = await runRequest();
    if (response.statusCode == 401 && await _authService.tryRefreshSession()) {
      response = await runRequest();
    }

    if (response.statusCode == 401) {
      await _authService.clearSession();
      throw ApiException(
        operation,
        response.statusCode,
        utf8.decode(response.bodyBytes, allowMalformed: true),
      );
    }

    return response;
  }

  Future<http.Response> _get(Uri uri, {required Map<String, String> headers}) {
    return _client.get(uri, headers: headers).timeout(_defaultRequestTimeout);
  }

  Future<http.Response> _post(
    Uri uri, {
    required Map<String, String> headers,
    Object? body,
  }) {
    return _client
        .post(uri, headers: headers, body: body)
        .timeout(_defaultRequestTimeout);
  }

  Future<http.Response> _put(
    Uri uri, {
    required Map<String, String> headers,
    Object? body,
  }) {
    return _client
        .put(uri, headers: headers, body: body)
        .timeout(_defaultRequestTimeout);
  }

  Map<String, dynamic> _withCompatAliases(Map<String, dynamic> body) {
    final normalized = <String, dynamic>{...body};

    void alias(String camelCaseKey, String pascalCaseKey) {
      if (normalized.containsKey(camelCaseKey) &&
          !normalized.containsKey(pascalCaseKey)) {
        normalized[pascalCaseKey] = normalized[camelCaseKey];
      }
    }

    alias('sourceType', 'SourceType');
    alias('sourceValue', 'SourceValue');
    alias('model', 'Model');
    alias('task', 'Task');
    alias('language', 'Language');
    alias('outputFormat', 'OutputFormat');
    alias('requestedOutputs', 'RequestedOutputs');
    alias('requestedOutputsCsv', 'RequestedOutputsCsv');
    alias('deliveryMode', 'DeliveryMode');
    alias('generateSubtitles', 'GenerateSubtitles');
    alias('burnSubtitlesIntoVideo', 'BurnSubtitlesIntoVideo');
    alias('keepTimestamps', 'KeepTimestamps');
    alias('splitBySentence', 'SplitBySentence');
    alias('wordTimestamps', 'WordTimestamps');
    alias('vadFilter', 'VadFilter');
    alias('devicePreference', 'DevicePreference');
    alias('computeType', 'ComputeType');
    alias('beamSize', 'BeamSize');
    alias('maxSubtitleChars', 'MaxSubtitleChars');
    alias('subtitleStyle', 'SubtitleStyle');
    alias('subtitleVisualPreset', 'SubtitleVisualPreset');
    alias('targetLanguages', 'TargetLanguages');
    alias('targetLanguagesCsv', 'TargetLanguagesCsv');
    alias('videoDeliveryMode', 'VideoDeliveryMode');
    alias('aiEnhancementEnabled', 'AiEnhancementEnabled');
    alias('aiProvider', 'AiProvider');
    alias('aiModel', 'AiModel');
    alias('aiMode', 'AiMode');
    alias('aiPrompt', 'AiPrompt');
    alias('aiTemperature', 'AiTemperature');
    alias('aiTopP', 'AiTopP');
    alias('aiMaxTokens', 'AiMaxTokens');
    alias('aiChunkChars', 'AiChunkChars');
    alias('aiUseVisualContext', 'AiUseVisualContext');
    alias('aiFrameSampleSeconds', 'AiFrameSampleSeconds');
    alias('preserveTimestamps', 'PreserveTimestamps');
    alias('aiRevisionPasses', 'AiRevisionPasses');
    alias('useAdvancedAlignment', 'UseAdvancedAlignment');
    alias('enableOnlineContext', 'EnableOnlineContext');
    alias('contextHints', 'ContextHints');
    alias('qualityProfile', 'QualityProfile');
    alias('contentMode', 'ContentMode');
    alias('speakerStyleMode', 'SpeakerStyleMode');
    alias('styleIntensity', 'StyleIntensity');
    alias('renderedPreviewMode', 'RenderedPreviewMode');
    alias('animeSongLayoutMode', 'AnimeSongLayoutMode');
    alias('karaokeGranularity', 'KaraokeGranularity');

    final requestedOutputs = normalized['requestedOutputs'];
    if (requestedOutputs is List) {
      final csv = requestedOutputs
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .join(',');
      if (csv.isNotEmpty) {
        normalized['requestedOutputsCsv'] ??= csv;
        normalized['RequestedOutputsCsv'] ??= csv;
      }
    }

    final targetLanguages = normalized['targetLanguages'];
    if (targetLanguages is List) {
      final csv = targetLanguages
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .join(',');
      if (csv.isNotEmpty) {
        normalized['targetLanguagesCsv'] ??= csv;
        normalized['TargetLanguagesCsv'] ??= csv;
      }
    }

    return normalized;
  }

  Future<Map<String, dynamic>> _getJson(String path) async {
    final response = await _sendAuthorized(
      'GetJson',
      (headers) => _get(_resolveUri(path), headers: headers),
      accept: 'application/json',
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _buildHttpError(response);
    }

    return _toStringKeyMap(_decodeResponseBody(response));
  }

  Future<List<dynamic>> _getJsonList(String path) async {
    final response = await _sendAuthorized(
      'GetJsonList',
      (headers) => _get(_resolveUri(path), headers: headers),
      accept: 'application/json',
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _buildHttpError(response);
    }

    return _toDynamicList(_decodeResponseBody(response));
  }

  Future<Map<String, dynamic>> _postJson(
    String path,
    Map<String, dynamic> body,
  ) async {
    final response = await _sendAuthorized(
      'PostJson',
      (headers) => _post(
        _resolveUri(path),
        headers: headers,
        body: jsonEncode(_withCompatAliases(body)),
      ),
      accept: 'application/json',
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _buildHttpError(response);
    }

    return _toStringKeyMap(_decodeResponseBody(response));
  }

  Future<Map<String, dynamic>> _putJson(
    String path,
    Map<String, dynamic> body,
  ) async {
    final response = await _sendAuthorized(
      'PutJson',
      (headers) => _put(
        _resolveUri(path),
        headers: headers,
        body: jsonEncode(_withCompatAliases(body)),
      ),
      accept: 'application/json',
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _buildHttpError(response);
    }

    return _toStringKeyMap(_decodeResponseBody(response));
  }

  Future<Map<String, dynamic>> _postEmpty(String path) async {
    final response = await _sendAuthorized(
      'PostEmpty',
      (headers) => _post(_resolveUri(path), headers: headers),
      accept: 'application/json',
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _buildHttpError(response);
    }

    return _toStringKeyMap(_decodeResponseBody(response));
  }

  Future<TranscriptionOptions> getOptions() async {
    final json = await _getJson('/api/transcription/options');
    return TranscriptionOptions.fromJson(json);
  }

  Future<TranscriptionCapabilities> getCapabilities() async {
    final json = await _getJson('/api/transcription/capabilities');
    return TranscriptionCapabilities.fromJson(json);
  }

  Future<AiModelDownloadStatus> startModelDownload({
    required String provider,
    required String model,
  }) async {
    final json = await _postJson(
      '/api/transcription/models/download',
      <String, dynamic>{'provider': provider, 'model': model},
    );
    return AiModelDownloadStatus.fromJson(json);
  }

  Future<AiModelDownloadStatus> getModelDownloadStatus(
    String downloadId,
  ) async {
    final json = await _getJson(
      '/api/transcription/models/downloads/$downloadId',
    );
    return AiModelDownloadStatus.fromJson(json);
  }

  Future<TranscriptionPreference> getPreferences() async {
    final json = await _getJson('/api/transcription/preferences');
    final preference = TranscriptionPreference.fromJson(json);
    return _mergePreferenceOverlay(preference);
  }

  Future<TranscriptionPreference> savePreferences(
    TranscriptionPreference preference,
  ) async {
    final normalized = preference.normalizedForUi();
    final json = await _putJson(
      '/api/transcription/preferences',
      normalized.toBackendJson(),
    );
    await _saveUiPreferenceOverlay(normalized);
    return _mergePreferenceOverlay(TranscriptionPreference.fromJson(json));
  }

  Future<TranscriptionPreference> resetPreferences() async {
    final json = await _postEmpty('/api/transcription/preferences/reset');
    await _clearUiPreferenceOverlay();
    return _mergePreferenceOverlay(TranscriptionPreference.fromJson(json));
  }

  Future<List<TranscriptionJobListItem>> listJobs() async {
    final list = await _getJsonList('/api/transcription/jobs');
    return list
        .whereType<Map>()
        .map(
          (item) => item.map((key, value) => MapEntry(key.toString(), value)),
        )
        .map(TranscriptionJobListItem.fromJson)
        .toList();
  }

  Future<TranscriptionJobDetail> getJob(String id) async {
    final json = await _getJson('/api/transcription/jobs/$id');
    return TranscriptionJobDetail.fromJson(json);
  }

  Future<TranscriptionJobDetail> createJob(CreateJobInput input) async {
    final json = await _postJson('/api/transcription/jobs', input.toJson());
    return TranscriptionJobDetail.fromJson(json);
  }

  Future<TranscriptionJobDetail> uploadJob(CreateUploadJobInput input) async {
    final file = File(input.filePath);
    if (!await file.exists()) {
      throw Exception(
        'Arquivo selecionado não foi encontrado: ${input.filePath}',
      );
    }

    final requestedOutputs = List<String>.from(
      input.requestedOutputs,
    ).map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    final targetLanguages = List<String>.from(
      input.targetLanguages,
    ).map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

    Future<http.Response> sendUpload(Map<String, String> headers) async {
      final request = http.MultipartRequest(
        'POST',
        _resolveUri('/api/transcription/jobs/upload'),
      );

      request.headers.addAll(headers);

      void addField(
        String key,
        Object? value, {
        List<String> aliases = const [],
      }) {
        if (value == null) return;
        final text = value.toString().trim();
        if (text.isEmpty) return;

        request.fields[key] = text;
        for (final alias in aliases) {
          request.fields[alias] = text;
        }
      }

      void addJsonListField(
        String key,
        List<String> values, {
        List<String> aliases = const [],
      }) {
        final sanitized = values
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();
        if (sanitized.isEmpty) return;

        final jsonValue = jsonEncode(sanitized);
        request.fields[key] = jsonValue;
        for (final alias in aliases) {
          request.fields[alias] = jsonValue;
        }
      }

      void addCsvField(
        String key,
        List<String> values, {
        List<String> aliases = const [],
      }) {
        final sanitized = values
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();
        if (sanitized.isEmpty) return;

        final csvValue = sanitized.join(',');
        request.fields[key] = csvValue;
        for (final alias in aliases) {
          request.fields[alias] = csvValue;
        }
      }

      void addIndexedFields(
        String key,
        List<String> values, {
        List<String> aliases = const [],
      }) {
        final sanitized = values
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();
        for (var i = 0; i < sanitized.length; i++) {
          request.fields['$key[$i]'] = sanitized[i];
          for (final alias in aliases) {
            request.fields['$alias[$i]'] = sanitized[i];
          }
        }
      }

      addField('model', input.model, aliases: const ['Model']);
      addField('task', input.task, aliases: const ['Task']);
      addField('language', input.language, aliases: const ['Language']);
      addField(
        'outputFormat',
        input.outputFormat,
        aliases: const ['OutputFormat'],
      );
      addCsvField(
        'requestedOutputsCsv',
        requestedOutputs,
        aliases: const ['RequestedOutputsCsv'],
      );
      addJsonListField(
        'requestedOutputs',
        requestedOutputs,
        aliases: const ['RequestedOutputs'],
      );
      addIndexedFields(
        'requestedOutputs',
        requestedOutputs,
        aliases: const ['RequestedOutputs'],
      );
      addField(
        'deliveryMode',
        input.deliveryMode,
        aliases: const ['DeliveryMode'],
      );
      addField(
        'generateSubtitles',
        input.generateSubtitles.toString(),
        aliases: const ['GenerateSubtitles'],
      );
      addField(
        'burnSubtitlesIntoVideo',
        input.burnSubtitlesIntoVideo.toString(),
        aliases: const ['BurnSubtitlesIntoVideo'],
      );
      addField(
        'keepTimestamps',
        input.keepTimestamps.toString(),
        aliases: const ['KeepTimestamps'],
      );
      addField(
        'splitBySentence',
        input.splitBySentence.toString(),
        aliases: const ['SplitBySentence'],
      );
      addField(
        'wordTimestamps',
        input.wordTimestamps.toString(),
        aliases: const ['WordTimestamps'],
      );
      addField(
        'vadFilter',
        input.vadFilter.toString(),
        aliases: const ['VadFilter'],
      );
      addField(
        'devicePreference',
        input.devicePreference,
        aliases: const ['DevicePreference'],
      );
      addField(
        'computeType',
        input.computeType,
        aliases: const ['ComputeType'],
      );
      addField('beamSize', input.beamSize, aliases: const ['BeamSize']);
      addField(
        'maxSubtitleChars',
        input.maxSubtitleChars,
        aliases: const ['MaxSubtitleChars'],
      );
      addField(
        'subtitleStyle',
        input.subtitleStyle,
        aliases: const ['SubtitleStyle'],
      );
      addField(
        'subtitleVisualPreset',
        input.subtitleVisualPreset,
        aliases: const ['SubtitleVisualPreset'],
      );
      addCsvField(
        'targetLanguagesCsv',
        targetLanguages,
        aliases: const ['TargetLanguagesCsv'],
      );
      addJsonListField(
        'targetLanguages',
        targetLanguages,
        aliases: const ['TargetLanguages'],
      );
      addIndexedFields(
        'targetLanguages',
        targetLanguages,
        aliases: const ['TargetLanguages'],
      );
      addField(
        'videoDeliveryMode',
        input.videoDeliveryMode,
        aliases: const ['VideoDeliveryMode'],
      );
      addField(
        'aiEnhancementEnabled',
        input.aiEnhancementEnabled.toString(),
        aliases: const ['AiEnhancementEnabled'],
      );
      addField('aiProvider', input.aiProvider, aliases: const ['AiProvider']);
      addField('aiModel', input.aiModel, aliases: const ['AiModel']);
      addField('aiMode', input.aiMode, aliases: const ['AiMode']);
      addField('aiPrompt', input.aiPrompt, aliases: const ['AiPrompt']);
      addField(
        'aiTemperature',
        input.aiTemperature,
        aliases: const ['AiTemperature'],
      );
      addField('aiTopP', input.aiTopP, aliases: const ['AiTopP']);
      addField(
        'aiMaxTokens',
        input.aiMaxTokens,
        aliases: const ['AiMaxTokens'],
      );
      addField(
        'aiChunkChars',
        input.aiChunkChars,
        aliases: const ['AiChunkChars'],
      );
      addField(
        'aiUseVisualContext',
        input.aiUseVisualContext.toString(),
        aliases: const ['AiUseVisualContext'],
      );
      addField(
        'aiFrameSampleSeconds',
        input.aiFrameSampleSeconds,
        aliases: const ['AiFrameSampleSeconds'],
      );
      addField(
        'aiRevisionPasses',
        input.aiRevisionPasses,
        aliases: const ['AiRevisionPasses'],
      );
      addField(
        'useAdvancedAlignment',
        input.useAdvancedAlignment,
        aliases: const ['UseAdvancedAlignment'],
      );
      addField(
        'enableOnlineContext',
        input.enableOnlineContext.toString(),
        aliases: const ['EnableOnlineContext'],
      );
      final contextHints = input.contextHints?.toJsonOrNull();
      if (contextHints != null) {
        addField(
          'contextHints',
          jsonEncode(contextHints),
          aliases: const ['ContextHints'],
        );
      }
      addField(
        'qualityProfile',
        input.qualityProfile,
        aliases: const ['QualityProfile'],
      );
      addField(
        'contentMode',
        input.contentMode,
        aliases: const ['ContentMode'],
      );
      addField(
        'speakerStyleMode',
        input.speakerStyleMode,
        aliases: const ['SpeakerStyleMode'],
      );
      addField(
        'styleIntensity',
        input.styleIntensity,
        aliases: const ['StyleIntensity'],
      );
      addField(
        'renderedPreviewMode',
        input.renderedPreviewMode,
        aliases: const ['RenderedPreviewMode'],
      );
      addField(
        'animeSongLayoutMode',
        input.animeSongLayoutMode,
        aliases: const ['AnimeSongLayoutMode'],
      );
      addField(
        'karaokeGranularity',
        input.karaokeGranularity,
        aliases: const ['KaraokeGranularity'],
      );
      addField(
        'preserveTimestamps',
        input.preserveTimestamps.toString(),
        aliases: const ['PreserveTimestamps'],
      );

      request.files.add(
        await http.MultipartFile.fromPath('file', input.filePath),
      );

      final streamed = await request.send().timeout(_defaultUploadTimeout);
      return http.Response.fromStream(streamed);
    }

    final response = await _sendAuthorized(
      'UploadJob',
      sendUpload,
      includeJson: false,
      accept: 'application/json',
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _buildHttpError(response);
    }

    return TranscriptionJobDetail.fromJson(
      _toStringKeyMap(_decodeResponseBody(response)),
    );
  }

  Future<String> fetchTextPreview(TranscriptionOutput output) async {
    final previewUrl = output.previewUrl ?? output.downloadUrl;
    if (previewUrl == null || previewUrl.trim().isEmpty) {
      throw Exception('Este output não possui URL de preview textual.');
    }

    final response = await _sendAuthorized(
      'FetchTextPreview',
      (headers) => _get(_resolveUri(previewUrl), headers: headers),
      includeJson: false,
      accept: 'text/plain, text/vtt, application/octet-stream, */*',
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _buildHttpError(response);
    }

    return utf8.decode(response.bodyBytes, allowMalformed: true);
  }

  Future<List<int>> fetchOutputBytes(TranscriptionOutput output) async {
    final downloadUrl = output.downloadUrl ?? output.previewUrl;
    if (downloadUrl == null || downloadUrl.trim().isEmpty) {
      throw Exception('Este output não possui URL de download disponível.');
    }

    final response = await _sendAuthorized(
      'FetchOutputBytes',
      (headers) => _client
          .get(_resolveUri(downloadUrl), headers: headers)
          .timeout(_defaultDownloadTimeout),
      includeJson: false,
      accept: '*/*',
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _buildHttpError(response);
    }

    return response.bodyBytes;
  }

  Future<String?> downloadOutput(TranscriptionOutput output) async {
    final bytes = await fetchOutputBytes(output);
    final suggestedName = _buildSuggestedFileName(output);

    final location = await getSaveLocation(suggestedName: suggestedName);
    if (location == null) {
      return null;
    }

    final file = File(location.path);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  String _basename(String value) {
    final normalized = value.trim().replaceAll('\\', '/');
    if (normalized.isEmpty) return '';
    final parts = normalized.split('/');
    return parts.isEmpty ? normalized : parts.last;
  }

  String _buildSuggestedFileName(TranscriptionOutput output) {
    final fileName = output.fileName?.trim();
    if (fileName != null && fileName.isNotEmpty) {
      final base = _basename(fileName);
      if (base.isNotEmpty) return base;
    }

    final normalizedType = output.outputType.toLowerCase();
    final extension = switch (normalizedType) {
      'text' => '.txt',
      'srt' => '.srt',
      'vtt' => '.vtt',
      'ass' => '.ass',
      'video_burned' => '.mp4',
      'video_muxed' => '.mkv',
      final value when value.contains('srt') => '.srt',
      final value when value.contains('vtt') => '.vtt',
      final value when value.contains('ass') => '.ass',
      final value when value.contains('txt') => '.txt',
      final value when value.contains('video') => '.mp4',
      _ => '.bin',
    };

    return '${output.outputType}$extension';
  }
}
