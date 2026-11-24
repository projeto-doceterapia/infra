# The panel window: one form whose content area swaps between screens. It
# runs on the window thread and talks to the commands only through the panel
# state. Handlers keep their state in the controls' Tag and call named
# functions, so they work wherever the event fires.

$OPCOES_MENU = @(
    @{ Rotulo = 'Ligar o sistema'; Comando = 'up' },
    @{ Rotulo = 'Desligar o sistema'; Comando = 'down' },
    @{ Rotulo = 'Configurar (primeira vez)'; Comando = 'configurar-preparar' },
    @{ Rotulo = 'Configurações do WhatsApp'; Comando = 'configuracoes-preparar' },
    @{ Rotulo = 'Ver logs'; Comando = 'ver-logs' },
    @{ Rotulo = 'Fazer backup'; Comando = 'backup' },
    @{ Rotulo = 'Restaurar um backup'; Comando = 'restore' },
    @{ Rotulo = 'Atualizar'; Comando = 'atualizar' },
    @{ Rotulo = 'Verificar o computador'; Comando = 'doctor' },
    @{ Rotulo = 'Criar atalho'; Comando = 'criar-atalho' }
)
$OPCAO_PERIGOSA = @{ Rotulo = 'Apagar e recriar o banco'; Comando = 'resetar-banco' }
$OPCAO_ABRIR = @{ Rotulo = 'Abrir sistema'; Comando = 'abrir' }
$OPCAO_CONFIGURAR = @{ Rotulo = 'Configurar o sistema'; Comando = 'configurar-preparar' }

function Get-TextoEstado {
    param([Parameter(Mandatory = $true)]$Estado)
    if (-not $Estado.Configurado) { return 'Sistema não configurado' }
    if ($Estado.Ligado) { return 'Sistema ligado' }
    return 'Sistema desligado'
}

function Get-CorFarol {
    param($Estado)
    if ($null -eq $Estado) { return [System.Drawing.Color]::FromArgb(150, 150, 150) }
    if ($Estado.Configurado -and $Estado.Ligado) { return [System.Drawing.Color]::FromArgb(30, 150, 70) }
    return [System.Drawing.Color]::FromArgb(200, 40, 40)
}

function New-RotuloTela {
    param(
        [AllowEmptyString()][string]$Texto = '',
        [Parameter(Mandatory = $true)][int]$X,
        [Parameter(Mandatory = $true)][int]$Y,
        [int]$Largura = 520,
        [int]$Altura = 24
    )
    $rotulo = New-Object System.Windows.Forms.Label
    $rotulo.Text = $Texto
    $rotulo.Location = New-Object System.Drawing.Point($X, $Y)
    $rotulo.Size = New-Object System.Drawing.Size($Largura, $Altura)
    return $rotulo
}

function New-PainelTela {
    $painel = New-Object System.Windows.Forms.Panel
    $painel.Dock = 'Fill'
    return $painel
}

function New-JanelaPainel {
    param([Parameter(Mandatory = $true)][hashtable]$Estado)
    $janela = New-JanelaBase -Largura 560 -Altura 600
    $janela.MinimizeBox = $true

    $titulo = New-RotuloTela -Texto 'Doceterapia' -X 20 -Y 12 -Largura 520 -Altura 38
    $titulo.Font = New-Object System.Drawing.Font('Segoe UI', 18, [System.Drawing.FontStyle]::Bold)
    $farol = New-RotuloTela -Texto ([string][char]0x25CF) -X 20 -Y 52 -Largura 26 -Altura 28
    $farol.Font = New-Object System.Drawing.Font('Segoe UI', 14)
    $farol.ForeColor = Get-CorFarol -Estado $null
    $situacao = New-RotuloTela -Texto 'Verificando o sistema...' -X 46 -Y 56 -Largura 480
    $area = New-Object System.Windows.Forms.Panel
    $area.Location = New-Object System.Drawing.Point(0, 92)
    $area.Size = New-Object System.Drawing.Size(560, 508)
    $janela.Controls.AddRange(@($titulo, $farol, $situacao, $area))

    $relogio = New-Object System.Windows.Forms.Timer
    $relogio.Interval = 120
    $relogio.Tag = $janela
    $relogio.Add_Tick({ param($origem) Invoke-CicloDaJanela -Janela $origem.Tag })

    $janela.Tag = @{
        Estado    = $Estado
        Farol     = $farol
        Situacao  = $situacao
        Area      = $area
        Relogio   = $relogio
        Principal = $null
        Progresso = $null
        Ocupado       = $false
        ParaDescartar = @()
    }
    $janela.Add_Shown({
            param($origem)
            Show-TelaMenu -Janela $origem
            $origem.Tag.Relogio.Start()
        })
    $janela.Add_FormClosing({ param($origem, $evento) Confirm-FechamentoDaJanela -Janela $origem -Evento $evento })
    return $janela
}

