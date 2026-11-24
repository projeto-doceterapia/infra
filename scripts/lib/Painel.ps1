# Command side of the panel: starts the window thread and answers its requests
# with the subcommands of the same name, so the window and the CLI share every
# rule and exit code.

$ENTRADA_LAUNCHER = Join-Path (Split-Path -Parent $PSScriptRoot) 'doceterapia.ps1'

$OPERACOES_DO_MENU = @{
    'up'            = 'Ligar o sistema'
    'down'          = 'Desligar o sistema'
    'backup'        = 'Fazer backup'
    'atualizar'     = 'Atualizar'
    'doctor'        = 'Verificar o computador'
    'resetar-banco' = 'Apagar e recriar o banco'
}

$SCRIPT_JANELA_PAINEL = {
    param($estado, $entrada)
    . $entrada
    Enable-InterfaceGrafica
    try {
        [System.Windows.Forms.Application]::Run((New-JanelaPainel -Estado $estado))
    }
    finally {
        $estado.Fechada = $true
    }
}

function Start-ThreadJanelaPainel {
    param([Parameter(Mandatory = $true)][hashtable]$Estado)
    $espaco = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
    $espaco.ApartmentState = 'STA'
    $espaco.ThreadOptions = 'ReuseThread'
    $espaco.Open()
    $execucao = [System.Management.Automation.PowerShell]::Create()
    $execucao.Runspace = $espaco
    $null = $execucao.AddScript($SCRIPT_JANELA_PAINEL.ToString()).AddArgument($Estado).AddArgument($ENTRADA_LAUNCHER)
    return @{ Execucao = $execucao; Espaco = $espaco; Resultado = $execucao.BeginInvoke() }
}

function Wait-ThreadJanelaPainel {
    # Returns the window thread's errors, so a window that could not open is
    # still reported.
    param([Parameter(Mandatory = $true)][hashtable]$Thread)
    try {
        $null = $Thread.Execucao.EndInvoke($Thread.Resultado)
        return @($Thread.Execucao.Streams.Error | ForEach-Object { "$_" })
    }
    catch {
        return @("$($_.Exception.Message)")
    }
    finally {
        $Thread.Execucao.Dispose()
        $Thread.Espaco.Dispose()
    }
}

function Start-Painel {
    param([Parameter(Mandatory = $true)][hashtable]$Ctx)
    $estado = New-EstadoPainel
    $thread = Start-ThreadJanelaPainel -Estado $estado
    $script:Painel = $estado
    try {
        while (-not $estado.Encerrar -and -not $estado.Fechada) {
            $pedido = $null
            if ($estado.Pedidos.TryDequeue([ref]$pedido)) {
                Invoke-PedidoDoPainel -Ctx $Ctx -Pedido $pedido
            }
            else {
                Start-Sleep -Milliseconds 100
            }
        }
    }
    finally {
        $script:Painel = $null
        $erros = @(Wait-ThreadJanelaPainel -Thread $thread)
    }
    if ($erros.Count -gt 0) {
        Write-Erro "O painel foi fechado por um erro: $($erros[0])"
    }
}

function Close-Painel {
    Send-EventoPainel @{ Tipo = 'Fechar' }
    $script:Painel.Encerrar = $true
}

function Show-MenuDoPainel {
    Send-EventoPainel @{ Tipo = 'Menu' }
}

function Invoke-PedidoDoPainel {
    # A failure shows its message and returns to the menu; it never closes the
    # window.
    param(
        [Parameter(Mandatory = $true)][hashtable]$Ctx,
        [Parameter(Mandatory = $true)][hashtable]$Pedido
    )
    $codigo = Invoke-ComTratamento -Acao { Invoke-AcaoDoPainel -Ctx $Ctx -Acao $Pedido.Acao -Dados $Pedido.Dados }
    if ($codigo -ne $CODIGO_SUCESSO) { Show-MenuDoPainel }
}

