#!/usr/bin/env bash
set -euo pipefail

# -------- CONFIG --------
DIRS=( "$HOME/Pictures/DigitalArt" )   # можно несколько папок

IDLE_LIMIT_MS=$((5*60*1000))            # порог простоя (мс);
DURATION=30                             # сек на кадр
ORDER="shuffle"                         # "shuffle" или "natural"
TITLE="Idle Slideshow"                  # заголовок окна imv
SCALING=crop                            # full | crop | shrink | none
ALWAYS_ON_TOP=1                         # включить "над всеми"

# NEW: раздельные интервалы опроса
CHECK_EVERY_IDLE=0.5                    # когда ждём простоя (сек)
CHECK_EVERY_ACTIVE=0.08                 # когда слайд-шоу запущено (сек)
ACTIVE_EDGE_MS=500                      # считаем пользователя активным, если idle < 500 мс

EXTS="jpg|jpeg|png|webp|gif|bmp|tif|tiff|avif"
PIDFILE="${XDG_RUNTIME_DIR:-/tmp}/slideshow-imv.pid"
# ------------------------

log(){ printf '[slideshow] %s\n' "$*"; }

choose_viewer() {
  local sess="${XDG_SESSION_TYPE:-}"
  local cands=()
  # Для "always-on-top" на Wayland предпочитаем X11-сборку (управляется wmctrl):
  if [[ "$ALWAYS_ON_TOP" -eq 1 && "$sess" == "wayland" ]]; then
    cands+=(imv-x11 /usr/libexec/imv/imv-x11)
  else
    [[ "$sess" == "wayland" ]] && cands+=(imv-wayland /usr/libexec/imv/imv-wayland)
    [[ "$sess" == "x11" || -z "$sess" ]] && cands+=(imv-x11 /usr/libexec/imv/imv-x11)
  fi
  cands+=(imv /usr/libexec/imv/imv)
  for c in "${cands[@]}"; do
    command -v "$c" >/dev/null 2>&1 && { echo "$c"; return; }
    [[ -x "$c" ]] && { echo "$c"; return; }
  done
  return 1
}

VIEWER="$(choose_viewer)" || { log "imv(-wayland/-x11) не найден."; exit 1; }

mark_above() {
  # Работает для X11/XWayland-окон
  command -v wmctrl >/dev/null 2>&1 || return 0
  for _ in $(seq 1 40); do
    if wmctrl -l | grep -F "$TITLE" >/dev/null; then
      wmctrl -r "$TITLE" -b add,above
      wmctrl -r "$TITLE" -b add,fullscreen   # дублируем фуллскрин EWMH'ом
      wmctrl -a "$TITLE" || true             # подсветить/поднять
      return 0
    fi
    sleep 0.1
  done
}

start_show() {
  local regex='.*\.('"$EXTS"')$'

  if [[ "${ORDER:-shuffle}" == "shuffle" ]]; then
    mapfile -d '' -t FILES < <(
      find "${DIRS[@]}" -regextype posix-extended -type f -iregex "$regex" -print0 | shuf -z
    )
  else
    mapfile -d '' -t FILES < <(
      find "${DIRS[@]}" -regextype posix-extended -type f -iregex "$regex" -print0
    )
  fi

  if (( ${#FILES[@]} == 0 )); then
    log "Нет подходящих изображений в ${DIRS[*]}"
    return 0
  fi

  # Стартуем БЕЗ -f; fullscreen/always-on-top делаем через wmctrl (EWMH)
  setsid "$VIEWER" -t "$DURATION" -s "$SCALING" -w "$TITLE" "${FILES[@]}" >/dev/null 2>&1 &
  echo $! > "$PIDFILE"
  log "Started $VIEWER (pid $(cat "$PIDFILE")), files: ${#FILES[@]}"
  mark_above || true
}

stop_show() {
  [[ -f "$PIDFILE" ]] || return 0
  local pid; pid="$(cat "$PIDFILE" 2>/dev/null || true)"
  if [[ -n "${pid:-}" ]]; then
    local pgid; pgid="$(ps -o pgid= -p "$pid" | tr -d ' ')"
    kill -TERM -- -"${pgid}" 2>/dev/null || kill -TERM "$pid" 2>/dev/null || true
  fi
  rm -f "$PIDFILE"
  log "Stopped slideshow."
}

get_idle_ms() {
  # Официальный метод Mutter: org.gnome.Mutter.IdleMonitor.GetIdletime (uint64 мс)
  dbus-send --print-reply --dest=org.gnome.Mutter.IdleMonitor \
    /org/gnome/Mutter/IdleMonitor/Core org.gnome.Mutter.IdleMonitor.GetIdletime \
    2>/dev/null | awk '/uint64/ {print $2}'
}

trap 'stop_show; exit 0' INT TERM

running=0
while :; do
  idle_ms="$(get_idle_ms)"; idle_ms="${idle_ms:-0}"

  if (( running == 0 )); then
    # ждём простоя → опрашиваем реже
    if (( idle_ms >= IDLE_LIMIT_MS )); then
      start_show
      running=1
      # маленькая задержка, чтобы wmctrl успел навесить флаги
      sleep 0.05
    else
      sleep "$CHECK_EVERY_IDLE"
    fi
  else
    # слайд-шоу идёт → опрашиваем чаще и закрываем мгновенно при активности
    if (( idle_ms < ACTIVE_EDGE_MS )); then
      stop_show
      running=0
      # короткий анти-дребезг
      sleep 0.05
    else
      sleep "$CHECK_EVERY_ACTIVE"
    fi
  fi
done
