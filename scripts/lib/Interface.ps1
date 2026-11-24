# Native Windows dialogs. They are enabled only when the launcher runs from the
# shortcut; dot-sourcing (the tests) keeps the console path, so no window can
# block an automated run.

$TITULO_JANELA = 'Doceterapia'
# Darker shade of the front-end primary color, readable with white text.
$COR_DESTAQUE = '#B85F63'
$ICONE_SISTEMA = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\assets\doceterapia.ico'))
$script:InterfaceGrafica = $false

# Secondary actions, two per row. The primary action is chosen by the state.
$OPCOES_MENU = @(
    @{ Rotulo = 'Ligar o sistema'; Comando = 'up' },
    @{ Rotulo = 'Desligar o sistema'; Comando = 'down' },
    @{ Rotulo = 'Configurar (primeira vez)'; Comando = 'configurar' },
    @{ Rotulo = 'Configurações do WhatsApp'; Comando = 'configuracoes' },
    @{ Rotulo = 'Ver logs'; Comando = 'ver-logs' },
    @{ Rotulo = 'Fazer backup'; Comando = 'backup' },
    @{ Rotulo = 'Restaurar um backup'; Comando = 'restore' },
    @{ Rotulo = 'Atualizar'; Comando = 'atualizar' },
    @{ Rotulo = 'Verificar o computador'; Comando = 'doctor' },
    @{ Rotulo = 'Criar atalhos'; Comando = 'criar-atalhos' }
)
$OPCAO_PERIGOSA = @{ Rotulo = 'Apagar e recriar o banco'; Comando = 'resetar-banco' }
$OPCAO_ABRIR = @{ Rotulo = 'Abrir sistema'; Comando = 'abrir' }
$OPCAO_CONFIGURAR = @{ Rotulo = 'Configurar o sistema'; Comando = 'configurar' }

function Enable-InterfaceGrafica {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    [System.Windows.Forms.Application]::EnableVisualStyles()
    $script:InterfaceGrafica = $true
}

function Test-InterfaceGrafica {
    return [bool]$script:InterfaceGrafica
}

function Get-IconeJanela {
    if (Test-Path -LiteralPath $ICONE_SISTEMA) {
        return New-Object System.Drawing.Icon($ICONE_SISTEMA)
    }
    return $null
}

function New-JanelaBase {
    param(
        [Parameter(Mandatory = $true)][int]$Largura,
        [Parameter(Mandatory = $true)][int]$Altura
    )
    $janela = New-Object System.Windows.Forms.Form
    $janela.Text = $TITULO_JANELA
    $janela.ClientSize = New-Object System.Drawing.Size($Largura, $Altura)
    $janela.StartPosition = 'CenterScreen'
    $janela.FormBorderStyle = 'FixedDialog'
    $janela.MaximizeBox = $false
    $janela.MinimizeBox = $false
    $janela.TopMost = $true
    $janela.Font = New-Object System.Drawing.Font('Segoe UI', 10)
    $icone = Get-IconeJanela
    if ($icone) { $janela.Icon = $icone }
    return $janela
}

function New-Botao {
    param(
        [Parameter(Mandatory = $true)][string]$Texto,
        [Parameter(Mandatory = $true)][int]$X,
        [Parameter(Mandatory = $true)][int]$Y,
        [int]$Largura = 100,
        [System.Windows.Forms.DialogResult]$Resultado = 'None'
    )
    $botao = New-Object System.Windows.Forms.Button
    $botao.Text = $Texto
    $botao.Location = New-Object System.Drawing.Point($X, $Y)
    $botao.Size = New-Object System.Drawing.Size($Largura, 32)
    $botao.DialogResult = $Resultado
    return $botao
}

