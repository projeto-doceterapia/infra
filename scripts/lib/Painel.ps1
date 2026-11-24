# Actions of the launcher window. Each one runs the subcommand of the same
# name, so the window and the CLI share every rule and exit code.

$ACOES_COM_PROGRESSO = @('doctor', 'init', 'up', 'down', 'backup', 'restore', 'atualizar', 'resetar-banco')

function Invoke-AcaoComProgresso {
    # Returns the exit code; -AcaoFinal adds a button to the finished window and
    # the code is then paired with whether it was clicked.
    param(
        [Parameter(Mandatory = $true)][hashtable]$Ctx,
        [Parameter(Mandatory = $true)][string]$Titulo,
        [Parameter(Mandatory = $true)][string[]]$Argumentos,
        [string]$AcaoFinal
    )
    Start-JanelaProgresso -Titulo $Titulo
    $codigo = Invoke-Doceterapia -Ctx $Ctx -Argumentos $Argumentos
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
    $resultado = Invoke-AcaoComProgresso -Ctx $Ctx -Titulo $Rotulo -Argumentos $argumentos -AcaoFinal $acaoFinal
    if ($resultado.AcaoEscolhida) {
        $null = Invoke-Doceterapia -Ctx $Ctx -Argumentos @('abrir')
    }
}

function Invoke-MenuPrincipal {
    # The menu comes back after each action until the window is closed.
    param([Parameter(Mandatory = $true)][hashtable]$Ctx)
    while ($opcao = Show-MenuPrincipal) {
        Invoke-AcaoDoMenu -Ctx $Ctx -Comando $opcao.Comando -Rotulo $opcao.Rotulo
    }
}
