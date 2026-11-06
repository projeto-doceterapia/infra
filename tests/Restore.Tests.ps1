. (Join-Path $PSScriptRoot 'Apoio.ps1')

function New-BackupFicticio {
    param(
        [Parameter(Mandatory = $true)][hashtable]$Ctx,
        [switch]$ComSessao
    )
    $pasta = Join-Path $Ctx.PastaBackups '2026-11-01_120000'
    $null = New-Item -ItemType Directory -Path $pasta -Force
    [System.IO.File]::WriteAllText((Join-Path $pasta 'banco.sql'), '-- dump ficticio')
    [System.IO.File]::WriteAllText((Join-Path $pasta 'info.txt'), "Data: 2026-11-01 12:00:00`nTags das imagens:`n  BACK_END_TAG=sha-antiga`n")
    if ($ComSessao) {
        [System.IO.File]::WriteAllText((Join-Path $pasta 'sessao-whatsapp.tgz'), 'ficticio')
    }
    return $pasta
}

Describe 'restore' {
    Mock Invoke-BackupDados { Join-Path $Ctx.PastaBackups 'seguranca' }
    Mock Invoke-Docker { Get-RespostaDockerFalso -Argumentos $Argumentos }

    $regrasNoAr = @(
        @{ Padrao = 'ps --status running'; Codigo = 0; Saida = @('abc123') },
        @{ Padrao = 'config --services'; Codigo = 0; Saida = @('banco-de-dados', 'back-end', 'orquestrador') }
    )

    Context 'sem argumento' {
        Reset-DockerFalso
        $ctx = New-RaizDeTeste -Pasta (Join-Path $TestDrive 'lista')
        $null = New-BackupFicticio -Ctx $ctx
        $resultado = Invoke-ComCaptura -Ctx $ctx -Argumentos @('restore')

        It 'lista os backups sem chamar o Docker' {
            $resultado.Codigo | Should Be 0
            $resultado.Texto | Should Match '2026-11-01_120000'
            $global:ChamadasDocker.Count | Should Be 0
        }
    }

    foreach ($digitado in 'restaurar', 'sim', '') {
        Context "confirmação errada: '$digitado'" {
            Mock Read-Entrada { $digitado }
            Reset-DockerFalso
            $ctx = New-RaizDeTeste -Pasta (Join-Path $TestDrive "errada$digitado")
            New-EnvPreenchido -Ctx $ctx
            $null = New-BackupFicticio -Ctx $ctx
            $resultado = Invoke-ComCaptura -Ctx $ctx -Argumentos @('restore', '2026-11-01_120000')

            It 'não muda nada e sai com 6' {
                $resultado.Codigo | Should Be 6
                $resultado.Texto | Should Match 'Nada foi alterado'
                $global:ChamadasDocker.Count | Should Be 0
                Assert-MockCalled Invoke-BackupDados -Times 0 -Exactly -Scope Context
            }
        }
    }

    Context 'confirmado' {
        Mock Read-Entrada { 'RESTAURAR' }
        Reset-DockerFalso -Regras $regrasNoAr
        $ctx = New-RaizDeTeste -Pasta (Join-Path $TestDrive 'ok')
        New-EnvPreenchido -Ctx $ctx
        $pasta = New-BackupFicticio -Ctx $ctx
        $resultado = Invoke-ComCaptura -Ctx $ctx -Argumentos @('restore', '2026-11-01_120000')
        $chamadas = @($global:ChamadasDocker)

        It 'termina com sucesso e mostra o conteúdo do backup' {
            $resultado.Codigo | Should Be 0
            $resultado.Texto | Should Match 'BACK_END_TAG=sha-antiga'
        }

        It 'faz o backup de segurança antes' {
            Assert-MockCalled Invoke-BackupDados -Times 1 -Exactly -Scope Context
        }

        It 'para os serviços que escrevem no banco e ignora os de outro perfil' {
            ($chamadas | Where-Object { $_ -match ' stop ' }) | Should Match 'stop back-end orquestrador$'
        }

        It 'importa pelo cliente dentro do container' {
            ($chamadas -match [regex]::Escape("cp $(Join-Path $pasta 'banco.sql') banco-de-dados:/tmp/doceterapia-banco.sql")).Count | Should Be 1
            ($chamadas -match 'mysqladmin -uroot -f drop \$MYSQL_DATABASE; mysqladmin -uroot create \$MYSQL_DATABASE && mysql -uroot \$MYSQL_DATABASE < /tmp/doceterapia-banco\.sql').Count | Should Be 1
        }

        It 'sobe tudo no fim, nessa ordem' {
            $ordemStop = [array]::FindIndex([string[]]$chamadas, [Predicate[string]] { param($c) $c -match ' stop ' })
            $ordemImport = [array]::FindIndex([string[]]$chamadas, [Predicate[string]] { param($c) $c -match 'mysqladmin' })
            $ordemUp = [array]::FindLastIndex([string[]]$chamadas, [Predicate[string]] { param($c) $c -match 'up -d --wait --wait-timeout 300$' })
            ($ordemStop -lt $ordemImport -and $ordemImport -lt $ordemUp) | Should Be $true
        }
    }

    Context 'com sessão do WhatsApp' {
        Mock Read-Entrada { 'RESTAURAR' }
        Reset-DockerFalso -Regras ($regrasNoAr + @(@{ Padrao = 'volume=adaptador-baileys-session'; Codigo = 0; Saida = @('doceterapia_adaptador-baileys-session') }))
        $ctx = New-RaizDeTeste -Pasta (Join-Path $TestDrive 'sessao')
        New-EnvPreenchido -Ctx $ctx
        $null = New-BackupFicticio -Ctx $ctx -ComSessao
        $codigo = Invoke-Doceterapia -Ctx $ctx -Argumentos @('restore', '2026-11-01_120000')

        It 'restaura a sessão no volume do adaptador' {
            $codigo | Should Be 0
            Test-ChamadaDocker '^run --rm --network none -v doceterapia_adaptador-baileys-session:/data -v .*:/backup:ro alpine:.* tar xzf /backup/sessao-whatsapp\.tgz' | Should Be $true
        }
    }

    Context 'falhas' {
        Mock Read-Entrada { 'RESTAURAR' }

        It 'importação com erro sai com 7 e aponta o backup de segurança' {
            Reset-DockerFalso -Regras ($regrasNoAr + @(@{ Padrao = 'mysqladmin'; Codigo = 1 }))
            $ctx = New-RaizDeTeste -Pasta (Join-Path $TestDrive 'erro')
            New-EnvPreenchido -Ctx $ctx
            $null = New-BackupFicticio -Ctx $ctx
            $resultado = Invoke-ComCaptura -Ctx $ctx -Argumentos @('restore', '2026-11-01_120000')
            $resultado.Codigo | Should Be 7
            $resultado.Texto | Should Match 'seguranca'
        }

        It 'backup inexistente sai com 7 sem pedir confirmação' {
            Reset-DockerFalso
            $ctx = New-RaizDeTeste -Pasta (Join-Path $TestDrive 'inexistente')
            New-EnvPreenchido -Ctx $ctx
            Invoke-Doceterapia -Ctx $ctx -Argumentos @('restore', 'nao-existe') | Should Be 7
            Assert-MockCalled Read-Entrada -Times 0 -Exactly -Scope It
        }

        It 'sistema que não sobe depois sai com 4 e aponta o info.txt' {
            Reset-DockerFalso -Regras ($regrasNoAr + @(@{ Padrao = 'up -d --wait --wait-timeout 300$'; Codigo = 1 }))
            $ctx = New-RaizDeTeste -Pasta (Join-Path $TestDrive 'naosobe')
            New-EnvPreenchido -Ctx $ctx
            $null = New-BackupFicticio -Ctx $ctx
            $resultado = Invoke-ComCaptura -Ctx $ctx -Argumentos @('restore', '2026-11-01_120000')
            $resultado.Codigo | Should Be 4
            $resultado.Texto | Should Match 'info\.txt'
        }
    }
}
