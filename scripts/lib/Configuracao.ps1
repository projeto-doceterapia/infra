# Rules about the env file's content, shared by init, up, atualizar and resetar-banco.

$CHAVES_ASSISTENTE_CLOUD_API = @(
    'CLOUD_API_PHONE_ID', 'CLOUD_API_TOKEN', 'CLOUD_API_APP_SECRET',
    'GEMINI_API_KEY', 'NGROK_AUTHTOKEN', 'NGROK_DOMAIN'
)
$CHAVES_ASSISTENTE_BAILEYS = @('GEMINI_API_KEY')

# External values asked by init and edited later in the settings window. Canal
# names the only channel that uses the key; $null means every channel.
$CAMPOS_EXTERNOS = @(
    @{ Chave = 'CLOUD_API_PHONE_ID'; Rotulo = 'Identificador do número na Cloud API'; Oculto = $false; Canal = 'cloud_api' },
    @{ Chave = 'CLOUD_API_TOKEN'; Rotulo = 'Token da Cloud API'; Oculto = $true; Canal = 'cloud_api' },
    @{ Chave = 'CLOUD_API_APP_SECRET'; Rotulo = 'Segredo do aplicativo da Cloud API'; Oculto = $true; Canal = 'cloud_api' },
    @{ Chave = 'NGROK_AUTHTOKEN'; Rotulo = 'Token do ngrok'; Oculto = $true; Canal = 'cloud_api' },
    @{ Chave = 'NGROK_DOMAIN'; Rotulo = 'Domínio fixo do ngrok'; Oculto = $false; Canal = 'cloud_api' },
    @{ Chave = 'GEMINI_API_KEY'; Rotulo = 'Chave do Gemini'; Oculto = $true; Canal = $null }
)

# Services that read each editable key, so a settings change recreates only
# them. CHANNEL is absent on purpose: it changes the active profiles.
$SERVICOS_POR_CHAVE = @{
    BENEFICIARIA_TELEFONE = 'orquestrador'
    CLOUD_API_PHONE_ID    = 'orquestrador'
    CLOUD_API_TOKEN       = 'orquestrador'
    CLOUD_API_APP_SECRET  = 'orquestrador'
    GEMINI_API_KEY        = 'orquestrador'
    NGROK_AUTHTOKEN       = 'ngrok'
    NGROK_DOMAIN          = 'ngrok'
}

$MENSAGEM_VALOR_INVALIDO = 'O valor não pode ter aspas simples, quebra de linha nem terminar com barra invertida.'
$MENSAGEM_TELEFONE_INVALIDO = 'Telefone inválido. Use o formato +5511900000001.'
$MENSAGEM_DOMINIO_INVALIDO = 'Domínio inválido. Exemplo: meu-dominio.ngrok-free.app'
$MENSAGEM_NOME_INVALIDO = 'O nome precisa ter de 3 a 50 caracteres, sem aspas simples e sem terminar com barra invertida.'
$MENSAGEM_SENHA_INVALIDA = 'A senha precisa ter de 6 a 20 caracteres, sem aspas simples e sem terminar com barra invertida.'

function Set-SegredosGerados {
    # Fills only what is still missing or a placeholder: a secret already chosen
    # is never replaced, since the database and sessions depend on it.
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()]$Linhas)
    foreach ($chave in $SEGREDOS_URL_SAFE) {
        if (Test-SegredoPendente (Get-ValorEnv -Linhas $Linhas -Chave $chave)) {
            Set-ValorEnv -Linhas $Linhas -Chave $chave -Valor (New-Segredo -Bytes 32 -Formato UrlSafe)
        }
    }
    if (Test-SegredoPendente (Get-ValorEnv -Linhas $Linhas -Chave 'JWT_SECRET')) {
        Set-ValorEnv -Linhas $Linhas -Chave 'JWT_SECRET' -Valor (New-Segredo -Bytes 48 -Formato Base64)
    }
    if (Test-SegredoPendente (Get-ValorEnv -Linhas $Linhas -Chave 'DB_PASSWORD')) {
        Set-ValorEnv -Linhas $Linhas -Chave 'DB_PASSWORD' -Valor (Get-ValorEnv -Linhas $Linhas -Chave 'MYSQL_PASSWORD')
    }
    if (Test-SegredoPendente (Get-ValorEnv -Linhas $Linhas -Chave 'ORQUESTRADOR_REDIS_URL')) {
        $senhaRedis = [uri]::EscapeDataString((Get-ValorEnv -Linhas $Linhas -Chave 'REDIS_PASSWORD'))
        Set-ValorEnv -Linhas $Linhas -Chave 'ORQUESTRADOR_REDIS_URL' -Valor "redis://:$senhaRedis@redis:6379/0"
    }
}

