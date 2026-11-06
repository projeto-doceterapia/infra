. (Join-Path $PSScriptRoot 'Apoio.ps1')

Describe 'init' {
    Mock Invoke-Docker { Get-RespostaDockerFalso -Argumentos $Argumentos }
    Mock Invoke-ComandoDoctor { }
    Mock Read-SenhaOculta {
        if ($Pergunta -match 'DONA|Repita') { return $SENHA_FICTICIA }
        return ''
    }
    Mock Read-Entrada {
        if ($Pergunta -match 'E-mail') { return 'dona@exemplo.com' }
        if ($Pergunta -match 'demonstra') { return 'S' }
        return ''
    }

    Context 'primeira execução' {
        Reset-DockerFalso
        $ctx = New-RaizDeTeste -Pasta (Join-Path $TestDrive 'nova')
        $codigo = Invoke-Doceterapia -Ctx $ctx -Argumentos @('init')
        $linhas = Read-ArquivoEnv -Caminho $ctx.CaminhoEnv

        It 'termina com sucesso e valida o compose' {
            $codigo | Should Be 0
            Test-ChamadaDocker 'config --quiet' | Should Be $true
        }

        It 'gera JWT_SECRET de 48 bytes no lugar do marcador público' {
            $jwt = Get-ValorEnv -Linhas $linhas -Chave 'JWT_SECRET'
            $jwt -match '^replaceme' | Should Be $false
            ([Convert]::FromBase64String($jwt)).Length | Should Be 48
        }

        It 'gera os demais segredos só com caracteres seguros' {
            foreach ($chave in $SEGREDOS_URL_SAFE) {
                Get-ValorEnv -Linhas $linhas -Chave $chave | Should Match '^[A-Za-z0-9_-]{43}$'
            }
        }

        It 'mantém as igualdades entre as variáveis' {
            Get-ValorEnv -Linhas $linhas -Chave 'DB_PASSWORD' | Should Be (Get-ValorEnv -Linhas $linhas -Chave 'MYSQL_PASSWORD')
            $redis = Get-ValorEnv -Linhas $linhas -Chave 'REDIS_PASSWORD'
            Get-ValorEnv -Linhas $linhas -Chave 'ORQUESTRADOR_REDIS_URL' | Should Be "redis://:$redis@redis:6379/0"
        }

        It 'grava e-mail, senha entre aspas e dados de demonstração' {
            Get-ValorEnv -Linhas $linhas -Chave 'ADMIN_EMAIL' | Should Be 'dona@exemplo.com'
            Get-ValorEnv -Linhas $linhas -Chave 'ADMIN_SENHA' | Should Be $SENHA_FICTICIA
            ($linhas -ccontains "ADMIN_SENHA='$SENHA_FICTICIA'") | Should Be $true
            Get-ValorEnv -Linhas $linhas -Chave 'DEMO_DATA' | Should Be 'true'
        }

        It 'deixa os tokens adiados como replace-me' {
            foreach ($chave in 'CLOUD_API_TOKEN', 'CLOUD_API_APP_SECRET', 'CLOUD_API_PHONE_ID', 'GEMINI_API_KEY', 'NGROK_AUTHTOKEN') {
                Get-ValorEnv -Linhas $linhas -Chave $chave | Should Be 'replace-me'
            }
            Get-ValorEnv -Linhas $linhas -Chave 'NGROK_DOMAIN' | Should Be 'replace-me.ngrok-free.app'
        }

        It 'não gera sozinho o domínio do ngrok nem deixa vazia a linha de CORS' {
            ($linhas -ccontains 'CORS_ALLOWED_ORIGINS=') | Should Be $true
        }
    }

    Context 'exemplo com CRLF' {
        Reset-DockerFalso
        $ctx = New-RaizDeTeste -Pasta (Join-Path $TestDrive 'crlf') -ExemploCrlf
        $null = Invoke-Doceterapia -Ctx $ctx -Argumentos @('init')

        It 'não deixa CR no arquivo gerado' {
            ([System.IO.File]::ReadAllBytes($ctx.CaminhoEnv) -contains 13) | Should Be $false
        }
    }

    Context 'idempotente' {
        Reset-DockerFalso
        $ctx = New-RaizDeTeste -Pasta (Join-Path $TestDrive 'idempotente')
        $null = Invoke-Doceterapia -Ctx $ctx -Argumentos @('init')
        $primeira = Read-ArquivoEnv -Caminho $ctx.CaminhoEnv

        # A key the example gained later, and an external token filled afterwards.
        $linhas = Read-ArquivoEnv -Caminho $ctx.CaminhoEnv
        Set-ValorEnv -Linhas $linhas -Chave 'GEMINI_API_KEY' -Valor "'chave-ficticia'"
        $semChave = New-ListaLinhas
        foreach ($linha in $linhas) {
            if ($linha -notmatch '^(COOKIE_SECURE|ORQUESTRADOR_TOKEN)=') { $semChave.Add($linha) }
        }
        Write-ArquivoEnv -Ctx $ctx -Linhas $semChave
        $null = Invoke-Doceterapia -Ctx $ctx -Argumentos @('init')
        $segunda = Read-ArquivoEnv -Caminho $ctx.CaminhoEnv

        It 'não troca nenhum segredo existente' {
            foreach ($chave in 'JWT_SECRET', 'MYSQL_ROOT_PASSWORD', 'MYSQL_PASSWORD', 'DB_PASSWORD', 'REDIS_PASSWORD', 'ORQUESTRADOR_REDIS_URL', 'ADAPTER_SECRET', 'WEBHOOK_SECRET', 'CLOUD_API_VERIFY_TOKEN', 'ADMIN_SENHA') {
                Get-ValorEnv -Linhas $segunda -Chave $chave | Should Be (Get-ValorEnv -Linhas $primeira -Chave $chave)
            }
        }

        It 'mantém o token externo preenchido' {
            Get-ValorEnv -Linhas $segunda -Chave 'GEMINI_API_KEY' | Should Be 'chave-ficticia'
        }

        It 'completa as chaves novas' {
            Get-ValorEnv -Linhas $segunda -Chave 'COOKIE_SECURE' | Should Be 'false'
            Get-ValorEnv -Linhas $segunda -Chave 'ORQUESTRADOR_TOKEN' | Should Match '^[A-Za-z0-9_-]{43}$'
        }
    }

    Context 'banco já existe' {
        Reset-DockerFalso -Regras @(@{ Padrao = 'volume ls'; Codigo = 0; Saida = @('doceterapia_banco-de-dados-data') })
        $ctx = New-RaizDeTeste -Pasta (Join-Path $TestDrive 'existente')
        $null = Invoke-Doceterapia -Ctx $ctx -Argumentos @('init')

        It 'não pede a senha da DONA nem muda DEMO_DATA' {
            Read-ValorDoEnv -Ctx $ctx -Chave 'ADMIN_SENHA' | Should BeNullOrEmpty
            Read-ValorDoEnv -Ctx $ctx -Chave 'DEMO_DATA' | Should Be 'false'
        }
    }

    Context 'doctor com falha' {
        Mock Invoke-ComandoDoctor { Stop-Launcher -Codigo $CODIGO_PRE_REQUISITO -Mensagem 'falha' }
        Reset-DockerFalso
        $ctx = New-RaizDeTeste -Pasta (Join-Path $TestDrive 'semdocker')
        $codigo = Invoke-Doceterapia -Ctx $ctx -Argumentos @('init')

        It 'bloqueia sem criar a configuração' {
            $codigo | Should Be 2
            Test-Path -LiteralPath $ctx.CaminhoEnv | Should Be $false
        }
    }
}

