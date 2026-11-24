function Invoke-ComandoCriarAtalho {
    param([Parameter(Mandatory = $true)][hashtable]$Ctx)
    $null = New-AtalhoDoceterapia -Ctx $Ctx
}