function Get-SegredosPendentes {
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()]$Linhas)
    return @($SEGREDOS_GERADOS | Where-Object { Test-SegredoPendente (Get-ValorEnv -Linhas $Linhas -Chave $_) })
}

function Get-TokensAdiados {
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()]$Linhas)
    $chaves = if ((Get-ValorEnv -Linhas $Linhas -Chave 'CHANNEL') -eq 'baileys') { $CHAVES_ASSISTENTE_BAILEYS } else { $CHAVES_ASSISTENTE_CLOUD_API }
    return @($chaves | Where-Object { Test-SegredoPendente (Get-ValorEnv -Linhas $Linhas -Chave $_) })
}

function Assert-ConfiguracaoExiste {
    # Compose cannot even parse the stack without the file. Enough for commands
    # that only look at or stop what is running.
    param([Parameter(Mandatory = $true)][hashtable]$Ctx)
    if (Test-Path -LiteralPath $Ctx.CaminhoEnv) { return }
    if ($Ctx.Simular) {
        Write-Simulacao 'a configuração ainda não existe; simulando com os valores do exemplo.'
        return
    }
    Stop-Launcher -Codigo $CODIGO_CONFIGURACAO -Mensagem $MENSAGEM_SEM_CONFIGURACAO
}

function Assert-ConfiguracaoPronta {
    param([Parameter(Mandatory = $true)][hashtable]$Ctx)
    Assert-ConfiguracaoExiste -Ctx $Ctx
    if (-not (Test-Path -LiteralPath $Ctx.CaminhoEnv)) { return }
    if (@(Get-SegredosPendentes -Linhas (Read-ArquivoEnv -Caminho $Ctx.CaminhoEnv)).Count -gt 0) {
        Stop-Launcher -Codigo $CODIGO_CONFIGURACAO -Mensagem 'A configuração está incompleta. Rode de novo: doceterapia init'
    }
}

function Test-BancoExiste {
    param([Parameter(Mandatory = $true)][hashtable]$Ctx)
    return (@(Get-VolumesDoProjeto -Ctx $Ctx -Volume 'banco-de-dados-data').Count -gt 0)
}

function Test-EmailValido {
    param([AllowEmptyString()][string]$Email)
    return ($Email -match '^[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$')
}

function Test-SenhaDonaValida {
    param([AllowEmptyString()][string]$Senha)
    return ($Senha.Length -ge 6 -and $Senha.Length -le 20 -and (Test-ValorDigitavel $Senha))
}

function Test-NomeDonaValido {
    # Blank is valid: the back-end then uses its default name. The length range
    # is the one the back-end enforces for the first user.
    param([AllowEmptyString()][string]$Nome)
    if (-not $Nome) { return $true }
    return ($Nome.Length -ge 3 -and $Nome.Length -le 50 -and (Test-ValorDigitavel $Nome))
}

function Test-TelefoneValido {
    param([AllowEmptyString()][string]$Telefone)
    return ($Telefone -match '^\+[1-9]\d{7,14}$')
}

function ConvertTo-DominioNgrok {
    # Accepts a pasted URL; returns $null when what is left is not a host name.
    param([AllowEmptyString()][string]$Valor)
    $dominio = $Valor.Trim() -replace '^https?://', '' -replace '/+$', ''
    if ($dominio -match '^[A-Za-z0-9.\-]+$') { return $dominio }
    return $null
}

function Get-CamposDoCanal {
    param([Parameter(Mandatory = $true)][string]$Canal)
    return @($CAMPOS_EXTERNOS | Where-Object { -not $_.Canal -or $_.Canal -eq $Canal })
}

