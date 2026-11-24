. (Join-Path $PSScriptRoot 'Apoio.ps1')

function Get-EventosDoPainel {
    return , @($script:Painel.Eventos.ToArray())
}

function Get-TiposDosEventos {
    return (@((Get-EventosDoPainel) | ForEach-Object { $_.Tipo }) -join ',')
}

Describe 'estado do painel' {
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
        Mock Test-SistemaRespondendo { $Url -eq 'http://localhost:3100' }
        $ctx = New-RaizDeTeste -Pasta (Join-Path $TestDrive 'noar')
        New-EnvPreenchido -Ctx $ctx -Valores @{ FRONTEND_HOST_PORT = '3100' }

        It 'consulta a porta configurada' {
            $estado = Get-EstadoDoPainel -Ctx $ctx
            $estado.Configurado | Should Be $true
            $estado.Ligado | Should Be $true
        }
    }
}

Describe 'pedidos da janela' {
    Mock Wait-RespostaDoPainel { $true }
    Mock Start-AplicativoNavegador { $true }
    $ctx = New-RaizDeTeste -Pasta (Join-Path $TestDrive 'pedidos')
    New-EnvPreenchido -Ctx $ctx

    It 'responde o estado' {
        Mock Test-SistemaRespondendo { $false }
        $script:Painel = New-EstadoPainel
        try {
            Invoke-PedidoDoPainel -Ctx $ctx -Pedido @{ Acao = 'estado' }
            $evento = (Get-EventosDoPainel)[0]
            $evento.Tipo | Should Be 'Estado'
            $evento.Estado.Configurado | Should Be $true
            $evento.Estado.Ligado | Should Be $false
        }
        finally { $script:Painel = $null }
    }

    It 'abrir com o sistema no ar mostra o carregamento e passa a acompanhar o navegador' {
        Mock Test-SistemaRespondendo { $true }
        $script:Painel = New-EstadoPainel
        try {
            Invoke-PedidoDoPainel -Ctx $ctx -Pedido @{ Acao = 'abrir' }
            Assert-MockCalled Start-AplicativoNavegador -Times 1 -Exactly -Scope It
            Get-TiposDosEventos | Should Be 'Carregando'
            $script:MonitorNavegador.Fase | Should Be 'Abrindo'
            $script:Painel.Encerrar | Should Be $false
        }
        finally {
            $script:Painel = $null
            $script:MonitorNavegador = $null
        }
    }

    It 'sem navegador de aplicativo, abre no navegador padrão e volta ao menu' {
        Mock Test-SistemaRespondendo { $true }
        Mock Start-AplicativoNavegador { $false }
        $script:Painel = New-EstadoPainel
        try {
            Invoke-PedidoDoPainel -Ctx $ctx -Pedido @{ Acao = 'abrir' }
            Get-TiposDosEventos | Should Be 'Carregando,Menu'
            $script:MonitorNavegador | Should Be $null
        }
        finally { $script:Painel = $null }
    }

    It 'abrir com o sistema parado e a pessoa recusando volta ao menu' {
        Mock Test-SistemaRespondendo { $false }
        Mock Read-SimNao { $false }
        $script:Painel = New-EstadoPainel
        try {
            Invoke-PedidoDoPainel -Ctx $ctx -Pedido @{ Acao = 'abrir' }
            Assert-MockCalled Start-AplicativoNavegador -Times 0 -Exactly -Scope It
            Get-TiposDosEventos | Should Be 'Menu'
            $script:Painel.Encerrar | Should Be $false
        }
        finally { $script:Painel = $null }
    }

    It 'abrir com o sistema parado liga e abre' {
        Mock Start-AplicativoNavegador { $true }
        Mock Test-SistemaRespondendo { $false }
        Mock Read-SimNao { $true }
        Mock Invoke-Doceterapia { 0 }
        $script:Painel = New-EstadoPainel
        try {
            Invoke-PedidoDoPainel -Ctx $ctx -Pedido @{ Acao = 'abrir' }
            Assert-MockCalled Invoke-Doceterapia -Times 1 -Exactly -Scope It -ParameterFilter { $Argumentos -join ' ' -eq 'up' }
            Assert-MockCalled Start-AplicativoNavegador -Times 1 -Exactly -Scope It
            Get-TiposDosEventos | Should Be 'Inicio,Fim,Carregando'
        }
        finally {
            $script:Painel = $null
            $script:MonitorNavegador = $null
        }
    }

    It 'abrir não abre o navegador quando a subida falha' {
        Mock Test-SistemaRespondendo { $false }
        Mock Read-SimNao { $true }
        Mock Invoke-Doceterapia { 4 }
        $script:Painel = New-EstadoPainel
        try {
            Invoke-PedidoDoPainel -Ctx $ctx -Pedido @{ Acao = 'abrir' }
            Assert-MockCalled Start-AplicativoNavegador -Times 0 -Exactly -Scope It
            Get-TiposDosEventos | Should Be 'Inicio,Fim'
            (Get-EventosDoPainel)[1].Sucesso | Should Be $false
        }
        finally { $script:Painel = $null }
    }

    It 'uma operação do menu roda o subcomando e oferece abrir depois de ligar' {
        Mock Invoke-Doceterapia { 0 }
        $script:Painel = New-EstadoPainel
        try {
            Invoke-PedidoDoPainel -Ctx $ctx -Pedido @{ Acao = 'up' }
            Assert-MockCalled Invoke-Doceterapia -Times 1 -Exactly -Scope It -ParameterFilter { $Argumentos -join ' ' -eq 'up' }
            $fim = (Get-EventosDoPainel)[1]
            $fim.Tipo | Should Be 'Fim'
            $fim.Mensagem | Should Be 'Concluído.'
            $fim.AcaoFinal | Should Be 'Abrir sistema'
        }
        finally { $script:Painel = $null }
    }

    It 'um erro mostra a mensagem e volta ao menu, sem fechar o painel' {
        Mock Test-InterfaceGrafica { $true }
        $script:Painel = New-EstadoPainel
        try {
            Invoke-PedidoDoPainel -Ctx $ctx -Pedido @{ Acao = 'inexistente' } 6>$null
            $eventos = Get-EventosDoPainel
            $eventos[0].Modo | Should Be 'Mensagem'
            $eventos[0].Dados.Tipo | Should Be 'Erro'
            $eventos[1].Tipo | Should Be 'Menu'
            $script:Painel.Encerrar | Should Be $false
        }
        finally { $script:Painel = $null }
    }

    It 'ver logs sem serviço ligado avisa e volta ao menu' {
        Mock Assert-DockerLigado { }
        Mock Get-ServicosEmExecucao { @() }
        Mock Start-ConsoleLogs { }
        $script:Painel = New-EstadoPainel
        try {
            Invoke-PedidoDoPainel -Ctx $ctx -Pedido @{ Acao = 'ver-logs' }
            (Get-EventosDoPainel)[0].Dados.Texto | Should Match 'Nenhum serviço está ligado'
            (Get-EventosDoPainel)[1].Tipo | Should Be 'Menu'
            Assert-MockCalled Start-ConsoleLogs -Times 0 -Exactly -Scope It
        }
        finally { $script:Painel = $null }
    }

    It 'ver logs abre o console do serviço escolhido na janela' {
        Mock Assert-DockerLigado { }
        Mock Get-ServicosEmExecucao { @('back-end', 'orquestrador') }
        Mock Wait-RespostaDoPainel { 'orquestrador' }
        Mock Start-ConsoleLogs { }
        $script:Painel = New-EstadoPainel
        try {
            Invoke-PedidoDoPainel -Ctx $ctx -Pedido @{ Acao = 'ver-logs' }
            (Get-EventosDoPainel)[0].Modo | Should Be 'Servico'
            Assert-MockCalled Start-ConsoleLogs -Times 1 -Exactly -Scope It -ParameterFilter { $Servico -eq 'orquestrador' }
        }
        finally { $script:Painel = $null }
    }

    It 'configurações sem mudança avisam e voltam ao menu' {
        $script:Painel = New-EstadoPainel
        try {
            Invoke-PedidoDoPainel -Ctx $ctx -Pedido @{ Acao = 'configuracoes-salvar'; Dados = @{ CHANNEL = 'cloud_api' } }
            (Get-EventosDoPainel)[0].Dados.Texto | Should Be 'Nada foi alterado.'
            (Get-EventosDoPainel)[1].Tipo | Should Be 'Menu'
        }
        finally { $script:Painel = $null }
    }

    It 'configurações abre a tela com o arquivo atual' {
        $script:Painel = New-EstadoPainel
        try {
            Invoke-PedidoDoPainel -Ctx $ctx -Pedido @{ Acao = 'configuracoes-preparar' }
            $evento = (Get-EventosDoPainel)[0]
            $evento.Tipo | Should Be 'Configuracoes'
            Get-ValorEnv -Linhas $evento.Linhas -Chave 'ADMIN_EMAIL' | Should Be 'dona@exemplo.com'
        }
        finally { $script:Painel = $null }
    }

    It 'restaurar sem escolher pasta volta ao menu' {
        Mock Wait-RespostaDoPainel { $null }
        Mock Invoke-Doceterapia { throw 'must not restore' }
        $script:Painel = New-EstadoPainel
        try {
            Invoke-PedidoDoPainel -Ctx $ctx -Pedido @{ Acao = 'restore' }
            Get-TiposDosEventos | Should Be 'Pergunta,Menu'
        }
        finally { $script:Painel = $null }
    }

    It 'sair encerra o laço do painel' {
        $script:Painel = New-EstadoPainel
        try {
            Invoke-PedidoDoPainel -Ctx $ctx -Pedido @{ Acao = 'sair' }
            $script:Painel.Encerrar | Should Be $true
        }
        finally { $script:Painel = $null }
    }
}