function Invoke-AcaoDoPainel {
    param(
        [Parameter(Mandatory = $true)][hashtable]$Ctx,
        [Parameter(Mandatory = $true)][string]$Acao,
        $Dados
    )
    switch ($Acao) {
        'estado' { Send-EventoPainel @{ Tipo = 'Estado'; Estado = Get-EstadoDoPainel -Ctx $Ctx } }
        'abrir' { Invoke-AbrirPeloPainel -Ctx $Ctx }
        'configurar-preparar' { Invoke-PrepararAssistente -Ctx $Ctx }
        'configurar' { Invoke-ConfigurarPeloPainel -Ctx $Ctx -Respostas $Dados }
        'configuracoes-preparar' { Invoke-PrepararConfiguracoes -Ctx $Ctx }
        'configuracoes-salvar' { Invoke-SalvarConfiguracoes -Ctx $Ctx -Valores $Dados }
        'ver-logs' { Invoke-VerLogs -Ctx $Ctx }
        'restore' { Invoke-RestaurarPeloPainel -Ctx $Ctx }
        'criar-atalho' {
            $null = Invoke-Doceterapia -Ctx $Ctx -Argumentos @('criar-atalho')
            Show-MenuDoPainel
        }
        'sair' { $script:Painel.Encerrar = $true }
        default {
            if (-not $OPERACOES_DO_MENU.ContainsKey($Acao)) {
                Stop-Launcher -Codigo $CODIGO_USO -Mensagem 'Ação desconhecida no painel.'
            }
            $acaoFinal = if ($Acao -eq 'up') { 'Abrir sistema' } else { $null }
            $null = Invoke-OperacaoDoPainel -Titulo $OPERACOES_DO_MENU[$Acao] -AcaoFinal $acaoFinal -Trabalho { Invoke-Doceterapia -Ctx $Ctx -Argumentos @($Acao) }
        }
    }
}

function Invoke-OperacaoDoPainel {
    # The work returns an exit code; the window shows the outcome and offers
    # -AcaoFinal only on success.
    param(
        [Parameter(Mandatory = $true)][string]$Titulo,
        [Parameter(Mandatory = $true)][scriptblock]$Trabalho,
        [string]$AcaoFinal
    )
    Start-OperacaoPainel -Titulo $Titulo
    $codigo = $CODIGO_USO
    try {
        $codigo = [int](@(& $Trabalho)[-1])
    }
    finally {
        $sucesso = ($codigo -eq $CODIGO_SUCESSO)
        $mensagem = if ($sucesso) { 'Concluído.' } else { "$(Get-UltimoErro)" }
        if (-not $mensagem) { $mensagem = 'A operação não terminou.' }
        Complete-OperacaoPainel -Sucesso $sucesso -Mensagem $mensagem -AcaoFinal $AcaoFinal
    }
    return $codigo
}

function Get-EstadoDoPainel {
    param([Parameter(Mandatory = $true)][hashtable]$Ctx)
    $configurado = Test-Path -LiteralPath $Ctx.CaminhoEnv
    return [pscustomobject]@{
        Configurado = $configurado
        Ligado      = ($configurado -and (Test-SistemaRespondendo -Url (Get-UrlSistema -Ctx $Ctx)))
    }
}

function Invoke-AbrirPeloPainel {
    # A stopped system is offered a start first. Opening the system ends the
    # panel and this hidden process.
    param([Parameter(Mandatory = $true)][hashtable]$Ctx)
    $url = Get-UrlSistema -Ctx $Ctx
    if (-not (Test-SistemaRespondendo -Url $url)) {
        if (-not (Read-SimNao -Pergunta 'O sistema está desligado. Ligar agora e abrir em seguida?' -Padrao $true)) {
            Show-MenuDoPainel
            return
        }
        $codigo = Invoke-OperacaoDoPainel -Titulo 'Ligar o sistema' -Trabalho { Invoke-Doceterapia -Ctx $Ctx -Argumentos @('up') }
        if ($codigo -ne $CODIGO_SUCESSO) { return }
    }
    Start-AplicativoNavegador -Ctx $Ctx -Url $url
    Close-Painel
}

function Test-DonaPendente {
    # Mirrors init: the owner is asked only while no database exists and the env
    # file lacks the e-mail or the password.
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()]$Linhas,
        [Parameter(Mandatory = $true)][bool]$BancoExiste
    )
    if ($BancoExiste) { return $false }
    return (-not (Get-ValorEnv -Linhas $Linhas -Chave 'ADMIN_SENHA') -or -not (Get-ValorEnv -Linhas $Linhas -Chave 'ADMIN_EMAIL'))
}

function Invoke-PrepararAssistente {
    param([Parameter(Mandatory = $true)][hashtable]$Ctx)
    Assert-DockerLigado -Ctx $Ctx
    $bancoExiste = Test-BancoExiste -Ctx $Ctx
    $linhas = Read-ConfiguracaoAtual -Ctx $Ctx
    Send-EventoPainel @{
        Tipo      = 'Assistente'
        Linhas    = @($linhas)
        PedirDona = (Test-DonaPendente -Linhas $linhas -BancoExiste $bancoExiste)
        PedirDemo = (-not $bancoExiste)
    }
}

