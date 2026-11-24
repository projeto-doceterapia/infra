. (Join-Path $PSScriptRoot 'Apoio.ps1')

function New-LinhasExemplo {
    param([hashtable]$Valores = @{})
    $linhas = Read-ArquivoEnv -Caminho (Join-Path $RAIZ_REPOSITORIO '.env.example')
    foreach ($chave in $Valores.Keys) {
        Set-ValorEnv -Linhas $linhas -Chave $chave -Valor $Valores[$chave]
    }
    return , $linhas
}

Describe 'validação das janelas' {
    It 'aponta cada campo inválido da DONA' {
        $erros = Get-ErrosDaDona -Nome 'Al' -Email 'sem-arroba' -Senha '123' -Confirmacao '123'
        @($erros.Keys | Sort-Object) -join ',' | Should Be 'Email,Nome,Senha'
    }

    It 'aceita nome em branco e exige senhas iguais' {
        $erros = Get-ErrosDaDona -Nome '' -Email 'dona@exemplo.com' -Senha $SENHA_FICTICIA -Confirmacao 'OutraSenha1'
        @($erros.Keys) -join ',' | Should Be 'Confirmacao'
        (Get-ErrosDaDona -Nome '' -Email 'dona@exemplo.com' -Senha $SENHA_FICTICIA -Confirmacao $SENHA_FICTICIA).Count | Should Be 0
    }

    It 'aponta telefone, domínio, canal e chave inválidos e ignora os em branco' {
        $erros = Get-ErrosDoAssistente -Valores @{
            CHANNEL               = 'sms'
            BENEFICIARIA_TELEFONE = '11900000001'
            NGROK_DOMAIN          = 'dominio com espaço'
            GEMINI_API_KEY        = "com'aspas"
            CLOUD_API_TOKEN       = ''
        }
        @($erros.Keys | Sort-Object) -join ',' | Should Be 'BENEFICIARIA_TELEFONE,CHANNEL,GEMINI_API_KEY,NGROK_DOMAIN'
    }

    It 'grava só os valores informados e normaliza o domínio' {
        $linhas = New-LinhasExemplo
        Set-ValoresDoAssistente -Linhas $linhas -Valores @{ NGROK_DOMAIN = 'https://meu-dominio.ngrok-free.app/'; GEMINI_API_KEY = 'chave-ficticia-gemini'; CLOUD_API_TOKEN = '' }
        Get-ValorEnv -Linhas $linhas -Chave 'NGROK_DOMAIN' | Should Be 'meu-dominio.ngrok-free.app'
        Get-ValorEnv -Linhas $linhas -Chave 'GEMINI_API_KEY' | Should Be 'chave-ficticia-gemini'
        Get-ValorEnv -Linhas $linhas -Chave 'CLOUD_API_TOKEN' | Should Be 'replace-me'
    }

    It 'pede a DONA só sem banco e sem e-mail ou senha' {
        Test-DonaPendente -Linhas (New-LinhasExemplo) -BancoExiste $false | Should Be $true
        Test-DonaPendente -Linhas (New-LinhasExemplo) -BancoExiste $true | Should Be $false
        Test-DonaPendente -Linhas (New-LinhasExemplo -Valores @{ ADMIN_EMAIL = 'dona@exemplo.com'; ADMIN_SENHA = "'$SENHA_FICTICIA'" }) -BancoExiste $false | Should Be $false
    }
}

Describe 'init com as respostas do assistente' {
    Mock Invoke-Docker { Get-RespostaDockerFalso -Argumentos $Argumentos }
    Mock Invoke-ComandoDoctor { }
    Mock Read-Entrada { throw 'must not ask on the console' }
    Mock Read-SenhaOculta { throw 'must not ask on the console' }

    Context 'respostas válidas' {
        Reset-DockerFalso
        $ctx = New-RaizDeTeste -Pasta (Join-Path $TestDrive 'valido')
        $ctx.Respostas = @{
            Dona    = @{ Nome = 'Maria Fictícia'; Email = 'dona@exemplo.com'; Senha = $SENHA_FICTICIA }
            Demo    = $true
            Valores = @{ CHANNEL = 'baileys'; BENEFICIARIA_TELEFONE = '+5511900000002'; GEMINI_API_KEY = 'chave-ficticia-gemini' }
        }
        $codigo = Invoke-Doceterapia -Ctx $ctx -Argumentos @('init') 6>$null

        It 'grava tudo sem perguntar nada' {
            $codigo | Should Be 0
            Read-ValorDoEnv -Ctx $ctx -Chave 'ADMIN_NOME' | Should Be 'Maria Fictícia'
            Read-ValorDoEnv -Ctx $ctx -Chave 'ADMIN_SENHA' | Should Be $SENHA_FICTICIA
            Read-ValorDoEnv -Ctx $ctx -Chave 'DEMO_DATA' | Should Be 'true'
            Read-ValorDoEnv -Ctx $ctx -Chave 'CHANNEL' | Should Be 'baileys'
            Read-ValorDoEnv -Ctx $ctx -Chave 'BENEFICIARIA_TELEFONE' | Should Be '+5511900000002'
            Read-ValorDoEnv -Ctx $ctx -Chave 'GEMINI_API_KEY' | Should Be 'chave-ficticia-gemini'
            Read-ValorDoEnv -Ctx $ctx -Chave 'CLOUD_API_TOKEN' | Should Be 'replace-me'
        }
    }

    Context 'e-mail inválido' {
        Reset-DockerFalso
        $ctx = New-RaizDeTeste -Pasta (Join-Path $TestDrive 'invalido')
        $ctx.Respostas = @{ Dona = @{ Nome = ''; Email = 'sem-arroba'; Senha = $SENHA_FICTICIA }; Demo = $false; Valores = @{} }
        $codigo = Invoke-Doceterapia -Ctx $ctx -Argumentos @('init') 6>$null

        It 'recusa sem criar a configuração' {
            $codigo | Should Be 1
            Test-Path -LiteralPath $ctx.CaminhoEnv | Should Be $false
        }
    }
}

