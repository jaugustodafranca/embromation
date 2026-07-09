# Design: Tradutor local de texto selecionado (nome provisório: local-translator)

**Data:** 2026-07-09
**Status:** Aguardando revisão do autor
**Protótipo interativo:** https://claude.ai/code/artifact/46ddca1b-5bcd-4fa2-80d9-39f8b7dabb9a

> O nome definitivo do app/repositório será decidido antes da publicação no GitHub.
> Este documento está em português para facilitar a revisão; será traduzido para
> inglês quando o repositório for tornado público.

## 1. Contexto e motivação

O autor usa hoje o keybinder (app pessoal de automações por hotkey) exclusivamente
para traduzir textos, e o fluxo parece lento. Diagnóstico do keybinder:

1. Espera fixa de 200ms após simular Cmd+C, antes de qualquer processamento.
2. Chamada a modelos de nuvem (OpenAI/Anthropic/Gemini) **sem streaming** — o
   usuário espera a latência de rede mais o tempo total de geração.
3. Resultado vai para o clipboard sem feedback visual; é preciso colar manualmente.

Este projeto substitui esse fluxo por um app dedicado, open-source, com modelo
rodando **localmente** — sem API key, sem rede, sem conta — e com streaming
visível na tela.

## 2. Decisões de produto (com justificativa)

| Decisão | Escolha | Justificativa |
|---|---|---|
| Plataforma | macOS somente (Apple Silicon, macOS 14+) | É a plataforma do autor; app nativo maximiza velocidade e integração. Expansão futura fica a cargo da comunidade. |
| Stack | Swift + SwiftUI | A UI é ~10% do app; os 90% restantes (hotkey global, painel não-ativante, Accessibility API, inferência) são nativos de qualquer forma. React Native/Flutter exigiriam módulos nativos + ponte; Electron (familiar ao autor) custaria ~250MB e mais RAM. Avaliados e descartados conscientemente. |
| Motor | MLX embutido (mlx-swift / MLXLLM) | Experiência "instala e funciona": sem dependência externa (Ollama), sem API key. Inferência rápida em Apple Silicon (~50-100 tok/s em modelos 3-4B). |
| Modelo padrão | Gemma 3 4B instruct 4-bit (~2,5GB) | Forte em multilíngue. Catálogo curado com alternativas: Qwen 3 4B e um modelo ~1.5B para Macs com 8GB de RAM. |
| UX principal | Popup flutuante com streaming | Primeira palavra em <0,5s elimina a sensação de lentidão. Serve para ler e para escrever. |
| Idiomas | Par principal com detecção automática | Um único atalho para os dois sentidos (ex: PT↔EN). Detecção via NLLanguageRecognizer; seletor no popup para trocar o destino pontualmente. |
| Tom/Glossário | Configuração global única | Seletor de tom (neutro/formal/casual) + instruções livres + lista de termos que nunca devem ser traduzidos. Perfis múltiplos ficam para depois se houver demanda. |
| Estrutura | App + Swift Package interno (`TranslatorCore`) | Core testável e reusável sem dependência de UI; convida contribuições. |
| Licença | MIT | Padrão para utilitários open-source. |

**Limitação assumida:** MLX exige Apple Silicon. Macs Intel não são suportados;
o app detecta e explica no launch.

## 3. Estrutura do repositório

```
├── App/                    # Target SwiftUI
│   ├── MenuBar/            # Status item (LSUIElement, sem ícone no Dock)
│   ├── Popup/              # NSPanel não-ativante + view de streaming
│   ├── Settings/           # Janela única de ajustes
│   └── Onboarding/         # Fluxo de primeiro uso (3 passos)
├── TranslatorCore/         # Swift Package sem dependência de UI
│   ├── InferenceEngine     # Wrapper do MLXLLM; protocolo StreamingTranslator
│   ├── ModelManager        # Download do Hugging Face, cache, catálogo curado
│   ├── PromptBuilder       # Prompt com idiomas, tom, instruções e glossário
│   ├── LanguageDetector    # NLLanguageRecognizer (nativo, instantâneo)
│   └── SelectionCapture    # AX API + fallback Cmd+C com polling
└── .github/workflows/      # CI (build + testes) e release (sign/notarize + DMG)
```

Dependências externas: `mlx-swift-examples` (MLXLLM/MLXLMCommon) e
`KeyboardShortcuts` (sindresorhus) para o recorder de atalho global.

## 4. Componentes

### 4.1 SelectionCapture
Duas camadas:
1. **Accessibility API** — lê `kAXSelectedTextAttribute` do elemento focado.
   Instantâneo e não toca no clipboard. Não funciona em todos os apps
   (alguns Electron/web não expõem).
2. **Fallback Cmd+C simulado** — em vez de espera fixa, faz polling do
   `changeCount` do NSPasteboard a cada 10ms (timeout 300ms; na prática
   resolve em 30-50ms). Restaura o conteúdo original do clipboard ao final.

