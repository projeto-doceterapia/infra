. (Join-Path $PSScriptRoot 'Apoio.ps1')

function Get-ArquivosDaPasta {
    param([Parameter(Mandatory = $true)][string]$Pasta)
    return @(Get-ChildItem -LiteralPath $Pasta -Recurse -Force | ForEach-Object { $_.FullName } | Sort-Object)
}

Describe '-Simular' {
    Mock Invoke-DockerNativo { throw 'Docker must not run in a dry run' }
    Mock Read-Entrada { throw 'must not ask in a dry run' }
    Mock Read-SenhaOculta { throw 'must not ask in a dry run' }
    Mock Invoke-LoginUsuario { throw 'must not sign in in a dry run' }
    Mock Get-IpLocal { $null }

    foreach ($comando in 'init', 'up', 'doctor', 'down', 'backup', 'atualizar', 'resetar-banco', 'logs') {
        Context "$comando sem configuração" {
            $ctx = New-RaizDeTeste -Pasta (Join-Path $TestDrive "sem$comando")
            $antes = Get-ArquivosDaPasta -Pasta $ctx.Raiz
            $resultado = Invoke-ComCaptura -Ctx $ctx -Argumentos @($comando, '-Simular')

            It 'não cria arquivo nem executa o Docker' {
                $resultado.Codigo | Should Be 0
                (Get-ArquivosDaPasta -Pasta $ctx.Raiz) -join '|' | Should Be ($antes -join '|')
                Assert-MockCalled Invoke-DockerNativo -Times 0 -Exactly -Scope Context
            }
        }
    }

    Context 'init' {
        $ctx = New-RaizDeTeste -Pasta (Join-Path $TestDrive 'init')
        $resultado = Invoke-ComCaptura -Ctx $ctx -Argumentos @('-Simular', 'init')

        It 'aceita a opção antes do subcomando' {
            $resultado.Codigo | Should Be 0
        }

        It 'mostra o comando do Docker e as chaves com valor mascarado' {
            $resultado.Texto | Should Match '\[simulação\] docker compose .* config --quiet'
            $resultado.Texto | Should Match 'gravaria JWT_SECRET=\*{8}'
            $resultado.Texto | Should Match 'gravaria ORQUESTRADOR_TOKEN=\*{8}'
        }
    }

    Context 'up com senha na configuração' {
        $ctx = New-RaizDeTeste -Pasta (Join-Path $TestDrive 'up')
        New-EnvPreenchido -Ctx $ctx -Valores @{ ADMIN_SENHA = "'$SENHA_FICTICIA'" }
        $conteudo = [System.IO.File]::ReadAllBytes($ctx.CaminhoEnv)
        $resultado = Invoke-ComCaptura -Ctx $ctx -Argumentos @('up', '-Simular')

        It 'mostra a subida e não apaga a senha' {
            $resultado.Codigo | Should Be 0
            $resultado.Texto | Should Match 'up -d --wait --wait-timeout 300'
            $resultado.Texto | Should Match 'gravaria ADMIN_SENHA=\*{8}'
            (Compare-Object $conteudo ([System.IO.File]::ReadAllBytes($ctx.CaminhoEnv))) | Should BeNullOrEmpty
        }
    }

    Context 'down recusado continua recusado' {
        $ctx = New-RaizDeTeste -Pasta (Join-Path $TestDrive 'down')
        It 'sai com 1' {
            Invoke-Doceterapia -Ctx $ctx -Argumentos @('down', '-v', '-Simular') | Should Be 1
        }
    }

    Context 'atalho de ponta a ponta' {
        It 'o processo real sai com 0 e não cria arquivo' {
            $ctx = New-RaizDeTeste -Pasta (Join-Path $TestDrive 'processo')
            $script = Join-Path $RAIZ_REPOSITORIO 'scripts\doceterapia.ps1'
            $antes = (Get-ArquivosDaPasta -Pasta $RAIZ_REPOSITORIO) -join '|'
            & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script up -Simular | Out-Null
            $LASTEXITCODE | Should Be 0
            (Get-ArquivosDaPasta -Pasta $RAIZ_REPOSITORIO) -join '|' | Should Be $antes
        }
    }
}
