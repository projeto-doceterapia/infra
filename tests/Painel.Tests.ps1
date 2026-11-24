. (Join-Path $PSScriptRoot 'Apoio.ps1')

Describe 'estado da janela principal' {
    It 'descreve cada estado em PT-BR' {
        Get-TextoEstado -Estado ([pscustomobject]@{ Configurado = $false; Ligado = $false; Url = 'x' }) | Should Match 'ainda não foi configurado'
        Get-TextoEstado -Estado ([pscustomobject]@{ Configurado = $true; Ligado = $false; Url = 'x' }) | Should Be 'Sistema desligado.'
        Get-TextoEstado -Estado ([pscustomobject]@{ Configurado = $true; Ligado = $true; Url = 'http://localhost:3000' }) | Should Be 'Sistema ligado em http://localhost:3000'
    }

    Context 'sem configuração' {
        Mock Test-SistemaRespondendo { $true }
        $ctx = New-RaizDeTeste -Pasta (Join-Path $TestDrive 'semenv')
        $estado = Get-EstadoDoPainel -Ctx $ctx

        It 'não consulta o sistema' {
            $estado.Configurado | Should Be $false
            $estado.Ligado | Should Be $false
            Assert-MockCalled Test-SistemaRespondendo -Times 0 -Exactly -Scope Context
        }
    }

    Context 'configurado e no ar' {
        Mock Test-SistemaRespondendo { $true }
        $ctx = New-RaizDeTeste -Pasta (Join-Path $TestDrive 'noar')
        New-EnvPreenchido -Ctx $ctx -Valores @{ FRONTEND_HOST_PORT = '3100' }
        $estado = Get-EstadoDoPainel -Ctx $ctx

        It 'usa a porta configurada' {
            $estado.Configurado | Should Be $true
            $estado.Ligado | Should Be $true
            $estado.Url | Should Be 'http://localhost:3100'
        }
    }
}

Describe 'abrir pela janela' {
    Mock Start-AplicativoNavegador { }
    $ctx = New-RaizDeTeste -Pasta (Join-Path $TestDrive 'abrir')
    New-EnvPreenchido -Ctx $ctx

    It 'com o sistema no ar, abre sem ligar' {
        Mock Test-SistemaRespondendo { $true }
        Mock Invoke-AcaoComProgresso { throw 'must not start' }
        Invoke-AbrirPeloPainel -Ctx $ctx
        Assert-MockCalled Start-AplicativoNavegador -Times 1 -Exactly -Scope It
    }

    It 'com o sistema parado e a pessoa recusando, não faz nada' {
        Mock Test-SistemaRespondendo { $false }
        Mock Read-SimNao { $false }
        Mock Invoke-AcaoComProgresso { throw 'must not start' }
        Invoke-AbrirPeloPainel -Ctx $ctx
        Assert-MockCalled Start-AplicativoNavegador -Times 0 -Exactly -Scope It
    }

    It 'com o sistema parado, liga e abre' {
        Mock Test-SistemaRespondendo { $false }
        Mock Read-SimNao { $true }
        Mock Invoke-AcaoComProgresso { [pscustomobject]@{ Codigo = 0; AcaoEscolhida = $false } }
        Invoke-AbrirPeloPainel -Ctx $ctx
        Assert-MockCalled Invoke-AcaoComProgresso -Times 1 -Exactly -Scope It
        Assert-MockCalled Start-AplicativoNavegador -Times 1 -Exactly -Scope It
    }

    It 'não abre quando a subida falha' {
        Mock Test-SistemaRespondendo { $false }
        Mock Read-SimNao { $true }
        Mock Invoke-AcaoComProgresso { [pscustomobject]@{ Codigo = 4; AcaoEscolhida = $false } }
        Invoke-AbrirPeloPainel -Ctx $ctx
        Assert-MockCalled Start-AplicativoNavegador -Times 0 -Exactly -Scope It
    }
}

Describe 'registros em tempo real' {
    Mock Invoke-Docker { Get-RespostaDockerFalso -Argumentos $Argumentos }

    It 'lista só os serviços em execução' {
        Reset-DockerFalso -Regras @(@{ Padrao = 'ps --services --status running'; Codigo = 0; Saida = @('orquestrador', 'back-end', '') })
        $ctx = New-RaizDeTeste -Pasta (Join-Path $TestDrive 'emexecucao')
        (Get-ServicosEmExecucao -Ctx $ctx) -join ',' | Should Be 'back-end,orquestrador'
    }

    It 'sem Docker respondendo, não lista nada' {
        Reset-DockerFalso -Regras @(@{ Padrao = 'ps --services'; Codigo = 1 })
        $ctx = New-RaizDeTeste -Pasta (Join-Path $TestDrive 'semdocker')
        @(Get-ServicosEmExecucao -Ctx $ctx).Count | Should Be 0
    }

    It 'monta o comando do console com aspas no caminho e o serviço escolhido' {
        $ctx = New-RaizDeTeste -Pasta (Join-Path $TestDrive 'pasta com espaço')
        $comando = Get-ComandoConsoleLogs -Ctx $ctx -Servico 'back-end'
        $comando | Should Match "registros de back-end"
        $comando | Should Match ([regex]::Escape("'--project-directory' '$($ctx.Raiz)'"))
        $comando | Should Match "'logs' '--tail' '200' '-f' 'back-end'$"
    }
}
