from app.schemas.transcription import JobTranscriptionRequest
from app.services.transcription_engine import (
    OllamaCallError,
    OllamaGenerateResult,
    _build_scene_map,
    _build_release_gate,
    _build_quality_profiles,
    _build_voice_analysis,
    _build_karaoke_plan,
    _build_lyric_alignment_report,
    _call_structured_items_with_repair,
    _compact_ollama_raw_excerpt,
    _detect_content_mode,
    _detect_song_blocks,
    _derive_style_palette,
    _extract_ollama_text,
    _merge_style_plan_with_floor,
    _quality_is_local_non_ai_publishable,
    _quality_is_publishable,
    _quality_is_soft_publishable,
    _quality_summary_rank,
    _rescue_low_quality_segments,
    _sanitize_ai_text,
    _sanitize_translated_text,
    _should_publish_empty_translation,
    _score_translation_segments,
    _retranslate_low_quality_segments_with_ollama,
    _summarize_quality_scores,
    _should_use_english_reference_as_primary_translation,
)
from pathlib import Path


def test_extract_ollama_text_uses_thinking_when_response_is_empty_for_structured_output():
    decoded = {
        "response": "",
        "thinking": '{"items": [{"index": 0, "text": "ok"}]}',
    }

    text, source_field = _extract_ollama_text(decoded, structured=True)

    assert source_field == "thinking"
    assert text == '{"items": [{"index": 0, "text": "ok"}]}'


def test_extract_ollama_text_prefers_response_when_available():
    decoded = {
        "response": '{"items": [{"index": 0, "text": "ok"}]}',
        "thinking": '{"items": [{"index": 0, "text": "fallback"}]}',
    }

    text, source_field = _extract_ollama_text(decoded, structured=True)

    assert source_field == "response"
    assert '"text": "ok"' in text


def test_sanitize_ai_text_removes_decorative_symbols_but_preserves_punctuation():
    sanitized = _sanitize_ai_text("Oi!!! ❤️ ✨ ...")

    assert sanitized == "Oi!!! ..."


def test_sanitize_translated_text_collapses_repeated_clauses_and_tail_repetition():
    sanitized = _sanitize_translated_text(
        "語れない 眠れない 届かない",
        "I can't speak, I can't sleep, I can't sleep",
    )

    assert sanitized == "I can't speak, I can't sleep"


def test_sanitize_translated_text_collapses_repeated_suffix_phrase():
    sanitized = _sanitize_translated_text(
        "不可思議 知りたいだけ",
        "Is the sound of my eyes The sound of my eyes",
    )

    assert sanitized == "Is the sound of my eyes"


def test_sanitize_translated_text_suppresses_output_when_source_segment_is_empty():
    sanitized = _sanitize_translated_text("", "The sound of my eyes")

    assert sanitized == ""


def test_compact_ollama_raw_excerpt_drops_large_context_arrays():
    raw = (
        '{"model":"qwen","response":"","thinking":"{\\"fontSize\\":42}",'
        '"context":[1,2,3,4,5,6,7,8,9],"done":true}'
    )
    decoded = {
        "model": "qwen",
        "response": "",
        "thinking": '{"fontSize":42}',
        "context": [1, 2, 3, 4, 5, 6, 7, 8, 9],
        "done": True,
    }

    excerpt = _compact_ollama_raw_excerpt(raw, decoded, limit=120)

    assert excerpt is not None
    assert '"thinking"' in excerpt
    assert '"context"' not in excerpt


def test_structured_items_with_repair_splits_batches_when_count_is_wrong(
    monkeypatch,
):
    def fake_chat(*, messages, **kwargs):
        payload = __import__("json").loads(messages[-1]["content"])
        if payload.get("task") == "repair_structured_items":
            payload = payload["originalRequest"]

        items = payload.get("items") or []
        if len(items) > 1:
            return OllamaGenerateResult(
                text='{"items":[{"index":0,"text":"partial"}]}',
                source_field="message.content",
            )

        index = int(items[0]["index"])
        return OllamaGenerateResult(
            text=f'{{"items":[{{"index":{index},"text":"ok-{index}"}}]}}',
            source_field="message.content",
        )

    monkeypatch.setattr(
        "app.services.transcription_engine._call_ollama_chat",
        fake_chat,
    )

    mapped, _, repaired = _call_structured_items_with_repair(
        model="qwen2.5:32b",
        system="test",
        prompt_payload={
            "task": "translate_subtitles",
            "expectedCount": 2,
            "items": [
                {"index": 0, "text": "a"},
                {"index": 1, "text": "b"},
            ],
        },
        expected_count=2,
        value_field="text",
        temperature=0.0,
        top_p=1.0,
        num_predict=256,
    )

    assert repaired is True
    assert mapped == {0: "ok-0", 1: "ok-1"}


