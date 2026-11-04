. (Join-Path $PSScriptRoot 'Apoio.ps1')

Describe 'down' {
    Mock Invoke-Docker { Get-RespostaDockerFalso -Argumentos $Argumentos }

    foreach ($argumento in '-v', '--volumes', '-V', 'qualquer') {
        It "recusa $argumento com 1, sem chamar o Docker" {
            Reset-DockerFalso
            $ctx = New-RaizDeTeste -Pasta (Join-Path $TestDrive "recusa$($argumento.Trim('-'))")
            New-EnvPreenchido -Ctx $ctx
            $resultado = Invoke-ComCaptura -Ctx $ctx -Argumentos @('down', $argumento)
            $resultado.Codigo | Should Be 1
            $resultado.Texto | Should Match 'Este comando nunca apaga dados'
            $global:ChamadasDocker.Count | Should Be 0
        }
    }

    It 'para a pilha alcançando os serviços de qualquer perfil' {
        Reset-DockerFalso
        $ctx = New-RaizDeTeste -Pasta (Join-Path $TestDrive 'normal')
        New-EnvPreenchido -Ctx $ctx
        Invoke-Doceterapia -Ctx $ctx -Argumentos @('down') | Should Be 0
        Test-ChamadaDocker '--profile tunnel --profile baileys down$' | Should Be $true
    }

    It 'sem configuração, sai com 3' {
        Reset-DockerFalso
        $ctx = New-RaizDeTeste -Pasta (Join-Path $TestDrive 'semenv')
        Invoke-Doceterapia -Ctx $ctx -Argumentos @('down') | Should Be 3
    }
}

Describe 'proteção do código' {
    It 'nenhum script contém formas de apagar todos os volumes' {
        $proibidos = 'down -v', '--volumes', 'volume prune'
        foreach ($proibido in $proibidos) {
            $achados = Get-ChildItem -LiteralPath (Join-Path $RAIZ_REPOSITORIO 'scripts') -Recurse -Filter '*.ps1' |
                Select-String -SimpleMatch -Pattern $proibido
            @($achados).Count | Should Be 0
        }
    }

    It 'o único volume removido é o do banco' {
        $achados = Get-ChildItem -LiteralPath (Join-Path $RAIZ_REPOSITORIO 'scripts') -Recurse -Filter '*.ps1' |
            Select-String -Pattern "'volume', 'rm'"
        @($achados).Count | Should Be 1
        $achados[0].Filename | Should Be 'ResetarBanco.ps1'
    }

    It 'o env só é gravado pela API sem BOM' {
        $proibidos = Get-ChildItem -LiteralPath (Join-Path $RAIZ_REPOSITORIO 'scripts') -Recurse -Filter '*.ps1' |
            Select-String -Pattern '^[^#]*\b(Set-Content|Out-File|Add-Content)\b'
        @($proibidos).Count | Should Be 0
    }

    It 'todo script começa com BOM, para os acentos sobreviverem ao 5.1' {
        foreach ($arquivo in Get-ChildItem -LiteralPath (Join-Path $RAIZ_REPOSITORIO 'scripts') -Recurse -Filter '*.ps1') {
            $bytes = [System.IO.File]::ReadAllBytes($arquivo.FullName)
            ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) | Should Be $true
        }
    }
}
