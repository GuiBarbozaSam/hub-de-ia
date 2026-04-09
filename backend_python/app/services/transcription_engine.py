import base64
import contextvars
import ctypes
import json
import logging
import math
import os
import platform
import re
import shutil
import subprocess
import tempfile
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path
from typing import Any, Callable
from uuid import uuid4

from app.core.config import get_settings
from app.core.exceptions import DependencyMissingError

logger = logging.getLogger(__name__)
REPO_ROOT = Path(__file__).resolve().parents[3]
OLLAMA_MODEL_CATALOG_PATH = REPO_ROOT / "infra" / "ollama" / "model-catalog.json"

VIDEO_EXTENSIONS = {".mp4", ".mov", ".mkv", ".avi", ".webm", ".m4v"}
AUDIO_EXTENSIONS = {".mp3", ".wav", ".m4a", ".aac", ".flac", ".ogg", ".wma"}
DEFAULT_OLLAMA_TIMEOUT_SECONDS = 240
DEFAULT_STRUCTURED_TIMEOUT_SECONDS = 90
DEFAULT_STYLE_TIMEOUT_SECONDS = 180
OLLAMA_RAW_EXCERPT_LIMIT = 1400
ALLOWED_AI_MODELS = {
    "gemma3:4b",
    "qwen2.5:14b",
    "qwen2.5vl:7b",
    "qwen2.5vl:32b",
    "qwen3.5:35b-a3b-q4_K_M",
    "qwen3-vl:30b-a3b-instruct-q4_K_M",
    "qwen2.5:32b",
}
ALLOWED_AI_MODES = {"correction", "semantic_translation", "subtitle_styling"}
DEFAULT_TEXT_AI_MODEL = "qwen2.5:14b"
DEFAULT_VISUAL_AI_MODEL = "qwen2.5vl:7b"
ALLOWED_ALIGNMENT_MODES = {"auto", "on", "off"}
ALLOWED_QUALITY_PROFILES = {"safe", "balanced", "max"}
ALLOWED_CONTENT_MODES = {"auto", "episode", "anime_song"}
ALLOWED_SPEAKER_STYLE_MODES = {"off", "heuristic", "advanced"}
ALLOWED_STYLE_INTENSITIES = {"subtle", "thematic", "expressive"}
ALLOWED_RENDERED_PREVIEW_MODES = {"fast", "rendered"}
ALLOWED_ANIME_SONG_LAYOUT_MODES = {"off", "romaji_top_translation_bottom"}
ALLOWED_KARAOKE_GRANULARITIES = {"off", "word", "syllable"}
AI_SEGMENT_BATCH_SIZE = 2
AI_CONTEXT_WINDOW = 1
QUALITY_PUBLISH_THRESHOLD = 80
QUALITY_REVIEW_THRESHOLD = 60
DECORATIVE_TEXT_PATTERN = re.compile(
    "[\u2600-\u27BF\U0001F300-\U0001FAFF\U0001F1E6-\U0001F1FF]+",
    flags=re.UNICODE,
)
SUSPICIOUS_NOISE_PATTERN = re.compile(
    r"(instagram|twitter|facebook|subscribe|follow|sound\s*hodori|www\.|https?://|@\w+|\btrack\b|\bkaraoke\b)",
    flags=re.IGNORECASE,
)


@dataclass(slots=True)
class OllamaGenerateResult:
    text: str
    source_field: str
    raw_excerpt: str | None = None
    elapsed_ms: int | None = None
    status_code: int | None = None


@dataclass(slots=True)
class SegmentQualityScore:
    index: int
    score: int
    reasons: list[str]


@dataclass(slots=True)
class ContentModeDecision:
    requested: str
    detected: str
    confidence: float
    reason: str


_UNSET = object()
_MODEL_DOWNLOADS_LOCK = threading.Lock()
_MODEL_DOWNLOADS: dict[str, dict[str, Any]] = {}
_CAPABILITIES_CACHE_LOCK = threading.Lock()
_CAPABILITIES_CACHE: dict[str, Any] | None = None
_CAPABILITIES_CACHE_AT = 0.0
_CAPABILITIES_CACHE_TTL_SECONDS = 15.0
_AI_RUNTIME_CONTEXT: contextvars.ContextVar[dict[str, Any] | None] = contextvars.ContextVar(
    "ai_runtime_context",
    default=None,
)


class OllamaCallError(RuntimeError):
    def __init__(
        self,
        message: str,
        *,
        model: str,
        status_code: int | None = None,
        raw_excerpt: str | None = None,
        response_field: str | None = None,
        elapsed_ms: int | None = None,
    ) -> None:
        super().__init__(message)
        self.model = model
        self.status_code = status_code
        self.raw_excerpt = raw_excerpt
        self.response_field = response_field
        self.elapsed_ms = elapsed_ms


# -----------------------------------------------------------------------------
# Imports / runtime capabilities
# -----------------------------------------------------------------------------

def _import_faster_whisper():
    try:
        from faster_whisper import WhisperModel  # type: ignore
        return WhisperModel
    except ModuleNotFoundError as exc:
        raise DependencyMissingError(
            "A dependência 'faster-whisper' não está instalada no ambiente atual."
        ) from exc



def _import_ctranslate2():
    try:
        import ctranslate2  # type: ignore
        return ctranslate2
    except Exception:
        return None


def _import_argostranslate_translate():
    try:
        import argostranslate.translate  # type: ignore
        return argostranslate.translate
    except Exception:
        return None


def _import_pykakasi():
    try:
        from pykakasi import kakasi  # type: ignore
        return kakasi
    except Exception:
        return None


def _argos_language_candidates(code: str) -> list[str]:
    normalized = _normalize_lang(code)
    mapping = {
        "pt-br": ["pt", "pt_br", "pt-BR"],
        "en": ["en"],
        "es": ["es"],
        "fr": ["fr"],
        "de": ["de"],
        "it": ["it"],
        "ja": ["ja", "jp"],
        "ko": ["ko"],
        "zh-cn": ["zh", "zh_cn", "zh-CN"],
        "ru": ["ru"],
        "ar": ["ar"],
        "hi": ["hi"],
    }
    return mapping.get(normalized, [normalized])


def _resolve_argos_translation(from_code: str, to_code: str):
    argos_translate = _import_argostranslate_translate()
    if argos_translate is None:
        return None

    from_candidates = _argos_language_candidates(from_code)
    to_candidates = _argos_language_candidates(to_code)

    installed_languages = argos_translate.get_installed_languages()
    for installed_from in installed_languages:
        if installed_from.code not in from_candidates:
            continue
        for installed_to in installed_languages:
            if installed_to.code not in to_candidates:
                continue
            translation = installed_from.get_translation(installed_to)
            if translation is not None:
                return translation
    return None


def _translate_segments_with_argos(
    *,
    segments: list[dict[str, Any]],
    source_language: str,
    target_language: str,
) -> list[dict[str, Any]] | None:
    translation = _resolve_argos_translation(source_language, target_language)
    if translation is None:
        return None

    translated: list[dict[str, Any]] = []
    for segment in segments:
        clone = dict(segment)
        text_value = _segment_text(segment)
        translated_text = translation.translate(text_value) if text_value else text_value
        clone["text"] = (translated_text or "").strip()
        translated.append(clone)
    return translated



def _normalize_ai_provider(value: str | None) -> str:
    normalized = (value or "ollama_project").strip().lower()
    if normalized == "ollama":
        return "ollama_project"
    if normalized in {"ollama_project", "remote_api"}:
        return normalized
    return "ollama_project"


def _resolve_ai_model(model_name: str | None, ai_use_visual_context: bool) -> str:
    normalized = (model_name or "").strip()
    if normalized:
        return normalized
    return DEFAULT_VISUAL_AI_MODEL if ai_use_visual_context else DEFAULT_VISUAL_AI_MODEL


def _normalize_ai_modes(values: list[str], task: str) -> list[str]:
    ordered: list[str] = []
    for raw in values:
        normalized = (raw or "").strip().lower()
        if normalized in ALLOWED_AI_MODES and normalized not in ordered:
            ordered.append(normalized)

    if task == "translate" and "semantic_translation" not in ordered:
        ordered.append("semantic_translation")

    if not ordered:
        ordered.append("semantic_translation" if task == "translate" else "correction")

    return [item for item in ["correction", "semantic_translation", "subtitle_styling"] if item in ordered]



def is_faster_whisper_installed() -> bool:
    try:
        _import_faster_whisper()
        return True
    except DependencyMissingError:
        return False


def _read_total_memory_bytes() -> int | None:
    try:
        import psutil  # type: ignore

        return int(psutil.virtual_memory().total)
    except Exception:
        pass

    if os.name == "nt":
        try:
            class MEMORYSTATUSEX(ctypes.Structure):
                _fields_ = [
                    ("dwLength", ctypes.c_ulong),
                    ("dwMemoryLoad", ctypes.c_ulong),
                    ("ullTotalPhys", ctypes.c_ulonglong),
                    ("ullAvailPhys", ctypes.c_ulonglong),
                    ("ullTotalPageFile", ctypes.c_ulonglong),
                    ("ullAvailPageFile", ctypes.c_ulonglong),
                    ("ullTotalVirtual", ctypes.c_ulonglong),
                    ("ullAvailVirtual", ctypes.c_ulonglong),
                    ("sullAvailExtendedVirtual", ctypes.c_ulonglong),
                ]

            status = MEMORYSTATUSEX()
            status.dwLength = ctypes.sizeof(MEMORYSTATUSEX)
            ctypes.windll.kernel32.GlobalMemoryStatusEx(ctypes.byref(status))
            return int(status.ullTotalPhys)
        except Exception:
            return None

    return None


def _read_available_memory_bytes() -> int | None:
    try:
        import psutil  # type: ignore

        return int(psutil.virtual_memory().available)
    except Exception:
        return None


def _read_cpu_name() -> str:
    if os.name == "nt":
        try:
            result = _run_command(["wmic", "cpu", "get", "Name", "/value"], timeout=15)
            if result.returncode == 0:
                for line in (result.stdout or "").splitlines():
                    if line.strip().startswith("Name="):
                        return line.split("=", 1)[1].strip()
        except Exception:
            pass

    return platform.processor() or platform.machine() or "unknown"


def _detect_gpu_inventory() -> list[dict[str, Any]]:
    gpus: list[dict[str, Any]] = []

    try:
        import torch  # type: ignore

        if torch.cuda.is_available():
            for index in range(torch.cuda.device_count()):
                props = torch.cuda.get_device_properties(index)
                total_memory = getattr(props, "total_memory", None)
                gpus.append(
                    {
                        "index": index,
                        "name": getattr(props, "name", f"GPU {index}"),
                        "vramTotalBytes": int(total_memory) if total_memory is not None else None,
                    }
                )
    except Exception:
        pass

    if gpus:
        return gpus

    try:
        result = _run_command(
            [
                "nvidia-smi",
                "--query-gpu=name,memory.total,memory.free",
                "--format=csv,noheader,nounits",
            ],
            timeout=15,
        )
        if result.returncode == 0:
            for index, line in enumerate((result.stdout or "").splitlines()):
                parts = [item.strip() for item in line.split(",")]
                if len(parts) >= 3:
                    gpus.append(
                        {
                            "index": index,
                            "name": parts[0],
                            "vramTotalBytes": int(float(parts[1]) * 1024 * 1024),
                            "vramAvailableBytes": int(float(parts[2]) * 1024 * 1024),
                        }
                    )
    except Exception:
        pass

    return gpus


def _recommended_quality_profile(hardware: dict[str, Any]) -> str:
    total_ram = int(hardware.get("ramTotalBytes") or 0)
    logical_cores = int(hardware.get("logicalCores") or 0)
    gpus = hardware.get("gpus") or []

    if gpus and total_ram >= 24 * 1024**3:
        return "max"
    if total_ram >= 12 * 1024**3 or logical_cores >= 8:
        return "balanced"
    return "safe"


@lru_cache(maxsize=1)
def _load_ollama_model_catalog() -> dict[str, Any]:
    if not OLLAMA_MODEL_CATALOG_PATH.exists():
        return {}

    try:
        return json.loads(OLLAMA_MODEL_CATALOG_PATH.read_text(encoding="utf-8"))
    except Exception:
        logger.warning("Falha ao ler o catálogo de modelos do Ollama.", exc_info=True)
        return {}


def _project_ollama_base_url() -> str:
    settings = get_settings()
    return str(_get_value(settings, ["ollama_base_url"], os.getenv("OLLAMA_BASE_URL", "http://127.0.0.1:11435"))).rstrip("/")


def _host_ollama_base_url() -> str:
    settings = get_settings()
    return str(_get_value(settings, ["ollama_host_discovery_url"], os.getenv("OLLAMA_HOST_DISCOVERY_URL", "http://127.0.0.1:11434"))).rstrip("/")


def _list_ollama_models(
    base_url: str | None = None,
    *,
    timeout_seconds: int = 3,
) -> tuple[str, ...]:
    try:
        runtime_base_url = (base_url or _project_ollama_base_url()).rstrip("/")
        response = _request_json_simple(f"{runtime_base_url}/api/tags", timeout=timeout_seconds)
        models = response.get("models")
        if not isinstance(models, list):
            return ()

        names: list[str] = []
        for item in models:
            if not isinstance(item, dict):
                continue
            name = str(item.get("name") or "").strip()
            if name:
                names.append(name)
        return tuple(_ordered_unique(names))
    except Exception:
        return ()


def _request_json_simple(url: str, *, timeout: int = 10) -> dict[str, Any]:
    request = urllib.request.Request(url, headers={"Accept": "application/json"})
    with urllib.request.urlopen(request, timeout=timeout) as response:
        raw = response.read().decode("utf-8", errors="replace")
    decoded = json.loads(raw or "{}")
    return decoded if isinstance(decoded, dict) else {}


def _catalog_multimodal_models(catalog: dict[str, Any]) -> list[str]:
    ordered: list[str] = []
    profiles = catalog.get("profiles") or {}
    for profile_name in ("safe", "balanced", "max"):
        profile = profiles.get(profile_name) or {}
        for key in ("visualModel", "textModel"):
            value = str(profile.get(key) or "").strip()
            if not value:
                continue
            if "vl" in value.lower() or "vision" in value.lower() or value.lower().startswith("gemma3"):
                if value not in ordered:
                    ordered.append(value)

    for value in catalog.get("compatibilityModels") or []:
        model = str(value or "").strip()
        if not model:
            continue
        if model not in ordered:
            ordered.append(model)
    return ordered


def _is_user_selectable_multimodal_model(model: str) -> bool:
    normalized = str(model or "").strip().lower()
    if not normalized:
        return False
    if normalized.startswith("gemma3"):
        return False
    return "vl" in normalized or "vision" in normalized


def _catalog_user_selectable_multimodal_models(catalog: dict[str, Any]) -> list[str]:
    return [
        model
        for model in _catalog_multimodal_models(catalog)
        if _is_user_selectable_multimodal_model(model)
    ]


def _build_ollama_runtime_capabilities(
    *,
    runtime_id: str,
    label: str,
    base_url: str,
    model_store_path: str | None = None,
    request_timeout_seconds: int = 3,
) -> dict[str, Any]:
    catalog = _load_ollama_model_catalog()
    installed_models = list(_list_ollama_models(base_url, timeout_seconds=request_timeout_seconds))
    installed_lookup = {item.lower(): item for item in installed_models}
    selectable_multimodal = _catalog_user_selectable_multimodal_models(catalog)
    available = bool(installed_models)
    profiles = catalog.get("profiles") or {}
    downloadable_models = [
        model
        for model in selectable_multimodal
        if model.lower() not in installed_lookup
    ]

    return {
        "id": runtime_id,
        "label": label,
        "available": available,
        "baseUrl": base_url,
        "minimumVersion": catalog.get("minimumOllamaVersion") or "0.7.0",
        "installedModels": installed_models,
        "downloadableModels": downloadable_models,
        "configuredModels": profiles,
        "compatibilityModels": catalog.get("compatibilityModels") or [],
        "multimodalModels": selectable_multimodal,
        "defaultTextModel": installed_lookup.get(DEFAULT_TEXT_AI_MODEL.lower(), DEFAULT_TEXT_AI_MODEL),
        "defaultVisualModel": installed_lookup.get(DEFAULT_VISUAL_AI_MODEL.lower(), DEFAULT_VISUAL_AI_MODEL),
        "modelStorePath": model_store_path,
    }


def _build_remote_api_capabilities() -> dict[str, Any]:
    settings = get_settings()
    configured_models = [
        model
        for model in settings.remote_api_models_list
        if _is_user_selectable_multimodal_model(model)
    ]
    api_key = str(_get_value(settings, ["remote_api_api_key"], "") or "").strip()
    base_url = str(_get_value(settings, ["remote_api_base_url"], "") or "").strip().rstrip("/")
    available = bool(_get_value(settings, ["remote_api_enabled"], False)) and bool(base_url) and bool(api_key) and "change_me" not in api_key.lower()

    return {
        "id": "remote_api",
        "label": "Remote API",
        "available": available,
        "baseUrl": base_url,
        "installedModels": configured_models if available else [],
        "downloadableModels": [],
        "multimodalModels": configured_models,
        "defaultVisualModel": configured_models[0] if configured_models else None,
    }


def _clone_capabilities_document(value: dict[str, Any]) -> dict[str, Any]:
    return json.loads(json.dumps(value))


def _invalidate_capabilities_cache() -> None:
    global _CAPABILITIES_CACHE, _CAPABILITIES_CACHE_AT
    with _CAPABILITIES_CACHE_LOCK:
        _CAPABILITIES_CACHE = None
        _CAPABILITIES_CACHE_AT = 0.0


def _update_download_status(download_id: str, **values: Any) -> None:
    with _MODEL_DOWNLOADS_LOCK:
        current = dict(_MODEL_DOWNLOADS.get(download_id) or {})
        current.update(values)
        _MODEL_DOWNLOADS[download_id] = current


