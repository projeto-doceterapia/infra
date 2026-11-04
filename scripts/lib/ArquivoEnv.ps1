# The only code allowed to read or write the env file. It must stay UTF-8
# without BOM and with LF: a BOM becomes part of the first key and a CR becomes
# part of every value. Set-Content, Out-File and > break one or the other on 5.1.

$MASCARA = '********'

function New-ListaLinhas {
    return , (New-Object 'System.Collections.Generic.List[string]')
}

function Read-ArquivoEnv {
    param([Parameter(Mandatory = $true)][string]$Caminho)
    $utf8SemBom = New-Object System.Text.UTF8Encoding($false)
    $lista = New-ListaLinhas
    foreach ($linha in [System.IO.File]::ReadAllLines($Caminho, $utf8SemBom)) {
        # The example may reach this point with CRLF from a core.autocrlf checkout.
        $lista.Add($linha.TrimEnd("`r").TrimStart([char]0xFEFF))
    }
    return , $lista
}

function Get-ChaveDaLinha {
    param([AllowEmptyString()][string]$Linha)
    if ($Linha -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=') {
        return $Matches[1]
    }
    return $null
}

function ConvertFrom-ValorBruto {
    param([AllowEmptyString()][string]$Bruto)
    $valor = $Bruto.Trim()
    if ($valor.Length -ge 2 -and (($valor[0] -eq "'" -and $valor[-1] -eq "'") -or ($valor[0] -eq '"' -and $valor[-1] -eq '"'))) {
        return $valor.Substring(1, $valor.Length - 2)
    }
    return ($valor -replace '\s+#.*$', '')
}

function Get-ValorEnv {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()]$Linhas,
        [Parameter(Mandatory = $true)][string]$Chave
    )
    $valor = $null
    # Compose keeps the last occurrence of a repeated key, so this does too.
    foreach ($linha in $Linhas) {
        if ((Get-ChaveDaLinha $linha) -ceq $Chave) {
            $valor = ConvertFrom-ValorBruto ($linha.Substring($linha.IndexOf('=') + 1))
        }
    }
    return $valor
}

function Set-ValorEnv {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()]$Linhas,
        [Parameter(Mandatory = $true)][string]$Chave,
        [AllowEmptyString()][string]$Valor = ''
    )
    $encontrou = $false
    for ($i = 0; $i -lt $Linhas.Count; $i++) {
        if ((Get-ChaveDaLinha $Linhas[$i]) -ceq $Chave) {
            $Linhas[$i] = "$Chave=$Valor"
            $encontrou = $true
        }
    }
    if (-not $encontrou) {
        $Linhas.Add("$Chave=$Valor")
    }
}

function Get-ChavesEnv {
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()]$Linhas)
    foreach ($linha in $Linhas) {
        $chave = Get-ChaveDaLinha $linha
        if ($chave) { $chave }
    }
}

function Complete-ChavesNovas {
    # Copies the example's keys the file does not have yet, leaving existing ones alone.
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()]$Linhas,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()]$LinhasExemplo
    )
    $existentes = @(Get-ChavesEnv -Linhas $Linhas)
    foreach ($linha in $LinhasExemplo) {
        $chave = Get-ChaveDaLinha $linha
        if ($chave -and ($existentes -cnotcontains $chave)) {
            $Linhas.Add($linha)
        }
    }
}

function Test-ValorDigitavel {
    # Typed values are written single-quoted so compose keeps $ and # literally.
    # Compose has no escape for a quote inside, and it reads a final backslash
    # as escaping the closing quote.
    param([AllowEmptyString()][string]$Valor)
    return -not ($Valor -match "['\r\n]" -or $Valor.EndsWith('\'))
}

function ConvertTo-ValorLiteral {
    param([AllowEmptyString()][string]$Valor)
    if (-not (Test-ValorDigitavel $Valor)) {
        Stop-Launcher -Codigo $CODIGO_USO -Mensagem 'O valor digitado não pode ter aspas simples, quebra de linha nem terminar com barra invertida.'
    }
    return "'$Valor'"
}

function Set-PermissaoSoUsuario {
    # Replaces the whole list instead of only cutting inheritance: in a folder
    # without inheritable entries, such as some temp folders, a new file gets
    # explicit entries for SYSTEM and Administrators from the process token.
    # Hardening only: a failure here must not stop the installation.
    param([Parameter(Mandatory = $true)][string]$Caminho)
    try {
        $usuario = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
        $acesso = New-Object System.Security.AccessControl.FileSecurity
        $acesso.SetAccessRuleProtection($true, $false)
        $regra = New-Object System.Security.AccessControl.FileSystemAccessRule($usuario, 'FullControl', 'Allow')
        $acesso.AddAccessRule($regra)
        [System.IO.File]::SetAccessControl($Caminho, $acesso)
    }
    catch {
        Write-Aviso 'Não foi possível restringir a permissão do arquivo de configuração ao usuário atual.'
    }
}

function Write-ChavesAlteradas {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()]$Linhas,
        [Parameter(Mandatory = $true)][string]$Caminho
    )
    $atuais = @{}
    if (Test-Path -LiteralPath $Caminho) {
        $linhasAtuais = Read-ArquivoEnv -Caminho $Caminho
        foreach ($chave in Get-ChavesEnv -Linhas $linhasAtuais) {
            $atuais[$chave] = Get-ValorEnv -Linhas $linhasAtuais -Chave $chave
        }
    }
    foreach ($chave in Get-ChavesEnv -Linhas $Linhas) {
        if (-not $atuais.ContainsKey($chave) -or $atuais[$chave] -cne (Get-ValorEnv -Linhas $Linhas -Chave $chave)) {
            Write-Simulacao "gravaria $chave=$MASCARA"
        }
    }
}

function Write-ArquivoEnv {
    param(
        [Parameter(Mandatory = $true)][hashtable]$Ctx,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()]$Linhas
    )
    $caminhoEnv = $Ctx.CaminhoEnv
    if ($Ctx.Simular) {
        Write-ChavesAlteradas -Linhas $Linhas -Caminho $caminhoEnv
        return
    }
    $caminhoTemporario = Join-Path (Split-Path -Parent $caminhoEnv) '.env.tmp'
    $utf8SemBom = New-Object System.Text.UTF8Encoding($false)
    $texto = (@($Linhas) -join "`n") + "`n"
    [System.IO.File]::WriteAllText($caminhoTemporario, $texto, $utf8SemBom)
    # Restricted before the move so the final name never has the inherited access.
    Set-PermissaoSoUsuario -Caminho $caminhoTemporario
    Move-Item -LiteralPath $caminhoTemporario -Destination $caminhoEnv -Force
}
