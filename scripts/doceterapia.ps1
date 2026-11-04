# Entry point of the Windows launcher: parses the subcommand and the global
# option, runs the command and turns failures into a PT-BR message and a fixed
# exit code. Dot-sourcing it only loads the functions, which is how the tests use it.

$ErrorActionPreference = 'Stop'

foreach ($biblioteca in 'Mensagens', 'ArquivoEnv', 'Segredos', 'Docker', 'Http', 'Configuracao') {
    . (Join-Path $PSScriptRoot "lib\$biblioteca.ps1")
}
foreach ($arquivoComando in Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'comandos') -Filter '*.ps1') {
    . $arquivoComando.FullName
}

function Invoke-Doceterapia {
    param(
        [string[]]$Argumentos = @(),
        [hashtable]$Ctx
    )

    try {
        $simular = @($Argumentos | Where-Object { $_ -ieq '-Simular' }).Count -gt 0
        $resto = @($Argumentos | Where-Object { $_ -ine '-Simular' })

        if (-not $Ctx) {
            $Ctx = New-ContextoLauncher -Raiz (Split-Path -Parent $PSScriptRoot)
        }
        $Ctx.Simular = $simular

        if ($resto.Count -eq 0) {
            Invoke-ComandoAjuda
            Wait-Enter
            return $CODIGO_SUCESSO
        }

        $comando = $resto[0].ToLowerInvariant()
        $extras = @($resto | Select-Object -Skip 1)

        switch -Exact ($comando) {
            'ajuda' { $null = Invoke-ComandoAjuda }
            'doctor' { Assert-SemArgumentos $extras; $null = Invoke-ComandoDoctor -Ctx $Ctx }
            'init' { Assert-SemArgumentos $extras; $null = Invoke-ComandoInit -Ctx $Ctx }
            'up' { Assert-SemArgumentos $extras; $null = Invoke-ComandoUp -Ctx $Ctx }
            'aplicar' { $null = Invoke-ComandoAplicar -Ctx $Ctx -Extras $extras }
            'down' { $null = Invoke-ComandoDown -Ctx $Ctx -Extras $extras }
            'backup' { Assert-SemArgumentos $extras; $null = Invoke-ComandoBackup -Ctx $Ctx }
            'restore' { $null = Invoke-ComandoRestore -Ctx $Ctx -Extras $extras }
            'atualizar' { Assert-SemArgumentos $extras; $null = Invoke-ComandoAtualizar -Ctx $Ctx }
            'logs' { $null = Invoke-ComandoLogs -Ctx $Ctx -Extras $extras }
            'resetar-banco' { Assert-SemArgumentos $extras; $null = Invoke-ComandoResetarBanco -Ctx $Ctx }
            default { Stop-Launcher -Codigo $CODIGO_USO -Mensagem 'Comando desconhecido. Rode: doceterapia ajuda' }
        }
        return $CODIGO_SUCESSO
    }
    catch [System.Management.Automation.CommandNotFoundException] {
        Write-Erro 'O Docker não foi encontrado. Instale o Docker Desktop e tente de novo.'
        return $CODIGO_PRE_REQUISITO
    }
    catch {
        $codigo = $_.Exception.Data['CodigoSaida']
        if ($null -eq $codigo) {
            Write-Erro "Erro inesperado: $($_.Exception.Message)"
            return $CODIGO_USO
        }
        if ($_.Exception.Message) {
            Write-Erro $_.Exception.Message
        }
        return [int]$codigo
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    # Needed to capture Docker's JSON output without corrupting it. Hosts without
    # a console handle refuse the assignment, and they do not need it either.
    try {
        [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
    }
    catch {
        Write-Verbose 'No console to configure.'
    }
    exit (Invoke-Doceterapia -Argumentos $args)
}