Describe 'acompanhamento do navegador' {
    $ctx = New-RaizDeTeste -Pasta (Join-Path $TestDrive 'navegador')

    It 'esconde o painel quando a janela do sistema aparece e volta ao menu quando ela fecha' {
        $script:Painel = New-EstadoPainel
        try {
            Start-MonitorNavegador
            Mock Test-JanelaNavegadorAberta { $true }
            Update-MonitorNavegador -Ctx $ctx
            $script:MonitorNavegador.Fase | Should Be 'Aberto'

            Mock Test-JanelaNavegadorAberta { $false }
            $script:MonitorNavegador.ProximaChecagem = Get-Date
            Update-MonitorNavegador -Ctx $ctx
            Get-TiposDosEventos | Should Be 'Ocultar,Mostrar,Menu'
            $script:MonitorNavegador | Should Be $null
        }
        finally {
            $script:Painel = $null
            $script:MonitorNavegador = $null
        }
    }

    It 'volta ao menu quando a janela não aparece a tempo' {
        Mock Test-JanelaNavegadorAberta { $false }
        $script:Painel = New-EstadoPainel
        try {
            Start-MonitorNavegador
            $script:MonitorNavegador.Limite = (Get-Date).AddSeconds(-1)
            Update-MonitorNavegador -Ctx $ctx
            Get-TiposDosEventos | Should Be 'Menu'
            $script:MonitorNavegador | Should Be $null
        }
        finally {
            $script:Painel = $null
            $script:MonitorNavegador = $null
        }
    }

    It 'espera o intervalo entre duas checagens' {
        Mock Test-JanelaNavegadorAberta { $true }
        $script:Painel = New-EstadoPainel
        try {
            Start-MonitorNavegador
            $script:MonitorNavegador.ProximaChecagem = (Get-Date).AddMinutes(1)
            Update-MonitorNavegador -Ctx $ctx
            Assert-MockCalled Test-JanelaNavegadorAberta -Times 0 -Exactly -Scope It
        }
        finally {
            $script:Painel = $null
            $script:MonitorNavegador = $null
        }
    }

}

