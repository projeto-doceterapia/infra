# Actions of the launcher window. Each one runs the subcommand of the same
# name, so the window and the CLI share every rule and exit code.

$ACOES_COM_PROGRESSO = @('doctor', 'up', 'down', 'backup', 'restore', 'atualizar', 'resetar-banco')

function Invoke-AcaoComProgresso {
    # The action returns an exit code. -AcaoFinal adds a button to the finished
    # window; the result says whether it was clicked.
    param(
        [Parameter(Mandatory = $true)][string]$Titulo,
        [Parameter(Mandatory = $true)][scriptblock]$Acao,
        [string]$AcaoFinal
    )
    Start-JanelaProgresso -Titulo $Titulo
    $codigo = [int](@(& $Acao)[-1])
    $sucesso = ($codigo -eq $CODIGO_SUCESSO)
    $mensagem = if ($sucesso) { 'Concluído.' } else { "$(Get-UltimoErro)" }
    if (-not $mensagem) { $mensagem = 'A operação não terminou.' }
    $escolhida = Complete-JanelaProgresso -Sucesso $sucesso -Mensagem $mensagem -AcaoFinal $AcaoFinal
    return [pscustomobject]@{ Codigo = $codigo; AcaoEscolhida = $escolhida }
}

function Invoke-AcaoDoMenu {
    param(
        [Parameter(Mandatory = $true)][hashtable]$Ctx,
        [Parameter(Mandatory = $true)][string]$Comando,
        [Parameter(Mandatory = $true)][string]$Rotulo
    )
    switch ($Comando) {
        'abrir' { Invoke-AbrirPeloPainel -Ctx $Ctx; return }
        'configurar' { Invoke-AssistenteConfiguracao -Ctx $Ctx; return }
        'configuracoes' { Invoke-JanelaConfiguracoes -Ctx $Ctx; return }
        'ver-logs' { Invoke-VerLogs -Ctx $Ctx; return }
    }
    if ($ACOES_COM_PROGRESSO -notcontains $Comando) {
        $null = Invoke-Doceterapia -Ctx $Ctx -Argumentos @($Comando)
        return
    }
    $argumentos = @($Comando)
    if ($Comando -eq 'restore') {
        $pasta = Select-PastaBackup -Ctx $Ctx
        if (-not $pasta) { return }
        $argumentos += $pasta
    }
    $acaoFinal = if ($Comando -eq 'up') { 'Abrir sistema' } else { $null }
    $resultado = Invoke-AcaoComProgresso -Titulo $Rotulo -AcaoFinal $acaoFinal -Acao { Invoke-Doceterapia -Ctx $Ctx -Argumentos $argumentos }
    if ($resultado.AcaoEscolhida) {
        Invoke-AbrirPeloPainel -Ctx $Ctx
    }
}

function Get-EstadoDoPainel {
    param([Parameter(Mandatory = $true)][hashtable]$Ctx)
    $configurado = Test-Path -LiteralPath $Ctx.CaminhoEnv
    $url = Get-UrlSistema -Ctx $Ctx
    return [pscustomobject]@{
        Configurado = $configurado
        Url         = $url
        Ligado      = ($configurado -and (Test-SistemaRespondendo -Url $url))
    }
}

function Invoke-AbrirPeloPainel {
    # A stopped system is offered a start first, so the button always ends on
    # the open application.
    param([Parameter(Mandatory = $true)][hashtable]$Ctx)
    $url = Get-UrlSistema -Ctx $Ctx
    if (-not (Test-SistemaRespondendo -Url $url)) {
        if (-not (Read-SimNao -Pergunta 'O sistema está desligado. Ligar agora e abrir em seguida?' -Padrao $true)) { return }
        $resultado = Invoke-AcaoComProgresso -Titulo 'Ligar o sistema' -Acao { Invoke-Doceterapia -Ctx $Ctx -Argumentos @('up') }
        if ($resultado.Codigo -ne $CODIGO_SUCESSO) { return }
    }
    Start-AplicativoNavegador -Ctx $Ctx -Url $url
}

