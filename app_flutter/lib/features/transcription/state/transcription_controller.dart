import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/http/auth_service.dart';
import '../../auth/state/auth_controller.dart';
import '../data/transcription_api_service.dart';
import '../data/transcription_models.dart';

const Object _controllerStateSentinel = Object();

final transcriptionControllerProvider =
    StateNotifierProvider.autoDispose<
      TranscriptionController,
      TranscriptionControllerState
    >((ref) {
      return TranscriptionController(
        ref: ref,
        api: ref.watch(transcriptionApiServiceProvider),
      );
    });

enum TranscriptionSourceMode { upload, url, filePath }

class TranscriptionControllerState {
  final bool isBootstrapping;
  final bool isLoadingOptions;
  final bool isLoadingPreferences;
  final bool isSavingPreferences;
  final bool isResettingPreferences;
  final bool isRefreshingJobs;
  final bool isRefreshingSelectedJob;
  final bool isSubmitting;
  final bool isDownloading;
  final bool isPolling;
  final AiModelDownloadStatus? activeModelDownload;
  final String? errorMessage;
  final String? successMessage;
  final TranscriptionOptions? options;
  final TranscriptionCapabilities? capabilities;
  final TranscriptionPreference preference;
  final List<TranscriptionJobListItem> jobs;
  final String? selectedJobId;
  final TranscriptionJobDetail? selectedJob;
  final TranscriptionSourceMode sourceMode;
  final DateTime? lastUpdatedAt;

  const TranscriptionControllerState({
    required this.isBootstrapping,
    required this.isLoadingOptions,
    required this.isLoadingPreferences,
    required this.isSavingPreferences,
    required this.isResettingPreferences,
    required this.isRefreshingJobs,
    required this.isRefreshingSelectedJob,
    required this.isSubmitting,
    required this.isDownloading,
    required this.isPolling,
    required this.activeModelDownload,
    required this.errorMessage,
    required this.successMessage,
    required this.options,
    required this.capabilities,
    required this.preference,
    required this.jobs,
    required this.selectedJobId,
    required this.selectedJob,
    required this.sourceMode,
    required this.lastUpdatedAt,
  });

  factory TranscriptionControllerState.initial() {
    return TranscriptionControllerState(
      isBootstrapping: false,
      isLoadingOptions: false,
      isLoadingPreferences: false,
      isSavingPreferences: false,
      isResettingPreferences: false,
      isRefreshingJobs: false,
      isRefreshingSelectedJob: false,
      isSubmitting: false,
      isDownloading: false,
      isPolling: false,
      activeModelDownload: null,
      errorMessage: null,
      successMessage: null,
      options: null,
      capabilities: null,
      preference: TranscriptionPreference.defaults().normalizedForUi(),
      jobs: const [],
      selectedJobId: null,
      selectedJob: null,
      sourceMode: TranscriptionSourceMode.upload,
      lastUpdatedAt: null,
    );
  }

  bool get hasSelection =>
      selectedJobId != null && selectedJobId!.trim().isNotEmpty;
  bool get hasJobs => jobs.isNotEmpty;
  bool get hasActiveJobs => jobs.any((job) => job.isActive);

  List<String> get selectedAiModes =>
      _normalizeAiModesCsv(preference.aiMode, preference.task);

  TranscriptionControllerState copyWith({
    bool? isBootstrapping,
    bool? isLoadingOptions,
    bool? isLoadingPreferences,
    bool? isSavingPreferences,
    bool? isResettingPreferences,
    bool? isRefreshingJobs,
    bool? isRefreshingSelectedJob,
    bool? isSubmitting,
    bool? isDownloading,
    bool? isPolling,
    Object? activeModelDownload = _controllerStateSentinel,
    Object? errorMessage = _controllerStateSentinel,
    Object? successMessage = _controllerStateSentinel,
    Object? options = _controllerStateSentinel,
    Object? capabilities = _controllerStateSentinel,
    TranscriptionPreference? preference,
    List<TranscriptionJobListItem>? jobs,
    Object? selectedJobId = _controllerStateSentinel,
    Object? selectedJob = _controllerStateSentinel,
    TranscriptionSourceMode? sourceMode,
    Object? lastUpdatedAt = _controllerStateSentinel,
  }) {
    return TranscriptionControllerState(
      isBootstrapping: isBootstrapping ?? this.isBootstrapping,
      isLoadingOptions: isLoadingOptions ?? this.isLoadingOptions,
      isLoadingPreferences: isLoadingPreferences ?? this.isLoadingPreferences,
      isSavingPreferences: isSavingPreferences ?? this.isSavingPreferences,
      isResettingPreferences:
          isResettingPreferences ?? this.isResettingPreferences,
      isRefreshingJobs: isRefreshingJobs ?? this.isRefreshingJobs,
      isRefreshingSelectedJob:
          isRefreshingSelectedJob ?? this.isRefreshingSelectedJob,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      isDownloading: isDownloading ?? this.isDownloading,
      isPolling: isPolling ?? this.isPolling,
      activeModelDownload:
          identical(activeModelDownload, _controllerStateSentinel)
          ? this.activeModelDownload
          : activeModelDownload as AiModelDownloadStatus?,
      errorMessage: identical(errorMessage, _controllerStateSentinel)
          ? this.errorMessage
          : errorMessage as String?,
      successMessage: identical(successMessage, _controllerStateSentinel)
          ? this.successMessage
          : successMessage as String?,
      options: identical(options, _controllerStateSentinel)
          ? this.options
          : options as TranscriptionOptions?,
      capabilities: identical(capabilities, _controllerStateSentinel)
          ? this.capabilities
          : capabilities as TranscriptionCapabilities?,
      preference: preference ?? this.preference,
      jobs: jobs ?? this.jobs,
      selectedJobId: identical(selectedJobId, _controllerStateSentinel)
          ? this.selectedJobId
          : selectedJobId as String?,
      selectedJob: identical(selectedJob, _controllerStateSentinel)
          ? this.selectedJob
          : selectedJob as TranscriptionJobDetail?,
      sourceMode: sourceMode ?? this.sourceMode,
      lastUpdatedAt: identical(lastUpdatedAt, _controllerStateSentinel)
          ? this.lastUpdatedAt
          : lastUpdatedAt as DateTime?,
    );
  }
}

