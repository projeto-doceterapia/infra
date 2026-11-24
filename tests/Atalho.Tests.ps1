. (Join-Path $PSScriptRoot 'Apoio.ps1')

Describe 'atalho do sistema' {
    Mock Invoke-Docker { Get-RespostaDockerFalso -Argumentos $Argumentos }
    Mock Invoke-LoginUsuario { 200 }
    Mock Get-IpLocal { $null }

    Context 'up com navegador encontrado' {
        Mock Get-CaminhoNavegador { 'C:\Navegador\msedge.exe' }
        Reset-DockerFalso
        $ctx = New-RaizDeTeste -Pasta (Join-Path $TestDrive 'com')
        New-EnvPreenchido -Ctx $ctx -Valores @{ FRONTEND_HOST_PORT = '3100' }
        $null = New-Item -ItemType Directory -Path (Split-Path -Parent $ctx.CaminhoIcone) -Force
        Copy-Item -LiteralPath (Join-Path $RAIZ_REPOSITORIO 'assets\doceterapia.ico') -Destination $ctx.CaminhoIcone
        $resultado = Invoke-ComCaptura -Ctx $ctx -Argumentos @('up')
        $caminho = Join-Path $ctx.PastaAtalho 'Doceterapia.lnk'

        It 'cria o atalho na pasta de atalhos' {
            $resultado.Codigo | Should Be 0
            Test-Path -LiteralPath $caminho | Should Be $true
            $resultado.Texto | Should Match 'Atalho pronto'
        }

        It 'abre a porta configurada numa janela de aplicativo com o ícone' {
            $shell = New-Object -ComObject WScript.Shell
            $atalho = $shell.CreateShortcut($caminho)
            $atalho.TargetPath | Should Be 'C:\Navegador\msedge.exe'
            $atalho.Arguments | Should Match '^--app=http://localhost:3100 '
            $atalho.Arguments | Should Match '--user-data-dir='
            $atalho.IconLocation | Should Match 'assets\\doceterapia\.ico,0$'
        }
    }

    Context 'up sem navegador' {
        Mock Get-CaminhoNavegador { $null }
        Reset-DockerFalso
        $ctx = New-RaizDeTeste -Pasta (Join-Path $TestDrive 'sem')
        New-EnvPreenchido -Ctx $ctx
        $resultado = Invoke-ComCaptura -Ctx $ctx -Argumentos @('up')

        It 'avisa e termina com sucesso sem criar o atalho' {
            $resultado.Codigo | Should Be 0
            $resultado.Texto | Should Match 'o atalho não foi criado'
            Test-Path -LiteralPath (Join-Path $ctx.PastaAtalho 'Doceterapia.lnk') | Should Be $false
        }
    }

    Context 'abrir' {
        Mock Start-Process { }
        $ctx = New-RaizDeTeste -Pasta (Join-Path $TestDrive 'abrir')

        It 'com o sistema parado, pede para ligar' {
            Mock Test-SistemaRespondendo { $false }
            $resultado = Invoke-ComCaptura -Ctx $ctx -Argumentos @('abrir')
            $resultado.Codigo | Should Be 2
            $resultado.Texto | Should Match 'não está respondendo'
            Assert-MockCalled Start-Process -Times 0 -Exactly -Scope It
        }

        It 'com o sistema no ar, abre a janela de aplicativo na porta configurada' {
            Mock Test-SistemaRespondendo { $true }
            Mock Get-CaminhoNavegador { 'C:\Navegador\msedge.exe' }
            $resultado = Invoke-ComCaptura -Ctx $ctx -Argumentos @('abrir')
            $resultado.Codigo | Should Be 0
            Assert-MockCalled Start-Process -Times 1 -Exactly -Scope It -ParameterFilter {
                $FilePath -eq 'C:\Navegador\msedge.exe' -and "$ArgumentList" -match '^--app=http://localhost:3000 '
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
}
