# Desktop shortcut to the launcher panel, and the browser app window that the
# panel opens: no tabs, no address bar, full screen, only the application.

$NOME_ATALHO = 'Doceterapia.lnk'
$NAVEGADORES_APP = @('msedge.exe', 'chrome.exe')

function Get-CaminhoNavegador {
    # Edge ships with Windows 10 and 11; Chrome is the fallback. Both support
    # the --app window mode.
    foreach ($executavel in $NAVEGADORES_APP) {
        foreach ($raiz in 'HKCU:', 'HKLM:') {
            $chave = "$raiz\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\$executavel"
            try {
                $caminho = (Get-ItemProperty -LiteralPath $chave -ErrorAction Stop).'(default)'
                if ($caminho -and (Test-Path -LiteralPath $caminho)) { return $caminho }
            }
            catch {
                Write-Verbose "No App Paths entry for $executavel under $raiz."
            }
        }
    }
    $padrao = Join-Path ${env:ProgramFiles(x86)} 'Microsoft\Edge\Application\msedge.exe'
    if (Test-Path -LiteralPath $padrao) { return $padrao }
    return $null
}

function Get-ArgumentosAppNavegador {
    # A dedicated profile keeps the app window, its sign-in cookie and its
    # taskbar entry apart from the person's everyday browsing.
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$PastaPerfil
    )
    return "--app=$Url --start-fullscreen --user-data-dir=`"$PastaPerfil`" --no-first-run --no-default-browser-check"
}

function Save-Atalho {
    param(
        [Parameter(Mandatory = $true)][hashtable]$Ctx,
        [Parameter(Mandatory = $true)][string]$Destino,
        [Parameter(Mandatory = $true)][string]$Alvo,
        [Parameter(Mandatory = $true)][string]$Argumentos,
        [Parameter(Mandatory = $true)][string]$Descricao
    )
    $shell = New-Object -ComObject WScript.Shell
    try {
        $atalho = $shell.CreateShortcut($Destino)
        $atalho.TargetPath = $Alvo
        $atalho.Arguments = $Argumentos
        $atalho.WorkingDirectory = Split-Path -Parent $Alvo
        $atalho.Description = $Descricao
        if (Test-Path -LiteralPath $Ctx.CaminhoIcone) {
            $atalho.IconLocation = "$($Ctx.CaminhoIcone),0"
        }
        $atalho.Save()
    }
    finally {
        $null = [System.Runtime.InteropServices.Marshal]::ReleaseComObject($shell)
    }
    Write-Texto "Atalho pronto: $Destino"
}

function New-AtalhoDoceterapia {
    # wscript runs the stub with no console window, unlike doceterapia.cmd.
    param([Parameter(Mandatory = $true)][hashtable]$Ctx)
    $destino = Join-Path $Ctx.PastaAtalho $NOME_ATALHO
    if ($Ctx.Simular) {
        Write-Simulacao "criaria o atalho $destino abrindo o painel do Doceterapia."
        return $null
    }
    $alvo = Join-Path $env:SystemRoot 'System32\wscript.exe'
    Save-Atalho -Ctx $Ctx -Destino $destino -Alvo $alvo -Descricao 'Abre o painel do Doceterapia' `
        -Argumentos "`"$(Join-Path $Ctx.Raiz 'doceterapia.vbs')`""
    return $destino
}

function Get-UrlSistema {
    param([Parameter(Mandatory = $true)][hashtable]$Ctx)
    return "http://localhost:$(Get-PortaFrontEnd -Linhas (Read-ConfiguracaoAtual -Ctx $Ctx))"
}

function Start-AplicativoNavegador {
    param(
        [Parameter(Mandatory = $true)][hashtable]$Ctx,
        [Parameter(Mandatory = $true)][string]$Url
    )
    # Returns true when the app window was used, the only case whose closing
    # can be watched.
    $navegador = Get-CaminhoNavegador
    if ($navegador) {
        Start-Process -FilePath $navegador -ArgumentList (Get-ArgumentosAppNavegador -Url $Url -PastaPerfil $Ctx.PastaPerfilNavegador)
        return $true
    }
    Start-Process -FilePath $Url
    return $false
}

function Test-JanelaNavegadorAberta {
    # The dedicated profile folder is on the command line of every process of
    # the app window, and the browser may keep running in the background, so a
    # visible window is what counts.
    param([Parameter(Mandatory = $true)][string]$PastaPerfil)
    $processos = @(Get-CimInstance -ClassName Win32_Process -Filter "Name = 'msedge.exe' OR Name = 'chrome.exe'" -ErrorAction SilentlyContinue |
            Where-Object { $_.CommandLine -and $_.CommandLine.IndexOf($PastaPerfil, [System.StringComparison]::OrdinalIgnoreCase) -ge 0 })
    foreach ($processo in $processos) {
        if (Test-ProcessoComJanela -Id $processo.ProcessId) { return $true }
    }
    return $false
}

function Test-ProcessoComJanela {
    param([Parameter(Mandatory = $true)][int]$Id)
    $processo = Get-Process -Id $Id -ErrorAction SilentlyContinue
    return ($null -ne $processo -and $processo.MainWindowHandle -ne [IntPtr]::Zero)
}

function Invoke-AbrirSistema {
    param([Parameter(Mandatory = $true)][hashtable]$Ctx)
    $url = Get-UrlSistema -Ctx $Ctx
    if ($Ctx.Simular) {
        Write-Simulacao "abriria $url numa janela própria."
        return
    }
    if (-not (Test-SistemaRespondendo -Url $url)) {
        Stop-Launcher -Codigo $CODIGO_PRE_REQUISITO -Mensagem 'O sistema não está respondendo. Ligue o sistema primeiro: doceterapia up'
    }
    $null = Start-AplicativoNavegador -Ctx $Ctx -Url $url
}
