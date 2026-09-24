#!/bin/sh
# MagiTrickle: установщик и обновлятор для OpenWrt и Keenetic (Entware).
# Репозиторий: https://github.com/phenomenonRT/magitrickle
#
# Установить или обновить до последнего релиза одной командой:
#   wget -qO- https://raw.githubusercontent.com/phenomenonRT/magitrickle/main/install.sh | sh
#   curl -fsSL https://raw.githubusercontent.com/phenomenonRT/magitrickle/main/install.sh | sh
#
# Параметры передаются после "sh -s --", например:
#   wget -qO- https://raw.githubusercontent.com/phenomenonRT/magitrickle/main/install.sh | sh -s -- -c
# Подробности: README.md. Только POSIX sh (busybox ash), bash не нужен.

set -u
REPO="${REPO:-phenomenonRT/magitrickle}"
PKG="magitrickle"

say()  { printf '%s\n' "$*"; }
warn() { printf '! %s\n' "$*" >&2; }
die()  { printf 'ОШИБКА: %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
MagiTrickle: установка / обновление до последнего релиза с GitHub.

Параметры:
  -c, --check      только показать установленную и доступную версии
  -f, --force      переустановить, даже если версия уже последняя
  -l, --list       показать все файлы релиза и выбранный для этого роутера
  -u, --url URL    установить пакет (.ipk или .apk) по прямой https-ссылке
  -h, --help       эта справка

Переменные окружения (необязательно):
  REPO=owner/repo        откуда брать релизы (по умолчанию phenomenonRT/magitrickle)
  ARCH=...               задать архитектуру вручную
  KN=1|0                 Entware: сборка для Keenetic (_kn) или обычная (по умолчанию определяется сама)
  ALLOW_UNTRUSTED=1      OpenWrt apk: ставить пакет без проверки подписи
EOF
}

