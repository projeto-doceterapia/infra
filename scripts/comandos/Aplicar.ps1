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
