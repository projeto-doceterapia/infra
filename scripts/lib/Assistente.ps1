# Setup wizard and settings window. They only collect and validate answers;
# init and the restart plan apply them, so the console keeps the same rules.

function Get-CorErro { return [System.Drawing.Color]::FromArgb(180, 30, 30) }

function Get-CorDiscreta { return [System.Drawing.Color]::FromArgb(110, 110, 110) }

function New-Rotulo {
    param(
        [Parameter(Mandatory = $true)][string]$Texto,
        [Parameter(Mandatory = $true)][int]$X,
        [Parameter(Mandatory = $true)][int]$Y,
        [int]$Largura = 520,
        [int]$Altura = 22
    )
    $rotulo = New-Object System.Windows.Forms.Label
    $rotulo.Text = $Texto
    $rotulo.Location = New-Object System.Drawing.Point($X, $Y)
    $rotulo.Size = New-Object System.Drawing.Size($Largura, $Altura)
    return $rotulo
}

function New-CaixaTexto {
    param(
        [Parameter(Mandatory = $true)][int]$X,
        [Parameter(Mandatory = $true)][int]$Y,
        [string]$Texto = '',
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
    $painel = New-Object System.Windows.Forms.Panel
    $painel.Dock = 'Fill'
    $controles = @{ Painel = $painel; Campos = @{} }
    $y = 4
    if ($PedirDona) {
        foreach ($campo in @(
                @{ Chave = 'Nome'; Rotulo = 'Nome da DONA (opcional; em branco fica "Dona")'; Oculto = $false },
                @{ Chave = 'Email'; Rotulo = 'E-mail da DONA (usado para entrar no sistema)'; Oculto = $false },
                @{ Chave = 'Senha'; Rotulo = 'Senha (6 a 20 caracteres)'; Oculto = $true },
                @{ Chave = 'Confirmacao'; Rotulo = 'Repita a senha'; Oculto = $true })) {
            $painel.Controls.Add((New-Rotulo -Texto $campo.Rotulo -X 0 -Y $y))
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
    $painel = New-Object System.Windows.Forms.Panel
    $painel.Dock = 'Fill'
    $painel.AutoScroll = $true
    $controles = @{ Painel = $painel; Campos = @{} }

    $canalAtual = Get-ValorEnv -Linhas $Linhas -Chave 'CHANNEL'
    $painel.Controls.Add((New-Rotulo -Texto 'Como o assistente conversa no WhatsApp' -X 0 -Y 4))
    $nuvem = New-Object System.Windows.Forms.RadioButton
    $nuvem.Text = 'API oficial do WhatsApp (Cloud API)'
    $nuvem.Location = New-Object System.Drawing.Point(0, 28)
    $nuvem.Size = New-Object System.Drawing.Size(520, 24)
    $celular = New-Object System.Windows.Forms.RadioButton
    $celular.Text = 'Pareando um celular (Baileys)'
    $celular.Location = New-Object System.Drawing.Point(0, 52)
    $celular.Size = New-Object System.Drawing.Size(520, 24)
    $celular.Checked = ($canalAtual -eq 'baileys')
    $nuvem.Checked = -not $celular.Checked
    $painel.Controls.AddRange(@($nuvem, $celular))
    $controles.Celular = $celular

    $painel.Controls.Add((New-Rotulo -Texto 'Telefone da beneficiária (formato +5511900000001)' -X 0 -Y 84))
    $controles.Telefone = New-CaixaTexto -X 0 -Y 108 -Texto (Get-ValorEnv -Linhas $Linhas -Chave 'BENEFICIARIA_TELEFONE')
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
        $atual = Get-ValorEnv -Linhas $Linhas -Chave $campo.Chave
        $pendente = Test-SegredoPendente $atual
        $rotulo = New-Rotulo -Texto $campo.Rotulo -X 0 -Y $y -Largura 340
        $situacao = New-Rotulo -Texto $(if ($pendente) { 'pendente' } else { 'configurado: em branco mantém' }) -X 350 -Y $y -Largura 200
        $situacao.ForeColor = (Get-CorDiscreta)
        $texto = if (-not $campo.Oculto -and -not $pendente) { $atual } else { '' }
        $caixa = New-CaixaTexto -X 0 -Y ($y + 22) -Texto $texto -Oculto:$campo.Oculto
        $painel.Controls.AddRange(@($rotulo, $situacao, $caixa))
        $controles.Campos[$campo.Chave] = @{ Caixa = $caixa; Elementos = @($rotulo, $situacao, $caixa); Canal = $campo.Canal }
        $y += 56
    }

    $atualizar = {
        $canal = if ($controles.Celular.Checked) { 'baileys' } else { 'cloud_api' }
        $adiado = $controles.Adiar -and $controles.Adiar.Checked
        foreach ($campo in $controles.Campos.Values) {
            $visivel = (-not $campo.Canal -or $campo.Canal -eq $canal)
            foreach ($elemento in $campo.Elementos) { $elemento.Visible = $visivel }
            $campo.Caixa.Enabled = -not $adiado
        }
    }.GetNewClosure()
    $celular.Add_CheckedChanged($atualizar)
    if ($controles.Adiar) { $controles.Adiar.Add_CheckedChanged($atualizar) }
    & $atualizar
    return $controles
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
        $linhas += 'Chaves externas: configurar depois, pelo botão Configurações'
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

function Show-Assistente {
    # Returns @{ Dona; Demo; Valores } for init, or $null when cancelled.
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()]$Linhas,
        [Parameter(Mandatory = $true)][bool]$PedirDona,
        [Parameter(Mandatory = $true)][bool]$PedirDemo
    )
    $janela = New-JanelaBase -Largura 600 -Altura 600
    $janela.Text = 'Doceterapia - Configuração'
    $titulo = New-Rotulo -Texto '' -X 20 -Y 14 -Largura 560 -Altura 30
    $titulo.Font = New-Object System.Drawing.Font('Segoe UI', 13, [System.Drawing.FontStyle]::Bold)
    $passo = New-Rotulo -Texto '' -X 20 -Y 46 -Largura 560
    $passo.ForeColor = (Get-CorDiscreta)
    $area = New-Object System.Windows.Forms.Panel
    $area.Location = New-Object System.Drawing.Point(20, 78)
    $area.Size = New-Object System.Drawing.Size(560, 420)
    $erro = New-Rotulo -Texto '' -X 20 -Y 504 -Largura 560 -Altura 36
    $erro.ForeColor = (Get-CorErro)
    $voltar = New-Botao -Texto 'Voltar' -X 262 -Y 552
    $avancar = New-Botao -Texto 'Avançar' -X 368 -Y 552
    $cancelar = New-Botao -Texto 'Cancelar' -X 480 -Y 552 -Resultado Cancel
    $janela.Controls.AddRange(@($titulo, $passo, $area, $erro, $voltar, $avancar, $cancelar))
    $janela.AcceptButton = $avancar
    $janela.CancelButton = $cancelar
    $provedor = New-Object System.Windows.Forms.ErrorProvider
    $provedor.BlinkStyle = 'NeverBlink'

    $paginas = New-Object System.Collections.Generic.List[hashtable]
    $dona = $null
    if ($PedirDona -or $PedirDemo) {
        $dona = New-PainelDona -PedirDona $PedirDona -PedirDemo $PedirDemo
        $paginas.Add(@{ Titulo = 'Conta da DONA'; Controles = $dona; Painel = $dona.Painel })
    }
    $whatsapp = New-PainelWhatsApp -Linhas $Linhas -ComAdiar
    $paginas.Add(@{ Titulo = 'WhatsApp'; Controles = $whatsapp; Painel = $whatsapp.Painel })
    $resumoCaixa = New-Object System.Windows.Forms.TextBox
    $resumoCaixa.Multiline = $true
    $resumoCaixa.ReadOnly = $true
    $resumoCaixa.Dock = 'Fill'
    $paginas.Add(@{ Titulo = 'Resumo'; Painel = $resumoCaixa })

    $estado = @{ Indice = 0; Resultado = $null }

    $lerDona = {
        if (-not $dona -or -not $dona.Campos.Count) { return $null }
        return @{
            Nome        = $dona.Campos.Nome.Text.Trim()
            Email       = $dona.Campos.Email.Text.Trim()
            Senha       = $dona.Campos.Senha.Text
            Confirmacao = $dona.Campos.Confirmacao.Text
        }
    }
    $mostrar = {
        $pagina = $paginas[$estado.Indice]
        $area.Controls.Clear()
        $area.Controls.Add($pagina.Painel)
        $titulo.Text = $pagina.Titulo
        $passo.Text = "Passo $($estado.Indice + 1) de $($paginas.Count)"
        $voltar.Enabled = $estado.Indice -gt 0
        $ultima = ($estado.Indice -eq $paginas.Count - 1)
        $avancar.Text = if ($ultima) { 'Concluir' } else { 'Avançar' }
        if ($ultima) {
            $adiado = [bool]$whatsapp.Adiar.Checked
            $demo = if ($dona -and $dona.Demo) { $dona.Demo.Checked } else { $null }
            $resumoCaixa.Text = Get-TextoResumo -Dona (& $lerDona) -Demo $demo -Valores (Get-ValoresPainelWhatsApp -Controles $whatsapp) -Adiado $adiado
        }
        $erro.Text = ''
    }
    $validar = {
        $pagina = $paginas[$estado.Indice]
        if ($pagina.Controles -eq $dona -and $dona.Campos.Count) {
            $d = & $lerDona
            $erros = Get-ErrosDaDona -Nome $d.Nome -Email $d.Email -Senha $d.Senha -Confirmacao $d.Confirmacao
            return (Show-ErrosNosCampos -Provedor $provedor -Erros $erros -Caixas $dona.Campos)
        }
        if ($pagina.Controles -eq $whatsapp) {
            $erros = Get-ErrosDoAssistente -Valores (Get-ValoresPainelWhatsApp -Controles $whatsapp)
            return (Show-ErrosNosCampos -Provedor $provedor -Erros $erros -Caixas (Get-CaixasWhatsApp -Controles $whatsapp))
        }
        return ''
    }

    $voltar.Add_Click({
            $provedor.Clear()
            $estado.Indice--
            & $mostrar
        })
    $avancar.Add_Click({
            $mensagem = & $validar
            if ($mensagem) {
                $erro.Text = $mensagem
                return
            }
            if ($estado.Indice -lt $paginas.Count - 1) {
                $estado.Indice++
                & $mostrar
                return
            }
            $d = & $lerDona
            $estado.Resultado = @{
                Dona    = $(if ($d) { @{ Nome = $d.Nome; Email = $d.Email; Senha = $d.Senha } } else { $null })
                Demo    = [bool]($dona -and $dona.Demo -and $dona.Demo.Checked)
                Valores = Get-ValoresPainelWhatsApp -Controles $whatsapp
            }
            $janela.DialogResult = [System.Windows.Forms.DialogResult]::OK
            $janela.Close()
        })

    & $mostrar
    try {
        $null = $janela.ShowDialog()
        return $estado.Resultado
    }
    finally {
        $provedor.Dispose()
        $janela.Dispose()
    }
}

function Show-Configuracoes {
    # Returns the values to write, keyed by env key, or $null when cancelled.
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()]$Linhas)
    $janela = New-JanelaBase -Largura 600 -Altura 600
    $janela.Text = 'Doceterapia - Configurações'
    $titulo = New-Rotulo -Texto 'Configurações do WhatsApp' -X 20 -Y 14 -Largura 560 -Altura 30
    $titulo.Font = New-Object System.Drawing.Font('Segoe UI', 13, [System.Drawing.FontStyle]::Bold)
    $nota = New-Rotulo -Texto 'Ao salvar, só os serviços afetados são reiniciados. A conta da DONA não muda aqui.' -X 20 -Y 46 -Largura 560 -Altura 28
    $nota.ForeColor = (Get-CorDiscreta)
    $area = New-Object System.Windows.Forms.Panel
    $area.Location = New-Object System.Drawing.Point(20, 78)
    $area.Size = New-Object System.Drawing.Size(560, 420)
    $whatsapp = New-PainelWhatsApp -Linhas $Linhas
    $area.Controls.Add($whatsapp.Painel)
    $erro = New-Rotulo -Texto '' -X 20 -Y 504 -Largura 560 -Altura 36
    $erro.ForeColor = (Get-CorErro)
    $salvar = New-Botao -Texto 'Salvar' -X 368 -Y 552
    $cancelar = New-Botao -Texto 'Cancelar' -X 480 -Y 552 -Resultado Cancel
    $janela.Controls.AddRange(@($titulo, $nota, $area, $erro, $salvar, $cancelar))
    $janela.AcceptButton = $salvar
    $janela.CancelButton = $cancelar
    $provedor = New-Object System.Windows.Forms.ErrorProvider
    $provedor.BlinkStyle = 'NeverBlink'
    $estado = @{ Resultado = $null }

    $salvar.Add_Click({
            $valores = Get-ValoresPainelWhatsApp -Controles $whatsapp
            $mensagem = Show-ErrosNosCampos -Provedor $provedor -Erros (Get-ErrosDoAssistente -Valores $valores) -Caixas (Get-CaixasWhatsApp -Controles $whatsapp)
            if ($mensagem) {
                $erro.Text = $mensagem
                return
            }
            $estado.Resultado = $valores
            $janela.DialogResult = [System.Windows.Forms.DialogResult]::OK
            $janela.Close()
        })

    try {
        $null = $janela.ShowDialog()
        return $estado.Resultado
    }
    finally {
        $provedor.Dispose()
        $janela.Dispose()
    }
}
