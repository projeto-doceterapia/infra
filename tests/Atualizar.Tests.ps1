. (Join-Path $PSScriptRoot 'Apoio.ps1')

function New-EnvComTagAntiga {
    param([Parameter(Mandatory = $true)][hashtable]$Ctx)
    New-EnvPreenchido -Ctx $Ctx -Valores @{ BACK_END_TAG = 'sha-antiga' }
}

Describe 'atualizar' {
    Mock Invoke-Docker { Get-RespostaDockerFalso -Argumentos $Argumentos }
    Mock Read-Entrada { 'S' }
    Mock Invoke-BackupDados { Join-Path $Ctx.PastaBackups 'pasta-do-backup' }
    Mock Get-IpLocal { $null }

    Context 'sem diferença' {
        Reset-DockerFalso
        $ctx = New-RaizDeTeste -Pasta (Join-Path $TestDrive 'igual')
        New-EnvPreenchido -Ctx $ctx
        $resultado = Invoke-ComCaptura -Ctx $ctx -Argumentos @('atualizar')

        It 'diz que já está na versão mais nova e sai com 0' {
            $resultado.Codigo | Should Be 0
            $resultado.Texto | Should Match 'Já está na versão mais nova'
            Assert-MockCalled Invoke-BackupDados -Times 0 -Exactly -Scope Context
        }
    }

    Context 'atualização completa' {
        Reset-DockerFalso
        $ctx = New-RaizDeTeste -Pasta (Join-Path $TestDrive 'ok')
        New-EnvComTagAntiga -Ctx $ctx
        $segredo = Read-ValorDoEnv -Ctx $ctx -Chave 'MYSQL_ROOT_PASSWORD'
        $tagNova = Get-ValorEnv -Linhas (Read-ArquivoEnv -Caminho $ctx.CaminhoExemplo) -Chave 'BACK_END_TAG'

        # A key the release added, with a value the launcher must generate.
        $linhas = Read-ArquivoEnv -Caminho $ctx.CaminhoEnv
        $semToken = New-ListaLinhas
        foreach ($linha in $linhas) {
            if ($linha -notmatch '^(ORQUESTRADOR_TOKEN|COOKIE_SECURE)=') { $semToken.Add($linha) }
        }
        Write-ArquivoEnv -Ctx $ctx -Linhas $semToken

        $resultado = Invoke-ComCaptura -Ctx $ctx -Argumentos @('atualizar')

        It 'mostra de e para' {
            $resultado.Codigo | Should Be 0
            $resultado.Texto | Should Match "BACK_END_TAG: sha-antiga -> $tagNova"
        }

        It 'troca a tag e completa as chaves novas, sem mexer nas existentes' {
            Read-ValorDoEnv -Ctx $ctx -Chave 'BACK_END_TAG' | Should Be $tagNova
            Read-ValorDoEnv -Ctx $ctx -Chave 'COOKIE_SECURE' | Should Be 'false'
            Read-ValorDoEnv -Ctx $ctx -Chave 'ORQUESTRADOR_TOKEN' | Should Match '^[A-Za-z0-9_-]{43}$'
            Read-ValorDoEnv -Ctx $ctx -Chave 'MYSQL_ROOT_PASSWORD' | Should Be $segredo
        }

        It 'baixa e sobe' {
            Test-ChamadaDocker ' pull$' | Should Be $true
            Test-ChamadaDocker 'up -d --wait --wait-timeout 300$' | Should Be $true
        }
    }

    Context 'recusa da confirmação' {
        Mock Read-Entrada { 'N' }
        Reset-DockerFalso
        $ctx = New-RaizDeTeste -Pasta (Join-Path $TestDrive 'nao')
        New-EnvComTagAntiga -Ctx $ctx
        $codigo = Invoke-Doceterapia -Ctx $ctx -Argumentos @('atualizar')

        It 'sai com 6 sem mudar nada' {
            $codigo | Should Be 6
            Read-ValorDoEnv -Ctx $ctx -Chave 'BACK_END_TAG' | Should Be 'sha-antiga'
            Assert-MockCalled Invoke-BackupDados -Times 0 -Exactly -Scope Context
        }
    }

    Context 'backup com falha' {
        Mock Invoke-BackupDados { Stop-Launcher -Codigo $CODIGO_BACKUP -Mensagem 'falha ficticia' }
        Reset-DockerFalso
        $ctx = New-RaizDeTeste -Pasta (Join-Path $TestDrive 'backup')
        New-EnvComTagAntiga -Ctx $ctx
        $resultado = Invoke-ComCaptura -Ctx $ctx -Argumentos @('atualizar')

        It 'não muda as tags e sai com 7' {
            $resultado.Codigo | Should Be 7
            $resultado.Texto | Should Match 'O backup falhou; nada foi atualizado'
            Read-ValorDoEnv -Ctx $ctx -Chave 'BACK_END_TAG' | Should Be 'sha-antiga'
            Test-ChamadaDocker ' pull$' | Should Be $false
        }
    }

    foreach ($trecho in 'Migrations have failed validation', 'checksum mismatch') {
        Context "Flyway recusa: $trecho" {
            $logFlyway = "back-end  | ERROR $trecho for version 1"
            Reset-DockerFalso -Regras @(
                @{ Padrao = 'up -d --wait'; Codigo = 1 },
                @{ Padrao = 'logs --no-color'; Codigo = 0; Saida = @('linha comum', $logFlyway) }
            )
            $ctx = New-RaizDeTeste -Pasta (Join-Path $TestDrive "flyway$($trecho.Length)")
            New-EnvComTagAntiga -Ctx $ctx
            $resultado = Invoke-ComCaptura -Ctx $ctx -Argumentos @('atualizar')

            It 'indica resetar-banco com o backup, sai com 4 e não recria o banco' {
                $resultado.Codigo | Should Be 4
                $resultado.Texto | Should Match 'Esta versão mudou a estrutura do banco'
                $resultado.Texto | Should Match 'pasta-do-backup'
                $resultado.Texto | Should Match 'doceterapia resetar-banco'
                Test-ChamadaDocker 'volume rm' | Should Be $false
                Test-ChamadaDocker ' down' | Should Be $false
            }
        }
    }

    Context 'outra falha de saúde' {
        Reset-DockerFalso -Regras @(
            @{ Padrao = 'up -d --wait'; Codigo = 1 },
            @{ Padrao = 'logs --no-color'; Codigo = 0; Saida = @('linha comum') },
            @{ Padrao = 'ps -a --format json'; Codigo = 0; Saida = @('[{"Service":"redis","Health":"unhealthy"}]') }
        )
        $ctx = New-RaizDeTeste -Pasta (Join-Path $TestDrive 'outra')
        New-EnvComTagAntiga -Ctx $ctx
        $resultado = Invoke-ComCaptura -Ctx $ctx -Argumentos @('atualizar')

        It 'sai com 4 citando o serviço' {
            $resultado.Codigo | Should Be 4
            $resultado.Texto | Should Match 'O serviço redis não ficou pronto'
        }
    }
}