function Show-Tela {
    param(
        [Parameter(Mandatory = $true)]$Janela,
        [Parameter(Mandatory = $true)]$Conteudo
    )
    # The screen being replaced may hold the button whose click is still running,
    # so it is disposed only on the next swap.
    $area = $Janela.Tag.Area
    foreach ($antigo in @($Janela.Tag.ParaDescartar)) { if ($antigo) { $antigo.Dispose() } }
    $Janela.Tag.ParaDescartar = @($area.Controls)
    $area.Controls.Clear()
    $area.Controls.Add($Conteudo)
    $Janela.Tag.Progresso = $null
    $Janela.Tag.Principal = $null
}

function Submit-PedidoDaJanela {
    # The loading screen shows at once, so a slow check never looks frozen.
    param(
        [Parameter(Mandatory = $true)]$Janela,
        [Parameter(Mandatory = $true)][string]$Acao,
        $Dados,
        [string]$Carregando = 'Carregando...'
    )
    Show-Tela -Janela $Janela -Conteudo (New-TelaCarregando -Texto $Carregando)
    $Janela.Tag.Estado.Pedidos.Enqueue(@{ Acao = $Acao; Dados = $Dados })
}

function New-TelaCarregando {
    param([Parameter(Mandatory = $true)][string]$Texto)
    $painel = New-PainelTela
    $rotulo = New-RotuloTela -Texto $Texto -X 20 -Y 150 -Largura 520 -Altura 30
    $rotulo.TextAlign = 'MiddleCenter'
    $rotulo.Font = New-Object System.Drawing.Font('Segoe UI', 12)
    $barra = New-Object System.Windows.Forms.ProgressBar
    $barra.Location = New-Object System.Drawing.Point(120, 190)
    $barra.Size = New-Object System.Drawing.Size(320, 16)
    $barra.Style = 'Marquee'
    $barra.MarqueeAnimationSpeed = 30
    $painel.Controls.AddRange(@($rotulo, $barra))
    return $painel
}

function New-BotaoMenu {
    param(
        [Parameter(Mandatory = $true)][hashtable]$Opcao,
        [Parameter(Mandatory = $true)][int]$X,
        [Parameter(Mandatory = $true)][int]$Y,
        [int]$Largura = 252
    )
    $botao = New-Botao -Texto $Opcao.Rotulo -X $X -Y $Y -Largura $Largura
    $botao.Tag = $Opcao
    $botao.Add_Click({ param($origem) Invoke-OpcaoDoMenu -Janela $origem.FindForm() -Opcao $origem.Tag })
    return $botao
}

function Show-TelaMenu {
    # The state is checked in the background; the primary button waits for it.
    param([Parameter(Mandatory = $true)]$Janela)
    $painel = New-PainelTela
    $principal = New-BotaoMenu -Opcao $OPCAO_ABRIR -X 20 -Y 4 -Largura 520
    $principal.Text = 'Verificando...'
    $principal.Enabled = $false
    $principal.Height = 64
    $principal.Font = New-Object System.Drawing.Font('Segoe UI', 14, [System.Drawing.FontStyle]::Bold)
    $principal.FlatStyle = 'Flat'
    $principal.FlatAppearance.BorderSize = 0
    $principal.BackColor = [System.Drawing.ColorTranslator]::FromHtml($COR_DESTAQUE)
    $principal.ForeColor = [System.Drawing.Color]::White
    $painel.Controls.Add($principal)

    $y = 84
    for ($indice = 0; $indice -lt $OPCOES_MENU.Count; $indice++) {
        $x = if ($indice % 2 -eq 0) { 20 } else { 288 }
        $painel.Controls.Add((New-BotaoMenu -Opcao $OPCOES_MENU[$indice] -X $x -Y $y))
        if ($indice % 2 -eq 1) { $y += 40 }
    }
    $perigosa = New-BotaoMenu -Opcao $OPCAO_PERIGOSA -X 20 -Y ($y + 12)
    $perigosa.ForeColor = [System.Drawing.Color]::FromArgb(180, 30, 30)
    $fechar = New-Botao -Texto 'Fechar' -X 440 -Y ($y + 12)
    $fechar.Add_Click({ param($origem) $origem.FindForm().Close() })
    $painel.Controls.AddRange(@($perigosa, $fechar))

    Show-Tela -Janela $Janela -Conteudo $painel
    $Janela.Tag.Principal = $principal
    $Janela.Tag.Farol.ForeColor = Get-CorFarol -Estado $null
    $Janela.Tag.Situacao.Text = 'Verificando o sistema...'
    $Janela.Tag.Estado.Pedidos.Enqueue(@{ Acao = 'estado' })
}

