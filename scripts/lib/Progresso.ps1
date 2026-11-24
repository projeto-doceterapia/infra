# Progress window for long operations. It runs on its own STA thread, so it
# keeps repainting while the command blocks on Docker in the main thread.

$script:Progresso = $null

$SCRIPT_JANELA_PROGRESSO = {
    param($estado, $caminhoIcone)
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    [System.Windows.Forms.Application]::EnableVisualStyles()

    $janela = New-Object System.Windows.Forms.Form
    $janela.Text = "Doceterapia - $($estado.Titulo)"
    $janela.ClientSize = New-Object System.Drawing.Size(600, 430)
    $janela.StartPosition = 'CenterScreen'
    $janela.FormBorderStyle = 'FixedDialog'
    $janela.MaximizeBox = $false
    $janela.MinimizeBox = $true
    $janela.Font = New-Object System.Drawing.Font('Segoe UI', 10)
    if (Test-Path -LiteralPath $caminhoIcone) { $janela.Icon = New-Object System.Drawing.Icon($caminhoIcone) }

    $etapa = New-Object System.Windows.Forms.Label
    $etapa.Location = New-Object System.Drawing.Point(16, 14)
    $etapa.Size = New-Object System.Drawing.Size(568, 48)
    $etapa.Font = New-Object System.Drawing.Font('Segoe UI', 11, [System.Drawing.FontStyle]::Bold)

    $barra = New-Object System.Windows.Forms.ProgressBar
    $barra.Location = New-Object System.Drawing.Point(16, 66)
    $barra.Size = New-Object System.Drawing.Size(568, 18)
    $barra.Style = 'Marquee'
    $barra.MarqueeAnimationSpeed = 30

    $registro = New-Object System.Windows.Forms.TextBox
    $registro.Location = New-Object System.Drawing.Point(16, 96)
    $registro.Size = New-Object System.Drawing.Size(568, 274)
    $registro.Multiline = $true
    $registro.ReadOnly = $true
    $registro.ScrollBars = 'Vertical'
    $registro.Font = New-Object System.Drawing.Font('Consolas', 9)

    $acao = New-Object System.Windows.Forms.Button
    $acao.Location = New-Object System.Drawing.Point(318, 384)
    $acao.Size = New-Object System.Drawing.Size(150, 34)
    $acao.Visible = $false

    $fechar = New-Object System.Windows.Forms.Button
    $fechar.Text = 'Aguarde...'
    $fechar.Location = New-Object System.Drawing.Point(478, 384)
    $fechar.Size = New-Object System.Drawing.Size(106, 34)
    $fechar.Enabled = $false

    $janela.Controls.AddRange(@($etapa, $barra, $registro, $acao, $fechar))

    $fechar.Add_Click({ $janela.Close() })
    $acao.Add_Click({
            $estado.AcaoEscolhida = $true
            $janela.Close()
        })
    $janela.Add_FormClosing({
            param($origem, $evento)
            if (-not $estado.Concluido) { $evento.Cancel = $true }
        })

    $relogio = New-Object System.Windows.Forms.Timer
    $relogio.Interval = 150
    $relogio.Add_Tick({
            $linha = $null
            while ($estado.Fila.TryDequeue([ref]$linha)) {
                $registro.AppendText($linha + "`r`n")
            }
            $etapa.Text = $estado.Etapa
            if ($estado.Concluido -and -not $estado.Finalizada) {
                $estado.Finalizada = $true
                $barra.Style = 'Blocks'
                $barra.Value = 100
                $etapa.ForeColor = if ($estado.Sucesso) { [System.Drawing.Color]::FromArgb(30, 120, 60) } else { [System.Drawing.Color]::FromArgb(180, 30, 30) }
                $fechar.Text = 'Fechar'
                $fechar.Enabled = $true
                if ($estado.AcaoFinal) {
                    $acao.Text = $estado.AcaoFinal
                    $acao.Visible = $true
                    $janela.AcceptButton = $acao
                    $acao.Focus()
                }
                else {
                    $janela.AcceptButton = $fechar
                    $fechar.Focus()
                }
            }
        })
    $relogio.Start()
    $null = $janela.ShowDialog()
    $relogio.Stop()
    $janela.Dispose()
    $estado.Fechada = $true
}

function Test-JanelaProgresso {
    return ($null -ne $script:Progresso)
}

function New-EstadoProgresso {
    param([Parameter(Mandatory = $true)][string]$Titulo)
    return [hashtable]::Synchronized(@{
            Titulo        = $Titulo
            Etapa         = "$Titulo..."
            Fila          = New-Object 'System.Collections.Concurrent.ConcurrentQueue[string]'
            Concluido     = $false
            Finalizada    = $false
            Sucesso       = $false
            AcaoFinal     = $null
            AcaoEscolhida = $false
            Fechada       = $false
        })
}

function Start-ThreadJanelaProgresso {
    param([Parameter(Mandatory = $true)][hashtable]$Estado)
    $espaco = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
    $espaco.ApartmentState = 'STA'
    $espaco.ThreadOptions = 'ReuseThread'
    $espaco.Open()
    $execucao = [System.Management.Automation.PowerShell]::Create()
    $execucao.Runspace = $espaco
    $null = $execucao.AddScript($SCRIPT_JANELA_PROGRESSO.ToString()).AddArgument($Estado).AddArgument($ICONE_SISTEMA)
    return @{ Execucao = $execucao; Espaco = $espaco; Resultado = $execucao.BeginInvoke() }
}

function Wait-JanelaProgresso {
    param([Parameter(Mandatory = $true)][hashtable]$Progresso)
    while (-not $Progresso.Estado.Fechada) {
        Start-Sleep -Milliseconds 200
    }
    $null = $Progresso.Thread.Execucao.EndInvoke($Progresso.Thread.Resultado)
    $Progresso.Thread.Execucao.Dispose()
    $Progresso.Thread.Espaco.Dispose()
}

function Start-JanelaProgresso {
    param([Parameter(Mandatory = $true)][string]$Titulo)
    $estado = New-EstadoProgresso -Titulo $Titulo
    $script:Progresso = @{ Estado = $estado; Thread = (Start-ThreadJanelaProgresso -Estado $estado) }
}

function Add-LinhaProgresso {
    param([AllowEmptyString()][string]$Texto)
    if (Test-JanelaProgresso) { $script:Progresso.Estado.Fila.Enqueue($Texto) }
}

function Set-EtapaProgresso {
    # The step line names what is happening now; the log keeps it as a header.
    param([Parameter(Mandatory = $true)][string]$Texto)
    if (-not (Test-JanelaProgresso)) { return }
    $script:Progresso.Estado.Etapa = $Texto
    Add-LinhaProgresso "== $Texto"
}

function Complete-JanelaProgresso {
    # Shows the outcome and waits for the person to close the window. Returns
    # true when the optional final action was chosen.
    param(
        [Parameter(Mandatory = $true)][bool]$Sucesso,
        [Parameter(Mandatory = $true)][string]$Mensagem,
        [string]$AcaoFinal
    )
    if (-not (Test-JanelaProgresso)) { return $false }
    $estado = $script:Progresso.Estado
    $estado.Etapa = $Mensagem
    $estado.Sucesso = $Sucesso
    if ($Sucesso -and $AcaoFinal) { $estado.AcaoFinal = $AcaoFinal }
    $estado.Concluido = $true
    try {
        Wait-JanelaProgresso -Progresso $script:Progresso
    }
    finally {
        $script:Progresso = $null
    }
    return [bool]$estado.AcaoEscolhida
}
