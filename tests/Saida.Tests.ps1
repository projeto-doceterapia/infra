. (Join-Path $PSScriptRoot 'Apoio.ps1')

# Every secret must stay out of the output of every command, including errors
# and the dry run.
function Get-SegredosDoEnv {
    param([Parameter(Mandatory = $true)][hashtable]$Ctx)
    $linhas = Read-ArquivoEnv -Caminho $Ctx.CaminhoEnv
    $valores = @($SEGREDOS_GERADOS | ForEach-Object { Get-ValorEnv -Linhas $linhas -Chave $_ })
    return ($valores + @($SENHA_FICTICIA, 'token-ficticio-cloud', 'chave-ficticia-gemini'))
}

function Assert-SemSegredos {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Texto,
        [Parameter(Mandatory = $true)][string[]]$Segredos
    )
    foreach ($segredo in $Segredos) {
        $Texto.Contains($segredo) | Should Be $false
    }
}

function New-EnvComTudo {
    param([Parameter(Mandatory = $true)][hashtable]$Ctx)
    New-EnvPreenchido -Ctx $Ctx -Valores @{
        ADMIN_SENHA     = "'$SENHA_FICTICIA'"
        CLOUD_API_TOKEN = "'token-ficticio-cloud'"
        GEMINI_API_KEY  = "'chave-ficticia-gemini'"
    }
}

Describe 'nenhum segredo na saída' {
    Mock Invoke-Docker { Get-RespostaDockerFalso -Argumentos $Argumentos }
    Mock Read-SenhaOculta { $SENHA_FICTICIA }
    Mock Get-IpLocal { $null }
    Mock Test-DockerInstalado { $true }
    Mock Get-MemoriaLivreGb { 6.0 }
    Mock Test-PortaEmEscuta { $false }
    Mock Wait-Intervalo { }

    $casos = @(
        @{ Nome = 'ajuda'; Args = @('ajuda'); Login = 200; Resposta = '' },
        @{ Nome = 'doctor'; Args = @('doctor'); Login = 200; Resposta = '' },
        @{ Nome = 'init'; Args = @('init'); Login = 200; Resposta = 'dona@exemplo.com' },
        @{ Nome = 'up com login 200'; Args = @('up'); Login = 200; Resposta = '' },
        @{ Nome = 'up com login 401'; Args = @('up'); Login = 401; Resposta = '' },
        @{ Nome = 'up sem resposta'; Args = @('up'); Login = 0; Resposta = '' },
        @{ Nome = 'down'; Args = @('down'); Login = 200; Resposta = '' },
        @{ Nome = 'down recusado'; Args = @('down', '-v'); Login = 200; Resposta = '' },
        @{ Nome = 'backup com falha'; Args = @('backup'); Login = 200; Resposta = '' },
        @{ Nome = 'atualizar'; Args = @('atualizar'); Login = 200; Resposta = 'S' },
        @{ Nome = 'logs inválido'; Args = @('logs', 'x'); Login = 200; Resposta = '' },
        @{ Nome = 'resetar-banco cancelado'; Args = @('resetar-banco'); Login = 200; Resposta = 'nao' },
        @{ Nome = 'init simulado'; Args = @('init', '-Simular'); Login = 200; Resposta = '' },
        @{ Nome = 'up simulado'; Args = @('up', '-Simular'); Login = 200; Resposta = '' },
        @{ Nome = 'backup simulado'; Args = @('backup', '-Simular'); Login = 200; Resposta = '' },
        @{ Nome = 'resetar-banco simulado'; Args = @('resetar-banco', '-Simular'); Login = 200; Resposta = '' }
    )

    foreach ($caso in $casos) {
        Context $caso.Nome {
            $login = $caso.Login
            $resposta = $caso.Resposta
            Mock Invoke-LoginUsuario { $login }
            Mock Read-Entrada { $resposta }
            Reset-DockerFalso -Regras @(
                @{ Padrao = 'info --format \{\{\.ServerVersion\}\}'; Codigo = 0; Saida = @('29.0.0') },
                @{ Padrao = 'compose version --short'; Codigo = 0; Saida = @('2.30.0') },
                @{ Padrao = 'info --format \{\{\.MemTotal\}\}'; Codigo = 0; Saida = @('8000000000') }
            )
            $ctx = New-RaizDeTeste -Pasta (Join-Path $TestDrive ($caso.Nome -replace '\W', ''))
            New-EnvComTudo -Ctx $ctx
            $segredos = Get-SegredosDoEnv -Ctx $ctx
            $resultado = Invoke-ComCaptura -Ctx $ctx -Argumentos $caso.Args

            It 'não imprime nenhum segredo' {
                Assert-SemSegredos -Texto $resultado.Texto -Segredos $segredos
            }

            It 'não passa segredo em argumento do Docker' {
                Assert-SemSegredos -Texto (@($global:ChamadasDocker) -join "`n") -Segredos $segredos
            }
        }
    }
}