Describe 'plano de reinício' {
    $comTunel = @{ NGROK_AUTHTOKEN = "'token-ficticio-ngrok'"; NGROK_DOMAIN = 'meu-dominio.ngrok-free.app' }

    It 'reinicia só o orquestrador quando muda a chave do Gemini' {
        $plano = Get-PlanoDeReinicio -Antes (New-LinhasExemplo) -Depois (New-LinhasExemplo -Valores @{ GEMINI_API_KEY = "'chave-ficticia-gemini'" })
        $plano.Completo | Should Be $false
        $plano.Servicos -join ',' | Should Be 'orquestrador'
    }

    It 'desliga e liga tudo quando muda o canal' {
        $plano = Get-PlanoDeReinicio -Antes (New-LinhasExemplo) -Depois (New-LinhasExemplo -Valores @{ CHANNEL = 'baileys' })
        $plano.Completo | Should Be $true
    }

    It 'desliga e liga tudo quando o túnel passa a ter credenciais' {
        $plano = Get-PlanoDeReinicio -Antes (New-LinhasExemplo) -Depois (New-LinhasExemplo -Valores $comTunel)
        $plano.Completo | Should Be $true
    }

    It 'reinicia o ngrok só quando o túnel já está ativo' {
        $depois = New-LinhasExemplo -Valores $comTunel
        Set-ValorEnv -Linhas $depois -Chave 'NGROK_DOMAIN' -Valor 'outro-dominio.ngrok-free.app'
        $plano = Get-PlanoDeReinicio -Antes (New-LinhasExemplo -Valores $comTunel) -Depois $depois
        $plano.Completo | Should Be $false
        $plano.Servicos -join ',' | Should Be 'ngrok'
    }

    It 'não reinicia nada sem mudança' {
        $plano = Get-PlanoDeReinicio -Antes (New-LinhasExemplo) -Depois (New-LinhasExemplo)
        $plano.Completo | Should Be $false
        @($plano.Servicos).Count | Should Be 0
    }
}

Describe 'configurações salvas' {
    Mock Invoke-Docker { Get-RespostaDockerFalso -Argumentos $Argumentos }

    Context 'gravação' {
        $ctx = New-RaizDeTeste -Pasta (Join-Path $TestDrive 'salvar')
        New-EnvPreenchido -Ctx $ctx

        It 'sem mudança, não grava nem planeja' {
            Save-Configuracoes -Ctx $ctx -Valores @{ CHANNEL = 'cloud_api'; CLOUD_API_TOKEN = '' } | Should Be $null
        }

        It 'com mudança, grava e devolve o plano' {
            $plano = Save-Configuracoes -Ctx $ctx -Valores @{ CHANNEL = 'cloud_api'; GEMINI_API_KEY = 'chave-ficticia-gemini' }
            $plano.Servicos -join ',' | Should Be 'orquestrador'
            Read-ValorDoEnv -Ctx $ctx -Chave 'GEMINI_API_KEY' | Should Be 'chave-ficticia-gemini'
        }
    }

    Context 'aplicação com o sistema ligado' {
        Reset-DockerFalso -Regras @(@{ Padrao = 'ps --services --status running'; Codigo = 0; Saida = @('back-end', 'orquestrador') })
        $ctx = New-RaizDeTeste -Pasta (Join-Path $TestDrive 'ligado')
        New-EnvPreenchido -Ctx $ctx
        $codigo = Invoke-ComTratamento -Acao { Invoke-PlanoDeReinicio -Ctx $ctx -Plano ([pscustomobject]@{ Completo = $false; Servicos = @('orquestrador') }) } 6>$null

        It 'recria só o serviço afetado' {
            $codigo | Should Be 0
            Test-ChamadaDocker 'up -d --wait --wait-timeout 300 orquestrador$' | Should Be $true
            Test-ChamadaDocker ' down' | Should Be $false
        }
    }

    Context 'aplicação com o sistema desligado' {
        Reset-DockerFalso
        $ctx = New-RaizDeTeste -Pasta (Join-Path $TestDrive 'desligado')
        New-EnvPreenchido -Ctx $ctx
        $resultado = @(Invoke-PlanoDeReinicio -Ctx $ctx -Plano ([pscustomobject]@{ Completo = $true; Servicos = @() }) 6>&1 | ForEach-Object { "$_" }) -join "`n"

        It 'só avisa que vale na próxima vez' {
            $resultado | Should Match 'vale quando o sistema for ligado'
            Test-ChamadaDocker ' up ' | Should Be $false
            Test-ChamadaDocker ' down' | Should Be $false
        }
    }
}
