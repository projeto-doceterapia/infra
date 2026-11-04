$DOCKER_VERSAO_MINIMA = '25.0'
$COMPOSE_VERSAO_MINIMA = '2.20'
$MEMORIA_MINIMA_GB = 2.1
$MEMORIA_MINIMA_BAILEYS_GB = 2.4
$PORTAS_NAO_PUBLICADAS = @(80, 8080, 3306)
$BYTES_POR_GB = 1024 * 1024 * 1024

function Test-DockerInstalado {
    return ($null -ne (Get-Command docker -ErrorAction SilentlyContinue))
}

function Get-VersaoPowerShell {
    return $PSVersionTable.PSVersion
}

function Test-PortaEmEscuta {
    param([int]$Porta)
    return ($null -ne (Get-NetTCPConnection -State Listen -LocalPort $Porta -ErrorAction SilentlyContinue))
}

function Get-MemoriaLivreGb {
    $kilobytes = (Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory
    return ($kilobytes * 1024 / $BYTES_POR_GB)
}

function Test-VersaoMinima {
    param(
        [AllowEmptyString()][string]$Versao,
        [Parameter(Mandatory = $true)][string]$Minima
    )
    if ($Versao -notmatch '(\d+\.\d+)') { return $false }
    return ([version]$Matches[1] -ge [version]$Minima)
}

function Write-Checagem {
    param(
        [ValidateSet('OK', 'AVISO', 'FALHA')][string]$Estado,
        [string]$Texto
    )
    $cores = @{ OK = 'Green'; AVISO = 'Yellow'; FALHA = 'Red' }
    Write-Host "[$Estado] $Texto" -ForegroundColor $cores[$Estado]
}

function Get-ProjetosCompose {
    param([Parameter(Mandatory = $true)][hashtable]$Ctx)
    $resultado = Invoke-Docker -Ctx $Ctx -Argumentos @('compose', 'ls', '--all', '--format', 'json') -Capturar
    return @(ConvertFrom-JsonLinhas -Linhas $resultado.Saida | Where-Object { $_.Name -eq $Ctx.Projeto })
}

function Test-ChecagensDocker {
    # Returns the number of failures among the checks that need a running Docker.
    param(
        [Parameter(Mandatory = $true)][hashtable]$Ctx,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()]$Linhas
    )
    $falhas = 0

    $versao = Invoke-Docker -Ctx $Ctx -Argumentos @('info', '--format', '{{.ServerVersion}}') -Capturar
    if ($versao.Codigo -ne 0) {
        Write-Checagem FALHA $MENSAGEM_DOCKER_DESLIGADO
        return 1
    }
    if (Test-VersaoMinima "$($versao.Saida)" $DOCKER_VERSAO_MINIMA) {
        Write-Checagem OK "Docker ligado, versão $($versao.Saida)"
    }
    else {
        Write-Checagem FALHA "O Docker é antigo demais ($($versao.Saida)). Atualize o Docker Desktop: é preciso o Docker Engine $DOCKER_VERSAO_MINIMA ou mais novo."
        $falhas++
    }

    $compose = Invoke-Docker -Ctx $Ctx -Argumentos @('compose', 'version', '--short') -Capturar
    if ($compose.Codigo -ne 0) {
        Write-Checagem FALHA 'O Docker Compose v2 não foi encontrado. Atualize o Docker Desktop.'
        $falhas++
    }
    elseif (Test-VersaoMinima "$($compose.Saida)" $COMPOSE_VERSAO_MINIMA) {
        Write-Checagem OK "Docker Compose, versão $($compose.Saida)"
    }
    else {
        Write-Checagem FALHA "O Docker Compose é antigo demais ($($compose.Saida)). Atualize o Docker Desktop: é preciso o Compose $COMPOSE_VERSAO_MINIMA ou mais novo."
        $falhas++
    }

    $memoriaMinima = if ((Get-ValorEnv -Linhas $Linhas -Chave 'CHANNEL') -eq 'baileys') { $MEMORIA_MINIMA_BAILEYS_GB } else { $MEMORIA_MINIMA_GB }
    $memoria = Invoke-Docker -Ctx $Ctx -Argumentos @('info', '--format', '{{.MemTotal}}') -Capturar
    $memoriaGb = 0.0
    if ("$($memoria.Saida)" -match '^\d+$') {
        $memoriaGb = [double]"$($memoria.Saida)" / $BYTES_POR_GB
    }
    $memoriaTexto = $memoriaGb.ToString('0.0')
    if ($memoriaGb -ge $memoriaMinima) {
        Write-Checagem OK "Memória do Docker: $memoriaTexto GB"
    }
    else {
        Write-Checagem FALHA "O Docker tem $memoriaTexto GB de memória e o sistema precisa de $memoriaMinima GB. Aumente a memória do WSL no arquivo .wslconfig (veja o manual de instalação)."
        $falhas++
    }

    return $falhas
}

