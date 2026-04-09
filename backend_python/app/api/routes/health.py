from fastapi import APIRouter

from app.core.config import get_settings
from app.schemas.transcription import HealthResponse
from app.services.transcription_engine import detect_hardware, is_faster_whisper_installed

router = APIRouter(tags=["Health"])


@router.get("/health", response_model=HealthResponse)
async def health_check():
    settings = get_settings()

    return HealthResponse(
        status="ok",
        service=settings.app_name,
        version=settings.app_version,
        environment=settings.app_env,
        faster_whisper_installed=is_faster_whisper_installed(),
        hardware=detect_hardware(),
    )