class TranscriptionController
    extends StateNotifier<TranscriptionControllerState> {
  TranscriptionController({
    required Ref ref,
    required TranscriptionApiService api,
  }) : _ref = ref,
       _api = api,
       super(TranscriptionControllerState.initial()) {
    unawaited(bootstrap());
  }
  List<String> get selectedAiModes =>
      _normalizeAiModesCsv(state.preference.aiMode, state.preference.task);

  static const Duration _pollingInterval = Duration(seconds: 4);

  final Ref _ref;
  final TranscriptionApiService _api;
  Timer? _pollingTimer;
  bool _isDisposed = false;

  @override
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    _stopPolling(updateState: false);
    super.dispose();
  }

  Future<void> bootstrap({bool force = false}) async {
    if (_isDisposed) return;
    if (state.isBootstrapping && !force) return;

    state = state.copyWith(
      isBootstrapping: true,
      errorMessage: null,
      successMessage: null,
    );

    try {
      final results = await Future.wait<dynamic>([
        _api.getOptions(),
        _api.getCapabilities(),
        _api.getPreferences(),
        _api.listJobs(),
      ]);

      final options = results[0] as TranscriptionOptions;
      final capabilities = results[1] as TranscriptionCapabilities;
      final preference = _sanitizePreferenceForOptions(
        (results[2] as TranscriptionPreference).normalizedForUi(),
        options,
      );
      final jobs = results[3] as List<TranscriptionJobListItem>;

      String? selectedJobId = state.selectedJobId;
      if (selectedJobId == null ||
          !jobs.any((job) => job.id == selectedJobId)) {
        selectedJobId = jobs.isNotEmpty ? jobs.first.id : null;
      }

      TranscriptionJobDetail? selectedJob;
      if (selectedJobId != null) {
        try {
          selectedJob = await _api.getJob(selectedJobId);
        } catch (_) {
          selectedJob = null;
        }
      }

      state = state.copyWith(
        options: options,
        capabilities: capabilities,
        preference: preference,
        jobs: jobs,
        selectedJobId: selectedJobId,
        selectedJob: selectedJob,
        isBootstrapping: false,
        lastUpdatedAt: DateTime.now(),
      );

      _syncPolling();
    } catch (error) {
      await _handleUnauthorizedIfNeeded(error);
      state = state.copyWith(
        isBootstrapping: false,
        errorMessage: _toMessage(error),
      );
      _syncPolling();
    }
  }

  Future<void> refreshOptions() async {
    if (_isDisposed) return;
    state = state.copyWith(isLoadingOptions: true, errorMessage: null);
    try {
      final options = await _api.getOptions();
      final capabilities = await _api.getCapabilities();
      state = state.copyWith(
        options: options,
        capabilities: capabilities,
        preference: _sanitizePreferenceForOptions(state.preference, options),
        isLoadingOptions: false,
        lastUpdatedAt: DateTime.now(),
      );
    } catch (error) {
      await _handleUnauthorizedIfNeeded(error);
      state = state.copyWith(
        isLoadingOptions: false,
        errorMessage: _toMessage(error),
      );
    }
  }

  List<String> installedAiModelsForProvider(String provider) {
    final capabilities = state.capabilities;
    if (capabilities == null) {
      final fallback =
          state.options?.aiModels ?? UiTranscriptionConstants.aiModelOptions;
      return List<String>.from(fallback);
    }

    final providerInfo = capabilities.providerById(provider);
    final allowed = providerInfo?.multimodalModels.toSet() ?? <String>{};
    final models = capabilities
        .installedModelsForProvider(provider)
        .where((model) => allowed.isEmpty || allowed.contains(model))
        .toList();
    return models.isNotEmpty
        ? models
        : (state.options?.aiModels ?? UiTranscriptionConstants.aiModelOptions);
  }

  List<String> downloadableAiModelsForProvider(String provider) {
    final capabilities = state.capabilities;
    if (capabilities == null) return const <String>[];
    final providerInfo = capabilities.providerById(provider);
    final allowed = providerInfo?.multimodalModels.toSet() ?? <String>{};
    return capabilities
        .downloadableModelsForProvider(provider)
        .where((model) => allowed.isEmpty || allowed.contains(model))
        .toList();
  }

  bool isAiModelInstalled(String provider, String model) {
    return installedAiModelsForProvider(provider).contains(model);
  }

  Future<void> downloadAiModel({
    required String provider,
    required String model,
  }) async {
    if (_isDisposed) return;
    state = state.copyWith(
      isDownloading: true,
      errorMessage: null,
      successMessage: null,
    );

    try {
      var status = await _api.startModelDownload(
        provider: provider,
        model: model,
      );
      state = state.copyWith(activeModelDownload: status);

      while (!_isDisposed && !status.isTerminal) {
        await Future<void>.delayed(const Duration(seconds: 2));
        status = await _api.getModelDownloadStatus(status.id);
        state = state.copyWith(activeModelDownload: status);
      }

      await refreshOptions();

      if (_isDisposed) return;
      state = state.copyWith(
        isDownloading: false,
        activeModelDownload: status,
        successMessage: status.isCompleted
            ? 'Modelo instalado e pronto para seleção.'
            : null,
        errorMessage: status.isCompleted
            ? null
            : (status.error ?? status.detail),
      );
    } catch (error) {
      await _handleUnauthorizedIfNeeded(error);
      if (_isDisposed) return;
      state = state.copyWith(
        isDownloading: false,
        errorMessage: _toMessage(error),
      );
    }
  }

  Future<void> refreshPreferences() async {
    if (_isDisposed) return;
    state = state.copyWith(isLoadingPreferences: true, errorMessage: null);
    try {
      final preference = await _api.getPreferences();
      state = state.copyWith(
        preference: _sanitizePreferenceForOptions(
          preference.normalizedForUi(),
          state.options,
        ),
        isLoadingPreferences: false,
        lastUpdatedAt: DateTime.now(),
      );
    } catch (error) {
      await _handleUnauthorizedIfNeeded(error);
      state = state.copyWith(
        isLoadingPreferences: false,
        errorMessage: _toMessage(error),
      );
    }
  }

  Future<void> savePreferences() async {
    if (_isDisposed) return;
    state = state.copyWith(
      isSavingPreferences: true,
      errorMessage: null,
      successMessage: null,
    );

    try {
      final saved = await _api.savePreferences(
        state.preference.normalizedForUi(),
      );
      state = state.copyWith(
        preference: _sanitizePreferenceForOptions(
          saved.normalizedForUi(),
          state.options,
        ),
        isSavingPreferences: false,
        successMessage: 'Preferências de transcrição salvas com sucesso.',
        lastUpdatedAt: DateTime.now(),
      );
    } catch (error) {
      await _handleUnauthorizedIfNeeded(error);
      state = state.copyWith(
        isSavingPreferences: false,
        errorMessage: _toMessage(error),
      );
    }
  }

  Future<void> resetPreferences() async {
    if (_isDisposed) return;
    state = state.copyWith(
      isResettingPreferences: true,
      errorMessage: null,
      successMessage: null,
    );

    try {
      final reset = await _api.resetPreferences();
      state = state.copyWith(
        preference: _sanitizePreferenceForOptions(
          reset.normalizedForUi(),
          state.options,
        ),
        isResettingPreferences: false,
        successMessage: 'Preferências restauradas para o padrão.',
        lastUpdatedAt: DateTime.now(),
      );
    } catch (error) {
      await _handleUnauthorizedIfNeeded(error);
      state = state.copyWith(
        isResettingPreferences: false,
        errorMessage: _toMessage(error),
      );
    }
  }

  void clearMessages() {
    state = state.copyWith(errorMessage: null, successMessage: null);
  }

  void setSourceMode(TranscriptionSourceMode mode) {
    state = state.copyWith(sourceMode: mode);
  }

  void setPreference(TranscriptionPreference preference) {
    final constrained = _applyDerivedPreferenceConstraints(
      preference.normalizedForUi(),
      state.options,
    );
    final normalized = _sanitizePreferenceForOptions(
      constrained,
      state.options,
    );
    state = state.copyWith(
      preference: normalized,
      errorMessage: null,
      successMessage: null,
    );
  }

  void patchPreference({
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
    Object? maxSubtitleChars = transcriptionPreferenceCopySentinel,
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
    Object? aiPrompt = transcriptionPreferenceCopySentinel,
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
    Object? contextHints = transcriptionPreferenceCopySentinel,
    String? qualityProfile,
    String? contentMode,
    String? speakerStyleMode,
    String? styleIntensity,
    String? renderedPreviewMode,
    String? animeSongLayoutMode,
    String? karaokeGranularity,
  }) {
    final updated = state.preference.copyWith(
      sourceTypeDefault: sourceTypeDefault,
      model: model,
      task: task,
      language: language,
      outputFormat: outputFormat,
      generateSubtitles: generateSubtitles,
      burnSubtitlesIntoVideo: burnSubtitlesIntoVideo,
      keepTimestamps: keepTimestamps,
      splitBySentence: splitBySentence,
      wordTimestamps: wordTimestamps,
      vadFilter: vadFilter,
      devicePreference: devicePreference,
      computeType: computeType,
      beamSize: beamSize,
      maxSubtitleChars: maxSubtitleChars,
      subtitleStyle: subtitleStyle,
      subtitleVisualPreset: subtitleVisualPreset,
      selectedTextOutputs: selectedTextOutputs,
      requestVideoBurned: requestVideoBurned,
      targetLanguages: targetLanguages,
      videoDeliveryMode: videoDeliveryMode,
      aiEnhancementEnabled: aiEnhancementEnabled,
      aiProvider: aiProvider,
      aiModel: aiModel,
      aiMode: aiMode,
      aiPrompt: aiPrompt,
      aiTemperature: aiTemperature,
      aiTopP: aiTopP,
      aiMaxTokens: aiMaxTokens,
      aiChunkChars: aiChunkChars,
      aiUseVisualContext: aiUseVisualContext,
      aiFrameSampleSeconds: aiFrameSampleSeconds,
      preserveTimestamps: preserveTimestamps,
      aiRevisionPasses: aiRevisionPasses,
      useAdvancedAlignment: useAdvancedAlignment,
      enableOnlineContext: enableOnlineContext,
      contextHints: identical(contextHints, transcriptionPreferenceCopySentinel)
          ? transcriptionPreferenceCopySentinel
          : contextHints,
      qualityProfile: qualityProfile,
      contentMode: contentMode,
      speakerStyleMode: speakerStyleMode,
      styleIntensity: styleIntensity,
      renderedPreviewMode: renderedPreviewMode,
      animeSongLayoutMode: animeSongLayoutMode,
      karaokeGranularity: karaokeGranularity,
    );

    setPreference(updated);
  }

  void setTask(String task) {
    final normalizedTask = _normalizeTask(task, state.options);
    var modes = selectedAiModes;

    if (normalizedTask == 'translate' &&
        !modes.contains('semantic_translation')) {
      modes = _orderedAiModes([...modes, 'semantic_translation']);
    }

    final updated = state.preference
        .copyWith(task: normalizedTask, aiMode: modes.join(','))
        .normalizedForUi();

    setPreference(updated);
  }

  void setModel(String model) => patchPreference(model: model);
  void setLanguage(String language) => patchPreference(language: language);
  void setDevicePreference(String value) =>
      patchPreference(devicePreference: value);
  void setComputeType(String value) => patchPreference(computeType: value);
  void setBeamSize(int value) =>
      patchPreference(beamSize: _clampInt(value, min: 1, max: 50));
  void setMaxSubtitleChars(int? value) => patchPreference(
    maxSubtitleChars: value == null ? null : _clampInt(value, min: 8, max: 120),
  );
  void setKeepTimestamps(bool value) => patchPreference(keepTimestamps: value);
  void setSplitBySentence(bool value) =>
      patchPreference(splitBySentence: value);
  void setWordTimestamps(bool value) => patchPreference(wordTimestamps: value);
  void setVadFilter(bool value) => patchPreference(vadFilter: value);
  void setSubtitleVisualPreset(String value) =>
      patchPreference(subtitleVisualPreset: value, subtitleStyle: value);
  void setVideoDeliveryMode(String value) =>
      patchPreference(videoDeliveryMode: value);
  void setAiEnhancementEnabled(bool value) =>
      patchPreference(aiEnhancementEnabled: value);

  bool isTextOutputLocked(String output) {
    final normalized = output.trim().toLowerCase();
    return normalized == 'ass' && _containsStyleMode(state.preference);
  }

  void setAiProvider(String value) => patchPreference(aiProvider: value);
  void setAiModel(String value) => patchPreference(aiModel: value);
  void setAiPrompt(String? value) => patchPreference(
    aiPrompt: value?.trim().isEmpty ?? true ? null : value?.trim(),
  );
  void setAiTemperature(double value) =>
      patchPreference(aiTemperature: _clampDouble(value, min: 0.0, max: 2.0));
  void setAiTopP(double value) =>
      patchPreference(aiTopP: _clampDouble(value, min: 0.0, max: 1.0));
  void setAiMaxTokens(int value) =>
      patchPreference(aiMaxTokens: _clampInt(value, min: 64, max: 32768));
  void setAiChunkChars(int value) =>
      patchPreference(aiChunkChars: _clampInt(value, min: 500, max: 40000));
  void setAiUseVisualContext(bool value) =>
      patchPreference(aiUseVisualContext: value);
  void setAiFrameSampleSeconds(int value) =>
      patchPreference(aiFrameSampleSeconds: _clampInt(value, min: 1, max: 300));
  void setPreserveTimestamps(bool value) =>
      patchPreference(preserveTimestamps: value);
  void setAiRevisionPasses(int value) =>
      patchPreference(aiRevisionPasses: _clampInt(value, min: 0, max: 10));
  void setUseAdvancedAlignment(String value) =>
      patchPreference(useAdvancedAlignment: value);
  void setEnableOnlineContext(bool value) =>
      patchPreference(enableOnlineContext: value);
  void setQualityProfile(String value) =>
      patchPreference(qualityProfile: value);
  void setContextHints(TranscriptionContextHints? value) =>
      patchPreference(contextHints: value);
  void setContentMode(String value) => patchPreference(contentMode: value);
  void setSpeakerStyleMode(String value) =>
      patchPreference(speakerStyleMode: value);
  void setStyleIntensity(String value) =>
      patchPreference(styleIntensity: value);
  void setRenderedPreviewMode(String value) =>
      patchPreference(renderedPreviewMode: value);
  void setAnimeSongLayoutMode(String value) =>
      patchPreference(animeSongLayoutMode: value);
  void setKaraokeGranularity(String value) =>
      patchPreference(karaokeGranularity: value);

  void applyRecommendedProfile() {
    final capabilities = state.capabilities;
    if (capabilities == null) return;

    final recommended = capabilities.profiles[capabilities.recommendedProfile];
    if (recommended == null) return;

    patchPreference(
      qualityProfile: recommended.key,
      aiRevisionPasses: recommended.aiRevisionPasses,
      useAdvancedAlignment: recommended.useAdvancedAlignment,
      aiUseVisualContext: recommended.aiUseVisualContext,
      aiChunkChars: recommended.aiChunkChars,
      karaokeGranularity:
          recommended.maxSupportedKaraokeGranularity == 'syllable'
          ? (state.preference.contentMode == 'anime_song' ? 'syllable' : 'off')
          : (state.preference.contentMode == 'anime_song' ? 'word' : 'off'),
    );
  }

  void toggleTextOutput(String output) {
    final normalized = output.trim().toLowerCase();
    final selected = <String>[...state.preference.selectedTextOutputs];

    if (selected.contains(normalized)) {
      if (isTextOutputLocked(normalized)) {
        return;
      }
      selected.remove(normalized);
    } else {
      selected.add(normalized);
    }

    patchPreference(
      selectedTextOutputs: _normalizeTextOutputsForController(selected),
    );
  }

  void setAllTextOutputs(bool enabled) {
    final outputs = enabled
        ? <String>[...UiTranscriptionConstants.textOutputOptions]
        : (isTextOutputLocked('ass') ? <String>['ass'] : const <String>[]);

    patchPreference(selectedTextOutputs: outputs);
  }

  void setRequestVideoBurned(bool enabled) {
    final updated = state.preference.copyWith(
      requestVideoBurned: enabled,
      burnSubtitlesIntoVideo: enabled,
    );

    setPreference(updated.normalizedForUi());
  }

  void toggleTargetLanguage(String languageCode) {
    final normalized = languageCode.trim();
    final selected = [...state.preference.targetLanguages];

    if (selected.contains(normalized)) {
      selected.remove(normalized);
    } else {
      selected.add(normalized);
    }

    patchPreference(
      targetLanguages: _normalizeTargetLanguagesForController(selected),
    );
  }

  void setTargetLanguages(List<String> targetLanguages) {
    patchPreference(
      targetLanguages: _normalizeTargetLanguagesForController(targetLanguages),
    );
  }

  void setAiModes(List<String> modes) {
    final ordered = _orderedAiModes(modes);
    final forced = _forceAiModesForTask(ordered, state.preference.task);
    patchPreference(aiMode: forced.join(','));
  }

  void toggleAiMode(String mode) {
    final normalized = _normalizeSingleAiMode(mode);
    if (normalized == null) return;

    final List<String> selected = [...selectedAiModes];

    if (selected.contains(normalized)) {
      selected.remove(normalized);
    } else {
      selected.add(normalized);
    }

    final ordered = _orderedAiModes(selected);
    final forced = _forceAiModesForTask(ordered, state.preference.task);

    patchPreference(aiMode: forced.join(','));
  }

  Future<void> refreshJobs({bool keepSelection = true}) async {
    if (_isDisposed) return;
    state = state.copyWith(isRefreshingJobs: true, errorMessage: null);
    try {
      final jobs = await _api.listJobs();

      var selectedJobId = keepSelection ? state.selectedJobId : null;
      if (selectedJobId == null ||
          !jobs.any((job) => job.id == selectedJobId)) {
        selectedJobId = jobs.isNotEmpty ? jobs.first.id : null;
      }

      state = state.copyWith(
        jobs: jobs,
        selectedJobId: selectedJobId,
        isRefreshingJobs: false,
        lastUpdatedAt: DateTime.now(),
      );

      if (selectedJobId != null &&
          (state.selectedJob?.id != selectedJobId || !keepSelection)) {
        await refreshSelectedJob(jobId: selectedJobId, silent: true);
      }

      _syncPolling();
    } catch (error) {
      await _handleUnauthorizedIfNeeded(error);
      state = state.copyWith(
        isRefreshingJobs: false,
        errorMessage: _toMessage(error),
      );
      _syncPolling();
    }
  }

  Future<void> selectJob(String? jobId, {bool forceRefresh = true}) async {
    if (_isDisposed) return;
    state = state.copyWith(
      selectedJobId: jobId,
      successMessage: null,
      errorMessage: null,
    );

    if (jobId == null || jobId.trim().isEmpty) {
      state = state.copyWith(selectedJob: null);
      _syncPolling();
      return;
    }

    if (forceRefresh) {
      await refreshSelectedJob(jobId: jobId, silent: false);
    }
  }

  Future<void> refreshSelectedJob({String? jobId, bool silent = false}) async {
    if (_isDisposed) return;
    final effectiveId = jobId ?? state.selectedJobId;
    if (effectiveId == null || effectiveId.trim().isEmpty) return;

    if (!silent) {
      state = state.copyWith(isRefreshingSelectedJob: true, errorMessage: null);
    }

    try {
      final detail = await _api.getJob(effectiveId);
      state = state.copyWith(
        selectedJobId: effectiveId,
        selectedJob: detail,
        isRefreshingSelectedJob: false,
        lastUpdatedAt: DateTime.now(),
      );
      _syncPolling();
    } catch (error) {
      await _handleUnauthorizedIfNeeded(error);
      state = state.copyWith(
        isRefreshingSelectedJob: false,
        errorMessage: _toMessage(error),
      );
      _syncPolling();
    }
  }

  Future<TranscriptionJobDetail?> submitUpload(String filePath) async {
    final sanitizedPath = filePath.trim();
    if (sanitizedPath.isEmpty) {
      state = state.copyWith(errorMessage: 'Selecione um arquivo para enviar.');
      return null;
    }

    state = state.copyWith(
      isSubmitting: true,
      errorMessage: null,
      successMessage: null,
    );
    try {
      final input = _buildUploadInput(sanitizedPath);
      final detail = await _api.uploadJob(input);
      await _afterSubmit(
        detail,
        message: 'Execução criada com upload de arquivo.',
      );
      return detail;
    } catch (error) {
      await _handleUnauthorizedIfNeeded(error);
      state = state.copyWith(
        isSubmitting: false,
        errorMessage: _toMessage(error),
      );
      return null;
    }
  }

  Future<TranscriptionJobDetail?> submitUrl(String url) async {
    final sanitizedUrl = url.trim();
    if (sanitizedUrl.isEmpty) {
      state = state.copyWith(errorMessage: 'Informe a URL de origem.');
      return null;
    }

    state = state.copyWith(
      isSubmitting: true,
      errorMessage: null,
      successMessage: null,
    );
    try {
      final detail = await _api.createJob(
        _buildCreateJobInput(sourceType: 'url', sourceValue: sanitizedUrl),
      );
      await _afterSubmit(detail, message: 'Execução criada a partir de URL.');
      return detail;
    } catch (error) {
      await _handleUnauthorizedIfNeeded(error);
      state = state.copyWith(
        isSubmitting: false,
        errorMessage: _toMessage(error),
      );
      return null;
    }
  }

  Future<TranscriptionJobDetail?> submitServerPath(String serverPath) async {
    final sanitizedPath = serverPath.trim();
    if (sanitizedPath.isEmpty) {
      state = state.copyWith(
        errorMessage: 'Informe o caminho do arquivo no servidor.',
      );
      return null;
    }

    state = state.copyWith(
      isSubmitting: true,
      errorMessage: null,
      successMessage: null,
    );
    try {
      final detail = await _api.createJob(
        _buildCreateJobInput(
          sourceType: 'file_path',
          sourceValue: sanitizedPath,
        ),
      );
      await _afterSubmit(
        detail,
        message: 'Execução criada a partir de caminho no servidor.',
      );
      return detail;
    } catch (error) {
      await _handleUnauthorizedIfNeeded(error);
      state = state.copyWith(
        isSubmitting: false,
        errorMessage: _toMessage(error),
      );
      return null;
    }
  }

  Future<String> fetchTextPreview(TranscriptionOutput output) {
    return _api.fetchTextPreview(output);
  }

  Future<List<int>> fetchOutputBytes(TranscriptionOutput output) {
    return _api.fetchOutputBytes(output);
  }

  Future<String?> downloadOutput(TranscriptionOutput output) async {
    if (_isDisposed) return null;
    state = state.copyWith(
      isDownloading: true,
      errorMessage: null,
      successMessage: null,
    );
    try {
      final path = await _api.downloadOutput(output);
      state = state.copyWith(
        isDownloading: false,
        successMessage: path == null
            ? 'Download cancelado pelo usuário.'
            : 'Arquivo salvo com sucesso em: $path',
      );
      return path;
    } catch (error) {
      await _handleUnauthorizedIfNeeded(error);
      state = state.copyWith(
        isDownloading: false,
        errorMessage: _toMessage(error),
      );
      return null;
    }
  }

  Future<void> _afterSubmit(
    TranscriptionJobDetail detail, {
    required String message,
  }) async {
    final jobs = await _api.listJobs();
    state = state.copyWith(
      isSubmitting: false,
      jobs: jobs,
      selectedJobId: detail.id,
      selectedJob: detail,
      successMessage: message,
      lastUpdatedAt: DateTime.now(),
    );
    _syncPolling();
  }

  CreateJobInput _buildCreateJobInput({
    required String sourceType,
    required String sourceValue,
  }) {
    final normalized = _sanitizePreferenceForSubmit(state.preference);
    return CreateJobInput(
      sourceType: sourceType,
      sourceValue: sourceValue,
      model: normalized.model,
      task: normalized.task,
      language: normalized.language,
      outputFormat: normalized.outputFormat,
      requestedOutputs: _buildRequestedOutputsForSubmit(normalized),
      deliveryMode: _buildDeliveryModeForSubmit(normalized),
      generateSubtitles: _resolveGenerateSubtitles(normalized),
      burnSubtitlesIntoVideo: normalized.requestVideoBurned,
      keepTimestamps: normalized.keepTimestamps,
      splitBySentence: normalized.splitBySentence,
      wordTimestamps: normalized.wordTimestamps,
      vadFilter: normalized.vadFilter,
      devicePreference: normalized.devicePreference,
      computeType: normalized.computeType,
      beamSize: normalized.beamSize,
      maxSubtitleChars: normalized.maxSubtitleChars,
      subtitleStyle: _resolveSubtitleStyleForSubmit(normalized),
      subtitleVisualPreset: normalized.subtitleVisualPreset,
      targetLanguages: normalized.task == 'translate'
          ? _normalizeTargetLanguagesForController(normalized.targetLanguages)
          : const [],
      videoDeliveryMode: _resolveVideoDeliveryModeForSubmit(normalized),
      aiEnhancementEnabled: normalized.aiEnhancementEnabled,
      aiProvider: normalized.aiProvider,
      aiModel: normalized.aiModel,
      aiMode: _forceAiModesForTask(
        _normalizeAiModesCsv(normalized.aiMode, normalized.task),
        normalized.task,
      ).join(','),
      aiPrompt: normalized.aiPrompt,
      aiTemperature: normalized.aiTemperature,
      aiTopP: normalized.aiTopP,
      aiMaxTokens: normalized.aiMaxTokens,
      aiChunkChars: normalized.aiChunkChars,
      aiUseVisualContext: normalized.aiUseVisualContext,
      aiFrameSampleSeconds: normalized.aiFrameSampleSeconds,
      preserveTimestamps: normalized.preserveTimestamps,
      aiRevisionPasses: normalized.aiRevisionPasses,
      useAdvancedAlignment: normalized.useAdvancedAlignment,
      enableOnlineContext: normalized.enableOnlineContext,
      contextHints: normalized.contextHints,
      qualityProfile: normalized.qualityProfile,
      contentMode: normalized.contentMode,
      speakerStyleMode: normalized.speakerStyleMode,
      styleIntensity: normalized.styleIntensity,
      renderedPreviewMode: normalized.renderedPreviewMode,
      animeSongLayoutMode: normalized.animeSongLayoutMode,
      karaokeGranularity: normalized.karaokeGranularity,
    );
  }

  CreateUploadJobInput _buildUploadInput(String filePath) {
    final normalized = _sanitizePreferenceForSubmit(state.preference);
    return CreateUploadJobInput(
      filePath: filePath,
      model: normalized.model,
      task: normalized.task,
      language: normalized.language,
      outputFormat: normalized.outputFormat,
      requestedOutputs: _buildRequestedOutputsForSubmit(normalized),
      deliveryMode: _buildDeliveryModeForSubmit(normalized),
      generateSubtitles: _resolveGenerateSubtitles(normalized),
      burnSubtitlesIntoVideo: normalized.requestVideoBurned,
      keepTimestamps: normalized.keepTimestamps,
      splitBySentence: normalized.splitBySentence,
      wordTimestamps: normalized.wordTimestamps,
      vadFilter: normalized.vadFilter,
      devicePreference: normalized.devicePreference,
      computeType: normalized.computeType,
      beamSize: normalized.beamSize,
      maxSubtitleChars: normalized.maxSubtitleChars,
      subtitleStyle: _resolveSubtitleStyleForSubmit(normalized),
      subtitleVisualPreset: normalized.subtitleVisualPreset,
      targetLanguages: normalized.task == 'translate'
          ? _normalizeTargetLanguagesForController(normalized.targetLanguages)
          : const [],
      videoDeliveryMode: _resolveVideoDeliveryModeForSubmit(normalized),
      aiEnhancementEnabled: normalized.aiEnhancementEnabled,
      aiProvider: normalized.aiProvider,
      aiModel: normalized.aiModel,
      aiMode: _forceAiModesForTask(
        _normalizeAiModesCsv(normalized.aiMode, normalized.task),
        normalized.task,
      ).join(','),
      aiPrompt: normalized.aiPrompt,
      aiTemperature: normalized.aiTemperature,
      aiTopP: normalized.aiTopP,
      aiMaxTokens: normalized.aiMaxTokens,
      aiChunkChars: normalized.aiChunkChars,
      aiUseVisualContext: normalized.aiUseVisualContext,
      aiFrameSampleSeconds: normalized.aiFrameSampleSeconds,
      preserveTimestamps: normalized.preserveTimestamps,
      aiRevisionPasses: normalized.aiRevisionPasses,
      useAdvancedAlignment: normalized.useAdvancedAlignment,
      enableOnlineContext: normalized.enableOnlineContext,
      contextHints: normalized.contextHints,
      qualityProfile: normalized.qualityProfile,
      contentMode: normalized.contentMode,
      speakerStyleMode: normalized.speakerStyleMode,
      styleIntensity: normalized.styleIntensity,
      renderedPreviewMode: normalized.renderedPreviewMode,
      animeSongLayoutMode: normalized.animeSongLayoutMode,
      karaokeGranularity: normalized.karaokeGranularity,
    );
  }

  void _syncPolling() {
    final shouldPoll =
        state.hasActiveJobs || (state.selectedJob?.status == 'processing');
    if (shouldPoll) {
      _startPolling();
    } else {
      _stopPolling();
    }
  }

  void _startPolling() {
    if (_pollingTimer != null) {
      if (!state.isPolling) {
        state = state.copyWith(isPolling: true);
      }
      return;
    }

    state = state.copyWith(isPolling: true);
    _pollingTimer = Timer.periodic(_pollingInterval, (_) async {
      if (state.isRefreshingJobs ||
          state.isRefreshingSelectedJob ||
          state.isSubmitting) {
        return;
      }

      try {
        final jobs = await _api.listJobs();
        final selectedId = state.selectedJobId;
        TranscriptionJobDetail? selectedDetail = state.selectedJob;

        if (selectedId != null && jobs.any((job) => job.id == selectedId)) {
          final selectedListItem = jobs.firstWhere(
            (job) => job.id == selectedId,
          );
          if (selectedListItem.isActive ||
              state.selectedJob?.status == 'processing') {
            try {
              selectedDetail = await _api.getJob(selectedId);
            } catch (_) {}
          }
        }

        state = state.copyWith(
          jobs: jobs,
          selectedJob: selectedDetail,
          lastUpdatedAt: DateTime.now(),
        );

        final hasActive =
            jobs.any((job) => job.isActive) ||
            selectedDetail?.status == 'processing';
        if (!hasActive) {
          _stopPolling();
        }
      } catch (_) {
        // polling failure is intentionally silent to avoid flickering the UI
      }
    });
  }

  void _stopPolling({bool updateState = true}) {
    _pollingTimer?.cancel();
    _pollingTimer = null;
    if (updateState && !_isDisposed && state.isPolling) {
      state = state.copyWith(isPolling: false);
    }
  }

  TranscriptionPreference _sanitizePreferenceForOptions(
    TranscriptionPreference preference,
    TranscriptionOptions? options,
  ) {
    var normalized = preference.normalizedForUi();

    if (options == null) {
      final forcedModes = _forceAiModesForTask(
        _normalizeAiModesCsv(normalized.aiMode, normalized.task),
        normalized.task,
      );
      return normalized
          .copyWith(aiMode: forcedModes.join(','))
          .normalizedForUi();
    }

    final models = options.models;
    final tasks = options.tasks;
    final languages = options.languages;
    final devices = options.devices;
    final computeTypes = options.computeTypes;
    final subtitlePresets = options.subtitleVisualPresets;
    final aiProviders =
        state.capabilities?.providers.map((item) => item.id).toList() ??
        options.aiProviders;
    final targetLanguageOptions = options.targetLanguages;
    final alignmentModes = options.alignmentModes;
    final qualityProfiles = options.qualityProfiles;
    final contentModes = options.contentModes;
    final speakerStyleModes = options.speakerStyleModes;
    final styleIntensities = options.styleIntensities;
    final renderedPreviewModes = options.renderedPreviewModes;
    final animeSongLayoutModes = options.animeSongLayoutModes;
    final karaokeGranularities = options.karaokeGranularities;

    final selectedAiProvider = aiProviders.contains(normalized.aiProvider)
        ? normalized.aiProvider
        : (aiProviders.contains('ollama_project')
              ? 'ollama_project'
              : aiProviders.firstOrNull ?? normalized.aiProvider);
    final selectedAiProviderInfo = state.capabilities?.providerById(
      selectedAiProvider,
    );
    final installedAiModels = installedAiModelsForProvider(selectedAiProvider);
    final selectableAiModels =
        selectedAiProviderInfo?.multimodalModels.isNotEmpty == true
        ? selectedAiProviderInfo!.multimodalModels
        : installedAiModels;

    normalized = normalized.copyWith(
      model: models.contains(normalized.model)
          ? normalized.model
          : (models.contains('large-v3')
                ? 'large-v3'
                : models.firstOrNull ?? normalized.model),
      task: tasks.contains(normalized.task) ? normalized.task : 'transcribe',
      language: languages.contains(normalized.language)
          ? normalized.language
          : 'auto',
      devicePreference: devices.contains(normalized.devicePreference)
          ? normalized.devicePreference
          : (devices.contains('auto')
                ? 'auto'
                : devices.firstOrNull ?? normalized.devicePreference),
      computeType: computeTypes.contains(normalized.computeType)
          ? normalized.computeType
          : (computeTypes.contains('float16')
                ? 'float16'
                : computeTypes.firstOrNull ?? normalized.computeType),
      subtitleVisualPreset:
          subtitlePresets.contains(normalized.subtitleVisualPreset)
          ? normalized.subtitleVisualPreset
          : (subtitlePresets.contains('default')
                ? 'default'
                : subtitlePresets.firstOrNull ??
                      normalized.subtitleVisualPreset),
      subtitleStyle: subtitlePresets.contains(normalized.subtitleStyle)
          ? normalized.subtitleStyle
          : normalized.subtitleVisualPreset,
      aiProvider: selectedAiProvider,
      aiModel: _resolveAiModelForOptions(
        normalized.aiModel,
        selectableAiModels,
        installedAiModels,
        selectedAiProviderInfo?.defaultModel,
      ),
      useAdvancedAlignment:
          alignmentModes.contains(normalized.useAdvancedAlignment)
          ? normalized.useAdvancedAlignment
          : 'auto',
      qualityProfile: qualityProfiles.contains(normalized.qualityProfile)
          ? normalized.qualityProfile
          : 'balanced',
      contentMode: contentModes.contains(normalized.contentMode)
          ? normalized.contentMode
          : 'episode',
      speakerStyleMode: speakerStyleModes.contains(normalized.speakerStyleMode)
          ? normalized.speakerStyleMode
          : 'heuristic',
      styleIntensity: styleIntensities.contains(normalized.styleIntensity)
          ? normalized.styleIntensity
          : 'thematic',
      renderedPreviewMode:
          renderedPreviewModes.contains(normalized.renderedPreviewMode)
          ? normalized.renderedPreviewMode
          : 'fast',
      animeSongLayoutMode:
          animeSongLayoutModes.contains(normalized.animeSongLayoutMode)
          ? normalized.animeSongLayoutMode
          : 'off',
      karaokeGranularity:
          karaokeGranularities.contains(normalized.karaokeGranularity)
          ? normalized.karaokeGranularity
          : (normalized.contentMode == 'anime_song' ? 'syllable' : 'off'),
      targetLanguages: normalized.task == 'translate'
          ? normalized.targetLanguages
                .where(targetLanguageOptions.contains)
                .toList()
          : const [],
    );

    final modes = _forceAiModesForTask(
      _normalizeAiModesCsv(normalized.aiMode, normalized.task),
      normalized.task,
    ).where((mode) => options.aiModes.contains(mode)).toList();

    normalized = normalized.copyWith(
      aiMode:
          (modes.isEmpty
                  ? _forceAiModesForTask(const [], normalized.task)
                  : modes)
              .join(','),
    );

    return normalized.normalizedForUi();
  }

  TranscriptionPreference _sanitizePreferenceForSubmit(
    TranscriptionPreference preference,
  ) {
    var normalized = _sanitizePreferenceForOptions(preference, state.options);

    if (normalized.task == 'translate') {
      final targets = _normalizeTargetLanguagesForController(
        normalized.targetLanguages,
      );
      if (targets.isEmpty) {
        throw Exception(
          'Selecione ao menos um idioma de saída para a tarefa Traduzir.',
        );
      }
      normalized = normalized.copyWith(targetLanguages: targets);
    } else {
      normalized = normalized.copyWith(targetLanguages: const []);
    }

    final modes = _forceAiModesForTask(
      _normalizeAiModesCsv(normalized.aiMode, normalized.task),
      normalized.task,
    );

    normalized = normalized.copyWith(aiMode: modes.join(',')).normalizedForUi();

    if (normalized.aiEnhancementEnabled &&
        !isAiModelInstalled(normalized.aiProvider, normalized.aiModel)) {
      throw Exception(
        'O modelo ${normalized.aiModel} não está instalado para o provider ${normalized.aiProvider}. Baixe o modelo antes de rodar.',
      );
    }

    if (!normalized.requestVideoBurned &&
        _normalizeTextOutputsForController(
          normalized.selectedTextOutputs,
        ).isEmpty) {
      throw Exception(
        'Selecione ao menos uma saída textual ou habilite a entrega de vídeo antes de rodar.',
      );
    }

    return normalized;
  }

  List<String> _buildRequestedOutputsForSubmit(
    TranscriptionPreference preference,
  ) {
    final outputs = <String>[
      ..._normalizeTextOutputsForController(preference.selectedTextOutputs),
    ];

    if (preference.requestVideoBurned) {
      outputs.add('video_burned');
    }

    if (_containsStyleMode(preference)) {
      outputs.add('ass');
    }

    final ordered = <String>[];
    for (final item in ['txt', 'srt', 'vtt', 'ass', 'video_burned']) {
      if (outputs.contains(item) && !ordered.contains(item)) {
        ordered.add(item);
      }
    }
    return ordered;
  }

  String _buildDeliveryModeForSubmit(TranscriptionPreference preference) {
    if (preference.requestVideoBurned &&
        preference.selectedTextOutputs.isEmpty) {
      return 'video_only';
    }
    return 'standard';
  }

  bool _resolveGenerateSubtitles(TranscriptionPreference preference) {
    if (_containsStyleMode(preference)) return true;
    if (preference.requestVideoBurned) return true;
    return preference.selectedTextOutputs.any((item) => item != 'txt');
  }

  String _resolveSubtitleStyleForSubmit(TranscriptionPreference preference) {
    if (_containsStyleMode(preference) || preference.requestVideoBurned) {
      return preference.subtitleVisualPreset;
    }
    return preference.subtitleStyle;
  }

  String _resolveVideoDeliveryModeForSubmit(
    TranscriptionPreference preference,
  ) {
    if (preference.task == 'translate' &&
        preference.targetLanguages.length > 1) {
      return 'mux_subtitles';
    }

    if (preference.requestVideoBurned) {
      if (preference.videoDeliveryMode == 'mux_subtitles') {
        return 'mux_subtitles';
      }
      return 'burned_video';
    }

    return preference.videoDeliveryMode;
  }

  bool _containsStyleMode(TranscriptionPreference preference) {
    return preference.aiEnhancementEnabled &&
        _normalizeAiModesCsv(
          preference.aiMode,
          preference.task,
        ).contains('subtitle_styling');
  }

  Future<void> _handleUnauthorizedIfNeeded(Object error) async {
    if (error is ApiException && error.statusCode == 401) {
      await _ref.read(authControllerProvider.notifier).handleUnauthorized();
    }
  }

  TranscriptionPreference _applyDerivedPreferenceConstraints(
    TranscriptionPreference preference,
    TranscriptionOptions? options,
  ) {
    var normalized = preference.normalizedForUi();
    final aiModes = _forceAiModesForTask(
      _normalizeAiModesCsv(normalized.aiMode, normalized.task),
      normalized.task,
    );

    final selectedTextOutputs = _normalizeTextOutputsForController([
      ...normalized.selectedTextOutputs,
      if (normalized.aiEnhancementEnabled &&
          aiModes.contains('subtitle_styling'))
        'ass',
    ]);

    final targetLanguages = normalized.task == 'translate'
        ? _normalizeTargetLanguagesForController(normalized.targetLanguages)
        : const <String>[];

    var requestVideoBurned = normalized.requestVideoBurned;
    var videoDeliveryMode = normalized.videoDeliveryMode;

    if (normalized.task == 'translate' && targetLanguages.length > 1) {
      videoDeliveryMode = 'mux_subtitles';
      requestVideoBurned = false;
    } else if (!requestVideoBurned && videoDeliveryMode == 'burned_video') {
      videoDeliveryMode = 'standard';
    }

    if (requestVideoBurned && videoDeliveryMode == 'video_only') {
      videoDeliveryMode = 'burned_video';
    }

    var karaokeGranularity = normalized.karaokeGranularity;
    final maxSupportedKaraokeGranularity =
        state.capabilities?.maxSupportedKaraokeGranularity ?? 'syllable';
    if (normalized.contentMode == 'anime_song') {
      if (maxSupportedKaraokeGranularity == 'word' &&
          karaokeGranularity == 'syllable') {
        karaokeGranularity = 'word';
      }
      if (karaokeGranularity == 'off') {
        karaokeGranularity = maxSupportedKaraokeGranularity == 'word'
            ? 'word'
            : 'syllable';
      }
    } else if (normalized.contentMode == 'auto') {
      if (maxSupportedKaraokeGranularity == 'word' &&
          karaokeGranularity == 'syllable') {
        karaokeGranularity = 'word';
      }
    } else {
      karaokeGranularity = 'off';
    }

    normalized = normalized.copyWith(
      selectedTextOutputs: selectedTextOutputs,
      requestVideoBurned: requestVideoBurned,
      burnSubtitlesIntoVideo: requestVideoBurned,
      targetLanguages: targetLanguages,
      videoDeliveryMode: videoDeliveryMode,
      aiMode: aiModes.join(','),
      aiRevisionPasses: _clampInt(normalized.aiRevisionPasses, min: 0, max: 10),
      animeSongLayoutMode:
          normalized.contentMode == 'anime_song' ||
              (normalized.contentMode == 'auto' && karaokeGranularity != 'off')
          ? 'romaji_top_translation_bottom'
          : normalized.animeSongLayoutMode,
      karaokeGranularity: karaokeGranularity,
    );

    return normalized.normalizedForUi();
  }

  static String _toMessage(Object error) {
    final text = error.toString().trim();
    if (text.startsWith('Exception:')) {
      return text.substring('Exception:'.length).trim();
    }
    return text;
  }
}