function Get-ErrosDaDona {
    # One message per field, for inline display; empty when all is valid.
    param(
        [AllowEmptyString()][string]$Nome = '',
        [AllowEmptyString()][string]$Email = '',
        [AllowEmptyString()][string]$Senha = '',
        [AllowEmptyString()][string]$Confirmacao = ''
    )
    $erros = @{}
    if (-not (Test-NomeDonaValido $Nome.Trim())) { $erros.Nome = $MENSAGEM_NOME_INVALIDO }
    if (-not (Test-EmailValido $Email.Trim())) { $erros.Email = 'E-mail inválido. Exemplo: dona@exemplo.com' }
    if (-not (Test-SenhaDonaValida $Senha)) { $erros.Senha = $MENSAGEM_SENHA_INVALIDA }
    elseif ($Senha -cne $Confirmacao) { $erros.Confirmacao = 'As senhas não são iguais.' }
    return $erros
}

function Get-ErrosDoAssistente {
    # Values are keyed by env key. A blank value keeps what is configured.
    param([Parameter(Mandatory = $true)][hashtable]$Valores)
    $erros = @{}
    foreach ($chave in @($Valores.Keys)) {
        $valor = "$($Valores[$chave])".Trim()
        if (-not $valor) { continue }
        switch ($chave) {
            'CHANNEL' { if ($valor -cnotin 'cloud_api', 'baileys') { $erros[$chave] = 'Escolha cloud_api ou baileys.' } }
            'BENEFICIARIA_TELEFONE' { if (-not (Test-TelefoneValido $valor)) { $erros[$chave] = $MENSAGEM_TELEFONE_INVALIDO } }
            'NGROK_DOMAIN' { if (-not (ConvertTo-DominioNgrok $valor)) { $erros[$chave] = $MENSAGEM_DOMINIO_INVALIDO } }
            default { if (-not (Test-ValorDigitavel $valor)) { $erros[$chave] = $MENSAGEM_VALOR_INVALIDO } }
        }
    }
    return $erros
}

function Set-ValoresDoAssistente {
    # Writes only the values given; the caller validated them first.
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()]$Linhas,
        [Parameter(Mandatory = $true)][hashtable]$Valores
    )
    foreach ($chave in @($Valores.Keys)) {
        $valor = "$($Valores[$chave])".Trim()
        if (-not $valor) { continue }
        switch ($chave) {
            'CHANNEL' { Set-ValorEnv -Linhas $Linhas -Chave $chave -Valor $valor }
            'BENEFICIARIA_TELEFONE' { Set-ValorEnv -Linhas $Linhas -Chave $chave -Valor $valor }
            'NGROK_DOMAIN' { Set-ValorEnv -Linhas $Linhas -Chave $chave -Valor (ConvertTo-DominioNgrok $valor) }
            default { Set-ValorEnv -Linhas $Linhas -Chave $chave -Valor (ConvertTo-ValorLiteral $valor) }
        }
    }
}

function Set-RespostasInformadas {
    # The window's path into init: the same rules as the console questions.
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()]$Linhas,
        [Parameter(Mandatory = $true)][bool]$BancoExiste,
        [Parameter(Mandatory = $true)][hashtable]$Respostas
    )
    if (-not $BancoExiste) {
        if ($Respostas.Dona) {
            $dona = $Respostas.Dona
            $erros = Get-ErrosDaDona -Nome "$($dona.Nome)" -Email "$($dona.Email)" -Senha "$($dona.Senha)" -Confirmacao "$($dona.Senha)"
            if ($erros.Count -gt 0) {
                Stop-Launcher -Codigo $CODIGO_USO -Mensagem (@($erros.Values)[0])
            }
            Set-CredenciaisDona -Linhas $Linhas -Credenciais @{ Nome = "$($dona.Nome)".Trim(); Email = "$($dona.Email)".Trim(); Senha = $dona.Senha }
        }
        elseif (-not (Get-ValorEnv -Linhas $Linhas -Chave 'ADMIN_SENHA') -or -not (Get-ValorEnv -Linhas $Linhas -Chave 'ADMIN_EMAIL')) {
            Stop-Launcher -Codigo $CODIGO_USO -Mensagem 'Informe o e-mail e a senha da DONA.'
        }
        Set-ValorEnv -Linhas $Linhas -Chave 'DEMO_DATA' -Valor $(if ($Respostas.Demo) { 'true' } else { 'false' })
    }
    $valores = if ($Respostas.Valores) { $Respostas.Valores } else { @{} }
    $erros = Get-ErrosDoAssistente -Valores $valores
    if ($erros.Count -gt 0) {
        Stop-Launcher -Codigo $CODIGO_USO -Mensagem (@($erros.Values)[0])
    }
    Set-ValoresDoAssistente -Linhas $Linhas -Valores $valores
}

