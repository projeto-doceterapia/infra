# infra

Ambiente Docker Compose do sistema Doceterapia. O único repositório necessário
para executar a pilha: baixa imagens prontas e fixadas do GHCR e nunca faz build
por padrão.

## Ambientes suportados

- Windows 10 ou 11 com Docker Desktop e WSL2, com pelo menos 8 GB de RAM. Os limites
  de memória somam cerca de 2,1 GB, ou 2,4 GB com o adaptador Baileys.
- Linux com Docker Engine, como alternativa.
- Demonstração só com dados fictícios (`DEMO_DATA=true`).

## Requisitos

- Docker Engine 25 ou mais novo e Compose 2.20 ou mais novo. Versões antigas ignoram
  ou recusam o `start_interval` dos health checks.
- Um `.env` preenchido (veja abaixo). Nada mais no host.

## Comandos

| Objetivo | Comando |
|---|---|
| Subir a pilha | `docker compose up -d` |
| Subir com o túnel (canal `cloud_api`) | `docker compose --profile tunnel up -d` |
| Subir com o adaptador (canal `baileys`) | `docker compose --profile baileys up -d` |
| Ver o estado | `docker compose ps` |
| Ver o uso de memória | `docker stats --no-stream` |
| Parar sem apagar dados | `docker compose down` |
| Recriar só o banco | veja [Recriar o banco](#recriar-o-banco) |

## Configuração

```sh
cp .env.example .env   # depois preencha os segredos
```

O `.env` é ignorado pelo git. Já vem com as tags das imagens definidas nas
versões publicadas atualmente, então a pilha padrão executa como está; só os
segredos `replace-me` precisam ser preenchidos. Toda variável é obrigatória a
menos que seu comentário diga que tem um padrão; uma ausente interrompe o
`docker compose` com o nome da variável.

Exceções a essa regra:

- Opcionais com padrão seguro: `DISCOVER_GROUPS`, `ACCEPT_OWN_MESSAGES`,
  `COOKIE_SECURE`, `SWAGGER_ENABLED` e `DEMO_DATA` assumem `false` quando ausentes.
- Credenciais do primeiro usuário: `ADMIN_EMAIL` e `ADMIN_SENHA` podem ficar
  vazias ou ausentes, porque só são lidas enquanto a tabela de usuários está vazia.
- `CORS_ALLOWED_ORIGINS`: a linha precisa existir, mas o valor pode ser vazio,
  já que a aplicação web acessa a API pela mesma origem, em `/api`.

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
perfil `baileys` nenhum adaptador do WhatsApp executa; com `CHANNEL=baileys` use
esse perfil. O canal `cloud_api` (o padrão no `.env.example`) precisa de uma rota
HTTPS pública para o `/webhook` do orquestrador, fornecida pelo perfil `tunnel`.

Cada serviço tem um limite de memória (`mem_limit`):

| Serviço | Limite |
|---|---|
| `banco-de-dados` | 768 MiB |
| `back-end` | 768 MiB (a imagem reserva 75% para o heap da JVM) |
| `front-end` | 128 MiB |
| `redis` | 128 MiB, com `maxmemory` de 96 MiB |
| `orquestrador` | 256 MiB |
| `ngrok` (perfil `tunnel`) | 64 MiB |
| `adaptador-baileys` (perfil `baileys`) | 256 MiB |

### Túnel HTTPS (canal Cloud API)

```sh
docker compose --profile tunnel up -d
```

Inicia um túnel `ngrok` para o webhook do orquestrador (`NGROK_UPSTREAM`, padrão
`orquestrador:8000`) no domínio fixo da conta (`NGROK_DOMAIN`), que não muda entre
reinícios. Requer `NGROK_AUTHTOKEN` e `NGROK_DOMAIN`. Nada além do `docker-compose.yml`
é necessário.

Registre o webhook na Meta Cloud API usando a rota de entrada do orquestrador:

```
https://<NGROK_DOMAIN>/webhook
```

Use `CLOUD_API_VERIFY_TOKEN` como o verify token que a Meta envia no handshake GET.
O túnel publica a porta inteira do `NGROK_UPSTREAM`, então essa porta não pode
servir rotas internas.

### WhatsApp via o adaptador Baileys

```sh
docker compose --profile baileys up
```

Defina `CHANNEL=baileys` no `.env` e, no modo de número único (a conta pareada é
também a remetente autorizada), `ACCEPT_OWN_MESSAGES=true`.

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
  `orquestrador`, `ngrok` e `adaptador-baileys`; estes também ficam na `interna`
  para o tráfego dentro da pilha. Não publica porta.
- `front-end` está anexado a ambas: publica sua porta na `publica` e
  faz proxy de `/api` para o back-end pela `interna`.

### Expor as portas locais

A porta do back-end, publicada pelo override local, e a da UI de inspeção do
ngrok, publicada pelo perfil `tunnel`, estão presas em `127.0.0.1` por padrão,
então apenas a máquina que executa a pilha pode alcançá-las:

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
docker compose down        # mantém os volumes nomeados (banco, Redis, sessão do WhatsApp)
```

Evite `docker compose down -v`: além do banco, ele apaga a fila do Redis e a sessão
do WhatsApp, que exige parear o dispositivo de novo. Para recomeçar só o banco, use
o procedimento abaixo.

## Recriar o banco

O schema é criado pelas migrações Flyway do back-end na primeira subida de um banco
vazio. Recrie o banco quando:

- trocar para imagens de `banco-de-dados` e `back-end` com Flyway (troque as duas
  tags juntas: uma sem a outra deixa o banco sem schema ou com um schema que o Flyway
  recusa);
- a migração inicial for editada (o checksum deixa de bater);
- o valor de `DEMO_DATA` mudar.

Procedimento:

1. Se houver dados que importam, faça um backup antes.
2. `docker compose down` (sem `-v`).
3. `docker volume rm doceterapia_banco-de-dados-data`. Remove só o banco; o volume do
   Redis e o da sessão do WhatsApp ficam.
4. `docker compose up -d` e confira `Successfully applied` em
   `docker compose logs back-end`.

## Checklist de subida

1. `docker compose pull` com as tags do `.env`.
2. Banco novo (procedimento acima), com `DEMO_DATA=true` e `ADMIN_EMAIL` e `ADMIN_SENHA`
   fictícios.
3. `docker compose --profile tunnel up -d`; cronometre até todos ficarem `healthy` em
   `docker compose ps`.
4. Em `http://localhost:3000`, entre com o primeiro usuário e abra a Agenda com os dados
   de demonstração.
5. Confira o webhook pelo domínio fixo: `GET https://<NGROK_DOMAIN>/webhook?hub.mode=subscribe&hub.verify_token=<CLOUD_API_VERIFY_TOKEN>&hub.challenge=123`
   devolve `123`. Depois, envie uma mensagem de teste pela Cloud API.
6. Rode `docker stats --no-stream` três vezes durante o uso e anote o pico por serviço;
   revise o limite de quem passar de 90%.
7. `docker compose down` e `docker compose up -d` de novo: os dados continuam lá.
8. Canal alternativo: `CHANNEL=baileys`, `ACCEPT_OWN_MESSAGES=true` e
   `docker compose --profile baileys up -d`.

## Variáveis de ambiente

O `.env.example` lista cada variável agrupada por serviço, com valores de
exemplo. Grupos:

- Tags das imagens: `BANCO_DE_DADOS_TAG`, `BACK_END_TAG`, `FRONT_END_TAG`, `REDIS_TAG`,
  `ORQUESTRADOR_TAG`, `ADAPTADOR_BAILEYS_TAG` (fixadas nas versões publicadas
  atualmente, nunca `latest`; atualize para um build publicado mais novo definindo
  o novo `sha-<short>` ou semver).
- banco-de-dados: `MYSQL_ROOT_PASSWORD`, `MYSQL_DATABASE`, `MYSQL_USER`, `MYSQL_PASSWORD`.
- back-end: `SPRING_PROFILES_ACTIVE`, `DB_URL`, `DB_USERNAME`, `DB_PASSWORD`, `JWT_SECRET`,
  `ORQUESTRADOR_TOKEN`, `CORS_ALLOWED_ORIGINS`, `ADMIN_EMAIL`, `ADMIN_SENHA`,
  `COOKIE_SECURE`, `SWAGGER_ENABLED`, `DEMO_DATA`.
- front-end: `API_UPSTREAM`, `API_UPSTREAM_HOST`, `FRONTEND_HOST_PORT`.
- redis: `REDIS_PASSWORD`.
- orquestrador: `CHANNEL`, `BENEFICIARIA_TELEFONE`, `CORE_BASE_URL`, `ORQUESTRADOR_TOKEN`,
  `ORQUESTRADOR_REDIS_URL`, `CONV_TTL_MIN`, `MAX_AJUSTES`, `RETRY_MAX_TENTATIVAS`,
  `RETRY_BASE_S`, `RETRY_CAP_S`, `TZ`, `ADAPTER_URL`, `ADAPTER_SECRET`,
  `WEBHOOK_SECRET`, `CLOUD_API_PHONE_ID`, `CLOUD_API_TOKEN`, `CLOUD_API_APP_SECRET`,
  `CLOUD_API_VERIFY_TOKEN`, `CLOUD_API_GRAPH_VERSION`, `LLM_PROVIDER`,
  `GEMINI_API_KEY`, `GEMINI_MODEL`.
- adaptador-baileys (perfil `baileys`): `GRUPO_JID`, `WEBHOOK_URL`,
  `BAILEYS_SESSION_DIR`, `BAILEYS_LOG_LEVEL`, `DISCOVER_GROUPS`, `ACCEPT_OWN_MESSAGES` (além de
  `ADAPTER_SECRET` e `WEBHOOK_SECRET`, compartilhadas com o orquestrador).
- ngrok (perfil `tunnel`): `NGROK_TAG`, `NGROK_AUTHTOKEN`, `NGROK_DOMAIN`,
  `NGROK_UPSTREAM`, `NGROK_WEB_PORT`, `NGROK_WEB_BIND`.
- Apenas no override local: `BACK_END_HOST_PORT`, `BACK_END_HOST_BIND`.

O Compose interpola o arquivo inteiro, então as variáveis obrigatórias dos perfis
`tunnel` e `baileys` precisam existir mesmo sem o perfil ativo; o exemplo já traz
todas com valor.

Variáveis com regra própria e quem as recebe:

| Variável | Serviço | Padrão | Para que serve |
|---|---|---|---|
| `ORQUESTRADOR_TOKEN` | `back-end`, `orquestrador` | obrigatória | Credencial de serviço do orquestrador nas rotas do back-end |
| `CORS_ALLOWED_ORIGINS` | `back-end` | a linha é obrigatória; pode ser vazia | Origens cruzadas permitidas, separadas por vírgula |
| `ADMIN_EMAIL`, `ADMIN_SENHA` | `back-end` | vazias | Primeiro usuário, criado só com a tabela de usuários vazia |
| `COOKIE_SECURE` | `back-end` | `false` | Cookie de sessão só por HTTPS |
| `SWAGGER_ENABLED` | `back-end` | `false` | Swagger UI e documentação da API no perfil `prod` |
| `DEMO_DATA` | `back-end` | `false` | Dados fictícios de demonstração num banco novo; trocar depois exige recriar o banco |
| `ACCEPT_OWN_MESSAGES` | `adaptador-baileys` | `false` | Modo de número único: processa as mensagens da própria conta pareada |
| `NGROK_DOMAIN` | `ngrok` | obrigatória | Domínio fixo da conta ngrok, sem o esquema |
| `API_UPSTREAM_HOST` | `front-end` | obrigatória | Back-end como `host:porta`, para o `upstream` do nginx |
