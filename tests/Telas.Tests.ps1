. (Join-Path $PSScriptRoot 'Apoio.ps1')

# The screens are built and clicked without ever being shown, so no window can
# block the run. Clicks go through the protected OnClick, as a real click would.
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

function Invoke-Clique {
    param([Parameter(Mandatory = $true)]$Botao)
    $metodo = $Botao.GetType().GetMethod('OnClick', [System.Reflection.BindingFlags]'Instance, NonPublic')
    $null = $metodo.Invoke($Botao, @([EventArgs]::Empty))
}

function Find-Controle {
    param(
        [Parameter(Mandatory = $true)]$Raiz,
        [Parameter(Mandatory = $true)][string]$Texto
    )
    foreach ($controle in $Raiz.Controls) {
        if ($controle.Text -eq $Texto) { return $controle }
        $achado = Find-Controle -Raiz $controle -Texto $Texto
        if ($achado) { return $achado }
    }
    return $null
}

function Get-TelaAtual {
    param([Parameter(Mandatory = $true)]$Janela)
    return $Janela.Tag.Area.Controls[0]
}

function Get-PedidosDaJanela {
    param([Parameter(Mandatory = $true)]$Janela)
    return , @($Janela.Tag.Estado.Pedidos.ToArray())
}

function New-JanelaDeTeste {
    $janela = New-JanelaPainel -Estado (New-EstadoPainel)
    Show-TelaMenu -Janela $janela
    return $janela
}

function New-LinhasExemplo {
    return , (Read-ArquivoEnv -Caminho (Join-Path $RAIZ_REPOSITORIO '.env.example'))
}

