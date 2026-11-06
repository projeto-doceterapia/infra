function Write-ServicosValidos {
    param([string[]]$Servicos = @())
    Write-Texto 'Serviços disponíveis:'
    foreach ($servico in $Servicos) {
        Write-Texto "  $servico"
    }
}

function Invoke-ComandoLogs {
    param(
        [Parameter(Mandatory = $true)][hashtable]$Ctx,
        [string[]]$Extras = @()
    )
    if (@($Extras).Count -gt 1) {
        Stop-Launcher -Codigo $CODIGO_USO -Mensagem 'Informe um serviço só. Exemplo: doceterapia logs back-end'
    }
    Assert-ConfiguracaoExiste -Ctx $Ctx
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
    $null = Invoke-Compose -Ctx $Ctx -Argumentos @('logs', '--tail', '200', '-f', $Extras[0])
}
