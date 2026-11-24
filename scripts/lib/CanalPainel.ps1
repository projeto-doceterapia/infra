# Channel between the command thread and the panel window, which runs on its
# own STA thread so it keeps repainting while a command blocks on Docker. The
# window sends requests; the commands send events, log lines and questions.

$script:Painel = $null

function New-EstadoPainel {
    return [hashtable]::Synchronized(@{
            Pedidos    = New-Object 'System.Collections.Concurrent.ConcurrentQueue[hashtable]'
            Eventos    = New-Object 'System.Collections.Concurrent.ConcurrentQueue[hashtable]'
            Fila       = New-Object 'System.Collections.Concurrent.ConcurrentQueue[string]'
            Respostas  = [hashtable]::Synchronized(@{})
            Etapa      = ''
            EmOperacao = $false
            Encerrar   = $false
            Fechada    = $false
        })
}

function Test-PainelAtivo {
    return ($null -ne $script:Painel)
}

function Test-JanelaProgresso {
    return ((Test-PainelAtivo) -and [bool]$script:Painel.EmOperacao)
}

function Add-LinhaProgresso {
    param([AllowEmptyString()][string]$Texto)
    if (Test-JanelaProgresso) { $script:Painel.Fila.Enqueue($Texto) }
}

function Set-EtapaProgresso {
    # The step line names what is happening now; the log keeps it as a header.
    param([Parameter(Mandatory = $true)][string]$Texto)
    if (-not (Test-JanelaProgresso)) { return }
    $script:Painel.Etapa = $Texto
    Add-LinhaProgresso "== $Texto"
}

function Send-EventoPainel {
    param([Parameter(Mandatory = $true)][hashtable]$Evento)
    if (Test-PainelAtivo) { $script:Painel.Eventos.Enqueue($Evento) }
}

function Wait-RespostaDoPainel {
    # A closed window answers nothing, so the command falls back to its default.
    param([Parameter(Mandatory = $true)][string]$Id)
    $respostas = $script:Painel.Respostas
    while (-not $respostas.ContainsKey($Id)) {
        if ($script:Painel.Fechada) { return $null }
        Start-Sleep -Milliseconds 100
    }
    $resposta = $respostas[$Id]
    $respostas.Remove($Id)
    return $resposta
}

function Request-RespostaDoPainel {
    param(
        [Parameter(Mandatory = $true)][ValidateSet('Mensagem', 'SimNao', 'Texto', 'Servico', 'Pasta')][string]$Modo,
        [Parameter(Mandatory = $true)][hashtable]$Dados
    )
    $id = [guid]::NewGuid().ToString()
    Send-EventoPainel @{ Tipo = 'Pergunta'; Id = $id; Modo = $Modo; Dados = $Dados }
    return (Wait-RespostaDoPainel -Id $id)
}

function Start-OperacaoPainel {
    param([Parameter(Mandatory = $true)][string]$Titulo)
    $script:Painel.Etapa = "$Titulo..."
    $script:Painel.EmOperacao = $true
    Send-EventoPainel @{ Tipo = 'Inicio'; Titulo = $Titulo }
}

function Complete-OperacaoPainel {
    param(
        [Parameter(Mandatory = $true)][bool]$Sucesso,
        [Parameter(Mandatory = $true)][string]$Mensagem,
        [string]$AcaoFinal
    )
    $script:Painel.EmOperacao = $false
    $final = if ($Sucesso -and $AcaoFinal) { $AcaoFinal } else { $null }
    Send-EventoPainel @{ Tipo = 'Fim'; Sucesso = $Sucesso; Mensagem = $Mensagem; AcaoFinal = $final }
}
