# Shared test support. Dot-sourced at the top of each test file, it loads the
# launcher functions and provides a fake Docker driven by regex rules. Tests use
# $TestDrive and fictitious values only.

. (Join-Path (Split-Path -Parent $PSScriptRoot) 'scripts\doceterapia.ps1')

$RAIZ_REPOSITORIO = Split-Path -Parent $PSScriptRoot
$SENHA_FICTICIA = 'SenhaFicticia1'

function New-RaizDeTeste {
    # Mimics an infra folder: the real example, optionally with CRLF line endings.
    param(
        [Parameter(Mandatory = $true)][string]$Pasta,
        [switch]$ExemploCrlf
    )
    $null = New-Item -ItemType Directory -Path $Pasta -Force
    $linhas = Read-ArquivoEnv -Caminho (Join-Path $RAIZ_REPOSITORIO '.env.example')
    $separador = if ($ExemploCrlf) { "`r`n" } else { "`n" }
    $utf8SemBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText((Join-Path $Pasta '.env.example'), (($linhas -join $separador) + $separador), $utf8SemBom)
    Copy-Item -LiteralPath (Join-Path $RAIZ_REPOSITORIO 'docker-compose.yml') -Destination (Join-Path $Pasta 'docker-compose.yml')
    $ctx = New-ContextoLauncher -Raiz $Pasta
    $ctx.Projeto = 'doceterapia'
    return $ctx
}

function New-EnvPreenchido {
    # An env file as init would leave it, for the commands that require one.
    param(
        [Parameter(Mandatory = $true)][hashtable]$Ctx,
        [hashtable]$Valores = @{}
    )
    $linhas = Read-ArquivoEnv -Caminho $Ctx.CaminhoExemplo
    Set-SegredosGerados -Linhas $linhas
    Set-ValorEnv -Linhas $linhas -Chave 'ADMIN_EMAIL' -Valor 'dona@exemplo.com'
    foreach ($chave in $Valores.Keys) {
        Set-ValorEnv -Linhas $linhas -Chave $chave -Valor $Valores[$chave]
    }
    Write-ArquivoEnv -Ctx $Ctx -Linhas $linhas
}

function Read-ValorDoEnv {
    param(
        [Parameter(Mandatory = $true)][hashtable]$Ctx,
        [Parameter(Mandatory = $true)][string]$Chave
    )
    return (Get-ValorEnv -Linhas (Read-ArquivoEnv -Caminho $Ctx.CaminhoEnv) -Chave $Chave)
}

function Reset-DockerFalso {
    # Rules are tried in order: @{ Padrao = regex; Codigo = int; Saida = string[] }.
    param([object[]]$Regras = @())
    $global:RegrasDocker = $Regras
    $global:ChamadasDocker = New-Object 'System.Collections.Generic.List[string]'
}

function Get-RespostaDockerFalso {
    param([string[]]$Argumentos)
    $linha = $Argumentos -join ' '
    $global:ChamadasDocker.Add($linha)
    foreach ($regra in $global:RegrasDocker) {
        if ($linha -match $regra.Padrao) {
            return [pscustomobject]@{ Codigo = [int]$regra.Codigo; Saida = @($regra.Saida) }
        }
    }
    return [pscustomobject]@{ Codigo = 0; Saida = @() }
}

function Test-ChamadaDocker {
    param([Parameter(Mandatory = $true)][string]$Padrao)
    return (@($global:ChamadasDocker | Where-Object { $_ -match $Padrao }).Count -gt 0)
}

function Invoke-ComCaptura {
    # Runs the launcher and returns the exit code and everything it printed.
    param(
        [Parameter(Mandatory = $true)][hashtable]$Ctx,
        [string[]]$Argumentos = @()
    )
    $saida = @(Invoke-Doceterapia -Ctx $Ctx -Argumentos $Argumentos 6>&1 | ForEach-Object { $_ })
    $codigo = $saida | Where-Object { $_ -is [int] } | Select-Object -Last 1
    $texto = @($saida | Where-Object { $_ -isnot [int] } | ForEach-Object { "$_" }) -join "`n"
    return [pscustomobject]@{ Codigo = $codigo; Texto = $texto }
}
