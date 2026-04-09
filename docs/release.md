# Publicação e manutenção

## Objetivo

Este documento resume as validações mínimas para manter o repositório público consistente, reproduzível e livre de conteúdo local sensível.

## Validações recomendadas

### Build e testes

```powershell
dotnet build .\backend_dotnet\src\WebApi\WebApi.csproj
dotnet test .\backend_dotnet\tests\WebApi.Tests\WebApi.Tests.csproj
python -m pytest .\backend_python\tests
cd .\app_flutter; flutter test
```

### Verificação de segredos

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\scan-secrets.ps1
```

### Validação de mídia

```powershell
python .\scripts\smoke-transcription.py --use-discovered short --content-mode episode
python .\scripts\smoke-transcription.py --use-discovered short --content-mode anime_song
python .\scripts\smoke-transcription.py --use-discovered long --content-mode episode
python .\scripts\smoke-transcription.py --use-discovered long --content-mode anime_song
```

Os resumos técnicos dessas execuções ficam em `.tmp/smoke` e ajudam a confirmar integridade de artefatos, duração de mídia e estado do gate técnico.

## Critérios técnicos de publicação

Uma publicação técnica deve evitar:

- artefatos finais ausentes, como `render_preview.mp4` ou `video_muxed.mkv`
- bloqueios de qualidade reportados em `quality_report.json`
- labels semânticos inválidos em `scene_map.json` ou `karaoke_plan.json`
- uso de configurações locais ou credenciais reais no conteúdo versionado

## Conteúdo esperado no repositório público

- código-fonte
- documentação
- exemplos de configuração
- workflows de integração contínua

## Conteúdo mantido fora do repositório

- pesos e caches de modelos
- diretórios gerados em `shared_storage`
- arquivos temporários em `.tmp`
- arquivos locais de ambiente e configuração
- credenciais e caminhos específicos de máquina
