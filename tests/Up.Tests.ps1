. (Join-Path $PSScriptRoot 'Apoio.ps1')

Describe 'up' {
    Mock Invoke-Docker { Get-RespostaDockerFalso -Argumentos $Argumentos }
    Mock Wait-Intervalo { }
    Mock Get-IpLocal { '192.168.0.10' }

    Context 'login 200' {
        Reset-DockerFalso
        Mock Invoke-LoginUsuario { 200 }
        $ctx = New-RaizDeTeste -Pasta (Join-Path $TestDrive 'ok')
        New-EnvPreenchido -Ctx $ctx -Valores @{ ADMIN_SENHA = "'$SENHA_FICTICIA'" }
        $resultado = Invoke-ComCaptura -Ctx $ctx -Argumentos @('up')

        It 'sobe esperando a saúde dos serviços' {
            $resultado.Codigo | Should Be 0
            Test-ChamadaDocker 'up -d --wait --wait-timeout 300' | Should Be $true
        }

        It 'apaga ADMIN_SENHA e mantém ADMIN_EMAIL' {
            Read-ValorDoEnv -Ctx $ctx -Chave 'ADMIN_SENHA' | Should BeNullOrEmpty
            Read-ValorDoEnv -Ctx $ctx -Chave 'ADMIN_EMAIL' | Should Be 'dona@exemplo.com'
        }

        It 'chama o login pela porta publicada' {
            Assert-MockCalled Invoke-LoginUsuario -Scope Context -ParameterFilter { $Url -eq 'http://localhost:3000/api/usuarios/login' }
        }

        It 'mostra os endereços do sistema' {
            $resultado.Texto | Should Match 'http://localhost:3000'
            $resultado.Texto | Should Match 'http://192.168.0.10:3000'
        }

        It 'avisa que o assistente não está configurado' {
            $resultado.Texto | Should Match 'o assistente do WhatsApp só funciona depois de configurar os tokens'
        }
    }

    foreach ($caso in @(@{ Status = 401; Nome = 'login 401' }, @{ Status = 0; Nome = 'sem resposta' }, @{ Status = 500; Nome = 'erro 500' })) {
        Context $caso.Nome {
            $status = $caso.Status
            Reset-DockerFalso
            Mock Invoke-LoginUsuario { $status }
            $ctx = New-RaizDeTeste -Pasta (Join-Path $TestDrive "falha$status")
            New-EnvPreenchido -Ctx $ctx -Valores @{ ADMIN_SENHA = "'$SENHA_FICTICIA'" }
            $codigo = Invoke-Doceterapia -Ctx $ctx -Argumentos @('up')

            It 'mantém ADMIN_SENHA e sai com 5, após 5 tentativas' {
                $codigo | Should Be 5
                Read-ValorDoEnv -Ctx $ctx -Chave 'ADMIN_SENHA' | Should Be $SENHA_FICTICIA
                Assert-MockCalled Invoke-LoginUsuario -Times 5 -Exactly -Scope Context
            }
        }
    }

    Context 'ADMIN_SENHA vazia' {
        Reset-DockerFalso
        Mock Invoke-LoginUsuario { 500 }
        $ctx = New-RaizDeTeste -Pasta (Join-Path $TestDrive 'vazia')
        New-EnvPreenchido -Ctx $ctx
        $codigo = Invoke-Doceterapia -Ctx $ctx -Argumentos @('up')

        It 'pula a detecção' {
            $codigo | Should Be 0
            Assert-MockCalled Invoke-LoginUsuario -Times 0 -Exactly -Scope Context
        }
    }

    Context 'sem configuração' {
        Reset-DockerFalso
        $ctx = New-RaizDeTeste -Pasta (Join-Path $TestDrive 'sem')
        $codigo = Invoke-Doceterapia -Ctx $ctx -Argumentos @('up')

        It 'sai com 3 sem chamar o Docker' {
            $codigo | Should Be 3
            $global:ChamadasDocker.Count | Should Be 0
        }
    }

    Context 'marcadores ainda não gerados' {
        foreach ($chave in 'JWT_SECRET', 'REDIS_PASSWORD', 'ORQUESTRADOR_TOKEN', 'DB_PASSWORD') {
            It "recusa $chave pendente, inclusive o marcador do JWT" {
                Reset-DockerFalso
                $ctx = New-RaizDeTeste -Pasta (Join-Path $TestDrive "pendente$chave")
                $original = Get-ValorEnv -Linhas (Read-ArquivoEnv -Caminho $ctx.CaminhoExemplo) -Chave $chave
                New-EnvPreenchido -Ctx $ctx -Valores @{ $chave = $original }
                Invoke-Doceterapia -Ctx $ctx -Argumentos @('up') | Should Be 3
            }
        }
    }

    Context 'serviço que não fica saudável' {
        Reset-DockerFalso -Regras @(
            @{ Padrao = 'up -d --wait'; Codigo = 1 },
            @{ Padrao = 'ps -a --format json'; Codigo = 0; Saida = @('{"Service":"banco-de-dados","Health":"healthy"}', '{"Service":"back-end","Health":"unhealthy"}') }
        )
        $ctx = New-RaizDeTeste -Pasta (Join-Path $TestDrive 'doente')
        New-EnvPreenchido -Ctx $ctx -Valores @{ ADMIN_SENHA = "'$SENHA_FICTICIA'" }
        $resultado = Invoke-ComCaptura -Ctx $ctx -Argumentos @('up')

        It 'sai com 4 citando o serviço e mantém a senha' {
            $resultado.Codigo | Should Be 4
            $resultado.Texto | Should Match 'O serviço back-end não ficou pronto em 5 minutos'
            Read-ValorDoEnv -Ctx $ctx -Chave 'ADMIN_SENHA' | Should Be $SENHA_FICTICIA
        }
    }

    Context 'imagens' {
        It 'baixa só quando falta imagem' {
            Reset-DockerFalso -Regras @(@{ Padrao = 'config --images'; Codigo = 0; Saida = @('imagem:1') })
            $ctx = New-RaizDeTeste -Pasta (Join-Path $TestDrive 'imagem-ok')
            New-EnvPreenchido -Ctx $ctx
            $null = Invoke-Doceterapia -Ctx $ctx -Argumentos @('up')
            Test-ChamadaDocker ' pull$' | Should Be $false
        }

        It 'baixa quando falta' {
            Reset-DockerFalso -Regras @(
                @{ Padrao = 'config --images'; Codigo = 0; Saida = @('imagem:1') },
                @{ Padrao = 'image inspect'; Codigo = 1 }
            )
            $ctx = New-RaizDeTeste -Pasta (Join-Path $TestDrive 'imagem-falta')
            New-EnvPreenchido -Ctx $ctx
            $null = Invoke-Doceterapia -Ctx $ctx -Argumentos @('up')
            Test-ChamadaDocker ' pull$' | Should Be $true
        }
    }
}

