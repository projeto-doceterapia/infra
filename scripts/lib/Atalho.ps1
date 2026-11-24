# Desktop shortcut that opens the web system in a browser app window: no tabs,
# no address bar, only the application.

$NOME_ATALHO = 'Doceterapia.lnk'
$NOME_ATALHO_PAINEL = 'Doceterapia - Painel.lnk'
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
    Save-Atalho -Ctx $Ctx -Destino $destino -Alvo $navegador -Descricao 'Abre o sistema Doceterapia' `
        -Argumentos (Get-ArgumentosAppNavegador -Url $Url -PastaPerfil $Ctx.PastaPerfilNavegador)
    return $destino
}

function New-AtalhoPainel {
    # wscript runs the stub with no console window, unlike doceterapia.cmd.
    param([Parameter(Mandatory = $true)][hashtable]$Ctx)
    $destino = Join-Path $Ctx.PastaAtalho $NOME_ATALHO_PAINEL
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
    $navegador = Get-CaminhoNavegador
    if ($navegador) {
        Start-Process -FilePath $navegador -ArgumentList (Get-ArgumentosAppNavegador -Url $Url -PastaPerfil $Ctx.PastaPerfilNavegador)
        return
    }
    Start-Process -FilePath $Url
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
    Start-AplicativoNavegador -Ctx $Ctx -Url $url
}
