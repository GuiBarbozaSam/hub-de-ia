# Hub de IA

Hub de IA é uma plataforma local para fluxos de mídia assistidos por IA e automação de processamento. O módulo atualmente mais completo do projeto é o de transcrição, tradução, revisão e renderização de legendas com `Flutter -> .NET -> FastAPI/Python`.

## Capacidades atuais

- Processamento de vídeo e áudio por upload, URL ou caminho local.
- Geração de `txt`, `srt`, `vtt`, `ass`, `video_muxed.mkv` e `render_preview.mp4`.
- Modos de legenda para episódios e conteúdo musical.
- Diagnósticos por etapa, metadados de qualidade e artefatos técnicos por execução.

## Estrutura da solução

- `app_flutter`: interface de configuração, histórico e preview.
- `backend_dotnet`: API principal, autenticação, persistência e orquestração.
- `backend_python`: serviços de processamento, transcrição, tradução e render.
- `infra`: runtime local com Docker para dependências e serviços auxiliares.

## Módulo atual de legendagem

1. O Flutter envia o job para a API `.NET`.
2. A API persiste a execução, expõe progresso e delega o processamento ao backend Python.
3. O backend Python executa o pipeline de mídia e gera os artefatos finais.
4. O worker `.NET` publica outputs, diagnósticos e metadados operacionais.

## Setup local

1. Gere os arquivos locais a partir dos exemplos:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\bootstrap-local-config.ps1
```

2. Preencha os valores locais em:

- `infra/.env.compose.local`
- `backend_python/.env`
- `backend_dotnet/src/WebApi/appsettings.Development.local.json`

3. Suba o ambiente:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\start-all.ps1
```

## Validação técnica

```powershell
dotnet build .\backend_dotnet\src\WebApi\WebApi.csproj
dotnet test .\backend_dotnet\tests\WebApi.Tests\WebApi.Tests.csproj
python -m pytest .\backend_python\tests
cd .\app_flutter; flutter test
powershell -ExecutionPolicy Bypass -File .\scripts\scan-secrets.ps1
```

## Validação de mídia

O script `scripts/smoke-transcription.py` executa upload, polling, validação com `ffprobe` e salva um resumo técnico em `.tmp/smoke`.

```powershell
python .\scripts\smoke-transcription.py --use-discovered long --content-mode episode
python .\scripts\smoke-transcription.py --use-discovered long --content-mode anime_song
```

## Documentação

- [Arquitetura](docs/architecture.md)
- [Configuração local](docs/configuration.md)
- [Publicação e manutenção](docs/release.md)
