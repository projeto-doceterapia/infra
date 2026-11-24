. (Join-Path $PSScriptRoot 'Apoio.ps1')

function Get-LinhasDaFila {
    param([Parameter(Mandatory = $true)][hashtable]$Estado)
    return @($Estado.Fila.ToArray())
}

Describe 'janela de progresso' {
    Mock Start-ThreadJanelaProgresso { @{} }
    Mock Wait-JanelaProgresso { $global:EstadoFinal = $Progresso.Estado }
    Mock Show-Mensagem { }

    It 'sem janela, não guarda nada' {
        Test-JanelaProgresso | Should Be $false
        Add-LinhaProgresso 'nada'
        Set-EtapaProgresso 'nada'
        Test-JanelaProgresso | Should Be $false
    }

    It 'leva textos, avisos e erros para o registro, sem abrir caixa de erro' {
        Start-JanelaProgresso -Titulo 'Ligar o sistema'
        $estado = $script:Progresso.Estado
        Write-Texto 'linha comum'
        Write-Aviso 'cuidado'
        Write-Erro 'falhou'
        Set-EtapaProgresso 'Ligando os serviços'
        $linhas = Get-LinhasDaFila -Estado $estado
        $null = Complete-JanelaProgresso -Sucesso $false -Mensagem 'falhou'

        $linhas -contains 'linha comum' | Should Be $true
        $linhas -contains 'AVISO: cuidado' | Should Be $true
        $linhas -contains 'ERRO: falhou' | Should Be $true
        $linhas -contains '== Ligando os serviços' | Should Be $true
        Get-UltimoErro | Should Be 'falhou'
        Assert-MockCalled Show-Mensagem -Times 0 -Exactly -Scope It
        Test-JanelaProgresso | Should Be $false
    }

    It 'só oferece a ação final quando deu certo' {
        Start-JanelaProgresso -Titulo 'x'
        $null = Complete-JanelaProgresso -Sucesso $false -Mensagem 'erro' -AcaoFinal 'Abrir sistema'
        $global:EstadoFinal.AcaoFinal | Should Be $null
        $global:EstadoFinal.Sucesso | Should Be $false

        Start-JanelaProgresso -Titulo 'x'
        $null = Complete-JanelaProgresso -Sucesso $true -Mensagem 'ok' -AcaoFinal 'Abrir sistema'
        $global:EstadoFinal.AcaoFinal | Should Be 'Abrir sistema'
        $global:EstadoFinal.Concluido | Should Be $true
    }

    Context 'ação do menu' {
        $ctx = New-RaizDeTeste -Pasta (Join-Path $TestDrive 'acao')

        It 'termina com Concluído quando o comando dá certo' {
            $resultado = Invoke-AcaoComProgresso -Titulo 'Ajuda' -Acao { Invoke-Doceterapia -Ctx $ctx -Argumentos @('ajuda') } 6>$null
            $resultado.Codigo | Should Be 0
            $global:EstadoFinal.Etapa | Should Be 'Concluído.'
            $global:EstadoFinal.Sucesso | Should Be $true
        }

        It 'termina com a mensagem de erro do comando' {
            $resultado = Invoke-AcaoComProgresso -Titulo 'Teste' -Acao { Invoke-Doceterapia -Ctx $ctx -Argumentos @('xyz') } 6>$null
            $resultado.Codigo | Should Be 1
            $global:EstadoFinal.Etapa | Should Match 'Comando desconhecido'
            $global:EstadoFinal.Sucesso | Should Be $false
        }
    }
}
