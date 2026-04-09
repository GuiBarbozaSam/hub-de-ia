import argparse
import json
import mimetypes
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request
import uuid
from pathlib import Path
from typing import Any


REPO_ROOT = Path(__file__).resolve().parents[1]
TMP_ROOT = REPO_ROOT / ".tmp" / "smoke"


def _request_json(
    method: str,
    url: str,
    *,
    body: bytes | None = None,
    headers: dict[str, str] | None = None,
    timeout: int = 120,
) -> dict[str, Any]:
    request = urllib.request.Request(
        url,
        data=body,
        headers=headers or {},
        method=method.upper(),
    )
    with urllib.request.urlopen(request, timeout=timeout) as response:
        raw = response.read().decode("utf-8", errors="replace")
    if not raw.strip():
        return {}
    decoded = json.loads(raw)
    if isinstance(decoded, dict):
        return decoded
    raise RuntimeError(f"Resposta JSON inesperada em {url}: {type(decoded)!r}")


def _request_bytes(
    method: str,
    url: str,
    *,
    body: bytes | None = None,
    headers: dict[str, str] | None = None,
    timeout: int = 120,
) -> bytes:
    request = urllib.request.Request(
        url,
        data=body,
        headers=headers or {},
        method=method.upper(),
    )
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return response.read()


def _login_or_register(base_url: str, email: str, password: str) -> str:
    payload = json.dumps({"email": email, "password": password}).encode("utf-8")
    headers = {"Content-Type": "application/json", "Accept": "application/json"}
    for path in ("/api/auth/login", "/api/auth/register", "/api/auth/login"):
        try:
            result = _request_json("POST", f"{base_url}{path}", body=payload, headers=headers, timeout=90)
            token = str(result.get("accessToken") or "").strip()
            if token:
                return token
        except urllib.error.HTTPError as exc:
            if exc.code in {400, 401, 409}:
                continue
            raise
    raise RuntimeError("Falha ao autenticar ou registrar usuário de smoke.")


def _encode_multipart(fields: dict[str, str], file_field: str, file_path: Path) -> tuple[bytes, str]:
    boundary = f"----project-smoke-{uuid.uuid4().hex}"
    chunks: list[bytes] = []
    for key, value in fields.items():
        chunks.extend(
            [
                f"--{boundary}\r\n".encode("utf-8"),
                f'Content-Disposition: form-data; name="{key}"\r\n\r\n'.encode("utf-8"),
                str(value).encode("utf-8"),
                b"\r\n",
            ]
        )

    mime = mimetypes.guess_type(file_path.name)[0] or "application/octet-stream"
    chunks.extend(
        [
            f"--{boundary}\r\n".encode("utf-8"),
            (
                f'Content-Disposition: form-data; name="{file_field}"; filename="{file_path.name}"\r\n'
                f"Content-Type: {mime}\r\n\r\n"
            ).encode("utf-8"),
            file_path.read_bytes(),
            b"\r\n",
            f"--{boundary}--\r\n".encode("utf-8"),
        ]
    )
    return b"".join(chunks), boundary


def _upload_job(
    *,
    base_url: str,
    token: str,
    file_path: Path,
    ai_enabled: bool,
    ai_provider: str,
    ai_model: str,
    ai_use_visual_context: bool,
    ai_prompt: str | None,
    ai_modes: str,
    subtitle_visual_preset: str,
    content_mode: str,
    quality_profile: str,
    speaker_style_mode: str,
    karaoke_granularity: str,
    task: str,
    target_languages: list[str],
    rendered_preview_mode: str,
) -> dict[str, Any]:
    requested_outputs = "txt,srt,vtt,ass"
    target_csv = ",".join(target_languages)
    fields = {
        "Model": "large-v3",
        "Task": task,
        "Language": "auto",
        "OutputFormat": "all",
        "RequestedOutputsCsv": requested_outputs,
        "VideoDeliveryMode": "mux_subtitles" if task == "translate" else "standard",
        "GenerateSubtitles": "true",
        "BurnSubtitlesIntoVideo": "false",
        "KeepTimestamps": "true",
        "SplitBySentence": "true",
        "WordTimestamps": "true",
        "VadFilter": "true",
        "DevicePreference": "auto",
        "ComputeType": "float16",
        "BeamSize": "5",
        "MaxSubtitleChars": "42",
        "SubtitleStyle": subtitle_visual_preset,
        "SubtitleVisualPreset": subtitle_visual_preset,
        "TargetLanguagesCsv": target_csv,
        "AiEnhancementEnabled": "true" if ai_enabled else "false",
        "AiProvider": ai_provider,
        "AiModel": ai_model,
        "AiMode": ai_modes,
        "AiUseVisualContext": "true" if ai_use_visual_context else "false",
        "AiFrameSampleSeconds": "12",
        "PreserveTimestamps": "true",
        "AiRevisionPasses": "3",
        "UseAdvancedAlignment": "auto",
        "EnableOnlineContext": "false",
        "QualityProfile": quality_profile,
        "ContentMode": content_mode,
        "SpeakerStyleMode": speaker_style_mode,
        "StyleIntensity": "thematic",
        "RenderedPreviewMode": rendered_preview_mode,
        "AnimeSongLayoutMode": "romaji_top_translation_bottom" if content_mode == "anime_song" else "off",
        "KaraokeGranularity": karaoke_granularity,
    }
    if ai_prompt and ai_prompt.strip():
        fields["AiPrompt"] = ai_prompt.strip()
    body, boundary = _encode_multipart(fields, "File", file_path)
    headers = {
        "Authorization": f"Bearer {token}",
        "Accept": "application/json",
        "Content-Type": f"multipart/form-data; boundary={boundary}",
    }
    return _request_json(
        "POST",
        f"{base_url}/api/transcription/jobs/upload",
        body=body,
        headers=headers,
        timeout=300,
    )


