. (Join-Path $PSScriptRoot 'Apoio.ps1')

$REGRAS_SAUDAVEIS = @(
    @{ Padrao = 'info --format \{\{\.ServerVersion\}\}'; Codigo = 0; Saida = @('29.0.0') },
    @{ Padrao = 'compose version --short'; Codigo = 0; Saida = @('2.30.0') },
    @{ Padrao = 'info --format \{\{\.MemTotal\}\}'; Codigo = 0; Saida = @('8000000000') },
    @{ Padrao = 'compose ls'; Codigo = 0; Saida = @('[]') }
)

Describe 'doctor' {
    Mock Invoke-Docker { Get-RespostaDockerFalso -Argumentos $Argumentos }
    Mock Test-DockerInstalado { $true }
    Mock Get-MemoriaLivreGb { 6.0 }
    Mock Test-PortaEmEscuta { $false }

    It 'passa com tudo certo' {
        Reset-DockerFalso -Regras $REGRAS_SAUDAVEIS
        $ctx = New-RaizDeTeste -Pasta (Join-Path $TestDrive 'ok')
        $resultado = Invoke-ComCaptura -Ctx $ctx -Argumentos @('doctor')
        $resultado.Codigo | Should Be 0
        $resultado.Texto | Should Not Match '\[FALHA\]'
    }

    It 'com o Docker Desktop fechado, falha com a correção e código 2' {
        Reset-DockerFalso -Regras @(@{ Padrao = 'info'; Codigo = 1 })
        $ctx = New-RaizDeTeste -Pasta (Join-Path $TestDrive 'fechado')
        $resultado = Invoke-ComCaptura -Ctx $ctx -Argumentos @('doctor')
        $resultado.Codigo | Should Be 2
        $resultado.Texto | Should Match '\[FALHA\] O Docker Desktop não está aberto'
    }

    Context 'sem Docker instalado, falha pedindo a instalação' {
        Mock Test-DockerInstalado { $false }

        It 'resultado esperado' {
                Reset-DockerFalso
                $ctx = New-RaizDeTeste -Pasta (Join-Path $TestDrive 'sem')
                $resultado = Invoke-ComCaptura -Ctx $ctx -Argumentos @('doctor')
                $resultado.Codigo | Should Be 2
                $resultado.Texto | Should Match 'Instale o Docker Desktop'
        }
    }

    It 'falha com Docker Engine antigo' {
        Reset-DockerFalso -Regras (@(@{ Padrao = 'info --format \{\{\.ServerVersion\}\}'; Codigo = 0; Saida = @('24.0.7') }) + $REGRAS_SAUDAVEIS)
        $ctx = New-RaizDeTeste -Pasta (Join-Path $TestDrive 'antigo')
        $resultado = Invoke-ComCaptura -Ctx $ctx -Argumentos @('doctor')
        $resultado.Codigo | Should Be 2
        $resultado.Texto | Should Match '\[FALHA\] O Docker é antigo'
    }

    It 'falha com Compose antigo' {
        Reset-DockerFalso -Regras (@(@{ Padrao = 'compose version'; Codigo = 0; Saida = @('2.19.1') }) + $REGRAS_SAUDAVEIS)
        $ctx = New-RaizDeTeste -Pasta (Join-Path $TestDrive 'compose-antigo')
        $resultado = Invoke-ComCaptura -Ctx $ctx -Argumentos @('doctor')
        $resultado.Codigo | Should Be 2
        $resultado.Texto | Should Match '\[FALHA\] O Docker Compose é antigo'
    }

    It 'falha com pouca memória no Docker e pede mais com baileys' {
        $doisVirgulaDois = @(@{ Padrao = 'info --format \{\{\.MemTotal\}\}'; Codigo = 0; Saida = @([string][long](2.2 * 1024 * 1024 * 1024)) }) + $REGRAS_SAUDAVEIS

        Reset-DockerFalso -Regras $doisVirgulaDois
        $ctx = New-RaizDeTeste -Pasta (Join-Path $TestDrive 'mem1')
        New-EnvPreenchido -Ctx $ctx -Valores @{ CHANNEL = 'cloud_api' }
        (Invoke-ComCaptura -Ctx $ctx -Argumentos @('doctor')).Codigo | Should Be 0

        Reset-DockerFalso -Regras $doisVirgulaDois
        $ctx2 = New-RaizDeTeste -Pasta (Join-Path $TestDrive 'mem2')
        New-EnvPreenchido -Ctx $ctx2 -Valores @{ CHANNEL = 'baileys' }
        $resultado = Invoke-ComCaptura -Ctx $ctx2 -Argumentos @('doctor')
        $resultado.Codigo | Should Be 2
        $resultado.Texto | Should Match '\[FALHA\] O Docker tem'
    }

    Context 'pouca memória livre no Windows é só aviso' {
        Mock Get-MemoriaLivreGb { 1.0 }

        It 'resultado esperado' {
                Reset-DockerFalso -Regras $REGRAS_SAUDAVEIS
                $ctx = New-RaizDeTeste -Pasta (Join-Path $TestDrive 'livre')
                $resultado = Invoke-ComCaptura -Ctx $ctx -Argumentos @('doctor')
                $resultado.Codigo | Should Be 0
                $resultado.Texto | Should Match '\[AVISO\] Só 1'
        }
    }

    Context 'porta publicada ocupada por outro programa é falha que cita a porta' {
        Mock Test-PortaEmEscuta { $Porta -eq 3000 }

        It 'resultado esperado' {
                Reset-DockerFalso -Regras $REGRAS_SAUDAVEIS
                $ctx = New-RaizDeTeste -Pasta (Join-Path $TestDrive 'porta')
                $resultado = Invoke-ComCaptura -Ctx $ctx -Argumentos @('doctor')
                $resultado.Codigo | Should Be 2
                $resultado.Texto | Should Match '\[FALHA\] A porta 3000'
        }
    }

    Context 'lê a porta publicada de FRONTEND_HOST_PORT' {
        Mock Test-PortaEmEscuta { $Porta -eq 3100 }

        It 'resultado esperado' {
                Reset-DockerFalso -Regras $REGRAS_SAUDAVEIS
                $ctx = New-RaizDeTeste -Pasta (Join-Path $TestDrive 'porta-env')
                New-EnvPreenchido -Ctx $ctx -Valores @{ FRONTEND_HOST_PORT = '3100' }
                $resultado = Invoke-ComCaptura -Ctx $ctx -Argumentos @('doctor')
                $resultado.Texto | Should Match '\[FALHA\] A porta 3100'
        }
    }

    Context 'com 3306 ocupada, só avisa' {
        Mock Test-PortaEmEscuta { $Porta -eq 3306 }

        It 'resultado esperado' {
                Reset-DockerFalso -Regras $REGRAS_SAUDAVEIS
                $ctx = New-RaizDeTeste -Pasta (Join-Path $TestDrive 'mysql')
                $resultado = Invoke-ComCaptura -Ctx $ctx -Argumentos @('doctor')
                $resultado.Codigo | Should Be 0
                $resultado.Texto | Should Match '\[AVISO\] A porta 3306'
        }
    }

    Context 'porta ocupada pela própria pilha conta como OK' {
        Mock Test-PortaEmEscuta { $Porta -eq 3000 }

        It 'resultado esperado' {
                $ctx = New-RaizDeTeste -Pasta (Join-Path $TestDrive 'propria')
                $projeto = '[{"Name":"doceterapia","Status":"running(5)","ConfigFiles":"' + ($ctx.CaminhoCompose -replace '\\', '\\') + '"}]'
                Reset-DockerFalso -Regras (@(@{ Padrao = 'compose ls'; Codigo = 0; Saida = @($projeto) }) + $REGRAS_SAUDAVEIS)
                $resultado = Invoke-ComCaptura -Ctx $ctx -Argumentos @('doctor')
                $resultado.Codigo | Should Be 0
                $resultado.Texto | Should Match '\[OK\] Porta 3000 em uso pelo próprio sistema'
                $resultado.Texto | Should Not Match 'Já existe uma instalação'
        }
    }

    It 'avisa de instalação em outra pasta' {
        $projeto = '[{"Name":"doceterapia","Status":"exited(5)","ConfigFiles":"C:\\outra\\docker-compose.yml"}]'
        Reset-DockerFalso -Regras (@(@{ Padrao = 'compose ls'; Codigo = 0; Saida = @($projeto) }) + $REGRAS_SAUDAVEIS)
        $ctx = New-RaizDeTeste -Pasta (Join-Path $TestDrive 'duplicada')
        $resultado = Invoke-ComCaptura -Ctx $ctx -Argumentos @('doctor')
        $resultado.Codigo | Should Be 0
        $resultado.Texto | Should Match '\[AVISO\] Já existe uma instalação em C:\\outra'
    }
}
