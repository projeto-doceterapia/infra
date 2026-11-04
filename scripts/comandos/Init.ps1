function Read-Canal {
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()]$Linhas)
    $atual = Get-ValorEnv -Linhas $Linhas -Chave 'CHANNEL'
    if (-not $atual) { $atual = 'cloud_api' }
    for ($tentativa = 0; $tentativa -lt 3; $tentativa++) {
        $digitado = "$(Read-Entrada -Pergunta "Canal do WhatsApp: cloud_api ou baileys [$atual]")".Trim()
        if (-not $digitado) { return $atual }
        if ($digitado -cin 'cloud_api', 'baileys') { return $digitado }
        Write-Aviso 'Escolha cloud_api ou baileys.'
    }
    return $atual
}

function Read-TelefoneBeneficiaria {
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()]$Linhas)
    $atual = Get-ValorEnv -Linhas $Linhas -Chave 'BENEFICIARIA_TELEFONE'
    for ($tentativa = 0; $tentativa -lt 3; $tentativa++) {
        $digitado = "$(Read-Entrada -Pergunta "Telefone da beneficiária no formato +5511900000001 [$atual]")".Trim()
        if (-not $digitado) { return $atual }
        if ($digitado -match '^\+[1-9]\d{7,14}$') { return $digitado }
        Write-Aviso 'Telefone inválido. Use o formato +5511900000001.'
    }
    return $atual
}

function Set-TokenAdiavel {
    # Enter defers: the placeholder stays, which compose accepts because its
    # required-variable check refuses only empty values.
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()]$Linhas,
        [Parameter(Mandatory = $true)][string]$Chave,
        [Parameter(Mandatory = $true)][string]$Pergunta,
        [switch]$Oculto
    )
    if (-not (Test-SegredoPendente (Get-ValorEnv -Linhas $Linhas -Chave $Chave))) { return }
    for ($tentativa = 0; $tentativa -lt 3; $tentativa++) {
        if ($Oculto) {
            $digitado = Read-SenhaOculta -Pergunta "$Pergunta (Enter para adiar)"
        }
        else {
            $digitado = "$(Read-Entrada -Pergunta "$Pergunta (Enter para adiar)")".Trim()
        }
        if (-not $digitado) { return }
        if (Test-ValorDigitavel $digitado) {
            Set-ValorEnv -Linhas $Linhas -Chave $Chave -Valor (ConvertTo-ValorLiteral $digitado)
            return
        }
        Write-Aviso 'O valor não pode ter aspas simples, quebra de linha nem terminar com barra invertida.'
    }
}

function Set-DominioNgrok {
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()]$Linhas)
    if (-not (Test-SegredoPendente (Get-ValorEnv -Linhas $Linhas -Chave 'NGROK_DOMAIN'))) { return }
    for ($tentativa = 0; $tentativa -lt 3; $tentativa++) {
        $digitado = "$(Read-Entrada -Pergunta 'Domínio fixo do ngrok (Enter para adiar)')".Trim()
        if (-not $digitado) { return }
        $dominio = $digitado -replace '^https?://', '' -replace '/+$', ''
        if ($dominio -match '^[A-Za-z0-9.\-]+$') {
            Set-ValorEnv -Linhas $Linhas -Chave 'NGROK_DOMAIN' -Valor $dominio
            return
        }
        Write-Aviso 'Domínio inválido. Exemplo: meu-dominio.ngrok-free.app'
    }
}

function Set-RespostasDoInit {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()]$Linhas,
        [Parameter(Mandatory = $true)][bool]$BancoExiste
    )
    if (-not $BancoExiste) {
        $senhaAtual = Get-ValorEnv -Linhas $Linhas -Chave 'ADMIN_SENHA'
        $emailAtual = Get-ValorEnv -Linhas $Linhas -Chave 'ADMIN_EMAIL'
        if (-not $senhaAtual -or -not $emailAtual) {
            Set-CredenciaisDona -Linhas $Linhas -Credenciais (Read-CredenciaisDona)
        }
        $demo = Read-SimNao -Pergunta 'Carregar dados de demonstração?' -Padrao $false
        Set-ValorEnv -Linhas $Linhas -Chave 'DEMO_DATA' -Valor $(if ($demo) { 'true' } else { 'false' })
    }

    $canal = Read-Canal -Linhas $Linhas
    Set-ValorEnv -Linhas $Linhas -Chave 'CHANNEL' -Valor $canal
    Set-ValorEnv -Linhas $Linhas -Chave 'BENEFICIARIA_TELEFONE' -Valor (Read-TelefoneBeneficiaria -Linhas $Linhas)

    if ($canal -eq 'cloud_api') {
        Set-TokenAdiavel -Linhas $Linhas -Chave 'CLOUD_API_PHONE_ID' -Pergunta 'Identificador do número na Cloud API'
        Set-TokenAdiavel -Linhas $Linhas -Chave 'CLOUD_API_TOKEN' -Pergunta 'Token da Cloud API' -Oculto
        Set-TokenAdiavel -Linhas $Linhas -Chave 'CLOUD_API_APP_SECRET' -Pergunta 'Segredo do aplicativo da Cloud API' -Oculto
        Set-TokenAdiavel -Linhas $Linhas -Chave 'NGROK_AUTHTOKEN' -Pergunta 'Token do ngrok' -Oculto
        Set-DominioNgrok -Linhas $Linhas
    }
    Set-TokenAdiavel -Linhas $Linhas -Chave 'GEMINI_API_KEY' -Pergunta 'Chave do Gemini' -Oculto
}

function Invoke-ComandoInit {
    param([Parameter(Mandatory = $true)][hashtable]$Ctx)

    Invoke-ComandoDoctor -Ctx $Ctx

    if (-not (Test-Path -LiteralPath $Ctx.CaminhoExemplo)) {
        Stop-Launcher -Codigo $CODIGO_CONFIGURACAO -Mensagem 'O arquivo de exemplo da configuração não foi encontrado. Baixe a pasta infra de novo.'
    }
    $exemplo = Read-ArquivoEnv -Caminho $Ctx.CaminhoExemplo
    if (Test-Path -LiteralPath $Ctx.CaminhoEnv) {
        $linhas = Read-ArquivoEnv -Caminho $Ctx.CaminhoEnv
        Complete-ChavesNovas -Linhas $linhas -LinhasExemplo $exemplo
    }
    else {
        $linhas = $exemplo
    }

    Set-SegredosGerados -Linhas $linhas

    $bancoExiste = Test-BancoExiste -Ctx $Ctx
    if ($Ctx.Simular) {
        Write-Simulacao 'perguntaria e-mail e senha da DONA, dados de demonstração, canal, telefone e tokens externos.'
    }
    else {
        Set-RespostasDoInit -Linhas $linhas -BancoExiste $bancoExiste
    }

    Write-ArquivoEnv -Ctx $Ctx -Linhas $linhas

    $validacao = Invoke-Compose -Ctx $Ctx -Argumentos @('config', '--quiet')
    if ($validacao.Codigo -ne 0) {
        Stop-Launcher -Codigo $CODIGO_CONFIGURACAO -Mensagem 'A configuração foi gravada, mas o Docker a recusou. Veja a mensagem acima.'
    }
    Write-Texto 'Configuração pronta. Agora rode: doceterapia up'
}