function Invoke-ConfigurarPeloPainel {
    param(
        [Parameter(Mandatory = $true)][hashtable]$Ctx,
        [Parameter(Mandatory = $true)][hashtable]$Respostas
    )
    $Ctx.Respostas = $Respostas
    try {
        $null = Invoke-OperacaoDoPainel -Titulo 'Configurar e ligar o sistema' -AcaoFinal 'Abrir sistema' -Trabalho {
            $codigo = Invoke-Doceterapia -Ctx $Ctx -Argumentos @('init')
            if ($codigo -ne $CODIGO_SUCESSO) { return $codigo }
            Invoke-Doceterapia -Ctx $Ctx -Argumentos @('up')
        }
    }
    finally {
        $Ctx.Remove('Respostas')
    }
}

function Invoke-PrepararConfiguracoes {
    param([Parameter(Mandatory = $true)][hashtable]$Ctx)
    if (-not (Test-Path -LiteralPath $Ctx.CaminhoEnv)) {
        Show-Mensagem -Texto 'O sistema ainda não foi configurado. Use primeiro o botão Configurar o sistema.' -Tipo Aviso
        Show-MenuDoPainel
        return
    }
    $linhas = Read-ArquivoEnv -Caminho $Ctx.CaminhoEnv
    Send-EventoPainel @{ Tipo = 'Configuracoes'; Linhas = @($linhas) }
}

function Save-Configuracoes {
    # Writes the settings and returns the restart plan, or $null when nothing
    # changed.
    param(
        [Parameter(Mandatory = $true)][hashtable]$Ctx,
        [Parameter(Mandatory = $true)][hashtable]$Valores
    )
    $erros = Get-ErrosDoAssistente -Valores $Valores
    if ($erros.Count -gt 0) {
        Stop-Launcher -Codigo $CODIGO_USO -Mensagem (@($erros.Values)[0])
    }
    $antes = Read-ArquivoEnv -Caminho $Ctx.CaminhoEnv
    $depois = Read-ArquivoEnv -Caminho $Ctx.CaminhoEnv
    Set-ValoresDoAssistente -Linhas $depois -Valores $Valores
    if (($antes -join "`n") -ceq ($depois -join "`n")) { return $null }
    Write-ArquivoEnv -Ctx $Ctx -Linhas $depois
    return (Get-PlanoDeReinicio -Antes $antes -Depois $depois)
}

function Invoke-SalvarConfiguracoes {
    param(
        [Parameter(Mandatory = $true)][hashtable]$Ctx,
        [Parameter(Mandatory = $true)][hashtable]$Valores
    )
    $plano = Save-Configuracoes -Ctx $Ctx -Valores $Valores
    if (-not $plano -or (-not $plano.Completo -and $plano.Servicos.Count -eq 0)) {
        $texto = if ($plano) { 'Configuração salva.' } else { 'Nada foi alterado.' }
        Show-Mensagem -Texto $texto
        Show-MenuDoPainel
        return
    }
    $null = Invoke-OperacaoDoPainel -Titulo 'Aplicar as configurações' -Trabalho {
        Clear-ResumoDaSessao
        Invoke-ComTratamento -Acao { Invoke-PlanoDeReinicio -Ctx $Ctx -Plano $plano }
    }
}

function Invoke-VerLogs {
    param([Parameter(Mandatory = $true)][hashtable]$Ctx)
    Assert-ConfiguracaoExiste -Ctx $Ctx
    Assert-DockerLigado -Ctx $Ctx
    $servicos = @(Get-ServicosEmExecucao -Ctx $Ctx)
    if ($servicos.Count -eq 0) {
        Show-Mensagem -Texto 'Nenhum serviço está ligado. Ligue o sistema para ver os registros.' -Tipo Aviso
    }
    else {
        $servico = Show-EscolhaServico -Servicos $servicos
        if ($servico) { Start-ConsoleLogs -Ctx $Ctx -Servico $servico }
    }
    Show-MenuDoPainel
}

function Invoke-RestaurarPeloPainel {
    param([Parameter(Mandatory = $true)][hashtable]$Ctx)
    $pasta = Select-PastaBackup -PastaInicial $Ctx.PastaBackups
    if (-not $pasta) {
        Show-MenuDoPainel
        return
    }
    $null = Invoke-OperacaoDoPainel -Titulo 'Restaurar um backup' -Trabalho { Invoke-Doceterapia -Ctx $Ctx -Argumentos @('restore', $pasta) }
}