def _download_model_worker(download_id: str, model: str) -> None:
    started_at = time.time()
    _update_download_status(
        download_id,
        status="downloading",
        progress=5,
        startedAtUtc=time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(started_at)),
    )
    try:
        request = urllib.request.Request(
            f"{_project_ollama_base_url()}/api/pull",
            data=json.dumps({"name": model, "stream": True}).encode("utf-8"),
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        last_status = "downloading"
        with urllib.request.urlopen(request, timeout=60 * 60 * 8) as response:
            while True:
                line = response.readline()
                if not line:
                    break
                try:
                    payload = json.loads(line.decode("utf-8", errors="replace"))
                except Exception:
                    continue
                status_text = str(payload.get("status") or last_status).strip() or last_status
                completed = payload.get("completed")
                total = payload.get("total")
                progress = None
                if isinstance(completed, (int, float)) and isinstance(total, (int, float)) and total:
                    progress = max(1, min(99, int((float(completed) / float(total)) * 100)))
                _update_download_status(
                    download_id,
                    status=status_text,
                    progress=progress if progress is not None else _MODEL_DOWNLOADS.get(download_id, {}).get("progress", 5),
                    detail=status_text,
                )
                last_status = status_text

        installed_models = _list_ollama_models(_project_ollama_base_url())
        if model.lower() not in {item.lower() for item in installed_models}:
            raise RuntimeError("Pull concluído, mas o modelo não apareceu no runtime do projeto.")

        _update_download_status(
            download_id,
            status="completed",
            progress=100,
            finishedAtUtc=time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            detail="Modelo instalado com sucesso no runtime do projeto.",
        )
        _invalidate_capabilities_cache()
    except Exception as exc:
        _update_download_status(
            download_id,
            status="error",
            progress=100,
            finishedAtUtc=time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            detail=str(exc),
            error=str(exc),
        )


def start_model_download(provider: str, model: str) -> dict[str, Any]:
    normalized_provider = _normalize_ai_provider(provider)
    if normalized_provider != "ollama_project":
        raise ValueError("Somente o runtime do projeto suporta download direto neste fluxo.")

    requested_model = str(model or "").strip()
    if not requested_model:
        raise ValueError("Modelo é obrigatório para download.")

    capabilities = get_capabilities()
    downloadable = set((capabilities.get("downloadableModelsByProvider") or {}).get("ollama_project") or [])
    installed = set((capabilities.get("installedModelsByProvider") or {}).get("ollama_project") or [])
    if requested_model in installed:
        return {
            "id": f"model-{uuid4().hex}",
            "provider": normalized_provider,
            "model": requested_model,
            "status": "completed",
            "progress": 100,
            "detail": "Modelo já está instalado no runtime do projeto.",
        }
    if requested_model not in downloadable:
        raise ValueError("Modelo não está disponível para download neste runtime.")

    download_id = f"model-{uuid4().hex}"
    _update_download_status(
        download_id,
        id=download_id,
        provider=normalized_provider,
        model=requested_model,
        status="queued",
        progress=0,
        detail="Download enfileirado.",
    )
    worker = threading.Thread(
        target=_download_model_worker,
        args=(download_id, requested_model),
        daemon=True,
        name=f"ollama-pull-{requested_model}",
    )
    worker.start()
    return dict(_MODEL_DOWNLOADS[download_id])


def get_model_download_status(download_id: str) -> dict[str, Any] | None:
    with _MODEL_DOWNLOADS_LOCK:
        current = _MODEL_DOWNLOADS.get(download_id)
        return dict(current) if current else None


def _build_quality_profiles(hardware: dict[str, Any]) -> dict[str, Any]:
    advanced_available = bool(hardware.get("advancedAlignmentAvailable"))
    syllable_supported = _import_pykakasi() is not None
    catalog = (_load_ollama_model_catalog().get("profiles") or {})
    safe_models = catalog.get("safe") or {}
    balanced_models = catalog.get("balanced") or {}
    max_models = catalog.get("max") or {}
    return {
        "safe": {
            "aiRevisionPasses": 1,
            "useAdvancedAlignment": "off",
            "aiUseVisualContext": False,
            "aiChunkChars": 900,
            "aiBatchSize": 1,
            "aiMaxTokens": 128,
            "structuredTimeoutSeconds": 45,
            "styleTimeoutSeconds": 60,
            "textModel": str(safe_models.get("textModel") or "gemma3:4b"),
            "visualModel": str(safe_models.get("visualModel") or "gemma3:4b"),
            "maxSupportedKaraokeGranularity": "word",
        },
        "balanced": {
            "aiRevisionPasses": 3,
            "useAdvancedAlignment": "auto" if advanced_available else "off",
            "aiUseVisualContext": False,
            "aiChunkChars": 900,
            "aiBatchSize": 1,
            "aiMaxTokens": 160,
            "structuredTimeoutSeconds": 90,
            "styleTimeoutSeconds": 180,
            "textModel": str(balanced_models.get("textModel") or DEFAULT_TEXT_AI_MODEL),
            "visualModel": str(balanced_models.get("visualModel") or DEFAULT_VISUAL_AI_MODEL),
            "maxSupportedKaraokeGranularity": "syllable" if syllable_supported else "word",
        },
        "max": {
            "aiRevisionPasses": 5,
            "useAdvancedAlignment": "auto" if advanced_available else "off",
            "aiUseVisualContext": True,
            "aiChunkChars": 1000,
            "aiBatchSize": 2,
            "aiMaxTokens": 224,
            "structuredTimeoutSeconds": 150,
            "styleTimeoutSeconds": 300,
            "textModel": str(max_models.get("textModel") or "qwen2.5:32b"),
            "visualModel": str(max_models.get("visualModel") or "qwen2.5vl:32b"),
            "maxSupportedKaraokeGranularity": "syllable" if syllable_supported else "word",
        },
    }



def detect_hardware() -> dict[str, Any]:
    hardware: dict[str, Any] = {
        "device": "cpu",
        "cuda_available": False,
        "cuda_device_count": 0,
        "provider": "fallback",
        "supported_compute_types": ["int8", "float32"],
    }

    ctranslate2 = _import_ctranslate2()
    if ctranslate2 is not None:
        try:
            cuda_count = int(ctranslate2.get_cuda_device_count())
            hardware["provider"] = "ctranslate2"
            hardware["cuda_device_count"] = cuda_count
            hardware["cuda_available"] = cuda_count > 0
            hardware["device"] = "cuda" if cuda_count > 0 else "cpu"
            try:
                hardware["supported_compute_types"] = sorted(
                    ctranslate2.get_supported_compute_types(hardware["device"])
                )
            except Exception:
                pass
        except Exception:
            logger.warning("Falha ao detectar hardware via ctranslate2.", exc_info=True)

    if hardware["provider"] == "fallback":
        try:
            import torch  # type: ignore

            cuda_available = bool(torch.cuda.is_available())
            cuda_count = int(torch.cuda.device_count()) if cuda_available else 0
            hardware["provider"] = "torch"
            hardware["cuda_available"] = cuda_available
            hardware["cuda_device_count"] = cuda_count
            hardware["device"] = "cuda" if cuda_available else "cpu"
            hardware["supported_compute_types"] = (
                ["float16", "int8_float16", "float32"] if cuda_available else ["int8", "float32"]
            )
        except Exception:
            logger.info("Torch não disponível; seguindo com detecção fallback.")

    hardware["cpuName"] = _read_cpu_name()
    hardware["logicalCores"] = os.cpu_count() or 0
    hardware["physicalCores"] = None
    try:
        import psutil  # type: ignore

        hardware["physicalCores"] = psutil.cpu_count(logical=False)
    except Exception:
        pass
    hardware["ramTotalBytes"] = _read_total_memory_bytes()
    hardware["ramAvailableBytes"] = _read_available_memory_bytes()
    hardware["gpus"] = _detect_gpu_inventory()
    hardware["advancedAlignmentAvailable"] = False
    hardware["diarizationAvailable"] = False
    hardware["voiceAnalysisAvailable"] = True
    hardware["sceneAnalysisAvailable"] = True
    hardware["maxSupportedKaraokeGranularity"] = "syllable" if _import_pykakasi() is not None else "word"
    try:
        import whisperx  # type: ignore

        hardware["advancedAlignmentAvailable"] = whisperx is not None
    except Exception:
        hardware["advancedAlignmentAvailable"] = False

    return hardware



def _resolve_device(device_preference: str | None, hardware: dict[str, Any]) -> tuple[str, int]:
    preference = (device_preference or "auto").strip().lower()
    if preference == "auto":
        return ("cuda", 0) if hardware.get("cuda_available") else ("cpu", 0)
    if preference == "cpu":
        return "cpu", 0
    if preference == "cuda":
        return "cuda", 0
    if preference.startswith("gpu:"):
        try:
            return "cuda", int(preference.split(":", 1)[1])
        except Exception:
            return "cuda", 0
    return ("cuda", 0) if hardware.get("cuda_available") else ("cpu", 0)



def _resolve_compute_type(preference: str | None, device: str, hardware: dict[str, Any]) -> str:
    supported = set(hardware.get("supported_compute_types") or [])
    normalized = (preference or "auto").strip().lower()
    if normalized and normalized != "auto":
        return normalized
    if device == "cuda":
        if "float16" in supported:
            return "float16"
        if "int8_float16" in supported:
            return "int8_float16"
        return "float32"
    if "int8" in supported:
        return "int8"
    return "float32"


@lru_cache(maxsize=16)
def _get_model(
    model_name: str,
    device: str,
    device_index: int,
    compute_type: str,
    cpu_threads: int,
    num_workers: int,
):
    settings = get_settings()
    models_dir = _path_attr(settings, "models_dir", "models")
    models_dir.mkdir(parents=True, exist_ok=True)

    WhisperModel = _import_faster_whisper()
    logger.info(
        "Carregando WhisperModel | model=%s | device=%s | device_index=%s | compute_type=%s",
        model_name,
        device,
        device_index,
        compute_type,
    )
    return WhisperModel(
        model_name,
        device=device,
        device_index=device_index,
        compute_type=compute_type,
        cpu_threads=cpu_threads,
        num_workers=num_workers,
        download_root=str(models_dir),
    )



def get_capabilities() -> dict[str, Any]:
    global _CAPABILITIES_CACHE, _CAPABILITIES_CACHE_AT
    now = time.time()
    with _CAPABILITIES_CACHE_LOCK:
        if _CAPABILITIES_CACHE is not None and (now - _CAPABILITIES_CACHE_AT) <= _CAPABILITIES_CACHE_TTL_SECONDS:
            return _clone_capabilities_document(_CAPABILITIES_CACHE)

    settings = get_settings()
    hardware = detect_hardware()
    profiles = _build_quality_profiles(hardware)
    project_runtime = _build_ollama_runtime_capabilities(
        runtime_id="ollama_project",
        label="Ollama do projeto",
        base_url=_project_ollama_base_url(),
        model_store_path=str(settings.ollama_model_store_dir),
        request_timeout_seconds=2,
    )
    host_runtime = _build_ollama_runtime_capabilities(
        runtime_id="ollama_host",
        label="Ollama do host",
        base_url=_host_ollama_base_url(),
        model_store_path=None,
        request_timeout_seconds=1,
    )
    remote_provider = _build_remote_api_capabilities()
    recommended_profile = _recommended_quality_profile(hardware)
    selected_profile = profiles.get(recommended_profile) or {}
    providers = [
        {
            "id": "ollama_project",
            "label": "Ollama do projeto",
            "type": "ollama",
            "available": bool(project_runtime.get("available")),
            "multimodalModels": project_runtime.get("multimodalModels") or [],
            "installedModels": project_runtime.get("installedModels") or [],
            "downloadableModels": project_runtime.get("downloadableModels") or [],
            "defaultModel": project_runtime.get("defaultVisualModel"),
        },
        {
            "id": "remote_api",
            "label": "API remota",
            "type": "remote_api",
            "available": bool(remote_provider.get("available")),
            "multimodalModels": remote_provider.get("multimodalModels") or [],
            "installedModels": remote_provider.get("installedModels") or [],
            "downloadableModels": remote_provider.get("downloadableModels") or [],
            "defaultModel": remote_provider.get("defaultVisualModel"),
        },
    ]
    capabilities = {
        "service": "transcription",
        "faster_whisper_installed": is_faster_whisper_installed(),
        "default_model": str(_get_value(settings, ["transcription_default_model"], "large-v3")),
        "device_mode": str(_get_value(settings, ["transcription_device"], "auto")),
        "compute_type_mode": str(_get_value(settings, ["transcription_compute_type"], "auto")),
        "hardware": hardware,
        "ollama": project_runtime,
        "profiles": profiles,
        "recommendedProfile": recommended_profile,
        "voiceAnalysisAvailable": bool(hardware.get("voiceAnalysisAvailable")),
        "sceneAnalysisAvailable": bool(hardware.get("sceneAnalysisAvailable")),
        "jobTimeoutMinutes": 480,
        "structuredTimeoutSeconds": int(selected_profile.get("structuredTimeoutSeconds") or DEFAULT_STRUCTURED_TIMEOUT_SECONDS),
        "styleTimeoutSeconds": int(selected_profile.get("styleTimeoutSeconds") or DEFAULT_STYLE_TIMEOUT_SECONDS),
        "timeoutProfileApplied": recommended_profile,
        "projectRuntime": project_runtime,
        "hostRuntime": host_runtime,
        "providers": providers,
        "installedModelsByProvider": {
            "ollama_project": project_runtime.get("installedModels") or [],
            "remote_api": remote_provider.get("installedModels") or [],
        },
        "downloadableModelsByProvider": {
            "ollama_project": project_runtime.get("downloadableModels") or [],
            "remote_api": remote_provider.get("downloadableModels") or [],
        },
        "activeModelStorePath": str(settings.ollama_model_store_dir),
        "hostInstalledModels": host_runtime.get("installedModels") or [],
    }
    with _CAPABILITIES_CACHE_LOCK:
        _CAPABILITIES_CACHE = _clone_capabilities_document(capabilities)
        _CAPABILITIES_CACHE_AT = now
    return _clone_capabilities_document(capabilities)


def _lookup_provider_capabilities(
    capabilities: dict[str, Any],
    provider_id: str,
) -> dict[str, Any]:
    normalized_provider = _normalize_ai_provider(provider_id)
    for provider in capabilities.get("providers") or []:
        if not isinstance(provider, dict):
            continue
        if str(provider.get("id") or "").strip().lower() == normalized_provider:
            return provider
    return {}


# -----------------------------------------------------------------------------
# Generic helpers
# -----------------------------------------------------------------------------

def _get_value(source: Any, keys: list[str], default: Any = None) -> Any:
    if isinstance(source, dict):
        for key in keys:
            if key in source and source[key] is not None:
                return source[key]
        return default
    for key in keys:
        if hasattr(source, key):
            value = getattr(source, key)
            if value is not None:
                return value
    return default



def _path_attr(source: Any, key: str, default: str) -> Path:
    raw = _get_value(source, [key], default)
    return Path(str(raw)).expanduser().resolve()



def _pick_str(payload: dict[str, Any], *keys: str, default: str = "") -> str:
    value = _get_value(payload, list(keys), default)
    if value is None:
        return default
    return str(value).strip() or default



def _pick_bool(payload: dict[str, Any], *keys: str, default: bool = False) -> bool:
    value = _get_value(payload, list(keys), default)
    if isinstance(value, bool):
        return value
    if isinstance(value, (int, float)):
        return value != 0
    text = str(value or "").strip().lower()
    if text in {"true", "1", "yes", "sim"}:
        return True
    if text in {"false", "0", "no", "nao", "não"}:
        return False
    return default



def _pick_int(payload: dict[str, Any], *keys: str, default: int = 0) -> int:
    value = _get_value(payload, list(keys), default)
    try:
        return int(value)
    except Exception:
        return default



def _pick_float(payload: dict[str, Any], *keys: str, default: float = 0.0) -> float:
    value = _get_value(payload, list(keys), default)
    try:
        return float(value)
    except Exception:
        return default



def _pick_list(payload: dict[str, Any], *keys: str) -> list[str]:
    value = _get_value(payload, list(keys), None)
    if value is None:
        return []
    if isinstance(value, list):
        return [str(item).strip() for item in value if str(item).strip()]
    text = str(value).strip()
    if not text:
        return []
    if text.startswith("[") and text.endswith("]"):
        try:
            decoded = json.loads(text)
            if isinstance(decoded, list):
                return [str(item).strip() for item in decoded if str(item).strip()]
        except Exception:
            pass
    return [item.strip() for item in text.split(",") if item.strip()]



def _normalize_lang(code: str | None) -> str:
    value = (code or "").strip().lower().replace("_", "-")
    aliases = {
        "pt": "pt-br",
        "pt-br": "pt-br",
        "jp": "ja",
        "zh": "zh-cn",
        "zh-hans": "zh-cn",
    }
    return aliases.get(value, value)



def _display_lang(code: str) -> str:
    normalized = _normalize_lang(code)
    mapping = {
        "pt-br": "pt-BR",
        "en": "en",
        "es": "es",
        "fr": "fr",
        "de": "de",
        "it": "it",
        "ja": "ja",
        "ko": "ko",
        "zh-cn": "zh-CN",
        "ru": "ru",
        "ar": "ar",
        "hi": "hi",
    }
    return mapping.get(normalized, code)



def _ordered_unique(values: list[str]) -> list[str]:
    ordered: list[str] = []
    seen: set[str] = set()
    for value in values:
        if value not in seen:
            seen.add(value)
            ordered.append(value)
    return ordered



def _should_translate(target_language: str, source_language: str) -> bool:
    return _normalize_lang(target_language) != _normalize_lang(source_language)



def _ensure_dir(path: Path) -> Path:
    path.mkdir(parents=True, exist_ok=True)
    return path



def _relative_or_absolute(path: Path, base: Path) -> str:
    try:
        return str(path.resolve())
    except Exception:
        return str(path)



def _run_command(command: list[str], *, timeout: int | None = None) -> subprocess.CompletedProcess[str]:
    logger.debug("Executando comando: %s", " ".join(command))
    return subprocess.run(
        command,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
        timeout=timeout,
    )



def _ffmpeg_path() -> str:
    settings = get_settings()
    return str(_get_value(settings, ["ffmpeg_path"], os.getenv("FFMPEG_PATH", "ffmpeg")))



def _ffprobe_path() -> str:
    settings = get_settings()
    return str(_get_value(settings, ["ffprobe_path"], os.getenv("FFPROBE_PATH", "ffprobe")))



def _probe_duration_seconds(path: Path) -> float | None:
    command = [
        _ffprobe_path(),
        "-v",
        "error",
        "-show_entries",
        "format=duration",
        "-of",
        "default=noprint_wrappers=1:nokey=1",
        str(path),
    ]
    result = _run_command(command, timeout=60)
    if result.returncode != 0:
        return None
    try:
        return float((result.stdout or "").strip())
    except Exception:
        return None



def _probe_chapters(path: Path) -> list[dict[str, Any]]:
    command = [
        _ffprobe_path(),
        "-v",
        "error",
        "-show_chapters",
        "-print_format",
        "json",
        str(path),
    ]
    result = _run_command(command, timeout=60)
    if result.returncode != 0:
        return []

    try:
        decoded = json.loads(result.stdout or "{}")
    except Exception:
        return []

    chapters_raw = decoded.get("chapters")
    if not isinstance(chapters_raw, list):
        return []

    chapters: list[dict[str, Any]] = []
    for item in chapters_raw:
        if not isinstance(item, dict):
            continue
        tags = item.get("tags") if isinstance(item.get("tags"), dict) else {}
        title = str(tags.get("title") or item.get("title") or "").strip()
        try:
            start = float(item.get("start_time") or 0.0)
            end = float(item.get("end_time") or start)
        except Exception:
            continue
        if end <= start:
            continue
        chapters.append(
            {
                "title": title,
                "start": round(start, 3),
                "end": round(end, 3),
                "durationSeconds": round(end - start, 3),
            }
        )
    return chapters


def _is_video_file(path: Path) -> bool:
    return path.suffix.lower() in VIDEO_EXTENSIONS



def _is_audio_file(path: Path) -> bool:
    return path.suffix.lower() in AUDIO_EXTENSIONS



def _strip_path_quotes(value: str) -> str:
    return value.strip().strip('"').strip("'")



def _uploads_root() -> Path:
    settings = get_settings()
    explicit = os.getenv("UPLOADS_ROOT", "").strip()
    if explicit:
        configured = Path(explicit).expanduser()
        if not configured.is_absolute():
            shared_root = Path(str(_get_value(settings, ["shared_root_dir"], "") or "")).expanduser()
            service_root = Path.cwd().resolve()
            project_root = service_root.parent
            candidates: list[Path] = []
            if str(shared_root):
                try:
                    shared_root = shared_root.resolve()
                    candidates.extend([
                        shared_root / configured,
                        shared_root.parent / configured,
                    ])
                except Exception:
                    pass

            candidates.extend([
                project_root / configured,
                service_root / configured,
            ])

            existing = next((item.resolve() for item in candidates if item.exists()), None)
            if existing is not None:
                return existing

            configured_text = configured.as_posix().lower()
            if configured_text == "shared_storage" or configured_text.startswith("shared_storage/"):
                configured = (project_root / configured).resolve()
            elif configured_text == "uploads" or configured_text.startswith("uploads/"):
                configured = (shared_root / configured).resolve() if str(shared_root) else (project_root / configured).resolve()
            else:
                configured = (project_root / configured).resolve()
        else:
            configured = configured.resolve()
        return configured

    normalized_shared_root = _get_value(settings, ["shared_root_dir"], None)
    if normalized_shared_root:
        return Path(str(normalized_shared_root)).expanduser().resolve()

    for key in [
        "shared_storage_root",
        "shared_root",
        "storage_root",
        "shared_storage_dir",
    ]:
        raw = _get_value(settings, [key], None)
        if raw:
            configured = Path(str(raw)).expanduser()
            if configured.is_absolute():
                return configured.resolve()
            return (Path.cwd().resolve().parent / configured).resolve()

    return Path.cwd().resolve() / "shared_storage"



def _resolve_source_file(source_type: str, source_value: str) -> Path:
    normalized_type = (source_type or "file_path").strip().lower()
    value = _strip_path_quotes(source_value or "")
    if not value:
        raise FileNotFoundError("SourceValue não foi informado.")

    if normalized_type == "url":
        return _download_remote_file(value)

    candidate = Path(value)
    if candidate.is_absolute() and candidate.exists():
        return candidate.resolve()

    root = _uploads_root()
    relative_candidate = Path(value)
    uploads_relative = None
    try:
        uploads_relative = relative_candidate.relative_to("uploads")
    except Exception:
        uploads_relative = None

    candidates = [
        root / value,
        root / "uploads" / value,
        root.parent / value if root.name.lower() == "uploads" else None,
        root / uploads_relative if uploads_relative is not None else None,
        Path.cwd() / value,
        Path.cwd() / "uploads" / value,
    ]
    if candidate.exists():
        return candidate.resolve()
    for item in candidates:
        if item is None:
            continue
        if item.exists():
            return item.resolve()

    raise FileNotFoundError(f"Arquivo não encontrado: {value}")



def _download_remote_file(source_url: str) -> Path:
    settings = get_settings()
    temp_dir = _path_attr(settings, "temp_dir", tempfile.gettempdir())
    _ensure_dir(temp_dir)
    suffix = Path(source_url.split("?")[0]).suffix or ".bin"
    target = temp_dir / f"remote_{uuid4().hex}{suffix}"

    request = urllib.request.Request(source_url, headers={"User-Agent": "HubIA/1.0"})
    with urllib.request.urlopen(request, timeout=120) as response, target.open("wb") as handle:
        shutil.copyfileobj(response, handle)
    return target


def _fetch_online_context(payload: dict[str, Any]) -> list[dict[str, str]]:
    if not _pick_bool(payload, "enable_online_context", "enableOnlineContext", default=False):
        return []

    hints = _get_value(payload, ["context_hints", "contextHints"], {}) or {}
    if not isinstance(hints, dict):
        return []

    urls = hints.get("urls") or []
    if not isinstance(urls, list):
        urls = []

    references: list[dict[str, str]] = []
    for raw_url in urls[:5]:
        url = str(raw_url or "").strip()
        if not url:
            continue
        try:
            request = urllib.request.Request(url, headers={"User-Agent": "HubIA/1.0"})
            with urllib.request.urlopen(request, timeout=20) as response:
                content_type = response.headers.get("Content-Type", "")
                body = response.read().decode("utf-8", errors="replace")
            excerpt = re.sub(r"\s+", " ", body).strip()[:2000]
            references.append(
                {
                    "url": url,
                    "contentType": content_type,
                    "excerpt": excerpt,
                }
            )
        except Exception as exc:
            logger.debug("Falha ao obter contexto online de %s: %s", url, exc)

    return references


# -----------------------------------------------------------------------------
# Output paths
# -----------------------------------------------------------------------------

def _build_job_output_root(source_file: Path) -> Path:
    settings = get_settings()
    explicit = _get_value(settings, ["shared_outputs_dir", "outputs_dir"], None)
    if explicit:
        base = Path(str(explicit)).expanduser().resolve()
    else:
        base = _uploads_root() / "outputs"
    _ensure_dir(base)
    return _ensure_dir(base / f"job_{uuid4().hex}")



def _base_stem(source_file: Path) -> str:
    return source_file.stem.strip() or f"transcription_{uuid4().hex}"


# -----------------------------------------------------------------------------
# Whisper transcription
# -----------------------------------------------------------------------------

def _segment_text(item: dict[str, Any]) -> str:
    return str(item.get("text") or "").strip()



def _clone_segments(segments: list[dict[str, Any]]) -> list[dict[str, Any]]:
    return [dict(segment) for segment in segments]



def _segments_text(segments: list[dict[str, Any]]) -> str:
    return "\n".join(_segment_text(item) for item in segments if _segment_text(item)).strip()


def _should_publish_empty_translation(
    *,
    source_segments: list[dict[str, Any]],
    translated_segments: list[dict[str, Any]],
) -> bool:
    return not _segments_text(source_segments) and not _segments_text(translated_segments)


def _segment_coverage(segments: list[dict[str, Any]], duration_seconds: float | None) -> float:
    if not segments or not duration_seconds or duration_seconds <= 0:
        return 0.0
    total = 0.0
    for segment in segments:
        try:
            start = float(segment.get("start") or 0.0)
            end = float(segment.get("end") or start)
        except Exception:
            continue
        total += max(0.0, end - start)
    return max(0.0, min(1.0, total / duration_seconds))



def _segment_from_fw(segment: Any, *, index: int) -> dict[str, Any]:
    item: dict[str, Any] = {
        "id": int(getattr(segment, "id", index)),
        "start": float(getattr(segment, "start", 0.0) or 0.0),
        "end": float(getattr(segment, "end", 0.0) or 0.0),
        "text": str(getattr(segment, "text", "") or "").strip(),
        "avg_logprob": getattr(segment, "avg_logprob", None),
        "no_speech_prob": getattr(segment, "no_speech_prob", None),
        "compression_ratio": getattr(segment, "compression_ratio", None),
    }
    words = []
    for word in getattr(segment, "words", []) or []:
        try:
            words.append(
                {
                    "word": str(getattr(word, "word", "") or "").strip(),
                    "start": float(getattr(word, "start", 0.0) or 0.0),
                    "end": float(getattr(word, "end", 0.0) or 0.0),
                    "probability": float(getattr(word, "probability", 0.0) or 0.0),
                }
            )
        except Exception:
            continue
    if words:
        item["words"] = words
    return item



def _transcribe_base(
    *,
    source_file: Path,
    model_name: str,
    task: str,
    language: str,
    beam_size: int,
    vad_filter: bool,
    word_timestamps: bool,
    device_preference: str,
    compute_type_preference: str,
    warnings: list[str],
) -> tuple[list[dict[str, Any]], str, float | None, dict[str, Any]]:
    settings = get_settings()
    hardware = detect_hardware()
    device, device_index = _resolve_device(device_preference, hardware)
    compute_type = _resolve_compute_type(compute_type_preference, device, hardware)

    cpu_threads = int(_get_value(settings, ["transcription_cpu_threads"], 4))
    num_workers = int(_get_value(settings, ["transcription_num_workers"], 1))
    model = _get_model(model_name, device, device_index, compute_type, cpu_threads, num_workers)

    duration_seconds = _probe_duration_seconds(source_file)
    requested_language = None if language in {"", "auto"} else language

    def run_transcribe(current_vad: bool):
        segments_iter, info = model.transcribe(
            str(source_file),
            task="transcribe",
            language=requested_language,
            beam_size=max(1, beam_size),
            vad_filter=current_vad,
            word_timestamps=word_timestamps,
            condition_on_previous_text=False,
            temperature=0.0,
        )
        segments = [_segment_from_fw(segment, index=index) for index, segment in enumerate(segments_iter)]
        detected = str(getattr(info, "language", requested_language or "unknown") or "unknown")
        return segments, detected

    segments, detected_language = run_transcribe(vad_filter)

    if vad_filter:
        coverage = _segment_coverage(segments, duration_seconds)
        total_text = len(_segments_text(segments))
        if duration_seconds and duration_seconds >= 60 and (coverage < 0.15 or total_text < 80):
            try:
                rerun_segments, rerun_language = run_transcribe(False)
                rerun_coverage = _segment_coverage(rerun_segments, duration_seconds)
                if len(_segments_text(rerun_segments)) > total_text and rerun_coverage >= coverage:
                    warnings.append(
                        "Cobertura baixa detectada com VAD ativo; transcrição refeita com VAD desativado."
                    )
                    segments = rerun_segments
                    detected_language = rerun_language
            except Exception as exc:
                warnings.append(f"Reexecução sem VAD falhou: {exc}")

    meta = {
        "hardware": hardware,
        "device": device,
        "device_index": device_index,
        "compute_type": compute_type,
    }
    return segments, detected_language, duration_seconds, meta


# -----------------------------------------------------------------------------
# Ollama helpers
# -----------------------------------------------------------------------------

def _get_ai_runtime_context() -> dict[str, Any]:
    return dict(_AI_RUNTIME_CONTEXT.get() or {})


def _set_ai_runtime_context(context: dict[str, Any]) -> contextvars.Token[dict[str, Any] | None]:
    return _AI_RUNTIME_CONTEXT.set(dict(context))


def _reset_ai_runtime_context(token: contextvars.Token[dict[str, Any] | None]) -> None:
    _AI_RUNTIME_CONTEXT.reset(token)


def _ollama_base_url() -> str:
    context = _get_ai_runtime_context()
    base_url = str(context.get("base_url") or _project_ollama_base_url()).strip()
    return base_url.rstrip("/")



def _extract_json_fragment(text: str) -> dict[str, Any] | None:
    text = text.strip()
    if not text:
        return None
    try:
        decoded = json.loads(text)
        if isinstance(decoded, dict):
            return decoded
    except Exception:
        pass

    match = re.search(r"\{.*\}", text, flags=re.DOTALL)
    if not match:
        return None
    fragment = match.group(0)
    try:
        decoded = json.loads(fragment)
        if isinstance(decoded, dict):
            return decoded
    except Exception:
        return None
    return None



def _truncate_raw_excerpt(value: str | None, limit: int = OLLAMA_RAW_EXCERPT_LIMIT) -> str | None:
    if value is None:
        return None
    clean = value.strip()
    if not clean:
        return None
    if len(clean) <= limit:
        return clean
    return clean[:limit] + "..."


def _compact_ollama_raw_excerpt(
    raw: str | None,
    decoded: dict[str, Any] | None,
    limit: int = OLLAMA_RAW_EXCERPT_LIMIT,
) -> str | None:
    if isinstance(decoded, dict) and decoded:
        compact: dict[str, Any] = {}

        for key in (
            "model",
            "created_at",
            "done",
            "done_reason",
            "total_duration",
            "load_duration",
            "prompt_eval_count",
            "eval_count",
        ):
            value = decoded.get(key)
            if value not in (None, "", [], {}):
                compact[key] = value

        for key in ("response", "thinking", "output"):
            value = _stringify_ollama_field(decoded.get(key))
            if value:
                compact[key] = _truncate_raw_excerpt(value, max(120, limit // 3))

        message_value = decoded.get("message")
        if isinstance(message_value, dict):
            content = _stringify_ollama_field(message_value.get("content"))
            if content:
                compact["message"] = {
                    "content": _truncate_raw_excerpt(content, max(120, limit // 3))
                }

        error_value = _stringify_ollama_field(decoded.get("error"))
        if error_value:
            compact["error"] = _truncate_raw_excerpt(error_value, max(120, limit // 3))

        if compact:
            try:
                return _truncate_raw_excerpt(
                    json.dumps(compact, ensure_ascii=False),
                    limit=limit,
                )
            except Exception:
                pass

    return _truncate_raw_excerpt(raw, limit=limit)


def _stringify_ollama_field(value: Any) -> str:
    if value is None:
        return ""
    if isinstance(value, str):
        return value.strip()
    if isinstance(value, (dict, list)):
        try:
            return json.dumps(value, ensure_ascii=False)
        except Exception:
            return str(value).strip()
    return str(value).strip()


def _extract_ollama_text(
    decoded: dict[str, Any],
    *,
    structured: bool,
) -> tuple[str | None, str | None]:
    candidates: list[tuple[str, Any]] = [("response", decoded.get("response"))]
    message = decoded.get("message")
    if isinstance(message, dict):
        candidates.append(("message.content", message.get("content")))
    candidates.append(("thinking", decoded.get("thinking")))
    candidates.append(("output", decoded.get("output")))

    if structured:
        for field, candidate in candidates:
            text = _stringify_ollama_field(candidate)
            if not text:
                continue
            if field == "response":
                return text, field
            if _extract_json_fragment(text) is not None:
                return text, field
        return None, None

    for field, candidate in candidates:
        text = _stringify_ollama_field(candidate)
        if text:
            return text, field
    return None, None


def _sanitize_ai_text(text: str) -> str:
    sanitized = DECORATIVE_TEXT_PATTERN.sub("", text or "")
    sanitized = sanitized.replace("\ufe0f", "")
    sanitized = sanitized.replace("♪", "").replace("♫", "").replace("♬", "")
    return re.sub(r"\s+", " ", sanitized).strip()


def _collapse_repeated_translation_text(text: str) -> str:
    compact = re.sub(r"\s+", " ", text or "").strip()
    if not compact:
        return ""

    clause_split = re.split(r"\s*(?:,|;|\||/)\s*", compact)
    if len(clause_split) > 1:
        deduped: list[str] = []
        for clause in clause_split:
            cleaned = clause.strip()
            if not cleaned:
                continue
            if deduped and cleaned.lower() == deduped[-1].lower():
                continue
            deduped.append(cleaned)
        if deduped:
            compact = ", ".join(deduped)

    words = compact.split()
    max_span = len(words) // 2
    lowered_words = [item.lower() for item in words]
    for span in range(max_span, 1, -1):
        if lowered_words[-span:] == lowered_words[-(span * 2):-span]:
            compact = " ".join(words[:-span]).strip()
            break
        if len(words) > (span * 2) and lowered_words[-span:] == lowered_words[-((span * 2) + 1):-(span + 1)]:
            compact = " ".join(words[:-span]).strip()
            break

    return re.sub(r"\s+", " ", compact).strip(" ,;-")


def _sanitize_translated_text(source_text: str, translated_text: str) -> str:
    if not (source_text or "").strip():
        return ""

    sanitized = _sanitize_ai_text(translated_text)
    if not sanitized:
        return ""

    if not re.search(r"\d", source_text or ""):
        sanitized = re.sub(r"(?:[,;:\-]\s*)?\b\d+\.\d{1,2}\b$", "", sanitized).strip()
        sanitized = re.sub(r"(?:[,;:\-]\s*)?\b\d+\b$", "", sanitized).strip()
    sanitized = re.sub(r"\b(?:duration|seconds?|timestamp|index)\b[:=]?\s*[\d.]+", "", sanitized, flags=re.IGNORECASE)
    sanitized = _collapse_repeated_translation_text(sanitized)
    return re.sub(r"\s+", " ", sanitized).strip(" ,;-")


def _sanitize_translated_segments(
    source_segments: list[dict[str, Any]],
    translated_segments: list[dict[str, Any]],
) -> list[dict[str, Any]]:
    sanitized_segments: list[dict[str, Any]] = []
    for index, segment in enumerate(translated_segments):
        clone = dict(segment)
        source_text = _segment_text(source_segments[index]) if index < len(source_segments) else ""
        clone["text"] = _sanitize_translated_text(source_text, _segment_text(segment))
        sanitized_segments.append(clone)
    return sanitized_segments


def _diagnostic_entry(
    *,
    stage: str,
    severity: str,
    message: str,
    model: str | None = None,
    language: str | None = None,
    fallback_used: str | None = None,
    raw_excerpt: str | None = None,
    source_field: str | None = None,
    duration_ms: int | None = None,
) -> dict[str, Any]:
    entry: dict[str, Any] = {
        "stage": stage,
        "severity": severity,
        "message": message,
    }
    if model:
        entry["model"] = model
    if language:
        entry["language"] = language
    if fallback_used:
        entry["fallbackUsed"] = fallback_used
    if raw_excerpt:
        entry["rawExcerpt"] = raw_excerpt
    if source_field:
        entry["sourceField"] = source_field
    if duration_ms is not None:
        entry["durationMs"] = duration_ms
    return entry


def _append_stage_diagnostic(
    diagnostics: list[dict[str, Any]],
    *,
    stage: str,
    severity: str,
    message: str,
    model: str | None = None,
    language: str | None = None,
    fallback_used: str | None = None,
    raw_excerpt: str | None = None,
    source_field: str | None = None,
    duration_ms: int | None = None,
) -> None:
    diagnostics.append(
        _diagnostic_entry(
            stage=stage,
            severity=severity,
            message=message,
            model=model,
            language=language,
            fallback_used=fallback_used,
            raw_excerpt=raw_excerpt,
            source_field=source_field,
            duration_ms=duration_ms,
        )
    )


def _translate_source_file_with_faster_whisper(
    *,
    source_file: Path,
    model_name: str,
    input_language: str,
    beam_size: int,
    vad_filter: bool,
    device_preference: str,
    compute_type_preference: str,
) -> list[dict[str, Any]]:
    hardware = detect_hardware()
    device, device_index = _resolve_device(device_preference, hardware)
    compute_type = _resolve_compute_type(compute_type_preference, device, hardware)
    settings = get_settings()
    model = _get_model(
        model_name,
        device,
        device_index,
        compute_type,
        int(_get_value(settings, ["transcription_cpu_threads"], 4)),
        int(_get_value(settings, ["transcription_num_workers"], 1)),
    )
    segments_iter, _ = model.transcribe(
        str(source_file),
        task="translate",
        language=None if input_language == "auto" else input_language,
        beam_size=max(1, beam_size),
        vad_filter=vad_filter,
        word_timestamps=False,
        condition_on_previous_text=False,
        temperature=0.0,
    )
    return [_segment_from_fw(segment, index=i) for i, segment in enumerate(segments_iter)]


def _post_json(url: str, payload: dict[str, Any], headers: dict[str, str], timeout_seconds: int = 20) -> None:
    request = urllib.request.Request(
        url,
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json", **headers},
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=timeout_seconds):
        return None


def _report_job_progress(
    payload: dict[str, Any],
    *,
    progress_percent: int,
    current_stage: str,
    current_pass: int = 0,
    total_passes: int = 0,
    quality_summary: dict[str, Any] | None = None,
    translation_statuses: dict[str, Any] | None = None,
    style_source: str | None = None,
    capability_profile: dict[str, Any] | None = None,
    error_message: str | None = None,
) -> None:
    callback_url = _pick_str(payload, "progress_callback_url", "progressCallbackUrl", default="")
    callback_token = _pick_str(payload, "progress_callback_token", "progressCallbackToken", default="")
    if not callback_url:
        return

    body: dict[str, Any] = {
        "progressPercent": max(0, min(100, int(progress_percent))),
        "currentStage": current_stage,
        "currentPass": max(0, int(current_pass)),
        "totalPasses": max(0, int(total_passes)),
    }
    if quality_summary is not None:
        body["qualitySummary"] = quality_summary
    if translation_statuses is not None:
        body["translationStatuses"] = translation_statuses
    if style_source:
        body["styleSource"] = style_source
    if capability_profile is not None:
        body["capabilityProfile"] = capability_profile
    if error_message:
        body["errorMessage"] = error_message

    logger.info(
        "Job progress update: job_id=%s stage=%s progress=%s pass=%s/%s",
        _pick_str(payload, "job_id", "jobId"),
        current_stage,
        body["progressPercent"],
        body["currentPass"],
        body["totalPasses"],
    )

    try:
        headers = {"X-Internal-Api-Key": callback_token} if callback_token else {}
        _post_json(callback_url, body, headers)
    except Exception:
        logger.debug("Falha ao reportar progresso do job para %s.", callback_url, exc_info=True)


def _ollama_error_context(exc: Exception) -> dict[str, Any]:
    if isinstance(exc, OllamaCallError):
        return {
            "raw_excerpt": exc.raw_excerpt,
            "source_field": exc.response_field,
            "duration_ms": exc.elapsed_ms,
            "status_code": exc.status_code,
            "model": exc.model,
        }
    return {}


def _call_ollama_generate(
    *,
    model: str,
    prompt: str,
    system: str | None = None,
    images: list[str] | None = None,
    format_schema: dict[str, Any] | str | None = None,
    temperature: float = 0.2,
    top_p: float = 0.9,
    num_predict: int = 1024,
    timeout_seconds: int = DEFAULT_OLLAMA_TIMEOUT_SECONDS,
) -> OllamaGenerateResult:
    url = f"{_ollama_base_url()}/api/generate"
    payload: dict[str, Any] = {
        "model": model,
        "prompt": prompt,
        "stream": False,
        "options": {
            "temperature": temperature,
            "top_p": top_p,
            "num_predict": num_predict,
        },
    }
    if system and system.strip():
        payload["system"] = system.strip()
    if images:
        payload["images"] = images
    if format_schema is not None:
        payload["format"] = format_schema

    request = urllib.request.Request(
        url,
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST",
    )

    started = time.perf_counter()
    try:
        with urllib.request.urlopen(request, timeout=timeout_seconds) as response:
            raw = response.read().decode("utf-8", errors="replace")
    except urllib.error.HTTPError as exc:
        raw = exc.read().decode("utf-8", errors="replace") if exc.fp else ""
        decoded = _extract_json_fragment(raw) or {}
        raise OllamaCallError(
            str(decoded.get("error") or raw or f"HTTP {exc.code} ao chamar Ollama"),
            model=model,
            status_code=exc.code,
            raw_excerpt=_compact_ollama_raw_excerpt(raw, decoded),
            elapsed_ms=int((time.perf_counter() - started) * 1000),
        ) from exc
    except Exception as exc:
        raise OllamaCallError(
            f"Falha ao chamar Ollama: {exc}",
            model=model,
            raw_excerpt=None,
            elapsed_ms=int((time.perf_counter() - started) * 1000),
        ) from exc

    decoded = _extract_json_fragment(raw) or {}
    raw_excerpt = _compact_ollama_raw_excerpt(raw, decoded)
    response_text, source_field = _extract_ollama_text(
        decoded,
        structured=format_schema is not None,
    )
    if response_text and source_field:
        return OllamaGenerateResult(
            text=response_text,
            source_field=source_field,
            raw_excerpt=raw_excerpt,
            elapsed_ms=int((time.perf_counter() - started) * 1000),
        )
    if decoded.get("error"):
        raise OllamaCallError(
            str(decoded["error"]).strip(),
            model=model,
            raw_excerpt=raw_excerpt,
            elapsed_ms=int((time.perf_counter() - started) * 1000),
        )
    raise OllamaCallError(
        "Resposta inválida do Ollama.",
        model=model,
        raw_excerpt=raw_excerpt,
        elapsed_ms=int((time.perf_counter() - started) * 1000),
    )


def _remote_api_base_url() -> str:
    context = _get_ai_runtime_context()
    explicit = str(context.get("base_url") or "").strip()
    if explicit:
        return explicit.rstrip("/")
    settings = get_settings()
    return str(_get_value(settings, ["remote_api_base_url"], "") or "").strip().rstrip("/")


def _remote_api_key() -> str:
    context = _get_ai_runtime_context()
    explicit = str(context.get("api_key") or "").strip()
    if explicit:
        return explicit
    settings = get_settings()
    return str(_get_value(settings, ["remote_api_api_key"], "") or "").strip()


def _build_remote_api_messages(
    messages: list[dict[str, Any]],
    *,
    images: list[str] | None = None,
) -> list[dict[str, Any]]:
    if not images:
        return messages

    prepared: list[dict[str, Any]] = []
    for index, message in enumerate(messages):
        if index != len(messages) - 1:
            prepared.append(message)
            continue

        text_value = _stringify_ollama_field(message.get("content"))
        content_parts: list[dict[str, Any]] = []
        if text_value:
            content_parts.append({"type": "text", "text": text_value})
        for encoded in images:
            if not encoded:
                continue
            content_parts.append(
                {
                    "type": "image_url",
                    "image_url": {"url": f"data:image/jpeg;base64,{encoded}"},
                }
            )
        prepared.append({**message, "content": content_parts or text_value})
    return prepared


def _extract_remote_api_text(
    decoded: dict[str, Any],
    *,
    structured: bool,
) -> tuple[str | None, str | None]:
    choices = decoded.get("choices")
    if not isinstance(choices, list) or not choices:
        return None, None

    message = choices[0] if isinstance(choices[0], dict) else {}
    if "message" in message and isinstance(message["message"], dict):
        message = message["message"]

    content = message.get("content")
    if isinstance(content, list):
        parts: list[str] = []
        for item in content:
            if not isinstance(item, dict):
                continue
            text_value = _stringify_ollama_field(item.get("text"))
            if text_value:
                parts.append(text_value)
        content = "\n".join(part for part in parts if part).strip()

    text = _stringify_ollama_field(content)
    if not text:
        return None, None
    if structured and _extract_json_fragment(text) is None:
        return None, None
    return text, "choices[0].message.content"


def _call_remote_api_chat(
    *,
    model: str,
    messages: list[dict[str, Any]],
    images: list[str] | None = None,
    format_schema: dict[str, Any] | str | None = None,
    temperature: float = 0.0,
    top_p: float = 0.9,
    num_predict: int = 1024,
    timeout_seconds: int = DEFAULT_OLLAMA_TIMEOUT_SECONDS,
) -> OllamaGenerateResult:
    base_url = _remote_api_base_url()
    api_key = _remote_api_key()
    if not base_url or not api_key:
        raise OllamaCallError(
            "Provider remoto não está configurado localmente.",
            model=model,
        )

    payload: dict[str, Any] = {
        "model": model,
        "messages": _build_remote_api_messages(messages, images=images),
        "temperature": temperature,
        "top_p": top_p,
        "max_tokens": num_predict,
    }
    if format_schema is not None:
        payload["response_format"] = {"type": "json_object"}

    request = urllib.request.Request(
        f"{base_url}/chat/completions",
        data=json.dumps(payload).encode("utf-8"),
        headers={
            "Content-Type": "application/json",
            "Authorization": f"Bearer {api_key}",
        },
        method="POST",
    )

    started = time.perf_counter()
    try:
        with urllib.request.urlopen(request, timeout=timeout_seconds) as response:
            raw = response.read().decode("utf-8", errors="replace")
    except urllib.error.HTTPError as exc:
        raw = exc.read().decode("utf-8", errors="replace") if exc.fp else ""
        decoded = _extract_json_fragment(raw) or {}
        raise OllamaCallError(
            str(decoded.get("error") or raw or f"HTTP {exc.code} ao chamar provider remoto"),
            model=model,
            status_code=exc.code,
            raw_excerpt=_truncate_raw_excerpt(raw),
            elapsed_ms=int((time.perf_counter() - started) * 1000),
        ) from exc
    except Exception as exc:
        raise OllamaCallError(
            f"Falha ao chamar provider remoto: {exc}",
            model=model,
            raw_excerpt=None,
            elapsed_ms=int((time.perf_counter() - started) * 1000),
        ) from exc

    decoded = _extract_json_fragment(raw) or {}
    raw_excerpt = _truncate_raw_excerpt(raw)
    response_text, source_field = _extract_remote_api_text(
        decoded,
        structured=format_schema is not None,
    )
    if response_text and source_field:
        return OllamaGenerateResult(
            text=response_text,
            source_field=source_field,
            raw_excerpt=raw_excerpt,
            elapsed_ms=int((time.perf_counter() - started) * 1000),
        )
    raise OllamaCallError(
        "Resposta inválida do provider remoto.",
        model=model,
        raw_excerpt=raw_excerpt,
        elapsed_ms=int((time.perf_counter() - started) * 1000),
    )


def _call_ollama_chat(
    *,
    model: str,
    messages: list[dict[str, Any]],
    images: list[str] | None = None,
    format_schema: dict[str, Any] | str | None = None,
    temperature: float = 0.0,
    top_p: float = 0.9,
    num_predict: int = 1024,
    timeout_seconds: int = DEFAULT_OLLAMA_TIMEOUT_SECONDS,
    think: bool = False,
) -> OllamaGenerateResult:
    runtime_context = _get_ai_runtime_context()
    if runtime_context.get("provider") == "remote_api":
        return _call_remote_api_chat(
            model=model,
            messages=messages,
            images=images,
            format_schema=format_schema,
            temperature=temperature,
            top_p=top_p,
            num_predict=num_predict,
            timeout_seconds=timeout_seconds,
        )

    url = f"{_ollama_base_url()}/api/chat"
    payload: dict[str, Any] = {
        "model": model,
        "messages": messages,
        "stream": False,
        "think": think,
        "options": {
            "temperature": temperature,
            "top_p": top_p,
            "num_predict": num_predict,
        },
    }
    if images and payload["messages"]:
        payload["messages"][-1] = {
            **payload["messages"][-1],
            "images": images,
        }
    if format_schema is not None:
        payload["format"] = format_schema

    request = urllib.request.Request(
        url,
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST",
    )

    started = time.perf_counter()
    try:
        with urllib.request.urlopen(request, timeout=timeout_seconds) as response:
            raw = response.read().decode("utf-8", errors="replace")
    except urllib.error.HTTPError as exc:
        raw = exc.read().decode("utf-8", errors="replace") if exc.fp else ""
        decoded = _extract_json_fragment(raw) or {}
        raise OllamaCallError(
            str(decoded.get("error") or raw or f"HTTP {exc.code} ao chamar Ollama chat"),
            model=model,
            status_code=exc.code,
            raw_excerpt=_compact_ollama_raw_excerpt(raw, decoded),
            elapsed_ms=int((time.perf_counter() - started) * 1000),
        ) from exc
    except Exception as exc:
        raise OllamaCallError(
            f"Falha ao chamar Ollama chat: {exc}",
            model=model,
            raw_excerpt=None,
            elapsed_ms=int((time.perf_counter() - started) * 1000),
        ) from exc

    decoded = _extract_json_fragment(raw) or {}
    raw_excerpt = _compact_ollama_raw_excerpt(raw, decoded)
    response_text, source_field = _extract_ollama_text(
        decoded,
        structured=format_schema is not None,
    )
    if response_text and source_field:
        return OllamaGenerateResult(
            text=response_text,
            source_field=source_field,
            raw_excerpt=raw_excerpt,
            elapsed_ms=int((time.perf_counter() - started) * 1000),
        )
    if decoded.get("error"):
        raise OllamaCallError(
            str(decoded["error"]).strip(),
            model=model,
            raw_excerpt=raw_excerpt,
            elapsed_ms=int((time.perf_counter() - started) * 1000),
        )
    raise OllamaCallError(
        "Resposta inválida do Ollama chat.",
        model=model,
        raw_excerpt=raw_excerpt,
        elapsed_ms=int((time.perf_counter() - started) * 1000),
    )


def _chunk_segments_for_ai(
    segments: list[dict[str, Any]],
    *,
    max_items: int = AI_SEGMENT_BATCH_SIZE,
    max_chars: int = 1800,
) -> list[tuple[int, list[dict[str, Any]]]]:
    chunks: list[tuple[int, list[dict[str, Any]]]] = []
    current: list[dict[str, Any]] = []
    current_chars = 0
    current_start = 0

    for index, segment in enumerate(segments):
        text = _segment_text(segment)
        size = max(1, len(text))
        if current and (len(current) >= max_items or current_chars + size > max_chars):
            chunks.append((current_start, current))
            current = []
            current_chars = 0
            current_start = index
        if not current:
            current_start = index
        current.append(segment)
        current_chars += size

    if current:
        chunks.append((current_start, current))
    return chunks


def _build_chunk_context(
    segments: list[dict[str, Any]],
    start_index: int,
    count: int,
    *,
    window: int = AI_CONTEXT_WINDOW,
) -> dict[str, Any]:
    before = []
    after = []
    for index in range(max(0, start_index - window), start_index):
        before.append(_segment_text(segments[index]))
    for index in range(start_index + count, min(len(segments), start_index + count + window)):
        after.append(_segment_text(segments[index]))
    return {
        "before": [item for item in before if item],
        "after": [item for item in after if item],
    }



def _reference_window_text(
    reference_segments: list[dict[str, Any]] | None,
    start_time: float,
    end_time: float,
) -> str:
    if not reference_segments:
        return ""

    lines: list[str] = []
    seen: set[str] = set()
    window_start = max(0.0, start_time - 0.8)
    window_end = end_time + 0.8

    for segment in reference_segments:
        seg_start = float(segment.get("start") or 0.0)
        seg_end = float(segment.get("end") or seg_start)
        if seg_end < window_start or seg_start > window_end:
            continue
        text = _segment_text(segment)
        if not text or text in seen:
            continue
        seen.add(text)
        lines.append(text)
        if len(" ".join(lines)) >= 500:
            break

    return " | ".join(lines[:6]).strip()


def _remap_reference_segments_by_time(
    source_segments: list[dict[str, Any]],
    reference_segments: list[dict[str, Any]],
) -> list[dict[str, Any]]:
    remapped: list[dict[str, Any]] = []
    for source_segment in source_segments:
        start = float(source_segment.get("start") or 0.0)
        end = float(source_segment.get("end") or start)
        duration = max(0.1, end - start)
        source_text = _segment_text(source_segment)
        max_join_chars = max(48, min(96, len(source_text) * 3 if source_text else 72))
        ranked_matches: list[tuple[float, float, float, str]] = []
        for reference_segment in reference_segments:
            ref_start = float(reference_segment.get("start") or 0.0)
            ref_end = float(reference_segment.get("end") or ref_start)
            overlap = min(end, ref_end) - max(start, ref_start)
            if overlap > 0.08:
                text = _segment_text(reference_segment)
                if text:
                    midpoint = (start + end) / 2
                    ref_midpoint = (ref_start + ref_end) / 2
                    ranked_matches.append(
                        (
                            overlap,
                            overlap / duration,
                            abs(ref_midpoint - midpoint),
                            text,
                        )
                    )

        ranked_matches.sort(key=lambda item: (-item[0], -item[1], item[2], len(item[3])))
        matches: list[str] = []
        total_chars = 0
        for overlap, ratio, _, text in ranked_matches:
            if text in matches:
                continue
            if matches and overlap < 0.18 and ratio < 0.35:
                continue
            projected_chars = total_chars + len(text) + (1 if matches else 0)
            if projected_chars > max_join_chars:
                break
            matches.append(text)
            total_chars = projected_chars
            if len(matches) >= 2:
                break

        if not matches:
            midpoint = (start + end) / 2
            nearest = min(
                reference_segments,
                key=lambda item: abs((((float(item.get("start") or 0.0) + float(item.get("end") or item.get("start") or 0.0)) / 2)) - midpoint),
                default=None,
            )
            nearest_text = _segment_text(nearest or {})
            if nearest_text:
                matches.append(nearest_text)

        clone = dict(source_segment)
        clone["text"] = _sanitize_ai_text(" ".join(matches).strip())
        remapped.append(clone)
    return remapped


def _items_schema(
    *,
    value_field: str = "text",
    enum_values: list[str] | None = None,
) -> dict[str, Any]:
    value_schema: dict[str, Any] = {"type": "string"}
    if enum_values:
        value_schema["enum"] = enum_values

    return {
        "type": "object",
        "properties": {
            "items": {
                "type": "array",
                "items": {
                    "type": "object",
                    "properties": {
                        "index": {"type": "integer"},
                        value_field: value_schema,
                    },
                    "required": ["index", value_field],
                },
            }
        },
        "required": ["items"],
    }


def _extract_structured_item_map(
    decoded: dict[str, Any] | None,
    *,
    value_field: str = "text",
    enum_values: list[str] | None = None,
) -> dict[int, str]:
    if not decoded or not isinstance(decoded.get("items"), list):
        return {}

    mapped: dict[int, str] = {}
    allowed_values = {item.strip().lower() for item in (enum_values or []) if str(item).strip()}
    for item in decoded["items"]:
        try:
            index = int(item.get("index"))
            value = str(item.get(value_field) or "").strip()
        except Exception:
            continue
        if value:
            sanitized = _sanitize_ai_text(value)
            if allowed_values and sanitized.strip().lower() not in allowed_values:
                continue
            mapped[index] = sanitized
    return mapped


def _fallback_structured_value(item: dict[str, Any], value_field: str) -> str:
    fallback_keys = [value_field]
    if value_field == "label":
        fallback_keys.extend(["fallbackLabel", "heuristicLabel"])
    fallback_keys.extend(["currentText", "text", "sourceText"])
    for key in fallback_keys:
        value = item.get(key)
        if value is None:
            continue
        return _sanitize_ai_text(str(value).strip())
    return ""


def _split_structured_prompt_payload(
    prompt_payload: dict[str, Any],
) -> list[tuple[dict[str, Any], int]]:
    items = prompt_payload.get("items")
    if not isinstance(items, list) or len(items) <= 1:
        return []

    midpoint = max(1, len(items) // 2)
    payloads: list[tuple[dict[str, Any], int]] = []
    for sub_items in [items[:midpoint], items[midpoint:]]:
        if not sub_items:
            continue
        cloned = dict(prompt_payload)
        cloned["items"] = sub_items
        cloned["expectedCount"] = len(sub_items)
        payloads.append((cloned, len(sub_items)))
    return payloads


def _call_structured_items_with_repair(
    *,
    model: str,
    system: str,
    prompt_payload: dict[str, Any],
    expected_count: int,
    value_field: str = "text",
    enum_values: list[str] | None = None,
    temperature: float,
    top_p: float,
    num_predict: int,
    images: list[str] | None = None,
    timeout_seconds: int = DEFAULT_STRUCTURED_TIMEOUT_SECONDS,
) -> tuple[dict[int, str], OllamaGenerateResult, bool]:
    schema = _items_schema(value_field=value_field, enum_values=enum_values)
    user_payload = json.dumps(prompt_payload, ensure_ascii=False)
    fallback_response = OllamaGenerateResult(
        text="",
        source_field="local_fallback",
        raw_excerpt=None,
        elapsed_ms=None,
        status_code=None,
    )
    items = prompt_payload.get("items") if isinstance(prompt_payload.get("items"), list) else []

    def _split_or_fallback(last_response: OllamaGenerateResult) -> tuple[dict[int, str], OllamaGenerateResult, bool]:
        split_payloads = _split_structured_prompt_payload(prompt_payload)
        if split_payloads:
            merged: dict[int, str] = {}
            repaired_any = True
            last = last_response
            for sub_payload, sub_expected in split_payloads:
                sub_mapped, sub_response, sub_repaired = _call_structured_items_with_repair(
                    model=model,
                    system=system,
                    prompt_payload=sub_payload,
                    expected_count=sub_expected,
                    value_field=value_field,
                    enum_values=enum_values,
                    temperature=temperature,
                    top_p=top_p,
                    num_predict=num_predict,
                    images=images,
                    timeout_seconds=timeout_seconds,
                )
                merged.update(sub_mapped)
                last = sub_response
                repaired_any = repaired_any or sub_repaired
            return merged, last, repaired_any

        if len(items) == 1:
            try:
                index = int(items[0].get("index"))
            except Exception:
                index = 0
            return {
                index: _fallback_structured_value(items[0], value_field),
            }, last_response, True

        return {}, last_response, True

    try:
        response = _call_ollama_chat(
            model=model,
            messages=[
                {"role": "system", "content": system},
                {"role": "user", "content": user_payload},
            ],
            images=images,
            format_schema=schema,
            temperature=temperature,
            top_p=top_p,
            num_predict=num_predict,
            timeout_seconds=timeout_seconds,
        )
    except Exception:
        return _split_or_fallback(fallback_response)

    mapped = _extract_structured_item_map(
        _extract_json_fragment(response.text),
        value_field=value_field,
        enum_values=enum_values,
    )
    if len(mapped) == expected_count:
        return mapped, response, False

    repair_payload = {
        "task": "repair_structured_items",
        "expectedCount": expected_count,
        "valueField": value_field,
        "originalRequest": prompt_payload,
        "previousResponse": response.text,
        "instructions": [
            "Corrija a estrutura e retorne JSON válido.",
            "Mantenha exatamente a mesma quantidade de itens solicitada.",
            "Não adicione comentários.",
        ],
    }
    try:
        repair_response = _call_ollama_chat(
            model=model,
            messages=[
                {
                    "role": "system",
                    "content": "Você repara respostas estruturadas e deve retornar apenas JSON válido no schema pedido.",
                },
                {"role": "user", "content": json.dumps(repair_payload, ensure_ascii=False)},
            ],
            format_schema=schema,
            temperature=0.0,
            top_p=1.0,
            num_predict=min(num_predict, 768),
            timeout_seconds=max(30, min(timeout_seconds, 60)),
        )
    except Exception:
        return _split_or_fallback(response)

    repaired = _extract_structured_item_map(
        _extract_json_fragment(repair_response.text),
        value_field=value_field,
        enum_values=enum_values,
    )
    if len(repaired) == expected_count:
        return repaired, repair_response, True
    return _split_or_fallback(repair_response)


def _translate_segments_with_ollama(
    *,
    segments: list[dict[str, Any]],
    source_language: str,
    target_language: str,
    reference_segments: list[dict[str, Any]] | None,
    song_segment_indices: set[int] | None,
    model: str,
    prompt_hint: str | None,
    temperature: float,
    top_p: float,
    num_predict: int,
    chunk_chars: int,
    batch_size: int,
    timeout_seconds: int,
    progress_callback: Callable[[int, int], None] | None = None,
) -> list[dict[str, Any]]:
    translated: list[dict[str, Any]] = []
    musical_indices = set(song_segment_indices or set())
    chunks = _chunk_segments_for_ai(
        segments,
        max_items=max(1, min(batch_size, 3)),
        max_chars=max(800, min(chunk_chars, 1600)),
    )

    system = (
        "Você é um tradutor profissional de legendas. Preserve o sentido, naturalidade e a ancoragem no texto falado. "
        "NÃO altere timestamps. NÃO invente frases. NÃO reduza a quantidade de itens. "
        "Retorne apenas JSON válido no schema pedido."
    )
    if reference_segments:
        system += (
            " Quando houver um campo referenceText em inglês, use-o apenas como apoio semântico. "
            "O texto final ainda deve ser fiel ao original e adequado para legendas."
        )
        if _normalize_lang(target_language) != "en":
            system += (
                " Para destinos não ingleses, trate referenceText como base semântica primária quando ele estiver coerente com sourceText."
            )
    if musical_indices:
        system += (
            " Quando musicalSegment=true, traduza como letra natural no idioma alvo. "
            "Evite literalidade palavra-por-palavra, ordem sintática quebrada, fragmentos sem função e romanização no texto final."
        )
    if prompt_hint:
        system += f"\nPreferência extra do usuário: {prompt_hint.strip()}"

    total_chunks = max(1, len(chunks))
    for chunk_number, (start_index, chunk) in enumerate(chunks, start=1):
        chunk_start_time = float(chunk[0].get("start") or 0.0) if chunk else 0.0
        chunk_end_time = float(chunk[-1].get("end") or chunk_start_time) if chunk else chunk_start_time
        has_per_item_reference = bool(reference_segments) and len(reference_segments) == len(segments)
        reference_context = _reference_window_text(
            reference_segments,
            chunk_start_time,
            chunk_end_time,
        )
        items = [
            {
                "index": idx,
                "text": _segment_text(segment),
                "durationSeconds": round(
                    max(0.1, float(segment.get("end") or 0.0) - float(segment.get("start") or 0.0)),
                    3,
                ),
                "musicalSegment": (start_index + idx) in musical_indices,
                **(
                    {"referenceText": _segment_text(reference_segments[start_index + idx])}
                    if has_per_item_reference and (start_index + idx) < len(reference_segments) and _segment_text(reference_segments[start_index + idx])
                    else {}
                ),
            }
            for idx, segment in enumerate(chunk)
        ]
        prompt_payload = {
            "task": "translate_subtitles",
            "sourceLanguage": _display_lang(source_language),
            "targetLanguage": _display_lang(target_language),
            "expectedCount": len(chunk),
            "context": _build_chunk_context(segments, start_index, len(chunk)),
            **({"referenceContext": reference_context} if reference_context else {}),
            "items": items,
            "instructions": [
                "Traduza cada item para o idioma alvo mantendo a mesma ordem.",
                "Retorne exatamente a mesma quantidade de itens recebidos.",
                "Não inclua comentários, notas, colchetes ou texto extra.",
                "Se a fala for ruído, watermark ou texto não falado, devolva string vazia.",
                "Não amplie nem explique o sentido do texto.",
                "Use referenceText apenas como apoio semântico quando existir; não copie cegamente.",
                "Para destinos não ingleses, use referenceText para estabilizar sentido e naturalidade quando ele estiver disponível.",
                "Quando musicalSegment=true, prefira uma tradução lírica, fluida e coerente no idioma alvo.",
                "Ignore completamente index, durationSeconds e qualquer outro metadado numérico.",
                "Nunca copie duração, ordem, ids, timestamps ou números técnicos para o texto final.",
            ],
        }
        mapped, response, repaired = _call_structured_items_with_repair(
            model=model,
            system=system,
            prompt_payload=prompt_payload,
            expected_count=len(chunk),
            temperature=min(temperature, 0.2),
            top_p=top_p,
            num_predict=min(num_predict, 128),
            value_field="text",
            timeout_seconds=timeout_seconds,
        )

        for idx, original in enumerate(chunk):
            updated = dict(original)
            fallback_used = idx not in mapped
            updated["text"] = _sanitize_translated_text(
                _segment_text(original),
                mapped.get(idx, _segment_text(original)),
            )
            if repaired or fallback_used:
                updated["_aiRepairUsed"] = True
                updated["_aiSourceField"] = response.source_field
            if fallback_used:
                updated["_aiFallbackUsed"] = "source_text"
            translated.append(updated)

        if progress_callback is not None:
            progress_callback(chunk_number, total_chunks)

    return translated


def _correct_segments_with_ollama(
    *,
    segments: list[dict[str, Any]],
    language: str,
    model: str,
    prompt_hint: str | None,
    temperature: float,
    top_p: float,
    num_predict: int,
    chunk_chars: int,
    batch_size: int,
    timeout_seconds: int,
    progress_callback: Callable[[int, int], None] | None = None,
) -> list[dict[str, Any]]:
    corrected: list[dict[str, Any]] = []
    chunks = _chunk_segments_for_ai(
        segments,
        max_items=max(1, min(batch_size, 3)),
        max_chars=max(800, min(chunk_chars, 1600)),
    )

    system = (
        "Você é um revisor de legendas. Corrija apenas ortografia, segmentação leve e leitura natural, "
        "sem adicionar conteúdo novo. Preserve o idioma e a intenção. "
        "Se o texto parecer watermark, handle social, propaganda ou ruído não falado, devolva string vazia. "
        "Retorne apenas JSON válido no schema pedido."
    )
    if prompt_hint:
        system += f"\nPreferência extra do usuário: {prompt_hint.strip()}"

    total_chunks = max(1, len(chunks))
    for chunk_number, (start_index, chunk) in enumerate(chunks, start=1):
        items = [{"index": idx, "text": _segment_text(segment)} for idx, segment in enumerate(chunk)]
        prompt_payload = {
            "task": "correct_subtitles",
            "language": _display_lang(language),
            "expectedCount": len(chunk),
            "context": _build_chunk_context(segments, start_index, len(chunk)),
            "items": items,
            "instructions": [
                "Corrija apenas erros evidentes e limpeza leve.",
                "Não altere o sentido e não reescreva livremente.",
                "Não acrescente frases finais genéricas.",
                "Se o item parecer ruído, watermark, URL ou handle social, devolva string vazia.",
                "Mantenha a ordem e a mesma quantidade de itens.",
            ],
        }
        mapped, response, repaired = _call_structured_items_with_repair(
            model=model,
            system=system,
            prompt_payload=prompt_payload,
            expected_count=len(chunk),
            temperature=min(temperature, 0.1),
            top_p=top_p,
            num_predict=min(num_predict, 128),
            value_field="text",
            timeout_seconds=timeout_seconds,
        )

        for idx, original in enumerate(chunk):
            updated = dict(original)
            fallback_used = idx not in mapped
            updated["text"] = mapped.get(idx, _segment_text(original))
            if repaired or fallback_used:
                updated["_aiRepairUsed"] = True
                updated["_aiSourceField"] = response.source_field
            if fallback_used:
                updated["_aiFallbackUsed"] = "source_text"
            corrected.append(updated)

        if progress_callback is not None:
            progress_callback(chunk_number, total_chunks)

    return corrected


def _revise_segments_with_ollama(
    *,
    source_segments: list[dict[str, Any]],
    current_segments: list[dict[str, Any]],
    reference_segments: list[dict[str, Any]] | None,
    target_language: str,
    song_segment_indices: set[int] | None,
    model: str,
    prompt_hint: str | None,
    temperature: float,
    top_p: float,
    num_predict: int,
    batch_size: int,
    timeout_seconds: int,
    progress_callback: Callable[[int, int], None] | None = None,
) -> list[dict[str, Any]]:
    musical_indices = set(song_segment_indices or set())
    critical_revision_reasons = {
        "transliteration_artifact",
        "weak_language_signal",
        "unchanged",
        "empty",
        "non_speech_noise",
        "invented_from_noise",
        "ai_review_reject",
    }
    system = (
        "Você é um revisor final de legendas traduzidas. Reescreva apenas os itens marcados como problemáticos. "
        "Mantenha a quantidade exata de itens e não altere timestamps. "
        "Se houver transliteração estranha, fragmentos romanizados ou literalidade ruim, substitua por uma frase natural."
    )
    if musical_indices:
        system += (
            " Quando musicalSegment=true, revise como letra natural no idioma alvo, preservando coerência poética sem inventar versos."
        )
    if prompt_hint:
        system += f"\nPreferência extra do usuário: {prompt_hint.strip()}"

    flagged_items = []
    for index, (source_item, current_item) in enumerate(zip(source_segments, current_segments)):
        score = _segment_quality_score(current_item)
        issues = current_item.get("_qualityReasons") or []
        is_musical = index in musical_indices
        requires_revision = (
            score < (QUALITY_PUBLISH_THRESHOLD if is_musical else QUALITY_REVIEW_THRESHOLD)
            or any(reason in critical_revision_reasons for reason in issues)
        )
        if not requires_revision:
            continue
        flagged_items.append(
            {
                "index": index,
                "sourceText": _segment_text(source_item),
                "currentText": _segment_text(current_item),
                "musicalSegment": is_musical,
                "issues": issues,
                **(
                    {"referenceText": _segment_text(reference_segments[index])}
                    if reference_segments and index < len(reference_segments) and _segment_text(reference_segments[index])
                    else {}
                ),
            }
        )

    if not flagged_items:
        return [dict(item) for item in current_segments]

    mapped: dict[int, str] = {}
    chunks = _chunk_segments_for_ai(
        flagged_items,
        max_items=max(1, min(batch_size, 3)),
        max_chars=1400,
    )
    total_chunks = max(1, len(chunks))
    for chunk_number, (_, chunk) in enumerate(chunks, start=1):
        prompt_payload = {
            "task": "revise_subtitles",
            "targetLanguage": _display_lang(target_language),
            "expectedCount": len(chunk),
            "items": chunk,
            "instructions": [
                "Corrija apenas os itens com problema de qualidade.",
                "Mantenha texto curto, legível e fiel à fala.",
                "Não invente conteúdo.",
                "Quando houver referenceText, use-o apenas como apoio semântico para corrigir trechos ruins.",
                "Para destinos não ingleses, use referenceText para estabilizar o sentido quando a tradução atual estiver dura ou literal.",
                "Se houver transliteração, romanização estranha ou frase literal truncada, reescreva em linguagem natural.",
                "Quando musicalSegment=true, prefira linguagem lírica fluida e sintaxe natural no idioma alvo.",
                "Retorne exatamente o mesmo número de itens.",
            ],
        }
        revised_map, _, _ = _call_structured_items_with_repair(
            model=model,
            system=system,
            prompt_payload=prompt_payload,
            expected_count=len(chunk),
            temperature=min(temperature, 0.1),
            top_p=top_p,
            num_predict=min(num_predict, 128),
            value_field="text",
            timeout_seconds=timeout_seconds,
        )
        for item in chunk:
            try:
                item_index = int(item.get("index"))
            except Exception:
                continue
            mapped[item_index] = revised_map.get(
                item_index,
                _fallback_structured_value(item, "text"),
            )
        if progress_callback is not None:
            progress_callback(chunk_number, total_chunks)

    revised: list[dict[str, Any]] = []
    for idx, original in enumerate(current_segments):
        updated = dict(original)
        updated["text"] = _sanitize_translated_text(
            _segment_text(source_segments[idx]) if idx < len(source_segments) else _segment_text(original),
            mapped.get(idx, _segment_text(original)),
        )
        revised.append(updated)
    return revised


def _looks_like_non_speech_text(text: str) -> bool:
    normalized = (text or "").strip()
    if not normalized:
        return True
    compact = normalized.lower()
    if SUSPICIOUS_NOISE_PATTERN.search(compact):
        return True
    if compact.count("@") >= 1 or ".com" in compact or "http" in compact:
        return True
    if len(compact) <= 4 and not re.search(r"[a-zA-Z0-9\u3040-\u30ff\u3400-\u9fff]", compact):
        return True
    return False


def _filter_non_speech_segments(segments: list[dict[str, Any]]) -> list[dict[str, Any]]:
    cleaned: list[dict[str, Any]] = []
    for segment in segments:
        clone = dict(segment)
        text = _sanitize_ai_text(_segment_text(segment))
        if _looks_like_non_speech_text(text):
            clone["text"] = ""
        else:
            clone["text"] = text
        cleaned.append(clone)
    return cleaned


def _segment_chars_per_second(segment: dict[str, Any]) -> float:
    duration = max(0.1, float(segment.get("end") or 0.0) - float(segment.get("start") or 0.0))
    return len(_segment_text(segment)) / duration


def _segment_quality_score(segment: dict[str, Any], default: int = 100) -> int:
    raw = segment.get("_qualityScore")
    if raw is None:
        return default
    try:
        return int(raw)
    except Exception:
        return default


def _repetition_ratio(text: str) -> float:
    words = [item for item in re.findall(r"\w+", (text or "").lower()) if item]
    if not words:
        return 0.0
    return 1.0 - (len(set(words)) / max(1, len(words)))


def _language_signal_score(text: str, target_language: str) -> float:
    normalized = _normalize_lang(target_language)
    if not text.strip():
        return 0.0

    if normalized == "ja":
        return 1.0 if re.search(r"[\u3040-\u30ff\u3400-\u9fff]", text) else 0.0
    if normalized == "ko":
        return 1.0 if re.search(r"[\uac00-\ud7af]", text) else 0.0
    if normalized == "zh-cn":
        return 1.0 if re.search(r"[\u3400-\u9fff]", text) else 0.0
    if normalized == "ar":
        return 1.0 if re.search(r"[\u0600-\u06FF]", text) else 0.0
    if normalized == "hi":
        return 1.0 if re.search(r"[\u0900-\u097F]", text) else 0.0
    return 1.0 if re.search(r"[A-Za-zÀ-ÿ]", text) else 0.0


def _looks_like_transliteration_artifact(text: str, target_language: str) -> bool:
    normalized = _normalize_lang(target_language)
    if normalized not in {"en", "pt-br", "es", "fr", "de", "it"}:
        return False

    tokens = re.findall(r"[A-Za-z]{6,}", text or "")
    if len(tokens) != 1:
        return False

    token = tokens[0]
    return token.isupper()


def _score_translation_segments(
    *,
    source_segments: list[dict[str, Any]],
    translated_segments: list[dict[str, Any]],
    source_language: str,
    target_language: str,
) -> list[SegmentQualityScore]:
    scores: list[SegmentQualityScore] = []

    for index, (source_item, translated_item) in enumerate(zip(source_segments, translated_segments)):
        reasons: list[str] = []
        score = 100

        source_text = _segment_text(source_item)
        translated_text = _segment_text(translated_item)
        cps = _segment_chars_per_second(translated_item)
        source_is_noise = not source_text or _looks_like_non_speech_text(source_text)

        if source_is_noise:
            if translated_text:
                if _looks_like_non_speech_text(translated_text):
                    score = 90
                    reasons.append("noise_suppressed")
                else:
                    score = 35
                    reasons.append("invented_from_noise")
            else:
                score = 100
                reasons.append("noise_suppressed")
        elif not translated_text:
            score = 0
            reasons.append("empty")
        else:
            if _looks_like_non_speech_text(translated_text):
                score -= 55
                reasons.append("non_speech_noise")
            if _looks_like_transliteration_artifact(translated_text, target_language):
                score -= 45
                reasons.append("transliteration_artifact")
            if _should_translate(target_language, source_language) and translated_text == source_text:
                score -= 45
                reasons.append("unchanged")
            if _should_translate(target_language, source_language) and _language_signal_score(translated_text, target_language) < 0.5:
                score -= 35
                reasons.append("weak_language_signal")
            repetition = _repetition_ratio(translated_text)
            if repetition >= 0.45:
                score -= 30
                reasons.append("repetition")
            if cps > 22:
                score -= min(25, int((cps - 22) * 2))
                reasons.append("high_cps")
            if len(translated_text) > max(6, len(source_text) * 2.6):
                score -= 15
                reasons.append("too_long")
            if "..." in translated_text and translated_text.count("...") > 2:
                score -= 8
                reasons.append("punctuation_noise")

        score = max(0, min(100, score))
        translated_item["_qualityScore"] = score
        translated_item["_qualityReasons"] = reasons
        scores.append(SegmentQualityScore(index=index, score=score, reasons=reasons))

    return scores


def _review_translation_quality_with_ollama(
    *,
    source_segments: list[dict[str, Any]],
    translated_segments: list[dict[str, Any]],
    reference_segments: list[dict[str, Any]] | None,
    target_language: str,
    model: str,
    prompt_hint: str | None,
    song_segment_indices: set[int] | None,
    review_indices: set[int] | None,
    batch_size: int,
    timeout_seconds: int,
) -> dict[int, str]:
    musical_indices = set(song_segment_indices or set())
    target_indices = sorted(review_indices or set())
    if not target_indices:
        return {}

    system = (
        "Você avalia a qualidade final de tradução para legendas. "
        "Para cada item, retorne apenas um label: ok, revise ou reject. "
        "Use reject quando o texto estiver semanticamente colapsado, fragmentado, romanizado, pouco natural "
        "ou claramente inadequado para o idioma alvo. Use revise quando a ideia central existir, mas a frase soar dura, literal ou pouco fluida."
    )
    if musical_indices:
        system += " Quando musicalSegment=true, seja mais rigoroso com fluidez lírica, coerência e naturalidade."
    if prompt_hint:
        system += f"\nPreferência extra do usuário: {prompt_hint.strip()}"

    items: list[dict[str, Any]] = []
    for index in target_indices:
        if index >= len(source_segments) or index >= len(translated_segments):
            continue
        source_text = _segment_text(source_segments[index])
        current_text = _segment_text(translated_segments[index])
        if not source_text and not current_text:
            continue
        items.append(
            {
                "index": index,
                "text": current_text,
                "sourceText": source_text,
                "currentText": current_text,
                "musicalSegment": index in musical_indices,
                "issues": translated_segments[index].get("_qualityReasons") or [],
                **(
                    {"referenceText": _segment_text(reference_segments[index])}
                    if reference_segments and index < len(reference_segments) and _segment_text(reference_segments[index])
                    else {}
                ),
            }
        )

    if not items:
        return {}

    labels: dict[int, str] = {}
    chunks = _chunk_segments_for_ai(
        items,
        max_items=max(1, min(batch_size, 3)),
        max_chars=1400,
    )
    for _, chunk in chunks:
        prompt_payload = {
            "task": "review_translation_quality",
            "targetLanguage": _display_lang(target_language),
            "expectedCount": len(chunk),
            "items": chunk,
            "instructions": [
                "Retorne ok apenas se a frase estiver natural, correta e fiel ao sentido.",
                "Use revise para trechos compreensíveis, porém duros, literais ou pouco naturais.",
                "Use reject para nonsense, colapso semântico, romanização, fragmentos sem função ou idioma errado.",
                "Quando musicalSegment=true, cobre fluidez lírica e sintaxe natural.",
                "Retorne exatamente o mesmo número de itens.",
            ],
        }
        mapped, _, _ = _call_structured_items_with_repair(
            model=model,
            system=system,
            prompt_payload=prompt_payload,
            expected_count=len(chunk),
            value_field="label",
            enum_values=["ok", "revise", "reject"],
            temperature=0.0,
            top_p=1.0,
            num_predict=96,
            timeout_seconds=max(30, min(timeout_seconds, 60)),
        )
        labels.update(mapped)

    return labels


def _score_and_summarize_translation(
    *,
    source_segments: list[dict[str, Any]],
    translated_segments: list[dict[str, Any]],
    source_language: str,
    target_language: str,
    ai_enabled: bool,
    model: str | None,
    prompt_hint: str | None,
    reference_segments: list[dict[str, Any]] | None,
    song_segment_indices: set[int] | None,
    batch_size: int,
    timeout_seconds: int,
    warnings: list[str],
    content_mode: str,
) -> tuple[list[SegmentQualityScore], dict[str, Any]]:
    scores = _score_translation_segments(
        source_segments=source_segments,
        translated_segments=translated_segments,
        source_language=source_language,
        target_language=target_language,
    )

    if ai_enabled and model:
        musical_indices = set(song_segment_indices or set())
        review_scope: set[int] = set()
        if content_mode == "anime_song":
            review_scope.update(
                index
                for index, item in enumerate(source_segments)
                if _segment_text(item)
            )
        review_scope.update(musical_indices)
        critical_review_reasons = {
            "transliteration_artifact",
            "weak_language_signal",
            "unchanged",
            "empty",
            "non_speech_noise",
            "invented_from_noise",
            "ai_review_reject",
        }
        review_scope.update(
            item.index
            for item in scores
            if item.score < QUALITY_PUBLISH_THRESHOLD
            or any(reason in critical_review_reasons for reason in item.reasons)
        )

        if review_scope:
            try:
                ai_labels = _review_translation_quality_with_ollama(
                    source_segments=source_segments,
                    translated_segments=translated_segments,
                    reference_segments=reference_segments,
                    target_language=target_language,
                    model=model,
                    prompt_hint=prompt_hint,
                    song_segment_indices=musical_indices,
                    review_indices=review_scope,
                    batch_size=batch_size,
                    timeout_seconds=timeout_seconds,
                )
                rescored: list[SegmentQualityScore] = []
                for item in scores:
                    label = str(ai_labels.get(item.index) or "").strip().lower()
                    updated_score = item.score
                    updated_reasons = list(item.reasons)
                    if label == "revise":
                        updated_score = max(
                            0,
                            updated_score - (30 if item.index in musical_indices or content_mode == "anime_song" else 22),
                        )
                        updated_reasons.append("ai_review_revise")
                    elif label == "reject":
                        updated_score = max(
                            0,
                            updated_score - (60 if item.index in musical_indices or content_mode == "anime_song" else 45),
                        )
                        updated_reasons.append("ai_review_reject")
                    updated_reasons = list(dict.fromkeys(updated_reasons))
                    translated_segments[item.index]["_qualityScore"] = updated_score
                    translated_segments[item.index]["_qualityReasons"] = updated_reasons
                    rescored.append(
                        SegmentQualityScore(
                            index=item.index,
                            score=updated_score,
                            reasons=updated_reasons,
                        )
                    )
                scores = rescored
            except Exception as exc:
                warnings.append(f"Revisor semântico de qualidade falhou: {exc}")

    return scores, _summarize_quality_scores(scores)


def _summarize_quality_scores(scores: list[SegmentQualityScore]) -> dict[str, Any]:
    if not scores:
        return {
            "averageScore": 0,
            "minScore": 0,
            "publishableSegments": 0,
            "reviewSegments": 0,
            "failedSegments": 0,
        }

    average = round(sum(item.score for item in scores) / len(scores), 2)
    publishable = sum(1 for item in scores if item.score >= QUALITY_PUBLISH_THRESHOLD)
    review = sum(1 for item in scores if QUALITY_REVIEW_THRESHOLD <= item.score < QUALITY_PUBLISH_THRESHOLD)
    failed = sum(1 for item in scores if item.score < QUALITY_REVIEW_THRESHOLD)
    suppressed_noise = sum(1 for item in scores if "noise_suppressed" in item.reasons)
    return {
        "averageScore": average,
        "minScore": min(item.score for item in scores),
        "publishableSegments": publishable,
        "reviewSegments": review,
        "failedSegments": failed,
        "suppressedNoiseSegments": suppressed_noise,
    }


def _apply_timing_fit(segments: list[dict[str, Any]]) -> list[dict[str, Any]]:
    if not segments:
        return []

    fitted = _clone_segments(segments)
    for index, segment in enumerate(fitted):
        cps = _segment_chars_per_second(segment)
        if cps <= 22:
            continue

        previous_end = float(fitted[index - 1].get("end") or 0.0) if index > 0 else float(segment.get("start") or 0.0)
        next_start = float(fitted[index + 1].get("start") or segment.get("end") or 0.0) if index + 1 < len(fitted) else float(segment.get("end") or 0.0)
        start = float(segment.get("start") or 0.0)
        end = float(segment.get("end") or start)

        leading_gap = max(0.0, start - previous_end)
        trailing_gap = max(0.0, next_start - end)
        if trailing_gap > 0.05:
            end += min(0.18, trailing_gap * 0.6)
        if leading_gap > 0.05:
            start -= min(0.12, leading_gap * 0.5)

        segment["start"] = round(max(previous_end, start), 3)
        segment["end"] = round(max(segment["start"] + 0.1, end), 3)

    return fitted


def _apply_style_labels(
    segments: list[dict[str, Any]],
    labels: list[str],
) -> list[dict[str, Any]]:
    styled: list[dict[str, Any]] = []
    for index, segment in enumerate(segments):
        clone = dict(segment)
        clone["styleLabel"] = labels[index] if index < len(labels) else "default"
        styled.append(clone)
    return styled


def _should_use_english_reference_as_primary_translation(
    *,
    ai_enabled: bool,
    target_language: str,
) -> bool:
    return _normalize_lang(target_language) == "en"


def _quality_is_publishable(summary: dict[str, Any], total_segments: int) -> bool:
    average = float(summary.get("averageScore") or 0)
    min_score = float(summary.get("minScore") or 0)
    failed = int(summary.get("failedSegments") or 0)
    publishable = int(summary.get("publishableSegments") or 0)
    review = int(summary.get("reviewSegments") or 0)
    suppressed_noise = int(summary.get("suppressedNoiseSegments") or 0)
    effective_total = max(0, total_segments - suppressed_noise)
    if average < QUALITY_PUBLISH_THRESHOLD:
        return False
    if min_score < QUALITY_REVIEW_THRESHOLD:
        return False
    if effective_total > 0 and publishable == 0:
        return False
    if failed > 0:
        return False
    if effective_total > 0 and publishable < max(1, effective_total - review):
        return False
    return True


def _quality_is_soft_publishable(summary: dict[str, Any], total_segments: int) -> bool:
    average = float(summary.get("averageScore") or 0)
    min_score = float(summary.get("minScore") or 0)
    failed = int(summary.get("failedSegments") or 0)
    publishable = int(summary.get("publishableSegments") or 0)
    suppressed_noise = int(summary.get("suppressedNoiseSegments") or 0)
    effective_total = max(0, total_segments - suppressed_noise)
    if effective_total <= 0:
        return False
    if average < 92:
        return False
    if min_score < 55:
        return False
    if failed <= 0 or failed > 2:
        return False
    if publishable < max(1, effective_total - failed):
        return False
    return (failed / max(1, effective_total)) <= 0.06


def _quality_is_local_non_ai_publishable(summary: dict[str, Any], total_segments: int) -> bool:
    average = float(summary.get("averageScore") or 0)
    min_score = float(summary.get("minScore") or 0)
    failed = int(summary.get("failedSegments") or 0)
    publishable = int(summary.get("publishableSegments") or 0)
    review = int(summary.get("reviewSegments") or 0)
    suppressed_noise = int(summary.get("suppressedNoiseSegments") or 0)
    effective_total = max(0, total_segments - suppressed_noise)
    if effective_total <= 0:
        return False
    if average < 90:
        return False
    if min_score < 25:
        return False
    if failed <= 0:
        return False
    if failed > max(3, int(math.ceil(effective_total * 0.05))):
        return False
    if publishable < int(math.floor(effective_total * 0.8)):
        return False
    if review > max(12, int(math.ceil(effective_total * 0.2))):
        return False
    return True


def _quality_summary_rank(summary: dict[str, Any] | None, total_segments: int) -> tuple[int, int, int, int, float, float]:
    if not summary:
        return (0, 0, -999999, -999999, 0.0, 0.0)

    publishable = 1 if _quality_is_publishable(summary, total_segments) else 0
    soft_publishable = 1 if _quality_is_soft_publishable(summary, total_segments) else 0
    failed = int(summary.get("failedSegments") or 0)
    publishable_segments = int(summary.get("publishableSegments") or 0)
    average = float(summary.get("averageScore") or 0)
    min_score = float(summary.get("minScore") or 0)
    return (
        publishable,
        soft_publishable,
        -failed,
        publishable_segments,
        average,
        min_score,
    )


def _path_exists(path: str | None) -> bool:
    return bool(path and Path(path).exists())


def _load_json_document(path: str | None) -> dict[str, Any] | None:
    if not _path_exists(path):
        return None

    try:
        decoded = json.loads(Path(path).read_text(encoding="utf-8"))
    except Exception:
        return None

    return decoded if isinstance(decoded, dict) else None


def _validate_scene_map_release_labels(scene_map_path: str | None) -> list[str]:
    document = _load_json_document(scene_map_path)
    if scene_map_path and document is None:
        return ["invalid_scene_map_json"]

    allowed_themes = {
        "default",
        "chorus",
        "emphasis",
        "whisper",
        "shout",
        "duet",
        "tension",
        "comedic",
        "instrumental",
    }
    allowed_labels = {item.strip().lower() for item in STYLE_LABELS}
    reasons: list[str] = []

    for index, scene in enumerate((document or {}).get("scenes") or []):
        if not isinstance(scene, dict):
            reasons.append(f"scene_map_invalid_entry:{index}")
            continue

        theme = str(scene.get("theme") or "").strip().lower()
        label = str(scene.get("styleLabel") or "").strip().lower()

        if theme and theme not in allowed_themes:
            reasons.append(f"scene_map_invalid_theme:{index}:{theme}")
        if label and label not in allowed_labels:
            reasons.append(f"scene_map_invalid_style_label:{index}:{label}")

    return reasons


def _validate_karaoke_plan_release_labels(karaoke_plan_path: str | None) -> list[str]:
    document = _load_json_document(karaoke_plan_path)
    if karaoke_plan_path and document is None:
        return ["invalid_karaoke_plan_json"]

    allowed_labels = {item.strip().lower() for item in STYLE_LABELS}
    reasons: list[str] = []

    for index, scene in enumerate((document or {}).get("sceneSegments") or []):
        if not isinstance(scene, dict):
            reasons.append(f"karaoke_plan_invalid_scene_segment:{index}")
            continue

        label = str(scene.get("label") or "").strip().lower()
        if label and label not in allowed_labels:
            reasons.append(f"karaoke_plan_invalid_scene_label:{index}:{label}")

    for index, event in enumerate((document or {}).get("events") or []):
        if not isinstance(event, dict):
            reasons.append(f"karaoke_plan_invalid_event:{index}")
            continue

        label = str(event.get("styleLabel") or "").strip().lower()
        if label and label not in allowed_labels:
            reasons.append(f"karaoke_plan_invalid_style_label:{index}:{label}")

    return reasons


def _build_release_gate(
    *,
    task: str,
    content_mode: str,
    style_source: str | None,
    translation_statuses: dict[str, Any],
    render_preview_path: str | None,
    video_muxed_path: str | None,
    scene_map_path: str | None,
    speaker_map_path: str | None,
    karaoke_plan_path: str | None,
    lyric_alignment_path: str | None,
) -> dict[str, Any]:
    reasons: list[str] = []
    critical_fallbacks: list[str] = []

    if style_source != "ai_plan":
        reasons.append("style_source_not_ai_plan")
        critical_fallbacks.append("local_preset")

    published_languages = []
    for language, state in (translation_statuses or {}).items():
        if str((state or {}).get("status") or "").lower() != "published":
            continue
        published_languages.append(language)
        quality = (state or {}).get("quality") or {}
        if bool(quality.get("softPublished")):
            reasons.append(f"{language}:soft_published")
        if int(quality.get("failedSegments") or 0) > 0:
            reasons.append(f"{language}:failed_segments")
        if float(quality.get("minScore") or 0) < QUALITY_REVIEW_THRESHOLD:
            reasons.append(f"{language}:min_score_below_threshold")

    if task == "translate" and not published_languages:
        reasons.append("no_published_languages")

    artifact_checks = {
        "renderPreview": _path_exists(render_preview_path),
        "videoMuxed": _path_exists(video_muxed_path),
        "sceneMap": _path_exists(scene_map_path),
        "speakerMap": _path_exists(speaker_map_path),
        "karaokePlan": _path_exists(karaoke_plan_path),
        "lyricAlignment": _path_exists(lyric_alignment_path),
    }

    if not artifact_checks["renderPreview"]:
        reasons.append("missing_render_preview")
    if not artifact_checks["videoMuxed"]:
        reasons.append("missing_video_muxed")
    if not artifact_checks["sceneMap"]:
        reasons.append("missing_scene_map")
    if not artifact_checks["speakerMap"]:
        reasons.append("missing_speaker_map")

    reasons.extend(_validate_scene_map_release_labels(scene_map_path))

    if _normalize_content_mode(content_mode) == "anime_song":
        if not artifact_checks["karaokePlan"]:
            reasons.append("missing_karaoke_plan")
        if not artifact_checks["lyricAlignment"]:
            reasons.append("missing_lyric_alignment")
        reasons.extend(_validate_karaoke_plan_release_labels(karaoke_plan_path))

    if "missing_render_preview" in reasons:
        critical_fallbacks.append("missing_render_preview")
    if "missing_karaoke_plan" in reasons:
        critical_fallbacks.append("missing_karaoke_plan")
    if any(reason.endswith(":soft_published") for reason in reasons):
        critical_fallbacks.append("soft_quality_gate")
    if any(reason.endswith(":failed_segments") for reason in reasons):
        critical_fallbacks.append("failed_segments")
    if any(reason.startswith("scene_map_invalid_") for reason in reasons):
        critical_fallbacks.append("invalid_scene_map_labels")
    if any(reason.startswith("karaoke_plan_invalid_") for reason in reasons):
        critical_fallbacks.append("invalid_karaoke_plan_labels")

    return {
        "ready": len(reasons) == 0,
        "contentMode": _normalize_content_mode(content_mode),
        "publishedLanguages": published_languages,
        "reasons": list(dict.fromkeys(reasons)),
        "criticalFallbacks": list(dict.fromkeys(critical_fallbacks)),
        "artifactChecks": artifact_checks,
    }


def _rescue_low_quality_segments(
    *,
    source_segments: list[dict[str, Any]],
    translated_segments: list[dict[str, Any]],
    rescue_segments: list[dict[str, Any]] | None,
    source_language: str,
    target_language: str,
    threshold: int = QUALITY_REVIEW_THRESHOLD,
) -> tuple[list[dict[str, Any]], int]:
    if not rescue_segments or len(rescue_segments) != len(translated_segments):
        return translated_segments, 0

    rescued = _clone_segments(translated_segments)
    replacements = 0

    for index, (source_item, current_item, rescue_item) in enumerate(
        zip(source_segments, translated_segments, rescue_segments)
    ):
        current_score = _segment_quality_score(current_item)
        if current_score >= threshold:
            continue

        rescue_text = _sanitize_translated_text(
            _segment_text(source_item),
            _segment_text(rescue_item),
        )
        if not rescue_text or rescue_text == _segment_text(current_item):
            continue

        candidate_segment = dict(current_item)
        candidate_segment["text"] = rescue_text
        candidate_score = _score_translation_segments(
            source_segments=[source_item],
            translated_segments=[candidate_segment],
            source_language=source_language,
            target_language=target_language,
        )[0]

        if candidate_score.score <= current_score:
            continue

        rescued[index]["text"] = rescue_text
        rescued[index]["_qualityScore"] = candidate_score.score
        rescued[index]["_qualityReasons"] = candidate_score.reasons
        replacements += 1

    if replacements == 0:
        return translated_segments, 0

    rescued = _apply_timing_fit(_sanitize_translated_segments(source_segments, rescued))
    _score_translation_segments(
        source_segments=source_segments,
        translated_segments=rescued,
        source_language=source_language,
        target_language=target_language,
    )
    return rescued, replacements


def _retranslate_low_quality_segments_with_ollama(
    *,
    source_segments: list[dict[str, Any]],
    translated_segments: list[dict[str, Any]],
    reference_segments: list[dict[str, Any]] | None,
    source_language: str,
    target_language: str,
    song_segment_indices: set[int] | None,
    model: str,
    prompt_hint: str | None,
    temperature: float,
    top_p: float,
    num_predict: int,
    chunk_chars: int,
    batch_size: int,
    timeout_seconds: int,
    content_mode: str,
) -> tuple[list[dict[str, Any]], int]:
    musical_indices = set(song_segment_indices or set())
    critical_revision_reasons = {
        "transliteration_artifact",
        "weak_language_signal",
        "unchanged",
        "empty",
        "non_speech_noise",
        "invented_from_noise",
        "ai_review_reject",
    }

    target_indices: list[int] = []
    for index, current_item in enumerate(translated_segments):
        score = _segment_quality_score(current_item)
        issues = current_item.get("_qualityReasons") or []
        is_musical = index in musical_indices or content_mode == "anime_song"
        threshold = QUALITY_PUBLISH_THRESHOLD if is_musical else QUALITY_REVIEW_THRESHOLD
        if score < threshold or any(reason in critical_revision_reasons for reason in issues):
            target_indices.append(index)

    if not target_indices:
        return translated_segments, 0

    source_subset = [dict(source_segments[index]) for index in target_indices]
    reference_subset = (
        [dict(reference_segments[index]) for index in target_indices]
        if reference_segments and len(reference_segments) >= len(source_segments)
        else None
    )
    subset_song_indices = {
        subset_index
        for subset_index, original_index in enumerate(target_indices)
        if original_index in musical_indices
    }

    retranslated_subset = _translate_segments_with_ollama(
        segments=source_subset,
        source_language=source_language,
        target_language=target_language,
        reference_segments=reference_subset,
        song_segment_indices=subset_song_indices,
        model=model,
        prompt_hint=prompt_hint,
        temperature=temperature,
        top_p=top_p,
        num_predict=num_predict,
        chunk_chars=chunk_chars,
        batch_size=batch_size,
        timeout_seconds=timeout_seconds,
    )

    rescued = _clone_segments(translated_segments)
    replacements = 0

    for subset_index, original_index in enumerate(target_indices):
        source_item = source_segments[original_index]
        current_item = translated_segments[original_index]
        candidate_item = dict(current_item)
        candidate_text = _sanitize_translated_text(
            _segment_text(source_item),
            _segment_text(retranslated_subset[subset_index]) if subset_index < len(retranslated_subset) else "",
        )
        if not candidate_text or candidate_text == _segment_text(current_item):
            continue

        candidate_item["text"] = candidate_text
        candidate_score = _score_translation_segments(
            source_segments=[source_item],
            translated_segments=[candidate_item],
            source_language=source_language,
            target_language=target_language,
        )[0]
        current_score = _segment_quality_score(current_item)
        if candidate_score.score <= current_score:
            continue

        rescued[original_index]["text"] = candidate_text
        rescued[original_index]["_qualityScore"] = candidate_score.score
        rescued[original_index]["_qualityReasons"] = candidate_score.reasons
        replacements += 1

    if replacements == 0:
        return translated_segments, 0

    rescued = _apply_timing_fit(_sanitize_translated_segments(source_segments, rescued))
    _score_translation_segments(
        source_segments=source_segments,
        translated_segments=rescued,
        source_language=source_language,
        target_language=target_language,
    )
    return rescued, replacements


def _merge_prompt_with_context(prompt_hint: str, references: list[dict[str, str]]) -> str:
    prompt = (prompt_hint or "").strip()
    if not references:
        return prompt

    context_lines = []
    for reference in references[:3]:
        url = reference.get("url", "")
        excerpt = reference.get("excerpt", "")
        if excerpt:
            context_lines.append(f"Fonte: {url}\nResumo: {excerpt[:800]}")

    if not context_lines:
        return prompt

    suffix = "\n\nContexto externo opcional:\n" + "\n\n".join(context_lines)
    return f"{prompt}{suffix}" if prompt else suffix.strip()



def _sample_video_frames(source_file: Path, sample_seconds: int) -> list[str]:
    if not _is_video_file(source_file):
        return []
    temp_dir = Path(tempfile.mkdtemp(prefix="hub_ia_frames_"))
    duration = _probe_duration_seconds(source_file) or 0.0
    if duration <= 0:
        return []
    max_points = 3
    if duration >= 180:
        max_points = 2
    if duration >= 900:
        max_points = 1
    points = sorted(
        {
            max(1, int(duration * 0.18)),
            max(1, int(duration * 0.5)),
            max(1, int(duration * 0.82)),
        }
    )
    images: list[str] = []
    try:
        for index, second in enumerate(points[:max_points]):
            target = temp_dir / f"frame_{index:02d}.jpg"
            command = [
                _ffmpeg_path(),
                "-y",
                "-ss",
                str(second),
                "-i",
                str(source_file),
                "-vf",
                "scale=768:-2",
                "-frames:v",
                "1",
                "-q:v",
                "5",
                str(target),
            ]
            result = _run_command(command, timeout=max(60, sample_seconds * 10))
            if result.returncode == 0 and target.exists():
                images.append(base64.b64encode(target.read_bytes()).decode("ascii"))
    finally:
        shutil.rmtree(temp_dir, ignore_errors=True)
    return images


def _normalize_content_mode(value: str | None) -> str:
    normalized = (value or "episode").strip().lower()
    return normalized if normalized in ALLOWED_CONTENT_MODES else "episode"


def _normalize_speaker_style_mode(value: str | None) -> str:
    normalized = (value or "heuristic").strip().lower()
    return normalized if normalized in ALLOWED_SPEAKER_STYLE_MODES else "heuristic"


def _normalize_style_intensity(value: str | None) -> str:
    normalized = (value or "thematic").strip().lower()
    return normalized if normalized in ALLOWED_STYLE_INTENSITIES else "thematic"


def _normalize_rendered_preview_mode(value: str | None) -> str:
    normalized = (value or "fast").strip().lower()
    return normalized if normalized in ALLOWED_RENDERED_PREVIEW_MODES else "fast"


def _normalize_anime_song_layout_mode(
    value: str | None,
    content_mode: str,
    *,
    has_song_blocks: bool = False,
) -> str:
    normalized = (value or "off").strip().lower()
    if content_mode == "anime_song" or has_song_blocks:
        return (
            normalized
            if normalized in ALLOWED_ANIME_SONG_LAYOUT_MODES and normalized != "off"
            else "romaji_top_translation_bottom"
        )
    return "off"


def _normalize_karaoke_granularity(
    value: str | None,
    content_mode: str,
    *,
    has_song_blocks: bool = False,
) -> str:
    normalized = (value or "off").strip().lower()
    if content_mode != "anime_song" and not has_song_blocks:
        return "off"
    if normalized in ALLOWED_KARAOKE_GRANULARITIES and normalized != "off":
        return normalized
    return "syllable"


def _detect_content_mode(
    requested_mode: str,
    source_file: Path,
    prompt_hint: str | None,
    context_hints: dict[str, Any] | None,
) -> ContentModeDecision:
    requested = _normalize_content_mode(requested_mode)
    if requested in {"episode", "anime_song"}:
        return ContentModeDecision(
            requested=requested,
            detected=requested,
            confidence=1.0,
            reason="Modo explícito selecionado pelo usuário.",
        )

    chapters = _probe_chapters(source_file)
    if chapters:
        chapter_song_blocks = _extract_song_blocks_from_chapters(chapters)
        musical_chapters = len(chapter_song_blocks)
        narrative_chapters = max(0, len(chapters) - musical_chapters)

        if musical_chapters > 0 and narrative_chapters > 0:
            return ContentModeDecision(
                requested=requested,
                detected="episode",
                confidence=0.96,
                reason="Capítulos indicam episódio com blocos musicais e bloco narrativo.",
            )

        if musical_chapters > 0 and narrative_chapters == 0:
            return ContentModeDecision(
                requested=requested,
                detected="anime_song",
                confidence=0.92,
                reason="Capítulos indicam arquivo musical.",
            )

        if narrative_chapters > 0:
            return ContentModeDecision(
                requested=requested,
                detected="episode",
                confidence=0.9,
                reason="Capítulos indicam arquivo narrativo sem blocos musicais dedicados.",
            )

    hints = context_hints or {}
    searchable = " ".join(
        [
            source_file.stem,
            str(hints.get("title") or ""),
            str(hints.get("artist") or ""),
            str(hints.get("series") or ""),
            str(hints.get("episode") or ""),
            prompt_hint or "",
        ]
    ).lower()
    episode_markers = [
        r"\bepisode\b",
        r"\bepisodio\b",
        r"\bepisódio\b",
        r"(^|[^a-z])ep\s*\d+([^a-z]|$)",
        r"(^|[^a-z])e\d{1,3}([^a-z]|$)",
    ]
    explicit_episode_hint = bool(hints.get("episode")) or any(
        re.search(pattern, searchable) for pattern in episode_markers
    )

    song_patterns = [
        r"\bopening\b",
        r"\bending\b",
        r"\bkaraoke\b",
        r"\bsong\b",
        r"\bmusic\b",
        r"\btheme\b",
        r"\blyrics?\b",
        r"\bncop\b",
        r"\bnced\b",
        r"(^|[^a-z])op\d*([^a-z]|$)",
        r"(^|[^a-z])ed\d*([^a-z]|$)",
    ]
    if explicit_episode_hint and any(re.search(pattern, searchable) for pattern in song_patterns):
        return ContentModeDecision(
            requested=requested,
            detected="episode",
            confidence=0.82,
            reason="Hints indicam episódio com blocos musicais internos, sem promover o arquivo inteiro para anime_song.",
        )

    if any(re.search(pattern, searchable) for pattern in song_patterns):
        return ContentModeDecision(
            requested=requested,
            detected="anime_song",
            confidence=0.84,
            reason="Palavras-chave de opening/ending/música detectadas.",
        )

    if hints.get("artist") or (hints.get("title") and not hints.get("episode")):
        return ContentModeDecision(
            requested=requested,
            detected="anime_song",
            confidence=0.72,
            reason="Hints de música/título foram detectadas.",
        )

    return ContentModeDecision(
        requested=requested,
        detected="episode",
        confidence=0.58,
        reason="Nenhum marcador forte de música/opening foi detectado.",
    )


def _classify_song_block_title(title: str) -> str | None:
    normalized = (title or "").strip().lower()
    if not normalized:
        return None
    if re.search(r"\b(abertura|opening|op|ncop)\b", normalized):
        return "opening"
    if re.search(r"\b(encerramento|ending|ed|nced)\b", normalized):
        return "ending"
    if re.search(r"\b(insert song|song|music|karaoke|theme)\b", normalized):
        return "insert_song"
    return None


def _extract_song_blocks_from_chapters(
    chapters: list[dict[str, Any]],
) -> list[dict[str, Any]]:
    blocks: list[dict[str, Any]] = []
    for chapter in chapters:
        block_type = _classify_song_block_title(str(chapter.get("title") or ""))
        if not block_type:
            continue
        blocks.append(
            {
                "type": block_type,
                "label": block_type,
                "title": chapter.get("title"),
                "start": float(chapter.get("start") or 0.0),
                "end": float(chapter.get("end") or 0.0),
                "durationSeconds": float(chapter.get("durationSeconds") or 0.0),
            }
        )
    return blocks


def _detect_song_blocks(
    *,
    source_file: Path,
    requested_mode: str,
    detected_mode: str,
    karaoke_requested: bool,
    prompt_hint: str | None,
    context_hints: dict[str, Any] | None,
) -> list[dict[str, Any]]:
    effective_requested = _normalize_content_mode(requested_mode)
    effective_detected = _normalize_content_mode(detected_mode)
    duration = _probe_duration_seconds(source_file) or 0.0

    if effective_requested != "anime_song" and not karaoke_requested:
        return []

    if effective_requested == "anime_song":
        return [
            {
                "type": "anime_song",
                "label": "anime_song",
                "start": 0.0,
                "end": round(duration, 3) if duration > 0 else None,
                "durationSeconds": round(duration, 3) if duration > 0 else None,
            }
        ]

    chapters = _probe_chapters(source_file)
    blocks = _extract_song_blocks_from_chapters(chapters)

    if blocks:
        return blocks

    if chapters:
        return []

    if effective_detected == "anime_song":
        return [
            {
                "type": "anime_song",
                "label": "anime_song",
                "start": 0.0,
                "end": round(duration, 3) if duration > 0 else None,
                "durationSeconds": round(duration, 3) if duration > 0 else None,
            }
        ]

    searchable = " ".join(
        [
            source_file.stem,
            str((context_hints or {}).get("title") or ""),
            str((context_hints or {}).get("artist") or ""),
            str((context_hints or {}).get("series") or ""),
            str((context_hints or {}).get("episode") or ""),
            prompt_hint or "",
        ]
    ).lower()
    episode_markers = [
        r"\bepisode\b",
        r"\bepisodio\b",
        r"\bepisódio\b",
        r"(^|[^a-z])ep\s*\d+([^a-z]|$)",
        r"(^|[^a-z])e\d{1,3}([^a-z]|$)",
    ]
    explicit_episode_hint = bool((context_hints or {}).get("episode")) or any(
        re.search(pattern, searchable) for pattern in episode_markers
    )
    if karaoke_requested and re.search(r"\b(ending|opening|theme|karaoke|song|music|ed|op)\b", searchable):
        if effective_detected == "episode" and explicit_episode_hint and duration >= 150.0:
            opening_end = min(95.0, duration)
            ending_start = max(opening_end, duration - 95.0)
            blocks: list[dict[str, Any]] = [
                {
                    "type": "opening",
                    "label": "opening",
                    "title": "Opening (heuristic)",
                    "start": 0.0,
                    "end": round(opening_end, 3),
                    "durationSeconds": round(opening_end, 3),
                }
            ]
            if ending_start < duration:
                blocks.append(
                    {
                        "type": "ending",
                        "label": "ending",
                        "title": "Ending (heuristic)",
                        "start": round(ending_start, 3),
                        "end": round(duration, 3),
                        "durationSeconds": round(duration - ending_start, 3),
                    }
                )
            return blocks
        return [
            {
                "type": "anime_song",
                "label": "anime_song",
                "start": 0.0,
                "end": round(duration, 3) if duration > 0 else None,
                "durationSeconds": round(duration, 3) if duration > 0 else None,
            }
        ]

    return []


def _segment_overlaps_song_block(
    segment: dict[str, Any],
    song_blocks: list[dict[str, Any]],
) -> dict[str, Any] | None:
    start = float(segment.get("start") or 0.0)
    end = max(start, float(segment.get("end") or start))
    for block in song_blocks:
        block_start = float(block.get("start") or 0.0)
        block_end = max(block_start, float(block.get("end") or block_start))
        overlap = max(0.0, min(end, block_end) - max(start, block_start))
        if overlap >= 0.15:
            return block
    return None


def _build_song_segment_index_set(
    segments: list[dict[str, Any]],
    song_blocks: list[dict[str, Any]] | None,
) -> set[int]:
    if not segments or not song_blocks:
        return set()

    indices: set[int] = set()
    for index, segment in enumerate(segments):
        if _segment_overlaps_song_block(segment, song_blocks):
            indices.add(index)
    return indices


def _romanize_japanese_text(text: str) -> str:
    cleaned = _clean_subtitle_text(text)
    if not cleaned:
        return ""

    if not re.search(r"[\u3040-\u30ff\u3400-\u9fff]", cleaned):
        return cleaned

    kakasi = _import_pykakasi()
    if kakasi is None:
        return cleaned

    try:
        converter = kakasi()
        parts = []
        for item in converter.convert(cleaned):
            parts.append(
                str(item.get("hepburn") or item.get("kana") or item.get("orig") or "").strip()
            )
        romanized = re.sub(r"\s+", " ", " ".join(part for part in parts if part)).strip()
        return romanized or cleaned
    except Exception:
        return cleaned


def _tokenize_karaoke_words(text: str) -> list[str]:
    cleaned = _clean_subtitle_text(text).replace("\\N", " ").strip()
    if not cleaned:
        return []
    return re.findall(r"[A-Za-zÀ-ÿ0-9']+|[\u3040-\u30ff\u3400-\u9fff]+|[^\s]", cleaned)


def _split_romaji_syllables(token: str) -> list[str]:
    cleaned = re.sub(r"[^A-Za-z0-9']", "", token or "").strip()
    if not cleaned:
        return []
    if len(cleaned) <= 3:
        return [token]

    parts = re.findall(
        r"[^aeiouyAEIOUY]*[aeiouyAEIOUY]+(?:n(?![aeiouyAEIOUY]))?[^aeiouyAEIOUY]?",
        cleaned,
    )
    if len(parts) <= 1:
        return [token]
    return parts


def _split_karaoke_units(text: str, granularity: str) -> list[str]:
    words = _tokenize_karaoke_words(text)
    if granularity != "syllable":
        return words

    expanded: list[str] = []
    for token in words:
        if re.fullmatch(r"[^\w\s]", token):
            expanded.append(token)
            continue
        syllables = _split_romaji_syllables(token)
        if syllables:
            expanded.extend(syllables)
        else:
            expanded.append(token)
    return expanded or words


def _karaoke_token_weight(token: str) -> int:
    alnum = re.sub(r"[^A-Za-zÀ-ÿ0-9\u3040-\u30ff\u3400-\u9fff]", "", token or "")
    return max(1, len(alnum) or 1)


def _build_karaoke_tokens(
    text: str,
    *,
    start: float,
    end: float,
    granularity: str,
) -> list[dict[str, Any]]:
    units = [unit for unit in _split_karaoke_units(text, granularity) if unit.strip()]
    if not units:
        return []

    start_value = float(start or 0.0)
    end_value = max(start_value + 0.1, float(end or start_value))
    total_duration_cs = max(1, int(round((end_value - start_value) * 100)))
    weights = [_karaoke_token_weight(unit) for unit in units]
    total_weight = max(1, sum(weights))

    durations = [max(1, int(round(total_duration_cs * (weight / total_weight)))) for weight in weights]
    delta = total_duration_cs - sum(durations)
    if delta != 0:
        durations[-1] = max(1, durations[-1] + delta)

    cursor_cs = int(round(start_value * 100))
    tokens: list[dict[str, Any]] = []
    for unit, duration_cs in zip(units, durations):
        token_start_cs = cursor_cs
        token_end_cs = cursor_cs + duration_cs
        tokens.append(
            {
                "text": unit,
                "start": round(token_start_cs / 100.0, 3),
                "end": round(token_end_cs / 100.0, 3),
                "durationCs": max(1, duration_cs),
            }
        )
        cursor_cs = token_end_cs

    if tokens:
        tokens[-1]["end"] = round(end_value, 3)
        tokens[-1]["durationCs"] = max(1, int(round((end_value * 100) - ((tokens[-1]["start"]) * 100))))
    return tokens


def _build_ass_karaoke_text(tokens: list[dict[str, Any]]) -> str:
    if not tokens:
        return ""

    parts: list[str] = []
    pending_space = False
    for token in tokens:
        text = str(token.get("text") or "").strip()
        if not text:
            continue
        duration_cs = max(1, int(token.get("durationCs") or 1))
        if pending_space and not re.fullmatch(r"[^\w\s]", text):
            parts.append(" ")
        parts.append(r"{\kf" + str(duration_cs) + "}" + _ass_escape(text))
        pending_space = not re.fullmatch(r"[^\w\s]", text)
    return "".join(parts).strip()


def _build_speaker_spans(segments: list[dict[str, Any]]) -> list[dict[str, Any]]:
    spans: list[dict[str, Any]] = []
    for index, segment in enumerate(segments):
        speaker_id = str(segment.get("speakerId") or "speaker_1")
        spans.append(
            {
                "index": index,
                "speakerId": speaker_id,
                "placement": str(segment.get("speakerPlacement") or "bottom"),
                "accent": str(segment.get("speakerAccent") or "default"),
                "start": float(segment.get("start") or 0.0),
                "end": float(segment.get("end") or 0.0),
                "text": _segment_text(segment),
            }
        )
    return spans


def _annotate_overlap_speaker_layout(
    segments: list[dict[str, Any]],
    speaker_style_mode: str,
) -> list[dict[str, Any]]:
    if speaker_style_mode == "off":
        return [dict(item) for item in segments]

    annotated = [dict(item) for item in segments]
    active_anchor = 0
    speaker_cursor = 1
    for index, segment in enumerate(annotated):
        segment["speakerPlacement"] = "bottom"
        segment["speakerAccent"] = "default"
        segment["speakerId"] = segment.get("speakerId") or f"speaker_{speaker_cursor}"
        if index == 0:
            continue

        previous = annotated[active_anchor]
        previous_end = float(previous.get("end") or 0.0)
        current_start = float(segment.get("start") or 0.0)
        if current_start >= previous_end:
            active_anchor = index
            continue

        previous["speakerPlacement"] = previous.get("speakerPlacement") or "bottom"
        previous["speakerAccent"] = previous.get("speakerAccent") or "primary"
        previous["speakerId"] = previous.get("speakerId") or "speaker_1"
        segment["speakerPlacement"] = "top"
        segment["speakerAccent"] = "secondary"
        segment["speakerId"] = f"speaker_{2 if str(previous.get('speakerId') or 'speaker_1') == 'speaker_1' else 1}"
    return annotated


def _prepare_render_segments(
    *,
    source_segments: list[dict[str, Any]],
    rendered_segments: list[dict[str, Any]],
    content_mode: str,
    anime_song_layout_mode: str,
    speaker_style_mode: str,
    karaoke_granularity: str,
    song_blocks: list[dict[str, Any]] | None = None,
) -> list[dict[str, Any]]:
    prepared = _annotate_overlap_speaker_layout(rendered_segments, speaker_style_mode)
    effective_content_mode = _normalize_content_mode(content_mode)

    has_song_blocks = bool(song_blocks)
    combined: list[dict[str, Any]] = []
    for index, segment in enumerate(prepared):
        clone = dict(segment)
        source_segment = source_segments[index] if index < len(source_segments) else segment
        song_block = _segment_overlaps_song_block(source_segment, song_blocks or [])
        is_song_segment = (
            effective_content_mode == "anime_song"
            or (anime_song_layout_mode != "off" and song_block is not None)
        )
        clone["contentCategory"] = "anime_song" if is_song_segment else "episode_dialogue"
        clone["songBlockType"] = song_block.get("type") if song_block else None
        clone["songBlockTitle"] = song_block.get("title") if song_block else None
        if not is_song_segment or anime_song_layout_mode == "off":
            combined.append(clone)
            continue

        source_text = _segment_text(source_segment)
        clone["romajiText"] = _romanize_japanese_text(source_text)
        clone["translationText"] = _segment_text(segment)
        clone["songLayout"] = anime_song_layout_mode
        clone["karaokeGranularity"] = karaoke_granularity
        clone["romajiTokens"] = _build_karaoke_tokens(
            clone["romajiText"],
            start=float(clone.get("start") or 0.0),
            end=float(clone.get("end") or 0.0),
            granularity=karaoke_granularity,
        )
        clone["translationTokens"] = _build_karaoke_tokens(
            clone["translationText"],
            start=float(clone.get("start") or 0.0),
            end=float(clone.get("end") or 0.0),
            granularity="word" if karaoke_granularity == "off" else karaoke_granularity,
        )
        combined.append(clone)
    return combined


def _build_karaoke_plan(
    *,
    source_segments: list[dict[str, Any]],
    translated_segments: list[dict[str, Any]],
    layout_mode: str,
    karaoke_granularity: str,
    speaker_style_mode: str,
) -> dict[str, Any]:
    normalized_layout_mode = _normalize_anime_song_layout_mode(
        layout_mode,
        "anime_song",
    )
    normalized_granularity = _normalize_karaoke_granularity(
        karaoke_granularity,
        "anime_song",
    )
    musical_indexes = [
        index
        for index, segment in enumerate(translated_segments)
        if str(segment.get("contentCategory") or "").strip().lower() == "anime_song"
        or str(segment.get("songLayout") or "").strip().lower() != ""
    ]
    if not musical_indexes and (
        normalized_layout_mode == "romaji_top_translation_bottom"
        or normalized_granularity != "off"
    ):
        musical_indexes = list(range(min(len(source_segments), len(translated_segments))))
    scene_segments: list[dict[str, Any]] = []
    current_scene: dict[str, Any] | None = None
    musical_segments = [translated_segments[index] for index in musical_indexes]
    speaker_spans = _build_speaker_spans(musical_segments)

    for scene_index, index in enumerate(musical_indexes):
        segment = translated_segments[index]
        label = str(segment.get("styleLabel") or "default")
        start = float(segment.get("start") or 0.0)
        end = float(segment.get("end") or 0.0)
        if current_scene is None or current_scene["label"] != label or start - float(current_scene["end"]) > 3.0:
            current_scene = {
                "sceneIndex": scene_index,
                "label": label,
                "start": start,
                "end": end,
                "segmentIndexes": [index],
            }
            scene_segments.append(current_scene)
        else:
            current_scene["end"] = end
            current_scene["segmentIndexes"].append(index)

    return {
        "layoutMode": normalized_layout_mode,
        "granularity": normalized_granularity,
        "speakerModeApplied": speaker_style_mode,
        "sceneSegments": scene_segments,
        "speakerSpans": speaker_spans,
        "events": [
            {
                "index": index,
                "start": float(source.get("start") or 0.0),
                "end": float(source.get("end") or 0.0),
                "romaji": _romanize_japanese_text(_segment_text(source)),
                "translation": _segment_text(translated_segments[index]) if index < len(translated_segments) else "",
                "styleLabel": str(translated_segments[index].get("styleLabel") or "default")
                if index < len(translated_segments)
                else "default",
                "speakerId": str(translated_segments[index].get("speakerId") or "speaker_1")
                if index < len(translated_segments)
                else "speaker_1",
                "romajiTokens": _build_karaoke_tokens(
                    _romanize_japanese_text(_segment_text(source)),
                    start=float(source.get("start") or 0.0),
                    end=float(source.get("end") or 0.0),
                    granularity=karaoke_granularity,
                ),
                "translationTokens": _build_karaoke_tokens(
                    _segment_text(translated_segments[index]) if index < len(translated_segments) else "",
                    start=float(source.get("start") or 0.0),
                    end=float(source.get("end") or 0.0),
                    granularity="word" if karaoke_granularity == "off" else karaoke_granularity,
                ),
            }
            for index, source in enumerate(source_segments)
            if index in musical_indexes
        ],
    }


def _build_lyric_alignment_report(
    karaoke_plan: dict[str, Any],
) -> dict[str, Any]:
    events = karaoke_plan.get("events") or []
    return {
        "granularity": karaoke_plan.get("granularity") or "off",
        "layoutMode": karaoke_plan.get("layoutMode") or "off",
        "eventCount": len(events),
        "speakerModeApplied": karaoke_plan.get("speakerModeApplied") or "off",
        "events": [
            {
                "index": item.get("index"),
                "start": item.get("start"),
                "end": item.get("end"),
                "romajiTokens": item.get("romajiTokens") or [],
                "translationTokens": item.get("translationTokens") or [],
            }
            for item in events
        ],
    }


def _build_voice_analysis(
    *,
    source_segments: list[dict[str, Any]],
    speaker_style_mode_requested: str,
    diarization_available: bool,
) -> tuple[dict[str, Any], str, str]:
    normalized_mode = _normalize_speaker_style_mode(speaker_style_mode_requested)
    if normalized_mode == "off":
        return (
            {
                "modeRequested": normalized_mode,
                "modeApplied": "off",
                "source": "disabled",
                "speakerCount": 0,
                "overlapCount": 0,
                "spans": [],
            },
            "off",
            "disabled",
        )

    mode_applied = normalized_mode if normalized_mode != "advanced" or diarization_available else "heuristic"
    source = "diarization" if mode_applied == "advanced" else "heuristic_overlap_layout"
    annotated = _annotate_overlap_speaker_layout(source_segments, mode_applied)
    spans = _build_speaker_spans(annotated)
    overlap_count = 0
    for index in range(1, len(annotated)):
        previous = annotated[index - 1]
        current = annotated[index]
        if float(current.get("start") or 0.0) < float(previous.get("end") or 0.0):
            overlap_count += 1

    speaker_ids = {
        str(item.get("speakerId") or "").strip()
        for item in annotated
        if str(item.get("speakerId") or "").strip()
    }
    return (
        {
            "modeRequested": normalized_mode,
            "modeApplied": mode_applied,
            "source": source,
            "speakerCount": len(speaker_ids),
            "overlapCount": overlap_count,
            "spans": spans,
        },
        mode_applied,
        source,
    )


def _build_scene_map(
    *,
    segments: list[dict[str, Any]],
    content_mode: str,
    voice_analysis: dict[str, Any] | None = None,
) -> tuple[dict[str, Any], str]:
    if not segments:
        return (
            {
                "source": "timing_style_blocks",
                "contentMode": _normalize_content_mode(content_mode),
                "sceneCount": 0,
                "scenes": [],
            },
            "timing_style_blocks",
        )

    scenes: list[dict[str, Any]] = []
    current_scene: dict[str, Any] | None = None
    for index, segment in enumerate(segments):
        label = str(segment.get("styleLabel") or "default")
        start = float(segment.get("start") or 0.0)
        end = float(segment.get("end") or 0.0)
        placement = str(segment.get("speakerPlacement") or "bottom")
        speaker_id = str(segment.get("speakerId") or "speaker_1")
        overlap = placement == "top"
        theme = label
        if overlap and label == "default":
            theme = "duet"

        should_split = (
            current_scene is None
            or current_scene["theme"] != theme
            or start - float(current_scene["end"]) > 3.25
        )
        if should_split:
            current_scene = {
                "sceneIndex": len(scenes),
                "theme": theme,
                "styleLabel": label,
                "start": start,
                "end": end,
                "segmentIndexes": [index],
                "speakerIds": [speaker_id],
                "hasOverlap": overlap,
            }
            scenes.append(current_scene)
        else:
            current_scene["end"] = end
            current_scene["segmentIndexes"].append(index)
            if speaker_id not in current_scene["speakerIds"]:
                current_scene["speakerIds"].append(speaker_id)
            current_scene["hasOverlap"] = bool(current_scene["hasOverlap"] or overlap)

    source = "timing_style_blocks"
    return (
        {
            "source": source,
            "contentMode": _normalize_content_mode(content_mode),
            "sceneCount": len(scenes),
            "voiceAnalysisSource": (voice_analysis or {}).get("source"),
            "speakerModeApplied": (voice_analysis or {}).get("modeApplied"),
            "scenes": scenes,
        },
        source,
    )


STYLE_LABELS = ["default", "chorus", "emphasis", "whisper", "shout"]


def _normalize_ass_color(value: Any, fallback: str) -> str:
    raw = str(value or "").strip()
    if not raw:
        return fallback

    hex_only = re.sub(r"[^0-9A-Fa-f]", "", raw)
    if len(hex_only) == 6:
        rr, gg, bb = hex_only[0:2], hex_only[2:4], hex_only[4:6]
        return f"&H00{bb.upper()}{gg.upper()}{rr.upper()}"
    if len(hex_only) == 8:
        aa, rr, gg, bb = hex_only[0:2], hex_only[2:4], hex_only[4:6], hex_only[6:8]
        return f"&H{aa.upper()}{bb.upper()}{gg.upper()}{rr.upper()}"
    return fallback


def _ass_color_to_rgba(value: str) -> tuple[int, int, int, int]:
    normalized = _normalize_ass_color(value, "&H00F6F6F6")
    hex_only = re.sub(r"[^0-9A-Fa-f]", "", normalized).upper()
    if len(hex_only) != 8:
        return 246, 246, 246, 0
    alpha = int(hex_only[0:2], 16)
    blue = int(hex_only[2:4], 16)
    green = int(hex_only[4:6], 16)
    red = int(hex_only[6:8], 16)
    return red, green, blue, alpha


def _rgba_to_ass_color(red: int, green: int, blue: int, alpha: int = 0) -> str:
    return f"&H{alpha:02X}{blue:02X}{green:02X}{red:02X}"


def _mix_channel(source: int, target: int, ratio: float) -> int:
    return max(0, min(255, int(round(source + ((target - source) * ratio)))))


def _mix_ass_color(value: str, target_rgb: tuple[int, int, int], ratio: float, *, alpha: int | None = None) -> str:
    red, green, blue, base_alpha = _ass_color_to_rgba(value)
    return _rgba_to_ass_color(
        _mix_channel(red, target_rgb[0], ratio),
        _mix_channel(green, target_rgb[1], ratio),
        _mix_channel(blue, target_rgb[2], ratio),
        base_alpha if alpha is None else alpha,
    )


def _derive_style_palette(style: dict[str, Any]) -> dict[str, str]:
    base = _normalize_ass_color(style.get("primaryColour"), "&H00F6F6F6")
    outline = _normalize_ass_color(style.get("outlineColour"), "&H00101010")
    back = _normalize_ass_color(style.get("backColour"), "&H50000000")
    return {
        "defaultPrimary": base,
        "chorusPrimary": _mix_ass_color(base, (255, 225, 160), 0.22),
        "emphasisPrimary": _mix_ass_color(base, (255, 214, 110), 0.28),
        "whisperPrimary": _mix_ass_color(base, (174, 213, 255), 0.38, alpha=18),
        "shoutPrimary": _mix_ass_color(base, (255, 126, 102), 0.48),
        "defaultOutline": outline,
        "chorusOutline": _mix_ass_color(outline, (18, 24, 48), 0.18),
        "emphasisOutline": _mix_ass_color(outline, (34, 24, 18), 0.24),
        "whisperOutline": _mix_ass_color(outline, (20, 32, 52), 0.22),
        "shoutOutline": _mix_ass_color(outline, (58, 18, 18), 0.28),
        "back": back,
    }


def _sanitize_style_plan(style: dict[str, Any]) -> dict[str, Any]:
    sanitized = dict(style)
    sanitized["fontName"] = str(sanitized.get("fontName") or "Segoe UI").strip() or "Segoe UI"
    sanitized["fontSize"] = max(24, min(68, int(float(sanitized.get("fontSize", 36)))))
    sanitized["songFontSize"] = max(
        sanitized["fontSize"],
        min(74, int(float(sanitized.get("songFontSize", max(40, sanitized["fontSize"] + 4))))),
    )
    sanitized["outline"] = max(1.6, min(6.0, float(sanitized.get("outline", 3.2))))
    sanitized["shadow"] = max(0, min(2, int(float(sanitized.get("shadow", 0)))))
    sanitized["marginV"] = max(28, min(120, int(float(sanitized.get("marginV", 52)))))
    sanitized["alignment"] = 2
    sanitized["fadeInMs"] = max(0, min(220, int(float(sanitized.get("fadeInMs", 90)))))
    sanitized["fadeOutMs"] = max(0, min(260, int(float(sanitized.get("fadeOutMs", 120)))))
    sanitized["scaleIntro"] = max(100, min(125, int(float(sanitized.get("scaleIntro", 104)))))
    sanitized["primaryColour"] = _normalize_ass_color(sanitized.get("primaryColour"), "&H00F6F6F6")
    sanitized["outlineColour"] = _normalize_ass_color(sanitized.get("outlineColour"), "&H00101010")
    sanitized["backColour"] = _normalize_ass_color(sanitized.get("backColour"), "&H50000000")
    return sanitized


def _merge_style_plan_with_floor(base_style: dict[str, Any], candidate_style: dict[str, Any]) -> dict[str, Any]:
    base = _sanitize_style_plan(base_style)
    candidate = _sanitize_style_plan({**base, **candidate_style})
    candidate["fontSize"] = max(base["fontSize"], candidate["fontSize"])
    candidate["songFontSize"] = max(base["songFontSize"], candidate["songFontSize"])
    candidate["outline"] = max(max(1.6, base["outline"] - 0.3), candidate["outline"])
    candidate["marginV"] = max(max(28, base["marginV"] - 10), candidate["marginV"])
    candidate["scaleIntro"] = max(base["scaleIntro"], candidate["scaleIntro"])
    return candidate


def _apply_style_intensity(
    base_style: dict[str, Any],
    *,
    style_intensity: str,
    content_mode: str,
) -> dict[str, Any]:
    style = dict(base_style)
    normalized_intensity = _normalize_style_intensity(style_intensity)
    if normalized_intensity == "subtle":
        style["fontSize"] = max(28, int(float(style.get("fontSize", 36))) - 2)
        style["songFontSize"] = max(32, int(float(style.get("songFontSize", 40))) - 2)
        style["outline"] = max(2.0, float(style.get("outline", 3.2)) - 0.4)
        style["scaleIntro"] = max(100, int(float(style.get("scaleIntro", 104))) - 2)
    elif normalized_intensity == "expressive":
        style["fontSize"] = min(54, int(float(style.get("fontSize", 36))) + 3)
        style["songFontSize"] = min(62, int(float(style.get("songFontSize", 40))) + 6)
        style["outline"] = min(5.6, float(style.get("outline", 3.2)) + 0.6)
        style["scaleIntro"] = min(125, int(float(style.get("scaleIntro", 104))) + 6)

    if _normalize_content_mode(content_mode) == "anime_song":
        style["fontSize"] = min(60, int(float(style.get("fontSize", 36))) + 2)
        style["songFontSize"] = min(68, int(float(style.get("songFontSize", 40))) + 8)
        style["marginV"] = max(58, int(float(style.get("marginV", 52))) + 6)
        style["scaleIntro"] = min(125, int(float(style.get("scaleIntro", 104))) + 4)

    return _sanitize_style_plan(style)


def _heuristic_style_label(text: str) -> str:
    compact = (text or "").strip()
    if not compact:
        return "default"
    if "!!!" in compact or compact.count("!") >= 2:
        return "shout"
    if compact.startswith("...") or compact.endswith("...") or compact.count("...") >= 1:
        return "whisper"
    if len(compact) >= 48 or compact.count(" / ") >= 1 or compact.count(" - ") >= 1:
        return "chorus"
    if "!" in compact or "?" in compact:
        return "emphasis"
    return "default"


def _build_segment_style_labels(
    *,
    segments: list[dict[str, Any]],
    preset: str,
    prompt_hint: str | None,
    ai_enabled: bool,
    ai_modes: list[str],
    ai_model: str,
    ai_temperature: float,
    ai_top_p: float,
    ai_batch_size: int,
    timeout_seconds: int,
    warnings: list[str],
    content_mode: str,
) -> tuple[list[str], str]:
    seen_lines: dict[str, int] = {}
    heuristic: list[str] = []
    for segment in segments:
        text = _segment_text(segment)
        label = _heuristic_style_label(text)
        normalized_line = re.sub(r"\W+", "", text.lower())
        if normalized_line:
            seen_lines[normalized_line] = seen_lines.get(normalized_line, 0) + 1
            if seen_lines[normalized_line] >= 2 and len(normalized_line) >= 6:
                label = "chorus"
        heuristic.append(label)
    if not ai_enabled or "subtitle_styling" not in ai_modes or not segments:
        return heuristic, "heuristic"

    labels = heuristic[:]
    system = (
        "Você classifica trechos de legenda em rótulos visuais seguros. "
        "Não invente texto e não gere tags ASS."
    )
    if prompt_hint:
        system += f"\nPreferência extra do usuário: {prompt_hint.strip()}"

    try:
        for start_index, chunk in _chunk_segments_for_ai(
            segments,
            max_items=max(1, min(ai_batch_size, 4)),
            max_chars=1400,
        ):
            prompt_payload = {
                "task": "classify_subtitle_style_labels",
                "preset": preset,
                "contentMode": content_mode,
                "expectedCount": len(chunk),
                "items": [
                    {
                        "index": idx,
                        "text": _segment_text(segment),
                        "fallbackLabel": heuristic[start_index + idx],
                        "durationSeconds": round(
                            max(0.1, float(segment.get("end") or 0.0) - float(segment.get("start") or 0.0)),
                            3,
                        ),
                    }
                    for idx, segment in enumerate(chunk)
                ],
                "instructions": [
                    "Classifique cada trecho em um único rótulo visual.",
                    "Use apenas os rótulos permitidos.",
                    "Baseie-se em intensidade, pontuação, energia e clareza.",
                    "Nunca use speaker_a ou speaker_b sem diarização explícita.",
                    "Se contentMode=anime_song, priorize chorus/emphasis para trechos musicais sem inventar texto.",
                ],
            }
            mapped, _, _ = _call_structured_items_with_repair(
                model=ai_model,
                system=system,
                prompt_payload=prompt_payload,
                expected_count=len(chunk),
                value_field="label",
                enum_values=STYLE_LABELS,
                temperature=min(ai_temperature, 0.1),
                top_p=ai_top_p,
                num_predict=128,
                timeout_seconds=timeout_seconds,
            )
            if len(mapped) != len(chunk):
                raise RuntimeError(
                    f"Rótulos de estilo inválidos: esperado {len(chunk)}, recebido {len(mapped)}."
                )
            for local_index, _ in enumerate(chunk):
                labels[start_index + local_index] = mapped.get(local_index, heuristic[start_index + local_index])
        return labels, "ai_labels"
    except Exception as exc:
        warnings.append(f"Classificação visual por trecho caiu no modo heurístico: {exc}")
        return heuristic, "heuristic"



def _plan_visual_style(
    *,
    preset: str,
    prompt_hint: str | None,
    ai_enabled: bool,
    ai_modes: list[str],
    ai_use_visual_context: bool,
    source_file: Path,
    ai_model: str,
    fallback_ai_models: list[str] | None,
    ai_temperature: float,
    ai_top_p: float,
    ai_max_tokens: int,
    ai_frame_sample_seconds: int,
    timeout_seconds: int,
    warnings: list[str],
    content_mode: str,
    style_intensity: str,
) -> tuple[dict[str, Any], str, dict[str, Any] | None]:
    base = {
        "fontName": "Segoe UI",
        "fontSize": 36,
        "songFontSize": 40,
        "outline": 3.2,
        "shadow": 0,
        "marginV": 52,
        "primaryColour": "&H00F6F6F6",
        "outlineColour": "&H00101010",
        "backColour": "&H50000000",
        "alignment": 2,
        "karaokePop": True,
        "fadeInMs": 90,
        "fadeOutMs": 120,
        "scaleIntro": 104,
        "styleName": "Default",
    }

    preset_map = {
        "default": {},
        "clean": {"fontSize": 34, "songFontSize": 38, "outline": 2.8, "backColour": "&H28000000"},
        "highlight": {"fontSize": 38, "songFontSize": 42, "primaryColour": "&H00F8F2D0", "outline": 3.4},
        "cinematic": {"fontSize": 40, "songFontSize": 44, "marginV": 64, "outline": 4.0, "backColour": "&H64000000"},
        "shorts_bold": {"fontSize": 44, "songFontSize": 48, "outline": 4.2, "marginV": 72},
        "shorts_dynamic": {"fontSize": 42, "songFontSize": 48, "outline": 4.0, "marginV": 68, "scaleIntro": 108},
        "shorts_neon": {"fontSize": 42, "songFontSize": 48, "outline": 4.0, "primaryColour": "&H00C8FFF8", "outlineColour": "&H00242A52", "marginV": 68},
    }
    base.update(preset_map.get((preset or "default").strip().lower(), {}))
    base = _apply_style_intensity(base, style_intensity=style_intensity, content_mode=content_mode)

    if not ai_enabled or "subtitle_styling" not in ai_modes:
        return base, "local_preset", None

    schema = {
        "type": "object",
        "properties": {
            "fontSize": {"type": "integer"},
            "songFontSize": {"type": "integer"},
            "outline": {"type": "number"},
            "marginV": {"type": "integer"},
            "primaryColour": {"type": "string"},
            "outlineColour": {"type": "string"},
            "backColour": {"type": "string"},
            "scaleIntro": {"type": "integer"},
        },
        "required": ["fontSize", "songFontSize", "outline", "marginV", "primaryColour", "outlineColour", "backColour", "scaleIntro"],
    }

    prompt = json.dumps(
        {
            "task": "subtitle_style_plan",
            "preset": preset,
            "contentMode": content_mode,
            "styleIntensity": style_intensity,
            "userPrompt": prompt_hint or "",
            "instructions": [
                "Retorne apenas um plano visual para legenda ASS.",
                "Retorne um objeto JSON plano com apenas estas chaves: fontSize, songFontSize, outline, marginV, primaryColour, outlineColour, backColour, scaleIntro.",
                "Não altere texto nem timing.",
                "Prefira legibilidade alta para 1080p.",
                "Use cores seguras para vídeo escuro.",
                "Nunca use figurinhas, kaomoji, corações, ícones ou símbolos decorativos no texto.",
                "Expresse emoção apenas com cor, intensidade, fade, posicionamento e pontuação já existente.",
                "Se contentMode=anime_song, mantenha espaço para layout de romaji no topo e tradução embaixo.",
            ],
        },
        ensure_ascii=False,
    )
    images: list[str] | None = None
    if ai_use_visual_context:
        try:
            images = _sample_video_frames(source_file, ai_frame_sample_seconds)
        except Exception as exc:
            warnings.append(f"Amostragem de frames falhou: {exc}")

    response_meta: dict[str, Any] | None = None
    attempted_models: list[str] = []

    def try_plan(model_name: str, *, include_images: bool) -> tuple[dict[str, Any], dict[str, Any]] | None:
        attempted_models.append(model_name)
        is_remote_provider = _get_ai_runtime_context().get("provider") == "remote_api"
        if is_remote_provider:
            plan_token_budget = 768 if include_images else 512
        else:
            plan_token_budget = 320 if include_images else 256
        response = _call_ollama_chat(
            model=model_name,
            messages=[
                {
                    "role": "system",
                    "content": "Você produz apenas planos visuais JSON seguros para legenda ASS. Não escreva tags ASS livres.",
                },
                {"role": "user", "content": prompt},
            ],
            images=images if include_images else None,
            format_schema=schema,
            temperature=min(ai_temperature, 0.1),
            top_p=ai_top_p,
            num_predict=max(ai_max_tokens, plan_token_budget),
            timeout_seconds=timeout_seconds,
        )
        decoded = _extract_json_fragment(response.text) or {}
        if not isinstance(decoded, dict):
            return None

        candidate_style: dict[str, Any] = {}
        candidate_sources: list[dict[str, Any]] = [decoded]
        plan_root = decoded.get("plan")
        if isinstance(plan_root, dict):
            candidate_sources.append(plan_root)
            if isinstance(plan_root.get("style"), dict):
                candidate_sources.append(plan_root["style"])
            styles_root = plan_root.get("styles")
            if isinstance(styles_root, dict):
                style_entry = styles_root.get("style")
                if isinstance(style_entry, dict):
                    candidate_sources.append(style_entry)

        field_aliases = {
            "fontSize": ["fontSize", "Fontsize", "fontsize"],
            "songFontSize": ["songFontSize", "SongFontSize"],
            "outline": ["outline", "Outline"],
            "marginV": ["marginV", "MarginV"],
            "primaryColour": ["primaryColour", "PrimaryColour"],
            "outlineColour": ["outlineColour", "OutlineColour"],
            "backColour": ["backColour", "BackColour"],
            "scaleIntro": ["scaleIntro", "ScaleIntro"],
            "fontName": ["fontName", "Fontname"],
        }
        for source in candidate_sources:
            if not isinstance(source, dict):
                continue
            for normalized_key, aliases in field_aliases.items():
                for alias in aliases:
                    if alias in source and source[alias] not in {None, ""}:
                        candidate_style[normalized_key] = source[alias]
                        break
        merged = _merge_style_plan_with_floor(base, candidate_style)
        meta = {
            "source_field": response.source_field,
            "raw_excerpt": response.raw_excerpt,
            "duration_ms": response.elapsed_ms,
            "model": model_name,
            "usedImages": include_images,
        }
        return (
            _apply_style_intensity(
                merged,
                style_intensity=style_intensity,
                content_mode=content_mode,
            ),
            meta,
        )

    try:
        primary_result = try_plan(ai_model, include_images=bool(images))
        if primary_result is not None:
            planned_style, response_meta = primary_result
            return planned_style, "ai_plan", response_meta
    except Exception as exc:
        warnings.append(f"Plano visual primário falhou ({ai_model}): {exc}")
        response_meta = _ollama_error_context(exc)

    if images:
        try:
            secondary_result = try_plan(ai_model, include_images=False)
            if secondary_result is not None:
                planned_style, secondary_meta = secondary_result
                warnings.append(
                    f"Plano visual reutilizou o modelo selecionado em modo textual após falha/timeout com frames ({ai_model})."
                )
                response_meta = secondary_meta
                return planned_style, "ai_plan", response_meta
        except Exception as exc:
            warnings.append(f"Plano visual textual com o mesmo modelo falhou ({ai_model}): {exc}")
            response_meta = _ollama_error_context(exc)

    for fallback_ai_model in [
        item.strip()
        for item in (fallback_ai_models or [])
        if str(item or "").strip() and str(item).strip() not in attempted_models
    ]:
        try:
            fallback_result = try_plan(fallback_ai_model, include_images=False)
            if fallback_result is not None:
                planned_style, fallback_meta = fallback_result
                warnings.append(
                    f"Plano visual usou fallback textual após falha/timeout do modelo principal ({ai_model} -> {fallback_ai_model})."
                )
                response_meta = fallback_meta
                return planned_style, "ai_plan", response_meta
        except Exception as exc:
            warnings.append(f"Plano visual textual de fallback falhou ({fallback_ai_model}): {exc}")
            response_meta = _ollama_error_context(exc)

    warnings.append(f"Plano visual caiu no preset local após tentativas: {', '.join(attempted_models) or ai_model}.")
    return _apply_style_intensity(base, style_intensity=style_intensity, content_mode=content_mode), "local_preset", response_meta


# -----------------------------------------------------------------------------
# Writers: TXT / SRT / VTT / ASS
# -----------------------------------------------------------------------------

def _srt_time(seconds: float) -> str:
    total_ms = int(round(max(0.0, seconds) * 1000))
    hours = total_ms // 3_600_000
    total_ms %= 3_600_000
    minutes = total_ms // 60_000
    total_ms %= 60_000
    secs = total_ms // 1000
    ms = total_ms % 1000
    return f"{hours:02d}:{minutes:02d}:{secs:02d},{ms:03d}"



def _vtt_time(seconds: float) -> str:
    return _srt_time(seconds).replace(",", ".")



def _ass_time(seconds: float) -> str:
    total_cs = int(round(max(0.0, seconds) * 100))
    hours = total_cs // 360000
    total_cs %= 360000
    minutes = total_cs // 6000
    total_cs %= 6000
    secs = total_cs // 100
    cs = total_cs % 100
    return f"{hours:d}:{minutes:02d}:{secs:02d}.{cs:02d}"



def _clean_subtitle_text(text: str) -> str:
    return re.sub(r"\s+", " ", (text or "").replace("\n", " ")).strip()



def _wrap_subtitle(text: str, max_chars: int | None) -> str:
    text = _clean_subtitle_text(text)
    if not text:
        return ""
    limit = max(12, int(max_chars or 42))
    words = text.split()
    lines: list[str] = []
    current: list[str] = []
    current_len = 0
    for word in words:
        projected = current_len + (1 if current else 0) + len(word)
        if current and projected > limit:
            lines.append(" ".join(current))
            current = [word]
            current_len = len(word)
        else:
            current.append(word)
            current_len = projected
    if current:
        lines.append(" ".join(current))
    return "\\N".join(lines)



def _write_text_file(path: Path, segments: list[dict[str, Any]]) -> None:
    path.write_text(_segments_text(segments), encoding="utf-8")



def _write_srt_file(path: Path, segments: list[dict[str, Any]], max_chars: int | None) -> None:
    lines: list[str] = []
    counter = 1
    for segment in segments:
        text = _wrap_subtitle(_segment_text(segment), max_chars).replace("\\N", "\n")
        if not text:
            continue
        lines.extend(
            [
                str(counter),
                f"{_srt_time(float(segment.get('start') or 0.0))} --> {_srt_time(float(segment.get('end') or 0.0))}",
                text,
                "",
            ]
        )
        counter += 1
    path.write_text("\n".join(lines).strip() + "\n", encoding="utf-8")



def _write_vtt_file(path: Path, segments: list[dict[str, Any]], max_chars: int | None) -> None:
    lines = ["WEBVTT", ""]
    for segment in segments:
        text = _wrap_subtitle(_segment_text(segment), max_chars).replace("\\N", "\n")
        if not text:
            continue
        lines.extend(
            [
                f"{_vtt_time(float(segment.get('start') or 0.0))} --> {_vtt_time(float(segment.get('end') or 0.0))}",
                text,
                "",
            ]
        )
    path.write_text("\n".join(lines).strip() + "\n", encoding="utf-8")



def _ass_escape(text: str) -> str:
    return text.replace("{", r"\{").replace("}", r"\}")



def _segment_style_name(segment: dict[str, Any]) -> str:
    label = str(segment.get("styleLabel") or "default").strip().lower()
    return {
        "chorus": "Chorus",
        "emphasis": "Emphasis",
        "whisper": "Whisper",
        "shout": "Shout",
    }.get(label, "Default")



def _ass_override(
    segment: dict[str, Any],
    style: dict[str, Any],
    *,
    style_name: str | None = None,
    top_layout: bool = False,
) -> str:
    fade_in = max(0, int(style.get("fadeInMs", 90)))
    fade_out = max(0, int(style.get("fadeOutMs", 120)))
    effective_style = style_name or _segment_style_name(segment)
    blur = 0.3 if effective_style in {"Chorus", "Shout", "SongTop", "SongBottom"} else 0.5
    scale = int(style.get("scaleIntro", 104))
    outline = float(style.get("outline", 3.2))
    palette = _derive_style_palette(style)

    tags: list[str] = [rf"\fad({fade_in},{fade_out})", rf"\blur{blur}"]

    placement = str(segment.get("speakerPlacement") or "bottom").strip().lower()
    if top_layout or placement == "top":
        tags.append(r"\an8\pos(960,146)")
    elif placement == "middle":
        tags.append(r"\an5\pos(960,540)")
    else:
        tags.append(r"\an2")

    accent = str(segment.get("speakerAccent") or "default").strip().lower()
    if accent == "primary":
        tags.append(rf"\1c{palette['emphasisPrimary']}")
    elif accent == "secondary":
        tags.append(rf"\1c{palette['chorusPrimary']}")

    if effective_style in {"Chorus", "SongBottom"}:
        tags.append(
            rf"\t(0,180,\fscx{min(124, scale + 6)}\fscy{min(124, scale + 6)})"
        )
    elif effective_style == "SongTop":
        tags.append(
            rf"\alpha&H10&\t(0,180,\fscx{min(123, scale + 4)}\fscy{min(123, scale + 4)})"
        )
    elif effective_style == "Shout":
        tags.append(rf"\bord{min(7.0, outline + 1.2):.1f}")
        tags.append(
            rf"\t(0,120,\fscx{min(125, scale + 10)}\fscy{min(125, scale + 10)})"
        )
    elif effective_style == "Whisper":
        tags.append(r"\alpha&H22&")
    elif effective_style == "Emphasis":
        tags.append(
            rf"\t(0,120,\fscx{min(122, scale + 5)}\fscy{min(122, scale + 5)})"
        )

    return "{" + "".join(tags) + "}"



def _write_ass_file(
    path: Path,
    segments: list[dict[str, Any]],
    max_chars: int | None,
    style: dict[str, Any],
    *,
    content_mode: str,
    anime_song_layout_mode: str,
) -> None:
    font_name = str(style.get("fontName", "Segoe UI"))
    font_size = int(style.get("fontSize", 36))
    song_font_size = int(style.get("songFontSize", 40))
    outline = float(style.get("outline", 3.2))
    shadow = int(style.get("shadow", 0))
    margin_v = int(style.get("marginV", 52))
    alignment = int(style.get("alignment", 2))
    palette = _derive_style_palette(style)

    content = [
        "[Script Info]",
        "ScriptType: v4.00+",
        "PlayResX: 1920",
        "PlayResY: 1080",
        "ScaledBorderAndShadow: yes",
        "WrapStyle: 2",
        "YCbCr Matrix: TV.601",
        "",
        "[V4+ Styles]",
        "Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding",
        f"Style: Default,{font_name},{font_size},{palette['defaultPrimary']},{palette['defaultPrimary']},{palette['defaultOutline']},{palette['back']},0,0,0,0,100,100,0,0,1,{outline},{shadow},{alignment},28,28,{margin_v},1",
        f"Style: Chorus,{font_name},{song_font_size},{palette['chorusPrimary']},{palette['chorusPrimary']},{palette['chorusOutline']},{palette['back']},1,0,0,0,100,100,0.2,0,1,{min(5.6, outline + 0.5)},{shadow},2,28,28,{max(36, margin_v - 12)},1",
        f"Style: Emphasis,{font_name},{font_size + 1},{palette['emphasisPrimary']},{palette['emphasisPrimary']},{palette['emphasisOutline']},{palette['back']},1,0,0,0,100,100,0,0,1,{min(5.4, outline + 0.2)},{shadow},2,28,28,{max(34, margin_v - 6)},1",
        f"Style: Whisper,{font_name},{font_size},{palette['whisperPrimary']},{palette['whisperPrimary']},{palette['whisperOutline']},{palette['back']},0,1,0,0,100,100,0,0,1,{max(1.4, outline - 0.6)},{shadow},2,28,28,{margin_v + 2},1",
        f"Style: Shout,{font_name},{min(74, song_font_size + 4)},{palette['shoutPrimary']},{palette['shoutPrimary']},{palette['shoutOutline']},{palette['back']},1,0,0,0,100,100,0.1,0,1,{min(6.0, outline + 0.9)},{shadow},2,28,28,{max(28, margin_v - 14)},1",
        f"Style: SongTop,{font_name},{max(28, song_font_size - 4)},{palette['chorusPrimary']},{palette['chorusPrimary']},{palette['chorusOutline']},{palette['back']},0,0,0,0,100,100,0.1,0,1,{min(5.2, outline + 0.3)},{shadow},8,28,28,{max(108, margin_v + 46)},1",
        f"Style: SongBottom,{font_name},{song_font_size},{palette['defaultPrimary']},{palette['defaultPrimary']},{palette['defaultOutline']},{palette['back']},1,0,0,0,100,100,0.1,0,1,{min(5.6, outline + 0.4)},{shadow},2,28,28,{max(42, margin_v - 4)},1",
        "",
        "[Events]",
        "Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text",
    ]

    effective_content_mode = _normalize_content_mode(content_mode)
    for segment in segments:
        text = _wrap_subtitle(_segment_text(segment), max_chars)
        if not text:
            continue

        start_time = _ass_time(float(segment.get("start") or 0.0))
        end_time = _ass_time(float(segment.get("end") or 0.0))

        is_song_segment = (
            (effective_content_mode == "anime_song" or str(segment.get("contentCategory") or "").strip().lower() == "anime_song")
            and anime_song_layout_mode != "off"
            and str(segment.get("songLayout") or anime_song_layout_mode).strip().lower() != "off"
        )
        if is_song_segment:
            romaji_text = _wrap_subtitle(str(segment.get("romajiText") or "").strip(), max_chars)
            translation_text = _wrap_subtitle(str(segment.get("translationText") or text).strip(), max_chars)
            romaji_karaoke = _build_ass_karaoke_text(segment.get("romajiTokens") or [])
            translation_karaoke = _build_ass_karaoke_text(segment.get("translationTokens") or [])
            if romaji_text:
                override = _ass_override(
                    segment,
                    style,
                    style_name="SongTop",
                    top_layout=True,
                )
                content.append(
                    "Dialogue: 0,"
                    f"{start_time},"
                    f"{end_time},"
                    f"SongTop,,0,0,0,,{override}{(romaji_karaoke or _ass_escape(romaji_text))}"
                )
            if translation_text:
                override = _ass_override(segment, style, style_name="SongBottom")
                content.append(
                    "Dialogue: 1,"
                    f"{start_time},"
                    f"{end_time},"
                    f"SongBottom,,0,0,0,,{override}{(translation_karaoke or _ass_escape(translation_text))}"
                )
            continue

        style_name = _segment_style_name(segment)
        override = _ass_override(segment, style, style_name=style_name)
        content.append(
            "Dialogue: 0,"
            f"{start_time},"
            f"{end_time},"
            f"{style_name},,0,0,0,,{override}{_ass_escape(text)}"
        )

    path.write_text("\n".join(content) + "\n", encoding="utf-8")



def _render_outputs_for_segments(
    *,
    output_dir: Path,
    base_name: str,
    segments: list[dict[str, Any]],
    requested_outputs: list[str],
    max_subtitle_chars: int | None,
    style: dict[str, Any],
    content_mode: str,
    anime_song_layout_mode: str,
) -> dict[str, str]:
    outputs: dict[str, str] = {}
    if "txt" in requested_outputs:
        target = output_dir / f"{base_name}.txt"
        _write_text_file(target, segments)
        outputs["text"] = str(target)
    if "srt" in requested_outputs:
        target = output_dir / f"{base_name}.srt"
        _write_srt_file(target, segments, max_subtitle_chars)
        outputs["srt"] = str(target)
    if "vtt" in requested_outputs:
        target = output_dir / f"{base_name}.vtt"
        _write_vtt_file(target, segments, max_subtitle_chars)
        outputs["vtt"] = str(target)
    if "ass" in requested_outputs:
        target = output_dir / f"{base_name}.ass"
        _write_ass_file(
            target,
            segments,
            max_subtitle_chars,
            style,
            content_mode=content_mode,
            anime_song_layout_mode=anime_song_layout_mode,
        )
        outputs["ass"] = str(target)
    return outputs


def _write_runtime_artifacts(
    *,
    output_root: Path | None,
    warnings: list[str],
    diagnostics: list[dict[str, Any]],
    style_source: str | None,
    content_mode: str | None = None,
    speaker_mode_applied: str | None = None,
    voice_analysis_source: str | None = None,
    scene_analysis_source: str | None = None,
    preview_mode_applied: str | None = None,
    planner_model_used: str | None = None,
    review_model_used: str | None = None,
    quality_summary: dict[str, Any] | None,
    translation_statuses: dict[str, Any] | None,
    capability_profile: dict[str, Any] | None,
    timeout_profile_applied: str | None = None,
    translations_manifest: dict[str, Any] | None = None,
    requested_ai_provider: str | None = None,
    requested_ai_model: str | None = None,
    effective_ai_provider: str | None = None,
    effective_ai_model: str | None = None,
    runtime_target: str | None = None,
    model_installed_at_submission: bool | None = None,
    fallbacks: list[dict[str, Any]] | None = None,
    source_duration_seconds: float | None = None,
    output_duration_seconds: float | None = None,
    musical_segment_durations: list[dict[str, Any]] | None = None,
) -> dict[str, str | None]:
    paths = {
        "diagnosticsPath": None,
        "qualityReportPath": None,
        "translationManifestPath": None,
    }
    if output_root is None:
        return paths

    _ensure_dir(output_root)

    diagnostics_payload = {
        "styleSource": style_source or "local_preset",
        "diagnostics": diagnostics,
        "warnings": warnings,
        "contentMode": content_mode,
        "speakerModeApplied": speaker_mode_applied,
        "voiceAnalysisSource": voice_analysis_source,
        "sceneAnalysisSource": scene_analysis_source,
        "previewModeApplied": preview_mode_applied,
        "plannerModelUsed": planner_model_used,
        "reviewModelUsed": review_model_used,
        "timeoutProfileApplied": timeout_profile_applied,
        "qualitySummary": quality_summary or {},
        "translationStatuses": translation_statuses or {},
        "capabilityProfile": capability_profile or {},
        "requestedAiProvider": requested_ai_provider,
        "requestedAiModel": requested_ai_model,
        "effectiveAiProvider": effective_ai_provider,
        "effectiveAiModel": effective_ai_model,
        "runtimeTarget": runtime_target,
        "modelInstalledAtSubmission": model_installed_at_submission,
        "fallbacks": fallbacks or [],
        "sourceDurationSeconds": source_duration_seconds,
        "outputDurationSeconds": output_duration_seconds,
        "musicalSegmentDurations": musical_segment_durations or [],
    }
    diagnostics_file = output_root / "job_diagnostics.json"
    diagnostics_file.write_text(
        json.dumps(diagnostics_payload, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    paths["diagnosticsPath"] = str(diagnostics_file)

    if quality_summary:
        quality_file = output_root / "quality_report.json"
        quality_file.write_text(
            json.dumps(quality_summary, ensure_ascii=False, indent=2),
            encoding="utf-8",
        )
        paths["qualityReportPath"] = str(quality_file)

    if translations_manifest and translations_manifest.get("languages"):
        manifest_file = output_root / "translations_manifest.json"
        manifest_file.write_text(
            json.dumps(translations_manifest, ensure_ascii=False, indent=2),
            encoding="utf-8",
        )
        paths["translationManifestPath"] = str(manifest_file)

    return paths


# -----------------------------------------------------------------------------
# Video generation / mux
# -----------------------------------------------------------------------------

def _escape_ffmpeg_filter_path(path: Path) -> str:
    value = str(path.resolve()).replace("\\", "/")
    value = value.replace(":", r"\:")
    value = value.replace("'", r"\'")
    value = value.replace(",", r"\,")
    value = value.replace("[", r"\[")
    value = value.replace("]", r"\]")
    return f"filename='{value}'"


def _burn_subtitles_into_video(source_file: Path, subtitle_path: Path, output_path: Path) -> None:
    subtitle_filter = (
        f"ass={_escape_ffmpeg_filter_path(subtitle_path)}"
        if subtitle_path.suffix.lower() == ".ass"
        else f"subtitles={_escape_ffmpeg_filter_path(subtitle_path)}"
    )
    command = [
        _ffmpeg_path(),
        "-y",
        "-i",
        str(source_file),
        "-vf",
        subtitle_filter,
        "-c:v",
        "libx264",
        "-preset",
        "veryfast",
        "-crf",
        "18",
        "-c:a",
        "copy",
        str(output_path),
    ]
    result = _run_command(command, timeout=60 * 60)
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or "Falha ao gerar vídeo com legenda queimada.")



def _mux_subtitles_into_mkv(
    source_file: Path,
    subtitle_tracks: list[tuple[str, Path]],
    output_path: Path,
) -> None:
    if not subtitle_tracks:
        raise RuntimeError("Nenhuma trilha de legenda foi fornecida para mux.")

    command = [_ffmpeg_path(), "-y", "-i", str(source_file)]
    for _, subtitle_path in subtitle_tracks:
        command.extend(["-i", str(subtitle_path)])

    command.extend(["-map", "0:v", "-map", "0:a?"])
    for index, _ in enumerate(subtitle_tracks, start=1):
        command.extend(["-map", f"{index}:0"])

    command.extend(["-c", "copy", "-c:s", "ass"])

    for subtitle_index, (language_code, _) in enumerate(subtitle_tracks):
        command.extend([f"-metadata:s:s:{subtitle_index}", f"language={language_code}"])
        command.extend([f"-metadata:s:s:{subtitle_index}", f"title={_display_lang(language_code)}"])

    command.append(str(output_path))
    result = _run_command(command, timeout=60 * 60)
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or "Falha ao muxar trilhas de legenda.")


def _render_styled_preview_clip(
    *,
    source_file: Path,
    subtitle_path: Path,
    output_path: Path,
    clip_start_seconds: float | None = None,
    clip_duration_seconds: float = 24.0,
    full_length: bool = False,
) -> None:
    duration = _probe_duration_seconds(source_file) or 0.0
    safe_duration = max(6.0, min(32.0, clip_duration_seconds))
    start = max(0.0, clip_start_seconds or 0.0)
    render_full = full_length or duration <= safe_duration
    if duration > safe_duration and not render_full:
        start = min(start, max(0.0, duration - safe_duration))
    else:
        start = 0.0

    subtitle_filter = (
        f"ass={_escape_ffmpeg_filter_path(subtitle_path)}"
        if subtitle_path.suffix.lower() == ".ass"
        else f"subtitles={_escape_ffmpeg_filter_path(subtitle_path)}"
    )
    command = [
        _ffmpeg_path(),
        "-y",
        "-ss",
        f"{start:.3f}",
        "-i",
        str(source_file),
        "-vf",
        subtitle_filter,
        "-c:v",
        "libx264",
        "-preset",
        "veryfast",
        "-crf",
        "20",
        "-c:a",
        "aac",
        "-b:a",
        "160k",
        "-movflags",
        "+faststart",
        str(output_path),
    ]
    if not render_full:
        command[6:6] = ["-t", f"{safe_duration:.3f}"]
    result = _run_command(command, timeout=60 * 30)
    if result.returncode != 0:
        raise RuntimeError(
            result.stderr.strip()
            or "Falha ao gerar preview renderizado com estilo."
        )


# -----------------------------------------------------------------------------
# Main pipeline
# -----------------------------------------------------------------------------

def run_job_transcription(payload: dict[str, Any]) -> dict[str, Any]:
    warnings: list[str] = []
    diagnostics: list[dict[str, Any]] = []
    output_root: Path | None = None
    capability_profile: dict[str, Any] = {}
    translation_statuses: dict[str, Any] = {}
    overall_quality_summary: dict[str, Any] = {}
    translations_manifest: dict[str, Any] = {"languages": {}}
    effective_style_source = "local_preset"
    content_mode = "episode"
    speaker_mode_applied = "heuristic"
    karaoke_mode_applied = "off"
    content_detection_confidence: float | None = None
    voice_analysis_source = "disabled"
    scene_analysis_source = "timing_style_blocks"
    preview_mode_applied = "fast"
    planner_model_used: str | None = None
    review_model_used: str | None = None
    effective_quality_profile = "balanced"
    requested_ai_provider = "ollama_project"
    requested_ai_model: str | None = None
    effective_ai_provider = "ollama_project"
    effective_ai_model: str | None = None
    runtime_target = "project_ollama"
    model_installed_at_submission: bool | None = None
    fallbacks: list[dict[str, Any]] = []
    source_duration_seconds: float | None = None
    output_duration_seconds: float | None = None
    musical_segment_durations: list[dict[str, Any]] = []
    ai_runtime_token: contextvars.Token[dict[str, Any] | None] | None = None

    try:
        source_type = _pick_str(payload, "source_type", "sourceType", default="file_path")
        source_value = _pick_str(payload, "source_value", "sourceValue")
        if not source_value:
            raise ValueError("SourceValue é obrigatório.")

        task = _pick_str(payload, "task", default="transcribe").lower()
        model_name = _pick_str(payload, "model", default="large-v3")
        input_language = _normalize_lang(_pick_str(payload, "language", default="auto")) or "auto"
        beam_size = _pick_int(payload, "beam_size", "beamSize", default=5)
        device_preference = _pick_str(payload, "device_preference", "devicePreference", default="auto")
        compute_type_preference = _pick_str(payload, "compute_type", "computeType", default="auto")
        vad_filter = _pick_bool(payload, "vad_filter", "vadFilter", default=True)
        keep_timestamps = _pick_bool(payload, "keep_timestamps", "keepTimestamps", default=True)
        word_timestamps_requested = _pick_bool(payload, "word_timestamps", "wordTimestamps", default=False)
        max_subtitle_chars = _pick_int(payload, "max_subtitle_chars", "maxSubtitleChars", default=42)
        subtitle_style = _pick_str(payload, "subtitle_visual_preset", "subtitleVisualPreset", "subtitle_style", "subtitleStyle", default="default")
        delivery_mode = _pick_str(payload, "video_delivery_mode", "videoDeliveryMode", "delivery_mode", "deliveryMode", default="standard")
        burn_requested = _pick_bool(payload, "burn_subtitles_into_video", "burnSubtitlesIntoVideo", default=False)
        requested_outputs = _ordered_unique([
            item.lower()
            for item in _pick_list(payload, "requested_outputs", "requestedOutputs", "requested_outputs_csv", "requestedOutputsCsv")
        ])
        if not requested_outputs:
            output_format = _pick_str(payload, "output_format", "outputFormat", default="srt").lower()
            if output_format == "all":
                requested_outputs = ["txt", "srt", "vtt"]
            elif output_format in {"video_only", "video_burned"}:
                requested_outputs = []
            else:
                requested_outputs = [item for item in output_format.split("+") if item in {"txt", "srt", "vtt", "ass"}]
                if not requested_outputs:
                    requested_outputs = ["srt"]

        ai_enabled = _pick_bool(payload, "ai_enhancement_enabled", "aiEnhancementEnabled", default=False)
        ai_provider = _normalize_ai_provider(
            _pick_str(payload, "ai_provider", "aiProvider", default="ollama_project")
        )
        ai_use_visual_context = _pick_bool(payload, "ai_use_visual_context", "aiUseVisualContext", default=False)
        ai_modes = _normalize_ai_modes([
            item.lower() for item in _pick_list(payload, "ai_mode", "aiMode") if item.strip()
        ], task)
        ai_model = _resolve_ai_model(
            _pick_str(payload, "ai_model", "aiModel", default=os.getenv("OLLAMA_DEFAULT_MODEL", DEFAULT_VISUAL_AI_MODEL)),
            ai_use_visual_context,
        )
        requested_ai_provider = ai_provider
        requested_ai_model = ai_model
        ai_prompt = _pick_str(payload, "ai_prompt", "aiPrompt", default="")
        ai_temperature = _pick_float(payload, "ai_temperature", "aiTemperature", default=0.2)
        ai_top_p = _pick_float(payload, "ai_top_p", "aiTopP", default=0.9)
        ai_max_tokens = _pick_int(payload, "ai_max_tokens", "aiMaxTokens", default=1024)
        ai_chunk_chars = _pick_int(payload, "ai_chunk_chars", "aiChunkChars", default=6000)
        ai_frame_sample_seconds = _pick_int(payload, "ai_frame_sample_seconds", "aiFrameSampleSeconds", default=12)
        ai_revision_passes = max(0, min(10, _pick_int(payload, "ai_revision_passes", "aiRevisionPasses", default=3)))
        use_advanced_alignment = _pick_str(payload, "use_advanced_alignment", "useAdvancedAlignment", default="auto").lower()
        if use_advanced_alignment not in ALLOWED_ALIGNMENT_MODES:
            use_advanced_alignment = "auto"
        quality_profile = _pick_str(payload, "quality_profile", "qualityProfile", default="balanced").lower()
        if quality_profile not in ALLOWED_QUALITY_PROFILES:
            quality_profile = "balanced"
        content_mode_requested = _normalize_content_mode(
            _pick_str(payload, "content_mode", "contentMode", default="episode")
        )
        speaker_style_mode_requested = _normalize_speaker_style_mode(
            _pick_str(payload, "speaker_style_mode", "speakerStyleMode", default="heuristic")
        )
        style_intensity = _normalize_style_intensity(
            _pick_str(payload, "style_intensity", "styleIntensity", default="thematic")
        )
        rendered_preview_mode = _normalize_rendered_preview_mode(
            _pick_str(payload, "rendered_preview_mode", "renderedPreviewMode", default="fast")
        )
        raw_karaoke_granularity = _pick_str(
            payload,
            "karaoke_granularity",
            "karaokeGranularity",
            default="off",
        )
        raw_context_hints = _get_value(payload, ["context_hints", "contextHints"], {}) or {}
        context_hints = raw_context_hints if isinstance(raw_context_hints, dict) else {}

        target_languages = _ordered_unique([_normalize_lang(item) for item in _pick_list(payload, "target_languages", "targetLanguages", "target_languages_csv", "targetLanguagesCsv") if item.strip()])

        if task == "translate" and len(target_languages) > 1 and delivery_mode == "burned_video":
            delivery_mode = "mux_subtitles"
            burn_requested = False

        if "subtitle_styling" in ai_modes and "ass" not in requested_outputs:
            requested_outputs.append("ass")
        requested_outputs = [item for item in requested_outputs if item in {"txt", "srt", "vtt", "ass"}]
        requested_outputs = _ordered_unique(requested_outputs)
        if not requested_outputs:
            requested_outputs = ["ass" if "subtitle_styling" in ai_modes else "srt"]

        word_timestamps = word_timestamps_requested or "subtitle_styling" in ai_modes
        capabilities = get_capabilities()
        provider_capabilities = _lookup_provider_capabilities(capabilities, ai_provider)
        if ai_enabled:
            if not provider_capabilities:
                raise ValueError(f"Provider de IA '{ai_provider}' não está disponível neste runtime.")
            if not bool(provider_capabilities.get("available")):
                raise ValueError(f"Provider de IA '{ai_provider}' não está pronto para uso local.")
            allowed_multimodal_models = {
                str(item or "").strip().lower()
                for item in (provider_capabilities.get("multimodalModels") or [])
            }
            if not ai_model or ai_model.strip().lower() not in allowed_multimodal_models:
                raise ValueError(
                    f"O modelo '{ai_model}' não faz parte do catálogo multimodal público do provider '{ai_provider}'."
                )
            installed_models = {
                str(item or "").strip().lower()
                for item in (capabilities.get("installedModelsByProvider") or {}).get(ai_provider, [])
            }
            if not ai_model or ai_model.strip().lower() not in installed_models:
                raise ValueError(
                    f"O modelo '{ai_model}' não está instalado para o provider '{ai_provider}'."
                )
            effective_ai_provider = ai_provider
            effective_ai_model = ai_model
            runtime_target = "project_ollama" if ai_provider == "ollama_project" else "remote_api"
            model_installed_at_submission = True
            ai_runtime_token = _set_ai_runtime_context(
                {
                    "provider": effective_ai_provider,
                    "model": effective_ai_model,
                    "base_url": provider_capabilities.get("baseUrl"),
                    "api_key": _remote_api_key() if effective_ai_provider == "remote_api" else None,
                }
            )

        recommended_profile = str(capabilities.get("recommendedProfile") or "balanced")
        profiles = capabilities.get("profiles") or {}
        effective_quality_profile = quality_profile if quality_profile in profiles else recommended_profile
        selected_profile = profiles.get(effective_quality_profile) or profiles.get(recommended_profile) or {}
        profile_chunk_chars = int(selected_profile.get("aiChunkChars") or 1800)
        profile_batch_size = max(1, min(4, int(selected_profile.get("aiBatchSize") or AI_SEGMENT_BATCH_SIZE)))
        profile_max_tokens = max(96, int(selected_profile.get("aiMaxTokens") or ai_max_tokens))
        structured_timeout_seconds = max(
            45,
            min(150, int(selected_profile.get("structuredTimeoutSeconds") or DEFAULT_STRUCTURED_TIMEOUT_SECONDS)),
        )
        style_timeout_seconds = max(
            60,
            min(300, int(selected_profile.get("styleTimeoutSeconds") or DEFAULT_STYLE_TIMEOUT_SECONDS)),
        )
        ai_chunk_chars = max(800, min(ai_chunk_chars, profile_chunk_chars))
        ai_max_tokens = max(96, min(ai_max_tokens, profile_max_tokens))
        online_context_references = _fetch_online_context(payload)
        effective_ai_prompt = _merge_prompt_with_context(ai_prompt, online_context_references)
        capability_profile = {
            "requestedQualityProfile": quality_profile,
            "effectiveQualityProfile": effective_quality_profile,
            "recommendedProfile": recommended_profile,
            "requestedAiProvider": requested_ai_provider if ai_enabled else None,
            "requestedAiModel": requested_ai_model if ai_enabled else None,
            "effectiveAiProvider": effective_ai_provider if ai_enabled else None,
            "effectiveAiModel": effective_ai_model if ai_enabled else None,
            "runtimeTarget": runtime_target if ai_enabled else None,
            "modelInstalledAtSubmission": model_installed_at_submission if ai_enabled else None,
            "useAdvancedAlignment": use_advanced_alignment,
            "aiRevisionPasses": ai_revision_passes,
            "aiChunkChars": ai_chunk_chars,
            "aiBatchSize": profile_batch_size,
            "aiMaxTokens": ai_max_tokens,
            "structuredTimeoutSeconds": structured_timeout_seconds,
            "styleTimeoutSeconds": style_timeout_seconds,
            "aiUseVisualContext": ai_use_visual_context,
            "onlineContextEnabled": _pick_bool(payload, "enable_online_context", "enableOnlineContext", default=False),
            "onlineReferencesUsed": len(online_context_references),
            "hardware": capabilities.get("hardware") or {},
            "contentModeRequested": content_mode_requested,
            "speakerStyleModeRequested": speaker_style_mode_requested,
            "styleIntensity": style_intensity,
            "renderedPreviewMode": rendered_preview_mode,
            "karaokeGranularityRequested": raw_karaoke_granularity or "off",
            "timeoutProfileApplied": effective_quality_profile,
        }
        capability_profile["voiceAnalysisAvailable"] = bool((capabilities.get("hardware") or {}).get("voiceAnalysisAvailable"))
        capability_profile["sceneAnalysisAvailable"] = bool((capabilities.get("hardware") or {}).get("sceneAnalysisAvailable"))

        source_file = _resolve_source_file(source_type, source_value)
        content_mode_decision = _detect_content_mode(
            content_mode_requested,
            source_file,
            effective_ai_prompt,
            context_hints,
        )
        content_mode = _normalize_content_mode(content_mode_decision.detected)
        content_detection_confidence = round(float(content_mode_decision.confidence or 0.0), 3)
        song_blocks = _detect_song_blocks(
            source_file=source_file,
            requested_mode=content_mode_requested,
            detected_mode=content_mode,
            karaoke_requested=(raw_karaoke_granularity or "off").strip().lower() != "off",
            prompt_hint=effective_ai_prompt,
            context_hints=context_hints,
        )
        musical_segment_durations = [
            {
                "type": str(block.get("type") or "anime_song"),
                "title": str(block.get("title") or block.get("label") or "").strip() or None,
                "start": round(float(block.get("start") or 0.0), 3),
                "end": round(float(block.get("end") or 0.0), 3) if block.get("end") is not None else None,
                "durationSeconds": round(float(block.get("durationSeconds") or 0.0), 3) if block.get("durationSeconds") is not None else None,
            }
            for block in song_blocks
        ]
        anime_song_layout_mode = _normalize_anime_song_layout_mode(
            _pick_str(payload, "anime_song_layout_mode", "animeSongLayoutMode", default="off"),
            content_mode,
            has_song_blocks=bool(song_blocks),
        )
        karaoke_mode_applied = _normalize_karaoke_granularity(
            raw_karaoke_granularity,
            content_mode,
            has_song_blocks=bool(song_blocks),
        )
        speaker_mode_applied = (
            "heuristic"
            if speaker_style_mode_requested == "advanced"
            else speaker_style_mode_requested
        )
        capability_profile["contentModeApplied"] = content_mode
        capability_profile["contentDetectionConfidence"] = content_detection_confidence
        capability_profile["songBlocksDetected"] = len(song_blocks)
        capability_profile["songBlocks"] = musical_segment_durations
        capability_profile["animeSongLayoutMode"] = anime_song_layout_mode
        capability_profile["karaokeModeApplied"] = karaoke_mode_applied
        capability_profile["speakerStyleModeApplied"] = speaker_mode_applied
        base_name = _base_stem(source_file)
        output_root = _build_job_output_root(source_file)
        translations_root = _ensure_dir(output_root / "translations")
        enhanced_root = _ensure_dir(output_root / "enhanced") if ai_enabled else output_root / "enhanced"
        _append_stage_diagnostic(
            diagnostics,
            stage="content_detection",
            severity="info" if content_mode_requested == content_mode else "warning",
            message=content_mode_decision.reason,
            fallback_used=None if content_mode_requested == content_mode else content_mode,
        )
        if song_blocks:
            _append_stage_diagnostic(
                diagnostics,
                stage="song_block_detection",
                severity="info",
                message=f"{len(song_blocks)} bloco(s) musical(is) detectado(s) no arquivo.",
            )
        if speaker_style_mode_requested == "advanced":
            _append_stage_diagnostic(
                diagnostics,
                stage="speaker_styling",
                severity="warning",
                message="Modo avançado de vozes caiu para heurística nesta fase; diarização real ainda não está ativa.",
                fallback_used="heuristic_overlap_layout",
            )
        _report_job_progress(
            payload,
            progress_percent=5,
            current_stage="ingestion",
            current_pass=0,
            total_passes=ai_revision_passes,
            capability_profile=capability_profile,
        )

        segments, detected_language, duration_seconds, runtime = _transcribe_base(
            source_file=source_file,
            model_name=model_name,
            task=task,
            language=input_language,
            beam_size=beam_size,
            vad_filter=vad_filter,
            word_timestamps=word_timestamps,
            device_preference=device_preference,
            compute_type_preference=compute_type_preference,
            warnings=warnings,
        )
        source_duration_seconds = duration_seconds
        source_language = _normalize_lang(detected_language if input_language == "auto" else input_language)
        _report_job_progress(
            payload,
            progress_percent=15,
            current_stage="asr",
            current_pass=0,
            total_passes=ai_revision_passes,
            capability_profile=capability_profile,
        )

        base_segments = _filter_non_speech_segments(_clone_segments(segments))
        corrected_segments = _clone_segments(base_segments)
        alignment_report = {
            "requestedMode": use_advanced_alignment,
            "usedAdvancedAlignment": False,
            "status": "disabled" if use_advanced_alignment == "off" else "fallback",
            "details": "WhisperX/alinhamento fino não está ativo nesta execução; mantendo timestamps base do ASR.",
        }
        _append_stage_diagnostic(
            diagnostics,
            stage="alignment",
            severity="warning" if use_advanced_alignment != "off" else "info",
            message=(
                "Alinhamento avançado indisponível nesta execução; usando timestamps base do ASR."
                if use_advanced_alignment != "off"
                else "Alinhamento avançado desativado."
            ),
            fallback_used="base_asr_timestamps" if use_advanced_alignment != "off" else None,
        )
        _report_job_progress(
            payload,
            progress_percent=30,
            current_stage="alignment",
            current_pass=0,
            total_passes=ai_revision_passes,
            capability_profile=capability_profile,
        )

        def _report_correction_chunk_progress(processed_chunks: int, total_chunks: int) -> None:
            progress = 31 + int((processed_chunks / max(1, total_chunks)) * 13)
            _report_job_progress(
                payload,
                progress_percent=min(44, progress),
                current_stage="correction",
                current_pass=0,
                total_passes=ai_revision_passes,
                capability_profile=capability_profile,
            )

        should_run_ai_correction = (
            ai_enabled
            and "correction" in ai_modes
            and not (task == "translate" and "semantic_translation" in ai_modes)
        )

        if ai_enabled and "correction" in ai_modes and not should_run_ai_correction:
            _append_stage_diagnostic(
                diagnostics,
                stage="correction",
                severity="info",
                message="Correção dedicada foi incorporada ao estágio de tradução semântica para reduzir latência.",
                model=ai_model,
                fallback_used="merged_into_translation",
            )

        if should_run_ai_correction:
            try:
                corrected_segments = _correct_segments_with_ollama(
                    segments=base_segments,
                    language=source_language,
                    model=ai_model,
                    prompt_hint=effective_ai_prompt,
                    temperature=ai_temperature,
                    top_p=ai_top_p,
                    num_predict=ai_max_tokens,
                    chunk_chars=ai_chunk_chars,
                    batch_size=profile_batch_size,
                    timeout_seconds=structured_timeout_seconds,
                    progress_callback=_report_correction_chunk_progress,
                )
                _append_stage_diagnostic(
                    diagnostics,
                    stage="correction",
                    severity="info",
                    message="Correção por IA aplicada com sucesso.",
                    model=ai_model,
                    source_field="ollama",
                )
            except Exception as exc:
                warnings.append(f"Correção por IA falhou; seguindo com texto base: {exc}")
                context = _ollama_error_context(exc)
                _append_stage_diagnostic(
                    diagnostics,
                    stage="correction",
                    severity="warning",
                    message="Correção por IA falhou; seguindo com texto base.",
                    model=context.get("model") or ai_model,
                    fallback_used="base_text",
                    raw_excerpt=context.get("raw_excerpt"),
                    source_field=context.get("source_field"),
                    duration_ms=context.get("duration_ms"),
                )
                corrected_segments = _clone_segments(base_segments)

        corrected_segments = _filter_non_speech_segments(corrected_segments)
        song_segment_indices = _build_song_segment_index_set(corrected_segments, song_blocks)
        review_model_used = ai_model if ai_enabled and any(mode in ai_modes for mode in ("correction", "semantic_translation")) else None
        _report_job_progress(
            payload,
            progress_percent=45,
            current_stage="cleanup",
            current_pass=0,
            total_passes=ai_revision_passes,
            capability_profile=capability_profile,
        )

        english_reference_segments: list[dict[str, Any]] | None | object = _UNSET
        english_reference_strategy = "none"

        def _get_english_reference_segments() -> list[dict[str, Any]] | None:
            nonlocal english_reference_segments, english_reference_strategy
            if english_reference_segments is not _UNSET:
                return english_reference_segments

            english_reference_segments = None
            english_reference_strategy = "none"
            if source_language == "en":
                return None

            try:
                english_reference_segments = _translate_source_file_with_faster_whisper(
                    source_file=source_file,
                    model_name=model_name,
                    input_language=input_language,
                    beam_size=beam_size,
                    vad_filter=vad_filter,
                    device_preference=device_preference,
                    compute_type_preference=compute_type_preference,
                )
                english_reference_segments = _apply_timing_fit(
                    _filter_non_speech_segments(english_reference_segments)
                )
                if len(english_reference_segments) != len(corrected_segments):
                    english_reference_strategy = "time_remap"
                    english_reference_segments = _remap_reference_segments_by_time(
                        corrected_segments,
                        english_reference_segments,
                    )
                    _append_stage_diagnostic(
                        diagnostics,
                        stage="semantic_translation",
                        severity="warning",
                        message="Referência semântica em inglês foi remapeada por tempo por divergência de segmentação.",
                        model=model_name,
                        fallback_used="time_remap",
                    )
                else:
                    english_reference_strategy = "exact"
                _append_stage_diagnostic(
                    diagnostics,
                    stage="semantic_translation",
                    severity="info",
                    message="Referência semântica em inglês preparada via faster-whisper local.",
                    model=model_name,
                    fallback_used="english_reference",
                )
            except Exception as exc:
                warnings.append(f"Referência semântica em inglês indisponível nesta execução: {exc}")
                _append_stage_diagnostic(
                    diagnostics,
                    stage="semantic_translation",
                    severity="warning",
                    message="Referência semântica em inglês não pôde ser preparada.",
                    model=model_name,
                    fallback_used="no_english_reference",
                )
                english_reference_segments = None

            return english_reference_segments

        translations_manifest = {
            "sourceLanguage": _display_lang(source_language),
            "languages": {},
        }
        translated_segments_by_language: dict[str, list[dict[str, Any]]] = {}
        render_segments_by_language: dict[str, list[dict[str, Any]]] = {}
        rendered_by_language: dict[str, dict[str, str]] = {}
        translation_statuses = {}
        overall_quality_summary = {}

        if task == "translate" and not target_languages:
            raise ValueError("Task=translate requer ao menos um idioma de saída em targetLanguages.")

        publish_languages = target_languages[:] if task == "translate" else []
        review_pass_counter = 0

        total_publish_languages = max(1, len(publish_languages))

        for language_index, language_code in enumerate(publish_languages, start=1):
            normalized_target = _normalize_lang(language_code)
            language_label = _display_lang(normalized_target)
            translation_source = "source_passthrough"
            summary: dict[str, Any] | None = None
            translation_progress_start = min(
                79,
                55 + int(((language_index - 1) / total_publish_languages) * 20),
            )
            translation_progress_end = min(
                79,
                max(
                    translation_progress_start,
                    55 + int((language_index / total_publish_languages) * 20) - 1,
                ),
            )

            _report_job_progress(
                payload,
                progress_percent=translation_progress_start,
                current_stage="translation",
                current_pass=0,
                total_passes=ai_revision_passes,
                quality_summary=overall_quality_summary,
                translation_statuses=translation_statuses,
                capability_profile=capability_profile,
            )

            if not _should_translate(normalized_target, source_language):
                translated_segments = _clone_segments(corrected_segments)
            else:
                translated_segments = None
                reference_segments = None
                ai_failure_message: str | None = None
                translation_source = "ai_semantic"

                def _report_translation_chunk_progress(processed_chunks: int, total_chunks: int) -> None:
                    span = max(1, translation_progress_end - translation_progress_start)
                    progress = translation_progress_start + int(
                        (processed_chunks / max(1, total_chunks)) * span
                    )
                    _report_job_progress(
                        payload,
                        progress_percent=min(79, progress),
                        current_stage="translation",
                        current_pass=0,
                        total_passes=ai_revision_passes,
                        quality_summary=overall_quality_summary,
                        translation_statuses=translation_statuses,
                        capability_profile=capability_profile,
                    )

                if normalized_target == "en":
                    reference_segments = _get_english_reference_segments()
                    if reference_segments and _should_use_english_reference_as_primary_translation(
                        ai_enabled=ai_enabled,
                        target_language=normalized_target,
                    ):
                        translated_segments = _clone_segments(reference_segments)
                        translation_source = "faster_whisper_local"
                        _append_stage_diagnostic(
                            diagnostics,
                            stage="semantic_translation",
                            severity="info",
                            message=(
                                f"Tradução base para {language_label} preparada via faster-whisper local "
                                f"({english_reference_strategy or 'reference'})."
                            ),
                            model=model_name,
                            language=language_label,
                            fallback_used="english_reference",
                        )
                    elif reference_segments:
                        _append_stage_diagnostic(
                            diagnostics,
                            stage="semantic_translation",
                            severity="info",
                            message=(
                                f"Referência semântica em inglês anexada como contexto de tradução para {language_label}."
                            ),
                            model=model_name,
                            language=language_label,
                            fallback_used="english_reference_context",
                        )
                elif ai_enabled:
                    reference_segments = _get_english_reference_segments()
                    if reference_segments:
                        _append_stage_diagnostic(
                            diagnostics,
                            stage="semantic_translation",
                            severity="info",
                            message=f"Referência semântica em inglês anexada para {language_label}.",
                            model=model_name,
                            language=language_label,
                            fallback_used="english_reference_context",
                        )

                if ai_enabled and (translated_segments is None or normalized_target != "en"):
                    try:
                        translated_segments = _translate_segments_with_ollama(
                            segments=corrected_segments,
                            source_language=source_language,
                            target_language=normalized_target,
                            reference_segments=reference_segments,
                            song_segment_indices=song_segment_indices,
                            model=ai_model,
                            prompt_hint=effective_ai_prompt,
                            temperature=ai_temperature,
                            top_p=ai_top_p,
                            num_predict=ai_max_tokens,
                            chunk_chars=ai_chunk_chars,
                            batch_size=profile_batch_size,
                            timeout_seconds=structured_timeout_seconds,
                            progress_callback=_report_translation_chunk_progress,
                        )
                    except Exception as exc:
                        translation_source = "controlled_fallback"
                        ai_failure_message = (
                            f"Tradução para {language_label} falhou na etapa de IA: {exc}"
                        )
                        warnings.append(
                            f"Tradução para {language_label} falhou na IA; tentando fallback controlado: {exc}"
                        )
                        context = _ollama_error_context(exc)
                        _append_stage_diagnostic(
                            diagnostics,
                            stage="semantic_translation",
                            severity="warning",
                            message=f"Tradução para {language_label} falhou na etapa de IA.",
                            model=context.get("model") or ai_model,
                            language=language_label,
                            fallback_used="controlled_fallback",
                            raw_excerpt=context.get("raw_excerpt"),
                            source_field=context.get("source_field"),
                            duration_ms=context.get("duration_ms"),
                        )

                # Faster-whisper can only translate speech to English, so use it first as a local fallback for English.
                if translated_segments is None and normalized_target == "en":
                    try:
                        translated_segments = _get_english_reference_segments()
                        if translated_segments is not None:
                            translation_source = "faster_whisper_local"
                            warnings.append("Tradução para inglês executada via faster-whisper como fallback semântico local.")
                            _append_stage_diagnostic(
                                diagnostics,
                                stage="semantic_translation",
                                severity="warning" if ai_failure_message else "info",
                                message=f"Tradução para {language_label} executada via faster-whisper local.",
                                model=model_name,
                                language=language_label,
                                fallback_used="faster_whisper_local" if ai_failure_message else None,
                            )
                    except Exception as exc:
                        warnings.append(
                            f"Fallback local para {language_label} via faster-whisper falhou: {exc}"
                        )

                if translated_segments is None:
                    try:
                        translated_segments = _translate_segments_with_argos(
                            segments=corrected_segments,
                            source_language=source_language,
                            target_language=normalized_target,
                        )
                        if translated_segments is not None:
                            translation_source = "argos_offline"
                            warnings.append(
                                f"Tradução para {language_label} executada via Argos Translate offline."
                            )
                            _append_stage_diagnostic(
                                diagnostics,
                                stage="semantic_translation",
                                severity="warning" if ai_failure_message else "info",
                                message=f"Tradução para {language_label} executada via Argos Translate offline.",
                                model=ai_model if ai_failure_message else "argos",
                                language=language_label,
                                fallback_used="argos_offline" if ai_failure_message else None,
                            )
                    except Exception as exc:
                        warnings.append(
                            f"Fallback offline Argos para {language_label} falhou: {exc}"
                        )

                if translated_segments is None and normalized_target != "en":
                    try:
                        english_segments = _get_english_reference_segments()
                        if english_segments is not None:
                            translated_segments = _translate_segments_with_argos(
                                segments=english_segments,
                                source_language="en",
                                target_language=normalized_target,
                            )
                        if translated_segments is not None:
                            translation_source = "faster_whisper_argos_chain"
                            warnings.append(
                                f"Tradução para {language_label} executada via cadeia offline faster-whisper(en)+Argos."
                            )
                            _append_stage_diagnostic(
                                diagnostics,
                                stage="semantic_translation",
                                severity="warning" if ai_failure_message else "info",
                                message=f"Tradução para {language_label} executada via cadeia offline faster-whisper(en)+Argos.",
                                model=model_name,
                                language=language_label,
                                fallback_used="faster_whisper_argos_chain" if ai_failure_message else None,
                            )
                    except Exception as exc:
                        warnings.append(
                            f"Fallback offline em cadeia para {language_label} falhou: {exc}"
                        )

                if translated_segments is None:
                    failure_reason = (
                        ai_failure_message
                        or f"Tradução para {language_label} indisponível sem um backend local compatível."
                    )
                    warnings.append(failure_reason)
                    translations_manifest["languages"][language_label] = {
                        "status": "failed",
                        "failureReason": failure_reason,
                    }
                    translation_statuses[language_label] = {
                        "status": "failed",
                        "failureReason": failure_reason,
                        "source": translation_source,
                    }
                    _append_stage_diagnostic(
                        diagnostics,
                        stage="semantic_translation",
                        severity="warning",
                        message=f"Idioma {language_label} não foi publicado.",
                        model=ai_model if ai_enabled else model_name,
                        language=language_label,
                        fallback_used="not_published",
                    )
                    continue

                translated_segments = _sanitize_translated_segments(corrected_segments, translated_segments)
                translated_segments = _apply_timing_fit(translated_segments)
                scores, summary = _score_and_summarize_translation(
                    source_segments=corrected_segments,
                    translated_segments=translated_segments,
                    source_language=source_language,
                    target_language=normalized_target,
                    ai_enabled=ai_enabled,
                    model=ai_model if ai_enabled else None,
                    prompt_hint=effective_ai_prompt,
                    reference_segments=reference_segments,
                    song_segment_indices=song_segment_indices,
                    batch_size=profile_batch_size,
                    timeout_seconds=structured_timeout_seconds,
                    warnings=warnings,
                    content_mode=content_mode,
                )

                for current_pass in range(1, ai_revision_passes + 1):
                    if float(summary.get("averageScore") or 0) >= QUALITY_PUBLISH_THRESHOLD and int(summary.get("failedSegments") or 0) == 0:
                        break
                    if not ai_enabled or translation_source == "source_passthrough":
                        break

                    review_pass_counter = max(review_pass_counter, current_pass)
                    _report_job_progress(
                        payload,
                        progress_percent=min(80, 65 + max(1, int((current_pass / max(1, ai_revision_passes)) * 15))),
                        current_stage="review",
                        current_pass=current_pass,
                        total_passes=ai_revision_passes,
                        capability_profile=capability_profile,
                    )
                    translated_segments = _revise_segments_with_ollama(
                        source_segments=corrected_segments,
                        current_segments=translated_segments,
                        reference_segments=reference_segments,
                        target_language=normalized_target,
                        song_segment_indices=song_segment_indices,
                        model=ai_model,
                        prompt_hint=effective_ai_prompt,
                        temperature=ai_temperature,
                        top_p=ai_top_p,
                        num_predict=ai_max_tokens,
                        batch_size=profile_batch_size,
                        timeout_seconds=structured_timeout_seconds,
                    )
                    translated_segments = _apply_timing_fit(
                        _sanitize_translated_segments(corrected_segments, translated_segments)
                    )
                    scores, summary = _score_and_summarize_translation(
                        source_segments=corrected_segments,
                        translated_segments=translated_segments,
                        source_language=source_language,
                        target_language=normalized_target,
                        ai_enabled=ai_enabled,
                        model=ai_model if ai_enabled else None,
                        prompt_hint=effective_ai_prompt,
                        reference_segments=reference_segments,
                        song_segment_indices=song_segment_indices,
                        batch_size=profile_batch_size,
                        timeout_seconds=structured_timeout_seconds,
                        warnings=warnings,
                        content_mode=content_mode,
                    )

                if normalized_target == "en":
                    rescue_reference = _get_english_reference_segments()
                    translated_segments, rescued_count = _rescue_low_quality_segments(
                        source_segments=corrected_segments,
                        translated_segments=translated_segments,
                        rescue_segments=(
                            rescue_reference
                            if english_reference_strategy in {"exact", "time_remap"}
                            else None
                        ),
                        source_language=source_language,
                        target_language=normalized_target,
                    )
                    if rescued_count > 0:
                        scores, summary = _score_and_summarize_translation(
                            source_segments=corrected_segments,
                            translated_segments=translated_segments,
                            source_language=source_language,
                            target_language=normalized_target,
                            ai_enabled=ai_enabled,
                            model=ai_model if ai_enabled else None,
                            prompt_hint=effective_ai_prompt,
                            reference_segments=reference_segments,
                            song_segment_indices=song_segment_indices,
                            batch_size=profile_batch_size,
                            timeout_seconds=structured_timeout_seconds,
                            warnings=warnings,
                            content_mode=content_mode,
                        )
                        _append_stage_diagnostic(
                            diagnostics,
                            stage="review_score",
                            severity="info",
                            message=(
                                f"{rescued_count} segmento(s) de baixa qualidade em {language_label} "
                                "foram substituídos por referência semântica local."
                            ),
                            model=model_name,
                            language=language_label,
                            fallback_used="english_reference_segment_rescue",
                        )

                if not translated_segments or not _segments_text(translated_segments):
                    if _should_publish_empty_translation(
                        source_segments=corrected_segments,
                        translated_segments=translated_segments,
                    ):
                        summary = {
                            "averageScore": 100,
                            "minScore": 100,
                            "publishableSegments": 0,
                            "reviewSegments": 0,
                            "failedSegments": 0,
                            "suppressedNoiseSegments": 0,
                            "instrumentalSegments": len(corrected_segments),
                        }
                        translation_source = "instrumental_passthrough"
                        _append_stage_diagnostic(
                            diagnostics,
                            stage="semantic_translation",
                            severity="info",
                            message=(
                                f"Nenhuma fala ou verso detectado em {language_label}; "
                                "publicando bloco instrumental sem texto."
                            ),
                            model=ai_model if ai_enabled else model_name,
                            language=language_label,
                            fallback_used="instrumental_passthrough",
                        )
                    else:
                        failure_reason = f"Tradução para {language_label} ficou vazia; idioma não será publicado."
                        warnings.append(failure_reason)
                        translations_manifest["languages"][language_label] = {
                            "status": "failed",
                            "failureReason": failure_reason,
                        }
                        translation_statuses[language_label] = {
                            "status": "failed",
                            "failureReason": failure_reason,
                            "quality": summary,
                            "source": translation_source,
                        }
                        _append_stage_diagnostic(
                            diagnostics,
                            stage="semantic_translation",
                            severity="warning",
                            message=f"Tradução para {language_label} ficou vazia.",
                            model=ai_model if ai_enabled else model_name,
                            language=language_label,
                            fallback_used="not_published",
                        )
                        continue

                # Prevent false-success when target differs but output is basically identical.
                if _segments_text(corrected_segments) or _segments_text(translated_segments):
                    identical = 0
                    total = 0
                    for left, right in zip(corrected_segments, translated_segments):
                        ltext = _segment_text(left)
                        rtext = _segment_text(right)
                        if not ltext and not rtext:
                            continue
                        total += 1
                        if ltext == rtext:
                            identical += 1
                    ratio = 1.0 if total == 0 else identical / total
                    if ratio >= 0.95 and _should_translate(normalized_target, source_language):
                        failure_reason = (
                            f"Tradução para {language_label} voltou praticamente igual ao original; idioma não será publicado."
                        )
                        warnings.append(failure_reason)
                        translations_manifest["languages"][language_label] = {
                            "status": "failed",
                            "failureReason": failure_reason,
                        }
                        translation_statuses[language_label] = {
                            "status": "failed",
                            "failureReason": failure_reason,
                            "quality": summary,
                            "source": translation_source,
                        }
                        _append_stage_diagnostic(
                            diagnostics,
                            stage="semantic_translation",
                            severity="warning",
                            message=f"Tradução para {language_label} permaneceu praticamente igual ao original.",
                            model=ai_model if ai_enabled else model_name,
                            language=language_label,
                            fallback_used="not_published",
                        )
                        continue

                if summary is None:
                    scores, summary = _score_and_summarize_translation(
                        source_segments=corrected_segments,
                        translated_segments=translated_segments,
                        source_language=source_language,
                        target_language=normalized_target,
                        ai_enabled=ai_enabled,
                        model=ai_model if ai_enabled else None,
                        prompt_hint=effective_ai_prompt,
                        reference_segments=reference_segments,
                        song_segment_indices=song_segment_indices,
                        batch_size=profile_batch_size,
                        timeout_seconds=structured_timeout_seconds,
                        warnings=warnings,
                        content_mode=content_mode,
                    )

                if not _quality_is_publishable(summary, len(translated_segments)):
                    if normalized_target == "en" and ai_enabled:
                        try:
                            ai_rescued_segments, ai_rescued_count = _retranslate_low_quality_segments_with_ollama(
                                source_segments=corrected_segments,
                                translated_segments=translated_segments,
                                reference_segments=reference_segments,
                                source_language=source_language,
                                target_language=normalized_target,
                                song_segment_indices=song_segment_indices,
                                model=ai_model,
                                prompt_hint=effective_ai_prompt,
                                temperature=ai_temperature,
                                top_p=ai_top_p,
                                num_predict=ai_max_tokens,
                                chunk_chars=ai_chunk_chars,
                                batch_size=profile_batch_size,
                                timeout_seconds=structured_timeout_seconds,
                                content_mode=content_mode,
                            )
                            if ai_rescued_count > 0:
                                _, ai_rescue_summary = _score_and_summarize_translation(
                                    source_segments=corrected_segments,
                                    translated_segments=ai_rescued_segments,
                                    source_language=source_language,
                                    target_language=normalized_target,
                                    ai_enabled=ai_enabled,
                                    model=ai_model if ai_enabled else None,
                                    prompt_hint=effective_ai_prompt,
                                    reference_segments=reference_segments,
                                    song_segment_indices=song_segment_indices,
                                    batch_size=profile_batch_size,
                                    timeout_seconds=structured_timeout_seconds,
                                    warnings=warnings,
                                    content_mode=content_mode,
                                )
                                if _quality_summary_rank(
                                    ai_rescue_summary,
                                    len(ai_rescued_segments),
                                ) > _quality_summary_rank(
                                    summary,
                                    len(translated_segments),
                                ):
                                    translated_segments = ai_rescued_segments
                                    summary = ai_rescue_summary
                                    translation_source = "faster_whisper_local_ai_segment_rescue"
                                    _append_stage_diagnostic(
                                        diagnostics,
                                        stage="review_score",
                                        severity="warning",
                                        message=(
                                            f"Idioma {language_label} teve {ai_rescued_count} segmento(s) "
                                            "retraduzido(s) pela IA a partir da referência local."
                                        ),
                                        model=ai_model,
                                        language=language_label,
                                        fallback_used="ai_segment_rescue",
                                    )
                        except Exception as exc:
                            warnings.append(
                                f"Retradução segmentada por IA para {language_label} falhou: {exc}"
                            )

                    rescued_segments = None
                    rescued_source = None

                    if normalized_target == "en" and translation_source != "faster_whisper_local" and english_reference_strategy in {"exact", "time_remap"}:
                        rescued_segments = _get_english_reference_segments()
                        rescued_source = "faster_whisper_local"
                    elif normalized_target != "en" and translation_source != "english_reference_ai_chain":
                        english_segments = _get_english_reference_segments()
                        if english_segments is not None:
                            try:
                                rescued_segments = _translate_segments_with_ollama(
                                    segments=english_segments,
                                    source_language="en",
                                    target_language=normalized_target,
                                    reference_segments=None,
                                    song_segment_indices=song_segment_indices,
                                    model=ai_model,
                                    prompt_hint=effective_ai_prompt,
                                    temperature=ai_temperature,
                                    top_p=ai_top_p,
                                    num_predict=ai_max_tokens,
                                    chunk_chars=ai_chunk_chars,
                                    batch_size=profile_batch_size,
                                    timeout_seconds=structured_timeout_seconds,
                                )
                                rescued_source = "english_reference_ai_chain"
                            except Exception as exc:
                                warnings.append(
                                    f"Resgate semântico via referência em inglês para {language_label} falhou: {exc}"
                                )

                    if rescued_segments is None and normalized_target != "en" and translation_source != "faster_whisper_argos_chain":
                        english_segments = _get_english_reference_segments()
                        if english_segments is not None:
                            rescued_segments = _translate_segments_with_argos(
                                segments=english_segments,
                                source_language="en",
                                target_language=normalized_target,
                            )
                            rescued_source = "faster_whisper_argos_chain"

                    if rescued_segments is not None:
                        rescued_segments = _apply_timing_fit(
                            _sanitize_translated_segments(corrected_segments, rescued_segments)
                        )
                        _, rescue_summary = _score_and_summarize_translation(
                            source_segments=corrected_segments,
                            translated_segments=rescued_segments,
                            source_language=source_language,
                            target_language=normalized_target,
                            ai_enabled=ai_enabled,
                            model=ai_model if ai_enabled else None,
                            prompt_hint=effective_ai_prompt,
                            reference_segments=reference_segments,
                            song_segment_indices=song_segment_indices,
                            batch_size=profile_batch_size,
                            timeout_seconds=structured_timeout_seconds,
                            warnings=warnings,
                            content_mode=content_mode,
                        )
                        best_rescue_segments = rescued_segments
                        best_rescue_summary = rescue_summary
                        best_rescue_source = rescued_source or translation_source
                        best_rescue_replacements = 0

                        merged_rescue_segments, rescued_count = _rescue_low_quality_segments(
                            source_segments=corrected_segments,
                            translated_segments=translated_segments,
                            rescue_segments=rescued_segments,
                            source_language=source_language,
                            target_language=normalized_target,
                        )
                        if rescued_count > 0:
                            _, merged_rescue_summary = _score_and_summarize_translation(
                                source_segments=corrected_segments,
                                translated_segments=merged_rescue_segments,
                                source_language=source_language,
                                target_language=normalized_target,
                                ai_enabled=ai_enabled,
                                model=ai_model if ai_enabled else None,
                                prompt_hint=effective_ai_prompt,
                                reference_segments=reference_segments,
                                song_segment_indices=song_segment_indices,
                                batch_size=profile_batch_size,
                                timeout_seconds=structured_timeout_seconds,
                                warnings=warnings,
                                content_mode=content_mode,
                            )
                            if _quality_summary_rank(
                                merged_rescue_summary,
                                len(merged_rescue_segments),
                            ) > _quality_summary_rank(
                                best_rescue_summary,
                                len(best_rescue_segments),
                            ):
                                best_rescue_segments = merged_rescue_segments
                                best_rescue_summary = merged_rescue_summary
                                best_rescue_source = (
                                    f"{rescued_source}_segment_rescue"
                                    if rescued_source
                                    else "segment_rescue"
                                )
                                best_rescue_replacements = rescued_count

                        if _quality_summary_rank(
                            best_rescue_summary,
                            len(best_rescue_segments),
                        ) > _quality_summary_rank(
                            summary,
                            len(translated_segments),
                        ):
                            translated_segments = best_rescue_segments
                            summary = best_rescue_summary
                            translation_source = best_rescue_source
                            _append_stage_diagnostic(
                                diagnostics,
                                stage="review_score",
                                severity="warning",
                                message=(
                                    f"Idioma {language_label} foi resgatado por fallback de qualidade."
                                    if best_rescue_replacements <= 0
                                    else (
                                        f"Idioma {language_label} teve {best_rescue_replacements} segmento(s) "
                                        "resgatado(s) por fallback de qualidade."
                                    )
                                ),
                                model=model_name,
                                language=language_label,
                                fallback_used=translation_source,
                            )

                soft_publishable = _quality_is_soft_publishable(summary, len(translated_segments))
                local_non_ai_publishable = (
                    not ai_enabled
                    and translation_source == "faster_whisper_local"
                    and _quality_is_local_non_ai_publishable(summary, len(translated_segments))
                )
                soft_publishable = soft_publishable or local_non_ai_publishable
                if not _quality_is_publishable(summary, len(translated_segments)) and not soft_publishable:
                    failure_reason = (
                        f"Tradução para {language_label} reprovada na revisão de qualidade "
                        f"(score médio {summary.get('averageScore')})."
                    )
                    warnings.append(failure_reason)
                    translations_manifest["languages"][language_label] = {
                        "status": "failed",
                        "failureReason": failure_reason,
                    }
                    translation_statuses[language_label] = {
                        "status": "failed",
                        "failureReason": failure_reason,
                        "quality": summary,
                        "source": translation_source,
                    }
                    _append_stage_diagnostic(
                        diagnostics,
                        stage="review_score",
                        severity="warning",
                        message=f"Idioma {language_label} não atingiu o threshold de qualidade.",
                        model=ai_model if ai_enabled else model_name,
                        language=language_label,
                        fallback_used="not_published",
                    )
                    continue

                if soft_publishable and not _quality_is_publishable(summary, len(translated_segments)):
                    summary = dict(summary)
                    summary["softPublished"] = True
                    if local_non_ai_publishable:
                        summary["softPublishReason"] = "local_non_ai_gate"
                    _append_stage_diagnostic(
                        diagnostics,
                        stage="review_score",
                        severity="warning",
                        message=(
                            (
                                f"Idioma {language_label} publicado com warnings após gate "
                                "local sem IA para poucos segmentos limítrofes."
                                if local_non_ai_publishable
                                else f"Idioma {language_label} publicado com warnings após soft gate "
                                "de qualidade para poucos segmentos limítrofes."
                            )
                        ),
                        model=ai_model if ai_enabled else model_name,
                        language=language_label,
                        fallback_used="local_non_ai_quality_gate" if local_non_ai_publishable else "soft_quality_gate",
                    )

            translated_segments_by_language[language_label] = _clone_segments(translated_segments)
            translation_statuses[language_label] = {
                "status": "published",
                "quality": summary,
                "source": translation_source,
                "passesUsed": review_pass_counter,
            }
            if translation_source == "source_passthrough":
                _append_stage_diagnostic(
                    diagnostics,
                    stage="semantic_translation",
                    severity="info",
                    message=f"Idioma {language_label} publicado usando o texto-base.",
                    model=model_name,
                    language=language_label,
                )
            elif translation_source == "ai_semantic":
                _append_stage_diagnostic(
                    diagnostics,
                    stage="semantic_translation",
                    severity="info",
                    message=f"Tradução para {language_label} publicada com sucesso via IA.",
                    model=ai_model,
                    language=language_label,
                )

            _report_job_progress(
                payload,
                progress_percent=min(
                    80,
                    55 + int((language_index / total_publish_languages) * 20),
                ),
                current_stage="translation",
                current_pass=review_pass_counter,
                total_passes=ai_revision_passes,
                quality_summary=overall_quality_summary,
                translation_statuses=translation_statuses,
                capability_profile=capability_profile,
            )

        if task == "translate" and not translated_segments_by_language:
            raise RuntimeError("Nenhuma tradução válida foi gerada para os idiomas solicitados.")

        overall_quality_summary = {
            "publishedLanguages": sorted([
                key for key, value in translation_statuses.items()
                if str(value.get("status")).lower() == "published"
            ]),
            "failedLanguages": sorted([
                key for key, value in translation_statuses.items()
                if str(value.get("status")).lower() != "published"
            ]),
            "languages": translation_statuses,
        }
        _report_job_progress(
            payload,
            progress_percent=80,
            current_stage="review",
            current_pass=review_pass_counter,
            total_passes=ai_revision_passes,
            quality_summary=overall_quality_summary,
            translation_statuses=translation_statuses,
            capability_profile=capability_profile,
        )

        style_visual_context_enabled = ai_use_visual_context
        planner_primary_model = ai_model
        planner_fallback_models: list[str] = []

        style_plan, style_source, style_meta = _plan_visual_style(
            preset=subtitle_style,
            prompt_hint=effective_ai_prompt,
            ai_enabled=ai_enabled,
            ai_modes=ai_modes,
            ai_use_visual_context=style_visual_context_enabled,
            source_file=source_file,
            ai_model=planner_primary_model,
            fallback_ai_models=planner_fallback_models,
            ai_temperature=ai_temperature,
            ai_top_p=ai_top_p,
            ai_max_tokens=ai_max_tokens,
            ai_frame_sample_seconds=ai_frame_sample_seconds,
            timeout_seconds=style_timeout_seconds,
            warnings=warnings,
            content_mode=content_mode,
            style_intensity=style_intensity,
        )
        planner_model_used = (
            str((style_meta or {}).get("model")).strip()
            if style_meta and str((style_meta or {}).get("model") or "").strip()
            else planner_primary_model
        )
        style_label_segments = corrected_segments
        if task == "translate" and translated_segments_by_language:
            style_label_segments = next(iter(translated_segments_by_language.values()))

        style_labels, label_source = _build_segment_style_labels(
            segments=style_label_segments,
            preset=subtitle_style,
            prompt_hint=effective_ai_prompt,
            ai_enabled=ai_enabled and quality_profile != "safe",
            ai_modes=ai_modes,
            ai_model=ai_model,
            ai_temperature=ai_temperature,
            ai_top_p=ai_top_p,
            ai_batch_size=max(2, profile_batch_size),
            timeout_seconds=structured_timeout_seconds,
            warnings=warnings,
            content_mode=content_mode,
        )
        effective_style_source = style_source
        corrected_segments = _apply_style_labels(corrected_segments, style_labels)
        for language_label, items in list(translated_segments_by_language.items()):
            translated_segments_by_language[language_label] = _apply_style_labels(items, style_labels)

        if ai_enabled and "subtitle_styling" in ai_modes:
            style_message = "Plano visual aplicado com sucesso."
            style_severity = "info" if style_source == "ai_plan" else "warning"
            fallback_used: str | None = None if style_source == "ai_plan" else "local_preset"
            if style_source != "ai_plan" and label_source == "ai_labels":
                style_message = "Plano visual caiu em preset local, mas os rótulos por trecho vieram da IA."
            elif style_source == "ai_plan" and label_source != "ai_labels":
                style_message = "Plano visual aplicado via IA com rótulos heurísticos por trecho."

            _append_stage_diagnostic(
                diagnostics,
                stage="subtitle_styling",
                severity=style_severity,
                message=style_message,
                model=ai_model,
                fallback_used=fallback_used,
                raw_excerpt=(style_meta or {}).get("raw_excerpt"),
                source_field=(style_meta or {}).get("source_field"),
                duration_ms=(style_meta or {}).get("duration_ms"),
            )

        _report_job_progress(
            payload,
            progress_percent=90,
            current_stage="styling",
            current_pass=review_pass_counter,
            total_passes=ai_revision_passes,
            quality_summary=overall_quality_summary,
            translation_statuses=translation_statuses,
            style_source=effective_style_source,
            capability_profile=capability_profile,
        )

        style_map = {
            "styleSource": effective_style_source,
            "labelSource": label_source,
            "contentMode": content_mode,
            "contentDetectionConfidence": content_detection_confidence,
            "styleIntensity": style_intensity,
            "speakerModeApplied": speaker_mode_applied,
            "karaokeModeApplied": karaoke_mode_applied,
            "animeSongLayoutMode": anime_song_layout_mode,
            "stylePlan": style_plan,
            "segments": [
                {
                    "index": index,
                    "label": style_labels[index] if index < len(style_labels) else "default",
                    "text": _segment_text(segment),
                    "styleReferenceText": _segment_text(style_label_segments[index]) if index < len(style_label_segments) else "",
                }
                for index, segment in enumerate(corrected_segments)
            ],
        }

        primary_language_key = _display_lang(source_language)
        if task == "translate" and translated_segments_by_language:
            primary_language_key = next(iter(translated_segments_by_language.keys()))

        primary_render_segments = _prepare_render_segments(
            source_segments=corrected_segments,
            rendered_segments=(
                translated_segments_by_language.get(primary_language_key)
                if task == "translate" and primary_language_key in translated_segments_by_language
                else corrected_segments
            ),
            content_mode=content_mode,
            anime_song_layout_mode=anime_song_layout_mode,
            speaker_style_mode=speaker_mode_applied,
            karaoke_granularity=karaoke_mode_applied,
            song_blocks=song_blocks,
        )
        _report_job_progress(
            payload,
            progress_percent=84,
            current_stage="voice_analysis",
            current_pass=review_pass_counter,
            total_passes=ai_revision_passes,
            quality_summary=overall_quality_summary,
            translation_statuses=translation_statuses,
            capability_profile=capability_profile,
        )
        voice_analysis, speaker_mode_applied, voice_analysis_source = _build_voice_analysis(
            source_segments=primary_render_segments,
            speaker_style_mode_requested=speaker_style_mode_requested,
            diarization_available=bool((capabilities.get("hardware") or {}).get("diarizationAvailable")),
        )
        _append_stage_diagnostic(
            diagnostics,
            stage="voice_analysis",
            severity="warning" if speaker_style_mode_requested == "advanced" and speaker_mode_applied != "advanced" else "info",
            message=(
                "Diarização real indisponível; análise de vozes caiu para heurística por overlap."
                if speaker_style_mode_requested == "advanced" and speaker_mode_applied != "advanced"
                else "Análise de vozes concluída."
            ),
            fallback_used=voice_analysis_source if voice_analysis_source != "diarization" else None,
        )

        _report_job_progress(
            payload,
            progress_percent=86,
            current_stage="scene_analysis",
            current_pass=review_pass_counter,
            total_passes=ai_revision_passes,
            quality_summary=overall_quality_summary,
            translation_statuses=translation_statuses,
            capability_profile=capability_profile,
        )
        scene_map, scene_analysis_source = _build_scene_map(
            segments=primary_render_segments,
            content_mode=content_mode,
            voice_analysis=voice_analysis,
        )
        _append_stage_diagnostic(
            diagnostics,
            stage="scene_analysis",
            severity="info",
            message="Blocos de cena foram agrupados para render determinístico.",
            fallback_used=scene_analysis_source,
        )
        style_map["speakerSpans"] = voice_analysis.get("spans") or []
        style_map["sceneSegments"] = scene_map.get("scenes") or []
        style_map["voiceAnalysisSource"] = voice_analysis_source
        style_map["sceneAnalysisSource"] = scene_analysis_source
        style_map["plannerModelUsed"] = planner_model_used
        style_map["reviewModelUsed"] = review_model_used

        if task == "translate":
            for language_label, translated_segments in translated_segments_by_language.items():
                language_dir = _ensure_dir(translations_root / language_label)
                render_segments = _prepare_render_segments(
                    source_segments=corrected_segments,
                    rendered_segments=translated_segments,
                    content_mode=content_mode,
                    anime_song_layout_mode=anime_song_layout_mode,
                    speaker_style_mode=speaker_mode_applied,
                    karaoke_granularity=karaoke_mode_applied,
                    song_blocks=song_blocks,
                )
                rendered = _render_outputs_for_segments(
                    output_dir=language_dir,
                    base_name=base_name,
                    segments=render_segments,
                    requested_outputs=requested_outputs,
                    max_subtitle_chars=max_subtitle_chars,
                    style=style_plan,
                    content_mode=content_mode,
                    anime_song_layout_mode=anime_song_layout_mode,
                )
                render_segments_by_language[language_label] = render_segments
                rendered_by_language[language_label] = rendered
                translations_manifest["languages"][language_label] = {
                    "status": "published",
                    "outputs": rendered,
                    "quality": translation_statuses.get(language_label, {}).get("quality"),
                    "source": translation_statuses.get(language_label, {}).get("source"),
                }

        if task == "translate" and primary_language_key in rendered_by_language:
            primary_outputs = dict(rendered_by_language[primary_language_key])
            primary_render_segments = render_segments_by_language.get(
                primary_language_key,
                primary_render_segments,
            )
        else:
            primary_outputs = _render_outputs_for_segments(
                output_dir=output_root,
                base_name=base_name,
                segments=primary_render_segments,
                requested_outputs=requested_outputs,
                max_subtitle_chars=max_subtitle_chars,
                style=style_plan,
                content_mode=content_mode,
                anime_song_layout_mode=anime_song_layout_mode,
            )

        enhanced_dir_path: str | None = None
        if ai_enabled:
            _ensure_dir(enhanced_root)
            enhanced_render_segments = _prepare_render_segments(
                source_segments=corrected_segments,
                rendered_segments=corrected_segments,
                content_mode=content_mode,
                anime_song_layout_mode=anime_song_layout_mode,
                speaker_style_mode=speaker_mode_applied,
                karaoke_granularity=karaoke_mode_applied,
                song_blocks=song_blocks,
            )
            enhanced_outputs = _render_outputs_for_segments(
                output_dir=enhanced_root,
                base_name=base_name,
                segments=enhanced_render_segments,
                requested_outputs=requested_outputs,
                max_subtitle_chars=max_subtitle_chars,
                style=style_plan,
                content_mode=content_mode,
                anime_song_layout_mode=anime_song_layout_mode,
            )
            if enhanced_outputs:
                enhanced_dir_path = str(enhanced_root)

        translation_manifest_path: str | None = None
        if task == "translate" and translations_manifest.get("languages"):
            manifest_path = output_root / "translations_manifest.json"
            manifest_path.write_text(json.dumps(translations_manifest, ensure_ascii=False, indent=2), encoding="utf-8")
            translation_manifest_path = str(manifest_path)

        style_map_path = str(output_root / "style_map.json")
        Path(style_map_path).write_text(
            json.dumps(style_map, ensure_ascii=False, indent=2),
            encoding="utf-8",
        )

        alignment_report_path = str(output_root / "alignment_report.json")
        Path(alignment_report_path).write_text(
            json.dumps(alignment_report, ensure_ascii=False, indent=2),
            encoding="utf-8",
        )

        scene_map_path = str(output_root / "scene_map.json")
        Path(scene_map_path).write_text(
            json.dumps(scene_map, ensure_ascii=False, indent=2),
            encoding="utf-8",
        )

        karaoke_plan_path: str | None = None
        speaker_map_path: str | None = str(output_root / "speaker_map.json")
        lyric_alignment_path: str | None = None
        Path(speaker_map_path).write_text(
            json.dumps(voice_analysis, ensure_ascii=False, indent=2),
            encoding="utf-8",
        )

        if content_mode == "anime_song" or karaoke_mode_applied != "off":
            karaoke_plan = _build_karaoke_plan(
                source_segments=corrected_segments,
                translated_segments=primary_render_segments,
                layout_mode=anime_song_layout_mode,
                karaoke_granularity=karaoke_mode_applied,
                speaker_style_mode=speaker_mode_applied,
            )
            karaoke_plan_path = str(output_root / "karaoke_plan.json")
            Path(karaoke_plan_path).write_text(
                json.dumps(karaoke_plan, ensure_ascii=False, indent=2),
                encoding="utf-8",
            )
            lyric_alignment_path = str(output_root / "lyric_alignment.json")
            Path(lyric_alignment_path).write_text(
                json.dumps(
                    _build_lyric_alignment_report(karaoke_plan),
                    ensure_ascii=False,
                    indent=2,
                ),
                encoding="utf-8",
            )

        _report_job_progress(
            payload,
            progress_percent=97,
            current_stage="packaging",
            current_pass=review_pass_counter,
            total_passes=ai_revision_passes,
            quality_summary=overall_quality_summary,
            translation_statuses=translation_statuses,
            style_source=effective_style_source,
            capability_profile=capability_profile,
        )

        ass_path = primary_outputs.get("ass")
        video_output_path: str | None = None
        video_muxed_path: str | None = None
        render_preview_path: str | None = None

        subtitle_for_video = None
        if ass_path:
            subtitle_for_video = Path(ass_path)
        elif primary_outputs.get("srt"):
            subtitle_for_video = Path(primary_outputs["srt"])

        wants_burned = burn_requested or delivery_mode == "burned_video"
        wants_muxed = delivery_mode == "mux_subtitles" or delivery_mode == "standard"

        if subtitle_for_video and _is_video_file(source_file):
            full_render_preview = (
                content_mode == "anime_song"
                or karaoke_mode_applied != "off"
                or rendered_preview_mode == "rendered"
            )
            if rendered_preview_mode == "rendered" or "subtitle_styling" in ai_modes or content_mode == "anime_song" or karaoke_mode_applied != "off":
                preview_target = output_root / "render_preview.mp4"
                preview_start = None
                if primary_render_segments and not full_render_preview:
                    preview_start = max(
                        0.0,
                        float(primary_render_segments[0].get("start") or 0.0) - 0.35,
                    )
                try:
                    _render_styled_preview_clip(
                        source_file=source_file,
                        subtitle_path=subtitle_for_video,
                        output_path=preview_target,
                        clip_start_seconds=preview_start,
                        clip_duration_seconds=24.0 if content_mode != "anime_song" else 28.0,
                        full_length=full_render_preview,
                    )
                    render_preview_path = str(preview_target)
                    output_duration_seconds = _probe_duration_seconds(preview_target)
                    preview_mode_applied = "rendered"
                    _append_stage_diagnostic(
                        diagnostics,
                        stage="preview_render",
                        severity="info",
                        message=(
                            "Render completo com styling foi gerado com sucesso."
                            if full_render_preview
                            else "Preview renderizado com styling foi gerado com sucesso."
                        ),
                    )
                except Exception as exc:
                    warnings.append(f"Falha ao gerar preview renderizado: {exc}")
                    _append_stage_diagnostic(
                        diagnostics,
                        stage="preview_render",
                        severity="warning",
                        message="Falha ao gerar preview renderizado; mantendo preview rápido.",
                        fallback_used="fast_preview",
                    )
                    preview_mode_applied = "fast"

            if wants_burned:
                burned_path = output_root / f"{base_name}_burned.mp4"
                try:
                    _burn_subtitles_into_video(source_file, subtitle_for_video, burned_path)
                    video_output_path = str(burned_path)
                    _append_stage_diagnostic(
                        diagnostics,
                        stage="packaging",
                        severity="info",
                        message="Vídeo com legenda queimada gerado com sucesso.",
                        fallback_used=None,
                    )
                except Exception as exc:
                    _append_stage_diagnostic(
                        diagnostics,
                        stage="packaging",
                        severity="error" if delivery_mode == "burned_video" else "warning",
                        message="Falha ao gerar vídeo com legenda queimada.",
                        fallback_used="skip_burned_video" if delivery_mode != "burned_video" else None,
                    )
                    if delivery_mode == "burned_video":
                        raise
                    warnings.append(f"Falha ao gerar vídeo com legenda queimada: {exc}")

            if wants_muxed:
                subtitle_tracks: list[tuple[str, Path]] = []
                if task == "translate" and translations_manifest.get("languages"):
                    for lang_key, entry in translations_manifest["languages"].items():
                        if str(entry.get("status")).lower() != "published":
                            continue
                        rendered = entry.get("outputs") or {}
                        subtitle_candidate = rendered.get("ass") or rendered.get("srt") or rendered.get("vtt")
                        if subtitle_candidate:
                            subtitle_tracks.append((_normalize_lang(lang_key), Path(subtitle_candidate)))
                else:
                    subtitle_tracks.append((source_language, subtitle_for_video))
                if subtitle_tracks:
                    muxed_path = output_root / f"{base_name}_muxed.mkv"
                    try:
                        _mux_subtitles_into_mkv(source_file, subtitle_tracks, muxed_path)
                        video_muxed_path = str(muxed_path)
                        _append_stage_diagnostic(
                            diagnostics,
                            stage="packaging",
                            severity="info",
                            message="Vídeo muxado com trilhas de legenda gerado com sucesso.",
                        )
                        if output_duration_seconds is None:
                            output_duration_seconds = _probe_duration_seconds(muxed_path)
                    except Exception as exc:
                        _append_stage_diagnostic(
                            diagnostics,
                            stage="packaging",
                            severity="error" if delivery_mode == "mux_subtitles" else "warning",
                            message="Falha ao muxar trilhas de legenda no vídeo.",
                            fallback_used="skip_muxed_video" if delivery_mode != "mux_subtitles" else None,
                        )
                        if delivery_mode == "mux_subtitles":
                            raise
                        warnings.append(f"Falha ao muxar trilhas de legenda no vídeo: {exc}")

        text_value = None
        srt_value = None
        vtt_value = None
        if primary_outputs.get("text"):
            text_value = Path(primary_outputs["text"]).read_text(encoding="utf-8")
        if primary_outputs.get("srt"):
            srt_value = Path(primary_outputs["srt"]).read_text(encoding="utf-8")
        if primary_outputs.get("vtt"):
            vtt_value = Path(primary_outputs["vtt"]).read_text(encoding="utf-8")
        if output_duration_seconds is None:
            if render_preview_path:
                output_duration_seconds = _probe_duration_seconds(Path(render_preview_path))
            elif video_muxed_path:
                output_duration_seconds = _probe_duration_seconds(Path(video_muxed_path))
            elif video_output_path:
                output_duration_seconds = _probe_duration_seconds(Path(video_output_path))
            else:
                output_duration_seconds = source_duration_seconds
        fallbacks = [
            {
                "stage": str(entry.get("stage") or ""),
                "fallbackUsed": str(entry.get("fallbackUsed") or ""),
                "severity": str(entry.get("severity") or "warning"),
                "message": str(entry.get("message") or ""),
            }
            for entry in diagnostics
            if str(entry.get("fallbackUsed") or "").strip()
        ]

        timeout_profile_applied = str(capability_profile.get("timeoutProfileApplied") or effective_quality_profile)
        overall_quality_summary = dict(overall_quality_summary or {})
        overall_quality_summary["timeoutProfileApplied"] = timeout_profile_applied
        release_gate = _build_release_gate(
            task=task,
            content_mode=content_mode,
            style_source=effective_style_source,
            translation_statuses=translation_statuses,
            render_preview_path=render_preview_path,
            video_muxed_path=video_muxed_path,
            scene_map_path=scene_map_path,
            speaker_map_path=speaker_map_path,
            karaoke_plan_path=karaoke_plan_path,
            lyric_alignment_path=lyric_alignment_path,
        )
        overall_quality_summary["releaseGate"] = release_gate

        quality_report_path = str(output_root / "quality_report.json")
        Path(quality_report_path).write_text(
            json.dumps(overall_quality_summary, ensure_ascii=False, indent=2),
            encoding="utf-8",
        )

        diagnostics_path: str | None = None
        if diagnostics or warnings or ai_enabled:
            diagnostics_payload = {
                "styleSource": effective_style_source,
                "diagnostics": diagnostics,
                "warnings": warnings,
                "sourceLanguage": _display_lang(source_language),
                "contentMode": content_mode,
                "speakerModeApplied": speaker_mode_applied,
                "voiceAnalysisSource": voice_analysis_source,
                "sceneAnalysisSource": scene_analysis_source,
                "previewModeApplied": preview_mode_applied,
                "plannerModelUsed": planner_model_used,
                "reviewModelUsed": review_model_used,
                "timeoutProfileApplied": timeout_profile_applied,
                "qualitySummary": overall_quality_summary,
                "translationStatuses": translation_statuses,
                "capabilityProfile": capability_profile,
                "requestedAiProvider": requested_ai_provider if ai_enabled else None,
                "requestedAiModel": requested_ai_model if ai_enabled else None,
                "effectiveAiProvider": effective_ai_provider if ai_enabled else None,
                "effectiveAiModel": effective_ai_model if ai_enabled else None,
                "runtimeTarget": runtime_target if ai_enabled else None,
                "modelInstalledAtSubmission": model_installed_at_submission if ai_enabled else None,
                "fallbacks": fallbacks,
                "sourceDurationSeconds": source_duration_seconds,
                "outputDurationSeconds": output_duration_seconds,
                "musicalSegmentDurations": musical_segment_durations,
            }
            diagnostics_file = output_root / "job_diagnostics.json"
            diagnostics_file.write_text(
                json.dumps(diagnostics_payload, ensure_ascii=False, indent=2),
                encoding="utf-8",
            )
            diagnostics_path = str(diagnostics_file)

        return {
            "status": "completed",
            "text": text_value,
            "srt": srt_value,
            "vtt": vtt_value,
            "ass": ass_path,
            "assPath": ass_path,
            "videoOutputPath": video_output_path,
            "videoMuxedPath": video_muxed_path,
            "renderPreviewPath": render_preview_path,
            "karaokePlanPath": karaoke_plan_path,
            "sceneMapPath": scene_map_path,
            "speakerMapPath": speaker_map_path,
            "lyricAlignmentPath": lyric_alignment_path,
            "translationManifestPath": translation_manifest_path,
            "diagnosticsPath": diagnostics_path,
            "enhancedDirPath": enhanced_dir_path,
            "outputDirPath": str(output_root),
            "warnings": warnings,
            "diagnostics": diagnostics,
            "styleSource": effective_style_source,
            "detectedContentType": content_mode,
            "contentDetectionConfidence": content_detection_confidence,
            "speakerModeApplied": speaker_mode_applied,
            "karaokeModeApplied": karaoke_mode_applied,
            "voiceAnalysisSource": voice_analysis_source,
            "sceneAnalysisSource": scene_analysis_source,
            "previewModeApplied": preview_mode_applied,
            "plannerModelUsed": planner_model_used,
            "reviewModelUsed": review_model_used,
            "timeoutProfileApplied": timeout_profile_applied,
            "requestedAiProvider": requested_ai_provider if ai_enabled else None,
            "requestedAiModel": requested_ai_model if ai_enabled else None,
            "effectiveAiProvider": effective_ai_provider if ai_enabled else None,
            "effectiveAiModel": effective_ai_model if ai_enabled else None,
            "runtimeTarget": runtime_target if ai_enabled else None,
            "modelInstalledAtSubmission": model_installed_at_submission if ai_enabled else None,
            "fallbacks": fallbacks,
            "currentStage": "completed",
            "currentPass": review_pass_counter,
            "totalPasses": ai_revision_passes,
            "qualitySummary": overall_quality_summary,
            "translationStatuses": translation_statuses,
            "capabilityProfile": capability_profile,
            "qualityReportPath": quality_report_path,
            "styleMapPath": style_map_path,
            "alignmentReportPath": alignment_report_path,
            "error": None,
            "languageDetected": _display_lang(source_language),
            "durationSeconds": duration_seconds,
            "sourceDurationSeconds": source_duration_seconds,
            "outputDurationSeconds": output_duration_seconds,
            "musicalSegmentDurations": musical_segment_durations,
            "meta": runtime,
        }
    except Exception as exc:
        logger.exception("Falha ao executar job de transcrição.")
        timeout_profile_applied = str((capability_profile or {}).get("timeoutProfileApplied") or effective_quality_profile)
        overall_quality_summary = dict(overall_quality_summary or {})
        overall_quality_summary["timeoutProfileApplied"] = timeout_profile_applied
        overall_quality_summary["releaseGate"] = {
            "ready": False,
            "contentMode": _normalize_content_mode(content_mode),
            "publishedLanguages": [],
            "reasons": ["job_error"],
            "criticalFallbacks": ["job_error"],
            "artifactChecks": {},
        }
        failure_artifacts = _write_runtime_artifacts(
            output_root=output_root,
            warnings=warnings,
            diagnostics=diagnostics,
            style_source=effective_style_source,
            content_mode=content_mode,
            speaker_mode_applied=speaker_mode_applied,
            voice_analysis_source=voice_analysis_source,
            scene_analysis_source=scene_analysis_source,
            preview_mode_applied=preview_mode_applied,
            planner_model_used=planner_model_used,
            review_model_used=review_model_used,
            quality_summary=overall_quality_summary,
            translation_statuses=translation_statuses,
            capability_profile=capability_profile,
            timeout_profile_applied=timeout_profile_applied,
            translations_manifest=translations_manifest,
            requested_ai_provider=requested_ai_provider if ai_enabled else None,
            requested_ai_model=requested_ai_model if ai_enabled else None,
            effective_ai_provider=effective_ai_provider if ai_enabled else None,
            effective_ai_model=effective_ai_model if ai_enabled else None,
            runtime_target=runtime_target if ai_enabled else None,
            model_installed_at_submission=model_installed_at_submission if ai_enabled else None,
            fallbacks=fallbacks,
            source_duration_seconds=source_duration_seconds,
            output_duration_seconds=output_duration_seconds,
            musical_segment_durations=musical_segment_durations,
        )
        _report_job_progress(
            payload,
            progress_percent=100,
            current_stage="error",
            current_pass=0,
            total_passes=0,
            quality_summary=overall_quality_summary,
            translation_statuses=translation_statuses,
            style_source=effective_style_source,
            capability_profile=capability_profile,
            error_message=str(exc),
        )
        return {
            "status": "error",
            "text": None,
            "srt": None,
            "vtt": None,
            "ass": None,
            "assPath": None,
            "videoOutputPath": None,
            "videoMuxedPath": None,
            "renderPreviewPath": None,
            "karaokePlanPath": None,
            "sceneMapPath": None,
            "speakerMapPath": None,
            "lyricAlignmentPath": None,
            "translationManifestPath": failure_artifacts["translationManifestPath"],
            "diagnosticsPath": failure_artifacts["diagnosticsPath"],
            "enhancedDirPath": None,
            "outputDirPath": str(output_root) if output_root else None,
            "warnings": warnings,
            "diagnostics": diagnostics,
            "styleSource": effective_style_source,
            "detectedContentType": content_mode if output_root else None,
            "contentDetectionConfidence": content_detection_confidence,
            "speakerModeApplied": speaker_mode_applied,
            "karaokeModeApplied": karaoke_mode_applied,
            "voiceAnalysisSource": voice_analysis_source,
            "sceneAnalysisSource": scene_analysis_source,
            "previewModeApplied": preview_mode_applied,
            "plannerModelUsed": planner_model_used,
            "reviewModelUsed": review_model_used,
            "timeoutProfileApplied": timeout_profile_applied,
            "requestedAiProvider": requested_ai_provider if ai_enabled else None,
            "requestedAiModel": requested_ai_model if ai_enabled else None,
            "effectiveAiProvider": effective_ai_provider if ai_enabled else None,
            "effectiveAiModel": effective_ai_model if ai_enabled else None,
            "runtimeTarget": runtime_target if ai_enabled else None,
            "modelInstalledAtSubmission": model_installed_at_submission if ai_enabled else None,
            "fallbacks": fallbacks,
            "currentStage": "error",
            "currentPass": 0,
            "totalPasses": 0,
            "qualitySummary": overall_quality_summary,
            "translationStatuses": translation_statuses,
            "capabilityProfile": capability_profile,
            "qualityReportPath": failure_artifacts["qualityReportPath"],
            "styleMapPath": None,
            "alignmentReportPath": None,
            "error": str(exc),
            "languageDetected": None,
            "durationSeconds": None,
            "sourceDurationSeconds": source_duration_seconds,
            "outputDurationSeconds": output_duration_seconds,
            "musicalSegmentDurations": musical_segment_durations,
        }
    finally:
        if ai_runtime_token is not None:
            _reset_ai_runtime_context(ai_runtime_token)