function Set-EstadoNaJanela {
    param(
        [Parameter(Mandatory = $true)]$Janela,
        [Parameter(Mandatory = $true)]$Estado
    )
    $Janela.Tag.Farol.ForeColor = Get-CorFarol -Estado $Estado
    $Janela.Tag.Situacao.Text = Get-TextoEstado -Estado $Estado
    $principal = $Janela.Tag.Principal
    if ($principal -and -not $principal.IsDisposed) {
        $opcao = if ($Estado.Configurado) { $OPCAO_ABRIR } else { $OPCAO_CONFIGURAR }
        $principal.Tag = $opcao
        $principal.Text = $opcao.Rotulo
        $principal.Enabled = $true
    }
}

function Invoke-OpcaoDoMenu {
    param(
        [Parameter(Mandatory = $true)]$Janela,
        [Parameter(Mandatory = $true)][hashtable]$Opcao
    )
    Submit-PedidoDaJanela -Janela $Janela -Acao $Opcao.Comando -Carregando "$($Opcao.Rotulo)..."
}

function Show-TelaProgresso {
    param(
        [Parameter(Mandatory = $true)]$Janela,
        [Parameter(Mandatory = $true)][string]$Titulo
    )
    $painel = New-PainelTela
    $etapa = New-RotuloTela -Texto "$Titulo..." -X 20 -Y 4 -Largura 520 -Altura 48
    $etapa.Font = New-Object System.Drawing.Font('Segoe UI', 11, [System.Drawing.FontStyle]::Bold)
    $barra = New-Object System.Windows.Forms.ProgressBar
    $barra.Location = New-Object System.Drawing.Point(20, 56)
    $barra.Size = New-Object System.Drawing.Size(520, 18)
    $barra.Style = 'Marquee'
    $barra.MarqueeAnimationSpeed = 30
    $registro = New-Object System.Windows.Forms.TextBox
    $registro.Location = New-Object System.Drawing.Point(20, 84)
    $registro.Size = New-Object System.Drawing.Size(520, 362)
    $registro.Multiline = $true
    $registro.ReadOnly = $true
    $registro.ScrollBars = 'Vertical'
    $registro.Font = New-Object System.Drawing.Font('Consolas', 9)
    $acao = New-Botao -Texto 'Abrir sistema' -X 250 -Y 458 -Largura 150
    $acao.Visible = $false
    $acao.Add_Click({ param($origem) Submit-PedidoDaJanela -Janela $origem.FindForm() -Acao 'abrir' -Carregando 'Abrindo o sistema...' })
    $voltar = New-Botao -Texto 'Aguarde...' -X 410 -Y 458 -Largura 130
    $voltar.Enabled = $false
    $voltar.Add_Click({ param($origem) Show-TelaMenu -Janela $origem.FindForm() })
    $painel.Controls.AddRange(@($etapa, $barra, $registro, $acao, $voltar))

    Show-Tela -Janela $Janela -Conteudo $painel
    $Janela.Tag.Progresso = @{ Etapa = $etapa; Barra = $barra; Registro = $registro; Acao = $acao; Voltar = $voltar }
}

function Add-LinhasTelaProgresso {
    param(
        [Parameter(Mandatory = $true)]$Janela,
        [Parameter(Mandatory = $true)][string[]]$Linhas
    )
    if (-not $Janela.Tag.Progresso) { return }
    $Janela.Tag.Progresso.Registro.AppendText(($Linhas -join "`r`n") + "`r`n")
}

function Complete-TelaProgresso {
    param(
        [Parameter(Mandatory = $true)]$Janela,
        [Parameter(Mandatory = $true)][bool]$Sucesso,
        [Parameter(Mandatory = $true)][string]$Mensagem,
        [string]$AcaoFinal
    )
    $progresso = $Janela.Tag.Progresso
    if (-not $progresso) { return }
    $progresso.Barra.Style = 'Blocks'
    $progresso.Barra.Value = 100
    $progresso.Etapa.Text = $Mensagem
    $progresso.Etapa.ForeColor = if ($Sucesso) { [System.Drawing.Color]::FromArgb(30, 120, 60) } else { [System.Drawing.Color]::FromArgb(180, 30, 30) }
    $progresso.Voltar.Text = 'Voltar ao menu'
    $progresso.Voltar.Enabled = $true
    $Janela.AcceptButton = $progresso.Voltar
    if ($AcaoFinal) {
        $progresso.Acao.Text = $AcaoFinal
        $progresso.Acao.Visible = $true
        $Janela.AcceptButton = $progresso.Acao
    }
}

