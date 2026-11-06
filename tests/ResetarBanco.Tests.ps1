. (Join-Path $PSScriptRoot 'Apoio.ps1')

$VOLUME_REGRA = @{ Padrao = 'volume=banco-de-dados-data'; Codigo = 0; Saida = @('doceterapia_banco-de-dados-data') }

Describe 'resetar-banco' {
    Mock Invoke-Docker { Get-RespostaDockerFalso -Argumentos $Argumentos }
    Mock Invoke-BackupDados { Join-Path $Ctx.PastaBackups 'pasta-do-backup' }
    Mock Read-SenhaOculta { $SENHA_FICTICIA }
    Mock Invoke-LoginUsuario { 200 }
    Mock Get-IpLocal { $null }
    Mock Read-Entrada {
        if ($Pergunta -match 'APAGAR') { return 'APAGAR' }
        if ($Pergunta -match 'Nome') { return 'Nova Fictícia' }
        if ($Pergunta -match 'E-mail') { return 'nova@exemplo.com' }
        if ($Pergunta -match 'demonstra') { return 'S' }
        return ''
    }

    Context 'confirmado' {
        Reset-DockerFalso -Regras @($VOLUME_REGRA)
        $ctx = New-RaizDeTeste -Pasta (Join-Path $TestDrive 'ok')
        New-EnvPreenchido -Ctx $ctx -Valores @{ DEMO_DATA = 'false' }
        $segredo = Read-ValorDoEnv -Ctx $ctx -Chave 'MYSQL_ROOT_PASSWORD'
        $resultado = Invoke-ComCaptura -Ctx $ctx -Argumentos @('resetar-banco')
        $chamadas = @($global:ChamadasDocker)

        It 'termina com sucesso, depois do backup' {
            $resultado.Codigo | Should Be 0
            Assert-MockCalled Invoke-BackupDados -Times 1 -Exactly -Scope Context
        }

        It 'remove só o volume do banco, identificado pelo rótulo' {
            $remocoes = @($chamadas | Where-Object { $_ -match 'volume rm' })
            $remocoes.Count | Should Be 1
            $remocoes[0] | Should Be 'volume rm doceterapia_banco-de-dados-data'
            Test-ChamadaDocker 'label=com\.docker\.compose\.project=doceterapia --filter label=com\.docker\.compose\.volume=banco-de-dados-data' | Should Be $true
        }

        It 'nunca toca nos volumes do Redis e da sessão' {
            Test-ChamadaDocker 'volume rm .*redis' | Should Be $false
            Test-ChamadaDocker 'volume rm .*adaptador' | Should Be $false
        }

        It 'para a pilha sem apagar volumes e depois sobe' {
            $paradas = @($chamadas | Where-Object { $_ -match ' down' })
            $paradas.Count | Should Be 1
            $paradas[0] | Should Match ' down$'
            Test-ChamadaDocker 'up -d --wait --wait-timeout 300$' | Should Be $true
        }

        It 'aplica as novas respostas, apaga a senha após o login e mantém os segredos' {
            Read-ValorDoEnv -Ctx $ctx -Chave 'DEMO_DATA' | Should Be 'true'
            Read-ValorDoEnv -Ctx $ctx -Chave 'ADMIN_NOME' | Should Be 'Nova Fictícia'
            Read-ValorDoEnv -Ctx $ctx -Chave 'ADMIN_EMAIL' | Should Be 'nova@exemplo.com'
            Read-ValorDoEnv -Ctx $ctx -Chave 'ADMIN_SENHA' | Should BeNullOrEmpty
            Read-ValorDoEnv -Ctx $ctx -Chave 'MYSQL_ROOT_PASSWORD' | Should Be $segredo
            Assert-MockCalled Invoke-LoginUsuario -Times 1 -Exactly -Scope Context
        }
    }

    Context 'sem digitar APAGAR' {
        Mock Read-Entrada { 'apagar' }
        Reset-DockerFalso -Regras @($VOLUME_REGRA)
        $ctx = New-RaizDeTeste -Pasta (Join-Path $TestDrive 'nao')
        New-EnvPreenchido -Ctx $ctx
        $codigo = Invoke-Doceterapia -Ctx $ctx -Argumentos @('resetar-banco')

        It 'sai com 6 sem backup nem remoção' {
            $codigo | Should Be 6
            Assert-MockCalled Invoke-BackupDados -Times 0 -Exactly -Scope Context
            Test-ChamadaDocker 'volume rm' | Should Be $false
        }
    }

    Context 'backup com falha' {
        Mock Invoke-BackupDados { Stop-Launcher -Codigo $CODIGO_BACKUP -Mensagem 'falha ficticia' }
        Reset-DockerFalso -Regras @($VOLUME_REGRA)
        $ctx = New-RaizDeTeste -Pasta (Join-Path $TestDrive 'backup')
        New-EnvPreenchido -Ctx $ctx -Valores @{ DEMO_DATA = 'false' }
        $codigo = Invoke-Doceterapia -Ctx $ctx -Argumentos @('resetar-banco')

        It 'sai com 7 sem parar a pilha, apagar nem gravar a configuração' {
            $codigo | Should Be 7
            Test-ChamadaDocker ' down' | Should Be $false
            Test-ChamadaDocker 'volume rm' | Should Be $false
            Read-ValorDoEnv -Ctx $ctx -Chave 'DEMO_DATA' | Should Be 'false'
            Read-ValorDoEnv -Ctx $ctx -Chave 'ADMIN_SENHA' | Should BeNullOrEmpty
        }
    }

    Context 'senha inválida' {
        Mock Read-SenhaOculta { '123' }
        Reset-DockerFalso -Regras @($VOLUME_REGRA)
        $ctx = New-RaizDeTeste -Pasta (Join-Path $TestDrive 'senha')
        New-EnvPreenchido -Ctx $ctx
        $codigo = Invoke-Doceterapia -Ctx $ctx -Argumentos @('resetar-banco')

        It 'desiste antes de apagar qualquer coisa' {
            $codigo | Should Be 1
            Test-ChamadaDocker 'volume rm' | Should Be $false
            Assert-MockCalled Invoke-BackupDados -Times 0 -Exactly -Scope Context
        }
    }

    Context 'mais de um volume com o mesmo rótulo' {
        Reset-DockerFalso -Regras @(@{ Padrao = 'volume=banco-de-dados-data'; Codigo = 0; Saida = @('um', 'dois') })
        $ctx = New-RaizDeTeste -Pasta (Join-Path $TestDrive 'dois')
        New-EnvPreenchido -Ctx $ctx
        $codigo = Invoke-Doceterapia -Ctx $ctx -Argumentos @('resetar-banco')

        It 'não apaga nada' {
            $codigo | Should Be 1
            Test-ChamadaDocker 'volume rm' | Should Be $false
        }
    }

    Context 'projeto isolado' {
        $env:COMPOSE_PROJECT_NAME = 'projeto-de-teste'
        try {
            Reset-DockerFalso
            $ctx = New-RaizDeTeste -Pasta (Join-Path $TestDrive 'isolado')
            $ctx.Projeto = Get-NomeProjeto -CaminhoEnv $ctx.CaminhoEnv
            New-EnvPreenchido -Ctx $ctx
            $null = Invoke-Doceterapia -Ctx $ctx -Argumentos @('resetar-banco')
        }
        finally {
            Remove-Item Env:\COMPOSE_PROJECT_NAME
        }

        It 'procura o volume pelo nome do projeto que o compose usa' {
            Test-ChamadaDocker 'label=com\.docker\.compose\.project=projeto-de-teste ' | Should Be $true
            Test-ChamadaDocker 'label=com\.docker\.compose\.project=doceterapia ' | Should Be $false
        }
    }
}
