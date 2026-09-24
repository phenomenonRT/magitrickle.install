<p align="center">
  <img src="https://gitlab.com/magitrickle/magitrickle/-/raw/develop/img/logo256.png" alt="MagiTrickle logo" width="160">
</p>

# MagiTrickle

Проект изменен <https://gitlab.com/phenomenonRT/magitrickle>

## Назначение

MagiTrickle (произносится как *Мэджитрикл*) – утилита для точечной маршрутизации сетевого трафика по заданным доменным именам. Представляет собой установочный пакет, устанавливаемый в дополнение к операционной системе маршрутизатора.

![MagiTrickle Screenshot](https://gitlab.com/magitrickle/magitrickle/-/raw/develop/img/main_screenshot.png)

Принцип работы основан на подмене основного DNS-сервера через промежуточный компонент без его отключения. Это позволяет перехватывать входящие DNS-запросы, кешировать ответы и сопоставлять IP-адреса с доменными именами. Благодаря этому становится возможной маршрутизация трафика без необходимости очистки DNS-кэша на стороне клиентов. Очистка кэша требуется только при запуске или перезапуске сервиса MagiTrickle, поскольку в этот момент кэш ещё не прогрет, и маршрутизация невозможна до первого запроса к нужному домену.

## Резервный интернет-канал

Для группы или подписки можно указать основной интерфейс и упорядоченный список резервных интерфейсов.

### Keenetic

Создайте на роутере политику доступа в интернет и задайте в ней приоритет подключений. Затем выберите эту политику в списке интерфейсов MagiTrickle. Переключением между подключениями управляет сам Keenetic: при отказе текущего подключения он использует следующее доступное подключение из политики.

### OpenWrt и другие системы с Linux

Выберите основной интерфейс, затем добавьте резервные в нужном порядке. MagiTrickle следит за событиями интерфейса через netlink: при отключении интерфейса его маршрут убирается сразу. Дополнительно сервис проверяет доступ в интернет TCP-подключением к публичным адресам IPv4 и IPv6 на порту 443, привязанным к каждому интерфейсу. После трёх неудачных проверок маршрут уступает настроенным резервам; после двух успешных проверок восстанавливает приоритет. Проверка запускается раз в пять секунд.

Для переключения интерфейс должен появляться в списке доступных интерфейсов MagiTrickle и иметь настроенный default route. Проверка подтверждает TCP-доступность публичных адресов на порту 443; если сеть блокирует эти подключения, канал может считаться недоступным. MagiTrickle устанавливает отдельные маршруты для своих правил и не меняет настройки `mwan3` или UCI.

## Установка одной командой

Установщик [`install.sh`](install.sh) сам определяет систему роутера, находит **последний релиз** в [Releases](https://github.com/phenomenonRT/magitrickle/releases), скачивает подходящий пакет, устанавливает его и перезапускает сервис. Чтобы **обновиться** позже, просто запустите ту же команду ещё раз.

Зайдите на роутер по SSH от имени `root` и вставьте команду.

### OpenWrt (любая версия)

```sh
wget -qO- https://raw.githubusercontent.com/phenomenonRT/magitrickle/main/install.sh | sh
```

Или через `curl`, если он установлен:

```sh
curl -fsSL https://raw.githubusercontent.com/phenomenonRT/magitrickle/main/install.sh | sh
```

### Keenetic (Entware)

Команду нужно выполнять внутри **Entware** (SSH на роутер, обычно порт `222`), а не в основной командной строке Keenetic. Для скачивания по HTTPS нужен `curl` и сертификаты:

```sh
opkg update && opkg install curl ca-certificates
curl -fsSL https://raw.githubusercontent.com/phenomenonRT/magitrickle/main/install.sh | sh
```

### Что делает установщик

1. Определяет платформу: OpenWrt (`apk` на 25.12+, `opkg` на 24.10 и старше) или Entware на Keenetic.
2. Определяет архитектуру процессора (для OpenWrt из `/etc/openwrt_release`, для Entware из `opkg print-architecture`).
3. Получает список файлов последнего релиза и выбирает подходящий (см. таблицу ниже).
4. Сравнивает версию с установленной. Если она уже последняя, ничего не делает.
5. Скачивает пакет, обновляет индекс пакетов (чтобы подтянулись зависимости) и ставит его.
6. Перезапускает сервис. При первой установке на OpenWrt дополнительно включает автозапуск.

### Какой файл выбирается

| Система | Менеджер пакетов | Файл в релизе |
|---|---|---|
| OpenWrt 25.12 и новее | `apk` | `magitrickle_<версия>_openwrt_<архитектура>.apk` |
| OpenWrt 24.10 и старше | `opkg` | `magitrickle_<версия>_openwrt_<архитектура>.ipk` |
| Keenetic (Entware) | `opkg` | `magitrickle_<версия>_entware_<архитектура>_kn.ipk` |
| Другое устройство с Entware | `opkg` | `magitrickle_<версия>_entware_<архитектура>.ipk` |

Сборка с суффиксом `_kn` предназначена для Keenetic. Установщик выбирает её, если находит на роутере `ndmc`, и использует обычную сборку, если `_kn` для вашей архитектуры в релизе нет.

## Параметры установщика

Параметры передаются после `sh -s --`:

```sh
wget -qO- https://raw.githubusercontent.com/phenomenonRT/magitrickle/main/install.sh | sh -s -- -c
```

| Параметр | Что делает |
|---|---|
| `-c`, `--check` | Только показать установленную и доступную версии, ничего не устанавливая |
| `-f`, `--force` | Переустановить, даже если версия уже последняя |
| `-l`, `--list` | Показать все файлы релиза и тот, что выбран для этого роутера |
| `-u`, `--url URL` | Установить пакет (`.ipk` или `.apk`) по прямой `https`-ссылке |
| `-h`, `--help` | Справка |

Установка конкретного файла по ссылке (например, другой версии из Releases):

```sh
wget -qO- https://raw.githubusercontent.com/phenomenonRT/magitrickle/main/install.sh | sh -s -- -u https://github.com/phenomenonRT/magitrickle/releases/download/<тег>/<файл>.ipk
```

Переменные окружения ставятся перед `sh`:

```sh
wget -qO- https://raw.githubusercontent.com/phenomenonRT/magitrickle/main/install.sh | KN=0 sh
```

| Переменная | Назначение |
|---|---|
| `ARCH` | Задать архитектуру вручную, если автоопределение ошиблось (например, `ARCH=aarch64_cortex-a53`) |
| `KN` | Entware: `1` ставить сборку для Keenetic (`_kn`), `0` обычную. По умолчанию определяется сама |
| `ALLOW_UNTRUSTED` | `1` разрешает `apk` ставить пакет без проверки подписи (только OpenWrt 25.12+) |
| `REPO` | Брать релизы из другого репозитория, по умолчанию `phenomenonRT/magitrickle` |

## Безопасность

Установщик скачивает пакет из Releases этого репозитория и ставит его с правами `root`. Если не хотите запускать скрипт «вслепую», скачайте его, прочитайте и только потом запустите:

```sh
wget -O /tmp/install.sh https://raw.githubusercontent.com/phenomenonRT/magitrickle/main/install.sh
less /tmp/install.sh
sh /tmp/install.sh
```

## Управление сервисом

| Действие | Entware (Keenetic) | OpenWrt |
|---|---|---|
| Запустить | `/opt/etc/init.d/S99magitrickle start` | `service magitrickle start` |
| Остановить | `/opt/etc/init.d/S99magitrickle stop` | `service magitrickle stop` |
| Перезапустить | `/opt/etc/init.d/S99magitrickle restart` | `service magitrickle restart` |

Удаление пакета: `opkg remove magitrickle` (Entware, OpenWrt 24.10 и старше) или `apk del magitrickle` (OpenWrt 25.12+).

## Если что-то пошло не так

| Сообщение или симптом | Что делать |
|---|---|
| `нужен curl или wget с поддержкой HTTPS` | OpenWrt: `opkg install ca-bundle libustream-mbedtls` (или `apk add ...`). Entware: `opkg install curl ca-certificates` |
| `не похоже ни на OpenWrt, ни на Entware` | На Keenetic зайдите в Entware по SSH (обычно порт `222`), а не в основную оболочку роутера. Entware должен быть установлен |
| `в релизе ... нет сборки под ...` | Посмотрите список файлов: `sh -s -- -l`. Если ваша архитектура есть под другим названием, задайте её через `ARCH=...` |
| `GitHub API не ответил, читаю страницу релиза` | Это предупреждение, а не ошибка: у GitHub API лимит запросов с одного IP, и установщик автоматически берёт список файлов со страницы релиза |
| `UNTRUSTED signature` при установке через `apk` | Пакет подписан не тем ключом, которому доверяет система. Если доверяете этому репозиторию, запустите с `ALLOW_UNTRUSTED=1` |
| Ошибки зависимостей (`opkg` / `apk`) | Обновите индекс пакетов (`opkg update` или `apk update`) и проверьте, что у роутера есть доступ к репозиториям прошивки |

## Установка из официального репозитория MagiTrickle

<details>
<summary>Команды для установки из <code>bin.magitrickle.dev</code></summary>

Так ставится сборка из официального репозитория MagiTrickle, а не из Releases этого репозитория. Если этот репозиторий добавлен в систему, то обычный `opkg upgrade` или `apk upgrade` может заменить пакет на официальный.

**Entware**

```sh
wget -qO- http://bin.magitrickle.dev/packages/add_repo.sh | sh
opkg update && opkg install magitrickle
/opt/etc/init.d/S99magitrickle start
```

**OpenWrt 25.12 и новее**

```sh
wget -qO- http://bin.magitrickle.dev/packages/add_repo.sh | sh
apk update && apk add magitrickle
service magitrickle start
```

**OpenWrt 24.10 и старше**

```sh
wget -qO- http://bin.magitrickle.dev/packages/add_repo.sh | sh
opkg update && opkg install magitrickle
service magitrickle start
```

</details>

## Описание типов правил

### Namespace (Именное пространство)

Охватывает указанный домен и все его поддомены.

Например, при записи `example.com` будут обрабатываться:

```
✅ example.com
✅ sub.example.com
✅ sub.sub.example.com
❌ anotherexample.com
❌ example.net
```

### Wildcard (Подстановочный шаблон)

Шаблон с `*` и `?` — позволяет задавать гибкие условия:

- `*` — любое количество любых символов
- `?` — ровно один любой символ

Например, при записи `*example.com` будут обрабатываться:

```
✅ example.com
✅ sub.example.com
✅ sub.sub.example.com
✅ anotherexample.com
❌ example.net
```

### Domain (Точный домен)

Правило применяется только к строго указанному домену, без поддоменов.

Например, при записи `sub.example.com` будут обрабатываться:

```
❌ example.com
✅ sub.example.com
❌ sub.sub.example.com
❌ anotherexample.com
❌ example.net
```

### RegExp (Регулярное выражение)

Для опытных пользователей. Используется парсер [dlclark/regexp2](https://github.com/dlclark/regexp2).

Например, при записи `^[a-z]*example\.com$` будут обрабатываться:

```
✅ example.com
❌ sub.example.com
❌ sub.sub.example.com
✅ anotherexample.com
❌ example.net
```

## Поддержка

- [Официальный сайт](https://magitrickle.dev)
- [Форум на Keenetic Community](https://forum.keenetic.ru/topic/20125-magitrickle)
- [Канал Telegram](https://t.me/MagiTrickle)
- [Чат Telegram](https://t.me/MagiTrickleChat)
- [Финансовая поддержка](https://boosty.to/magitrickle)

## Лицензия

[GPL-3.0](LICENSE)
