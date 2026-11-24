# Setup wizard and settings screens of the panel window. They only collect and
# validate answers; init and the restart plan apply them, so the console keeps
# the same rules.

function Get-CorErro { return [System.Drawing.Color]::FromArgb(180, 30, 30) }

function Get-CorDiscreta { return [System.Drawing.Color]::FromArgb(110, 110, 110) }

function New-CaixaTexto {
    param(
        [Parameter(Mandatory = $true)][int]$X,
        [Parameter(Mandatory = $true)][int]$Y,
        [AllowEmptyString()][string]$Texto = '',
        [switch]$Oculto,
        [int]$Largura = 340
    )
    $caixa = New-Object System.Windows.Forms.TextBox
    $caixa.Location = New-Object System.Drawing.Point($X, $Y)
    $caixa.Size = New-Object System.Drawing.Size($Largura, 26)
    $caixa.Text = $Texto
    $caixa.UseSystemPasswordChar = [bool]$Oculto
    return $caixa
}

function New-PainelDona {
    param(
        [Parameter(Mandatory = $true)][bool]$PedirDona,
        [Parameter(Mandatory = $true)][bool]$PedirDemo
    )
    $painel = New-PainelTela
    $controles = @{ Painel = $painel; Campos = @{}; Demo = $null }
    $y = 4
    if ($PedirDona) {
        foreach ($campo in @(
                @{ Chave = 'Nome'; Rotulo = 'Nome da DONA (opcional; em branco fica "Dona")'; Oculto = $false },
                @{ Chave = 'Email'; Rotulo = 'E-mail da DONA (usado para entrar no sistema)'; Oculto = $false },
                @{ Chave = 'Senha'; Rotulo = 'Senha (6 a 20 caracteres)'; Oculto = $true },
                @{ Chave = 'Confirmacao'; Rotulo = 'Repita a senha'; Oculto = $true })) {
            $painel.Controls.Add((New-RotuloTela -Texto $campo.Rotulo -X 0 -Y $y))
            $caixa = New-CaixaTexto -X 0 -Y ($y + 24) -Oculto:$campo.Oculto
            $painel.Controls.Add($caixa)
            $controles.Campos[$campo.Chave] = $caixa
            $y += 60
        }
    }
    if ($PedirDemo) {
        $demo = New-Object System.Windows.Forms.CheckBox
        $demo.Text = 'Carregar dados de demonstração (clientes e pedidos fictícios)'
        $demo.Location = New-Object System.Drawing.Point(0, ($y + 6))
        $demo.Size = New-Object System.Drawing.Size(520, 26)
        $painel.Controls.Add($demo)
        $controles.Demo = $demo
    }
    return $controles
}

