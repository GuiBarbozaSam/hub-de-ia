import argparse
import json
import subprocess
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
TMP_ROOT = REPO_ROOT / ".tmp" / "smoke" / "clips"


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
        timeout=120,
        check=False,
    )
    if result.returncode != 0:
        return 0.0
    try:
        return float((result.stdout or "0").strip().splitlines()[0])
    except Exception:
        return 0.0


def _probe_chapters(path: Path) -> list[dict]:
    result = subprocess.run(
        [
            "ffprobe",
            "-v",
            "error",
            "-show_chapters",
            "-print_format",
            "json",
            str(path),
        ],
        capture_output=True,
        text=True,
        timeout=120,
        check=False,
    )
    if result.returncode != 0:
        return []
    try:
        decoded = json.loads(result.stdout or "{}")
    except Exception:
        return []
    chapters = []
    for item in decoded.get("chapters") or []:
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
                "start": start,
                "end": end,
                "duration": end - start,
            }
        )
    return chapters


def _classify_chapter(title: str) -> str | None:
    normalized = title.strip().lower()
    if not normalized:
        return None
    if any(token in normalized for token in ["abertura", "opening", "ncop"]):
        return "opening"
    if any(token in normalized for token in ["encerramento", "ending", "nced"]):
        return "ending"
    if any(token in normalized for token in ["insert song", "karaoke", "theme", "song", "music"]):
        return "insert_song"
    return None


def _extract_clip(source_path: Path, start: float, duration: float, label: str) -> Path:
    TMP_ROOT.mkdir(parents=True, exist_ok=True)
    target = TMP_ROOT / f"{source_path.stem}_{label}.mp4"
    result = subprocess.run(
        [
            "ffmpeg",
            "-y",
            "-ss",
            f"{start:.3f}",
            "-i",
            str(source_path),
            "-t",
            f"{duration:.3f}",
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
        ],
        capture_output=True,
        text=True,
        timeout=1800,
        check=False,
    )
    if result.returncode != 0 or not target.exists():
        raise RuntimeError(
            f"Falha ao extrair clip {label}. ffmpeg={result.returncode} stderr={result.stderr.strip() or result.stdout.strip()}"
        )
    return target


def _episode_clips(source_path: Path, dialogue_duration: float, song_duration: float) -> list[dict]:
    chapters = _probe_chapters(source_path)
    if not chapters:
        total_duration = _probe_duration(source_path)
        if total_duration <= 0:
            raise RuntimeError("Não foi possível detectar capítulos nem duração do arquivo.")
        middle_start = max(0.0, (total_duration / 2.0) - (dialogue_duration / 2.0))
        return [
            {"label": "dialogue_mid", "start": middle_start, "duration": dialogue_duration},
        ]

    opening = next((chapter for chapter in chapters if _classify_chapter(chapter["title"]) == "opening"), None)
    ending = next((chapter for chapter in chapters if _classify_chapter(chapter["title"]) == "ending"), None)
    narrative = next((chapter for chapter in chapters if _classify_chapter(chapter["title"]) is None), None)
    clips: list[dict] = []
    if opening:
        clips.append(
            {
                "label": "opening",
                "start": opening["start"],
                "duration": min(song_duration, opening["duration"]),
            }
        )
    if narrative:
        clips.append(
            {
                "label": "dialogue_mid",
                "start": max(narrative["start"], ((narrative["start"] + narrative["end"]) / 2.0) - (dialogue_duration / 2.0)),
                "duration": min(dialogue_duration, narrative["duration"]),
            }
        )
    if ending:
        clips.append(
            {
                "label": "ending",
                "start": ending["start"],
                "duration": min(song_duration, ending["duration"]),
            }
        )
    return clips


def _song_clips(source_path: Path, clip_duration: float) -> list[dict]:
    total_duration = _probe_duration(source_path)
    if total_duration <= 0:
        raise RuntimeError("Não foi possível detectar a duração do arquivo musical.")
    effective = min(clip_duration, max(10.0, total_duration))
    middle_start = max(0.0, (total_duration / 2.0) - (effective / 2.0))
    end_start = max(0.0, total_duration - effective)
    return [
        {"label": "song_start", "start": 0.0, "duration": effective},
        {"label": "song_mid", "start": middle_start, "duration": effective},
        {"label": "song_end", "start": end_start, "duration": effective},
    ]


def main() -> int:
    parser = argparse.ArgumentParser(description="Gera clipes curados para calibracao de karaoke/legenda.")
    parser.add_argument("--file", required=True)
    parser.add_argument("--profile", choices=["episode", "song", "auto"], default="auto")
    parser.add_argument("--dialogue-duration", type=float, default=30.0)
    parser.add_argument("--song-duration", type=float, default=40.0)
    args = parser.parse_args()

    source_path = Path(args.file).resolve()
    if not source_path.exists():
        raise FileNotFoundError(f"Arquivo não encontrado: {source_path}")

    profile = args.profile
    if profile == "auto":
        chapters = _probe_chapters(source_path)
        has_song_chapters = any(_classify_chapter(chapter["title"]) for chapter in chapters)
        has_narrative = any(_classify_chapter(chapter["title"]) is None for chapter in chapters)
        profile = "episode" if has_song_chapters and has_narrative else "song"

    definitions = (
        _episode_clips(source_path, args.dialogue_duration, args.song_duration)
        if profile == "episode"
        else _song_clips(source_path, args.song_duration)
    )

    manifest = {
        "sourceFile": str(source_path),
        "profile": profile,
        "clips": [],
    }

    for definition in definitions:
        clip_path = _extract_clip(
            source_path,
            start=float(definition["start"]),
            duration=float(definition["duration"]),
            label=str(definition["label"]),
        )
        manifest["clips"].append(
            {
                "label": definition["label"],
                "start": round(float(definition["start"]), 3),
                "duration": round(float(definition["duration"]), 3),
                "file": str(clip_path),
            }
        )

    TMP_ROOT.mkdir(parents=True, exist_ok=True)
    manifest_path = TMP_ROOT / f"{source_path.stem}_{profile}_clips.json"
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(manifest, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
