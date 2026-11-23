# Desktop shortcut that opens the web system in a browser app window: no tabs,
# no address bar, only the application.

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
    return "--app=$Url --user-data-dir=`"$PastaPerfil`" --no-first-run --no-default-browser-check"
}

function New-AtalhoSistema {
    param(
        [Parameter(Mandatory = $true)][hashtable]$Ctx,
        [Parameter(Mandatory = $true)][string]$Url
    )
    $destino = Join-Path $Ctx.PastaAtalho $NOME_ATALHO
    if ($Ctx.Simular) {
        Write-Simulacao "criaria o atalho $destino abrindo $Url numa janela própria."
        return $null
    }
    $navegador = Get-CaminhoNavegador
    if (-not $navegador) {
        Write-Aviso "Nenhum Microsoft Edge ou Google Chrome encontrado; o atalho não foi criado. Abra $Url no navegador."
        return $null
    }

    $shell = New-Object -ComObject WScript.Shell
    try {
        $atalho = $shell.CreateShortcut($destino)
        $atalho.TargetPath = $navegador
        $atalho.Arguments = Get-ArgumentosAppNavegador -Url $Url -PastaPerfil $Ctx.PastaPerfilNavegador
        $atalho.WorkingDirectory = Split-Path -Parent $navegador
        $atalho.Description = 'Abre o sistema Doceterapia'
        if (Test-Path -LiteralPath $Ctx.CaminhoIcone) {
            $atalho.IconLocation = "$($Ctx.CaminhoIcone),0"
        }
        $atalho.Save()
    }
    finally {
        $null = [System.Runtime.InteropServices.Marshal]::ReleaseComObject($shell)
    }
    Write-Texto "Atalho pronto: $destino"
    return $destino
}

function Invoke-AbrirSistema {
    param([Parameter(Mandatory = $true)][hashtable]$Ctx)
    $atalho = Join-Path $Ctx.PastaAtalho $NOME_ATALHO
    if (-not (Test-Path -LiteralPath $atalho)) {
        Stop-Launcher -Codigo $CODIGO_CONFIGURACAO -Mensagem 'O atalho ainda não existe. Ligue o sistema primeiro: doceterapia up'
    }
    if ($Ctx.Simular) {
        Write-Simulacao "abriria $atalho"
        return
    }
    Start-Process -FilePath $atalho
}