List<String> _normalizeTextOutputsForController(List<String> values) {
  const order = ['txt', 'srt', 'vtt', 'ass'];
  final set = <String>{};
  for (final value in values) {
    final normalized = value.trim().toLowerCase();
    if (order.contains(normalized)) {
      set.add(normalized);
    }
  }
  return order.where(set.contains).toList();
}

List<String> _normalizeTargetLanguagesForController(List<String> values) {
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
  for (final value in values) {
    final normalized = value.trim();
    if (normalized.isNotEmpty) {
      set.add(normalized);
    }
  }

  final result = <String>[];
  for (final item in order) {
    if (set.contains(item)) {
      result.add(item);
    }
  }
  for (final item in set) {
    if (!result.contains(item)) {
      result.add(item);
    }
  }
  return result;
}

List<String> _normalizeAiModesCsv(String? raw, String task) {
  final values = <String>[];
  final source = (raw ?? '').trim();

  if (source.isNotEmpty) {
    for (final item in source.split(',')) {
      final normalized = _normalizeSingleAiMode(item);
      if (normalized != null && !values.contains(normalized)) {
        values.add(normalized);
      }
    }
  }

  return _forceAiModesForTask(values, task);
}

String? _normalizeSingleAiMode(String? raw) {
  final normalized = (raw ?? '').trim().toLowerCase();
  switch (normalized) {
    case 'correction':
      return 'correction';
    case 'semantic_translation':
    case 'semantic-translation':
    case 'translation':
      return 'semantic_translation';
    case 'subtitle_styling':
    case 'subtitle-styling':
    case 'styling':
      return 'subtitle_styling';
    default:
      return null;
  }
}

