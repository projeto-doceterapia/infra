. (Join-Path $PSScriptRoot 'Apoio.ps1')

function Get-AtalhoGravado {
    param([Parameter(Mandatory = $true)][string]$Caminho)
    return (New-Object -ComObject WScript.Shell).CreateShortcut($Caminho)
}

Describe 'atalho do painel' {
    Mock Invoke-Docker { Get-RespostaDockerFalso -Argumentos $Argumentos }
    Mock Invoke-LoginUsuario { 200 }
    Mock Get-IpLocal { $null }

    Context 'up' {
        Reset-DockerFalso
        $ctx = New-RaizDeTeste -Pasta (Join-Path $TestDrive 'up')
        New-EnvPreenchido -Ctx $ctx
        $null = New-Item -ItemType Directory -Path (Split-Path -Parent $ctx.CaminhoIcone) -Force
        Copy-Item -LiteralPath (Join-Path $RAIZ_REPOSITORIO 'assets\doceterapia.ico') -Destination $ctx.CaminhoIcone
        $resultado = Invoke-ComCaptura -Ctx $ctx -Argumentos @('up')
        $caminho = Join-Path $ctx.PastaAtalho 'Doceterapia.lnk'

        It 'cria um único atalho, sem depender de navegador' {
            $resultado.Codigo | Should Be 0
            $resultado.Texto | Should Match 'Atalho pronto'
            @(Get-ChildItem -LiteralPath $ctx.PastaAtalho -Filter '*.lnk').Count | Should Be 1
        }

        It 'abre o painel pelo wscript, sem console, com o ícone' {
            $atalho = Get-AtalhoGravado -Caminho $caminho
            $atalho.TargetPath | Should Match 'wscript\.exe$'
            $atalho.Arguments | Should Be "`"$(Join-Path $ctx.Raiz 'doceterapia.vbs')`""
            $atalho.IconLocation | Should Match 'assets\\doceterapia\.ico,0$'
        }
    }

    Context 'criar-atalho' {
        $ctx = New-RaizDeTeste -Pasta (Join-Path $TestDrive 'criar')
        $resultado = Invoke-ComCaptura -Ctx $ctx -Argumentos @('criar-atalho')

        It 'cria o atalho do painel' {
            $resultado.Codigo | Should Be 0
            (Get-AtalhoGravado -Caminho (Join-Path $ctx.PastaAtalho 'Doceterapia.lnk')).TargetPath | Should Match 'wscript\.exe$'
        }
    }

    Context 'criar-atalho simulado' {
        $ctx = New-RaizDeTeste -Pasta (Join-Path $TestDrive 'simulado')
        $resultado = Invoke-ComCaptura -Ctx $ctx -Argumentos @('criar-atalho', '-Simular')

        It 'não cria nenhum atalho' {
            $resultado.Codigo | Should Be 0
            $resultado.Texto | Should Match 'criaria o atalho'
            @(Get-ChildItem -LiteralPath $ctx.PastaAtalho -Filter '*.lnk').Count | Should Be 0
        }
    }
}

Describe 'abrir' {
    Mock Start-Process { }
    $ctx = New-RaizDeTeste -Pasta (Join-Path $TestDrive 'abrir')

    It 'com o sistema parado, pede para ligar' {
        Mock Test-SistemaRespondendo { $false }
        $resultado = Invoke-ComCaptura -Ctx $ctx -Argumentos @('abrir')
        $resultado.Codigo | Should Be 2
        $resultado.Texto | Should Match 'não está respondendo'
        Assert-MockCalled Start-Process -Times 0 -Exactly -Scope It
    }

    It 'com o sistema no ar, abre a janela de aplicativo em tela cheia na porta configurada' {
        Mock Test-SistemaRespondendo { $true }
        Mock Get-CaminhoNavegador { 'C:\Navegador\msedge.exe' }
        $resultado = Invoke-ComCaptura -Ctx $ctx -Argumentos @('abrir')
        $resultado.Codigo | Should Be 0
        Assert-MockCalled Start-Process -Times 1 -Exactly -Scope It -ParameterFilter {
            $FilePath -eq 'C:\Navegador\msedge.exe' -and "$ArgumentList" -match '^--app=http://localhost:3000 --start-fullscreen ' -and "$ArgumentList" -match '--user-data-dir='
        }
    }

    It 'sem navegador de aplicativo, abre o endereço no navegador padrão' {
        Mock Test-SistemaRespondendo { $true }
        Mock Get-CaminhoNavegador { $null }
        $resultado = Invoke-ComCaptura -Ctx $ctx -Argumentos @('abrir')
        $resultado.Codigo | Should Be 0
        Assert-MockCalled Start-Process -Times 1 -Exactly -Scope It -ParameterFilter { $FilePath -eq 'http://localhost:3000' }
    }
}
