function Write-ServicosValidos {
    param([string[]]$Servicos = @())
    Write-Texto 'Serviços disponíveis:'
    foreach ($servico in $Servicos) {
        Write-Texto "  $servico"
    }
}

function Get-ComandoConsoleLogs {
    # PowerShell text for a separate console; every argument is quoted because
    # the project path may contain spaces.
    param(
        [Parameter(Mandatory = $true)][hashtable]$Ctx,
        [Parameter(Mandatory = $true)][string]$Servico
    )
    $perfis = @(Get-PerfisAtivos -Linhas (Read-ConfiguracaoAtual -Ctx $Ctx))
    $argumentos = @(Get-ArgumentosCompose -Ctx $Ctx -Perfis $perfis) + @('logs', '--tail', '200', '-f', $Servico)
    $citados = @($argumentos | ForEach-Object { "'" + ($_ -replace "'", "''") + "'" })
    return "`$Host.UI.RawUI.WindowTitle = 'Doceterapia - registros de $Servico'; & docker $($citados -join ' ')"
}

function Start-ConsoleLogs {
    param(
        [Parameter(Mandatory = $true)][hashtable]$Ctx,
        [Parameter(Mandatory = $true)][string]$Servico
    )
    $codificado = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes((Get-ComandoConsoleLogs -Ctx $Ctx -Servico $Servico)))
    Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoExit', '-NoProfile', '-EncodedCommand', $codificado)
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
