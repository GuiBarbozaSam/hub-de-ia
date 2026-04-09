# Configuração

## Arquivos versionados

- `infra/.env.compose.example`
- `backend_python/.env.example`
- `backend_dotnet/src/WebApi/appsettings.Development.local.example.json`

## Arquivos locais ignorados pelo Git

- `infra/.env.compose.local`
- `backend_python/.env`
- `backend_dotnet/src/WebApi/appsettings.Development.local.json`

## Bootstrap

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\bootstrap-local-config.ps1
```

## Variáveis locais importantes

### `infra/.env.compose.local`

- `POSTGRES_USER`
- `POSTGRES_PASSWORD`
- `POSTGRES_DB`
- `POSTGRES_HOST_PORT`
- `OLLAMA_HOST_PORT`
- `OLLAMA_PULL_PROFILE`

### `backend_python/.env`

- `TRANSCRIPTION_INTERNAL_API_KEY`
- `SHARED_STORAGE_ROOT`
- `OLLAMA_BASE_URL`
- `OLLAMA_TEXT_MODEL`
- `OLLAMA_VISUAL_MODEL`

### `appsettings.Development.local.json`

- `ConnectionStrings:Default`
- `Jwt:Key`
- `PythonTranscription:InternalApiKey`
- `PythonTranscription:TimeoutMinutes`
- `TranscriptionStorage:RootPath`

## Diretrizes de configuração local

- Os arquivos versionados servem como base pública e mantêm apenas placeholders seguros.
- Os arquivos locais concentram segredos, caminhos específicos da máquina e ajustes de ambiente.
- O valor de `PythonTranscription:InternalApiKey` no `.NET` deve ser o mesmo `TRANSCRIPTION_INTERNAL_API_KEY` do Python.
- O startup `.NET` falha se `ConnectionStrings:Default`, `Jwt:Key` ou `PythonTranscription:InternalApiKey` ainda estiverem com placeholder.
- O backend Python rejeita chamadas internas se a chave estiver ausente ou continuar com placeholder.

## Storage

- O padrão público é `shared_storage` na raiz do repositório.
- O backend Python resolve caminhos relativos contra a raiz do projeto.
- O `.NET` usa `../../../shared_storage` a partir de `backend_dotnet/src/WebApi`.