main() {
  CHECK=0; FORCE=0; LIST=0; URL_ARG=""
  while [ $# -gt 0 ]; do
    case "$1" in
      -c|--check) CHECK=1 ;;
      -f|--force) FORCE=1 ;;
      -l|--list)  LIST=1 ;;
      -u|--url)   [ $# -ge 2 ] || die "после $1 нужна ссылка на пакет"; URL_ARG="$2"; shift ;;
      -h|--help)  usage; exit 0 ;;
      *) die "неизвестный параметр: $1 (справка: -h)" ;;
    esac
    shift
  done

  PATH="/opt/sbin:/opt/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"
  [ "$(id -u)" = 0 ] || die "запускайте от root"

  # ---------- платформа ----------
  ARCHES=""; KN="${KN:-}"
  if [ -f /etc/openwrt_release ]; then
    PLATFORM=openwrt
    if command -v apk >/dev/null 2>&1; then PM=apk; EXT=apk; else PM=opkg; EXT=ipk; fi
    # shellcheck disable=SC1091
    . /etc/openwrt_release
    ARCHES="${ARCH:-${DISTRIB_ARCH:-}}"
    if [ -z "$ARCHES" ]; then
      if [ "$PM" = apk ]; then ARCHES=$(apk --print-arch 2>/dev/null)
      else ARCHES=$(opkg print-architecture | awk '$1=="arch" && $2!="all" && $2!="noarch" {print $2}'); fi
    fi
  elif command -v opkg >/dev/null 2>&1 && [ -d /opt/etc/init.d ]; then
    PLATFORM=entware; PM=opkg; EXT=ipk
    ARCHES="${ARCH:-$(opkg print-architecture | awk '$1=="arch" && $2!="all" && $2!="noarch" {print $2}')}"
    if [ -z "$KN" ] || [ "$KN" = auto ]; then
      if [ -e /bin/ndmc ] || command -v ndmc >/dev/null 2>&1; then KN=1; else KN=0; fi
    fi
    [ -d /opt/tmp ] && export TMPDIR=/opt/tmp
  else
    die "не похоже ни на OpenWrt, ни на Entware. Для Keenetic зайдите по SSH в Entware (порт 222), а не в основную оболочку роутера."
  fi
  [ -n "$ARCHES" ] || die "не удалось определить архитектуру, задайте ARCH=..."
  say "Платформа: $PLATFORM ($PM), архитектура: $(printf '%s' "$ARCHES" | tr '\n' ' ')${KN:+, Keenetic-сборка: $KN}"

  # ---------- загрузчик ----------
  if command -v curl >/dev/null 2>&1; then
    http_get()  { curl -fsSL --connect-timeout 15 --retry 2 "$1"; }
    http_save() { curl -fSL -# --connect-timeout 15 --retry 2 -o "$2" "$1"; }
  elif command -v wget >/dev/null 2>&1; then
    http_get()  { wget -qO- "$1"; }
    http_save() { wget -qO "$2" "$1"; }
  else
    die "нужен curl или wget с поддержкой HTTPS (и ca-bundle / ca-certificates), см. README"
  fi

  W=$(mktemp -d 2>/dev/null) || { W="/tmp/mgt.$$"; mkdir -p "$W"; }
  trap 'rm -rf "$W"' EXIT INT TERM

  # ---------- какой файл ставить ----------
  if [ -n "$URL_ARG" ]; then
    # пакет по прямой ссылке
    case "$URL_ARG" in https://*) ;; *) die "ссылка должна начинаться с https://" ;; esac
    ASSET="${URL_ARG##*/}"; ASSET="${ASSET%%\?*}"
    case "$ASSET" in
      *."$EXT") ;;
      *) die "в этой системе ($PM) нужен файл .$EXT, а ссылка ведёт на '$ASSET'" ;;
    esac
    DL_URL="$URL_ARG"
    say "Пакет по ссылке: $ASSET"
  else
    # последний релиз: тег и список файлов
    NAMES="$W/names"; TAG=""
    if http_get "https://api.github.com/repos/$REPO/releases/latest" >"$W/rel.json" 2>/dev/null; then
      tr ',' '\n' <"$W/rel.json" | sed -n 's#.*"browser_download_url" *: *"[^"]*/\([^"/]*\)".*#\1#p' >"$NAMES"
      TAG=$(tr ',' '\n' <"$W/rel.json" | sed -n 's#.*"tag_name" *: *"\([^"]*\)".*#\1#p' | head -n1)
    fi
    if [ -z "$TAG" ] || [ ! -s "$NAMES" ]; then
      # API недоступен (например, лимит 60 запросов/час с одного IP): читаем страницу релиза
      warn "GitHub API не ответил, читаю страницу релиза"
      TAG=$(http_get "https://github.com/$REPO/releases/latest" 2>/dev/null \
            | sed -n 's#.*releases/expanded_assets/\([^"]*\)".*#\1#p' | head -n1)
      [ -n "$TAG" ] || die "не удалось получить последний релиз $REPO (нет доступа к github.com? проверьте DNS и HTTPS)"
      http_get "https://github.com/$REPO/releases/expanded_assets/$TAG" \
        | sed -n 's#.*href="[^"]*/releases/download/[^"/]*/\([^"]*\)".*#\1#p' >"$NAMES"
    fi
    [ -s "$NAMES" ] || die "в релизе $TAG нет файлов"
    say "Последний релиз: $TAG ($REPO)"

    pick() { grep -F -e "$1" "$NAMES" | head -n1; }
    ASSET=""
    if [ "$PLATFORM" = openwrt ]; then
      for a in $ARCHES; do
        ASSET=$(pick "_openwrt_${a}.${EXT}")
        [ -n "$ASSET" ] && break
      done
    else
      for a in $ARCHES; do
        # у Entware armv7sf-k3.2 в релизах называется armv7-3.2
        a2=$(printf '%s' "$a" | sed 's/sf-k/-/; s/sf-/-/')
        for x in "$a" "$a2"; do
          [ "$KN" = 1 ] && ASSET=$(pick "_entware_${x}_kn.ipk")
          [ -z "$ASSET" ] && ASSET=$(pick "_entware_${x}.ipk")
          [ -n "$ASSET" ] && break 2
        done
      done
    fi
    if [ "$LIST" = 1 ]; then
      say "--- файлы релиза ---"; sort "$NAMES"; say "--------------------"
    fi
    [ -n "$ASSET" ] || die "в релизе $TAG нет сборки под '$(printf '%s' "$ARCHES" | tr '\n' ' ')'. Список файлов покажет параметр -l"
    DL_URL="https://github.com/$REPO/releases/download/$TAG/$ASSET"
  fi

  NEW="${ASSET#${PKG}_}"; NEW="${NEW%%_openwrt_*}"; NEW="${NEW%%_entware_*}"

  installed_ver() {
    if [ "$PM" = apk ]; then
      apk list -I "$PKG" 2>/dev/null | awk -v p="$PKG" '$1 ~ "^" p "-[0-9]" {sub("^" p "-", "", $1); print $1; exit}'
    else
      opkg list-installed "$PKG" 2>/dev/null | awk -v p="$PKG" '$1==p {print $3; exit}'
    fi
  }
  OLD=$(installed_ver)

  say "Установлено: ${OLD:-нет}"
  say "Доступно:    $NEW"
  say "Файл:        $ASSET"

  [ "$CHECK" = 1 ] && exit 0
  if [ -n "$OLD" ] && [ "$OLD" = "$NEW" ] && [ "$FORCE" = 0 ]; then
    say "Уже установлена эта версия. (-f, чтобы переустановить)"
    exit 0
  fi

  # ---------- скачиваем и ставим ----------
  FILE="$W/$ASSET"
  say "Скачиваю..."
  http_save "$DL_URL" "$FILE" || die "не удалось скачать $DL_URL"
  [ -s "$FILE" ] || die "скачанный файл пустой"

  say "Обновляю индекс пакетов (нужен для зависимостей)..."
  if [ "$PM" = apk ]; then apk update || warn "apk update не удался, продолжаю"
  else opkg update || warn "opkg update не удался, продолжаю"; fi

  say "Ставлю..."
  if [ "$PM" = apk ]; then
    if [ "${ALLOW_UNTRUSTED:-0}" = 1 ]; then apk add --allow-untrusted "$FILE"; else apk add "$FILE"; fi
    RC=$?
    [ "$RC" = 0 ] || warn "Если ошибка про подпись (UNTRUSTED signature), запустите с ALLOW_UNTRUSTED=1, но только если доверяете источнику."
  else
    if [ "$FORCE" = 1 ]; then opkg install --force-reinstall "$FILE"; else opkg install "$FILE"; fi
    RC=$?
  fi
  [ "$RC" = 0 ] || die "установка не удалась (код $RC)"

  # ---------- перезапуск сервиса ----------
  if [ "$PLATFORM" = entware ]; then
    INIT=/opt/etc/init.d/S99magitrickle
    if [ -x "$INIT" ]; then "$INIT" restart; else warn "не найден $INIT, запустите сервис вручную"; fi
  else
    INIT=/etc/init.d/magitrickle
    if [ -x "$INIT" ]; then
      [ -z "$OLD" ] && "$INIT" enable
      "$INIT" restart
    else
      warn "не найден $INIT, запустите сервис вручную"
    fi
  fi

  say "Готово. Установлено: $(installed_ver)"
}

# Всё тело обёрнуто в функцию: при обрыве загрузки через "| sh" ничего не выполнится.
main "$@" </dev/null
