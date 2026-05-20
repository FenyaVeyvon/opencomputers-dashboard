# EonLink для OpenComputers

Установка:

```lua
wget -fq https://raw.githubusercontent.com/FenyaVeyvon/opencomputers-dashboard/main/installer/installer.lua ins && ins
```

Настрой `/home/eonlink/config.lua`:

```lua
backend = {
  host = "open.eonhorizon.net",
  port = 4445,
  token = "change-me"
}
```

Запуск:

```sh
EonLink run
```

При запуске node:

- подключается к NestJS backend через домен `open.eonhorizon.net`;
- отправляет `hello`;
- забирает свой config по `nodeId`;
- применяет `members` через OpenComputers users;
- рисует GUI со статусом, members и log.

Команды:

```sh
EonLink update
EonLink repair
EonLink version
```