function Show-CaixaEntrada {
    # Cancel or closing the window answers blank, the same as Enter on the
    # console, so every caller keeps its default or cancels.
    param(
        [Parameter(Mandatory = $true)][string]$Pergunta,
        [switch]$Oculto
    )
    $janela = New-JanelaBase -Largura 420 -Altura 150

    $rotulo = New-Object System.Windows.Forms.Label
    $rotulo.Text = $Pergunta
    $rotulo.Location = New-Object System.Drawing.Point(12, 12)
    $rotulo.Size = New-Object System.Drawing.Size(396, 44)

    $campo = New-Object System.Windows.Forms.TextBox
    $campo.Location = New-Object System.Drawing.Point(12, 60)
    $campo.Size = New-Object System.Drawing.Size(396, 26)
    $campo.UseSystemPasswordChar = [bool]$Oculto

    $ok = New-Botao -Texto 'OK' -X 202 -Y 104 -Resultado OK
    $cancelar = New-Botao -Texto 'Cancelar' -X 308 -Y 104 -Resultado Cancel
    $janela.AcceptButton = $ok
    $janela.CancelButton = $cancelar
    $janela.Controls.AddRange(@($rotulo, $campo, $ok, $cancelar))
    $janela.Add_Shown({ $campo.Focus() })

    try {
        if ($janela.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            return $campo.Text
        }
        return ''
    }
    finally {
        $janela.Dispose()
    }
}

function Show-Mensagem {
    param(
        [Parameter(Mandatory = $true)][string]$Texto,
        [ValidateSet('Informacao', 'Aviso', 'Erro')][string]$Tipo = 'Informacao'
    )
    $icone = switch ($Tipo) {
        'Aviso' { [System.Windows.Forms.MessageBoxIcon]::Warning }
        'Erro' { [System.Windows.Forms.MessageBoxIcon]::Error }
        default { [System.Windows.Forms.MessageBoxIcon]::Information }
    }
    $null = [System.Windows.Forms.MessageBox]::Show($Texto, $TITULO_JANELA, [System.Windows.Forms.MessageBoxButtons]::OK, $icone)
}