Describe 'validação das respostas' {
    Mock Read-Entrada { 'dona@exemplo.com' }

    It 'recusa senha curta, longa, com aspa ou que não confere' {
        Test-SenhaDonaValida '12345' | Should Be $false
        Test-SenhaDonaValida ('x' * 21) | Should Be $false
        Test-SenhaDonaValida "abc'def" | Should Be $false
        Test-SenhaDonaValida '123456' | Should Be $true
        Test-SenhaDonaValida ('x' * 20) | Should Be $true
    }

    It 'pede a senha duas vezes' {
        Mock Read-SenhaOculta { 'SenhaFicticia1' }
        $credenciais = Read-CredenciaisDona
        $credenciais.Senha | Should Be 'SenhaFicticia1'
        Assert-MockCalled Read-SenhaOculta -Times 2 -Exactly -Scope It
    }

    It 'desiste após senhas curtas repetidas, com mensagem em português' {
        Mock Read-SenhaOculta { '123' }
        { Read-CredenciaisDona } | Should Throw 'Senha não aceita'
    }

    It 'pergunta de novo quando a confirmação não confere' {
        $global:TentativaSenha = 0
        Mock Read-SenhaOculta {
            $global:TentativaSenha++
            if ($global:TentativaSenha -eq 2) { return 'OutraSenha1' }
            return 'SenhaFicticia1'
        }
        (Read-CredenciaisDona).Senha | Should Be 'SenhaFicticia1'
        Assert-MockCalled Read-SenhaOculta -Times 4 -Exactly -Scope It
    }

    It 'valida o e-mail' {
        Test-EmailValido 'dona@exemplo.com' | Should Be $true
        Test-EmailValido 'dona' | Should Be $false
        Test-EmailValido "do'na@exemplo.com" | Should Be $false
    }

    It 'grava valor com $ de forma literal' {
        $linhas = New-ListaLinhas
        Set-CredenciaisDona -Linhas $linhas -Credenciais @{ Email = 'dona@exemplo.com'; Senha = 'a$b#c1' }
        ($linhas -ccontains "ADMIN_SENHA='a`$b#c1'") | Should Be $true
    }
}
