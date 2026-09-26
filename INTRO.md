# Intro opcional

A biblioteca nao cria intro automaticamente. No exemplo, CONFIG.Intro.Enabled = true ativa a demonstracao; troque para false para desativar. Nenhum dos componentes removidos de New Elements foi restaurado.

## Uso automatico

Depois de carregar VindUI e antes de CreateWindow:

```lua
VindUI:ShowIntro({
    Enabled = true,
    Title = "Meu Hub",
    Eyebrow = "BEM-VINDO",
    Subtitle = "Sua experiencia comeca aqui.",
    Logo = "Lucide:sparkles",
    Accent = Color3.fromRGB(151, 167, 255),
    Duration = 2.6,
    Skippable = true,
    SkipText = "Pular",
    Status = "Preparando sua interface",
    CompleteText = "Pronto",
}):Wait()

local Window = VindUI:CreateWindow({Title = "Meu Hub"})
```

A barra automatica representa o tempo da intro, nao progresso real de carregamento. Duration configura esse tempo; a animacao final acrescenta aproximadamente 0,45 segundo. Para representar carregamento real, use o modo manual.

## Progresso manual

```lua
local intro = VindUI:ShowIntro({
    Title = "Meu Hub",
    AutoClose = false,
    Skippable = false,
})

intro:SetProgress(0.2, "Carregando recursos")
-- Seu codigo de carregamento aqui.
intro:SetProgress(0.7, "Preparando configuracoes")
-- Restante do carregamento aqui.
intro:Complete("Tudo pronto"):Wait()
```

No modo manual, chame Complete() ou Destroy() em todos os caminhos de encerramento, inclusive falhas de carregamento. Pular fecha somente a intro; nao cancela operacoes do seu script.

## Personalizacao

| Opcao | Padrao / uso |
| --- | --- |
| Enabled | true quando ShowIntro e chamado; false nao cria objetos |
| Title / Subtitle / Eyebrow | Titulo, descricao e texto pequeno acima do titulo |
| Logo ou Icon | Nome de icone da biblioteca ou imagem aceita por ResolveIcon |
| Accent | Cor de destaque; usa a cor do tema por padrao |
| BackgroundColor | Fundo do cartao; Color3 |
| TextColor / SubtitleColor | Cores dos textos; Color3 |
| LogoColor | Cor da imagem; use Color3.new(1,1,1) para preservar um logo colorido |
| Font | Font usado pelos textos; usa a fonte do tema por padrao |
| Width / Height | 360 / 174; limites 300–760 e 174–440 |
| Scale | 1; limites 0,25–2; ajustado para caber na tela |
| CornerRadius | CornerRadius do tema; de 0 a 64 |
| Transparency | 0,22; transparencia do cartao, de 0 a 1 |
| Dim | 0,12; escurecimento do fundo, de 0 a 1 |
| TitleSize | 19; de 14 a 32 |
| Duration | 2,6 segundos; de 0,2 a 60 |
| AutoClose | true; false exige Complete ou Destroy |
| ShowProgress | true; false esconde barra e porcentagem |
| Status / CompleteText | Texto inicial / texto final |
| Skippable / SkipText | false / Skip |
| ReducedMotion | false; true elimina transicoes de entrada e saida |
| BlockInput | true; ativa a camada de fundo para interceptar cliques da UI |
| OnComplete | function(reason): completed ou skipped; protegido pelo handler de callbacks |

## Controle e ciclo de vida

- SetProgress(valor, textoOpcional): valor de 0 a 1; atualiza barra e porcentagem.
- SetStatus(texto): atualiza a mensagem inferior.
- GetProgress(): retorna o progresso atual.
- Complete(textoOpcional): conclui e fecha com animacao.
- Wait(): aguarda o encerramento; use em um contexto que permita espera.
- IsFinished(): informa se terminou.
- Destroy(): fecha imediatamente, sem executar OnComplete.

Uma nova intro substitui a anterior. Descarregar a biblioteca ou destruir a intro limpa suas conexoes e animacoes. A intro tem escala independente e acompanha mudancas no tamanho da tela.

## Arquivos e validacao

Substitua core.luau, full.luau e example.luau. Mescle tests com os testes existentes e atualize package.json. O exemplo continua carregando a URL do GitHub: publique o novo full.luau no repositorio para executar esta versao por essa URL.

Compilacao Luau, testes de intro (core e full), callbacks e escala passaram. O teste geral smoke continua tendo uma falha preexistente na versao original. A aparencia ainda nao foi validada dentro do Roblox real.

Os modulos e os bundles de integracoes estao sincronizados nesta versao.

Visual revisado: cartao compacto com logo a esquerda, tipografia e cores herdadas do tema, barra fina e fundo discretamente escurecido. O degradê fica exclusivamente na camada decorativa, sem tingir textos e logo.

## Acabamento em vidro / blur

A intro usa o mesmo acrylic das janelas da UI. UseBlur = true (padrao) habilita o efeito, respeitando VindUI.Config.Blur. UseBlur = false desativa o blur da intro. Transparency = 0.22 define a transparencia do cartao. Shimmer = true (padrao) ativa o brilho discreto na barra; false o desativa. ReducedMotion tambem desativa esse brilho animado.

Sombra em duas camadas, reflexo superior fino e borda suave mantem as cores do tema e o contraste do texto. O efeito de blur e removido no fechamento e no unload, sem desativar o acrylic de outras janelas. O efeito visual depende do suporte grafico do Roblox ao acrylic da biblioteca.

Testes simulados adicionais confirmaram a ativacao e limpeza do blur e o modo UseBlur = false; a renderizacao real desta revisao ainda precisa ser conferida no Roblox.
