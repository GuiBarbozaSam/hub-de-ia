from __future__ import annotations

from typing import Any

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator

ALLOWED_REQUESTED_OUTPUTS = ["txt", "srt", "vtt", "ass", "video_burned"]
ALLOWED_VIDEO_DELIVERY_MODES = {"standard", "video_only", "mux_subtitles", "burned_video"}
ALLOWED_AI_MODELS = [
    "qwen2.5vl:7b",
    "qwen2.5vl:32b",
    "qwen3-vl:30b-a3b-instruct-q4_K_M",
    "gemma3:4b",
    "qwen2.5:14b",
    "qwen2.5:32b",
    "qwen3.5:35b-a3b-q4_K_M",
]
ALLOWED_AI_PROVIDERS = {"ollama", "ollama_project", "remote_api"}
ALLOWED_AI_MODES = {"correction", "semantic_translation", "subtitle_styling"}
ALLOWED_ALIGNMENT_MODES = {"auto", "on", "off"}
ALLOWED_QUALITY_PROFILES = {"safe", "balanced", "max"}
ALLOWED_CONTENT_MODES = {"auto", "episode", "anime_song"}
ALLOWED_SPEAKER_STYLE_MODES = {"off", "heuristic", "advanced"}
ALLOWED_STYLE_INTENSITIES = {"subtle", "thematic", "expressive"}
ALLOWED_RENDERED_PREVIEW_MODES = {"fast", "rendered"}
ALLOWED_ANIME_SONG_LAYOUT_MODES = {"off", "romaji_top_translation_bottom"}
ALLOWED_KARAOKE_GRANULARITIES = {"off", "word", "syllable"}

DEFAULT_VISUAL_AI_MODEL = "qwen2.5vl:7b"
DEFAULT_TEXT_AI_MODEL = "qwen2.5:14b"


def _split_csv(value: str | None) -> list[str]:
    if value is None:
        return []
    return [item.strip() for item in value.split(",") if item and item.strip()]


def _normalize_requested_outputs(values: list[str]) -> list[str]:
    normalized: list[str] = []
    seen: set[str] = set()
    for raw in values:
        item = (raw or "").strip().lower()
        if item in ALLOWED_REQUESTED_OUTPUTS and item not in seen:
            seen.add(item)
            normalized.append(item)
    return normalized


def _normalize_target_languages(values: list[str]) -> list[str]:
    normalized: list[str] = []
    seen: set[str] = set()
    for raw in values:
        item = (raw or "").strip()
        if item and item not in seen:
            seen.add(item)
            normalized.append(item)
    return normalized


def _resolve_ai_model(value: str | None, ai_use_visual_context: bool) -> str:
    normalized = (value or "").strip()
    if normalized:
        return normalized
    return DEFAULT_VISUAL_AI_MODEL if ai_use_visual_context else DEFAULT_VISUAL_AI_MODEL


class SegmentResponse(BaseModel):
    id: int
    start: float
    end: float
    text: str
    avg_logprob: float | None = None
    no_speech_prob: float | None = None
    compression_ratio: float | None = None


class TranscriptionResponse(BaseModel):
    filename: str
    size_bytes: int
    model: str
    device: str
    compute_type: str
    language: str | None = None
    language_probability: float | None = None
    duration: float | None = None
    text: str
    segments: list[SegmentResponse] = Field(default_factory=list)
    hardware: dict[str, Any]


class CapabilitiesResponse(BaseModel):
    model_config = ConfigDict(populate_by_name=True, extra="ignore")

    service: str
    faster_whisper_installed: bool
    default_model: str
    device_mode: str
    compute_type_mode: str
    hardware: dict[str, Any]
    ollama: dict[str, Any] | None = None
    profiles: dict[str, Any] | None = None
    recommended_profile: str | None = Field(default=None, alias="recommendedProfile")
    voice_analysis_available: bool | None = Field(default=None, alias="voiceAnalysisAvailable")
    scene_analysis_available: bool | None = Field(default=None, alias="sceneAnalysisAvailable")
    job_timeout_minutes: int | None = Field(default=None, alias="jobTimeoutMinutes")
    structured_timeout_seconds: int | None = Field(default=None, alias="structuredTimeoutSeconds")
    style_timeout_seconds: int | None = Field(default=None, alias="styleTimeoutSeconds")
    timeout_profile_applied: str | None = Field(default=None, alias="timeoutProfileApplied")
    project_runtime: dict[str, Any] | None = Field(default=None, alias="projectRuntime")
    host_runtime: dict[str, Any] | None = Field(default=None, alias="hostRuntime")
    providers: list[dict[str, Any]] = Field(default_factory=list, alias="providers")
    installed_models_by_provider: dict[str, list[str]] = Field(default_factory=dict, alias="installedModelsByProvider")
    downloadable_models_by_provider: dict[str, list[str]] = Field(default_factory=dict, alias="downloadableModelsByProvider")
    active_model_store_path: str | None = Field(default=None, alias="activeModelStorePath")


