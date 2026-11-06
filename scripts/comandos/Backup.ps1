$ARQUIVO_DUMP_CONTAINER = '/tmp/doceterapia-banco.sql'
$VOLUME_BANCO = 'banco-de-dados-data'
$VOLUME_SESSAO = 'adaptador-baileys-session'

function Get-ImagemAuxiliar {
    param([Parameter(Mandatory = $true)][hashtable]$Ctx)
    $tag = Get-ValorEnv -Linhas (Read-ConfiguracaoAtual -Ctx $Ctx) -Chave 'ALPINE_TAG'
    if (-not $tag -and (Test-Path -LiteralPath $Ctx.CaminhoExemplo)) {
        $tag = Get-ValorEnv -Linhas (Read-ArquivoEnv -Caminho $Ctx.CaminhoExemplo) -Chave 'ALPINE_TAG'
    }
    if (-not $tag) {
        Stop-Launcher -Codigo $CODIGO_BACKUP -Mensagem 'A variável ALPINE_TAG não foi encontrada. Rode: doceterapia init'
    }
    return "alpine:$tag"
}

function Test-BancoNoAr {
    param([Parameter(Mandatory = $true)][hashtable]$Ctx)
    $resultado = Invoke-Compose -Ctx $Ctx -Argumentos @('ps', '--status', 'running', '-q', 'banco-de-dados') -Capturar
    return (@($resultado.Saida | Where-Object { $_ }).Count -gt 0)
}

function Write-InfoBackup {
    param(
        [Parameter(Mandatory = $true)][hashtable]$Ctx,
        [Parameter(Mandatory = $true)][string]$Pasta
    )
    if ($Ctx.Simular) {
        Write-Simulacao 'gravaria info.txt com a data e as tags das imagens.'
        return
    }
    $linhas = Read-ConfiguracaoAtual -Ctx $Ctx
    $conteudo = @("Data: $((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))", 'Tags das imagens:')
    foreach ($chave in Get-ChavesEnv -Linhas $linhas) {
        if ($chave -match '_TAG$') {
            $conteudo += "  $chave=$(Get-ValorEnv -Linhas $linhas -Chave $chave)"
        }
    }
    $utf8SemBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText((Join-Path $Pasta 'info.txt'), (($conteudo -join "`n") + "`n"), $utf8SemBom)
}

function Invoke-DumpBanco {
    # The dump never crosses the PowerShell pipeline, which re-encodes native
    # output on 5.1 and corrupts the file. It is also why the password goes by
    # MYSQL_PWD: 5.1 strips embedded double quotes from native arguments.
    param(
        [Parameter(Mandatory = $true)][hashtable]$Ctx,
        [Parameter(Mandatory = $true)][string]$Pasta
    )
    $comandoDump = 'MYSQL_PWD=$MYSQL_ROOT_PASSWORD mysqldump -uroot --no-tablespaces --single-transaction --routines --result-file=' + $ARQUIVO_DUMP_CONTAINER + ' $MYSQL_DATABASE'
    try {
        if ((Invoke-Compose -Ctx $Ctx -Argumentos @('exec', '-T', 'banco-de-dados', 'sh', '-c', $comandoDump)).Codigo -ne 0) {
            return $false
        }
        $destino = Join-Path $Pasta 'banco.sql'
        if ((Invoke-Compose -Ctx $Ctx -Argumentos @('cp', "banco-de-dados:$ARQUIVO_DUMP_CONTAINER", $destino)).Codigo -ne 0) {
            return $false
        }
    }
    finally {
        $null = Invoke-Compose -Ctx $Ctx -Argumentos @('exec', '-T', 'banco-de-dados', 'rm', '-f', $ARQUIVO_DUMP_CONTAINER) -Capturar
    }
    if ($Ctx.Simular) { return $true }
    $arquivo = Join-Path $Pasta 'banco.sql'
    return ((Test-Path -LiteralPath $arquivo) -and (Get-Item -LiteralPath $arquivo).Length -gt 0)
}

function Invoke-BackupSessao {
    param(
        [Parameter(Mandatory = $true)][hashtable]$Ctx,
        [Parameter(Mandatory = $true)][string]$Pasta
    )
    $volumes = @(Get-VolumesDoProjeto -Ctx $Ctx -Volume $VOLUME_SESSAO)
    if ($volumes.Count -eq 0) {
        Write-Aviso 'Sem sessão do WhatsApp para guardar neste canal; esse passo foi pulado.'
        return $true
    }
    $argumentos = @(
        'run', '--rm', '--network', 'none',
        '-v', "$($volumes[0]):/data:ro",
        '-v', "${Pasta}:/backup",
        (Get-ImagemAuxiliar -Ctx $Ctx),
        'tar', 'czf', '/backup/sessao-whatsapp.tgz', '-C', '/data', '.'
    )
    return ((Invoke-Docker -Ctx $Ctx -Argumentos $argumentos).Codigo -eq 0)
}

function Invoke-BackupDados {
    # Returns the backup folder. The stack may be down, or the back-end may be
    # failing after an update, so the database is started alone when needed and
    # stopped again to leave things as they were.
    param([Parameter(Mandatory = $true)][hashtable]$Ctx)

    $pasta = Join-Path $Ctx.PastaBackups (Get-Date).ToString('yyyy-MM-dd_HHmmss')
    if ($Ctx.Simular) {
        Write-Simulacao "criaria a pasta $pasta"
    }
    else {
        $null = New-Item -ItemType Directory -Path $pasta -Force
    }

    $estavaNoAr = Test-BancoNoAr -Ctx $Ctx
    if (-not $estavaNoAr -and -not (Invoke-SubidaAguardando -Ctx $Ctx -Servicos @('banco-de-dados'))) {
        Stop-Launcher -Codigo $CODIGO_BACKUP -Mensagem 'O backup falhou porque o banco não ligou; nada foi alterado. Veja: doceterapia logs banco-de-dados'
    }

    try {
        if (-not (Invoke-DumpBanco -Ctx $Ctx -Pasta $pasta)) {
            Stop-Launcher -Codigo $CODIGO_BACKUP -Mensagem 'O backup do banco falhou; nada foi alterado.'
        }
        if (-not (Invoke-BackupSessao -Ctx $Ctx -Pasta $pasta)) {
            Stop-Launcher -Codigo $CODIGO_BACKUP -Mensagem 'O backup da sessão do WhatsApp falhou; nada foi alterado.'
        }
        Write-InfoBackup -Ctx $Ctx -Pasta $pasta
    }
    finally {
        if (-not $estavaNoAr) {
            $null = Invoke-Compose -Ctx $Ctx -Argumentos @('stop', 'banco-de-dados')
        }
    }
    return $pasta
}

function Invoke-ComandoBackup {
    param([Parameter(Mandatory = $true)][hashtable]$Ctx)
    Assert-ConfiguracaoPronta -Ctx $Ctx
    Assert-DockerLigado -Ctx $Ctx
    $pasta = Invoke-BackupDados -Ctx $Ctx
    Write-Texto "Backup pronto em: $pasta"
}
