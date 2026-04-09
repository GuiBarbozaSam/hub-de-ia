import argparse
import json
import time
import urllib.request
from typing import Any


TRANSLATION_ITEMS = [
    {"index": 0, "text": "語れない 眠れない 届いめない"},
    {"index": 1, "text": "あなたの見てる正体"},
]

STYLE_ITEMS = [
    {"index": 0, "text": "語れない 眠れない 届いめない", "durationSeconds": 4.8},
    {"index": 1, "text": "あなたの見てる正体", "durationSeconds": 3.2},
]


def _post_json(url: str, payload: dict[str, Any], timeout_seconds: int) -> dict[str, Any]:
    request = urllib.request.Request(
        url,
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=timeout_seconds) as response:
        return json.loads(response.read().decode("utf-8", errors="replace"))


def _translation_schema() -> dict[str, Any]:
    return {
        "type": "object",
        "properties": {
            "items": {
                "type": "array",
                "items": {
                    "type": "object",
                    "properties": {
                        "index": {"type": "integer"},
                        "text": {"type": "string"},
                    },
                    "required": ["index", "text"],
                },
            }
        },
        "required": ["items"],
    }


def _label_schema() -> dict[str, Any]:
    return {
        "type": "object",
        "properties": {
            "items": {
                "type": "array",
                "items": {
                    "type": "object",
                    "properties": {
                        "index": {"type": "integer"},
                        "label": {
                            "type": "string",
                            "enum": ["default", "chorus", "emphasis", "whisper", "shout"],
                        },
                    },
                    "required": ["index", "label"],
                },
            }
        },
        "required": ["items"],
    }


def _build_translation_payload(model: str, count: int) -> dict[str, Any]:
    items = TRANSLATION_ITEMS[:count]
    return {
        "model": model,
        "stream": False,
        "think": False,
        "format": _translation_schema(),
        "messages": [
            {
                "role": "system",
                "content": "You are a subtitle translator. Return only valid JSON matching the schema and keep the item count unchanged.",
            },
            {
                "role": "user",
                "content": json.dumps(
                    {
                        "task": "translate_subtitles",
                        "sourceLanguage": "Japanese",
                        "targetLanguage": "English",
                        "expectedCount": count,
                        "items": items,
                        "instructions": [
                            "Translate naturally.",
                            f"Return exactly {count} items.",
                            "Do not add commentary.",
                        ],
                    },
                    ensure_ascii=False,
                ),
            },
        ],
        "options": {"temperature": 0, "top_p": 0.9, "num_predict": 192},
    }


def _build_style_payload(model: str) -> dict[str, Any]:
    return {
        "model": model,
        "stream": False,
        "think": False,
        "format": _label_schema(),
        "messages": [
            {
                "role": "system",
                "content": "You classify subtitle lines into safe visual labels. Return only JSON matching the schema.",
            },
            {
                "role": "user",
                "content": json.dumps(
                    {
                        "task": "classify_subtitle_style_labels",
                        "preset": "cinematic",
                        "expectedCount": len(STYLE_ITEMS),
                        "items": STYLE_ITEMS,
                        "instructions": [
                            "Choose one label per item.",
                            "Use only the allowed labels.",
                            "Do not add commentary.",
                        ],
                    },
                    ensure_ascii=False,
                ),
            },
        ],
        "options": {"temperature": 0, "top_p": 0.9, "num_predict": 96},
    }


def _response_text(decoded: dict[str, Any]) -> str:
    message = decoded.get("message")
    if isinstance(message, dict) and message.get("content"):
        return str(message["content"])
    for key in ("response", "thinking", "output"):
        value = decoded.get(key)
        if value:
            return str(value)
    return json.dumps(decoded, ensure_ascii=False)


def _run_case(base_url: str, payload: dict[str, Any], timeout_seconds: int) -> dict[str, Any]:
    started = time.perf_counter()
    try:
        response = _post_json(f"{base_url}/api/chat", payload, timeout_seconds)
        elapsed = round(time.perf_counter() - started, 2)
        return {
            "ok": True,
            "seconds": elapsed,
            "responseField": "message.content" if isinstance(response.get("message"), dict) else "response",
            "content": _response_text(response),
        }
    except Exception as exc:
        elapsed = round(time.perf_counter() - started, 2)
        return {
            "ok": False,
            "seconds": elapsed,
            "error": str(exc),
        }


def main() -> int:
    parser = argparse.ArgumentParser(description="Benchmark structured Ollama requests used by the transcription pipeline.")
    parser.add_argument("--base-url", default="http://127.0.0.1:11435")
    parser.add_argument(
        "--models",
        nargs="+",
        default=[
            "gemma3:4b",
            "qwen2.5:14b",
            "qwen2.5vl:7b",
            "qwen2.5:32b",
        ],
    )
    parser.add_argument("--timeout", type=int, default=180)
    args = parser.parse_args()

    results: list[dict[str, Any]] = []
    for model in args.models:
        results.append(
            {
                "model": model,
                "translation_1_item": _run_case(
                    args.base_url,
                    _build_translation_payload(model, 1),
                    args.timeout,
                ),
                "translation_2_items": _run_case(
                    args.base_url,
                    _build_translation_payload(model, 2),
                    args.timeout,
                ),
                "style_labels_2_items": _run_case(
                    args.base_url,
                    _build_style_payload(model),
                    args.timeout,
                ),
            }
        )

    print(json.dumps({"generatedAt": time.strftime("%Y-%m-%dT%H:%M:%S"), "results": results}, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
