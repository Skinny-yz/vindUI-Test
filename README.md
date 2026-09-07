# Vind UI modular

Parte de `VindUI-notificacoes-fila.lua`, preserva as correções anteriores e separa as integrações. O núcleo passa de aproximadamente 13,6 mil para 9,9 mil linhas. A versão completa continua maior porque inclui todos os módulos e os novos recursos: separar arquivos não elimina por si só código.

## Arquivos

| Arquivo | Uso |
| --- | --- |
| `core.luau` | Janela, abas, componentes, temas, configurações locais, notificações e perfil. |
| `integrations.luau` | Todas as integrações opcionais, com dependências incluídas. |
| `modules/spotify.luau` | Painel e conexão com bridge Spotify. |
| `modules/chat-common.luau` | Estrutura visual compartilhada dos chats. |
| `modules/assistant.luau` | Chat, ferramentas e serviço de assistente. Requer chat-common. |
| `modules/cloud.luau` | Configurações em nuvem, serviço e chat global. Requer chat-common. |
| `modules/feedback.luau` | Envio de feedback por webhook. |
| `full.luau` | Núcleo com todos os módulos registrados; substitui o antigo src.lua. |

Carregar um módulo registra funções. Não abre painéis nem configura serviços automaticamente. Endpoints, credenciais e callbacks continuam sendo passados às APIs existentes. Não há backend novo neste pacote.

## Carregamento

Os exemplos pressupõem os arquivos copiados para `VindUI` no ambiente que executa seu script:

```lua
local UI = loadstring(readfile("VindUI/core.luau"))()
-- Opcional: todas as integrações.
UI:Use(loadstring(readfile("VindUI/integrations.luau"))())
local Window = UI:CreateWindow({
    Title = "Meu painel",
    Size = UDim2.fromOffset(640, 455),
    UserInfo = {Avatar = "player", NameMode = "display"},
})
Window:AddTab("Home")
Window:AddUIPreferences()
```

Ou registre apenas o necessário:

```lua
UI:Use(loadstring(readfile("VindUI/modules/spotify.luau"))())
Window:AddSpotifyPanel({BridgeUrl = CONFIG.SpotifyBridgeUrl})

-- Para assistente ou nuvem, carregar a base compartilhada primeiro:
UI:Use(loadstring(readfile("VindUI/modules/chat-common.luau"))())
UI:Use(loadstring(readfile("VindUI/modules/assistant.luau"))())
-- Agora CreateAIAssistant e AddChatPanel estão disponíveis.
```

Veja `example.luau`: funciona sem serviços externos e permite ativar Spotify/nuvem no CONFIG. `Use` é idempotente: repetir o mesmo nome não duplica a instalação. Dependências ausentes geram uma mensagem indicando o módulo necessário.

Com ModuleScripts, use `require` para obter os mesmos retornos, por exemplo `local UI = require(pasta.core)` e `UI:Use(require(pasta.integrations))`. Para distribuição por URL, use seu carregador HTTP existente. Nenhum endereço novo foi presumido ou publicado.

Para migrar um showcase antigo sem mudar chamadas, use `full.luau`. Para usar `core.luau`, registre primeiro os módulos dos métodos que o showcase chama.

## Perfil no rodapé

O perfil aparece quando não há botões visíveis no dock. Adicionar botões esconde o perfil; ocultar ou destruir todos faz o perfil voltar. Apenas registrar um módulo não esconde o perfil.

```lua
Window:SetUserInfo({Avatar = "player", NameMode = "display"})
Window:SetUserInfo({Avatar = "rbxassetid://123456789", NameMode = "anonymous"})
Window:SetUserInfo({Avatar = 123456789, NameMode = "username"})
Window:SetUserInfo({Enabled = false})
```

- `Avatar`: `"player"`, ID numérico ou string `rbxassetid://...`.
- `NameMode`: `"display"`, `"username"` ou `"anonymous"`.
- Anônimo esconde também o @username do rodapé. É uma preferência visual; não altera o que integrações enviam.
- Nomes longos são truncados. Respostas atrasadas do thumbnail não substituem uma imagem escolhida depois.

## Mobile e recursos novos

A escala se inspira na Redz fornecida: conserva o tamanho lógico e aplica o mesmo fator nos dois eixos, em função da altura disponível. A Vind também limita pela largura e altura para caber na tela e acompanha mudanças do viewport. Não foi copiado o restante da Redz.

```lua
UI:SetMobileScaleReference(450) -- padrão; referência maior = UI menor
UI:SetDensity("compact")      -- ou "comfortable"
Window:AddUIPreferences()       -- aba com densidade, perfil, histórico e restauração
Window:ResetLayout()
Window:ShowNotificationHistory()
local items = UI:GetNotificationHistory()
UI:ClearNotificationHistory()
UI:SetLayoutDebug(true)         -- contornos dos elementos existentes
UI:SetLayoutDebug(false)
```

`Size` conserva a proporção no mobile. `SetScaleRange` continua controlando o desktop; no mobile a referência e o encaixe têm precedência. Com várias janelas, a escala considera o maior tamanho lógico registrado. A densidade é salva quando funções de arquivos estão disponíveis.

O histórico contém as últimas 100 notificações exibidas desta execução, sem callbacks. O diagnóstico é opt-in, não intercepta cliques nem participa do layout; ative novamente depois de criar novos componentes.

## O que foi consolidado

- Compositor, lista de mensagens, rolagem automática e botões de cabeçalho dos chats.
- Base dos campos de texto e atalhos.
- Observação de propriedades e acompanhamento dos popups.
- Barras e acompanhamento dos popups atualizados por mudanças, em vez de um loop por frame.

Animações, arraste e polling dos serviços conservam seus mecanismos. Checks de destruição e suporte do ambiente foram preservados. Nem todo trecho parecido tem o mesmo comportamento; não foi feita remoção indiscriminada.

Edite `core.luau` e `modules/`. Execute `node build.mjs` para reconstruir `integrations.luau` e `full.luau`; não edite os gerados separadamente.

## Validação

Arquivos compilados com Luau. Testes com objetos Roblox simulados cobrem criação de janela, perfil/avatar/anônimo, alternância perfil/dock, controles, preferências, dependências, registro repetido, construção dos painéis e exclusividade do slider. A escala também foi verificada numericamente.

Isso não substitui validação visual no Roblox, toque em aparelho real, thumbnails reais ou conexão com serviços externos. O redesign de dropdown/colorpicker continua pendente conforme solicitado; o posicionamento anterior foi preservado.

Para reproduzir os testes de desenvolvimento: instale Node.js, execute `npm install` nesta pasta e depois `npm test`. Os mocks não executam HTTP, timers nem renderização do Roblox.
