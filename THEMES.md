# Temas completos

Os presets Dark, Light, Midnight e Forest agora incluem as cores de controles, bordas e estados. As mudancas sao aplicadas aos elementos abertos e aos criados depois, sem mudar os valores dos controles.

```lua
VindUI:SetTheme("Midnight")
```

No exemplo, altere CONFIG.Theme. O tema e aplicado antes da intro.

Cobertura: janela, navegacao, cards, toggles ligados/desligados, knobs, sliders, campos, placeholders, menus, bordas, dialogos, notificacoes, console, changelog, intro e superficies/textos dos paineis de integracao. As cores da marca Spotify, medalhas, avatares e os valores escolhidos no color picker continuam representando seus conteudos. Cores explicitamente fornecidas em opcoes como Intro.TextColor e GradientCard.ColorA/ColorB sao preservadas.

Cada preset redefine tambem ToggleOn, ToggleOff, ToggleKnob, ToggleKnobOn, SliderFill, SliderKnob, Card, Border, OnAccent, Info, Success, Warning e Danger. O Light usa cores de status mais escuras para contraste.

```lua
VindUI:SetTheme({Accent = Color3.fromRGB(150, 120, 255)})
-- Uma cor base atualiza as cores derivadas dos controles.
VindUI:SetTheme({ToggleOn = Color3.fromRGB(90, 180, 255)})
-- Uma cor especifica pode ser personalizada separadamente.
```

Ao fornecer cores base (Background, Surface, Text, TextDim, Accent), a paleta derivada e recalculada. Overrides passados na mesma tabela prevalecem. Escolher um preset restaura a paleta inteira.

Instalacao: substitua core.luau, full.luau, integrations.luau e example.luau. Atualize tambem modules, package.json, build.mjs e os testes para manter os fontes sincronizados. Mescle as pastas, mantendo seus outros arquivos.

Validacao: npm run test:ui passa para compilacao, temas em core/full, notificacoes existentes, construcao de paineis, estados de toggles, customizacao, intro, callbacks e escala. O antigo smoke test tem uma falha preexistente, reproduzida na versao original. Nao houve validacao visual desta revisao dentro do Roblox.

As alteracoes foram preparadas localmente e nao publicadas no GitHub.
