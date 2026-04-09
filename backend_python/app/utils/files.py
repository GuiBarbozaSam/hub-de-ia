from pathlib import Path
from uuid import uuid4

from fastapi import UploadFile

from app.core.exceptions import FileTooLargeError, InvalidUploadError


async def save_upload_file(
    upload_file: UploadFile,
    destination_dir: Path,
    max_bytes: int,
) -> tuple[Path, int]:
    if upload_file is None:
        raise InvalidUploadError("Nenhum arquivo foi enviado.")

    original_name = upload_file.filename or "input.bin"
    suffix = Path(original_name).suffix or ".bin"

    destination_dir.mkdir(parents=True, exist_ok=True)
    file_path = destination_dir / f"{uuid4().hex}{suffix}"

    total_size = 0

    try:
        with file_path.open("wb") as buffer:
            while True:
                chunk = await upload_file.read(1024 * 1024)
                if not chunk:
                    break

                total_size += len(chunk)
                if total_size > max_bytes:
                    raise FileTooLargeError(
                        f"Arquivo excede o limite de {max_bytes} bytes."
                    )

                buffer.write(chunk)

        if total_size == 0:
            raise InvalidUploadError("O arquivo enviado está vazio.")

        return file_path, total_size

    except Exception:
        if file_path.exists():
            file_path.unlink(missing_ok=True)
        raise

    finally:
        await upload_file.close()