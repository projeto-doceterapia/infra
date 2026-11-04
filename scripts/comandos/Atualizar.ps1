$PADRAO_LOG_FLYWAY = 'Migrations have failed validation|checksum mismatch'

function Get-TagsDiferentes {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()]$Linhas,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()]$Exemplo
    )
    foreach ($chave in Get-ChavesEnv -Linhas $Exemplo) {
        if ($chave -match '_TAG$') {
            $de = Get-ValorEnv -Linhas $Linhas -Chave $chave
            $para = Get-ValorEnv -Linhas $Exemplo -Chave $chave
            if ($de -cne $para) {
                [pscustomobject]@{ Chave = $chave; De = $de; Para = $para }
            }
        }
    }
}

function Test-LogFlywayRecusou {
    param([Parameter(Mandatory = $true)][hashtable]$Ctx)
    $log = Invoke-Compose -Ctx $Ctx -Argumentos @('logs', '--no-color', '--tail', '500', 'back-end') -Capturar -IncluirErro
    return ((@($log.Saida) -join "`n") -match $PADRAO_LOG_FLYWAY)
}

function Invoke-ComandoAtualizar {
    param([Parameter(Mandatory = $true)][hashtable]$Ctx)
    # Existence is enough: a secret still missing is generated below, which is
    # how a new release adds one.
    Assert-ConfiguracaoExiste -Ctx $Ctx
    Assert-DockerLigado -Ctx $Ctx

    $exemplo = Read-ArquivoEnv -Caminho $Ctx.CaminhoExemplo
    $linhas = Read-ConfiguracaoAtual -Ctx $Ctx

    $diferencas = @(Get-TagsDiferentes -Linhas $linhas -Exemplo $exemplo)
    if ($diferencas.Count -eq 0) {
        Write-Texto 'Já está na versão mais nova.'
        return
    }

    Write-Texto 'Versões que vão mudar:'
    foreach ($diferenca in $diferencas) {
        $de = if ($diferenca.De) { $diferenca.De } else { '(nova)' }
        Write-Texto "  $($diferenca.Chave): $de -> $($diferenca.Para)"
    }
    if ($Ctx.Simular) {
        Write-Simulacao 'pediria confirmação (S/N).'
    }
    elseif (-not (Read-SimNao -Pergunta 'Continuar?' -Padrao $false)) {
        Stop-Launcher -Codigo $CODIGO_CANCELADO -Mensagem $MENSAGEM_CANCELADO
    }

    # A failed backup stops here, before any tag changes.
    try {
        $pasta = Invoke-BackupDados -Ctx $Ctx
    }
    catch {
        if ($_.Exception.Data['CodigoSaida'] -eq $CODIGO_BACKUP) {
            Write-Erro $_.Exception.Message
            Stop-Launcher -Codigo $CODIGO_BACKUP -Mensagem 'O backup falhou; nada foi atualizado.'
        }
        throw
    }
    Write-Texto "Backup pronto em: $pasta"

    Complete-ChavesNovas -Linhas $linhas -LinhasExemplo $exemplo
    foreach ($diferenca in $diferencas) {
        Set-ValorEnv -Linhas $linhas -Chave $diferenca.Chave -Valor $diferenca.Para
    }
    Set-SegredosGerados -Linhas $linhas
    Write-ArquivoEnv -Ctx $Ctx -Linhas $linhas

    if ((Invoke-Compose -Ctx $Ctx -Argumentos @('pull')).Codigo -ne 0) {
        Stop-Launcher -Codigo $CODIGO_USO -Mensagem 'Não foi possível baixar as imagens. Confira a internet e tente de novo.'
    }
    if (-not (Invoke-SubidaAguardando -Ctx $Ctx)) {
        # Never recreates the database on its own: that is an explicit decision.
        if (Test-LogFlywayRecusou -Ctx $Ctx) {
            Stop-Launcher -Codigo $CODIGO_SERVICO -Mensagem "Esta versão mudou a estrutura do banco. Seus dados estão no backup $pasta. Para continuar, rode: doceterapia resetar-banco"
        }
        Stop-ServicoNaoPronto -Ctx $Ctx
    }
    Confirm-UsuarioInicial -Ctx $Ctx
    Write-EnderecosDoSistema -Linhas (Read-ConfiguracaoAtual -Ctx $Ctx)
}