List<String> _orderedAiModes(List<String> values) {
  const order = ['correction', 'semantic_translation', 'subtitle_styling'];

  final set = <String>{};
  for (final value in values) {
    final normalized = _normalizeSingleAiMode(value);
    if (normalized != null) {
      set.add(normalized);
    }
  }

  return order.where(set.contains).toList();
}

List<String> _forceAiModesForTask(List<String> values, String task) {
  final ordered = _orderedAiModes(values);
  if (task == 'translate' && !ordered.contains('semantic_translation')) {
    return _orderedAiModes([...ordered, 'semantic_translation']);
  }
  if (ordered.isEmpty) {
    return task == 'translate'
        ? const ['semantic_translation']
        : const ['correction'];
  }
  return ordered;
}

String _normalizeTask(String task, TranscriptionOptions? options) {
  final normalized = task.trim().toLowerCase();
  final allowed = options?.tasks ?? const ['transcribe', 'translate'];
  return allowed.contains(normalized) ? normalized : 'transcribe';
}

String _resolveAiModelForOptions(
  String currentValue,
  List<String> selectableModels,
  List<String> installedModels,
  String? defaultModel,
) {
  final normalizedCurrent = currentValue.trim();
  if (normalizedCurrent.isNotEmpty &&
      (selectableModels.contains(normalizedCurrent) ||
          installedModels.contains(normalizedCurrent))) {
    return normalizedCurrent;
  }

  final normalizedDefault = defaultModel?.trim() ?? '';
  if (normalizedDefault.isNotEmpty &&
      (selectableModels.contains(normalizedDefault) ||
          installedModels.contains(normalizedDefault))) {
    return normalizedDefault;
  }

  if (installedModels.isNotEmpty) {
    return installedModels.first;
  }

  if (selectableModels.isNotEmpty) {
    return selectableModels.first;
  }

  if (normalizedDefault.isNotEmpty) {
    return normalizedDefault;
  }

  return UiTranscriptionConstants.aiModelOptions.first;
}

int _clampInt(int value, {required int min, required int max}) {
  if (value < min) return min;
  if (value > max) return max;
  return value;
}

double _clampDouble(double value, {required double min, required double max}) {
  if (value < min) return min;
  if (value > max) return max;
  return value;
}

extension _FirstOrNullExtension<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
