. (Join-Path $PSScriptRoot 'Apoio.ps1')

Describe 'Segredos' {
    It 'gera JWT em Base64 de 48 bytes' {
        $jwt = New-Segredo -Bytes 48 -Formato Base64
        ([Convert]::FromBase64String($jwt)).Length | Should Be 48
    }

    It 'gera segredo URL-safe de 43 caracteres' {
        $segredo = New-Segredo -Bytes 32 -Formato UrlSafe
        $segredo.Length | Should Be 43
        $segredo -cmatch '^[A-Za-z0-9_-]+$' | Should Be $true
    }

    It 'não repete valores' {
        (New-Segredo) -ceq (New-Segredo) | Should Be $false
    }

    It 'trata como pendente todo marcador do exemplo, inclusive o do JWT' {
        foreach ($chave in 'JWT_SECRET', 'MYSQL_PASSWORD', 'ORQUESTRADOR_REDIS_URL', 'NGROK_DOMAIN') {
            $linhas = Read-ArquivoEnv -Caminho (Join-Path $RAIZ_REPOSITORIO '.env.example')
            Test-SegredoPendente (Get-ValorEnv -Linhas $linhas -Chave $chave) | Should Be $true
        }
        Test-SegredoPendente '' | Should Be $true
        Test-SegredoPendente 'valor-real-ficticio' | Should Be $false
    }

    It 'não usa geradores fracos' {
        $codigo = Get-ChildItem -LiteralPath (Join-Path $RAIZ_REPOSITORIO 'scripts') -Recurse -Filter '*.ps1' |
            Select-String -Pattern 'Get-Random|System\.Random'
        @($codigo).Count | Should Be 0
    }
}
