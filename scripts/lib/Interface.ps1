# Native Windows dialogs. They are enabled only when the launcher runs from the
# shortcut; dot-sourcing (the tests) keeps the console path, so no window can
# block an automated run.

$TITULO_JANELA = 'Doceterapia'
$ICONE_SISTEMA = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\assets\doceterapia.ico'))
$script:InterfaceGrafica = $false

$OPCOES_MENU = @(
    @{ Rotulo = 'Verificar o computador'; Comando = 'doctor' },
    @{ Rotulo = 'Configurar (primeira vez)'; Comando = 'configurar' },
    @{ Rotulo = 'Configurações do WhatsApp'; Comando = 'configuracoes' },
    @{ Rotulo = 'Ligar o sistema'; Comando = 'up' },
    @{ Rotulo = 'Abrir o sistema'; Comando = 'abrir' },
    @{ Rotulo = 'Desligar o sistema'; Comando = 'down' },
    @{ Rotulo = 'Fazer backup'; Comando = 'backup' },
    @{ Rotulo = 'Restaurar um backup'; Comando = 'restore' },
    @{ Rotulo = 'Atualizar'; Comando = 'atualizar' },
    @{ Rotulo = 'Apagar e recriar o banco'; Comando = 'resetar-banco' }
)

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

function Show-MenuPrincipal {
    # Returns the chosen option (Rotulo and Comando), or $null when closed.
    $alturaBotao = 40
    $janela = New-JanelaBase -Largura 320 -Altura (60 + $OPCOES_MENU.Count * $alturaBotao + 50)

    $titulo = New-Object System.Windows.Forms.Label
    $titulo.Text = 'O que você quer fazer?'
    $titulo.Location = New-Object System.Drawing.Point(16, 16)
    $titulo.Size = New-Object System.Drawing.Size(288, 28)
    $janela.Controls.Add($titulo)

    $escolha = @{ Opcao = $null }
    $y = 52
    foreach ($opcao in $OPCOES_MENU) {
        $botao = New-Botao -Texto $opcao.Rotulo -X 16 -Y $y -Largura 288
        $botao.Tag = $opcao
        $botao.Add_Click({
                param($origem)
                $escolha.Opcao = $origem.Tag
                $origem.FindForm().Close()
            })
        $janela.Controls.Add($botao)
        $y += $alturaBotao
    }
    $fechar = New-Botao -Texto 'Fechar' -X 204 -Y ($y + 8) -Resultado Cancel
    $janela.CancelButton = $fechar
    $janela.Controls.Add($fechar)

    try {
        $null = $janela.ShowDialog()
        return $escolha.Opcao
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
