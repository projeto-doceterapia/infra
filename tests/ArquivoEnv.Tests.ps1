. (Join-Path $PSScriptRoot 'Apoio.ps1')

Describe 'ArquivoEnv' {
    It 'grava sem BOM e com LF' {
        $ctx = New-RaizDeTeste -Pasta (Join-Path $TestDrive 'bom')
        $linhas = Read-ArquivoEnv -Caminho $ctx.CaminhoExemplo
        Write-ArquivoEnv -Ctx $ctx -Linhas $linhas

        $bytes = [System.IO.File]::ReadAllBytes($ctx.CaminhoEnv)
        ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) | Should Be $false
        ($bytes -contains 13) | Should Be $false
        $bytes[-1] | Should Be 10
    }

    It 'lê CRLF sem deixar \r em nenhum valor' {
        $ctx = New-RaizDeTeste -Pasta (Join-Path $TestDrive 'crlf') -ExemploCrlf
        $bytes = [System.IO.File]::ReadAllBytes($ctx.CaminhoExemplo)
        ($bytes -contains 13) | Should Be $true

        $linhas = Read-ArquivoEnv -Caminho $ctx.CaminhoExemplo
        foreach ($linha in $linhas) {
            $linha.EndsWith("`r") | Should Be $false
        }
        Get-ValorEnv -Linhas $linhas -Chave 'CHANNEL' | Should Be 'cloud_api'
    }

    It 'preserva comentários e ordem do exemplo' {
        $ctx = New-RaizDeTeste -Pasta (Join-Path $TestDrive 'ordem')
        $linhas = Read-ArquivoEnv -Caminho $ctx.CaminhoExemplo
        $original = @($linhas)
        Set-ValorEnv -Linhas $linhas -Chave 'CHANNEL' -Valor 'baileys'
        Write-ArquivoEnv -Ctx $ctx -Linhas $linhas

        $relido = Read-ArquivoEnv -Caminho $ctx.CaminhoEnv
        $relido.Count | Should Be $original.Count
        $relido[0] | Should Be $original[0]
        Get-ValorEnv -Linhas $relido -Chave 'CHANNEL' | Should Be 'baileys'
    }

    It 'lê valor entre aspas simples literalmente' {
        $linhas = New-ListaLinhas
        $linhas.Add("ADMIN_SENHA='a`$b#c d'")
        Get-ValorEnv -Linhas $linhas -Chave 'ADMIN_SENHA' | Should Be 'a$b#c d'
    }

    It 'recusa aspa simples, quebra de linha e barra final no valor digitado' {
        Test-ValorDigitavel "a'b" | Should Be $false
        Test-ValorDigitavel "a`nb" | Should Be $false
        Test-ValorDigitavel 'ab\' | Should Be $false
        Test-ValorDigitavel 'a$b#c"d\e' | Should Be $true
    }

    It 'acrescenta só as chaves novas, sem tocar nas existentes' {
        $linhas = New-ListaLinhas
        $linhas.Add('A=existente')
        $exemplo = New-ListaLinhas
        $exemplo.Add('# comentario')
        $exemplo.Add('A=do-exemplo')
        $exemplo.Add('B=novo')
        Complete-ChavesNovas -Linhas $linhas -LinhasExemplo $exemplo
        Get-ValorEnv -Linhas $linhas -Chave 'A' | Should Be 'existente'
        Get-ValorEnv -Linhas $linhas -Chave 'B' | Should Be 'novo'
    }

    It 'restringe a permissão ao usuário atual' {
        $ctx = New-RaizDeTeste -Pasta (Join-Path $TestDrive 'acl')
        Write-ArquivoEnv -Ctx $ctx -Linhas (Read-ArquivoEnv -Caminho $ctx.CaminhoExemplo)

        $acl = Get-Acl -LiteralPath $ctx.CaminhoEnv
        $acl.AreAccessRulesProtected | Should Be $true
        $atual = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
        $regras = @($acl.GetAccessRules($true, $true, [System.Security.Principal.SecurityIdentifier]))
        $regras.Count | Should Be 1
        $regras[0].IdentityReference.Value | Should Be $atual.Value
    }

    It 'não deixa o arquivo temporário para trás' {
        $ctx = New-RaizDeTeste -Pasta (Join-Path $TestDrive 'tmp')
        Write-ArquivoEnv -Ctx $ctx -Linhas (Read-ArquivoEnv -Caminho $ctx.CaminhoExemplo)
        Test-Path -LiteralPath (Join-Path $ctx.Raiz '.env.tmp') | Should Be $false
    }
}
