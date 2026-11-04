function Write-BackupsDisponiveis {
    param([Parameter(Mandatory = $true)][hashtable]$Ctx)
    $pastas = @()
    if (Test-Path -LiteralPath $Ctx.PastaBackups) {
        $pastas = @(Get-ChildItem -LiteralPath $Ctx.PastaBackups -Directory | Sort-Object Name -Descending)
    }
    if ($pastas.Count -eq 0) {
        Write-Texto 'Nenhum backup encontrado. Para criar um, rode: doceterapia backup'
        return
    }
    Write-Texto 'Backups disponíveis:'
    foreach ($pasta in $pastas) {
        Write-Texto "  $($pasta.Name)"
    }
    Write-Texto 'Para restaurar, rode: doceterapia restore <pasta>'
}

function Resolve-PastaBackup {
    param(
        [Parameter(Mandatory = $true)][hashtable]$Ctx,
        [Parameter(Mandatory = $true)][string]$Nome
    )
    $pasta = if ([System.IO.Path]::IsPathRooted($Nome)) { $Nome } else { Join-Path $Ctx.PastaBackups $Nome }
    if (-not (Test-Path -LiteralPath (Join-Path $pasta 'banco.sql'))) {
        Stop-Launcher -Codigo $CODIGO_BACKUP -Mensagem "O backup $Nome não foi encontrado ou está sem o arquivo banco.sql. Para ver os disponíveis, rode: doceterapia restore"
    }
    return $pasta
}

function Write-ConteudoBackup {
    param([Parameter(Mandatory = $true)][string]$Pasta)
    Write-Texto "Backup: $Pasta"
    $info = Join-Path $Pasta 'info.txt'
    if (Test-Path -LiteralPath $info) {
        $utf8SemBom = New-Object System.Text.UTF8Encoding($false)
        foreach ($linha in [System.IO.File]::ReadAllLines($info, $utf8SemBom)) {
            Write-Texto "  $linha"
        }
    }
    Write-Texto 'Arquivos:'
    foreach ($arquivo in Get-ChildItem -LiteralPath $Pasta -File) {
        Write-Texto "  $($arquivo.Name)"
    }
}

function Invoke-RestauracaoBanco {
    param(
        [Parameter(Mandatory = $true)][hashtable]$Ctx,
        [Parameter(Mandatory = $true)][string]$Pasta
    )
    $origem = Join-Path $Pasta 'banco.sql'
    if ((Invoke-Compose -Ctx $Ctx -Argumentos @('cp', $origem, "banco-de-dados:$ARQUIVO_DUMP_CONTAINER")).Codigo -ne 0) {
        return $false
    }
    # Same quoting constraint as the dump: no double quotes in this argument.
    $comando = 'MYSQL_PWD=$MYSQL_ROOT_PASSWORD; export MYSQL_PWD; ' +
    'mysqladmin -uroot -f drop $MYSQL_DATABASE; ' +
    'mysqladmin -uroot create $MYSQL_DATABASE && ' +
    'mysql -uroot $MYSQL_DATABASE < ' + $ARQUIVO_DUMP_CONTAINER
    try {
        return ((Invoke-Compose -Ctx $Ctx -Argumentos @('exec', '-T', 'banco-de-dados', 'sh', '-c', $comando)).Codigo -eq 0)
    }
    finally {
        $null = Invoke-Compose -Ctx $Ctx -Argumentos @('exec', '-T', 'banco-de-dados', 'rm', '-f', $ARQUIVO_DUMP_CONTAINER) -Capturar
    }
}

