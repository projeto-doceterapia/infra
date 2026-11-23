# Exit codes and every helper that talks to the person running the launcher.

$CODIGO_SUCESSO = 0
$CODIGO_USO = 1
$CODIGO_PRE_REQUISITO = 2
$CODIGO_CONFIGURACAO = 3
$CODIGO_SERVICO = 4
$CODIGO_BOOTSTRAP = 5
$CODIGO_CANCELADO = 6
$CODIGO_BACKUP = 7

$MENSAGEM_DOCKER_DESLIGADO = 'O Docker Desktop não está aberto. Abra o Docker Desktop, espere a baleia ficar parada e tente de novo.'
$MENSAGEM_SEM_CONFIGURACAO = 'Configuração não encontrada. Rode primeiro: doceterapia init'
$MENSAGEM_CANCELADO = 'Nada foi alterado.'

function Stop-Launcher {
    param(
        [Parameter(Mandatory = $true)][int]$Codigo,
        [string]$Mensagem = ''
    )
    $erro = New-Object System.Exception($Mensagem)
    $erro.Data['CodigoSaida'] = $Codigo
    throw $erro
}

$script:ResumoDaSessao = New-Object 'System.Collections.Generic.List[string]'

function Write-Texto {
    # With the dialogs on, the text is also kept to be shown when the command ends.
    param([string]$Texto = '')
    Write-Host $Texto
    if (Test-InterfaceGrafica) { $script:ResumoDaSessao.Add($Texto) }
}

function Get-ResumoDaSessao {
    return (($script:ResumoDaSessao -join "`n").Trim())
}

function Clear-ResumoDaSessao {
    $script:ResumoDaSessao.Clear()
}

function Write-Erro {
    param([string]$Texto)
    Write-Host $Texto -ForegroundColor Red
    if (Test-InterfaceGrafica) { Show-Mensagem -Texto $Texto -Tipo Erro }
}

function Write-Aviso {
    param([string]$Texto)
    Write-Host $Texto -ForegroundColor Yellow
    if (Test-InterfaceGrafica) { Show-Mensagem -Texto $Texto -Tipo Aviso }
}

function Write-Simulacao {
    param([string]$Texto)
    Write-Host "[simulação] $Texto" -ForegroundColor Cyan
}

function Assert-SemArgumentos {
    param([string[]]$Extras = @())
    if (@($Extras).Count -gt 0) {
        Stop-Launcher -Codigo $CODIGO_USO -Mensagem 'Este comando não aceita argumentos. Rode: doceterapia ajuda'
    }
}

function Read-Entrada {
    param([Parameter(Mandatory = $true)][string]$Pergunta)
    if (Test-InterfaceGrafica) { return (Show-CaixaEntrada -Pergunta $Pergunta) }
    return (Read-Host $Pergunta)
}

function Read-SimNao {
    param(
        [Parameter(Mandatory = $true)][string]$Pergunta,
        [bool]$Padrao = $false
    )
    if (Test-InterfaceGrafica) { return (Show-PerguntaSimNao -Pergunta $Pergunta) }
    for ($tentativa = 0; $tentativa -lt 3; $tentativa++) {
        $resposta = "$(Read-Entrada -Pergunta "$Pergunta (S/N)")".Trim()
        if ($resposta -match '^(s|sim)$') { return $true }
        if ($resposta -match '^(n|nao|não)$') { return $false }
        if ($resposta -eq '') { return $Padrao }
        Write-Aviso 'Responda S ou N.'
    }
    return $Padrao
}

function Wait-Intervalo {
    param([int]$Segundos)
    Start-Sleep -Seconds $Segundos
}

function Wait-Enter {
    # Keeps the console open on a double click. Dialogs need no pause, and hosts
    # without input just continue.
    if (Test-InterfaceGrafica) { return }
    try {
        $null = Read-Host 'Pressione Enter para fechar'
    }
    catch {
        Write-Verbose 'No interactive input available.'
    }
}
