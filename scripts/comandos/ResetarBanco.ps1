function Invoke-ComandoResetarBanco {
    param([Parameter(Mandatory = $true)][hashtable]$Ctx)
    Assert-ConfiguracaoPronta -Ctx $Ctx
    Assert-DockerLigado -Ctx $Ctx

    Write-Aviso 'Este comando apaga SÓ o banco de dados (pedidos, clientes, estoque e usuários). A fila do Redis e a sessão do WhatsApp ficam. Antes, é feito um backup.'

    $linhas = Read-ConfiguracaoAtual -Ctx $Ctx
    if ($Ctx.Simular) {
        Write-Simulacao 'pediria que a pessoa digitasse APAGAR, depois e-mail e senha da DONA e dados de demonstração.'
    }
    else {
        if ((Read-Entrada -Pergunta 'Para continuar, digite APAGAR') -cne 'APAGAR') {
            Stop-Launcher -Codigo $CODIGO_CANCELADO -Mensagem $MENSAGEM_CANCELADO
        }
        # Asked before anything is erased, so a mistyped answer cannot leave the
        # person with no database and no way to sign in. The new database needs
        # them because the first user is created again and the password is gone.
        Set-CredenciaisDona -Linhas $linhas -Credenciais (Read-CredenciaisDona)
        $demo = Read-SimNao -Pergunta 'Carregar dados de demonstração?' -Padrao $false
        Set-ValorEnv -Linhas $linhas -Chave 'DEMO_DATA' -Valor $(if ($demo) { 'true' } else { 'false' })
    }

    $pasta = Invoke-BackupDados -Ctx $Ctx
    Write-Texto "Backup pronto em: $pasta"

    if ((Invoke-Compose -Ctx $Ctx -Argumentos @('down') -TodosOsPerfis).Codigo -ne 0) {
        Stop-Launcher -Codigo $CODIGO_USO -Mensagem 'Não foi possível desligar o sistema. O banco não foi apagado.'
    }

    $volumes = @(Get-VolumesDoProjeto -Ctx $Ctx -Volume $VOLUME_BANCO)
    if ($volumes.Count -gt 1) {
        Stop-Launcher -Codigo $CODIGO_USO -Mensagem 'Mais de um volume de banco foi encontrado. Nada foi apagado.'
    }
    if ($volumes.Count -eq 1) {
        if ((Invoke-Docker -Ctx $Ctx -Argumentos @('volume', 'rm', $volumes[0])).Codigo -ne 0) {
            Stop-Launcher -Codigo $CODIGO_USO -Mensagem 'Não foi possível apagar o banco. Veja a mensagem acima.'
        }
    }
    elseif ($Ctx.Simular) {
        Write-Simulacao "docker volume rm $($Ctx.Projeto)_$VOLUME_BANCO"
    }

    Write-ArquivoEnv -Ctx $Ctx -Linhas $linhas
    Invoke-SubidaCompleta -Ctx $Ctx
}
