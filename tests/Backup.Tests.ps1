. (Join-Path $PSScriptRoot 'Apoio.ps1')

function Set-DumpFalso {
    # Stands in for "docker compose cp": creates the file the command would copy.
    Mock Invoke-Docker {
        $resposta = Get-RespostaDockerFalso -Argumentos $Argumentos
        if (($Argumentos -join ' ') -match ' cp banco-de-dados:' -and $resposta.Codigo -eq 0) {
            [System.IO.File]::WriteAllText($Argumentos[-1], '-- dump ficticio')
        }
        return $resposta
    }
}

$PILHA_NO_AR = @{ Padrao = 'ps --status running'; Codigo = 0; Saida = @('abc123') }

Describe 'backup' {
    Set-DumpFalso

    Context 'pilha no ar, canal cloud_api' {
        Reset-DockerFalso -Regras @($PILHA_NO_AR)
        $ctx = New-RaizDeTeste -Pasta (Join-Path $TestDrive 'Nome Sobrenome\ok')
        New-EnvPreenchido -Ctx $ctx
        $resultado = Invoke-ComCaptura -Ctx $ctx -Argumentos @('backup')
        $pasta = @(Get-ChildItem -LiteralPath $ctx.PastaBackups -Directory)[0]

        It 'cria a pasta com data e hora e mostra o caminho' {
            $resultado.Codigo | Should Be 0
            $pasta.Name | Should Match '^\d{4}-\d{2}-\d{2}_\d{6}$'
            $resultado.Texto | Should Match ([regex]::Escape($pasta.FullName))
        }

        It 'gera o dump dentro do container, sem passar a senha pelo host' {
            Test-ChamadaDocker 'exec -T banco-de-dados sh -c MYSQL_PWD=\$MYSQL_ROOT_PASSWORD mysqldump .*--no-tablespaces --single-transaction --routines --result-file=/tmp/doceterapia-banco\.sql \$MYSQL_DATABASE' | Should Be $true
            Test-ChamadaDocker 'exec -T banco-de-dados rm -f /tmp/doceterapia-banco\.sql' | Should Be $true
        }

        It 'pula a sessão do WhatsApp com aviso, sem falhar' {
            $resultado.Texto | Should Match 'Sem sessão do WhatsApp'
            Test-ChamadaDocker '^run ' | Should Be $false
        }

        It 'grava info.txt com as tags e sem segredos' {
            $info = [System.IO.File]::ReadAllText((Join-Path $pasta.FullName 'info.txt'))
            $info | Should Match 'BACK_END_TAG='
            $info | Should Not Match (Read-ValorDoEnv -Ctx $ctx -Chave 'MYSQL_ROOT_PASSWORD')
        }

        It 'não sobe nem para o banco' {
            Test-ChamadaDocker 'up -d' | Should Be $false
            Test-ChamadaDocker ' stop ' | Should Be $false
        }
    }

    Context 'com sessão do WhatsApp' {
        Reset-DockerFalso -Regras @($PILHA_NO_AR, @{ Padrao = 'volume=adaptador-baileys-session'; Codigo = 0; Saida = @('doceterapia_adaptador-baileys-session') })
        $ctx = New-RaizDeTeste -Pasta (Join-Path $TestDrive 'sessao')
        New-EnvPreenchido -Ctx $ctx
        $codigo = Invoke-Doceterapia -Ctx $ctx -Argumentos @('backup')

        It 'empacota o volume em modo leitura com a imagem fixada' {
            $codigo | Should Be 0
            $tag = Read-ValorDoEnv -Ctx $ctx -Chave 'ALPINE_TAG'
            $tag | Should Not BeNullOrEmpty
            Test-ChamadaDocker "^run --rm --network none -v doceterapia_adaptador-baileys-session:/data:ro -v .*:/backup alpine:$tag tar czf /backup/sessao-whatsapp\.tgz -C /data \." | Should Be $true
        }
    }

    Context 'banco parado' {
        Reset-DockerFalso
        $ctx = New-RaizDeTeste -Pasta (Join-Path $TestDrive 'parado')
        New-EnvPreenchido -Ctx $ctx
        $codigo = Invoke-Doceterapia -Ctx $ctx -Argumentos @('backup')

        It 'liga só o banco e o deixa parado de novo' {
            $codigo | Should Be 0
            Test-ChamadaDocker 'up -d --wait --wait-timeout 300 banco-de-dados$' | Should Be $true
            Test-ChamadaDocker ' stop banco-de-dados$' | Should Be $true
        }
    }

    Context 'falhas' {
        It 'falha do dump sai com 7' {
            Reset-DockerFalso -Regras @($PILHA_NO_AR, @{ Padrao = 'mysqldump'; Codigo = 1 })
            $ctx = New-RaizDeTeste -Pasta (Join-Path $TestDrive 'dump')
            New-EnvPreenchido -Ctx $ctx
            Invoke-Doceterapia -Ctx $ctx -Argumentos @('backup') | Should Be 7
        }

        It 'dump vazio sai com 7' {
            Mock Invoke-Docker { Get-RespostaDockerFalso -Argumentos $Argumentos }
            Reset-DockerFalso -Regras @($PILHA_NO_AR)
            $ctx = New-RaizDeTeste -Pasta (Join-Path $TestDrive 'vazio')
            New-EnvPreenchido -Ctx $ctx
            Invoke-Doceterapia -Ctx $ctx -Argumentos @('backup') | Should Be 7
        }

        It 'sem configuração sai com 3' {
            Reset-DockerFalso
            $ctx = New-RaizDeTeste -Pasta (Join-Path $TestDrive 'semenv')
            Invoke-Doceterapia -Ctx $ctx -Argumentos @('backup') | Should Be 3
        }
    }
}