def _create_job_from_file_path(
    *,
    base_url: str,
    token: str,
    file_path: Path,
    ai_enabled: bool,
    ai_provider: str,
    ai_model: str,
    ai_use_visual_context: bool,
    ai_prompt: str | None,
    ai_modes: str,
    subtitle_visual_preset: str,
    content_mode: str,
    quality_profile: str,
    speaker_style_mode: str,
    karaoke_granularity: str,
    task: str,
    target_languages: list[str],
    rendered_preview_mode: str,
) -> dict[str, Any]:
    payload: dict[str, Any] = {
        "sourceType": "file_path",
        "sourceValue": str(file_path),
        "model": "large-v3",
        "task": task,
        "language": "auto",
        "outputFormat": "all",
        "requestedOutputs": ["txt", "srt", "vtt", "ass"],
        "videoDeliveryMode": "mux_subtitles" if task == "translate" else "standard",
        "generateSubtitles": True,
        "burnSubtitlesIntoVideo": False,
        "keepTimestamps": True,
        "splitBySentence": True,
        "wordTimestamps": True,
        "vadFilter": True,
        "devicePreference": "auto",
        "computeType": "float16",
        "beamSize": 5,
        "maxSubtitleChars": 42,
        "subtitleStyle": subtitle_visual_preset,
        "subtitleVisualPreset": subtitle_visual_preset,
        "targetLanguages": target_languages,
        "aiEnhancementEnabled": ai_enabled,
        "aiProvider": ai_provider,
        "aiModel": ai_model,
        "aiMode": ai_modes,
        "aiUseVisualContext": ai_use_visual_context,
        "aiFrameSampleSeconds": 12,
        "preserveTimestamps": True,
        "aiRevisionPasses": 3,
        "useAdvancedAlignment": "auto",
        "enableOnlineContext": False,
        "qualityProfile": quality_profile,
        "contentMode": content_mode,
        "speakerStyleMode": speaker_style_mode,
        "styleIntensity": "thematic",
        "renderedPreviewMode": rendered_preview_mode,
        "animeSongLayoutMode": "romaji_top_translation_bottom" if content_mode == "anime_song" else "off",
        "karaokeGranularity": karaoke_granularity,
    }
    if ai_prompt and ai_prompt.strip():
        payload["aiPrompt"] = ai_prompt.strip()

    headers = {
        "Authorization": f"Bearer {token}",
        "Accept": "application/json",
        "Content-Type": "application/json",
    }
    return _request_json(
        "POST",
        f"{base_url}/api/transcription/jobs",
        body=json.dumps(payload, ensure_ascii=False).encode("utf-8"),
        headers=headers,
        timeout=180,
    )


