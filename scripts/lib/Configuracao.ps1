# Rules about the env file's content, shared by init, up, atualizar and resetar-banco.

$CHAVES_ASSISTENTE_CLOUD_API = @(
    'CLOUD_API_PHONE_ID', 'CLOUD_API_TOKEN', 'CLOUD_API_APP_SECRET',
    'GEMINI_API_KEY', 'NGROK_AUTHTOKEN', 'NGROK_DOMAIN'
)
$CHAVES_ASSISTENTE_BAILEYS = @('GEMINI_API_KEY')

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

function Read-NomeDona {
    for ($tentativa = 0; $tentativa -lt 3; $tentativa++) {
        $digitado = "$(Read-Entrada -Pergunta 'Nome da DONA (Enter para usar Dona)')".Trim()
        if (Test-NomeDonaValido $digitado) { return $digitado }
        Write-Aviso 'O nome precisa ter de 3 a 50 caracteres, sem aspas simples e sem terminar com barra invertida.'
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
            Write-Aviso 'A senha precisa ter de 6 a 20 caracteres, sem aspas simples e sem terminar com barra invertida.'
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
