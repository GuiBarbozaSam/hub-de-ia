from __future__ import annotations

import logging
from contextlib import asynccontextmanager
from pathlib import Path
from typing import Any, Iterable

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from app.api.routes.transcription import router as transcription_router
from app.core.config import get_settings
from app.core.exceptions import DependencyMissingError
from app.services.transcription_engine import detect_hardware, is_faster_whisper_installed

logger = logging.getLogger(__name__)


def _as_list(value: Any) -> list[str]:
    if value is None:
        return []
    if isinstance(value, (list, tuple, set)):
        return [str(item).strip() for item in value if str(item).strip()]
    text = str(value).strip()
    if not text:
        return []
    return [item.strip() for item in text.split(",") if item.strip()]


def _unique_paths(paths: Iterable[Path]) -> list[Path]:
    seen: set[str] = set()
    ordered: list[Path] = []
    for path in paths:
        key = str(path.resolve()).lower()
        if key in seen:
            continue
        seen.add(key)
        ordered.append(path)
    return ordered


def _ensure_runtime_directories() -> dict[str, str]:
    settings = get_settings()
    directories = _unique_paths(
        [
            settings.temp_dir,
            settings.models_dir,
            settings.local_outputs_dir,
            settings.shared_root_dir,
            settings.shared_uploads_dir,
            settings.shared_outputs_dir,
        ]
    )

    created: dict[str, str] = {}
    for directory in directories:
        directory.mkdir(parents=True, exist_ok=True)
        created[directory.name] = str(directory.resolve())

    return created


def _build_service_metadata() -> dict[str, Any]:
    settings = get_settings()
    return {
        "service": getattr(settings, "app_name", "Hub IA Python Backend"),
        "version": getattr(settings, "app_version", "1.0.0"),
        "environment": getattr(settings, "environment", getattr(settings, "app_env", "development")),
        "apiPrefix": getattr(settings, "api_v1_prefix", "/api/v1"),
    }


@asynccontextmanager
async def lifespan(app: FastAPI):
    settings = get_settings()
    created_dirs = _ensure_runtime_directories()
    logger.info(
        "Iniciando backend Python | environment=%s | api_prefix=%s",
        getattr(settings, "environment", getattr(settings, "app_env", "development")),
        getattr(settings, "api_v1_prefix", "/api/v1"),
    )
    logger.info("Diretórios garantidos no startup: %s", created_dirs)
    yield
    logger.info("Encerrando backend Python.")


settings = get_settings()
service_metadata = _build_service_metadata()
app = FastAPI(
    title=str(service_metadata["service"]),
    version=str(service_metadata["version"]),
    lifespan=lifespan,
    docs_url="/docs",
    redoc_url="/redoc",
    openapi_url="/openapi.json",
)

cors_origins = _as_list(getattr(settings, "cors_origins", None)) or ["*"]
allow_credentials = not (len(cors_origins) == 1 and cors_origins[0] == "*")

app.add_middleware(
    CORSMiddleware,
    allow_origins=cors_origins,
    allow_credentials=allow_credentials,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.exception_handler(DependencyMissingError)
async def dependency_missing_exception_handler(_: Request, exc: DependencyMissingError):
    return JSONResponse(
        status_code=500,
        content={
            "status": "error",
            "error": str(exc),
            **service_metadata,
        },
    )


@app.exception_handler(FileNotFoundError)
async def file_not_found_exception_handler(_: Request, exc: FileNotFoundError):
    return JSONResponse(
        status_code=404,
        content={
            "status": "error",
            "error": str(exc),
            **service_metadata,
        },
    )


@app.get("/", tags=["system"])
def root() -> dict[str, Any]:
    return {
        "status": "ok",
        **service_metadata,
        "fasterWhisperInstalled": is_faster_whisper_installed(),
    }


@app.get("/health", tags=["system"])
def health() -> dict[str, Any]:
    settings_local = get_settings()
    return {
        "status": "ok",
        **service_metadata,
        "fasterWhisperInstalled": is_faster_whisper_installed(),
        "hardware": detect_hardware(),
        "paths": {
            "tempDir": str(settings_local.temp_dir.resolve()),
            "modelsDir": str(settings_local.models_dir.resolve()),
            "localOutputsDir": str(settings_local.local_outputs_dir.resolve()),
            "sharedRootDir": str(settings_local.shared_root_dir.resolve()),
            "sharedUploadsDir": str(settings_local.shared_uploads_dir.resolve()),
            "sharedOutputsDir": str(settings_local.shared_outputs_dir.resolve()),
        },
    }


@app.get(f"{getattr(settings, 'api_v1_prefix', '/api/v1')}/health", tags=["system"])
def api_health() -> dict[str, Any]:
    return health()


app.include_router(
    transcription_router,
    prefix=getattr(settings, "api_v1_prefix", "/api/v1"),
)
