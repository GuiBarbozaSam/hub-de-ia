from __future__ import annotations

import hmac
from typing import Annotated

from fastapi import Header, HTTPException, status

from app.core.config import get_settings


_INTERNAL_API_KEY_HEADER_NAME = "X-Internal-Api-Key"


def _read_expected_internal_api_key() -> str:
    settings = get_settings()
    expected = (getattr(settings, "transcription_internal_api_key", None) or "").strip()
    if not expected or "change_me" in expected.lower() or "troque" in expected.lower():
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=(
                "A chave interna de transcrição não está configurada no backend Python. "
                "Defina transcription_internal_api_key antes de expor a rota interna."
            ),
        )
    return expected


def _read_presented_internal_api_key(value: str | None) -> str:
    presented = (value or "").strip()
    if not presented:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=(
                "Cabeçalho interno ausente. Envie a chave em "
                f"{_INTERNAL_API_KEY_HEADER_NAME}."
            ),
        )
    return presented


HeaderInternalApiKey = Annotated[
    str | None,
    Header(alias=_INTERNAL_API_KEY_HEADER_NAME, convert_underscores=False),
]


async def verify_internal_api_key(
    x_internal_api_key: HeaderInternalApiKey = None,
) -> None:
    """
    Valida a chave interna usada pelo backend .NET para chamar as rotas privadas
    de transcrição no backend Python.

    Mantém o nome mais comum usado nas rotas já existentes (`verify_internal_api_key`)
    e centraliza mensagens/validação em helpers pequenos para facilitar manutenção.
    """
    expected = _read_expected_internal_api_key()
    presented = _read_presented_internal_api_key(x_internal_api_key)

    if not hmac.compare_digest(presented, expected):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Chave interna inválida.",
        )


# Aliases de compatibilidade para não quebrar imports antigos caso alguma rota/utilitário
# ainda referencie nomes legados do projeto.
async def require_internal_api_key(
    x_internal_api_key: HeaderInternalApiKey = None,
) -> None:
    await verify_internal_api_key(x_internal_api_key)


async def validate_internal_api_key(
    x_internal_api_key: HeaderInternalApiKey = None,
) -> None:
    await verify_internal_api_key(x_internal_api_key)