function New-PainelWhatsApp {
    # A blank key keeps what is configured; -ComAdiar adds the "configure later"
    # switch used by the wizard.
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()]$Linhas,
        [switch]$ComAdiar
    )
    $painel = New-PainelTela
    $painel.AutoScroll = $true
    $controles = @{ Painel = $painel; Campos = @{}; Adiar = $null }

    $painel.Controls.Add((New-RotuloTela -Texto 'Como o assistente conversa no WhatsApp' -X 0 -Y 4))
    $nuvem = New-Object System.Windows.Forms.RadioButton
    $nuvem.Text = 'API oficial do WhatsApp (Cloud API)'
    $nuvem.Location = New-Object System.Drawing.Point(0, 28)
    $nuvem.Size = New-Object System.Drawing.Size(520, 24)
    $celular = New-Object System.Windows.Forms.RadioButton
    $celular.Text = 'Pareando um celular (Baileys)'
    $celular.Location = New-Object System.Drawing.Point(0, 52)
    $celular.Size = New-Object System.Drawing.Size(520, 24)
    $celular.Checked = ((Get-ValorEnv -Linhas $Linhas -Chave 'CHANNEL') -eq 'baileys')
    $nuvem.Checked = -not $celular.Checked
    $painel.Controls.AddRange(@($nuvem, $celular))
    $controles.Celular = $celular

    $painel.Controls.Add((New-RotuloTela -Texto 'Telefone da beneficiária (formato +5511900000001)' -X 0 -Y 84))
    $controles.Telefone = New-CaixaTexto -X 0 -Y 108 -Texto "$(Get-ValorEnv -Linhas $Linhas -Chave 'BENEFICIARIA_TELEFONE')"
    $painel.Controls.Add($controles.Telefone)

    $y = 144
    if ($ComAdiar) {
        $adiar = New-Object System.Windows.Forms.CheckBox
        $adiar.Text = 'Configurar as chaves depois (o sistema web funciona sem elas)'
        $adiar.Location = New-Object System.Drawing.Point(0, $y)
        $adiar.Size = New-Object System.Drawing.Size(520, 26)
        $painel.Controls.Add($adiar)
        $controles.Adiar = $adiar
        $y += 32
    }

    $campos = @($CAMPOS_EXTERNOS | Where-Object { -not $_.Canal }) + @($CAMPOS_EXTERNOS | Where-Object { $_.Canal })
    foreach ($campo in $campos) {
        $atual = "$(Get-ValorEnv -Linhas $Linhas -Chave $campo.Chave)"
        $pendente = Test-SegredoPendente $atual
        $rotulo = New-RotuloTela -Texto $campo.Rotulo -X 0 -Y $y -Largura 340
        $situacao = New-RotuloTela -Texto $(if ($pendente) { 'pendente' } else { 'configurado: em branco mantém' }) -X 350 -Y $y -Largura 190
        $situacao.ForeColor = Get-CorDiscreta
        $texto = if (-not $campo.Oculto -and -not $pendente) { $atual } else { '' }
        $caixa = New-CaixaTexto -X 0 -Y ($y + 22) -Texto $texto -Oculto:$campo.Oculto
        $painel.Controls.AddRange(@($rotulo, $situacao, $caixa))
        $controles.Campos[$campo.Chave] = @{ Caixa = $caixa; Elementos = @($rotulo, $situacao, $caixa); Canal = $campo.Canal }
        $y += 56
    }

    $celular.Tag = $controles
    $celular.Add_CheckedChanged({ param($origem) Update-PainelWhatsApp -Controles $origem.Tag })
    if ($controles.Adiar) {
        $controles.Adiar.Tag = $controles
        $controles.Adiar.Add_CheckedChanged({ param($origem) Update-PainelWhatsApp -Controles $origem.Tag })
    }
    Update-PainelWhatsApp -Controles $controles
    return $controles
}

function Update-PainelWhatsApp {
    # Shows only the keys of the chosen channel and locks them while deferred.
    param([Parameter(Mandatory = $true)][hashtable]$Controles)
    $canal = if ($Controles.Celular.Checked) { 'baileys' } else { 'cloud_api' }
    $adiado = $Controles.Adiar -and $Controles.Adiar.Checked
    foreach ($campo in $Controles.Campos.Values) {
        $visivel = (-not $campo.Canal -or $campo.Canal -eq $canal)
        foreach ($elemento in $campo.Elementos) { $elemento.Visible = $visivel }
        $campo.Caixa.Enabled = -not $adiado
    }
}

function Get-ValoresPainelWhatsApp {
    param([Parameter(Mandatory = $true)][hashtable]$Controles)
    $canal = if ($Controles.Celular.Checked) { 'baileys' } else { 'cloud_api' }
    $valores = @{ CHANNEL = $canal; BENEFICIARIA_TELEFONE = $Controles.Telefone.Text.Trim() }
    if ($Controles.Adiar -and $Controles.Adiar.Checked) { return $valores }
    foreach ($chave in $Controles.Campos.Keys) {
        $campo = $Controles.Campos[$chave]
        if (-not $campo.Canal -or $campo.Canal -eq $canal) {
            $valores[$chave] = $campo.Caixa.Text.Trim()
        }
    }
    return $valores
}

