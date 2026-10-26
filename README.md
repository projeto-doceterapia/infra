# infra

Ambiente Docker Compose do sistema Doceterapia. O único repositório necessário
para executar a pilha: baixa imagens prontas e fixadas do GHCR e nunca faz build
por padrão.

## Requisitos

- Docker com Compose v2.
- Um `.env` preenchido (veja abaixo). Nada mais no host.

## Configuração

```sh
cp .env.example .env   # depois preencha os segredos
```

O `.env` é ignorado pelo git. Já vem com as tags das imagens definidas nas
versões publicadas atualmente, então a pilha padrão executa como está; só os
segredos `replace-me` precisam ser preenchidos. Toda variável é obrigatória a
menos que seu comentário diga que tem um padrão; uma ausente interrompe o
`docker compose` com o nome da variável.

## Modos

### Executar a pilha publicada (padrão)

```sh
docker compose up
```

Baixa as imagens nas tags definidas no `.env` e inicia `banco-de-dados`,
`back-end`, `front-end`, `redis` e `orquestrador`. A aplicação web é publicada em
`http://localhost:3000` (substitua com `FRONTEND_HOST_PORT`). O banco de dados, o
back-end e o redis ficam na rede interna do Docker `interna` (sem alcance ao host
ou à internet); o orquestrador também está na `interna`, mas entra na ponte de
saída `saida` para suas chamadas externas (LLM, Meta Cloud API). Apenas o
front-end está na rede `publica`, voltada ao host, e publica uma porta. Sem o
perfil `baileys` nenhum adaptador do WhatsApp executa; com `CHANNEL=baileys` (o
padrão no `.env.example`) use o perfil abaixo. O canal `cloud_api` precisa de uma
rota HTTPS pública para o `/webhook` do orquestrador, que esta pilha não publica;
a única rota fornecida é o túnel de desenvolvimento.

### WhatsApp via o adaptador Baileys

```sh
docker compose --profile baileys up
```

Adiciona `adaptador-baileys` à pilha. Ele mantém a sessão do WhatsApp no volume
nomeado `adaptador-baileys-session` (sobrevive ao `docker compose down`),
processa apenas mensagens do grupo em `GRUPO_JID` e encaminha os eventos de
entrada ao webhook do orquestrador (`WEBHOOK_URL`) pela rede interna.

Pareie o dispositivo na primeira vez lendo o QR nos logs do adaptador:

```sh
docker compose --profile baileys logs -f adaptador-baileys
```

Escaneie o QR exibido com o WhatsApp (Aparelhos conectados) no telefone do
assistente. A sessão então persiste no volume, então as inicializações
posteriores reconectam sem um novo QR.

Encontre o id do grupo para `GRUPO_JID` após o pareamento: defina
`DISCOVER_GROUPS=true` no `.env`, reinicie o adaptador, leia os ids e nomes
registrados nos logs e depois desative-o novamente:

```sh
docker compose --profile baileys up -d adaptador-baileys
docker compose --profile baileys logs adaptador-baileys | grep 'group discovery'
```

Copie o `jid` do grupo dedicado para `GRUPO_JID`, defina `DISCOVER_GROUPS` de
volta como `false` e execute `docker compose --profile baileys up -d` novamente.
O log lista nomes de grupos, então mantenha-o privado.

### Desenvolver um serviço localmente

Faça o build de um ou mais serviços a partir dos checkouts vizinhos
(`../back-end`, `../front-end`, `../banco-de-dados`,
`../assistente-whatsapp/orquestrador`,
`../assistente-whatsapp/adaptador-baileys`) em vez de baixá-los; os serviços que
você não nomear mantêm suas imagens publicadas:

```sh
docker compose -f docker-compose.yml -f compose.local.yml up --build back-end
```

O override também publica a porta do back-end para o Swagger UI
(`http://localhost:8080/swagger-ui/index.html`, substitua com `BACK_END_HOST_PORT`).
Ela está presa em `127.0.0.1` por padrão; defina `BACK_END_HOST_BIND=0.0.0.0`
para alcançá-la a partir de outros hosts (veja Expor as portas locais).
Para tornar essa porta publicada alcançável, ele também anexa o back-end à rede
`publica`; na pilha padrão o back-end fica somente na `interna`.

## Redes

- `interna`: interna do Docker (`internal: true`). Contém `banco-de-dados`,
  `back-end`, `redis` e os serviços do assistente (`orquestrador`,
  `adaptador-baileys`). Os serviços aqui não têm alcance ao host ou à internet
  e não podem publicar portas, então o banco de dados nunca é exposto.
- `publica`: ponte normal para o tráfego voltado ao host. Apenas o front-end
  está nela na pilha padrão (e o back-end quando o override local publica
  sua porta).
