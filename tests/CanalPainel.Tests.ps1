. (Join-Path $PSScriptRoot 'Apoio.ps1')

function Get-EventosDoPainel {
    return , @($script:Painel.Eventos.ToArray())
}

Describe 'canal do painel' {
    It 'sem painel, não guarda nada' {
        $script:Painel = $null
        Test-PainelAtivo | Should Be $false
        Add-LinhaProgresso 'nada'
        Set-EtapaProgresso 'nada'
        Send-EventoPainel @{ Tipo = 'Menu' }
        Test-JanelaProgresso | Should Be $false
    }

    It 'fora de uma operação, não registra linhas' {
        $script:Painel = New-EstadoPainel
        try {
            Write-Texto 'linha solta' 6>$null
            $script:Painel.Fila.Count | Should Be 0
        }
        finally { $script:Painel = $null }
    }

    It 'numa operação, leva textos, avisos, erros e etapas para o registro' {
        $script:Painel = New-EstadoPainel
        try {
            Start-OperacaoPainel -Titulo 'Ligar o sistema'
            Write-Texto 'linha comum' 6>$null
            Write-Aviso 'cuidado' 6>$null
            Write-Erro 'falhou' 6>$null
            Set-EtapaProgresso 'Ligando os serviços'
            $linhas = @($script:Painel.Fila.ToArray())
            $linhas -contains 'linha comum' | Should Be $true
            $linhas -contains 'AVISO: cuidado' | Should Be $true
            $linhas -contains 'ERRO: falhou' | Should Be $true
            $linhas -contains '== Ligando os serviços' | Should Be $true
            $script:Painel.Etapa | Should Be 'Ligando os serviços'
            Get-UltimoErro | Should Be 'falhou'
            (Get-EventosDoPainel)[0].Tipo | Should Be 'Inicio'
        }
        finally { $script:Painel = $null }
    }

    It 'só oferece a ação final quando deu certo' {
        $script:Painel = New-EstadoPainel
        try {
            Start-OperacaoPainel -Titulo 'x'
            Complete-OperacaoPainel -Sucesso $false -Mensagem 'erro' -AcaoFinal 'Abrir sistema'
            Start-OperacaoPainel -Titulo 'x'
            Complete-OperacaoPainel -Sucesso $true -Mensagem 'ok' -AcaoFinal 'Abrir sistema'
            $fins = @((Get-EventosDoPainel) | Where-Object { $_.Tipo -eq 'Fim' })
            $fins[0].AcaoFinal | Should Be $null
            $fins[1].AcaoFinal | Should Be 'Abrir sistema'
            $script:Painel.EmOperacao | Should Be $false
        }
        finally { $script:Painel = $null }
    }

    It 'pergunta pela janela e devolve a resposta' {
        Mock Wait-RespostaDoPainel { 'resposta da janela' }
        $script:Painel = New-EstadoPainel
        try {
            Request-RespostaDoPainel -Modo 'Texto' -Dados @{ Texto = 'Digite' } | Should Be 'resposta da janela'
            $pergunta = (Get-EventosDoPainel)[0]
            $pergunta.Tipo | Should Be 'Pergunta'
            $pergunta.Modo | Should Be 'Texto'
            $pergunta.Dados.Texto | Should Be 'Digite'
        }
        finally { $script:Painel = $null }
    }

    It 'com o painel aberto, os diálogos viram perguntas à janela' {
        Mock Wait-RespostaDoPainel { $true }
        $script:Painel = New-EstadoPainel
        try {
            Show-Mensagem -Texto 'Olá' -Tipo Aviso
            Show-PerguntaSimNao -Pergunta 'Continuar?' | Should Be $true
            $modos = @((Get-EventosDoPainel) | ForEach-Object { $_.Modo })
            $modos -join ',' | Should Be 'Mensagem,SimNao'
            (Get-EventosDoPainel)[0].Dados.Tipo | Should Be 'Aviso'
        }
        finally { $script:Painel = $null }
    }
}

Describe 'espera da resposta' {
    It 'com a janela fechada, a espera termina sem resposta' {
        $script:Painel = New-EstadoPainel
        try {
            $script:Painel.Fechada = $true
            Wait-RespostaDoPainel -Id 'qualquer' | Should Be $null
        }
        finally { $script:Painel = $null }
    }

    It 'devolve a resposta registrada pela janela' {
        $script:Painel = New-EstadoPainel
        try {
            $script:Painel.Respostas['id-1'] = 'sim'
            Wait-RespostaDoPainel -Id 'id-1' | Should Be 'sim'
            $script:Painel.Respostas.ContainsKey('id-1') | Should Be $false
        }
        finally { $script:Painel = $null }
    }
}