def test_structured_items_with_repair_falls_back_to_original_text_for_single_item(
    monkeypatch,
):
    def fake_chat(**kwargs):
        raise OllamaCallError(
            "timeout",
            model="qwen2.5:32b",
            status_code=504,
        )

    monkeypatch.setattr(
        "app.services.transcription_engine._call_ollama_chat",
        fake_chat,
    )

    mapped, response, repaired = _call_structured_items_with_repair(
        model="qwen2.5:32b",
        system="test",
        prompt_payload={
            "task": "correct_subtitles",
            "expectedCount": 1,
            "items": [{"index": 0, "text": "texto base"}],
        },
        expected_count=1,
        value_field="text",
        temperature=0.0,
        top_p=1.0,
        num_predict=256,
    )

    assert repaired is True
    assert response.source_field == "local_fallback"
    assert mapped == {0: "texto base"}


def test_structured_items_with_repair_falls_back_to_heuristic_label_for_single_item(
    monkeypatch,
):
    def fake_chat(**kwargs):
        raise OllamaCallError(
            "timeout",
            model="qwen2.5:14b",
            status_code=504,
        )

    monkeypatch.setattr(
        "app.services.transcription_engine._call_ollama_chat",
        fake_chat,
    )

    mapped, response, repaired = _call_structured_items_with_repair(
        model="qwen2.5:14b",
        system="test",
        prompt_payload={
            "task": "classify_subtitle_style_labels",
            "expectedCount": 1,
            "items": [
                {
                    "index": 0,
                    "text": "The sound of my eyes",
                    "fallbackLabel": "chorus",
                }
            ],
        },
        expected_count=1,
        value_field="label",
        enum_values=["default", "chorus", "emphasis"],
        temperature=0.0,
        top_p=1.0,
        num_predict=128,
    )

    assert repaired is True
    assert response.source_field == "local_fallback"
    assert mapped == {0: "chorus"}


def test_structured_items_with_repair_rejects_non_enum_label_and_falls_back(
    monkeypatch,
):
    def fake_chat(*, messages, **kwargs):
        payload = __import__("json").loads(messages[-1]["content"])
        items = payload.get("items") or []
        index = int(items[0]["index"])
        return OllamaGenerateResult(
            text=f'{{"items":[{{"index":{index},"label":"This is not a valid label"}}]}}',
            source_field="message.content",
        )

    monkeypatch.setattr(
        "app.services.transcription_engine._call_ollama_chat",
        fake_chat,
    )

    mapped, _, repaired = _call_structured_items_with_repair(
        model="qwen2.5:14b",
        system="test",
        prompt_payload={
            "task": "classify_subtitle_style_labels",
            "expectedCount": 1,
            "items": [
                {
                    "index": 0,
                    "text": "The sound of my eyes",
                    "fallbackLabel": "chorus",
                }
            ],
        },
        expected_count=1,
        value_field="label",
        enum_values=["default", "chorus", "emphasis"],
        temperature=0.0,
        top_p=1.0,
        num_predict=128,
    )

    assert repaired is True
    assert mapped == {0: "chorus"}


def test_quality_scoring_does_not_fail_suppressed_noise_segments():
    scores = _score_translation_segments(
        source_segments=[
            {"text": "@fansub", "start": 0.0, "end": 1.0},
            {"text": "こんにちは", "start": 1.0, "end": 3.0},
        ],
        translated_segments=[
            {"text": "", "start": 0.0, "end": 1.0},
            {"text": "Hello there.", "start": 1.0, "end": 3.0},
        ],
        source_language="ja",
        target_language="en",
    )

    summary = _summarize_quality_scores(scores)

    assert scores[0].score == 100
    assert "noise_suppressed" in scores[0].reasons
    assert summary["suppressedNoiseSegments"] == 1
    assert _quality_is_publishable(summary, total_segments=2) is True