- `saida`: ponte somente de saída. Carrega o tráfego externo de internet de
  `orquestrador` e `adaptador-baileys` (e `ngrok` no override local);
  estes também ficam na `interna` para o tráfego dentro da pilha. Não publica porta.
- `front-end` está anexado a ambas: publica sua porta na `publica` e
  faz proxy de `/api` para o back-end pela `interna`.

### Túnel HTTPS (testes de webhook da Cloud API)

```sh
docker compose -f docker-compose.yml -f compose.local.yml --profile tunnel up
```

Inicia um túnel `ngrok` para o webhook do orquestrador (`NGROK_UPSTREAM`, padrão
`orquestrador:8000`); a URL HTTPS pública é exibida nos logs do `ngrok` e
alcança o orquestrador pela rede interna. Requer `NGROK_AUTHTOKEN`.

No modo `cloud_api`, registre o webhook na Meta Cloud API usando a rota de
entrada do orquestrador, `/webhook`:

```
https://<ngrok-host>/webhook
```

Use `CLOUD_API_VERIFY_TOKEN` como o verify token que a Meta envia no handshake GET.

### Expor as portas locais

As duas portas que o override local publica estão presas em `127.0.0.1` por
padrão, então apenas a máquina que executa a pilha pode alcançá-las:

| Variável | Porta | O que expõe |
|---|---|---|
| `BACK_END_HOST_BIND` | `BACK_END_HOST_PORT` (8080) | API do back-end e Swagger UI; as rotas de negócio não têm autenticação |
| `NGROK_WEB_BIND` | `NGROK_WEB_PORT` (4040) | UI de inspeção do ngrok; mostra corpos de requisição e assinaturas, sem autenticação |

Em um servidor provisionado, defina a variável como `0.0.0.0` no `.env` para
alcançar o painel de fora, e restrinja a porta com um firewall ou security group
(permita apenas o seu próprio endereço). A porta do front-end não é afetada: é a
aplicação web e é publicada em todas as interfaces.
## Parar

```sh
docker compose down        # mantém os volumes nomeados (dados, Redis)
docker compose down -v      # também remove os volumes
```

## Variáveis de ambiente

O `.env.example` lista cada variável agrupada por serviço, com valores de
exemplo. Grupos:

- Tags das imagens: `BANCO_DE_DADOS_TAG`, `BACK_END_TAG`, `FRONT_END_TAG`, `REDIS_TAG`,
  `ORQUESTRADOR_TAG`, `ADAPTADOR_BAILEYS_TAG` (fixadas nas versões publicadas
  atualmente, nunca `latest`; atualize para um build publicado mais novo definindo
  o novo `sha-<short>` ou semver).
- banco-de-dados: `MYSQL_ROOT_PASSWORD`, `MYSQL_DATABASE`, `MYSQL_USER`, `MYSQL_PASSWORD`.
- back-end: `SPRING_PROFILES_ACTIVE`, `DB_URL`, `DB_USERNAME`, `DB_PASSWORD`, `JWT_SECRET`.
- front-end: `API_UPSTREAM`, `FRONTEND_HOST_PORT`.
- redis: `REDIS_PASSWORD`.
- orquestrador: `CHANNEL`, `BENEFICIARIA_TELEFONE`, `CORE_BASE_URL`,
  `ORQUESTRADOR_REDIS_URL`, `CONV_TTL_MIN`, `MAX_AJUSTES`, `RETRY_MAX_TENTATIVAS`,
  `RETRY_BASE_S`, `RETRY_CAP_S`, `TZ`, `ADAPTER_URL`, `ADAPTER_SECRET`,
  `WEBHOOK_SECRET`, `CLOUD_API_PHONE_ID`, `CLOUD_API_TOKEN`, `CLOUD_API_APP_SECRET`,
  `CLOUD_API_VERIFY_TOKEN`, `CLOUD_API_GRAPH_VERSION`, `LLM_PROVIDER`,
  `GEMINI_API_KEY`, `GEMINI_MODEL`.
- adaptador-baileys (perfil `baileys`): `GRUPO_JID`, `WEBHOOK_URL`,
  `BAILEYS_SESSION_DIR`, `BAILEYS_LOG_LEVEL`, `DISCOVER_GROUPS` (além de
  `ADAPTER_SECRET` e `WEBHOOK_SECRET`, compartilhadas com o orquestrador).
- Apenas no override local: `BACK_END_HOST_PORT`, `BACK_END_HOST_BIND`, `NGROK_AUTHTOKEN`,
  `NGROK_UPSTREAM`, `NGROK_WEB_PORT`, `NGROK_WEB_BIND`, `NGROK_TAG`.
