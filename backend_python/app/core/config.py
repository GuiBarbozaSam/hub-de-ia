from functools import lru_cache
from pathlib import Path
from typing import Literal

from pydantic_settings import BaseSettings, SettingsConfigDict


BASE_DIR = Path(__file__).resolve().parents[2]
PROJECT_ROOT = BASE_DIR.parent


class Settings(BaseSettings):
    app_name: str = "Hub de IA - Python AI Service"
    app_env: Literal["local", "dev", "hom", "prod"] = "local"
    app_debug: bool = True
    app_version: str = "1.0.0"
    api_v1_prefix: str = "/api/v1"

    cors_origins: str = (
        "http://localhost:3000,"
        "http://127.0.0.1:3000,"
        "http://localhost:5045,"
        "https://localhost:7045,"
        "http://10.0.2.2:5045"
    )

    log_level: str = "INFO"

    transcription_default_model: str = "small"
    transcription_device: Literal["auto", "cpu", "cuda"] = "auto"
    transcription_compute_type: Literal[
        "auto",
        "int8",
        "int8_float16",
        "float16",
        "float32",
    ] = "auto"
    transcription_cpu_threads: int = 4
    transcription_num_workers: int = 1
    transcription_max_upload_mb: int = 1024
    transcription_beam_size: int = 5
    transcription_vad_filter: bool = True
    transcription_word_timestamps: bool = False
    transcription_internal_api_key: str = "change_me_internal_api_key"

    shared_storage_root: str = "shared_storage"
    shared_uploads_folder_name: str = "uploads"
    shared_outputs_folder_name: str = "outputs"

    ffmpeg_path: str = "ffmpeg"
    ffprobe_path: str = "ffprobe"
    ffmpeg_video_codec: str = "libx264"
    ffmpeg_audio_codec: str = "aac"
    ffmpeg_crf: int = 20
    ffmpeg_preset: str = "medium"
    ffmpeg_overwrite: bool = True

    subtitle_default_style: str = "default"
    subtitle_font_name: str = "Arial"
    subtitle_font_size: int = 18
    subtitle_margin_v: int = 28
    subtitle_outline: int = 2
    subtitle_shadow: int = 0
    subtitle_alignment: int = 2  # bottom center in ASS
    subtitle_primary_colour: str = "&H00FFFFFF"
    subtitle_outline_colour: str = "&H00000000"
    subtitle_back_colour: str = "&H64000000"

    ollama_base_url: str = "http://127.0.0.1:11435"
    ollama_host_discovery_url: str = "http://127.0.0.1:11434"
    ollama_model_store_path: str = "backend_python/storage/ollama"
    ollama_default_model: str = "qwen2.5vl:7b"
    ollama_text_model: str = "qwen2.5:14b"
    ollama_visual_model: str = "qwen2.5vl:7b"

    remote_api_enabled: bool = False
    remote_api_base_url: str = ""
    remote_api_api_key: str = "change_me_remote_api_key"
    remote_api_models: str = ""

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=False,
        extra="ignore",
    )

    @property
    def cors_origins_list(self) -> list[str]:
        return [item.strip() for item in self.cors_origins.split(",") if item.strip()]

    @property
    def temp_dir(self) -> Path:
        return BASE_DIR / "storage" / "temp"

    @property
    def models_dir(self) -> Path:
        return BASE_DIR / "storage" / "models"

    @property
    def local_outputs_dir(self) -> Path:
        return BASE_DIR / "storage" / "outputs"

    @property
    def shared_root_dir(self) -> Path:
        configured = Path(self.shared_storage_root)
        if configured.is_absolute():
            return configured
        return (PROJECT_ROOT / configured).resolve()

    @property
    def shared_uploads_dir(self) -> Path:
        return self.shared_root_dir / self.shared_uploads_folder_name

    @property
    def shared_outputs_dir(self) -> Path:
        return self.shared_root_dir / self.shared_outputs_folder_name

    @property
    def max_upload_bytes(self) -> int:
        return self.transcription_max_upload_mb * 1024 * 1024

    @property
    def ollama_model_store_dir(self) -> Path:
        configured = Path(self.ollama_model_store_path)
        if configured.is_absolute():
            return configured
        return (PROJECT_ROOT / configured).resolve()

    @property
    def remote_api_models_list(self) -> list[str]:
        values = []
        for raw in self.remote_api_models.split(","):
            item = raw.strip()
            if item and item not in values:
                values.append(item)
        return values


@lru_cache
def get_settings() -> Settings:
    return Settings()