def test_style_palette_creates_distinct_visible_variants():
    palette = _derive_style_palette(
        {
            "primaryColour": "&H00F6F6F6",
            "outlineColour": "&H00101010",
            "backColour": "&H50000000",
        }
    )

    assert palette["defaultPrimary"] != palette["shoutPrimary"]
    assert palette["defaultPrimary"] != palette["whisperPrimary"]
    assert palette["chorusOutline"] != palette["defaultOutline"]


def test_sanitize_translated_text_removes_numeric_metadata_leak():
    sanitized = _sanitize_translated_text(
        "不可思議 知りたいだけ",
        "A chart no one can decipher, 4.92",
    )

    assert sanitized == "A chart no one can decipher"


def test_merge_style_plan_with_floor_keeps_preset_strength():
    merged = _merge_style_plan_with_floor(
        {
            "fontSize": 40,
            "songFontSize": 44,
            "outline": 4.0,
            "marginV": 64,
            "scaleIntro": 108,
            "primaryColour": "&H00FFFFFF",
            "outlineColour": "&H00000000",
            "backColour": "&H64000000",
        },
        {
            "fontSize": 24,
            "songFontSize": 20,
            "outline": 2.0,
            "marginV": 20,
            "scaleIntro": 999999,
            "primaryColour": "&H00EAF8FF",
        },
    )

    assert merged["fontSize"] == 40
    assert merged["songFontSize"] == 44
    assert merged["outline"] >= 3.7
    assert merged["marginV"] >= 54
    assert merged["scaleIntro"] == 125
    assert merged["primaryColour"] == "&H00FFF8EA"


def test_rescue_low_quality_segments_replaces_failed_line_when_reference_is_better():
    source = [
        {"text": "不可思議 知りたいだけ", "start": 0.0, "end": 2.0},
        {"text": "あなたの見てる正体", "start": 2.0, "end": 4.0},
    ]
    current = [
        {"text": "IMERAI", "start": 0.0, "end": 2.0},
        {"text": "The truth you see", "start": 2.0, "end": 4.0},
    ]
    scored = _score_translation_segments(
        source_segments=source,
        translated_segments=current,
        source_language="ja",
        target_language="en",
    )
    assert scored[0].score < 60

    rescued, replacements = _rescue_low_quality_segments(
        source_segments=source,
        translated_segments=current,
        rescue_segments=[
            {"text": "Mysterious, just curious", "start": 0.0, "end": 2.0},
            {"text": "The truth you see", "start": 2.0, "end": 4.0},
        ],
        source_language="ja",
        target_language="en",
    )

    assert replacements == 1
    assert rescued[0]["text"] == "Mysterious, just curious"


def test_segment_rescue_can_outperform_full_reference_chain_for_publish_gate():
    source = [
        {"text": "不可思議 知りたいだけ", "start": 0.0, "end": 2.0},
        {"text": "あなたの見てる正体", "start": 2.0, "end": 4.0},
        {"text": "眠れない", "start": 4.0, "end": 6.0},
    ]
    current = [
        {"text": "IMERAI", "start": 0.0, "end": 2.0},
        {"text": "A verdade que você vê", "start": 2.0, "end": 4.0},
        {"text": "Não consigo dormir", "start": 4.0, "end": 6.0},
    ]
    rescue_chain = [
        {"text": "Mistério, eu só quero saber", "start": 0.0, "end": 2.0},
        {"text": "あなたの見てる正体", "start": 2.0, "end": 4.0},
        {"text": "Não consigo dormir", "start": 4.0, "end": 6.0},
    ]

    current_summary = _summarize_quality_scores(
        _score_translation_segments(
            source_segments=source,
            translated_segments=current,
            source_language="ja",
            target_language="pt-BR",
        )
    )
    rescue_summary = _summarize_quality_scores(
        _score_translation_segments(
            source_segments=source,
            translated_segments=rescue_chain,
            source_language="ja",
            target_language="pt-BR",
        )
    )

    merged, replacements = _rescue_low_quality_segments(
        source_segments=source,
        translated_segments=current,
        rescue_segments=rescue_chain,
        source_language="ja",
        target_language="pt-BR",
    )
    merged_summary = _summarize_quality_scores(
        _score_translation_segments(
            source_segments=source,
            translated_segments=merged,
            source_language="ja",
            target_language="pt-BR",
        )
    )

    assert replacements == 1
    assert _quality_is_publishable(current_summary, total_segments=3) is False
    assert _quality_is_publishable(rescue_summary, total_segments=3) is False
    assert _quality_is_publishable(merged_summary, total_segments=3) is True
    assert _quality_summary_rank(merged_summary, 3) > _quality_summary_rank(current_summary, 3)
    assert _quality_summary_rank(merged_summary, 3) > _quality_summary_rank(rescue_summary, 3)