def _poll_job(
    *,
    base_url: str,
    token: str,
    email: str,
    password: str,
    job_id: str,
    timeout_seconds: int,
    poll_interval: int,
) -> dict[str, Any]:
    current_token = token
    deadline = time.time() + timeout_seconds
    last_stage = None
    last_progress = None
    while time.time() < deadline:
        headers = {"Authorization": f"Bearer {current_token}", "Accept": "application/json"}
        try:
            detail = _request_json("GET", f"{base_url}/api/transcription/jobs/{job_id}", headers=headers, timeout=120)
        except urllib.error.HTTPError as exc:
            if exc.code == 401:
                current_token = _login_or_register(base_url, email, password)
                continue
            raise
        stage = detail.get("currentStage")
        progress = detail.get("progressPercent")
        if stage != last_stage or progress != last_progress:
            print(
                json.dumps(
                    {
                        "job_id": job_id,
                        "status": detail.get("status"),
                        "stage": stage,
                        "progress": progress,
                        "pass": detail.get("currentPass"),
                        "totalPasses": detail.get("totalPasses"),
                    },
                    ensure_ascii=False,
                )
            )
            last_stage = stage
            last_progress = progress
        if str(detail.get("status")).lower() in {"completed", "error", "canceled"}:
            return detail
        time.sleep(max(1, poll_interval))
    raise TimeoutError(f"Timeout aguardando job {job_id}.")


def _ffprobe_ok(path: str | None) -> dict[str, Any]:
    if not path:
        return {"ok": False, "reason": "missing"}
    resolved = Path(path)
    if not resolved.is_absolute():
        normalized = str(resolved).replace("\\", "/").lstrip("/")
        if normalized.startswith("outputs/"):
            resolved = REPO_ROOT / "shared_storage" / normalized
        else:
            resolved = REPO_ROOT / normalized
    try:
        result = subprocess.run(
            [
                "ffprobe",
                "-v",
                "error",
                "-show_entries",
                "format=duration",
                "-show_streams",
                "-of",
                "json",
                str(resolved),
            ],
            capture_output=True,
            text=True,
            timeout=120,
            check=False,
        )
    except Exception as exc:
        return {"ok": False, "reason": str(exc)}

    if result.returncode != 0:
        return {"ok": False, "reason": result.stderr.strip() or result.stdout.strip()}
    try:
        decoded = json.loads(result.stdout or "{}")
    except Exception:
        decoded = {}
    return {
        "ok": True,
        "streamCount": len(decoded.get("streams") or []),
        "duration": ((decoded.get("format") or {}).get("duration")),
    }


def _run_benchmark(base_url: str, models: list[str]) -> dict[str, Any] | None:
    TMP_ROOT.mkdir(parents=True, exist_ok=True)
    target = TMP_ROOT / "ollama_benchmark.json"
    result = subprocess.run(
        [
            sys.executable,
            str(REPO_ROOT / "scripts" / "benchmark-ollama.py"),
            "--base-url",
            base_url,
            "--timeout",
            "90",
            "--models",
            *models,
        ],
        capture_output=True,
        text=True,
        timeout=600,
        check=False,
    )
    if result.returncode != 0:
        target.write_text(
            json.dumps({"ok": False, "stderr": result.stderr, "stdout": result.stdout}, ensure_ascii=False, indent=2),
            encoding="utf-8",
        )
        return None
    target.write_text(result.stdout, encoding="utf-8")
    return json.loads(result.stdout)


def _probe_duration(path: Path) -> float:
    result = subprocess.run(
        [
            "ffprobe",
            "-v",
            "error",
            "-show_entries",
            "format=duration",
            "-of",
            "default=nokey=1:noprint_wrappers=1",
            str(path),
        ],
        capture_output=True,
        text=True,
        timeout=60,
        check=False,
    )
    if result.returncode != 0:
        return 0.0
    try:
        return float((result.stdout or "0").strip().splitlines()[0])
    except Exception:
        return 0.0


def _extract_clip(
    source_path: Path,
    *,
    clip_start: float,
    clip_duration: float,
    clip_label: str | None,
) -> Path:
    TMP_ROOT.mkdir(parents=True, exist_ok=True)
    safe_label = "".join(ch for ch in (clip_label or "clip") if ch.isalnum() or ch in {"-", "_"}).strip() or "clip"
    target = TMP_ROOT / f"{source_path.stem}_{safe_label}_{int(clip_start * 1000)}_{int(clip_duration * 1000)}.mp4"
    command = [
        "ffmpeg",
        "-y",
        "-ss",
        f"{clip_start:.3f}",
        "-i",
        str(source_path),
        "-t",
        f"{clip_duration:.3f}",
        "-map",
        "0:v:0?",
        "-map",
        "0:a:0?",
        "-c:v",
        "libx264",
        "-preset",
        "veryfast",
        "-crf",
        "18",
        "-c:a",
        "aac",
        "-movflags",
        "+faststart",
        str(target),
    ]
    result = subprocess.run(
        command,
        capture_output=True,
        text=True,
        timeout=1800,
        check=False,
    )
    if result.returncode != 0 or not target.exists():
        raise RuntimeError(
            f"Falha ao extrair clip {safe_label}. ffmpeg={result.returncode} stderr={result.stderr.strip() or result.stdout.strip()}"
        )
    return target


