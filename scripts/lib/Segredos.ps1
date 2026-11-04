# Secret generation (CSPRNG only) and input that does not echo.

$SEGREDOS_URL_SAFE = @(
    'MYSQL_ROOT_PASSWORD',
    'MYSQL_PASSWORD',
    'REDIS_PASSWORD',
    'ADAPTER_SECRET',
    'WEBHOOK_SECRET',
    'CLOUD_API_VERIFY_TOKEN',
    'ORQUESTRADOR_TOKEN'
)
$SEGREDOS_GERADOS = $SEGREDOS_URL_SAFE + @('JWT_SECRET', 'DB_PASSWORD', 'ORQUESTRADOR_REDIS_URL')

function New-BytesAleatorios {
    param([int]$Bytes)
    $buffer = New-Object byte[] $Bytes
    $gerador = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $gerador.GetBytes($buffer)
    }
    finally {
        $gerador.Dispose()
    }
    return , $buffer
}

function New-Segredo {
    # URL-safe output has no $ nor #, so it needs no quoting in the env file and
    # can go inside the Redis URL.
    param(
        [int]$Bytes = 32,
        [ValidateSet('Base64', 'UrlSafe')][string]$Formato = 'UrlSafe'
    )
    $base64 = [Convert]::ToBase64String((New-BytesAleatorios -Bytes $Bytes))
    if ($Formato -eq 'Base64') {
        return $base64
    }
    return $base64.TrimEnd('=').Replace('+', '-').Replace('/', '_')
}

function Test-SegredoPendente {
    # The JWT placeholder must be valid Base64, which has no hyphen, so it starts
    # with "replaceme" instead of containing "replace-me". Missing it would ship
    # a publicly known signing key.
    param([AllowNull()][AllowEmptyString()][string]$Valor)
    if ([string]::IsNullOrEmpty($Valor)) { return $true }
    return ($Valor -match 'replace-me' -or $Valor -match '^replaceme')
}

function Read-SenhaOculta {
    param([Parameter(Mandatory = $true)][string]$Pergunta)
    $seguro = Read-Host $Pergunta -AsSecureString
    $ponteiro = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($seguro)
    try {
        return [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($ponteiro)
    }
    finally {
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ponteiro)
    }
}