function Show-ErrosNosCampos {
    # Marks each invalid field and returns the first message, or '' when valid.
    param(
        [Parameter(Mandatory = $true)]$Provedor,
        [Parameter(Mandatory = $true)][hashtable]$Erros,
        [Parameter(Mandatory = $true)][hashtable]$Caixas
    )
    $Provedor.Clear()
    foreach ($chave in $Erros.Keys) {
        if ($Caixas.ContainsKey($chave)) { $Provedor.SetError($Caixas[$chave], $Erros[$chave]) }
    }
    if ($Erros.Count -eq 0) { return '' }
    return "$(@($Erros.Values)[0])"
}

function Get-CaixasWhatsApp {
    param([Parameter(Mandatory = $true)][hashtable]$Controles)
    $caixas = @{ BENEFICIARIA_TELEFONE = $Controles.Telefone }
    foreach ($chave in $Controles.Campos.Keys) { $caixas[$chave] = $Controles.Campos[$chave].Caixa }
    return $caixas
}

function Get-TextoResumo {
    param(
        [hashtable]$Dona,
        $Demo,
        [Parameter(Mandatory = $true)][hashtable]$Valores,
        [Parameter(Mandatory = $true)][bool]$Adiado
    )
    $linhas = @()
    if ($Dona) {
        $nome = if ($Dona.Nome) { $Dona.Nome } else { 'Dona' }
        $linhas += "DONA: $nome ($($Dona.Email)), senha definida"
    }
    if ($null -ne $Demo) { $linhas += "Dados de demonstração: $(if ($Demo) { 'sim' } else { 'não' })" }
    $canal = if ($Valores.CHANNEL -eq 'baileys') { 'celular pareado (Baileys)' } else { 'API oficial (Cloud API)' }
    $linhas += "WhatsApp: $canal"
    $linhas += "Telefone da beneficiária: $($Valores.BENEFICIARIA_TELEFONE)"
    if ($Adiado) {
        $linhas += 'Chaves externas: configurar depois, pelo botão Configurações do WhatsApp'
    }
    else {
        foreach ($campo in $CAMPOS_EXTERNOS) {
            if ($Valores.ContainsKey($campo.Chave)) {
                $situacao = if ($Valores[$campo.Chave]) { 'informado' } else { 'sem mudança' }
                $linhas += "$($campo.Rotulo): $situacao"
            }
        }
    }
    $linhas += ''
    $linhas += 'Ao concluir, a configuração é gravada e o sistema é ligado.'
    return ($linhas -join "`r`n")
}

function New-MolduraFormulario {
    # Title, hint, content area, error line and the button row shared by the
    # wizard and the settings screen.
    param([Parameter(Mandatory = $true)][string]$Titulo)
    $painel = New-PainelTela
    $rotuloTitulo = New-RotuloTela -Texto $Titulo -X 20 -Y 0 -Largura 520 -Altura 30
    $rotuloTitulo.Font = New-Object System.Drawing.Font('Segoe UI', 13, [System.Drawing.FontStyle]::Bold)
    $dica = New-RotuloTela -X 20 -Y 32 -Largura 520 -Altura 26
    $dica.ForeColor = Get-CorDiscreta
    $area = New-Object System.Windows.Forms.Panel
    $area.Location = New-Object System.Drawing.Point(20, 60)
    $area.Size = New-Object System.Drawing.Size(520, 364)
    $erro = New-RotuloTela -X 20 -Y 426 -Largura 520 -Altura 32
    $erro.ForeColor = Get-CorErro
    $provedor = New-Object System.Windows.Forms.ErrorProvider
    $provedor.BlinkStyle = 'NeverBlink'
    $painel.Controls.AddRange(@($rotuloTitulo, $dica, $area, $erro))
    $painel.Add_Disposed({ param($origem) $origem.Tag.Provedor.Dispose() })
    return @{ Painel = $painel; Titulo = $rotuloTitulo; Dica = $dica; Area = $area; Erro = $erro; Provedor = $provedor }
}

function New-BotaoTela {
    param(
        [Parameter(Mandatory = $true)][string]$Texto,
        [Parameter(Mandatory = $true)][int]$X,
        [Parameter(Mandatory = $true)][hashtable]$Tela,
        [Parameter(Mandatory = $true)][scriptblock]$AoClicar
    )
    $botao = New-Botao -Texto $Texto -X $X -Y 464
    $botao.Tag = $Tela
    $botao.Add_Click($AoClicar)
    $Tela.Painel.Controls.Add($botao)
    return $botao
}

