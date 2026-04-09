import 'package:flutter_test/flutter_test.dart';

import 'package:app_flutter/features/transcription/data/transcription_models.dart';

void main() {
  test('preference normalizes anime_song to karaoke syllable mode', () {
    final preference = TranscriptionPreference.defaults()
        .copyWith(
          aiEnhancementEnabled: true,
          contentMode: 'anime_song',
          animeSongLayoutMode: 'off',
          karaokeGranularity: 'off',
        )
        .normalizedForUi();

    expect(preference.animeSongLayoutMode, 'romaji_top_translation_bottom');
    expect(preference.karaokeGranularity, 'syllable');
  });

  test('preference keeps karaoke enabled for auto mode', () {
    final preference = TranscriptionPreference.defaults()
        .copyWith(
          aiEnhancementEnabled: true,
          contentMode: 'auto',
          karaokeGranularity: 'syllable',
          animeSongLayoutMode: 'romaji_top_translation_bottom',
        )
        .normalizedForUi();

    expect(preference.contentMode, 'auto');
    expect(preference.karaokeGranularity, 'syllable');
  });

  test('preference parser falls back to multimodal ai model', () {
    final preference = TranscriptionPreference.fromJson(<String, dynamic>{
      'aiEnhancementEnabled': true,
      'aiProvider': 'ollama_project',
    }).normalizedForUi();

    expect(preference.aiModel, 'qwen2.5vl:7b');
  });

  test('job detail parses diagnostics and style source', () {
    final detail = TranscriptionJobDetail.fromJson(<String, dynamic>{
      'id': 'job-1',
      'sourceType': 'file_path',
      'sourceValue': 'video.mp4',
      'model': 'large-v3',
      'task': 'translate',
      'language': 'auto',
      'outputFormat': 'all',
      'requestedOutputs': <String>['txt', 'srt', 'vtt', 'ass'],
      'deliveryMode': 'standard',
      'generateSubtitles': true,
      'burnSubtitlesIntoVideo': false,
      'keepTimestamps': true,
      'splitBySentence': true,
      'wordTimestamps': true,
      'vadFilter': true,
      'devicePreference': 'auto',
      'computeType': 'float16',
      'beamSize': 5,
      'maxSubtitleChars': 42,
      'subtitleStyle': 'cinematic',
      'targetLanguages': <String>['en', 'ja'],
      'videoDeliveryMode': 'mux_subtitles',
      'aiEnhancementEnabled': true,
      'aiProvider': 'ollama',
      'aiModel': 'qwen3.5:35b-a3b-q4_K_M',
      'aiMode': 'correction,semantic_translation,subtitle_styling',
      'karaokeGranularity': 'syllable',
      'styleSource': 'local_preset',
      'contentDetectionConfidence': 0.91,
      'karaokeModeApplied': 'syllable',
      'sceneMapPath': 'outputs/scene_map.json',
      'speakerMapPath': 'outputs/speaker_map.json',
      'lyricAlignmentPath': 'outputs/lyric_alignment.json',
      'voiceAnalysisSource': 'heuristic_overlap_layout',
      'sceneAnalysisSource': 'timing_style_blocks',
      'previewModeApplied': 'rendered',
      'plannerModelUsed': 'qwen2.5vl:7b',
      'reviewModelUsed': 'qwen2.5:14b',
      'timeoutProfileApplied': 'balanced',
      'jobTimeoutMinutes': 480,
      'structuredTimeoutSeconds': 90,
      'styleTimeoutSeconds': 180,
      'diagnostics': <Map<String, dynamic>>[
        <String, dynamic>{
          'stage': 'semantic_translation',
          'severity': 'warning',
          'message': 'Idioma en nao foi publicado.',
          'language': 'en',
          'fallbackUsed': 'not_published',
        },
      ],
      'status': 'completed',
      'progressPercent': 100,
      'errorMessage': 'Job concluido com warnings.',
      'createdAtUtc': '2026-04-01T00:00:00Z',
      'outputs': <Map<String, dynamic>>[],
    });

    expect(detail.styleSource, 'local_preset');
    expect(detail.karaokeGranularity, 'syllable');
    expect(detail.contentDetectionConfidence, 0.91);
    expect(detail.karaokeModeApplied, 'syllable');
    expect(detail.sceneMapPath, 'outputs/scene_map.json');
    expect(detail.speakerMapPath, 'outputs/speaker_map.json');
    expect(detail.lyricAlignmentPath, 'outputs/lyric_alignment.json');
    expect(detail.voiceAnalysisSource, 'heuristic_overlap_layout');
    expect(detail.sceneAnalysisSource, 'timing_style_blocks');
    expect(detail.previewModeApplied, 'rendered');
    expect(detail.plannerModelUsed, 'qwen2.5vl:7b');
    expect(detail.reviewModelUsed, 'qwen2.5:14b');
    expect(detail.timeoutProfileApplied, 'balanced');
    expect(detail.jobTimeoutMinutes, 480);
    expect(detail.structuredTimeoutSeconds, 90);
    expect(detail.styleTimeoutSeconds, 180);
    expect(detail.diagnostics, hasLength(1));
    expect(detail.diagnostics.single.stage, 'semantic_translation');
    expect(detail.diagnostics.single.fallbackUsed, 'not_published');
  });

  test('preview policy prefers rendered preview for anime song jobs', () {
    final detail = TranscriptionJobDetail.fromJson(<String, dynamic>{
      'id': 'job-2',
      'sourceType': 'file_path',
      'sourceValue': 'video.mp4',
      'model': 'large-v3',
      'task': 'translate',
      'language': 'auto',
      'outputFormat': 'all',
      'requestedOutputs': <String>['txt', 'srt', 'vtt', 'ass'],
      'deliveryMode': 'standard',
      'generateSubtitles': true,
      'burnSubtitlesIntoVideo': false,
      'keepTimestamps': true,
      'splitBySentence': true,
      'wordTimestamps': true,
      'vadFilter': true,
      'devicePreference': 'auto',
      'computeType': 'float16',
      'beamSize': 5,
      'subtitleStyle': 'cinematic',
      'targetLanguages': <String>['en'],
      'videoDeliveryMode': 'mux_subtitles',
      'aiEnhancementEnabled': true,
      'aiProvider': 'ollama',
      'aiModel': 'qwen2.5:14b',
      'aiMode': 'semantic_translation,subtitle_styling',
      'contentMode': 'anime_song',
      'renderedPreviewMode': 'fast',
      'karaokeModeApplied': 'syllable',
      'status': 'completed',
      'progressPercent': 100,
      'createdAtUtc': '2026-04-02T00:00:00Z',
      'outputs': <Map<String, dynamic>>[],
    });

    expect(
      TranscriptionPreviewPolicy.prefersRenderedPreviewForDetail(detail),
      isTrue,
    );
  });

  test('capabilities parse voice and scene analysis flags', () {
    final capabilities = TranscriptionCapabilities.fromJson(<String, dynamic>{
      'service': 'transcription',
      'fasterWhisperInstalled': true,
      'defaultModel': 'large-v3',
      'deviceMode': 'auto',
      'computeTypeMode': 'float16',
      'hardware': <String, dynamic>{
        'device': 'cuda',
        'provider': 'ctranslate2',
        'cpuName': 'CPU',
        'logicalCores': 16,
        'physicalCores': 8,
        'ramTotalBytes': 100,
        'ramAvailableBytes': 50,
        'advancedAlignmentAvailable': false,
        'diarizationAvailable': false,
        'voiceAnalysisAvailable': true,
        'sceneAnalysisAvailable': true,
        'maxSupportedKaraokeGranularity': 'syllable',
        'gpus': <Map<String, dynamic>>[],
      },
      'recommendedProfile': 'balanced',
      'voiceAnalysisAvailable': true,
      'sceneAnalysisAvailable': true,
      'maxSupportedKaraokeGranularity': 'syllable',
      'installedModels': <String>['gemma3:4b'],
      'jobTimeoutMinutes': 480,
      'structuredTimeoutSeconds': 90,
      'styleTimeoutSeconds': 180,
      'timeoutProfileApplied': 'balanced',
    });

    expect(capabilities.voiceAnalysisAvailable, isTrue);
    expect(capabilities.sceneAnalysisAvailable, isTrue);
    expect(capabilities.hardware.voiceAnalysisAvailable, isTrue);
    expect(capabilities.hardware.sceneAnalysisAvailable, isTrue);
    expect(capabilities.jobTimeoutMinutes, 480);
    expect(capabilities.structuredTimeoutSeconds, 90);
    expect(capabilities.styleTimeoutSeconds, 180);
    expect(capabilities.timeoutProfileApplied, 'balanced');
  });
}
