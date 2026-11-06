$LOGIN_TENTATIVAS = 5
$LOGIN_INTERVALO_S = 3

function Get-PortaFrontEnd {
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()]$Linhas)
    $porta = Get-ValorEnv -Linhas $Linhas -Chave 'FRONTEND_HOST_PORT'
    if ($porta) { return $porta }
    return '3000'
}

function Get-IpLocal {
    try {
        $endereco = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop |
            Where-Object { $_.IPAddress -notmatch '^(127\.|169\.254\.)' -and $_.InterfaceAlias -notmatch 'vEthernet|WSL|Loopback|Docker' } |
            Select-Object -First 1
        if ($endereco) { return $endereco.IPAddress }
    }
    catch {
        Write-Verbose 'Local address not available.'
    }
    return $null
}

function Invoke-ImagensFaltantes {
    param([Parameter(Mandatory = $true)][hashtable]$Ctx)
    $imagens = @((Invoke-Compose -Ctx $Ctx -Argumentos @('config', '--images') -Capturar).Saida | Where-Object { $_ })
    $falta = $Ctx.Simular
    foreach ($imagem in $imagens) {
        if ((Invoke-Docker -Ctx $Ctx -Argumentos @('image', 'inspect', '--format', '{{.Id}}', $imagem) -Capturar).Codigo -ne 0) {
            $falta = $true
        }
    }
    if ($falta -and (Invoke-Compose -Ctx $Ctx -Argumentos @('pull')).Codigo -ne 0) {
        Stop-Launcher -Codigo $CODIGO_USO -Mensagem 'Não foi possível baixar as imagens. Confira a internet e tente de novo.'
    }
}

function Confirm-UsuarioInicial {
    # The back-end creates the first user at startup and never fails when it
    # cannot, so signing in is the only proof that the password may be erased.
    param([Parameter(Mandatory = $true)][hashtable]$Ctx)
    $linhas = Read-ConfiguracaoAtual -Ctx $Ctx
    $senha = Get-ValorEnv -Linhas $linhas -Chave 'ADMIN_SENHA'
    if (-not $senha) { return }

    if ($Ctx.Simular) {
        Write-Simulacao 'entraria com o e-mail e a senha da DONA para confirmar o primeiro acesso e apagaria a senha do arquivo.'
        Set-ValorEnv -Linhas $linhas -Chave 'ADMIN_SENHA' -Valor ''
        Write-ArquivoEnv -Ctx $Ctx -Linhas $linhas
        return
    }

    $url = "http://localhost:$(Get-PortaFrontEnd -Linhas $linhas)/api/usuarios/login"
    $email = Get-ValorEnv -Linhas $linhas -Chave 'ADMIN_EMAIL'
    $status = 0
    for ($tentativa = 1; $tentativa -le $LOGIN_TENTATIVAS; $tentativa++) {
        $status = Invoke-LoginUsuario -Url $url -Email $email -Senha $senha
        if ($status -eq 200) { break }
        if ($tentativa -lt $LOGIN_TENTATIVAS) { Wait-Intervalo -Segundos $LOGIN_INTERVALO_S }
    }

    if ($status -eq 200) {
        Set-ValorEnv -Linhas $linhas -Chave 'ADMIN_SENHA' -Valor ''
        Write-ArquivoEnv -Ctx $Ctx -Linhas $linhas
        Write-Texto 'Usuária DONA pronta. A senha foi apagada do arquivo de configuração.'
        return
    }
    if ($status -eq 401) {
        Stop-Launcher -Codigo $CODIGO_BOOTSTRAP -Mensagem 'Não foi possível entrar com o e-mail e a senha da configuração. Se o sistema já tinha usuários, eles foram mantidos. Veja: doceterapia logs back-end'
    }
    Stop-Launcher -Codigo $CODIGO_BOOTSTRAP -Mensagem 'O sistema não respondeu ao confirmar o primeiro acesso. A senha continua no arquivo de configuração. Rode de novo: doceterapia up. Se persistir, veja: doceterapia logs back-end'
}

function Write-AvisosAssistente {
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()]$Linhas)
    if (@(Get-TokensAdiados -Linhas $Linhas).Count -gt 0) {
        Write-Aviso 'O sistema web funciona; o assistente do WhatsApp só funciona depois de configurar os tokens (doceterapia init)'
    }
}

function Write-EnderecosDoSistema {
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()]$Linhas)
    $porta = Get-PortaFrontEnd -Linhas $Linhas
    Write-Texto 'Sistema no ar.'
    Write-Texto "  No computador: http://localhost:$porta"
    $ip = Get-IpLocal
    if ($ip) {
        Write-Texto "  Na rede de casa: http://${ip}:$porta"
    }
    Write-Texto 'Entre com o e-mail da DONA configurado no init.'
}

function Invoke-SubidaCompleta {
    # Shared by up, atualizar and resetar-banco.
    param([Parameter(Mandatory = $true)][hashtable]$Ctx)
    Invoke-ImagensFaltantes -Ctx $Ctx
    if (-not (Invoke-SubidaAguardando -Ctx $Ctx)) {
        Stop-ServicoNaoPronto -Ctx $Ctx
    }
    Confirm-UsuarioInicial -Ctx $Ctx
    $linhas = Read-ConfiguracaoAtual -Ctx $Ctx
    Write-AvisosAssistente -Linhas $linhas
    Write-EnderecosDoSistema -Linhas $linhas
}

function Invoke-ComandoUp {
    param([Parameter(Mandatory = $true)][hashtable]$Ctx)
    Assert-ConfiguracaoPronta -Ctx $Ctx
    Assert-DockerLigado -Ctx $Ctx
    Invoke-SubidaCompleta -Ctx $Ctx
}