function New-TelaAssistente {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()]$Linhas,
        [Parameter(Mandatory = $true)][bool]$PedirDona,
        [Parameter(Mandatory = $true)][bool]$PedirDemo
    )
    $tela = New-MolduraFormulario -Titulo 'Configuração'
    $tela.Paginas = New-Object System.Collections.Generic.List[hashtable]
    $tela.Dona = $null
    if ($PedirDona -or $PedirDemo) {
        $tela.Dona = New-PainelDona -PedirDona $PedirDona -PedirDemo $PedirDemo
        $tela.Paginas.Add(@{ Titulo = 'Conta da DONA'; Painel = $tela.Dona.Painel })
    }
    $tela.WhatsApp = New-PainelWhatsApp -Linhas $Linhas -ComAdiar
    $tela.Paginas.Add(@{ Titulo = 'WhatsApp'; Painel = $tela.WhatsApp.Painel })
    $tela.Resumo = New-Object System.Windows.Forms.TextBox
    $tela.Resumo.Multiline = $true
    $tela.Resumo.ReadOnly = $true
    $tela.Resumo.Dock = 'Fill'
    $tela.Paginas.Add(@{ Titulo = 'Resumo'; Painel = $tela.Resumo })
    $tela.Indice = 0
    $tela.Resultado = $null
    $tela.Painel.Tag = $tela

    $tela.Voltar = New-BotaoTela -Texto 'Voltar' -X 222 -Tela $tela -AoClicar { param($origem) Step-Assistente -Tela $origem.Tag -Direcao -1 }
    $tela.Avancar = New-BotaoTela -Texto 'Avançar' -X 330 -Tela $tela -AoClicar { param($origem) Step-Assistente -Tela $origem.Tag -Direcao 1 }
    $null = New-BotaoTela -Texto 'Cancelar' -X 440 -Tela $tela -AoClicar { param($origem) Show-TelaMenu -Janela $origem.FindForm() }
    Show-PaginaAssistente -Tela $tela
    return $tela.Painel
}

function Get-DonaDoAssistente {
    param([Parameter(Mandatory = $true)][hashtable]$Tela)
    if (-not $Tela.Dona -or $Tela.Dona.Campos.Count -eq 0) { return $null }
    $campos = $Tela.Dona.Campos
    return @{
        Nome        = $campos.Nome.Text.Trim()
        Email       = $campos.Email.Text.Trim()
        Senha       = $campos.Senha.Text
        Confirmacao = $campos.Confirmacao.Text
    }
}

