# Arquitetura

## Visão geral

Hub de IA é organizado como uma solução modular. O módulo de mídia e legendagem é o componente atualmente mais avançado e está dividido em três camadas executáveis:

- `app_flutter`: interface de configuração, acompanhamento e preview.
- `backend_dotnet`: API pública, autenticação JWT, persistência dos jobs e orquestração.
- `backend_python`: serviços de processamento de mídia, transcrição, tradução, revisão e render.

## Fluxo do módulo de legendagem

1. O usuário cria um job no Flutter.
2. A API `.NET` grava `TranscriptionJob` e `TranscriptionJobOutput`.
3. O `TranscriptionJobWorker` chama o backend Python por rota interna autenticada.
4. O backend Python executa o pipeline de mídia:
   - `ingest`
   - `asr`
   - `alignment`
   - `cleanup`
   - `draft_translation`
   - `review_loop`
   - `timing_fit`
   - `content_analysis`
   - `voice_analysis`
   - `scene_analysis`
   - `style_planning`
   - `karaoke_planning`
   - `render`
   - `package`
5. O worker publica artefatos, diagnósticos e estado final da execução.

## Artefatos principais

- `quality_report.json`: resumo de qualidade, idiomas publicados e bloqueios de publicação.
- `style_map.json`: plano visual consolidado.
- `scene_map.json`: blocos visuais e temáticos por trecho.
- `speaker_map.json`: spans de voz por heurística ou diarização.
- `karaoke_plan.json`: eventos de karaoke no modo `anime_song`.
- `lyric_alignment.json`: alinhamento derivado do plano de karaoke.
- `render_preview.mp4`: preview renderizado para inspeção rápida.
- `video_muxed.mkv`: vídeo com trilhas muxadas.

## Modos de conteúdo

- `episode`: foco em legibilidade, timing e preview rápido.
- `anime_song`: layout musical com `romaji` e tradução, além de preview renderizado por padrão.

## Políticas de render

- A camada de IA não escreve `ASS` livremente.
- Os serviços geram apenas rótulos e planos semânticos.
- O renderer determinístico produz `ASS` válido com limites seguros para cor, outline, blur, margins e scale.

## Publicação técnica

O `quality_report.json` pode carregar `releaseGate`, usado para validar publicações técnicas e detectar saídas incompletas ou inconsistentes.

## Limitações atuais

- `speakerStyleMode=advanced` depende de capability real de diarização.
- Em hardware restrito, o pipeline pode preferir presets visuais determinísticos.
- O preview rápido prioriza fluidez e inspeção operacional.