def test_quality_gate_blocks_language_with_failed_segment():
    summary = {
        "averageScore": 86,
        "minScore": 42,
        "failedSegments": 1,
        "suppressedNoiseSegments": 0,
        "publishableSegments": 1,
    }

    assert _quality_is_publishable(summary, total_segments=2) is False


def test_soft_quality_gate_allows_borderline_high_average_language():
    summary = {
        "averageScore": 93.57,
        "minScore": 55,
        "failedSegments": 2,
        "suppressedNoiseSegments": 1,
        "publishableSegments": 33,
        "reviewSegments": 0,
    }

    assert _quality_is_publishable(summary, total_segments=36) is False
    assert _quality_is_soft_publishable(summary, total_segments=36) is True


def test_anime_song_karaoke_plan_includes_tokens_and_speaker_spans():
    segments = [
        {
            "start": 0.0,
            "end": 2.0,
            "text": "Mystery",
            "styleLabel": "chorus",
            "romajiText": "fushigi",
            "translationText": "Mystery",
            "speakerId": "speaker_1",
            "placement": "bottom",
        },
        {
            "start": 1.0,
            "end": 3.0,
            "text": "I need to know",
            "styleLabel": "emphasis",
            "romajiText": "shiritai dake",
            "translationText": "I need to know",
            "speakerId": "speaker_2",
            "placement": "top",
        },
    ]

    plan = _build_karaoke_plan(
        source_segments=segments,
        translated_segments=segments,
        layout_mode="romaji_top_translation_bottom",
        karaoke_granularity="syllable",
        speaker_style_mode="heuristic",
    )

    assert plan["granularity"] == "syllable"
    assert plan["speakerModeApplied"] == "heuristic"
    assert len(plan["events"]) == 2
    assert plan["events"][0]["romajiTokens"]
    assert plan["events"][0]["translationTokens"]
    assert plan["speakerSpans"]
    assert plan["sceneSegments"]


def test_lyric_alignment_report_uses_karaoke_events():
    plan = {
        "granularity": "word",
        "events": [
            {
                "index": 0,
                "start": 0.0,
                "end": 2.0,
                "romajiTokens": [
                    {"text": "fu", "start": 0.0, "end": 1.0},
                    {"text": "shigi", "start": 1.0, "end": 2.0},
                ],
                "translationTokens": [
                    {"text": "Mystery", "start": 0.0, "end": 2.0},
                ],
            }
        ],
    }

    report = _build_lyric_alignment_report(plan)

    assert report["granularity"] == "word"
    assert report["events"][0]["index"] == 0
    assert len(report["events"][0]["romajiTokens"]) == 2


def test_voice_analysis_falls_back_to_heuristic_when_advanced_is_unavailable():
    analysis, mode_applied, source = _build_voice_analysis(
        source_segments=[
            {"start": 0.0, "end": 2.0, "text": "One"},
            {"start": 1.2, "end": 2.7, "text": "Two"},
        ],
        speaker_style_mode_requested="advanced",
        diarization_available=False,
    )

    assert mode_applied == "heuristic"
    assert source == "heuristic_overlap_layout"
    assert analysis["overlapCount"] == 1
    assert analysis["speakerCount"] >= 1
    assert analysis["spans"]


def test_scene_map_groups_segments_into_timing_style_blocks():
    scene_map, source = _build_scene_map(
        segments=[
            {"start": 0.0, "end": 2.0, "text": "One", "styleLabel": "default", "speakerId": "speaker_1"},
            {"start": 2.1, "end": 4.0, "text": "Two", "styleLabel": "default", "speakerId": "speaker_1"},
            {"start": 8.5, "end": 10.0, "text": "Three!", "styleLabel": "shout", "speakerId": "speaker_2"},
        ],
        content_mode="episode",
        voice_analysis={"source": "heuristic_overlap_layout", "modeApplied": "heuristic"},
    )

    assert source == "timing_style_blocks"
    assert scene_map["sceneCount"] == 2
    assert scene_map["scenes"][0]["theme"] == "default"
    assert scene_map["scenes"][1]["theme"] == "shout"