function Show-PaginaAssistente {
    param([Parameter(Mandatory = $true)][hashtable]$Tela)
    $pagina = $Tela.Paginas[$Tela.Indice]
    $Tela.Area.Controls.Clear()
    $Tela.Area.Controls.Add($pagina.Painel)
    $Tela.Titulo.Text = $pagina.Titulo
    $Tela.Dica.Text = "Passo $($Tela.Indice + 1) de $($Tela.Paginas.Count)"
    $Tela.Voltar.Enabled = $Tela.Indice -gt 0
    $ultima = ($Tela.Indice -eq $Tela.Paginas.Count - 1)
    $Tela.Avancar.Text = if ($ultima) { 'Concluir' } else { 'Avançar' }
    if ($ultima) {
        $demo = if ($Tela.Dona -and $Tela.Dona.Demo) { $Tela.Dona.Demo.Checked } else { $null }
        $Tela.Resumo.Text = Get-TextoResumo -Dona (Get-DonaDoAssistente -Tela $Tela) -Demo $demo `
            -Valores (Get-ValoresPainelWhatsApp -Controles $Tela.WhatsApp) -Adiado ([bool]$Tela.WhatsApp.Adiar.Checked)
    }
    $Tela.Erro.Text = ''
}

function Test-PaginaAssistente {
    # Returns the first error of the current page, or '' when it is valid.
    param([Parameter(Mandatory = $true)][hashtable]$Tela)
    $painel = $Tela.Paginas[$Tela.Indice].Painel
    if ($Tela.Dona -and $painel -eq $Tela.Dona.Painel -and $Tela.Dona.Campos.Count -gt 0) {
        $dona = Get-DonaDoAssistente -Tela $Tela
        $erros = Get-ErrosDaDona -Nome $dona.Nome -Email $dona.Email -Senha $dona.Senha -Confirmacao $dona.Confirmacao
        return (Show-ErrosNosCampos -Provedor $Tela.Provedor -Erros $erros -Caixas $Tela.Dona.Campos)
    }
    if ($painel -eq $Tela.WhatsApp.Painel) {
        $erros = Get-ErrosDoAssistente -Valores (Get-ValoresPainelWhatsApp -Controles $Tela.WhatsApp)
        return (Show-ErrosNosCampos -Provedor $Tela.Provedor -Erros $erros -Caixas (Get-CaixasWhatsApp -Controles $Tela.WhatsApp))
    }
    return ''
}

function Step-Assistente {
    param(
        [Parameter(Mandatory = $true)][hashtable]$Tela,
        [Parameter(Mandatory = $true)][int]$Direcao
    )
    if ($Direcao -lt 0) {
        $Tela.Provedor.Clear()
        if ($Tela.Indice -gt 0) { $Tela.Indice-- }
        Show-PaginaAssistente -Tela $Tela
        return
    }
    $mensagem = Test-PaginaAssistente -Tela $Tela
    if ($mensagem) {
        $Tela.Erro.Text = $mensagem
        return
    }
    if ($Tela.Indice -lt $Tela.Paginas.Count - 1) {
        $Tela.Indice++
        Show-PaginaAssistente -Tela $Tela
        return
    }
    $dona = Get-DonaDoAssistente -Tela $Tela
    $Tela.Resultado = @{
        Dona    = $(if ($dona) { @{ Nome = $dona.Nome; Email = $dona.Email; Senha = $dona.Senha } } else { $null })
        Demo    = [bool]($Tela.Dona -and $Tela.Dona.Demo -and $Tela.Dona.Demo.Checked)
        Valores = Get-ValoresPainelWhatsApp -Controles $Tela.WhatsApp
    }
    $janela = $Tela.Painel.FindForm()
    if ($janela) { Submit-PedidoDaJanela -Janela $janela -Acao 'configurar' -Dados $Tela.Resultado -Carregando 'Gravando a configuração...' }
}

function New-TelaConfiguracoes {
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()]$Linhas)
    $tela = New-MolduraFormulario -Titulo 'Configurações do WhatsApp'
    $tela.Dica.Text = 'Ao salvar, só os serviços afetados são reiniciados. A conta da DONA não muda aqui.'
    $tela.WhatsApp = New-PainelWhatsApp -Linhas $Linhas
    $tela.Area.Controls.Add($tela.WhatsApp.Painel)
    $tela.Resultado = $null
    $tela.Painel.Tag = $tela
    $null = New-BotaoTela -Texto 'Salvar' -X 330 -Tela $tela -AoClicar { param($origem) Submit-Configuracoes -Tela $origem.Tag }
    $null = New-BotaoTela -Texto 'Cancelar' -X 440 -Tela $tela -AoClicar { param($origem) Show-TelaMenu -Janela $origem.FindForm() }
    return $tela.Painel
}

function Submit-Configuracoes {
    param([Parameter(Mandatory = $true)][hashtable]$Tela)
    $valores = Get-ValoresPainelWhatsApp -Controles $Tela.WhatsApp
    $mensagem = Show-ErrosNosCampos -Provedor $Tela.Provedor -Erros (Get-ErrosDoAssistente -Valores $valores) -Caixas (Get-CaixasWhatsApp -Controles $Tela.WhatsApp)
    if ($mensagem) {
        $Tela.Erro.Text = $mensagem
        return
    }
    $Tela.Resultado = $valores
    $janela = $Tela.Painel.FindForm()
    if ($janela) { Submit-PedidoDaJanela -Janela $janela -Acao 'configuracoes-salvar' -Dados $valores -Carregando 'Salvando as configurações...' }
}