class HealthResponse(BaseModel):
    status: str
    service: str
    version: str
    environment: str
    faster_whisper_installed: bool
    hardware: dict[str, Any]


class JobTranscriptionRequest(BaseModel):
    model_config = ConfigDict(populate_by_name=True, extra="ignore")

    source_type: str = Field(default="file_path", alias="sourceType")
    source_value: str = Field(default="", alias="sourceValue")

    model: str = "large-v3"
    task: str = "transcribe"
    language: str = "auto"
    output_format: str = Field(default="srt", alias="outputFormat")

    requested_outputs: list[str] = Field(default_factory=list, alias="requestedOutputs")
    requested_outputs_csv: str | None = Field(default=None, alias="requestedOutputsCsv")
    delivery_mode: str | None = Field(default=None, alias="deliveryMode")

    generate_subtitles: bool = Field(default=True, alias="generateSubtitles")
    burn_subtitles_into_video: bool = Field(default=False, alias="burnSubtitlesIntoVideo")
    keep_timestamps: bool = Field(default=True, alias="keepTimestamps")
    split_by_sentence: bool = Field(default=True, alias="splitBySentence")
    word_timestamps: bool = Field(default=False, alias="wordTimestamps")
    vad_filter: bool = Field(default=True, alias="vadFilter")

    device_preference: str = Field(default="auto", alias="devicePreference")
    compute_type: str = Field(default="float16", alias="computeType")
    beam_size: int = Field(default=5, alias="beamSize")
    max_subtitle_chars: int | None = Field(default=42, alias="maxSubtitleChars")
    subtitle_style: str = Field(default="default", alias="subtitleStyle")
    subtitle_visual_preset: str | None = Field(default=None, alias="subtitleVisualPreset")

    target_languages: list[str] = Field(default_factory=list, alias="targetLanguages")
    target_languages_csv: str | None = Field(default=None, alias="targetLanguagesCsv")
    video_delivery_mode: str = Field(default="standard", alias="videoDeliveryMode")

    ai_enhancement_enabled: bool = Field(default=False, alias="aiEnhancementEnabled")
    ai_provider: str = Field(default="ollama_project", alias="aiProvider")
    ai_model: str = Field(default=DEFAULT_VISUAL_AI_MODEL, alias="aiModel")
    ai_mode: str = Field(default="correction", alias="aiMode")
    ai_prompt: str | None = Field(default=None, alias="aiPrompt")
    ai_temperature: float = Field(default=0.2, alias="aiTemperature")
    ai_top_p: float = Field(default=0.9, alias="aiTopP")
    ai_max_tokens: int = Field(default=1024, alias="aiMaxTokens")
    ai_chunk_chars: int = Field(default=6000, alias="aiChunkChars")
    ai_use_visual_context: bool = Field(default=False, alias="aiUseVisualContext")
    ai_frame_sample_seconds: int = Field(default=12, alias="aiFrameSampleSeconds")
    preserve_timestamps: bool = Field(default=True, alias="preserveTimestamps")
    ai_revision_passes: int = Field(default=3, alias="aiRevisionPasses")
    use_advanced_alignment: str = Field(default="auto", alias="useAdvancedAlignment")
    enable_online_context: bool = Field(default=False, alias="enableOnlineContext")
    context_hints: dict[str, Any] = Field(default_factory=dict, alias="contextHints")
    quality_profile: str = Field(default="balanced", alias="qualityProfile")
    content_mode: str = Field(default="episode", alias="contentMode")
    speaker_style_mode: str = Field(default="heuristic", alias="speakerStyleMode")
    style_intensity: str = Field(default="thematic", alias="styleIntensity")
    rendered_preview_mode: str = Field(default="fast", alias="renderedPreviewMode")
    anime_song_layout_mode: str = Field(default="off", alias="animeSongLayoutMode")
    karaoke_granularity: str = Field(default="off", alias="karaokeGranularity")
    job_id: str | None = Field(default=None, alias="jobId")
    progress_callback_url: str | None = Field(default=None, alias="progressCallbackUrl")
    progress_callback_token: str | None = Field(default=None, alias="progressCallbackToken")

    @field_validator("requested_outputs", mode="before")
    @classmethod
    def _coerce_requested_outputs(cls, value: Any) -> list[str]:
        if value is None:
            return []
        if isinstance(value, list):
            return [str(item) for item in value]
        if isinstance(value, str):
            return _split_csv(value)
        return []

    @field_validator("target_languages", mode="before")
    @classmethod
    def _coerce_target_languages(cls, value: Any) -> list[str]:
        if value is None:
            return []
        if isinstance(value, list):
            return [str(item) for item in value]
        if isinstance(value, str):
            return _split_csv(value)
        return []

    @field_validator("context_hints", mode="before")
    @classmethod
    def _coerce_context_hints(cls, value: Any) -> dict[str, Any]:
        if value is None:
            return {}
        if isinstance(value, dict):
            return {str(key): item for key, item in value.items()}
        return {}

    @field_validator("requested_outputs", mode="after")
    @classmethod
    def _normalize_requested_outputs_field(cls, value: list[str]) -> list[str]:
        return _normalize_requested_outputs(value)

    @field_validator("target_languages", mode="after")
    @classmethod
    def _normalize_target_languages_field(cls, value: list[str]) -> list[str]:
        return _normalize_target_languages(value)

    @field_validator("task")
    @classmethod
    def _normalize_task(cls, value: str) -> str:
        normalized = (value or "transcribe").strip().lower()
        return normalized if normalized in {"transcribe", "translate"} else "transcribe"

    @field_validator("video_delivery_mode")
    @classmethod
    def _normalize_video_delivery_mode(cls, value: str) -> str:
        normalized = (value or "standard").strip().lower()
        return normalized if normalized in ALLOWED_VIDEO_DELIVERY_MODES else "standard"

    @field_validator("ai_provider")
    @classmethod
    def _normalize_ai_provider(cls, value: str) -> str:
        normalized = (value or "ollama_project").strip().lower()
        if normalized == "ollama":
            return "ollama_project"
        return normalized if normalized in ALLOWED_AI_PROVIDERS else "ollama_project"

    @field_validator("use_advanced_alignment")
    @classmethod
    def _normalize_alignment_mode(cls, value: str) -> str:
        normalized = (value or "auto").strip().lower()
        return normalized if normalized in ALLOWED_ALIGNMENT_MODES else "auto"

    @field_validator("quality_profile")
    @classmethod
    def _normalize_quality_profile(cls, value: str) -> str:
        normalized = (value or "balanced").strip().lower()
        return normalized if normalized in ALLOWED_QUALITY_PROFILES else "balanced"

    @field_validator("content_mode")
    @classmethod
    def _normalize_content_mode(cls, value: str) -> str:
        normalized = (value or "episode").strip().lower()
        return normalized if normalized in ALLOWED_CONTENT_MODES else "episode"

    @field_validator("speaker_style_mode")
    @classmethod
    def _normalize_speaker_style_mode(cls, value: str) -> str:
        normalized = (value or "heuristic").strip().lower()
        return normalized if normalized in ALLOWED_SPEAKER_STYLE_MODES else "heuristic"

    @field_validator("style_intensity")
    @classmethod
    def _normalize_style_intensity(cls, value: str) -> str:
        normalized = (value or "thematic").strip().lower()
        return normalized if normalized in ALLOWED_STYLE_INTENSITIES else "thematic"

    @field_validator("rendered_preview_mode")
    @classmethod
    def _normalize_rendered_preview_mode(cls, value: str) -> str:
        normalized = (value or "fast").strip().lower()
        return normalized if normalized in ALLOWED_RENDERED_PREVIEW_MODES else "fast"

    @field_validator("anime_song_layout_mode")
    @classmethod
    def _normalize_anime_song_layout_mode(cls, value: str) -> str:
        normalized = (value or "off").strip().lower()
        return normalized if normalized in ALLOWED_ANIME_SONG_LAYOUT_MODES else "off"

    @field_validator("karaoke_granularity")
    @classmethod
    def _normalize_karaoke_granularity(cls, value: str) -> str:
        normalized = (value or "off").strip().lower()
        return normalized if normalized in ALLOWED_KARAOKE_GRANULARITIES else "off"

    def normalized_ai_modes(self) -> list[str]:
        ordered: list[str] = []
        for raw in _split_csv(self.ai_mode):
            normalized = raw.strip().lower()
            if normalized in ALLOWED_AI_MODES and normalized not in ordered:
                ordered.append(normalized)

        if self.task == "translate" and "semantic_translation" not in ordered:
            ordered.append("semantic_translation")

        if not ordered:
            ordered.append("semantic_translation" if self.task == "translate" else "correction")

        return [
            item
            for item in ["correction", "semantic_translation", "subtitle_styling"]
            if item in ordered
        ]

    @model_validator(mode="after")
    def _normalize_request(self) -> "JobTranscriptionRequest":
        self.ai_provider = self._normalize_ai_provider(self.ai_provider)
        self.ai_model = _resolve_ai_model(self.ai_model, self.ai_use_visual_context)
        self.ai_mode = ",".join(self.normalized_ai_modes())
        self.ai_revision_passes = max(0, min(10, int(self.ai_revision_passes)))
        self.content_mode = self._normalize_content_mode(self.content_mode)
        self.speaker_style_mode = self._normalize_speaker_style_mode(self.speaker_style_mode)
        self.style_intensity = self._normalize_style_intensity(self.style_intensity)
        self.rendered_preview_mode = self._normalize_rendered_preview_mode(self.rendered_preview_mode)
        self.anime_song_layout_mode = self._normalize_anime_song_layout_mode(self.anime_song_layout_mode)
        self.karaoke_granularity = self._normalize_karaoke_granularity(self.karaoke_granularity)

        outputs = self.normalized_requested_outputs()
        if "subtitle_styling" in self.normalized_ai_modes() and "ass" not in outputs:
            outputs.append("ass")
        self.requested_outputs = _normalize_requested_outputs(outputs)

        self.target_languages = self.normalized_target_languages()
        if self.task != "translate":
            self.target_languages = []
        elif len(self.target_languages) > 1 and self.video_delivery_mode == "burned_video":
            self.video_delivery_mode = "mux_subtitles"
            self.burn_subtitles_into_video = False

        if self.content_mode == "anime_song" and self.anime_song_layout_mode == "off":
            self.anime_song_layout_mode = "romaji_top_translation_bottom"
        elif self.content_mode == "auto":
            if self.karaoke_granularity != "off" and self.anime_song_layout_mode == "off":
                self.anime_song_layout_mode = "romaji_top_translation_bottom"
            elif self.karaoke_granularity == "off":
                self.anime_song_layout_mode = "off"
        elif self.content_mode != "anime_song":
            self.anime_song_layout_mode = "off"

        if self.content_mode == "anime_song" and self.karaoke_granularity == "off":
            self.karaoke_granularity = "syllable"
        elif self.content_mode == "episode":
            self.karaoke_granularity = "off"

        return self

    def normalized_requested_outputs(self) -> list[str]:
        direct = _normalize_requested_outputs(self.requested_outputs)
        csv_values = _normalize_requested_outputs(_split_csv(self.requested_outputs_csv))

        merged = direct or csv_values
        if not merged:
            output_format = (self.output_format or "").strip().lower()
            if output_format == "all":
                merged = ["txt", "srt", "vtt"]
            elif output_format in {"video_only", "video_burned"}:
                merged = ["video_burned"]
            elif "+" in output_format:
                merged = _normalize_requested_outputs(output_format.split("+"))
            elif output_format in {"txt", "srt", "vtt", "ass"}:
                merged = [output_format]
            else:
                merged = ["srt"]

        if "subtitle_styling" in self.normalized_ai_modes() and "ass" not in merged:
            merged.append("ass")

        return _normalize_requested_outputs(merged)

    def normalized_target_languages(self) -> list[str]:
        direct = _normalize_target_languages(self.target_languages)
        csv_values = _normalize_target_languages(_split_csv(self.target_languages_csv))
        return direct or csv_values

    def effective_subtitle_preset(self) -> str:
        return (self.subtitle_visual_preset or self.subtitle_style or "default").strip() or "default"


