. (Join-Path $PSScriptRoot 'Apoio.ps1')

Describe 'logs' {
    Mock Invoke-Docker { Get-RespostaDockerFalso -Argumentos $Argumentos }
    $regras = @(@{ Padrao = 'config --services'; Codigo = 0; Saida = @('back-end', 'front-end') })

    It 'segue o log do serviço pedido' {
        Reset-DockerFalso -Regras $regras
        $ctx = New-RaizDeTeste -Pasta (Join-Path $TestDrive 'ok')
        New-EnvPreenchido -Ctx $ctx
        Invoke-Doceterapia -Ctx $ctx -Argumentos @('logs', 'back-end') | Should Be 0
        Test-ChamadaDocker 'logs --tail 200 -f back-end$' | Should Be $true
    }

    It 'com nome inválido, lista os serviços e sai com 1' {
        Reset-DockerFalso -Regras $regras
        $ctx = New-RaizDeTeste -Pasta (Join-Path $TestDrive 'invalido')
        New-EnvPreenchido -Ctx $ctx
        $resultado = Invoke-ComCaptura -Ctx $ctx -Argumentos @('logs', 'nao-existe')
        $resultado.Codigo | Should Be 1
        $resultado.Texto | Should Match 'back-end'
        $resultado.Texto | Should Match 'front-end'
        Test-ChamadaDocker ' logs ' | Should Be $false
    }

    It 'sem serviço, lista os nomes' {
        Reset-DockerFalso -Regras $regras
        $ctx = New-RaizDeTeste -Pasta (Join-Path $TestDrive 'sem')
        New-EnvPreenchido -Ctx $ctx
        $resultado = Invoke-ComCaptura -Ctx $ctx -Argumentos @('logs')
        $resultado.Codigo | Should Be 0
        $resultado.Texto | Should Match 'front-end'
    }
}

Describe 'entrada do launcher' {
    Mock Invoke-Docker { Get-RespostaDockerFalso -Argumentos $Argumentos }

    It 'comando desconhecido sai com 1 e orienta' {
        Reset-DockerFalso
        $ctx = New-RaizDeTeste -Pasta (Join-Path $TestDrive 'desconhecido')
        $resultado = Invoke-ComCaptura -Ctx $ctx -Argumentos @('xyz')
        $resultado.Codigo | Should Be 1
        $resultado.Texto | Should Match 'Comando desconhecido. Rode: doceterapia ajuda'
    }

    It 'ajuda lista todos os subcomandos' {
        $ctx = New-RaizDeTeste -Pasta (Join-Path $TestDrive 'ajuda')
        $resultado = Invoke-ComCaptura -Ctx $ctx -Argumentos @('ajuda')
        $resultado.Codigo | Should Be 0
        foreach ($comando in 'doctor', 'init', 'up', 'aplicar', 'down', 'backup', 'restore', 'atualizar', 'logs', 'resetar-banco', 'ajuda', '-Simular') {
            $resultado.Texto | Should Match $comando
        }
    }

    It 'sem argumento, mostra a ajuda e espera o Enter' {
        Mock Wait-Enter { }
        $ctx = New-RaizDeTeste -Pasta (Join-Path $TestDrive 'duplo')
        $resultado = Invoke-ComCaptura -Ctx $ctx
        $resultado.Codigo | Should Be 0
        $resultado.Texto | Should Match 'comandos disponíveis'
        Assert-MockCalled Wait-Enter -Times 1 -Exactly -Scope It
    }

    It 'Docker desligado num comando comum sai com 2' {
        Reset-DockerFalso -Regras @(@{ Padrao = '^info'; Codigo = 1 })
        $ctx = New-RaizDeTeste -Pasta (Join-Path $TestDrive 'desligado')
        New-EnvPreenchido -Ctx $ctx
        $resultado = Invoke-ComCaptura -Ctx $ctx -Argumentos @('up')
        $resultado.Codigo | Should Be 2
        $resultado.Texto | Should Match 'O Docker Desktop não está aberto'
    }
}

Describe 'atalho doceterapia.cmd' {
    It 'repassa o código de saída e não muda a política da máquina' {
        $atalho = Join-Path $RAIZ_REPOSITORIO 'doceterapia.cmd'
        & cmd.exe /c "`"$atalho`" comando-que-nao-existe" | Out-Null
        $LASTEXITCODE | Should Be 1
    }

    It 'chama o PowerShell com Bypass só para o processo' {
        $conteudo = [System.IO.File]::ReadAllText((Join-Path $RAIZ_REPOSITORIO 'doceterapia.cmd'))
        $conteudo | Should Match 'powershell\.exe -NoProfile -ExecutionPolicy Bypass -File'
        $conteudo | Should Not Match 'Set-ExecutionPolicy'
    }
}
