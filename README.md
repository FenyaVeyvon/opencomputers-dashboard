# EonLink

EonLink - Lua-система для OpenComputers 1.12.2, которая связывает компьютер в Minecraft с backend по TCP line protocol.

Архитектура:

```text
OpenComputers Lua <-> TCP Line Protocol <-> Node.js Backend <-> Socket.IO <-> Web Dashboard
```

## Установка

```lua
wget -fq https://raw.githubusercontent.com/FenyaVeyvon/opencomputers-dashboard/main/installer/installer.lua ins && ins
```

Установка кладет runtime в `/home/eonlink`, команды в `/bin/EonLink.lua` и `/bin/eonlink.lua`.

## Запуск

```sh
EonLink run
```

## Обновление

```sh
EonLink update
```

## Repair

```sh
EonLink repair
```

## Модули

```sh
EonLink modules
EonLink enable radar
EonLink disable inventory
```

## Конфиг

Основной конфиг находится тут:

```text
/home/eonlink/config.lua
```

Чтобы поменять backend, отредактируй:

```lua
backend = {
  host = "127.0.0.1",
  port = 5050,
  token = "change-me"
}
```

`update` и `repair` не перетирают `/home/eonlink/config.lua`.

## Новый модуль

Добавь файл в `/home/eonlink/modules/<name>.lua` и включи его:

```sh
EonLink enable <name>
```

Пример структуры:

```lua
local M = {}

M.name = "example"
M.version = "0.1.0"

function M.init(ctx)
end

function M.tick(dt)
end

function M.onMessage(msg)
end

return M
```