class JobTranscriptionResponse(BaseModel):
    model_config = ConfigDict(populate_by_name=True, extra="ignore")

    status: str = "error"
    text: str | None = None
    srt: str | None = None
    vtt: str | None = None

    ass_path: str | None = Field(default=None, alias="assPath")
    video_output_path: str | None = Field(default=None, alias="videoOutputPath")
    video_muxed_path: str | None = Field(default=None, alias="videoMuxedPath")
    translation_manifest_path: str | None = Field(default=None, alias="translationManifestPath")
    diagnostics_path: str | None = Field(default=None, alias="diagnosticsPath")
    enhanced_dir_path: str | None = Field(default=None, alias="enhancedDirPath")
    output_dir_path: str | None = Field(default=None, alias="outputDirPath")

    warnings: list[str] = Field(default_factory=list)
    diagnostics: list[dict[str, Any]] = Field(default_factory=list)
    style_source: str | None = Field(default=None, alias="styleSource")
    current_stage: str | None = Field(default=None, alias="currentStage")
    current_pass: int | None = Field(default=None, alias="currentPass")
    total_passes: int | None = Field(default=None, alias="totalPasses")
    quality_summary: dict[str, Any] | None = Field(default=None, alias="qualitySummary")
    translation_statuses: dict[str, Any] | None = Field(default=None, alias="translationStatuses")
    capability_profile: dict[str, Any] | None = Field(default=None, alias="capabilityProfile")
    quality_report_path: str | None = Field(default=None, alias="qualityReportPath")
    style_map_path: str | None = Field(default=None, alias="styleMapPath")
    alignment_report_path: str | None = Field(default=None, alias="alignmentReportPath")
    render_preview_path: str | None = Field(default=None, alias="renderPreviewPath")
    karaoke_plan_path: str | None = Field(default=None, alias="karaokePlanPath")
    scene_map_path: str | None = Field(default=None, alias="sceneMapPath")
    speaker_map_path: str | None = Field(default=None, alias="speakerMapPath")
    lyric_alignment_path: str | None = Field(default=None, alias="lyricAlignmentPath")
    detected_content_type: str | None = Field(default=None, alias="detectedContentType")
    content_detection_confidence: float | None = Field(default=None, alias="contentDetectionConfidence")
    speaker_mode_applied: str | None = Field(default=None, alias="speakerModeApplied")
    karaoke_mode_applied: str | None = Field(default=None, alias="karaokeModeApplied")
    voice_analysis_source: str | None = Field(default=None, alias="voiceAnalysisSource")
    scene_analysis_source: str | None = Field(default=None, alias="sceneAnalysisSource")
    preview_mode_applied: str | None = Field(default=None, alias="previewModeApplied")
    planner_model_used: str | None = Field(default=None, alias="plannerModelUsed")
    review_model_used: str | None = Field(default=None, alias="reviewModelUsed")
    timeout_profile_applied: str | None = Field(default=None, alias="timeoutProfileApplied")
    requested_ai_provider: str | None = Field(default=None, alias="requestedAiProvider")
    requested_ai_model: str | None = Field(default=None, alias="requestedAiModel")
    effective_ai_provider: str | None = Field(default=None, alias="effectiveAiProvider")
    effective_ai_model: str | None = Field(default=None, alias="effectiveAiModel")
    runtime_target: str | None = Field(default=None, alias="runtimeTarget")
    model_installed_at_submission: bool | None = Field(default=None, alias="modelInstalledAtSubmission")
    source_duration_seconds: float | None = Field(default=None, alias="sourceDurationSeconds")
    output_duration_seconds: float | None = Field(default=None, alias="outputDurationSeconds")
    musical_segment_durations: list[dict[str, Any]] = Field(default_factory=list, alias="musicalSegmentDurations")
    fallbacks: list[dict[str, Any]] = Field(default_factory=list, alias="fallbacks")
    error: str | None = None
    language_detected: str | None = Field(default=None, alias="languageDetected")
    duration_seconds: float | None = Field(default=None, alias="durationSeconds")
