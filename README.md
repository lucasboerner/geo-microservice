# geo-microservice

A self-hostable **geocoding + routing gateway**: it bundles
[Photon](https://github.com/komoot/photon) (forward/reverse geocoding and
autocomplete) and [OSRM](https://project-osrm.org/) (address-to-address routing)
behind **one unified HTTP API**, built on PHP / Symfony / API Platform 4 and
served by [FrankenPHP](https://frankenphp.dev/).

You set **one knob — `REGION`** — and the stack downloads the Photon index and
builds the OSRM graph for that area automatically on first boot. No database, no
manual data import, no third-party API keys.

It exposes three things over a clean JSON API:

1. **Geocoding** — address → coordinates
2. **Autocomplete** — search-as-you-type, location-biased
3. **Routing** — route between two addresses (or coordinates), with geometry,
   distance and duration

---

## Quickstart

```bash
cp .env.dist .env.local      # optional: change REGION or other defaults
docker compose up            # first boot imports data — see "First boot" below
```

That's it. The default `REGION=de` brings up the whole stack for Germany. Once
the gateway is healthy:

```bash
curl 'http://localhost:8080/health'
open http://localhost:8080/docs        # interactive API reference
```

To enable Redis caching instead of the filesystem, set `ENABLE_REDIS=true` (see
[Configuration](#configuration)) and run `docker compose up` again — the bundled
`redis` service starts automatically.

> **Note on the bundled `API_KEY`.** The committed `.env` ships `API_KEY=1234`
> for local development, so every endpoint except `/health` requires the
> `X-API-Key` header. Send `-H 'X-API-Key: 1234'` with the curl examples below,
> or clear `API_KEY` to run the API open. The `.env.dist` template leaves it
> empty (open) by default.

---

## First boot, hardware & disk (read before deploying)

The first `docker compose up` does the slow, one-time data import. The `gateway`
deliberately **waits until both backends are healthy**, so the first start sits
for a while before serving — that is expected, not a hang. Watch progress with:

```bash
docker compose logs -f photon osrm-init
```

What happens, and what it costs:

- **Photon** downloads a *prebuilt* index for the region. A single country is in
  the **low tens of GB** on disk (check the current size on the index server);
  continents are far larger.
- **OSRM** downloads the Geofabrik `.osm.pbf` extract and then **builds** the
  routing graph (`osrm-extract` → `osrm-partition` → `osrm-customize`). This is
  **CPU- and RAM-heavy** and one-time. A country like Germany needs several GB of
  free RAM and disk for the build; larger extracts (a continent, or `planet`)
  need **substantially more disk and RAM** — budget a much bigger box.
- **Serving** a country graph afterwards is modest; serving Europe/planet is not.

Both datasets are stored in named volumes (`photon_data`, `osrm_data`), so
**subsequent boots are fast** — the import is skipped. To rebuild for a new
`REGION`, remove the volumes first:

```bash
docker compose down
docker volume rm geo-microservice_photon_data geo-microservice_osrm_data
docker compose up
```

### ARM hosts (Apple Silicon, Hetzner CAX, …)

Before deploying on `arm64`, verify the upstream images publish an `arm64`
variant:

```bash
docker buildx imagetools inspect rtuszik/photon-docker:latest
docker buildx imagetools inspect ghcr.io/project-osrm/osrm-backend:latest
```

If a tag is `amd64`-only, build it locally (both are architecture-portable) or
run it under emulation. The gateway image (FrankenPHP) builds fine on `arm64`.

### Photon download mirror

The `rtuszik/photon-docker` image defaults its index download to a community
mirror. For production, point it at the official GraphHopper server or a dump
you host yourself (set `BASE_URL` on the `photon` service in `compose.yaml`).

---

## The coverage rule (`REGION` drives both backends)

`REGION` selects **two** things from one value: the Photon prebuilt index *and*
the Geofabrik extract that the OSRM graph is built from (mapped in
`osrm/build.sh`). They are tied together on purpose, because of:

> **OSRM coverage must be ⊇ Photon coverage.** The routing graph has to cover **at
> least** the same area as the geocoder. Otherwise an address can be geocoded but
> not routed — Photon finds a city that OSRM's graph doesn't contain. **Never
> point OSRM at a smaller extract than Photon.** (OSRM larger than Photon is
> wasteful but safe.)

With a single `REGION`, both backends are built for the same country, so they
match by construction. If you set `GEOFABRIK_URL` to override the OSRM extract
for a region not in the built-in map, make sure that extract still covers at
least the Photon area.

Built-in `REGION` map (extend in `osrm/build.sh`):

| `REGION`           | Photon region | Geofabrik extract    |
|--------------------|---------------|----------------------|
| `de` / `germany`   | `de`          | `europe/germany`     |
| `at` / `austria`   | `at`          | `europe/austria`     |
| `fr` / `france`    | `fr`          | `europe/france`      |
| `nl` / `netherlands` | `nl`        | `europe/netherlands` |
| `es` / `spain`     | `es`          | `europe/spain`       |
| `it` / `italy`     | `it`          | `europe/italy`       |
| `ch` / `switzerland` | `ch`        | `europe/switzerland` |
| `be` / `belgium`   | `be`          | `europe/belgium`     |
| `pl` / `poland`    | `pl`          | `europe/poland`      |
| `europe`           | `europe`      | `europe`             |

For any other region, set both a Photon-supported `REGION` value and a matching
`GEOFABRIK_URL`.

---

## Configuration

Everything has a working default — `REGION=de docker compose up` runs with no
extra config. Set values in `.env.local` (or `.env`). See `.env.dist` for the
annotated template.

| Variable            | Default                | Purpose                                                                                  |
|---------------------|------------------------|------------------------------------------------------------------------------------------|
| `REGION`            | `de`                   | **The one knob.** Selects the Photon index and the OSRM graph (see the coverage rule).   |
| `DEFAULT_LANG`      | `de`                   | Default result language (Photon `lang`).                                                 |
| `OSRM_PROFILE`      | `car`                  | OSRM routing profile: `car`, `bicycle` or `foot`. Changing it needs a graph rebuild.     |
| `GEOFABRIK_URL`     | *(unset)*              | Override the auto-derived `.osm.pbf` extract URL for a region not in the built-in map.   |
| `CACHE_TTL`         | `86400`                | Cache lifetime in seconds for geocoding and routing lookups.                             |
| `ENABLE_REDIS`      | `false`                | **The only Redis knob.** `true` starts the bundled `redis` service and caches there; otherwise a filesystem cache is used (no extra service). |
| `API_KEY`           | *(unset)*              | If set, every request except `/health` must send it via `X-API-Key`. Empty = open.       |
| `CORS_ALLOW_ORIGIN` | `*`                    | CORS origin(s) allowed for browser autocomplete.                                         |
| `PHOTON_URL`        | `http://photon:2322`   | Internal Photon URL. Set automatically under Compose; only change for bare-metal setups. |
| `OSRM_URL`          | `http://osrm:5000`     | Internal OSRM URL. Set automatically under Compose; only change for bare-metal setups.   |

`COMPOSE_PROFILES` in `.env` is **plumbing** that maps `ENABLE_REDIS` onto a
Compose profile — leave it as-is; toggle Redis via `ENABLE_REDIS`.

---

## API reference

Base URL: `http://localhost:8080`. Add `-H 'Accept: application/json'` for plain
JSON (otherwise API Platform negotiates JSON:API / JSON-LD). If `API_KEY` is set,
add `-H 'X-API-Key: <key>'` (the bundled dev value is `1234`). The interactive
reference with every parameter lives at **`/docs`**.

> **Parameter naming.** The search term for `/geocode` and `/autocomplete` is
> **`query`** (not `q`). The build spec's `?q=` examples are aspirational; the
> implementation uses `?query=`, which is what the examples below and the smoke
> test use.

### `GET /geocode` — address → coordinates

| Param   | Required | Default | Notes                  |
|---------|----------|---------|------------------------|
| `query` | yes      | —       | Address or place name. |
| `limit` | no       | `5`     | Max results.           |
| `lang`  | no       | `DEFAULT_LANG` | Result language. |

```bash
curl -G 'http://localhost:8080/geocode' \
  -H 'Accept: application/json' -H 'X-API-Key: 1234' \
  --data-urlencode 'query=Webergasse 1 Dresden'
```

```json
[
  {
    "label": "Webergasse 1, 01067 Dresden, Germany",
    "lat": 51.0578,
    "lon": 13.7237,
    "street": "Webergasse",
    "houseNumber": "1",
    "postCode": "01067",
    "city": "Dresden",
    "countryCode": "DE"
  }
]
```

### `GET /autocomplete` — search-as-you-type, location-biased

| Param   | Required | Default | Notes                              |
|---------|----------|---------|------------------------------------|
| `query` | yes      | —       | Partial address or place name.     |
| `lat`   | no       | —       | Latitude to bias results towards.  |
| `lon`   | no       | —       | Longitude to bias results towards. |
| `limit` | no       | `8`     | Max results.                       |
| `lang`  | no       | `DEFAULT_LANG` | Result language.            |

```bash
curl -G 'http://localhost:8080/autocomplete' \
  -H 'Accept: application/json' -H 'X-API-Key: 1234' \
  --data-urlencode 'query=Marschner' \
  --data-urlencode 'lat=51.05' --data-urlencode 'lon=13.74'
```

Returns the same `Place` shape as `/geocode`.

### `GET /reverse` — coordinates → address

| Param  | Required | Default | Notes               |
|--------|----------|---------|---------------------|
| `lat`  | yes      | —       | Latitude.           |
| `lon`  | yes      | —       | Longitude.          |
| `lang` | no       | `DEFAULT_LANG` | Result language. |

```bash
curl -G 'http://localhost:8080/reverse' \
  -H 'Accept: application/json' -H 'X-API-Key: 1234' \
  --data-urlencode 'lat=51.0504' --data-urlencode 'lon=13.7373'
```

Returns a single `Place`.

### `GET /route` — A → B route

`from` and `to` each accept either an address (geocoded to its best match) or a
`"lat,lon"` coordinate pair.

| Param  | Required | Default | Notes                                       |
|--------|----------|---------|---------------------------------------------|
| `from` | yes      | —       | Origin: address or `lat,lon`.               |
| `to`   | yes      | —       | Destination: address or `lat,lon`.          |
| `lang` | no       | `DEFAULT_LANG` | Language used when geocoding addresses. |

```bash
# by address
curl -G 'http://localhost:8080/route' \
  -H 'Accept: application/json' -H 'X-API-Key: 1234' \
  --data-urlencode 'from=Webergasse 1 Dresden' \
  --data-urlencode 'to=Peschelstr 33 Dresden'

# by coordinates
curl -G 'http://localhost:8080/route' \
  -H 'Accept: application/json' -H 'X-API-Key: 1234' \
  --data-urlencode 'from=51.05,13.74' \
  --data-urlencode 'to=51.06,13.75'
```

```json
{
  "from": { "lat": 51.0578, "lon": 13.7237 },
  "to":   { "lat": 51.0719, "lon": 13.7869 },
  "distanceInMeters": 5421.3,
  "durationInSeconds": 612.7,
  "geometry": { "type": "LineString", "coordinates": [ [13.7237, 51.0578], "…" ] }
}
```

### `GET /health` — readiness

Returns `200` only when **both** upstreams are reachable, `503` otherwise. Not
protected by `API_KEY`.

```bash
curl 'http://localhost:8080/health'
# {"status":"ok","photon":true,"osrm":true}
```

### `GET /docs` — interactive API reference

OpenAPI-backed interactive docs (Scalar), listing every endpoint with its query
parameters.

### Error shape

Errors use API Platform's RFC 7807 problem responses: `400` for missing
parameters, `422` when an address can't be geocoded, `502` when an upstream
fails.

---

## Smoke test

With the stack running, check the three core endpoints end-to-end:

```bash
make smoke                 # against http://localhost:8080
make smoke API_KEY=1234    # if the deployment requires an API key
BASE_URL=http://host:8080 API_KEY=secret make smoke
```

It exits non-zero if `/health`, `/geocode` or `/route` is down or returns the
wrong shape. The script is `bin/smoke.sh`.

---

## Architecture

- **Stateless proxy — no database, no ORM.** API Platform resources are plain
  DTOs (`src/ApiResource/`) served by custom state providers (`src/State/`) that
  call Photon/OSRM via Symfony HttpClient. The gateway boots with zero DB.
- **lon/lat ordering** (Photon returns `[lon,lat]`; OSRM URLs are `lon,lat`) is
  encapsulated in the clients, not leaked to responses.
- **Caching** wraps the Photon and OSRM clients (`src/Cache/`, `src/Client/`):
  filesystem by default, Redis when `ENABLE_REDIS=true`.
- **Data import lives in `osrm/build.sh`** (idempotent), never in PHP.

Services: `gateway` (this app), `photon`, `osrm` (+ one-shot `osrm-init`), and an
optional `redis`. See `compose.yaml`.

---

## License

[MIT](LICENSE) © 2026 Lucas Börner.