function Get-PlanoDeReinicio {
    # Completo when the active profiles change: services of the old profile must
    # stop, so the stack goes down and up. Otherwise only the readers restart.
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()]$Antes,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()]$Depois
    )
    $perfisAntes = @(Get-PerfisAtivos -Linhas $Antes) -join ','
    $perfisDepois = @(Get-PerfisAtivos -Linhas $Depois)
    $canalMudou = (Get-ValorEnv -Linhas $Antes -Chave 'CHANNEL') -cne (Get-ValorEnv -Linhas $Depois -Chave 'CHANNEL')
    if ($canalMudou -or $perfisAntes -cne ($perfisDepois -join ',')) {
        return [pscustomobject]@{ Completo = $true; Servicos = @() }
    }
    $servicos = @()
    foreach ($chave in $SERVICOS_POR_CHAVE.Keys) {
        if ((Get-ValorEnv -Linhas $Antes -Chave $chave) -ceq (Get-ValorEnv -Linhas $Depois -Chave $chave)) { continue }
        $servico = $SERVICOS_POR_CHAVE[$chave]
        if ($servico -eq 'ngrok' -and $perfisDepois -notcontains 'tunnel') { continue }
        if ($servicos -notcontains $servico) { $servicos += $servico }
    }
    return [pscustomobject]@{ Completo = $false; Servicos = @($servicos | Sort-Object) }
}

function Read-NomeDona {
    for ($tentativa = 0; $tentativa -lt 3; $tentativa++) {
        $digitado = "$(Read-Entrada -Pergunta 'Nome da DONA (Enter para usar Dona)')".Trim()
        if (Test-NomeDonaValido $digitado) { return $digitado }
        Write-Aviso $MENSAGEM_NOME_INVALIDO
    }
    Stop-Launcher -Codigo $CODIGO_USO -Mensagem 'Nome não aceito. Rode o comando de novo.'
}

function Read-CredenciaisDona {
    # The caller keeps the result in memory and writes it together with the rest.
    $nome = Read-NomeDona
    $email = $null
    for ($tentativa = 0; $tentativa -lt 3 -and -not $email; $tentativa++) {
        $digitado = "$(Read-Entrada -Pergunta 'E-mail da DONA')".Trim()
        if (Test-EmailValido $digitado) {
            $email = $digitado
        }
        else {
            Write-Aviso 'E-mail inválido. Exemplo: dona@exemplo.com'
        }
    }
    if (-not $email) {
        Stop-Launcher -Codigo $CODIGO_USO -Mensagem 'E-mail inválido. Rode o comando de novo.'
    }

    for ($tentativa = 0; $tentativa -lt 3; $tentativa++) {
        $senha = Read-SenhaOculta -Pergunta 'Senha da DONA (6 a 20 caracteres)'
        if (-not (Test-SenhaDonaValida $senha)) {
            Write-Aviso $MENSAGEM_SENHA_INVALIDA
            continue
        }
        $confirmacao = Read-SenhaOculta -Pergunta 'Repita a senha'
        if ($senha -cne $confirmacao) {
            Write-Aviso 'As senhas não são iguais.'
            continue
        }
        return @{ Nome = $nome; Email = $email; Senha = $senha }
    }
    Stop-Launcher -Codigo $CODIGO_USO -Mensagem 'Senha não aceita. Rode o comando de novo.'
}

function Set-CredenciaisDona {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()]$Linhas,
        [Parameter(Mandatory = $true)][hashtable]$Credenciais
    )
    $nome = "$($Credenciais.Nome)"
    Set-ValorEnv -Linhas $Linhas -Chave 'ADMIN_NOME' -Valor $(if ($nome) { ConvertTo-ValorLiteral $nome } else { '' })
    Set-ValorEnv -Linhas $Linhas -Chave 'ADMIN_EMAIL' -Valor $Credenciais.Email
    Set-ValorEnv -Linhas $Linhas -Chave 'ADMIN_SENHA' -Valor (ConvertTo-ValorLiteral $Credenciais.Senha)
}
