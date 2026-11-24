# Native Windows dialogs. They are enabled only when the launcher runs from the
# shortcut; dot-sourcing (the tests) keeps the console path, so no window can
# block an automated run. While the panel is open, a command asks through it,
# so every dialog appears over the panel window.

$TITULO_JANELA = 'Doceterapia'
# Darker shade of the front-end primary color, readable with white text.
$COR_DESTAQUE = '#B85F63'
$ICONE_SISTEMA = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\assets\doceterapia.ico'))
$script:InterfaceGrafica = $false

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

function Show-DialogoComDono {
    # Without an owner a dialog can open behind the panel; TopMost covers the
    # console-only case.
    param(
        [Parameter(Mandatory = $true)]$Janela,
        $Dono
    )
    if ($Dono) { return $Janela.ShowDialog($Dono) }
    $Janela.TopMost = $true
    return $Janela.ShowDialog()
}

function Show-CaixaEntrada {
    # Cancel or closing the window answers blank, the same as Enter on the
    # console, so every caller keeps its default or cancels.
    param(
        [Parameter(Mandatory = $true)][string]$Pergunta,
        [switch]$Oculto,
        $Dono
    )
    if (Test-PainelAtivo) {
        return "$(Request-RespostaDoPainel -Modo 'Texto' -Dados @{ Texto = $Pergunta; Oculto = [bool]$Oculto })"
    }
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
    $janela.Add_Shown({ param($origem) $origem.Controls[1].Focus() })

    try {
        if ((Show-DialogoComDono -Janela $janela -Dono $Dono) -eq [System.Windows.Forms.DialogResult]::OK) {
            return $campo.Text
        }
        return ''
    }
    finally {
        $janela.Dispose()
    }
}

function Get-IconeMensagem {
    param([Parameter(Mandatory = $true)][string]$Tipo)
    switch ($Tipo) {
        'Aviso' { return [System.Windows.Forms.MessageBoxIcon]::Warning }
        'Erro' { return [System.Windows.Forms.MessageBoxIcon]::Error }
        'Pergunta' { return [System.Windows.Forms.MessageBoxIcon]::Question }
    }
    return [System.Windows.Forms.MessageBoxIcon]::Information
}

function Show-Mensagem {
    # Inside the panel the message waits for OK, so a warning shown between two
    # questions is read before the next one.
    param(
        [Parameter(Mandatory = $true)][string]$Texto,
        [ValidateSet('Informacao', 'Aviso', 'Erro')][string]$Tipo = 'Informacao',
        $Dono
    )
    if (Test-PainelAtivo) {
        $null = Request-RespostaDoPainel -Modo 'Mensagem' -Dados @{ Texto = $Texto; Tipo = $Tipo }
        return
    }
    $botoes = [System.Windows.Forms.MessageBoxButtons]::OK
    if ($Dono) {
        $null = [System.Windows.Forms.MessageBox]::Show($Dono, $Texto, $TITULO_JANELA, $botoes, (Get-IconeMensagem $Tipo))
        return
    }
    $null = [System.Windows.Forms.MessageBox]::Show($Texto, $TITULO_JANELA, $botoes, (Get-IconeMensagem $Tipo))
}

function Show-PerguntaSimNao {
    param(
        [Parameter(Mandatory = $true)][string]$Pergunta,
        $Dono
    )
    if (Test-PainelAtivo) {
        return [bool](Request-RespostaDoPainel -Modo 'SimNao' -Dados @{ Texto = $Pergunta })
    }
    $botoes = [System.Windows.Forms.MessageBoxButtons]::YesNo
    if ($Dono) {
        $resposta = [System.Windows.Forms.MessageBox]::Show($Dono, $Pergunta, $TITULO_JANELA, $botoes, (Get-IconeMensagem 'Pergunta'))
    }
    else {
        $resposta = [System.Windows.Forms.MessageBox]::Show($Pergunta, $TITULO_JANELA, $botoes, (Get-IconeMensagem 'Pergunta'))
    }
    return ($resposta -eq [System.Windows.Forms.DialogResult]::Yes)
}

function Show-EscolhaServico {
    # Returns the chosen service, or $null when cancelled.
    param(
        [Parameter(Mandatory = $true)][string[]]$Servicos,
        $Dono
    )
    if (Test-PainelAtivo) {
        $escolhido = Request-RespostaDoPainel -Modo 'Servico' -Dados @{ Servicos = $Servicos }
        if ($escolhido) { return "$escolhido" }
        return $null
    }
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
        if ((Show-DialogoComDono -Janela $janela -Dono $Dono) -eq [System.Windows.Forms.DialogResult]::OK) { return "$($lista.SelectedItem)" }
        return $null
    }
    finally {
        $janela.Dispose()
    }
}

function Select-PastaBackup {
    # Returns the chosen folder, or $null when cancelled.
    param(
        [Parameter(Mandatory = $true)][string]$PastaInicial,
        $Dono
    )
    if (Test-PainelAtivo) {
        $pasta = Request-RespostaDoPainel -Modo 'Pasta' -Dados @{ PastaInicial = $PastaInicial }
        if ($pasta) { return "$pasta" }
        return $null
    }
    $seletor = New-Object System.Windows.Forms.FolderBrowserDialog
    $seletor.Description = 'Escolha a pasta do backup que será restaurado.'
    $seletor.ShowNewFolderButton = $false
    if (Test-Path -LiteralPath $PastaInicial) {
        $seletor.SelectedPath = $PastaInicial
    }
    try {
        $resultado = if ($Dono) { $seletor.ShowDialog($Dono) } else { $seletor.ShowDialog() }
        if ($resultado -eq [System.Windows.Forms.DialogResult]::OK) {
            return $seletor.SelectedPath
        }
        return $null
    }
    finally {
        $seletor.Dispose()
    }
}
