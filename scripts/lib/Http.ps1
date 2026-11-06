# HTTP sign-in used to confirm the first user. The body carries the password, so
# neither it nor the request details are ever printed.

function Invoke-LoginUsuario {
    # Returns the HTTP status, or 0 when the server did not answer.
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [AllowEmptyString()][string]$Email,
        [AllowEmptyString()][string]$Senha
    )
    $corpo = @{ email = $Email; senha = $Senha } | ConvertTo-Json -Compress
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($corpo)
    $progresso = $ProgressPreference
    $ProgressPreference = 'SilentlyContinue'
    try {
        $resposta = Invoke-WebRequest -Uri $Url -Method Post -UseBasicParsing -TimeoutSec 15 `
            -ContentType 'application/json; charset=utf-8' -Body $bytes
        return [int]$resposta.StatusCode
    }
    catch {
        $respostaErro = $_.Exception.Response
        if ($null -ne $respostaErro) {
            return [int]$respostaErro.StatusCode
        }
        return 0
    }
    finally {
        $ProgressPreference = $progresso
    }
}