function Show-PerguntaSimNao {
    param([Parameter(Mandatory = $true)][string]$Pergunta)
    $resposta = [System.Windows.Forms.MessageBox]::Show($Pergunta, $TITULO_JANELA, [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
    return ($resposta -eq [System.Windows.Forms.DialogResult]::Yes)
}

function Get-TextoEstado {
    param([Parameter(Mandatory = $true)]$Estado)
    if (-not $Estado.Configurado) { return 'O sistema ainda não foi configurado.' }
    if ($Estado.Ligado) { return "Sistema ligado em $($Estado.Url)" }
    return 'Sistema desligado.'
}

function Show-MenuPrincipal {
    # Returns the chosen option (Rotulo and Comando), or $null when closed.
    param([Parameter(Mandatory = $true)]$Estado)
    $janela = New-JanelaBase -Largura 520 -Altura 520
    $janela.TopMost = $false
    $escolha = @{ Opcao = $null }
    $escolher = {
        param($origem)
        $escolha.Opcao = $origem.Tag
        $origem.FindForm().Close()
    }

    $titulo = New-Object System.Windows.Forms.Label
    $titulo.Text = 'Doceterapia'
    $titulo.Font = New-Object System.Drawing.Font('Segoe UI', 18, [System.Drawing.FontStyle]::Bold)
    $titulo.Location = New-Object System.Drawing.Point(20, 14)
    $titulo.Size = New-Object System.Drawing.Size(480, 38)
    $situacao = New-Object System.Windows.Forms.Label
    $situacao.Text = Get-TextoEstado -Estado $Estado
    $situacao.Location = New-Object System.Drawing.Point(22, 54)
    $situacao.Size = New-Object System.Drawing.Size(478, 24)
    $situacao.ForeColor = if ($Estado.Ligado) { [System.Drawing.Color]::FromArgb(30, 120, 60) } else { [System.Drawing.Color]::FromArgb(110, 110, 110) }
    $janela.Controls.AddRange(@($titulo, $situacao))

    $opcaoPrincipal = if ($Estado.Configurado) { $OPCAO_ABRIR } else { $OPCAO_CONFIGURAR }
    $principal = New-Botao -Texto $opcaoPrincipal.Rotulo -X 20 -Y 88 -Largura 480
    $principal.Height = 64
    $principal.Font = New-Object System.Drawing.Font('Segoe UI', 14, [System.Drawing.FontStyle]::Bold)
    $principal.FlatStyle = 'Flat'
    $principal.FlatAppearance.BorderSize = 0
    $principal.BackColor = [System.Drawing.ColorTranslator]::FromHtml($COR_DESTAQUE)
    $principal.ForeColor = [System.Drawing.Color]::White
    $principal.Tag = $opcaoPrincipal
    $principal.Add_Click($escolher)
    $janela.Controls.Add($principal)
    $janela.AcceptButton = $principal

    $y = 168
    for ($indice = 0; $indice -lt $OPCOES_MENU.Count; $indice++) {
        $x = if ($indice % 2 -eq 0) { 20 } else { 264 }
        $botao = New-Botao -Texto $OPCOES_MENU[$indice].Rotulo -X $x -Y $y -Largura 236
        $botao.Tag = $OPCOES_MENU[$indice]
        $botao.Add_Click($escolher)
        $janela.Controls.Add($botao)
        if ($indice % 2 -eq 1) { $y += 40 }
    }
    $perigosa = New-Botao -Texto $OPCAO_PERIGOSA.Rotulo -X 20 -Y ($y + 8) -Largura 236
    $perigosa.ForeColor = [System.Drawing.Color]::FromArgb(180, 30, 30)
    $perigosa.Tag = $OPCAO_PERIGOSA
    $perigosa.Add_Click($escolher)
    $fechar = New-Botao -Texto 'Fechar' -X 400 -Y ($y + 8) -Resultado Cancel
    $janela.CancelButton = $fechar
    $janela.Controls.AddRange(@($perigosa, $fechar))
    $janela.ClientSize = New-Object System.Drawing.Size(520, ($y + 60))

    try {
        $null = $janela.ShowDialog()
        return $escolha.Opcao
    }
    finally {
        $janela.Dispose()
    }
}

function Show-EscolhaServico {
    # Returns the chosen service, or $null when cancelled.
    param([Parameter(Mandatory = $true)][string[]]$Servicos)
    $janela = New-JanelaBase -Largura 360 -Altura 140
    $rotulo = New-Object System.Windows.Forms.Label
    $rotulo.Text = 'Ver os registros de qual serviço?'
    $rotulo.Location = New-Object System.Drawing.Point(12, 12)
    $rotulo.Size = New-Object System.Drawing.Size(336, 24)
    $lista = New-Object System.Windows.Forms.ComboBox
    $lista.DropDownStyle = 'DropDownList'
    $lista.Location = New-Object System.Drawing.Point(12, 42)
    $lista.Size = New-Object System.Drawing.Size(336, 28)
    $lista.Items.AddRange([object[]]$Servicos)
    $lista.SelectedIndex = [Math]::Max(0, [Array]::IndexOf($Servicos, 'back-end'))
    $ok = New-Botao -Texto 'Abrir' -X 142 -Y 94 -Resultado OK
    $cancelar = New-Botao -Texto 'Cancelar' -X 248 -Y 94 -Resultado Cancel
    $janela.AcceptButton = $ok
    $janela.CancelButton = $cancelar
    $janela.Controls.AddRange(@($rotulo, $lista, $ok, $cancelar))
    try {
        if ($janela.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { return "$($lista.SelectedItem)" }
        return $null
    }
    finally {
        $janela.Dispose()
    }
}

function Select-PastaBackup {
    param([Parameter(Mandatory = $true)][hashtable]$Ctx)
    $seletor = New-Object System.Windows.Forms.FolderBrowserDialog
    $seletor.Description = 'Escolha a pasta do backup que será restaurado.'
    $seletor.ShowNewFolderButton = $false
    if (Test-Path -LiteralPath $Ctx.PastaBackups) {
        $seletor.SelectedPath = $Ctx.PastaBackups
    }
    try {
        if ($seletor.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            return $seletor.SelectedPath
        }
        return $null
    }
    finally {
        $seletor.Dispose()
    }
}