def test_quality_profiles_use_public_release_timeouts():
    profiles = _build_quality_profiles({})

    assert profiles["safe"]["structuredTimeoutSeconds"] == 45
    assert profiles["safe"]["styleTimeoutSeconds"] == 60
    assert profiles["balanced"]["structuredTimeoutSeconds"] == 90
    assert profiles["balanced"]["styleTimeoutSeconds"] == 180
    assert profiles["max"]["structuredTimeoutSeconds"] == 150
    assert profiles["max"]["styleTimeoutSeconds"] == 300


def test_content_mode_auto_prefers_episode_when_chapters_mix_song_and_dialogue(monkeypatch):
    monkeypatch.setattr(
        "app.services.transcription_engine._probe_chapters",
        lambda _path: [
            {"title": "Abertura", "start": 0.0, "end": 90.0, "durationSeconds": 90.0},
            {"title": "Episodio", "start": 90.0, "end": 1230.0, "durationSeconds": 1140.0},
            {"title": "Encerramento", "start": 1230.0, "end": 1320.0, "durationSeconds": 90.0},
        ],
    )

    decision = _detect_content_mode(
        "auto",
        Path("episode.mkv"),
        "karaoke only when it is actually an opening or ending",
        {},
    )

    assert decision.detected == "episode"
    assert "Capítulos" in decision.reason


def test_detect_song_blocks_uses_only_chapter_music_blocks_for_episode_auto(monkeypatch):
    monkeypatch.setattr(
        "app.services.transcription_engine._probe_duration_seconds",
        lambda _path: 1320.0,
    )
    monkeypatch.setattr(
        "app.services.transcription_engine._probe_chapters",
        lambda _path: [
            {"title": "Abertura", "start": 0.0, "end": 90.0, "durationSeconds": 90.0},
            {"title": "Episodio", "start": 90.0, "end": 1230.0, "durationSeconds": 1140.0},
            {"title": "Encerramento", "start": 1230.0, "end": 1320.0, "durationSeconds": 90.0},
        ],
    )

    blocks = _detect_song_blocks(
        source_file=Path("episode.mkv"),
        requested_mode="auto",
        detected_mode="episode",
        karaoke_requested=True,
        prompt_hint="karaoke only on opening and ending",
        context_hints={},
    )

    assert len(blocks) == 2
    assert [block["type"] for block in blocks] == ["opening", "ending"]


def test_detect_song_blocks_does_not_promote_narrative_chapters_to_full_song(monkeypatch):
    monkeypatch.setattr(
        "app.services.transcription_engine._probe_duration_seconds",
        lambda _path: 1320.0,
    )
    monkeypatch.setattr(
        "app.services.transcription_engine._probe_chapters",
        lambda _path: [
            {"title": "Parte 1", "start": 0.0, "end": 660.0, "durationSeconds": 660.0},
            {"title": "Parte 2", "start": 660.0, "end": 1320.0, "durationSeconds": 660.0},
        ],
    )

    blocks = _detect_song_blocks(
        source_file=Path("episode.mkv"),
        requested_mode="auto",
        detected_mode="anime_song",
        karaoke_requested=True,
        prompt_hint="the filename mentions theme song",
        context_hints={},
    )

    assert blocks == []


def test_content_mode_auto_keeps_episode_when_prompt_mentions_opening_and_episode_without_chapters(monkeypatch):
    monkeypatch.setattr(
        "app.services.transcription_engine._probe_chapters",
        lambda _path: [],
    )

    decision = _detect_content_mode(
        "auto",
        Path("Episode_04.mkv"),
        "apply karaoke only on opening and ending",
        {"series": "Oshi no Ko", "episode": "04"},
    )

    assert decision.detected == "episode"
    assert "blocos musicais internos" in decision.reason


def test_detect_song_blocks_creates_opening_and_ending_windows_for_episode_hint_without_chapters(monkeypatch):
    monkeypatch.setattr(
        "app.services.transcription_engine._probe_duration_seconds",
        lambda _path: 1420.0,
    )
    monkeypatch.setattr(
        "app.services.transcription_engine._probe_chapters",
        lambda _path: [],
    )

    blocks = _detect_song_blocks(
        source_file=Path("Episode_04.mkv"),
        requested_mode="auto",
        detected_mode="episode",
        karaoke_requested=True,
        prompt_hint="karaoke only on opening and ending",
        context_hints={"series": "Oshi no Ko", "episode": "04"},
    )

    assert len(blocks) == 2
    assert blocks[0]["type"] == "opening"
    assert blocks[0]["start"] == 0.0
    assert blocks[0]["end"] == 95.0
    assert blocks[1]["type"] == "ending"
    assert blocks[1]["start"] == 1325.0
    assert blocks[1]["end"] == 1420.0