function Invoke-PerguntaNaJanela {
    param(
        [Parameter(Mandatory = $true)]$Janela,
        [Parameter(Mandatory = $true)][hashtable]$Pergunta
    )
    $dados = $Pergunta.Dados
    switch ($Pergunta.Modo) {
        'Mensagem' { Show-Mensagem -Texto $dados.Texto -Tipo $dados.Tipo -Dono $Janela; return $true }
        'SimNao' { return (Show-PerguntaSimNao -Pergunta $dados.Texto -Dono $Janela) }
        'Texto' { return (Show-CaixaEntrada -Pergunta $dados.Texto -Oculto:$dados.Oculto -Dono $Janela) }
        'Servico' { return (Show-EscolhaServico -Servicos $dados.Servicos -Dono $Janela) }
        'Pasta' { return (Select-PastaBackup -PastaInicial $dados.PastaInicial -Dono $Janela) }
    }
    return $null
}

function Invoke-EventoNaJanela {
    param(
        [Parameter(Mandatory = $true)]$Janela,
        [Parameter(Mandatory = $true)][hashtable]$Evento
    )
    switch ($Evento.Tipo) {
        'Estado' { Set-EstadoNaJanela -Janela $Janela -Estado $Evento.Estado }
        'Menu' { Show-TelaMenu -Janela $Janela }
        'Inicio' { Show-TelaProgresso -Janela $Janela -Titulo $Evento.Titulo }
        'Fim' { Complete-TelaProgresso -Janela $Janela -Sucesso $Evento.Sucesso -Mensagem $Evento.Mensagem -AcaoFinal $Evento.AcaoFinal }
        'Assistente' { Show-Tela -Janela $Janela -Conteudo (New-TelaAssistente -Linhas $Evento.Linhas -PedirDona $Evento.PedirDona -PedirDemo $Evento.PedirDemo) }
        'Configuracoes' { Show-Tela -Janela $Janela -Conteudo (New-TelaConfiguracoes -Linhas $Evento.Linhas) }
        'Pergunta' { $Janela.Tag.Estado.Respostas[$Evento.Id] = Invoke-PerguntaNaJanela -Janela $Janela -Pergunta $Evento }
        'Carregando' { Show-Tela -Janela $Janela -Conteudo (New-TelaCarregando -Texto $Evento.Texto) }
        'Ocultar' { $Janela.Hide() }
        'Mostrar' { Show-JanelaEmFoco -Janela $Janela }
    }
}

function Show-JanelaEmFoco {
    # A brief TopMost brings the window over the browser even when Windows
    # would only flash its taskbar button.
    param([Parameter(Mandatory = $true)]$Janela)
    if (-not $Janela.Visible) { $Janela.Show() }
    if ($Janela.WindowState -eq [System.Windows.Forms.FormWindowState]::Minimized) {
        $Janela.WindowState = [System.Windows.Forms.FormWindowState]::Normal
    }
    $Janela.TopMost = $true
    $Janela.Activate()
    $Janela.TopMost = $false
}

function Invoke-CicloDaJanela {
    # A question opens a modal dialog, whose message loop keeps the timer
    # ticking; the busy flag stops a second tick from handling events meanwhile.
    param([Parameter(Mandatory = $true)]$Janela)
    $dados = $Janela.Tag
    if ($dados.Ocupado) { return }
    $dados.Ocupado = $true
    try {
        $linhas = New-Object 'System.Collections.Generic.List[string]'
        $linha = $null
        while ($dados.Estado.Fila.TryDequeue([ref]$linha)) { $linhas.Add($linha) }
        if ($linhas.Count -gt 0) { Add-LinhasTelaProgresso -Janela $Janela -Linhas $linhas.ToArray() }
        if ($dados.Progresso -and $dados.Estado.EmOperacao) { $dados.Progresso.Etapa.Text = $dados.Estado.Etapa }
        if ($dados.Estado.SinalFoco -and $dados.Estado.SinalFoco.WaitOne(0)) { Show-JanelaEmFoco -Janela $Janela }
        $evento = $null
        while ($dados.Estado.Eventos.TryDequeue([ref]$evento)) {
            Invoke-EventoNaJanela -Janela $Janela -Evento $evento
        }
    }
    finally {
        $dados.Ocupado = $false
    }
}

function Confirm-FechamentoDaJanela {
    param(
        [Parameter(Mandatory = $true)]$Janela,
        [Parameter(Mandatory = $true)]$Evento
    )
    $dados = $Janela.Tag
    if ($dados.Estado.EmOperacao) {
        $Evento.Cancel = $true
        Show-Mensagem -Texto 'Aguarde a operação terminar para fechar o painel.' -Tipo Aviso -Dono $Janela
        return
    }
    $dados.Relogio.Stop()
    $dados.Estado.Pedidos.Enqueue(@{ Acao = 'sair' })
}
