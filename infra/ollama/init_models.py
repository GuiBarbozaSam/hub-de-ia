from __future__ import annotations

import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path


def _request_json(url: str, payload: dict | None = None, timeout: int = 30) -> dict:
    request = urllib.request.Request(
        url,
        data=None if payload is None else json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="GET" if payload is None else "POST",
    )
    with urllib.request.urlopen(request, timeout=timeout) as response:
        body = response.read().decode("utf-8", errors="replace")
    return json.loads(body or "{}")


def _wait_for_ollama(base_url: str, timeout_seconds: int = 240) -> None:
    deadline = time.time() + timeout_seconds
    last_error = "Ollama ainda não respondeu."
    while time.time() < deadline:
        try:
            _request_json(f"{base_url}/api/tags", timeout=10)
            return
        except Exception as exc:  # pragma: no cover - best effort bootstrap
            last_error = str(exc)
            time.sleep(2)
    raise RuntimeError(f"Falha ao conectar no Ollama em {base_url}: {last_error}")


def _load_catalog(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def _models_for_profile(catalog: dict, profile: str, include_compatibility: bool = False) -> list[str]:
    profiles = catalog.get("profiles") or {}
    selected = profiles.get(profile) or profiles.get("balanced") or {}
    ordered: list[str] = []
    for key in ("textModel", "visualModel"):
        value = str(selected.get(key) or "").strip()
        if value and value not in ordered:
            ordered.append(value)
    if include_compatibility:
        for value in catalog.get("compatibilityModels") or []:
            model = str(value).strip()
            if model and model not in ordered:
                ordered.append(model)
    return ordered


def _pull_model(base_url: str, model: str) -> None:
    print(f"[ollama-init] pulling {model}", flush=True)
    _request_json(
        f"{base_url}/api/pull",
        {"name": model, "stream": False},
        timeout=60 * 60,
    )


def main() -> int:
    parser = argparse.ArgumentParser(description="Pulls the project Ollama models for a selected profile.")
    parser.add_argument("--base-url", required=True)
    parser.add_argument("--catalog", required=True)
    parser.add_argument("--profile", default=os.getenv("OLLAMA_PULL_PROFILE", "balanced"))
    parser.add_argument("--include-compatibility", action="store_true")
    args = parser.parse_args()

    base_url = args.base_url.rstrip("/")
    catalog = _load_catalog(Path(args.catalog))
    include_compatibility = args.include_compatibility or os.getenv("OLLAMA_INCLUDE_COMPATIBILITY", "").strip().lower() in {"1", "true", "yes", "on"}
    models = _models_for_profile(catalog, args.profile, include_compatibility=include_compatibility)
    if not models:
        print("[ollama-init] no models configured", flush=True)
        return 0

    _wait_for_ollama(base_url)
    for model in models:
      _pull_model(base_url, model)
    print("[ollama-init] model bootstrap complete", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
