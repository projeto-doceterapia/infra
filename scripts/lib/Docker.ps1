# The single place that runs Docker, which is what makes the dry run and the
# test mocks possible.

function Get-NomeProjeto {
    # Same precedence as compose. Volumes are looked up by this label, so it has
    # to name the project compose is really acting on.
    param([Parameter(Mandatory = $true)][string]$CaminhoEnv)
    if ($env:COMPOSE_PROJECT_NAME) {
        return $env:COMPOSE_PROJECT_NAME
    }
    if (Test-Path -LiteralPath $CaminhoEnv) {
        $nome = Get-ValorEnv -Linhas (Read-ArquivoEnv -Caminho $CaminhoEnv) -Chave 'COMPOSE_PROJECT_NAME'
        if ($nome) {
            return $nome
        }
    }
    return 'doceterapia'
}

function New-ContextoLauncher {
    param([Parameter(Mandatory = $true)][string]$Raiz)
    $caminhoEnv = Join-Path $Raiz '.env'
    return @{
        Raiz           = $Raiz
        CaminhoEnv     = $caminhoEnv
        CaminhoExemplo = Join-Path $Raiz '.env.example'
        CaminhoCompose = Join-Path $Raiz 'docker-compose.yml'
        PastaBackups   = Join-Path $Raiz 'backups'
        Projeto        = Get-NomeProjeto -CaminhoEnv $caminhoEnv
        Simular        = $false
    }
}

function Invoke-DockerNativo {
    # 2>&1 on a native command under Stop turns a stderr line into a terminating
    # error on 5.1, so the preference is relaxed here and the result comes from
    # the exit code. Output streams to the console unless captured.
    param(
        [string[]]$Argumentos,
        [switch]$Capturar,
        [switch]$IncluirErro
    )
    $ErrorActionPreference = 'Continue'
    if ($IncluirErro) {
        $saida = @(& docker @Argumentos 2>&1 | ForEach-Object { "$_" })
    }
    elseif ($Capturar) {
        $saida = @(& docker @Argumentos 2>$null | ForEach-Object { "$_" })
    }
    else {
        $saida = @()
        & docker @Argumentos | Out-Host
    }
    return [pscustomobject]@{ Codigo = $LASTEXITCODE; Saida = $saida }
}

function Invoke-Docker {
    param(
        [Parameter(Mandatory = $true)][hashtable]$Ctx,
        [Parameter(Mandatory = $true)][string[]]$Argumentos,
        [switch]$Capturar,
        [switch]$IncluirErro
    )
    if ($Ctx.Simular) {
        Write-Simulacao ("docker " + ($Argumentos -join ' '))
        return [pscustomobject]@{ Codigo = 0; Saida = @() }
    }
    return (Invoke-DockerNativo -Argumentos $Argumentos -Capturar:$Capturar -IncluirErro:$IncluirErro)
}

function Read-ConfiguracaoAtual {
    # The env file when it exists, else the example, so read-only checks work
    # before the first init.
    param([Parameter(Mandatory = $true)][hashtable]$Ctx)
    if (Test-Path -LiteralPath $Ctx.CaminhoEnv) {
        return , (Read-ArquivoEnv -Caminho $Ctx.CaminhoEnv)
    }
    if (Test-Path -LiteralPath $Ctx.CaminhoExemplo) {
        return , (Read-ArquivoEnv -Caminho $Ctx.CaminhoExemplo)
    }
    return , (New-ListaLinhas)
}

function Test-TunelConfigurado {
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()]$Linhas)
    return -not ((Test-SegredoPendente (Get-ValorEnv -Linhas $Linhas -Chave 'NGROK_AUTHTOKEN')) -or
        (Test-SegredoPendente (Get-ValorEnv -Linhas $Linhas -Chave 'NGROK_DOMAIN')))
}

function Get-PerfisAtivos {
    # The tunnel carries the Cloud API webhook, but with deferred credentials ngrok
    # would never turn healthy and would fail the whole "up --wait" for a web app
    # that works without it. The missing tunnel is reported as a warning instead.
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()]$Linhas)
    switch (Get-ValorEnv -Linhas $Linhas -Chave 'CHANNEL') {
        'baileys' { return @('baileys') }
        'cloud_api' {
            if (Test-TunelConfigurado -Linhas $Linhas) { return @('tunnel') }
        }
    }
    return @()
}