function Invoke-VerLogs {
    param([Parameter(Mandatory = $true)][hashtable]$Ctx)
    $estado = @{ Servicos = @() }
    $codigo = Invoke-ComTratamento -Acao {
        Assert-ConfiguracaoExiste -Ctx $Ctx
        Assert-DockerLigado -Ctx $Ctx
        $estado.Servicos = @(Get-ServicosEmExecucao -Ctx $Ctx)
    }
    if ($codigo -ne $CODIGO_SUCESSO) { return }
    if ($estado.Servicos.Count -eq 0) {
        Show-Mensagem -Texto 'Nenhum serviço está ligado. Ligue o sistema para ver os registros.' -Tipo Aviso
        return
    }
    $servico = Show-EscolhaServico -Servicos $estado.Servicos
    if ($servico) { Start-ConsoleLogs -Ctx $Ctx -Servico $servico }
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

function Invoke-AssistenteConfiguracao {
    param([Parameter(Mandatory = $true)][hashtable]$Ctx)
    if ((Invoke-ComTratamento -Acao { Assert-DockerLigado -Ctx $Ctx }) -ne $CODIGO_SUCESSO) { return }
    $bancoExiste = Test-BancoExiste -Ctx $Ctx
    $linhas = Read-ConfiguracaoAtual -Ctx $Ctx
    $respostas = Show-Assistente -Linhas $linhas -PedirDona (Test-DonaPendente -Linhas $linhas -BancoExiste $bancoExiste) -PedirDemo (-not $bancoExiste)
    if (-not $respostas) { return }

    $Ctx.Respostas = $respostas
    try {
        $resultado = Invoke-AcaoComProgresso -Titulo 'Configurar e ligar o sistema' -AcaoFinal 'Abrir sistema' -Acao {
            $codigo = Invoke-Doceterapia -Ctx $Ctx -Argumentos @('init')
            if ($codigo -ne $CODIGO_SUCESSO) { return $codigo }
            Invoke-Doceterapia -Ctx $Ctx -Argumentos @('up')
        }
    }
    finally {
        $Ctx.Remove('Respostas')
    }
    if ($resultado.AcaoEscolhida) {
        Invoke-AbrirPeloPainel -Ctx $Ctx
    }
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

function Invoke-JanelaConfiguracoes {
    param([Parameter(Mandatory = $true)][hashtable]$Ctx)
    if (-not (Test-Path -LiteralPath $Ctx.CaminhoEnv)) {
        Show-Mensagem -Texto 'O sistema ainda não foi configurado. Use primeiro o botão Configurar.' -Tipo Aviso
        return
    }
    $valores = Show-Configuracoes -Linhas (Read-ArquivoEnv -Caminho $Ctx.CaminhoEnv)
    if (-not $valores) { return }

    $estado = @{ Plano = $null }
    if ((Invoke-ComTratamento -Acao { $estado.Plano = Save-Configuracoes -Ctx $Ctx -Valores $valores }) -ne $CODIGO_SUCESSO) { return }
    $plano = $estado.Plano
    if (-not $plano) {
        Show-Mensagem -Texto 'Nada foi alterado.'
        return
    }
    if (-not $plano.Completo -and $plano.Servicos.Count -eq 0) {
        Show-Mensagem -Texto 'Configuração salva.'
        return
    }
    $null = Invoke-AcaoComProgresso -Titulo 'Aplicar as configurações' -Acao {
        Clear-ResumoDaSessao
        Invoke-ComTratamento -Acao { Invoke-PlanoDeReinicio -Ctx $Ctx -Plano $plano }
    }
}

function Invoke-MenuPrincipal {
    # The menu comes back after each action until the window is closed.
    param([Parameter(Mandatory = $true)][hashtable]$Ctx)
    while ($opcao = Show-MenuPrincipal -Estado (Get-EstadoDoPainel -Ctx $Ctx)) {
        Invoke-AcaoDoMenu -Ctx $Ctx -Comando $opcao.Comando -Rotulo $opcao.Rotulo
    }
}
