# OpenComputers Telemetry Backend

NestJS backend + web dashboard for OpenComputers telemetry.

## Run Dev

```bash
npm install
cp .env.example .env
npm run start:dev
```

Default local port: `4444`. Tunnel host: `https://open.eonhorizon.net`.

## Build

```bash
npm run build
npm run start:prod
```

## Endpoints

- `GET /` - web dashboard
- `POST /api/oc/telemetry` - telemetry ingest, requires `Authorization: Bearer <OC_TOKEN>`
- `GET /api/oc/state` - aggregated UI state
- `GET /api/oc/nodes` - node summaries
- `GET /api/oc/nodes/:node` - full node state and raw latest payload
- `GET /api/oc/config?node=main-base` - flat Lua config
- `PATCH /api/oc/config/:node` - update node config
- `POST /api/oc/config/:node/reset` - reset node config
- `GET /api/oc/health` - health check

OpenComputers telemetry URL:

```txt
https://open.eonhorizon.net/api/oc/telemetry
```

Config URL:

```txt
https://open.eonhorizon.net/api/oc/config?node=main-base
```

Install/update Lua client:

```sh
wget -fq https://github.com/FenyaVeyvon/opencomputers-dashboard/raw/refs/heads/main/eon_oc_mvp.lua eon && eon
```

## curl POST Test

```bash
curl -X POST http://localhost:4444/api/oc/telemetry \
  -H "Authorization: Bearer CHANGE_ME_SECRET" \
  -H "Content-Type: application/json" \
  -d '{
    "node": "main-base",
    "nodeLabel": "Main Base",
    "nodeTags": ["base"],
    "version": "0.5.0",
    "players": {
      "count": 1,
      "list": [{
        "name": "FenyaVeyvon",
        "uuid": "e285be19-a8b9-442d-b6e6-4efe2826e39b",
        "online": true,
        "source": "chatbox",
        "age": 1
      }]
    },
    "chat": [{
      "player": "FenyaVeyvon",
      "uuid": "e285be19-a8b9-442d-b6e6-4efe2826e39b",
      "message": "@status"
    }],
    "me": {
      "ok": true,
      "totalStacks": 100,
      "totalItems": 50000,
      "top": [{ "id": "minecraft:diamond:0", "label": "Diamond", "count": 1200 }]
    },
    "flux": {
      "ok": true,
      "stored": 1000000,
      "max": 5000000,
      "input": 2000,
      "output": 1500
    },
    "api": { "ok": true, "status": "OK", "sent": 10, "failed": 0 },
    "config": { "ok": true, "status": "OK", "version": 1, "pulled": 5, "failed": 0 }
  }'
```