function Get-ArgumentosCompose {
    param(
        [Parameter(Mandatory = $true)][hashtable]$Ctx,
        [string[]]$Perfis = @()
    )
    $argumentos = @('compose', '--project-directory', $Ctx.Raiz, '-f', $Ctx.CaminhoCompose)
    foreach ($perfil in $Perfis) {
        $argumentos += @('--profile', $perfil)
    }
    return $argumentos
}

function Invoke-Compose {
    # -TodosOsPerfis is for stopping the stack: it also reaches a profile service
    # left over from a channel that has since changed.
    param(
        [Parameter(Mandatory = $true)][hashtable]$Ctx,
        [Parameter(Mandatory = $true)][string[]]$Argumentos,
        [switch]$Capturar,
        [switch]$IncluirErro,
        [switch]$TodosOsPerfis
    )
    if ($TodosOsPerfis) {
        $perfis = @('tunnel', 'baileys')
    }
    else {
        $perfis = @(Get-PerfisAtivos -Linhas (Read-ConfiguracaoAtual -Ctx $Ctx))
    }
    $completo = @(Get-ArgumentosCompose -Ctx $Ctx -Perfis $perfis) + $Argumentos
    return (Invoke-Docker -Ctx $Ctx -Argumentos $completo -Capturar:$Capturar -IncluirErro:$IncluirErro)
}

function Assert-DockerLigado {
    param([Parameter(Mandatory = $true)][hashtable]$Ctx)
    if ($Ctx.Simular) { return }
    $resultado = Invoke-Docker -Ctx $Ctx -Argumentos @('info', '--format', '{{.ServerVersion}}') -Capturar
    if ($resultado.Codigo -ne 0) {
        Stop-Launcher -Codigo $CODIGO_PRE_REQUISITO -Mensagem $MENSAGEM_DOCKER_DESLIGADO
    }
}

function Get-VolumesDoProjeto {
    param(
        [Parameter(Mandatory = $true)][hashtable]$Ctx,
        [Parameter(Mandatory = $true)][string]$Volume
    )
    $resultado = Invoke-Docker -Ctx $Ctx -Capturar -Argumentos @(
        'volume', 'ls', '-q',
        '--filter', "label=com.docker.compose.project=$($Ctx.Projeto)",
        '--filter', "label=com.docker.compose.volume=$Volume"
    )
    return @($resultado.Saida | Where-Object { $_ })
}

function ConvertFrom-JsonLinhas {
    # Compose prints either one JSON array or one object per line, by version.
    param([string[]]$Linhas = @())
    foreach ($linha in $Linhas) {
        if ($linha -match '^\s*[\[{]') {
            $objeto = ConvertFrom-Json -InputObject $linha
            foreach ($item in $objeto) { $item }
        }
    }
}

function Get-ServicosNaoProntos {
    param([Parameter(Mandatory = $true)][hashtable]$Ctx)
    $resultado = Invoke-Compose -Ctx $Ctx -Argumentos @('ps', '-a', '--format', 'json') -Capturar
    $itens = @(ConvertFrom-JsonLinhas -Linhas $resultado.Saida)
    return @($itens | Where-Object { $_.Health -ne 'healthy' } | ForEach-Object { $_.Service })
}

function Invoke-SubidaAguardando {
    # Returns true when every service turned healthy within five minutes.
    param(
        [Parameter(Mandatory = $true)][hashtable]$Ctx,
        [string[]]$Servicos = @()
    )
    $argumentos = @('up', '-d', '--wait', '--wait-timeout', '300') + $Servicos
    return ((Invoke-Compose -Ctx $Ctx -Argumentos $argumentos).Codigo -eq 0)
}

function Stop-ServicoNaoPronto {
    param([Parameter(Mandatory = $true)][hashtable]$Ctx)
    $naoProntos = @(Get-ServicosNaoProntos -Ctx $Ctx)
    $servico = if ($naoProntos.Count -gt 0) { $naoProntos[0] } else { 'back-end' }
    Stop-Launcher -Codigo $CODIGO_SERVICO -Mensagem "O serviço $servico não ficou pronto em 5 minutos. Veja: doceterapia logs $servico"
}

function Get-ServicosValidos {
    param([Parameter(Mandatory = $true)][hashtable]$Ctx)
    $resultado = Invoke-Compose -Ctx $Ctx -Argumentos @('config', '--services') -Capturar
    return @($resultado.Saida | Where-Object { $_ } | Sort-Object)
}
