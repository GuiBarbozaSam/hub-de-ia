import logging
from pathlib import Path
from typing import Any

from fastapi import APIRouter, File, Form, Header, HTTPException, UploadFile, status

from app.core.config import get_settings
from app.core.exceptions import (
    DependencyMissingError,
    FileTooLargeError,
    InvalidUploadError,
)
from app.schemas.transcription import (
    CapabilitiesResponse,
    JobTranscriptionRequest,
    JobTranscriptionResponse,
    TranscriptionResponse,
)
from app.services.transcription_engine import (
    get_model_download_status,
    get_capabilities,
    run_job_transcription as run_transcription,
    start_model_download,
)
from app.utils.files import save_upload_file

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/transcription", tags=["Transcription"])


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _normalize_internal_key(value: str | None) -> str:
    return (value or "").strip()


def _validate_internal_api_key(x_internal_api_key: str | None) -> None:
    settings = get_settings()

    expected = _normalize_internal_key(settings.transcription_internal_api_key)
    received = _normalize_internal_key(x_internal_api_key)

    if not expected or "change_me" in expected.lower() or "troque" in expected.lower():
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Chave interna do backend Python não está configurada com valor real.",
        )

    if expected and received != expected:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Chave interna inválida.",
        )


def _http_error_from_exception(exc: Exception) -> HTTPException:
    if isinstance(exc, FileNotFoundError):
        return HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=str(exc),
        )

    if isinstance(exc, (ValueError, InvalidUploadError)):
        return HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(exc),
        )

    if isinstance(exc, FileTooLargeError):
        return HTTPException(
            status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
            detail=str(exc),
        )

    if isinstance(exc, DependencyMissingError):
        return HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=str(exc),
        )

    logger.exception("Erro interno na rota de transcrição.")
    return HTTPException(
        status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
        detail=str(exc),
    )


# ---------------------------------------------------------------------------
# Routes
# ---------------------------------------------------------------------------

@router.get(
    "/capabilities",
    response_model=CapabilitiesResponse,
    response_model_by_alias=True,
)
async def transcription_capabilities() -> CapabilitiesResponse:
    return CapabilitiesResponse(**get_capabilities())


@router.post("/models/download")
async def download_model(
    payload: dict[str, Any],
    x_internal_api_key: str | None = Header(default=None),
) -> dict[str, Any]:
    _validate_internal_api_key(x_internal_api_key)
    provider = str(payload.get("provider") or payload.get("aiProvider") or "ollama_project").strip()
    model = str(payload.get("model") or payload.get("aiModel") or "").strip()
    try:
        return start_model_download(provider, model)
    except Exception as exc:
        raise _http_error_from_exception(exc) from exc


@router.get("/models/downloads/{download_id}")
async def get_model_download(
    download_id: str,
    x_internal_api_key: str | None = Header(default=None),
) -> dict[str, Any]:
    _validate_internal_api_key(x_internal_api_key)
    current = get_model_download_status(download_id)
    if current is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Download de modelo não encontrado.",
        )
    return current


@router.post(
    "/jobs/run",
    response_model=JobTranscriptionResponse,
    response_model_by_alias=True,
)
async def run_transcription_job(
    payload: JobTranscriptionRequest,
    x_internal_api_key: str | None = Header(default=None),
) -> JobTranscriptionResponse:
    _validate_internal_api_key(x_internal_api_key)

    raw_payload = payload.model_dump(by_alias=False)

    logger.info(
        "Job recebido na borda Python | source_type=%s | task=%s | language=%s | requested_outputs=%s | target_languages=%s | video_delivery_mode=%s | ai_enabled=%s | ai_model=%s | ai_mode=%s",
        raw_payload.get("source_type"),
        raw_payload.get("task"),
        raw_payload.get("language"),
        raw_payload.get("requested_outputs") or raw_payload.get("requested_outputs_csv"),
        raw_payload.get("target_languages") or raw_payload.get("target_languages_csv"),
        raw_payload.get("video_delivery_mode"),
        raw_payload.get("ai_enhancement_enabled"),
        raw_payload.get("ai_model"),
        raw_payload.get("ai_mode"),
    )

    try:
        result = run_transcription(raw_payload)
    except Exception as exc:
        raise _http_error_from_exception(exc) from exc

    logger.info(
        "Job concluído na borda Python | status=%s | language_detected=%s | video_output=%s | video_muxed=%s | manifest=%s | diagnostics=%s | style_source=%s | enhanced_dir=%s | warnings=%s",
        result.get("status"),
        result.get("languageDetected") or result.get("language_detected"),
        result.get("videoOutputPath") or result.get("video_output_path"),
        result.get("videoMuxedPath") or result.get("video_muxed_path"),
        result.get("translationManifestPath") or result.get("translation_manifest_path"),
        result.get("diagnosticsPath") or result.get("diagnostics_path"),
        result.get("styleSource") or result.get("style_source"),
        result.get("enhancedDirPath") or result.get("enhanced_dir_path"),
        result.get("warnings"),
    )

    return JobTranscriptionResponse(**result)


@router.post(
    "/file",
    response_model=TranscriptionResponse,
    response_model_by_alias=True,
)
async def transcribe_uploaded_file(
    file: UploadFile = File(...),
    language: str | None = Form(default=None),
    task: str = Form(default="transcribe"),
    beam_size: int | None = Form(default=None),
    vad_filter: bool | None = Form(default=None),
    word_timestamps: bool | None = Form(default=None),
    model: str | None = Form(default=None),
    device_preference: str | None = Form(default=None),
    compute_type: str | None = Form(default=None),
) -> TranscriptionResponse:
    settings = get_settings()

    if task not in {"transcribe", "translate"}:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="O campo 'task' deve ser 'transcribe' ou 'translate'.",
        )

    saved_file_path: Path | None = None
    size_bytes = 0
    original_name = file.filename or "input.bin"

    try:
        saved_file_path, size_bytes = await save_upload_file(
            upload_file=file,
            destination_dir=settings.temp_dir,
            max_bytes=settings.max_upload_bytes,
        )

        result = run_transcription(
            file_path=saved_file_path,
            original_filename=original_name,
            size_bytes=size_bytes,
            language=language,
            task=task,
            beam_size=beam_size,
            vad_filter=vad_filter,
            word_timestamps=word_timestamps,
            model_name=model,
            device_preference=device_preference,
            compute_type_preference=compute_type,
            condition_on_previous_text=True,
        )

        return TranscriptionResponse(**result)
    except Exception as exc:
        raise _http_error_from_exception(exc) from exc
    finally:
        if saved_file_path and saved_file_path.exists():
            try:
                saved_file_path.unlink(missing_ok=True)
            except Exception:
                logger.warning(
                    "Falha ao remover arquivo temporário de upload: %s",
                    saved_file_path,
                    exc_info=True,
                )