Describe 'janela principal' {
    It 'abre o menu pedindo o estado, com o botão principal esperando' {
        $janela = New-JanelaDeTeste
        (Get-PedidosDaJanela -Janela $janela)[0].Acao | Should Be 'estado'
        $janela.Tag.Principal.Enabled | Should Be $false
        $janela.Tag.Situacao.Text | Should Be 'Verificando o sistema...'
    }

    It 'mostra o farol verde e Abrir sistema quando o sistema está ligado' {
        $janela = New-JanelaDeTeste
        Invoke-EventoNaJanela -Janela $janela -Evento @{ Tipo = 'Estado'; Estado = [pscustomobject]@{ Configurado = $true; Ligado = $true } }
        $janela.Tag.Situacao.Text | Should Be 'Sistema ligado'
        $janela.Tag.Farol.ForeColor.G | Should BeGreaterThan $janela.Tag.Farol.ForeColor.R
        $janela.Tag.Principal.Text | Should Be 'Abrir sistema'
        $janela.Tag.Principal.Enabled | Should Be $true
    }

    It 'mostra o farol vermelho, sem endereço, quando o sistema está desligado' {
        $janela = New-JanelaDeTeste
        Invoke-EventoNaJanela -Janela $janela -Evento @{ Tipo = 'Estado'; Estado = [pscustomobject]@{ Configurado = $true; Ligado = $false } }
        $janela.Tag.Situacao.Text | Should Be 'Sistema desligado'
        $janela.Tag.Farol.ForeColor.R | Should BeGreaterThan $janela.Tag.Farol.ForeColor.G
    }

    It 'sem configuração, o botão principal configura o sistema' {
        $janela = New-JanelaDeTeste
        Invoke-EventoNaJanela -Janela $janela -Evento @{ Tipo = 'Estado'; Estado = [pscustomobject]@{ Configurado = $false; Ligado = $false } }
        $janela.Tag.Situacao.Text | Should Be 'Sistema não configurado'
        $janela.Tag.Principal.Text | Should Be 'Configurar o sistema'
        Invoke-Clique $janela.Tag.Principal
        (Get-PedidosDaJanela -Janela $janela)[-1].Acao | Should Be 'configurar-preparar'
    }

    It 'um botão do menu mostra o carregamento na hora e envia o pedido' {
        $janela = New-JanelaDeTeste
        Invoke-Clique (Find-Controle -Raiz $janela -Texto 'Atualizar')
        (Get-PedidosDaJanela -Janela $janela)[-1].Acao | Should Be 'atualizar'
        Find-Controle -Raiz (Get-TelaAtual -Janela $janela) -Texto 'Atualizar...' | Should Not Be $null
    }

    It 'acompanha uma operação na mesma janela e volta ao menu' {
        $janela = New-JanelaDeTeste
        $estado = $janela.Tag.Estado
        Invoke-EventoNaJanela -Janela $janela -Evento @{ Tipo = 'Inicio'; Titulo = 'Ligar o sistema' }
        $estado.EmOperacao = $true
        $estado.Etapa = 'Ligando os serviços'
        $estado.Fila.Enqueue('linha do docker')
        Invoke-CicloDaJanela -Janela $janela
        $janela.Tag.Progresso.Registro.Text | Should Match 'linha do docker'
        $janela.Tag.Progresso.Etapa.Text | Should Be 'Ligando os serviços'

        $estado.EmOperacao = $false
        $estado.Eventos.Enqueue(@{ Tipo = 'Fim'; Sucesso = $true; Mensagem = 'Concluído.'; AcaoFinal = 'Abrir sistema' })
        Invoke-CicloDaJanela -Janela $janela
        $janela.Tag.Progresso.Etapa.Text | Should Be 'Concluído.'
        $janela.Tag.Progresso.Voltar.Enabled | Should Be $true
        $janela.AcceptButton | Should Be $janela.Tag.Progresso.Acao

        Invoke-Clique $janela.Tag.Progresso.Acao
        (Get-PedidosDaJanela -Janela $janela)[-1].Acao | Should Be 'abrir'
    }

    It 'mostra o carregamento pedido pelos comandos e se esconde e volta com o navegador' {
        Mock Show-JanelaEmFoco { }
        $janela = New-JanelaDeTeste
        Invoke-EventoNaJanela -Janela $janela -Evento @{ Tipo = 'Carregando'; Texto = 'Abrindo o sistema...' }
        Find-Controle -Raiz (Get-TelaAtual -Janela $janela) -Texto 'Abrindo o sistema...' | Should Not Be $null
        Invoke-EventoNaJanela -Janela $janela -Evento @{ Tipo = 'Ocultar' }
        $janela.Visible | Should Be $false
        Invoke-EventoNaJanela -Janela $janela -Evento @{ Tipo = 'Mostrar' }
        Assert-MockCalled Show-JanelaEmFoco -Times 1 -Exactly -Scope It
    }

    It 'vem para a frente quando outra instância pede foco' {
        Mock Show-JanelaEmFoco { }
        $janela = New-JanelaDeTeste
        $janela.Tag.Estado.SinalFoco = New-Object System.Threading.EventWaitHandle($false, [System.Threading.EventResetMode]::AutoReset)
        try {
            Invoke-CicloDaJanela -Janela $janela
            Assert-MockCalled Show-JanelaEmFoco -Times 0 -Exactly -Scope It
            $null = $janela.Tag.Estado.SinalFoco.Set()
            Invoke-CicloDaJanela -Janela $janela
            Assert-MockCalled Show-JanelaEmFoco -Times 1 -Exactly -Scope It
        }
        finally { $janela.Tag.Estado.SinalFoco.Dispose() }
    }

    It 'responde as perguntas dos comandos' {
        Mock Invoke-PerguntaNaJanela { 'resposta' }
        $janela = New-JanelaDeTeste
        Invoke-EventoNaJanela -Janela $janela -Evento @{ Tipo = 'Pergunta'; Id = 'p1'; Modo = 'Texto'; Dados = @{ Texto = 'x' } }
        $janela.Tag.Estado.Respostas['p1'] | Should Be 'resposta'
    }

    It 'não fecha durante uma operação' {
        Mock Show-Mensagem { }
        $janela = New-JanelaDeTeste
        $janela.Tag.Estado.EmOperacao = $true
        $evento = New-Object System.Windows.Forms.FormClosingEventArgs([System.Windows.Forms.CloseReason]::UserClosing, $false)
        Confirm-FechamentoDaJanela -Janela $janela -Evento $evento
        $evento.Cancel | Should Be $true

        $janela.Tag.Estado.EmOperacao = $false
        $evento = New-Object System.Windows.Forms.FormClosingEventArgs([System.Windows.Forms.CloseReason]::UserClosing, $false)
        Confirm-FechamentoDaJanela -Janela $janela -Evento $evento
        $evento.Cancel | Should Be $false
        (Get-PedidosDaJanela -Janela $janela)[-1].Acao | Should Be 'sair'
    }
}

