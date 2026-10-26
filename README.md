# infra

Docker Compose environment for the Doceterapia system. The only repo needed to
run the stack: it pulls prebuilt, pinned images from GHCR and never builds by
default.

## Requirements

- Docker with Compose v2.
- A filled `.env` (see below). Nothing else on the host.

## Setup

```sh
cp .env.example .env   # then fill in the secrets
```

`.env` is git-ignored. It ships with the image tags already set to the
currently published versions, so the default stack runs as is; only the
`replace-me` secrets must be filled. Every variable is required unless its
comment says it has a default; a missing one stops `docker compose` with the
variable's name.

## Modes

### Run the published stack (default)

```sh
docker compose up
```

Pulls the images at the tags set in `.env` and starts `banco-de-dados`,
`back-end`, `front-end`, `redis` and `orquestrador`. The web app is published on
`http://localhost:3000` (override with `FRONTEND_HOST_PORT`). The database,
back-end and redis sit on the Docker-internal network `interna` (no host or
internet reachability); the orchestrator is also on `interna` but joins the
`saida` egress bridge for its outbound calls (LLM, Meta Cloud API). Only the
front-end is on the host-facing `publica` network and publishes a port. Without
the `baileys` profile no WhatsApp adapter runs; with `CHANNEL=baileys` (the
default in `.env.example`) use the profile below. The `cloud_api` channel needs a
public HTTPS route to the orchestrator's `/webhook`, which this stack does not
publish; the only route provided is the development tunnel.

### WhatsApp via the Baileys adapter

```sh
docker compose --profile baileys up
```

Adds `adaptador-baileys` to the stack. It keeps the WhatsApp session in the
named volume `adaptador-baileys-session` (survives `docker compose down`), only
processes messages from the group in `GRUPO_JID`, and forwards inbound events to
the orchestrator webhook (`WEBHOOK_URL`) over the internal network.

Pair the device the first time by reading the QR from the adapter logs:

```sh
docker compose --profile baileys logs -f adaptador-baileys
```

Scan the printed QR with WhatsApp (Linked devices) on the assistant's phone. The
session then persists in the volume, so later starts reconnect without a new QR.

Find the group id for `GRUPO_JID` after pairing: set `DISCOVER_GROUPS=true` in
`.env`, restart the adapter, read the logged ids and names, then turn it back
off:

```sh
docker compose --profile baileys up -d adaptador-baileys
docker compose --profile baileys logs adaptador-baileys | grep 'group discovery'
```

Copy the `jid` of the dedicated group into `GRUPO_JID`, set `DISCOVER_GROUPS`
back to `false` and run `docker compose --profile baileys up -d` again. The log
lists group names, so keep it private.

### Develop a service locally

Build one or more services from their sibling checkouts (`../back-end`,
`../front-end`, `../banco-de-dados`, `../assistente-whatsapp/orquestrador`,
`../assistente-whatsapp/adaptador-baileys`) instead of pulling them; the services
you do not name keep their published images:

```sh
docker compose -f docker-compose.yml -f compose.local.yml up --build back-end
```

The override also publishes the back-end port for Swagger UI
(`http://localhost:8080/swagger-ui/index.html`, override with `BACK_END_HOST_PORT`).
It is bound to `127.0.0.1` by default; set `BACK_END_HOST_BIND=0.0.0.0` to reach
it from other hosts (see Exposing the local ports).
To make that published port reachable it also attaches the back-end to the
`publica` network; in the default stack the back-end stays on `interna` only.

## Networks

- `interna`: Docker-internal (`internal: true`). Holds `banco-de-dados`,
  `back-end`, `redis` and the assistant services (`orquestrador`,
  `adaptador-baileys`). Services here have no host or internet reachability
  and cannot publish ports, so the database is never exposed.
- `publica`: normal bridge for host-facing traffic. Only the front-end is on
  it in the default stack (and the back-end when the local override publishes
  its port).
- `saida`: egress-only bridge. Carries the outbound internet traffic of
  `orquestrador` and `adaptador-baileys` (and `ngrok` in the local override);
  these also stay on `interna` for in-stack traffic. It publishes no port.
- `front-end` is attached to both: it publishes its port on `publica` and
  proxies `/api` to the back-end over `interna`.

### HTTPS tunnel (Cloud API webhook tests)

```sh
docker compose -f docker-compose.yml -f compose.local.yml --profile tunnel up
```

Starts an `ngrok` tunnel to the orchestrator webhook (`NGROK_UPSTREAM`, default
`orquestrador:8000`); the public HTTPS URL is printed in the `ngrok` logs and
reaches the orchestrator over the internal network. Requires `NGROK_AUTHTOKEN`.

In `cloud_api` mode, register the webhook with the Meta Cloud API using the
orchestrator's inbound route, `/webhook`:

```
https://<ngrok-host>/webhook
```

Use `CLOUD_API_VERIFY_TOKEN` as the verify token Meta sends on the GET handshake.

### Exposing the local ports

The two ports the local override publishes are bound to `127.0.0.1` by
default, so only the machine running the stack can reach them:

| Variable | Port | What it exposes |
|---|---|---|
| `BACK_END_HOST_BIND` | `BACK_END_HOST_PORT` (8080) | Back-end API and Swagger UI; business routes have no authentication |
| `NGROK_WEB_BIND` | `NGROK_WEB_PORT` (4040) | ngrok inspection UI; shows request bodies and signatures, no authentication |

On a provisioned server, set the variable to `0.0.0.0` in `.env` to reach
the panel from outside, and restrict the port with a firewall or security group
(allow only your own address). The front-end port is not affected: it is the
web app and is published on all interfaces.
## Stop

```sh
docker compose down        # keeps named volumes (data, Redis)
docker compose down -v      # also removes the volumes
```

## Environment variables

`.env.example` lists every variable grouped by service, with placeholder
values. Groups:

- Image tags: `BANCO_DE_DADOS_TAG`, `BACK_END_TAG`, `FRONT_END_TAG`, `REDIS_TAG`,
  `ORQUESTRADOR_TAG`, `ADAPTADOR_BAILEYS_TAG` (pinned to the currently published
  versions, never `latest`; bump to a newer published build by setting the new
  `sha-<short>` or semver).
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
- adaptador-baileys (profile `baileys`): `GRUPO_JID`, `WEBHOOK_URL`,
  `BAILEYS_SESSION_DIR`, `BAILEYS_LOG_LEVEL`, `DISCOVER_GROUPS` (plus
  `ADAPTER_SECRET` and `WEBHOOK_SECRET`, shared with the orchestrator).
- Local override only: `BACK_END_HOST_PORT`, `BACK_END_HOST_BIND`, `NGROK_AUTHTOKEN`,
  `NGROK_UPSTREAM`, `NGROK_WEB_PORT`, `NGROK_WEB_BIND`, `NGROK_TAG`.