function Invoke-RestauracaoSessao {
    param(
        [Parameter(Mandatory = $true)][hashtable]$Ctx,
        [Parameter(Mandatory = $true)][string]$Pasta
    )
    if (-not $Ctx.Simular -and -not (Test-Path -LiteralPath (Join-Path $Pasta 'sessao-whatsapp.tgz'))) {
        return $true
    }
    $volumes = @(Get-VolumesDoProjeto -Ctx $Ctx -Volume $VOLUME_SESSAO)
    if ($volumes.Count -eq 0) {
        Write-Aviso 'O backup tem uma sessão do WhatsApp, mas este canal não usa o adaptador; a sessão não foi restaurada.'
        return $true
    }
    $argumentos = @(
        'run', '--rm', '--network', 'none',
        '-v', "$($volumes[0]):/data",
        '-v', "${Pasta}:/backup:ro",
        (Get-ImagemAuxiliar -Ctx $Ctx),
        'sh', '-c', 'find /data -mindepth 1 -delete && tar xzf /backup/sessao-whatsapp.tgz -C /data'
    )
    return ((Invoke-Docker -Ctx $Ctx -Argumentos $argumentos).Codigo -eq 0)
}

function Invoke-ComandoRestore {
    param(
        [Parameter(Mandatory = $true)][hashtable]$Ctx,
        [string[]]$Extras = @()
    )
    if (@($Extras).Count -gt 1) {
        Stop-Launcher -Codigo $CODIGO_USO -Mensagem 'Informe uma pasta só. Para ver os backups, rode: doceterapia restore'
    }
    if (@($Extras).Count -eq 0) {
        Write-BackupsDisponiveis -Ctx $Ctx
        return
    }
    Assert-ConfiguracaoPronta -Ctx $Ctx
    $pasta = Resolve-PastaBackup -Ctx $Ctx -Nome $Extras[0]
    Write-ConteudoBackup -Pasta $pasta

    if ($Ctx.Simular) {
        Write-Simulacao 'pediria que a pessoa digitasse RESTAURAR.'
    }
    else {
        Write-Aviso 'Os dados atuais serão trocados pelos dados deste backup.'
        if ((Read-Entrada -Pergunta 'Para continuar, digite RESTAURAR') -cne 'RESTAURAR') {
            Stop-Launcher -Codigo $CODIGO_CANCELADO -Mensagem $MENSAGEM_CANCELADO
        }
    }
    Assert-DockerLigado -Ctx $Ctx

    $seguranca = Invoke-BackupDados -Ctx $Ctx
    Write-Texto "Backup de segurança em: $seguranca"

    $servicosValidos = @(Get-ServicosValidos -Ctx $Ctx)
    $parar = @('back-end', 'orquestrador', 'adaptador-baileys') | Where-Object { $Ctx.Simular -or $servicosValidos -ccontains $_ }
    $null = Invoke-Compose -Ctx $Ctx -Argumentos (@('stop') + @($parar))

    if (-not (Test-BancoNoAr -Ctx $Ctx) -and -not (Invoke-SubidaAguardando -Ctx $Ctx -Servicos @('banco-de-dados'))) {
        Stop-Launcher -Codigo $CODIGO_BACKUP -Mensagem 'A restauração falhou porque o banco não ligou. Veja: doceterapia logs banco-de-dados'
    }
    if (-not (Invoke-RestauracaoBanco -Ctx $Ctx -Pasta $pasta)) {
        Stop-Launcher -Codigo $CODIGO_BACKUP -Mensagem "A restauração do banco falhou. Os dados de antes estão em: $seguranca"
    }
    if (-not (Invoke-RestauracaoSessao -Ctx $Ctx -Pasta $pasta)) {
        Stop-Launcher -Codigo $CODIGO_BACKUP -Mensagem "A restauração da sessão do WhatsApp falhou. Os dados de antes estão em: $seguranca"
    }
    if (-not (Invoke-SubidaAguardando -Ctx $Ctx)) {
        Stop-Launcher -Codigo $CODIGO_SERVICO -Mensagem "Os dados foram restaurados, mas o sistema não subiu. Um backup feito em outra versão pode não ser aceito: veja em $(Join-Path $pasta 'info.txt') as tags da época e em doceterapia logs back-end o motivo."
    }
    Write-Texto 'Restauração concluída.'
}