Describe 'tela do assistente' {
    $janela = New-JanelaDeTeste
    Invoke-EventoNaJanela -Janela $janela -Evento @{ Tipo = 'Assistente'; Linhas = @(New-LinhasExemplo); PedirDona = $true; PedirDemo = $true }
    $tela = (Get-TelaAtual -Janela $janela).Tag

    It 'abre na conta da DONA' {
        $tela.Titulo.Text | Should Be 'Conta da DONA'
        $tela.Dica.Text | Should Be 'Passo 1 de 3'
        $tela.Voltar.Enabled | Should Be $false
    }

    It 'não avança com e-mail inválido' {
        $tela.Dona.Campos.Email.Text = 'sem-arroba'
        $tela.Dona.Campos.Senha.Text = $SENHA_FICTICIA
        $tela.Dona.Campos.Confirmacao.Text = $SENHA_FICTICIA
        Invoke-Clique $tela.Avancar
        $tela.Indice | Should Be 0
        $tela.Erro.Text | Should Match 'E-mail inválido'
    }

    It 'avança com a conta válida e confere o telefone' {
        $tela.Dona.Campos.Email.Text = 'dona@exemplo.com'
        Invoke-Clique $tela.Avancar
        $tela.Indice | Should Be 1
        $tela.Titulo.Text | Should Be 'WhatsApp'
        $tela.WhatsApp.Telefone.Text = '11900000001'
        Invoke-Clique $tela.Avancar
        $tela.Indice | Should Be 1
        $tela.Erro.Text | Should Match 'Telefone inválido'
    }

    It 'adia as chaves e mostra o resumo antes de concluir' {
        $tela.WhatsApp.Telefone.Text = '+5511900000002'
        $tela.WhatsApp.Adiar.Checked = $true
        Invoke-Clique $tela.Avancar
        $tela.Avancar.Text | Should Be 'Concluir'
        $tela.Resumo.Text | Should Match 'configurar depois'
    }

    It 'conclui enviando as respostas' {
        Invoke-Clique $tela.Avancar
        $pedido = (Get-PedidosDaJanela -Janela $janela)[-1]
        $pedido.Acao | Should Be 'configurar'
        $pedido.Dados.Dona.Email | Should Be 'dona@exemplo.com'
        $pedido.Dados.Valores.BENEFICIARIA_TELEFONE | Should Be '+5511900000002'
        $pedido.Dados.Valores.ContainsKey('GEMINI_API_KEY') | Should Be $false
    }
}

Describe 'tela de configurações' {
    $janela = New-JanelaDeTeste
    Invoke-EventoNaJanela -Janela $janela -Evento @{ Tipo = 'Configuracoes'; Linhas = @(New-LinhasExemplo) }
    $tela = (Get-TelaAtual -Janela $janela).Tag

    It 'mostra só as chaves do canal escolhido' {
        $tela.WhatsApp.Celular.Checked = $true
        $valores = Get-ValoresPainelWhatsApp -Controles $tela.WhatsApp
        $valores.CHANNEL | Should Be 'baileys'
        $valores.ContainsKey('CLOUD_API_TOKEN') | Should Be $false
        $valores.ContainsKey('GEMINI_API_KEY') | Should Be $true
    }

    It 'não salva com valor inválido' {
        $tela.WhatsApp.Campos.GEMINI_API_KEY.Caixa.Text = "com'aspas"
        Invoke-Clique (Find-Controle -Raiz (Get-TelaAtual -Janela $janela) -Texto 'Salvar')
        $tela.Erro.Text | Should Match 'aspas simples'
    }

    It 'salva enviando os valores' {
        $tela.WhatsApp.Campos.GEMINI_API_KEY.Caixa.Text = 'chave-ficticia-gemini'
        Invoke-Clique (Find-Controle -Raiz (Get-TelaAtual -Janela $janela) -Texto 'Salvar')
        $pedido = (Get-PedidosDaJanela -Janela $janela)[-1]
        $pedido.Acao | Should Be 'configuracoes-salvar'
        $pedido.Dados.GEMINI_API_KEY | Should Be 'chave-ficticia-gemini'
    }

    It 'cancelar volta ao menu' {
        $janela2 = New-JanelaDeTeste
        Invoke-EventoNaJanela -Janela $janela2 -Evento @{ Tipo = 'Configuracoes'; Linhas = @(New-LinhasExemplo) }
        Invoke-Clique (Find-Controle -Raiz (Get-TelaAtual -Janela $janela2) -Texto 'Cancelar')
        $janela2.Tag.Principal | Should Not Be $null
    }
}