Describe 'janela do navegador' {
    Context 'janela do sistema aberta' {
        Mock Get-CimInstance {
            @(
                [pscustomobject]@{ ProcessId = 11; CommandLine = 'msedge.exe --user-data-dir="C:\Outro\perfil"' },
                [pscustomobject]@{ ProcessId = 12; CommandLine = 'msedge.exe --user-data-dir="C:\Dados\DOCETERAPIA\navegador" --type=renderer' },
                [pscustomobject]@{ ProcessId = 13; CommandLine = 'msedge.exe --app=x --user-data-dir="C:\Dados\Doceterapia\navegador"' }
            )
        }
        Mock Test-ProcessoComJanela { $Id -eq 13 }

        It 'conta só processos do perfil do sistema com janela visível' {
            Test-JanelaNavegadorAberta -PastaPerfil 'C:\Dados\Doceterapia\navegador' | Should Be $true
            Assert-MockCalled Test-ProcessoComJanela -Times 0 -Exactly -Scope It -ParameterFilter { $Id -eq 11 }
        }
    }

    Context 'só processos em segundo plano' {
        Mock Get-CimInstance { @([pscustomobject]@{ ProcessId = 12; CommandLine = 'msedge.exe --user-data-dir="C:\Dados\Doceterapia\navegador" --type=renderer' }) }
        Mock Test-ProcessoComJanela { $false }

        It 'sem janela visível do perfil, o sistema está fechado' {
            Test-JanelaNavegadorAberta -PastaPerfil 'C:\Dados\Doceterapia\navegador' | Should Be $false
        }
    }
}

Describe 'instância única' {
    $nome = "Local\Doceterapia.Teste.$([guid]::NewGuid())"

    It 'só a primeira instância fica com o painel' {
        $primeira = Enter-InstanciaUnica -Nome $nome
        try {
            $primeira | Should Not Be $null
            Enter-InstanciaUnica -Nome $nome | Should Be $null
        }
        finally { Exit-InstanciaUnica -Mutex $primeira }
    }

    It 'a segunda instância pede foco à primeira' {
        $sinalNome = "Local\Doceterapia.Teste.Foco.$([guid]::NewGuid())"
        $sinal = New-Object System.Threading.EventWaitHandle($false, [System.Threading.EventResetMode]::AutoReset, $sinalNome)
        try {
            Request-FocoDaInstancia -Nome $sinalNome | Should Be $true
            $sinal.WaitOne(0) | Should Be $true
        }
        finally { $sinal.Dispose() }
    }

    It 'sem painel aberto, o pedido de foco não encontra ninguém' {
        Request-FocoDaInstancia -Nome "Local\Doceterapia.Teste.Ninguem.$([guid]::NewGuid())" | Should Be $false
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
        $comando | Should Match 'registros de back-end'
        $comando | Should Match ([regex]::Escape("'--project-directory' '$($ctx.Raiz)'"))
        $comando | Should Match "'logs' '--tail' '200' '-f' 'back-end'$"
    }
}