Ambas exigem permissão de Acessibilidade (pedida no onboarding).

### 4.2 InferenceEngine
Wrapper do MLXLLM atrás de um protocolo `StreamingTranslator` (permite fake nos
testes). Carrega o modelo na primeira tradução (~1-2s) e o mantém residente;
descarrega após inatividade configurável (padrão 10 min) para liberar ~2,5GB de
RAM. Emite tokens via `AsyncSequence` para a UI streamar.

### 4.3 ModelManager
Baixa o modelo do Hugging Face no onboarding, com progresso, retry e resume.
Armazena em `~/Library/Application Support/<app>/models/`. Mantém o catálogo
curado (3 opções) com id do repositório HF, tamanho e requisito mínimo de RAM.

### 4.4 PromptBuilder
Monta o system prompt de forma determinística e testável:
- idioma de origem (detectado) e destino (resolvido pelo par),
- tom (neutro/formal/casual) e instruções livres do usuário,
- lista de termos protegidos ("nunca traduza: deploy, commit, …"),
- instrução rígida: responder SOMENTE com a tradução, sem explicações.

### 4.5 LanguageDetector
`NLLanguageRecognizer.dominantLanguage` sobre o texto capturado. Resolução do
destino: se o idioma detectado é um dos lados do par principal, traduz para o
outro; caso contrário, traduz para o lado primário do par.

### 4.6 Popup
`NSPanel` não-ativante (o foco permanece no app de origem), posicionado próximo
ao cursor do mouse. Conteúdo SwiftUI:
- header: chip "EN → PT-BR" + status do modelo,
- corpo: texto streamando com caret,
- rodapé: **Copiar** (⌘C), **Substituir** (⏎ — cola por cima da seleção via
  Cmd+V simulado e restaura o clipboard), seletor de destino pontual
  (re-executa), dica "esc fecha".
Fecha com Esc ou clique fora.

### 4.7 Settings
Janela única (padrão visual de Ajustes do macOS): par de idiomas, tom,
instruções livres, glossário (chips com adicionar/remover), atalho global
(recorder), modelo (catálogo + status de download), descarregar após
inatividade, iniciar no login. Persistência via `UserDefaults`
(nada sensível — não há API keys).

### 4.8 Onboarding
Três passos no primeiro launch: boas-vindas → permissão de Acessibilidade
(botão para System Settings, com verificação de estado) → download do modelo
com barra de progresso. Termina ensinando o atalho padrão (⌥⌘T).

## 5. Fluxo principal

1. Atalho global disparado.
2. Captura da seleção (AX → fallback Cmd+C com polling).
3. Seleção vazia → popup mostra "nenhum texto selecionado" e se fecha sozinho.
4. Detecta idioma → resolve destino pelo par configurado.
5. Popup aparece imediatamente com indicador de progresso.
6. Modelo não carregado? Carrega mostrando "preparando modelo…".
7. Tokens streamam no popup conforme gerados.
8. Usuário copia, substitui, troca o destino ou fecha.

## 6. Tratamento de erros

| Situação | Comportamento |
|---|---|
| Sem permissão de Acessibilidade | Popup explica e abre o painel do sistema; onboarding cobre o caso comum. |
| Download do modelo falha | Retry com resume; app permanece funcional (sem traduzir) e informa o estado. |
| Mac Intel | Alerta no launch explicando o requisito de Apple Silicon. |
| Erro/OOM na geração | Mensagem no popup com "tentar de novo"; sugere modelo menor se RAM for a causa. |
| Seleção não capturável (app sem AX e Cmd+C falhou) | Popup orienta a copiar manualmente e re-disparar o atalho (traduz o clipboard). |

## 7. Testes

- **Unit (TranslatorCore):** PromptBuilder (tom/glossário/idiomas), resolução do
  par de idiomas, catálogo de modelos, lógica de retry do ModelManager
  (com URLSession mockada).
- **Fake de inferência:** `StreamingTranslator` fake que streama texto fixo —
  usado nos testes de integração da UI sem carregar modelo real.
- **Manual:** checklist versionado no repo para inferência real, captura em
  apps diversos (Safari, Chrome, VS Code, Slack) e fluxo de substituição.
- **CI:** GitHub Actions em runner macOS arm64 — build + testes a cada push.

## 8. Distribuição

- GitHub Releases com DMG **assinado e notarizado** (Developer ID existente do autor).
- README em inglês com GIF demonstrativo.
- Homebrew cask após o primeiro release estável.
- Auto-update (Sparkle) fica para um segundo momento.

## 9. Fora de escopo (primeira versão)

Histórico de traduções, OCR/tradução de screenshots, Windows/Linux, perfis
múltiplos de tom/glossário, auto-update, CLI independente. O core separado
facilita qualquer um desses no futuro.