function Invoke-ComandoDoctor {
    param([Parameter(Mandatory = $true)][hashtable]$Ctx)

    $linhas = Read-ConfiguracaoAtual -Ctx $Ctx

    if ($Ctx.Simular) {
        Write-Simulacao 'o diagnóstico não é avaliado na simulação; estes comandos seriam executados:'
        $null = Invoke-Docker -Ctx $Ctx -Argumentos @('info', '--format', '{{.ServerVersion}}') -Capturar
        $null = Invoke-Docker -Ctx $Ctx -Argumentos @('compose', 'version', '--short') -Capturar
        $null = Invoke-Docker -Ctx $Ctx -Argumentos @('info', '--format', '{{.MemTotal}}') -Capturar
        $null = Invoke-Docker -Ctx $Ctx -Argumentos @('compose', 'ls', '--all', '--format', 'json') -Capturar
        return
    }

    $falhas = 0

    $versaoPs = Get-VersaoPowerShell
    if ($versaoPs -ge [version]'5.1') {
        Write-Checagem OK "PowerShell $versaoPs"
    }
    else {
        Write-Checagem FALHA "O PowerShell $versaoPs é antigo demais. Atualize o Windows: é preciso o PowerShell 5.1."
        $falhas++
    }

    $dockerLigado = $false
    if (Test-DockerInstalado) {
        Write-Checagem OK 'Docker instalado'
        $falhasDocker = Test-ChecagensDocker -Ctx $Ctx -Linhas $linhas
        $falhas += $falhasDocker
        $dockerLigado = ((Invoke-Docker -Ctx $Ctx -Argumentos @('info', '--format', '{{.ServerVersion}}') -Capturar).Codigo -eq 0)
    }
    else {
        Write-Checagem FALHA 'O Docker não está instalado. Instale o Docker Desktop e tente de novo.'
        $falhas++
    }

    $memoriaLivre = Get-MemoriaLivreGb
    $memoriaLivreTexto = ([double]$memoriaLivre).ToString('0.0')
    if ($memoriaLivre -ge $MEMORIA_MINIMA_GB) {
        Write-Checagem OK "Memória livre no Windows: $memoriaLivreTexto GB"
    }
    else {
        Write-Checagem AVISO "Só $memoriaLivreTexto GB de memória livre no Windows. Se o sistema ficar lento, feche outros programas."
    }

    $projetos = @()
    if ($dockerLigado) {
        $projetos = @(Get-ProjetosCompose -Ctx $Ctx)
        foreach ($projeto in $projetos) {
            if ("$($projeto.ConfigFiles)" -and "$($projeto.ConfigFiles)" -inotmatch [regex]::Escape($Ctx.Raiz)) {
                Write-Checagem AVISO "Já existe uma instalação em $($projeto.ConfigFiles)"
            }
        }
    }
    $pilhaNoAr = @($projetos | Where-Object { "$($_.Status)" -match 'running' }).Count -gt 0

    $portaValor = Get-ValorEnv -Linhas $linhas -Chave 'FRONTEND_HOST_PORT'
    $portaPublicada = if ($portaValor) { [int]$portaValor } else { 3000 }
    if (-not (Test-PortaEmEscuta -Porta $portaPublicada)) {
        Write-Checagem OK "Porta $portaPublicada livre"
    }
    elseif ($pilhaNoAr) {
        Write-Checagem OK "Porta $portaPublicada em uso pelo próprio sistema"
    }
    else {
        Write-Checagem FALHA "A porta $portaPublicada está ocupada por outro programa. Feche esse programa ou escolha outra em FRONTEND_HOST_PORT."
        $falhas++
    }
    foreach ($porta in $PORTAS_NAO_PUBLICADAS) {
        if ($porta -ne $portaPublicada -and (Test-PortaEmEscuta -Porta $porta)) {
            Write-Checagem AVISO "A porta $porta está ocupada. O sistema não a usa nesta instalação, então pode seguir."
        }
    }

    if ($falhas -gt 0) {
        Stop-Launcher -Codigo $CODIGO_PRE_REQUISITO -Mensagem 'Corrija os itens com [FALHA] e rode de novo: doceterapia doctor'
    }
    Write-Texto 'Tudo certo com este computador.'
}