def test_request_schema_preserves_auto_mode_karaoke_when_requested():
    payload = JobTranscriptionRequest(
        sourceType="file_path",
        sourceValue="episode.mkv",
        task="translate",
        aiEnhancementEnabled=True,
        contentMode="auto",
        animeSongLayoutMode="romaji_top_translation_bottom",
        karaokeGranularity="syllable",
        targetLanguages=["pt-BR"],
    )

    assert payload.content_mode == "auto"
    assert payload.karaoke_granularity == "syllable"
    assert payload.anime_song_layout_mode == "romaji_top_translation_bottom"


def test_empty_translation_is_publishable_for_instrumental_block():
    assert _should_publish_empty_translation(
        source_segments=[],
        translated_segments=[],
    ) is True

    assert _should_publish_empty_translation(
        source_segments=[{"text": "lyric"}],
        translated_segments=[],
    ) is False


def test_english_reference_is_only_primary_translation_when_ai_is_disabled():
    assert _should_use_english_reference_as_primary_translation(
        ai_enabled=False,
        target_language="en",
    ) is True
    assert _should_use_english_reference_as_primary_translation(
        ai_enabled=True,
        target_language="en",
    ) is True
    assert _should_use_english_reference_as_primary_translation(
        ai_enabled=False,
        target_language="pt-BR",
    ) is False


def test_quality_is_local_non_ai_publishable_accepts_high_average_with_few_failed_segments():
    summary = {
        "averageScore": 91.13,
        "minScore": 30,
        "publishableSegments": 203,
        "reviewSegments": 39,
        "failedSegments": 10,
        "suppressedNoiseSegments": 0,
    }

    assert _quality_is_local_non_ai_publishable(summary, total_segments=252) is True


def test_quality_is_local_non_ai_publishable_rejects_when_failed_ratio_is_too_high():
    summary = {
        "averageScore": 91.13,
        "minScore": 30,
        "publishableSegments": 180,
        "reviewSegments": 40,
        "failedSegments": 20,
        "suppressedNoiseSegments": 0,
    }

    assert _quality_is_local_non_ai_publishable(summary, total_segments=240) is False


def test_retranslate_low_quality_segments_with_ollama_only_replaces_improved_items(
    monkeypatch,
):
    source_segments = [{"text": "語れない", "start": 0.0, "end": 2.0}]
    translated_segments = [{"text": "", "start": 0.0, "end": 2.0}]
    _score_translation_segments(
        source_segments=source_segments,
        translated_segments=translated_segments,
        source_language="ja",
        target_language="en",
    )

    def fake_translate(**kwargs):
        return [{"text": "I can't speak", "start": 0.0, "end": 2.0}]

    monkeypatch.setattr(
        "app.services.transcription_engine._translate_segments_with_ollama",
        fake_translate,
    )

    rescued, replacements = _retranslate_low_quality_segments_with_ollama(
        source_segments=source_segments,
        translated_segments=translated_segments,
        reference_segments=[{"text": "I can't speak", "start": 0.0, "end": 2.0}],
        source_language="ja",
        target_language="en",
        song_segment_indices=set(),
        model="qwen3-vl:30b-a3b-instruct-q4_K_M",
        prompt_hint=None,
        temperature=0.0,
        top_p=1.0,
        num_predict=128,
        chunk_chars=900,
        batch_size=1,
        timeout_seconds=60,
        content_mode="episode",
    )

    assert replacements == 1
    assert rescued[0]["text"] == "I can't speak"
    assert int(rescued[0]["_qualityScore"]) > 0