def _discover_workspace_clip(kind: str) -> Path:
    candidates = []
    for root in (REPO_ROOT / "shared_storage" / "uploads", REPO_ROOT / ".tmp" / "smoke"):
        if not root.exists():
            continue
        for path in root.rglob("*"):
            if path.suffix.lower() not in {".mp4", ".mkv", ".mov", ".webm"}:
                continue
            duration = _probe_duration(path)
            if duration > 0:
                candidates.append((duration, path))
    if not candidates:
        raise FileNotFoundError("Nenhum clip local encontrado para smoke.")
    candidates.sort(key=lambda item: item[0])
    if kind == "short":
        for duration, path in candidates:
            if duration >= 15:
                return path
        return candidates[0][1]
    return candidates[-1][1]


def _collect_artifacts(detail: dict[str, Any]) -> dict[str, Any]:
    outputs = detail.get("outputs") or []
    output_types = sorted(
        {
            str(item.get("outputType") or item.get("OutputType") or "").strip()
            for item in outputs
            if str(item.get("outputType") or item.get("OutputType") or "").strip()
        }
    )
    return {
        "outputTypes": output_types,
        "renderPreviewPath": detail.get("renderPreviewPath"),
        "sceneMapPath": detail.get("sceneMapPath"),
        "speakerMapPath": detail.get("speakerMapPath"),
        "lyricAlignmentPath": detail.get("lyricAlignmentPath"),
        "qualitySummary": detail.get("qualitySummary"),
        "translationStatuses": detail.get("translationStatuses"),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Smoke runner for the transcription pipeline using the real API.")
    parser.add_argument("--base-url", default="http://127.0.0.1:5045")
    parser.add_argument("--ollama-base-url", default="http://127.0.0.1:11435")
    parser.add_argument("--email", default="smoke@example.com")
    parser.add_argument("--password", default="SmokePass123!")
    parser.add_argument("--file")
    parser.add_argument("--source-mode", choices=["upload", "file_path"], default="file_path")
    parser.add_argument("--use-discovered", choices=["short", "long"], default="long")
    parser.add_argument("--content-mode", choices=["auto", "episode", "anime_song"], default="episode")
    parser.add_argument("--task", choices=["transcribe", "translate"], default="translate")
    parser.add_argument("--quality-profile", choices=["safe", "balanced", "max"], default="balanced")
    parser.add_argument("--speaker-style-mode", choices=["off", "heuristic", "advanced"], default="heuristic")
    parser.add_argument("--karaoke-granularity", choices=["off", "word", "syllable"], default="off")
    parser.add_argument("--target-language", action="append", default=[])
    parser.add_argument("--rendered-preview-mode", choices=["fast", "rendered"], default="rendered")
    parser.add_argument("--subtitle-visual-preset", default="cinematic")
    parser.add_argument("--ai-enabled", dest="ai_enabled", action="store_true")
    parser.add_argument("--no-ai", dest="ai_enabled", action="store_false")
    parser.set_defaults(ai_enabled=True)
    parser.add_argument("--ai-provider", default="ollama_project")
    parser.add_argument("--ai-model", default="qwen2.5vl:7b")
    parser.add_argument("--ai-modes", default="correction,semantic_translation,subtitle_styling")
    parser.add_argument("--ai-use-visual-context", action="store_true")
    parser.add_argument("--ai-prompt")
    parser.add_argument("--timeout", type=int, default=28800)
    parser.add_argument("--poll-interval", type=int, default=10)
    parser.add_argument("--skip-benchmark", action="store_true")
    parser.add_argument("--allow-critical-fallbacks", action="store_true")
    parser.add_argument("--clip-start", type=float)
    parser.add_argument("--clip-duration", type=float)
    parser.add_argument("--clip-label")
    args = parser.parse_args()
    if not args.target_language:
        args.target_language = ["en"]

    file_path = Path(args.file).resolve() if args.file else _discover_workspace_clip(args.use_discovered)
    original_file_path = file_path
    if args.clip_start is not None or args.clip_duration is not None:
        if args.clip_start is None or args.clip_duration is None:
            raise RuntimeError("--clip-start e --clip-duration devem ser informados juntos.")
        file_path = _extract_clip(
            file_path,
            clip_start=max(0.0, args.clip_start),
            clip_duration=max(1.0, args.clip_duration),
            clip_label=args.clip_label,
        )
    token = _login_or_register(args.base_url, args.email, args.password)

    benchmark = None
    if args.ai_enabled and not args.skip_benchmark:
        benchmark = _run_benchmark(
            args.ollama_base_url,
            ["gemma3:4b", "qwen2.5:14b", "qwen2.5vl:7b"],
        )

    submit = _create_job_from_file_path if args.source_mode == "file_path" else _upload_job
    job = submit(
        base_url=args.base_url,
        token=token,
        file_path=file_path,
        ai_enabled=args.ai_enabled,
        ai_provider=args.ai_provider,
        ai_model=args.ai_model,
        ai_use_visual_context=args.ai_use_visual_context,
        ai_prompt=args.ai_prompt,
        ai_modes=args.ai_modes,
        subtitle_visual_preset=args.subtitle_visual_preset,
        content_mode=args.content_mode,
        quality_profile=args.quality_profile,
        speaker_style_mode=args.speaker_style_mode,
        karaoke_granularity=args.karaoke_granularity,
        task=args.task,
        target_languages=args.target_language,
        rendered_preview_mode=args.rendered_preview_mode,
    )
    job_id = str(job.get("id") or job.get("Id") or "").strip()
    if not job_id:
        raise RuntimeError(f"Falha ao criar job: {json.dumps(job, ensure_ascii=False)}")

    detail = _poll_job(
        base_url=args.base_url,
        token=token,
        email=args.email,
        password=args.password,
        job_id=job_id,
        timeout_seconds=args.timeout,
        poll_interval=args.poll_interval,
    )

    video_muxed = next(
        (
            item.get("filePath")
            for item in (detail.get("outputs") or [])
            if str(item.get("outputType") or "").lower() == "video_muxed"
        ),
        None,
    )
    render_preview = detail.get("renderPreviewPath")

    summary = {
        "job_id": job_id,
        "file": str(file_path),
        "originalFile": str(original_file_path),
        "contentMode": args.content_mode,
        "subtitleVisualPreset": args.subtitle_visual_preset,
        "aiEnabled": args.ai_enabled,
        "aiModes": args.ai_modes if args.ai_enabled else "",
        "requestedAiProvider": detail.get("requestedAiProvider"),
        "requestedAiModel": detail.get("requestedAiModel"),
        "effectiveAiProvider": detail.get("effectiveAiProvider"),
        "effectiveAiModel": detail.get("effectiveAiModel"),
        "runtimeTarget": detail.get("runtimeTarget"),
        "status": detail.get("status"),
        "progress": detail.get("progressPercent"),
        "currentStage": detail.get("currentStage"),
        "sourceDurationSeconds": detail.get("sourceDurationSeconds"),
        "outputDurationSeconds": detail.get("outputDurationSeconds"),
        "musicalSegmentDurations": detail.get("musicalSegmentDurations"),
        "fallbacks": detail.get("fallbacks"),
        "publishedLanguages": ((detail.get("qualitySummary") or {}).get("publishedLanguages") or []),
        "failedLanguages": ((detail.get("qualitySummary") or {}).get("failedLanguages") or []),
        "artifacts": _collect_artifacts(detail),
        "videoMuxedProbe": _ffprobe_ok(video_muxed),
        "renderPreviewProbe": _ffprobe_ok(render_preview),
        "benchmarkAvailable": benchmark is not None,
        "releaseGate": ((detail.get("qualitySummary") or {}).get("releaseGate") or {}),
        "clipStartSeconds": args.clip_start,
        "clipDurationSeconds": args.clip_duration,
    }
    summary["modelMatch"] = (
        summary["requestedAiProvider"] == summary["effectiveAiProvider"]
        and summary["requestedAiModel"] == summary["effectiveAiModel"]
    )

    TMP_ROOT.mkdir(parents=True, exist_ok=True)
    stamp = time.strftime("%Y%m%d-%H%M%S")
    summary_file = TMP_ROOT / f"{stamp}_{args.content_mode}_{args.use_discovered}.json"
    summary["summaryPath"] = str(summary_file)
    summary_file.write_text(
        json.dumps(summary, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )

    print(json.dumps(summary, ensure_ascii=False, indent=2))
    release_ready = bool((summary["releaseGate"] or {}).get("ready"))
    if args.allow_critical_fallbacks:
        return 0 if str(detail.get("status")).lower() == "completed" else 1
    return 0 if str(detail.get("status")).lower() == "completed" and release_ready else 1


if __name__ == "__main__":
    raise SystemExit(main())
