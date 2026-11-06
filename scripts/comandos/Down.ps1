function Invoke-ComandoDown {
    param(
        [Parameter(Mandatory = $true)][hashtable]$Ctx,
        [string[]]$Extras = @()
    )
    if (@($Extras).Count -gt 0) {
        Stop-Launcher -Codigo $CODIGO_USO -Mensagem 'Este comando nunca apaga dados.'
    }
    Assert-ConfiguracaoExiste -Ctx $Ctx
    Assert-DockerLigado -Ctx $Ctx
    if ((Invoke-Compose -Ctx $Ctx -Argumentos @('down') -TodosOsPerfis).Codigo -ne 0) {
        Stop-Launcher -Codigo $CODIGO_USO -Mensagem 'Não foi possível desligar o sistema. Veja a mensagem acima.'
    }
    Write-Texto 'Sistema desligado. Os dados continuam guardados.'
}