def test_release_gate_blocks_local_preset_and_soft_publish(tmp_path):
    render_preview = tmp_path / "render_preview.mp4"
    render_preview.write_text("preview", encoding="utf-8")
    video_muxed = tmp_path / "video_muxed.mkv"
    video_muxed.write_text("muxed", encoding="utf-8")
    scene_map = tmp_path / "scene_map.json"
    scene_map.write_text(
        '{"scenes":[{"theme":"default","styleLabel":"default"}]}',
        encoding="utf-8",
    )
    speaker_map = tmp_path / "speaker_map.json"
    speaker_map.write_text('{"spans":[]}', encoding="utf-8")

    gate = _build_release_gate(
        task="translate",
        content_mode="episode",
        style_source="local_preset",
        translation_statuses={
            "en": {
                "status": "published",
                "quality": {
                    "softPublished": True,
                    "failedSegments": 0,
                    "minScore": 84,
                },
            }
        },
        render_preview_path=str(render_preview),
        video_muxed_path=str(video_muxed),
        scene_map_path=str(scene_map),
        speaker_map_path=str(speaker_map),
        karaoke_plan_path=None,
        lyric_alignment_path=None,
    )

    assert gate["ready"] is False
    assert "local_preset" in gate["criticalFallbacks"]
    assert "soft_quality_gate" in gate["criticalFallbacks"]
    assert "style_source_not_ai_plan" in gate["reasons"]


def test_release_gate_blocks_invalid_scene_map_theme(tmp_path):
    render_preview = tmp_path / "render_preview.mp4"
    render_preview.write_text("preview", encoding="utf-8")
    video_muxed = tmp_path / "video_muxed.mkv"
    video_muxed.write_text("muxed", encoding="utf-8")
    scene_map = tmp_path / "scene_map.json"
    scene_map.write_text(
        '{"scenes":[{"theme":"plain subtitle text","styleLabel":"default"}]}',
        encoding="utf-8",
    )
    speaker_map = tmp_path / "speaker_map.json"
    speaker_map.write_text('{"spans":[]}', encoding="utf-8")

    gate = _build_release_gate(
        task="translate",
        content_mode="episode",
        style_source="ai_plan",
        translation_statuses={
            "en": {
                "status": "published",
                "quality": {
                    "softPublished": False,
                    "failedSegments": 0,
                    "minScore": 84,
                },
            }
        },
        render_preview_path=str(render_preview),
        video_muxed_path=str(video_muxed),
        scene_map_path=str(scene_map),
        speaker_map_path=str(speaker_map),
        karaoke_plan_path=None,
        lyric_alignment_path=None,
    )

    assert gate["ready"] is False
    assert any(reason.startswith("scene_map_invalid_theme") for reason in gate["reasons"])
    assert "invalid_scene_map_labels" in gate["criticalFallbacks"]


def test_release_gate_blocks_invalid_karaoke_style_label(tmp_path):
    render_preview = tmp_path / "render_preview.mp4"
    render_preview.write_text("preview", encoding="utf-8")
    video_muxed = tmp_path / "video_muxed.mkv"
    video_muxed.write_text("muxed", encoding="utf-8")
    scene_map = tmp_path / "scene_map.json"
    scene_map.write_text(
        '{"scenes":[{"theme":"chorus","styleLabel":"chorus"}]}',
        encoding="utf-8",
    )
    speaker_map = tmp_path / "speaker_map.json"
    speaker_map.write_text('{"spans":[]}', encoding="utf-8")
    karaoke_plan = tmp_path / "karaoke_plan.json"
    karaoke_plan.write_text(
        '{"sceneSegments":[{"label":"chorus"}],"events":[{"styleLabel":"raw lyric text"}]}',
        encoding="utf-8",
    )
    lyric_alignment = tmp_path / "lyric_alignment.json"
    lyric_alignment.write_text('{"events":[]}', encoding="utf-8")

    gate = _build_release_gate(
        task="translate",
        content_mode="anime_song",
        style_source="ai_plan",
        translation_statuses={
            "en": {
                "status": "published",
                "quality": {
                    "softPublished": False,
                    "failedSegments": 0,
                    "minScore": 84,
                },
            }
        },
        render_preview_path=str(render_preview),
        video_muxed_path=str(video_muxed),
        scene_map_path=str(scene_map),
        speaker_map_path=str(speaker_map),
        karaoke_plan_path=str(karaoke_plan),
        lyric_alignment_path=str(lyric_alignment),
    )

    assert gate["ready"] is False
    assert any(reason.startswith("karaoke_plan_invalid_style_label") for reason in gate["reasons"])
    assert "invalid_karaoke_plan_labels" in gate["criticalFallbacks"]
