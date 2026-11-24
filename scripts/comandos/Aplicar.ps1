function Invoke-PlanoDeReinicio {
    # Runs after the settings window saved the env file. A stopped stack picks
    # the change up on its next start, so nothing is started here.
    param(
        [Parameter(Mandatory = $true)][hashtable]$Ctx,
        [Parameter(Mandatory = $true)]$Plano
    )
    $info = Invoke-Docker -Ctx $Ctx -Argumentos @('info', '--format', '{{.ServerVersion}}') -Capturar
    if ($info.Codigo -ne 0 -or @(Get-ServicosEmExecucao -Ctx $Ctx).Count -eq 0) {
        Write-Texto 'Configuração salva. Ela vale quando o sistema for ligado.'
        return
    }
    if ($Plano.Completo) {
        Set-EtapaProgresso 'Desligando o sistema para trocar o canal'
        if ((Invoke-Compose -Ctx $Ctx -Argumentos @('down') -TodosOsPerfis).Codigo -ne 0) {
            Stop-Launcher -Codigo $CODIGO_USO -Mensagem 'A configuração foi salva, mas não foi possível desligar o sistema. Veja a mensagem acima.'
        }
        Invoke-SubidaCompleta -Ctx $Ctx
        return
    }
    foreach ($servico in $Plano.Servicos) {
        Set-EtapaProgresso "Aplicando a configuração ao serviço $servico"
        if (-not (Invoke-SubidaAguardando -Ctx $Ctx -Servicos @($servico))) {
            Stop-ServicoNaoPronto -Ctx $Ctx
        }
        Write-Texto "Configuração aplicada ao serviço $servico."
    }
}

function Invoke-ComandoAplicar {
    # A plain restart keeps the environment the container was created with, so a
    # configuration change only takes effect when compose recreates the service.
    param(
        [Parameter(Mandatory = $true)][hashtable]$Ctx,
        [string[]]$Extras = @()
    )
    if (@($Extras).Count -gt 1) {
        Stop-Launcher -Codigo $CODIGO_USO -Mensagem 'Informe um serviço só. Exemplo: doceterapia aplicar orquestrador'
    }
    Assert-ConfiguracaoPronta -Ctx $Ctx
    Assert-DockerLigado -Ctx $Ctx

    $servicos = @(Get-ServicosValidos -Ctx $Ctx)
    if (@($Extras).Count -eq 0) {
        Write-ServicosValidos -Servicos $servicos
        return
    }
    if ($servicos -cnotcontains $Extras[0]) {
        Write-ServicosValidos -Servicos $servicos
        Stop-Launcher -Codigo $CODIGO_USO -Mensagem "O serviço $($Extras[0]) não existe."
    }
    if (-not (Invoke-SubidaAguardando -Ctx $Ctx -Servicos @($Extras[0]))) {
        Stop-ServicoNaoPronto -Ctx $Ctx
    }
    Write-Texto "Configuração aplicada ao serviço $($Extras[0])."
}