Describe 'perfis' {
    Mock Invoke-Docker { Get-RespostaDockerFalso -Argumentos $Argumentos }

    It 'usa baileys com CHANNEL=baileys' {
        Reset-DockerFalso
        $ctx = New-RaizDeTeste -Pasta (Join-Path $TestDrive 'p1')
        New-EnvPreenchido -Ctx $ctx -Valores @{ CHANNEL = 'baileys' }
        $null = Invoke-Compose -Ctx $ctx -Argumentos @('ps')
        Test-ChamadaDocker '--profile baileys ps' | Should Be $true
    }

    It 'usa tunnel com cloud_api e ngrok preenchido' {
        Reset-DockerFalso
        $ctx = New-RaizDeTeste -Pasta (Join-Path $TestDrive 'p2')
        New-EnvPreenchido -Ctx $ctx -Valores @{ CHANNEL = 'cloud_api'; NGROK_AUTHTOKEN = "'token-ficticio'"; NGROK_DOMAIN = 'exemplo.ngrok-free.app' }
        $null = Invoke-Compose -Ctx $ctx -Argumentos @('ps')
        Test-ChamadaDocker '--profile tunnel ps' | Should Be $true
    }

    It 'não usa tunnel com o ngrok adiado, para não derrubar o sistema web' {
        Reset-DockerFalso
        $ctx = New-RaizDeTeste -Pasta (Join-Path $TestDrive 'p3')
        New-EnvPreenchido -Ctx $ctx -Valores @{ CHANNEL = 'cloud_api' }
        $null = Invoke-Compose -Ctx $ctx -Argumentos @('ps')
        Test-ChamadaDocker '--profile' | Should Be $false
    }

    It 'monta o caminho como argumentos separados, por causa de espaços' {
        Reset-DockerFalso
        $ctx = New-RaizDeTeste -Pasta (Join-Path $TestDrive 'Nome Sobrenome')
        $argumentos = Get-ArgumentosCompose -Ctx $ctx -Perfis @()
        $argumentos[2] | Should Be $ctx.Raiz
        $argumentos[4] | Should Be $ctx.CaminhoCompose
    }
}

Describe 'aplicar' {
    Mock Invoke-Docker { Get-RespostaDockerFalso -Argumentos $Argumentos }

    It 'recria só o serviço pedido' {
        Reset-DockerFalso -Regras @(@{ Padrao = 'config --services'; Codigo = 0; Saida = @('orquestrador', 'back-end') })
        $ctx = New-RaizDeTeste -Pasta (Join-Path $TestDrive 'a1')
        New-EnvPreenchido -Ctx $ctx
        Invoke-Doceterapia -Ctx $ctx -Argumentos @('aplicar', 'orquestrador') | Should Be 0
        Test-ChamadaDocker 'up -d --wait --wait-timeout 300 orquestrador$' | Should Be $true
        Test-ChamadaDocker ' restart ' | Should Be $false
    }

    It 'recusa serviço inválido com 1' {
        Reset-DockerFalso -Regras @(@{ Padrao = 'config --services'; Codigo = 0; Saida = @('orquestrador') })
        $ctx = New-RaizDeTeste -Pasta (Join-Path $TestDrive 'a2')
        New-EnvPreenchido -Ctx $ctx
        Invoke-Doceterapia -Ctx $ctx -Argumentos @('aplicar', 'nao-existe') | Should Be 1
        Test-ChamadaDocker ' up ' | Should Be $false
    }

    It 'sem serviço, lista os nomes e não sobe nada' {
        Reset-DockerFalso -Regras @(@{ Padrao = 'config --services'; Codigo = 0; Saida = @('orquestrador') })
        $ctx = New-RaizDeTeste -Pasta (Join-Path $TestDrive 'a3')
        New-EnvPreenchido -Ctx $ctx
        Invoke-Doceterapia -Ctx $ctx -Argumentos @('aplicar') | Should Be 0
        Test-ChamadaDocker ' up ' | Should Be $false
    }
}
