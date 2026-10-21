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
`back-end` and `front-end`. The web app is published on
`http://localhost:3000` (override with `FRONTEND_HOST_PORT`). The database and
back-end sit on the Docker-internal network `interna` (no host or internet
reachability); only the front-end is on the host-facing `publica` network and
publishes a port.

> Note: the full stack does not come up yet. The front-end waits for a healthy
> back-end, and the back-end cannot become healthy against the currently
> published database image, whose schema is behind the back-end entities. The
> stack stays blocked until a database image with the corrected schema is
> published; after that, only `BANCO_DE_DADOS_TAG` (and the matching
> `BACK_END_TAG`) need to be bumped in `.env`.

### Develop a service locally

Build one or more services from their sibling checkouts (`../back-end`,
`../front-end`, `../banco-de-dados`) instead of pulling them; the services you do
not name keep their published images:

```sh
docker compose -f docker-compose.yml -f compose.local.yml up --build back-end
```

The override also publishes the back-end port for Swagger UI
(`http://localhost:8080/swagger-ui/index.html`, override with `BACK_END_HOST_PORT`).
To make that published port reachable it also attaches the back-end to the
`publica` network; in the default stack the back-end stays on `interna` only.

## Networks

- `interna`: Docker-internal (`internal: true`). Holds `banco-de-dados` and
  `back-end`. Services here have no host or internet reachability and cannot
  publish ports, so the database is never exposed.
- `publica`: normal bridge for host-facing traffic. Only the front-end is on
  it in the default stack (and the back-end when the local override publishes
  its port).
- `front-end` is attached to both: it publishes its port on `publica` and
  proxies `/api` to the back-end over `interna`.

## Stop

```sh
docker compose down        # keeps named volumes (data)
docker compose down -v      # also removes the volumes
```

## Environment variables

`.env.example` lists every variable grouped by service, with placeholder
values. Groups:

- Image tags: `BANCO_DE_DADOS_TAG`, `BACK_END_TAG`, `FRONT_END_TAG`
  (pinned to the currently published versions, never `latest`; bump to a newer
  published build by setting the new `sha-<short>` or semver).
- banco-de-dados: `MYSQL_ROOT_PASSWORD`, `MYSQL_DATABASE`, `MYSQL_USER`, `MYSQL_PASSWORD`.
- back-end: `SPRING_PROFILES_ACTIVE`, `DB_URL`, `DB_USERNAME`, `DB_PASSWORD`, `JWT_SECRET`.
- front-end: `API_UPSTREAM`, `FRONTEND_HOST_PORT`.
- Local override only: `BACK_END_HOST_PORT`.
