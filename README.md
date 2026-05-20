# EonLink

EonLink - OpenComputers 1.12.2 node runtime + NestJS backend.

Архитектура:

```text
OpenComputers Lua GUI <-> TCP JSON Line Protocol <-> NestJS API + Prisma <-> PostgreSQL <-> Web Dashboard
```

Lua-node при запуске подключается к backend по TCP, отправляет `hello`, получает свой конфиг по `nodeId`, применяет `members` через `computer.addUser/removeUser` и показывает локальный GUI со статусом, версией конфига, members и log.

## Установка в OpenComputers

```lua
wget -fq https://raw.githubusercontent.com/FenyaVeyvon/opencomputers-dashboard/main/installer/installer.lua ins && ins
```

## Запуск node

```sh
EonLink run
```

Конфиг node:

```text
/home/eonlink/config.lua
```

Главное:

```lua
return {
  nodeId = "base_pc_1",
  backend = {
    host = "open.eonhorizon.net",
    port = 4444,
    token = "change-me"
  },
  members = {},
  debug = true
}
```

`members` приходят из backend отдельно для каждой node. Runtime применяет их к OpenComputers whitelist.

## Backend

```sh
cd workspace
docker compose up -d
npm install
npx prisma migrate dev --name init
npm run start:dev
```

Переменные:

```env
PORT=4444
EONLINK_TCP_PORT=4444
EONLINK_NODE_TOKEN=change-me
DATABASE_URL="postgresql://eonlink:eonlink@localhost:5432/eonlink?schema=public"
```

API:

```text
GET   /api/nodes
GET   /api/nodes/:node
GET   /api/nodes/:node/config?token=change-me
PATCH /api/nodes/:node/config
GET   /api/nodes/:node/logs
```

Пример настройки members:

```sh
curl -X PATCH http://open.eonhorizon.net/api/nodes/base_pc_1/config ^
  -H "Content-Type: application/json" ^
  -d "{\"members\":[\"FenyaVeyvon\",\"FriendNick\"],\"token\":\"change-me\"}"
```

## Обновление OC

```sh
EonLink update
EonLink repair
EonLink version
```
