# Design: Correção de texto + Refinamento por feedback (Feature 2)

**Data:** 2026-07-10
**Status:** Aguardando revisão do autor
**Base:** main pós-merge do MVP (PR #1). Completa o escopo da v1.0.0.

## 1. Contexto

Durante o QA do MVP o autor esclareceu que seu uso principal não é traduzir
textos alheios, e sim **corrigir o que ele mesmo escreve** (gramática,
ortografia, pontuação — mantendo idioma, significado e tom). Além disso,
pediu a capacidade de **dar feedback ao modelo e regenerar** ("ficou formal
demais", "errou o contexto") direto no popup.

## 2. Decisões (fechadas em conversa, 2026-07-10)

| Decisão | Escolha |
|---|---|
| Ação nova | **Corrigir** (Fix grammar): mesmo pipeline, prompt próprio, mesmo idioma do texto |
| Atalho | Próprio e configurável (recorder), default **⌥⌘G**; item "Fix grammar ⌥⌘G" no menu da barra |
| Fluxo da correção | **Configurável nos Settings**: "Mostrar popup" (default) vs "Substituir direto". Erros no modo direto sempre abrem o popup |
| Refinamento | Campo de feedback no popup (ambas as ações) → regenera usando histórico de chat (system + texto + resposta anterior + feedback). Vive só na sessão do popup; nada é armazenado ou enviado |
| Menu | Ambos os itens com hint de atalho (preenche a coluna reservada que hoje fica vazia) |

## 3. Mudanças no TranslatorCore

### 3.1 Modo na requisição

```swift
public enum TranslationMode: Equatable, Sendable {
    case translate   // source → target
    case correct     // fix grammar/spelling/punctuation, same language
}
```

`TranslationRequest` ganha `mode: TranslationMode` (default `.translate` para
compatibilidade) e `refinement: Refinement?`:

```swift
public struct Refinement: Equatable, Sendable {
    public var previousOutput: String
    public var feedback: String
}
```

### 3.2 PromptBuilder

Novo método `correctionPrompt(language:tone:customInstructions:glossary:)`:

> "You are a proofreading engine. Fix grammar, spelling and punctuation of the
> user's message, keeping the SAME language (\(language.englishName)), meaning
> and tone. Preserve emoji, keyboard shortcuts, code, URLs, numbers and any
> other symbols exactly as written. [tone/custom/glossary clauses as today]
> Reply with ONLY the corrected text."

O prompt de tradução atual permanece como está.

### 3.3 Chat com refinamento (engine)

No `MLXTranslator`, quando `request.refinement != nil` o chat vira:

```
system(prompt do modo) · user(texto) · assistant(previousOutput) ·
user("Feedback: \(feedback). Produce an improved version. Reply with ONLY the new text.")
```

`FakeTranslator` passa a ecoar o feedback quando presente (testável).

## 4. Mudanças no App

### 4.1 Coordinator

- `correctSelection()` — mesmo fluxo do translate, `mode: .correct`; o idioma
  detectado é usado apenas para o prompt (chip mostra ex: "PT ✓" em vez de
  "PT → EN").
- Modo direto (setting): não mostra popup; captura → corrige (sem streaming
  visível) → `SelectionReplacer`. Falha em qualquer etapa → abre popup com o
  erro (regra: todo erro tem ação de recuperação).
- `refine(feedback:)` — reexecuta a última requisição com `Refinement`
  (funciona para translate e correct; re-target continua limpando refinement).

### 4.2 Popup

- Campo de feedback (TextField) visível quando `phase == .done`, com
  placeholder localizado ("Tell the model what to fix…"); Enter no campo →
  `refine(feedback:)`.
- **Foco:** o painel passa a `canBecomeKey = true` mantendo
  `.nonactivatingPanel` + `becomesKeyOnlyIfNeeded = true` — só o clique no
  campo de texto toma o teclado; botões e atalhos continuam sem roubar foco.
  Ao regenerar/fechar, o painel devolve o foco ao app de origem (necessário
  para o Replace continuar funcionando).
- Header no modo correção mostra o idioma único (sem "→").

### 4.3 Hotkey e menu

- `KeyboardShortcuts.Name.fixGrammar`, default ⌥⌘G, registrado no
  `HotkeyController` ao lado do translate.
- Menu: "Translate selection ⌥⌘T" e "Fix grammar ⌥⌘G" (hints estáticos dos
  defaults; se o usuário re-gravar o atalho, o hint do menu é cosmético —
  aceito para v1).

### 4.4 Settings

Nova seção **Correction**: recorder do atalho + picker do fluxo
("Show popup" / "Replace directly"). `SettingsData` ganha
`correctionReplacesDirectly: Bool = false`.

## 5. Débitos de QA incluídos nesta feature

1. **Progresso de download honesto** — o handler atual reporta 0-1% durante
   todo o download. Trocar por barra indeterminada + status por bytes se o
   callback não fornecer fração confiável (medir via tamanho conhecido do
   arquivo quando possível), e **botão de cancelar/tentar de novo** visível
   durante o download (estado preso em `.downloading` hoje não tem saída).
2. **Reabrir onboarding** — item "Welcome guide" no menu da barra (abre a
   janela `onboarding` a qualquer momento; útil também para conferir os dois
   atalhos).
3. Strings novas em EN + PT-BR (tabelas com paridade, como sempre).

## 6. Testes

- PromptBuilder: correção menciona idioma único, exige mesmo idioma, cláusula
  de preservação presente; tradução inalterada (regressão).
- TranslationRequest/Refinement: round-trip Codable? (não é persistido — só
  Equatable/Sendable).
- FakeTranslator ecoa feedback quando refinement presente.
- SettingsStore: default `correctionReplacesDirectly == false`, persistência.
- Manual: correção em PT e EN; refinamento muda a saída; modo direto substitui
  sem popup; erro no modo direto abre popup; ⌥⌘G configurável.

## 7. Fora de escopo (pós-v1.0.0)

Pós-validação automática de símbolos/emoji com regeneração, perfis múltiplos,
histórico de correções, hint de menu dinâmico com o atalho re-gravado.
