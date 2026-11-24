function Invoke-ComandoCriarAtalhos {
    param([Parameter(Mandatory = $true)][hashtable]$Ctx)
    $null = New-AtalhoPainel -Ctx $Ctx
    $null = New-AtalhoSistema -Ctx $Ctx -Url (Get-UrlSistema -Ctx $Ctx)
}
