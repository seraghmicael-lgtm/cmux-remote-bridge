#!/bin/bash
# cmux 원격(아이폰) 자동 복구 워치독. launchd io.dk.cmux-watchdog가
# --loop 로 띄우고, 스스로 60초마다 한 바퀴 돈다.
#   소켓만 죽음  → repair_socket: 앱 재시작 없이 재바인드 (워크스페이스 보존)
#   그래도 안 되면 → restart_cmux: 앱 재시작, 5분 쿨다운으로 루프 방지
#   브리지만 죽음 → launchd로 재기동
# 점검:  --status (지금 어디가 죽었나)  --selftest / watchdog-sim.sh (회귀 검증)
export PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
CMUX=/Applications/cmux.app/Contents/Resources/bin/cmux
BRIDGE="$HOME/.config/cmux-remote/CmuxBridge"
# 로그·상태는 /tmp 밖에 둔다: /tmp는 오래된 파일을 자동 삭제해서
# "장애가 있었는데 기록이 없다" 상태를 만든다 (2026-07-26 사고 때 실제로 겪음).
LOG="$HOME/.config/cmux-remote/watchdog.log"
STATE="$HOME/.config/cmux-remote/watchdog.last-restart"
BEAT="$HOME/.config/cmux-remote/watchdog.heartbeat"
log() { echo "$(date '+%F %T') $*" >> "$LOG"; }

# 소켓 비밀번호: cmux가 password 모드일 때 필수 (없으면 auth_required를
# 죽음으로 오판해 재시작 루프에 빠진다)
export CMUX_SOCKET_PASSWORD="$(cat "$HOME/.config/cmux-remote/socket-password" 2>/dev/null)"
socket_ok()  { "$CMUX" workspace list >/dev/null 2>&1; }

# ── 자동 업데이트 ────────────────────────────────────────────────────────────
# 브리지는 App Store 를 타지 않아 예전엔 사용자가 install.sh 를 다시 실행해야만
# 갱신됐다. 보안 수정이 나가도 아무도 안 받는 상태가 되므로 여기서 스스로 받는다.
#
# 지켜야 할 것:
#  - 하루 한 번만 확인한다(워치독은 60초마다 도는데 매번 네트워크를 때릴 이유가 없다).
#  - 받은 파일이 **실행 가능한 Mach-O 인지 검증**하고 나서 교체한다. HTML 에러 페이지나
#    잘린 파일을 그대로 덮으면 브리지가 영영 안 뜬다(교체는 되돌리기 어렵다).
#  - 교체 전 현재 바이너리를 백업하고, 새 것이 /ping 에 응답하지 않으면 되돌린다.
UPDATE_URL="https://raw.githubusercontent.com/seraghmicael-lgtm/cmux-remote-bridge/main"
UPDATE_STAMP="$HOME/.config/cmux-remote/last-update-check"
AUTO_UPDATE="${CMUX_AUTO_UPDATE:-1}"    # CMUX_AUTO_UPDATE=0 으로 끌 수 있다

check_update() {
  [ "$AUTO_UPDATE" = "1" ] || return 0
  # 하루 한 번
  if [ -f "$UPDATE_STAMP" ]; then
    local age=$(( $(date +%s) - $(stat -f %m "$UPDATE_STAMP" 2>/dev/null || echo 0) ))
    [ "$age" -lt 86400 ] && return 0
  fi
  touch "$UPDATE_STAMP"

  local remote local_v tmp
  remote=$(curl -fsSL -m 15 "$UPDATE_URL/VERSION" 2>/dev/null | tr -d '[:space:]')
  [ -n "$remote" ] || return 0
  local_v=$(curl -fsS -m 5 "http://127.0.0.1:9393/version" \
            -H "Authorization: Bearer $(cat "$HOME/.config/cmux-remote/token" 2>/dev/null)" \
            2>/dev/null | tr -d '[:space:]')
  # /version 이 없는 구버전이면 local_v 가 비고, 그때는 무조건 갱신 대상이다.
  [ "$remote" = "$local_v" ] && return 0
  log "업데이트 발견: ${local_v:-unknown} → $remote"

  tmp=$(mktemp "${TMPDIR:-/tmp}/CmuxBridge.XXXXXX") || return 0
  if ! curl -fsSL -m 120 "$UPDATE_URL/CmuxBridge" -o "$tmp"; then
    log "업데이트 다운로드 실패"; rm -f "$tmp"; return 0
  fi
  # 받은 게 진짜 실행 파일인가 — HTML 오류 페이지·잘린 파일을 거른다.
  if ! file -b "$tmp" | grep -q "Mach-O"; then
    log "업데이트 거부: Mach-O 가 아님 ($(file -b "$tmp" | head -c 60))"; rm -f "$tmp"; return 0
  fi
  if [ "$(stat -f %z "$tmp")" -lt 100000 ]; then
    log "업데이트 거부: 파일이 너무 작음"; rm -f "$tmp"; return 0
  fi
  chmod +x "$tmp"

  cp "$BRIDGE" "$BRIDGE.prev" 2>/dev/null
  mv "$tmp" "$BRIDGE" || { log "업데이트 교체 실패"; return 0; }
  launchctl kickstart -k "gui/$(id -u)/io.dk.cmux-bridge" >/dev/null 2>&1
  # 새 바이너리가 실제로 서비스되는지 확인하고, 아니면 되돌린다.
  local ok=0
  for _ in $(seq 1 20); do sleep 1; bridge_ok && { ok=1; break; }; done
  if [ "$ok" = "1" ]; then
    log "업데이트 완료 → $remote"
    rm -f "$BRIDGE.prev"
  else
    log "새 브리지가 응답하지 않음 → 이전 버전으로 롤백"
    [ -f "$BRIDGE.prev" ] && mv "$BRIDGE.prev" "$BRIDGE"
    launchctl kickstart -k "gui/$(id -u)/io.dk.cmux-bridge" >/dev/null 2>&1
  fi
}
# pgrep/ps가 이 GUI 앱을 못 보는 경우가 있다 (2026-07-26 확인: ps -A·pgrep 목록에는
# 없는데 ps -p <pid>로는 살아있음). 오판하면 main에서 복구 루틴을 통째로 건너뛰고
# 'cmux 미실행' 경로로 새므로, launchd에 등록된 앱 서비스를 1차 기준으로 삼는다.
app_running(){ launchctl list 2>/dev/null | grep -q "application.com.cmuxterm.app" \
               || pgrep -f "cmux.app/Contents/MacOS/cmux" >/dev/null 2>&1; }
# 'LISTEN이나 accept 못 하는 좀비'(utun 바인딩 장애 등)를 lsof만으론 못 거른다
# — 실제로 /ping이 200을 주는지 확인한다. 200이면 accept·파싱·서빙 전 구간 정상.
# 브리지는 전 인터페이스(*:9393)에 바인딩하므로 루프백으로 검증한다(자기 tailscale
# IP로 치면 헤어핀 SYN_RCVD로 걸림). 연결거부/타임아웃/무응답은 전부 '죽음'으로 본다.
bridge_ok()  {
  local code
  code=$(curl -s -o /dev/null -m 4 -w '%{http_code}' \
    -H "Authorization: Bearer $(cat "$HOME/.config/cmux-remote/token" 2>/dev/null)" \
    "http://127.0.0.1:9393/ping" 2>/dev/null)
  [ "$code" = "200" ]
}
# 포트를 쥐고 있는지(LISTEN)만 보는 저수준 체크 — 좀비 감지·정리 판단에만 쓴다.
bridge_listening() { lsof -iTCP:9393 -sTCP:LISTEN >/dev/null 2>&1; }

ensure_bridge() {
  bridge_ok && return 0
  socket_ok || return 1
  # 여기 도달 = 브리지가 죽었거나 'LISTEN이나 /ping 무응답' 좀비. 좀비가 9393을 쥔 채로
  # 그냥 kickstart하면 새 인스턴스가 EADDRINUSE로 죽는다(원래 장애 재현 경로). 그래서
  # 포트를 쥔 프로세스를 먼저 정리한 뒤 재기동한다.
  if bridge_listening; then
    log "브리지 무응답(좀비 LISTEN) — 포트 점유 프로세스 정리"
    pkill -f "cmux-remote/CmuxBridge" 2>/dev/null; sleep 2
    pkill -9 -f "cmux-remote/CmuxBridge" 2>/dev/null; sleep 1
  fi
  log "브리지 재기동"
  # 브리지는 launchd(io.dk.cmux-bridge)가 소유한다. 워크스페이스에서 또 띄우면
  # 같은 9393 포트를 두 프로세스가 다투게 되므로 launchd 쪽을 먼저 쓴다.
  if launchctl print "gui/$(id -u)/io.dk.cmux-bridge" >/dev/null 2>&1; then
    launchctl kickstart -k "gui/$(id -u)/io.dk.cmux-bridge" >/dev/null 2>&1
    # launchd(KeepAlive)가 담당하는 게 확실하면 워크스페이스 폴백은 하지 않는다 —
    # 폴백 스폰은 launchd 인스턴스와 9393을 다투다 EADDRINUSE로 죽고 빈 cmux-bridge
    # 워크스페이스만 남긴다(이중 스폰 사고 원인). 넉넉히 기다렸다 판정하고, 실패해도
    # launchd가 알아서 재시도하므로 다음 60s 사이클에 맡긴다.
    for _ in $(seq 1 15); do sleep 1; bridge_ok && { log "브리지 복구됨(launchd)"; return 0; }; done
    log "브리지 복구 실패(launchd) — 다음 사이클 재시도"
    return 1
  fi
  # launchd 서비스가 아예 없을 때만 워크스페이스로 직접 띄운다.
  WS=$("$CMUX" workspace list 2>/dev/null | grep cmux-bridge | grep -oE "workspace:[0-9]+" | head -1)
  if [ -n "$WS" ]; then
    "$CMUX" send --workspace "$WS" "~/.config/cmux-remote/CmuxBridge 2>&1 | tee \"$BRIDGE_LOG\"" >/dev/null 2>&1
    "$CMUX" send-key --workspace "$WS" enter >/dev/null 2>&1
  else
    "$CMUX" new-workspace --name cmux-bridge --focus false \
      --command "~/.config/cmux-remote/CmuxBridge 2>&1 | tee \"$BRIDGE_LOG\"" >/dev/null 2>&1
  fi
  sleep 3
  bridge_ok && log "브리지 복구됨" || log "브리지 복구 실패"
}

# 앱은 살아있는데 자동화 소켓만 죽은 경우의 가벼운 복구.
# 원인: 낡은 소켓 파일이 남아있으면 앱이 재시작할 때 그걸 unlink 하고
# 다시 bind 해야 하는데, 파일에 'everyone deny delete' ACL이 붙어 있으면
# unlink가 실패하고 앱은 조용히 소켓 없이 뜬다. 그 ACL은 iCloud 등
# 클라우드에 폴더를 왕복시키면 붙는다. (2026-07-26 실제 장애 원인)
# 앱을 재시작하지 않으므로 워크스페이스가 죽지 않는다 — 항상 이걸 먼저 시도.
CFG="$HOME/.config/cmux/cmux.json"
SOCKDIR="$HOME/.local/state/cmux"

# 브리지 로그는 요청마다 몇 줄씩 쌓여 하루에도 수십만 줄이 된다.
# 파일을 rename 하면 launchd가 쥔 fd가 옛 inode를 계속 가리켜 새 로그가
# 사라지므로, 최근 분량만 남기고 '제자리 절단'한다 — 브리지를 안 끊는다.
BRIDGE_LOG="$HOME/.config/cmux-remote/bridge.log"
BRIDGE_LOG_MAX=$((20 * 1024 * 1024))
BRIDGE_LOG_KEEP=3000
rotate_bridge_log() {
  [ -f "$BRIDGE_LOG" ] || return 0
  sz=$(stat -f%z "$BRIDGE_LOG" 2>/dev/null || echo 0)
  [ "$sz" -gt "$BRIDGE_LOG_MAX" ] || return 0
  keep=$(tail -n "$BRIDGE_LOG_KEEP" "$BRIDGE_LOG")
  printf '%s\n' "$keep" > "$BRIDGE_LOG"
  log "브리지 로그 절단: ${sz}바이트 → 최근 ${BRIDGE_LOG_KEEP}줄"
}
repair_socket() {
  [ -f "$CFG" ] || return 1
  mode=$(sed -n 's/.*"socketControlMode"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$CFG" | head -1)
  [ -n "$mode" ] && [ "$mode" != "off" ] || return 1
  log "소켓 재바인드 시도 (ACL 제거 + 낡은 소켓 삭제 + 설정 토글)"
  chmod -N "$SOCKDIR" "$SOCKDIR"/*.sock "$SOCKDIR"/*.sock.lock 2>/dev/null
  rm -f "$SOCKDIR"/*.sock "$SOCKDIR"/*.sock.lock
  cp "$CFG" "$CFG.watchdog.bak"
  toggle_mode "off" || { cp "$CFG.watchdog.bak" "$CFG"; return 1; }
  sleep 3
  toggle_mode "$mode" || { cp "$CFG.watchdog.bak" "$CFG"; return 1; }
  for _ in $(seq 1 8); do sleep 1; socket_ok && { log "소켓 재바인드 성공"; return 0; }; done
  log "소켓 재바인드 실패"
  return 1
}

# cmux.json의 socketControlMode 값만 교체. 앱이 설정 변경을 감지해 소켓을 다시 만든다.
toggle_mode() {
  sed -i '' "s/\"socketControlMode\"[[:space:]]*:[[:space:]]*\"[^\"]*\"/\"socketControlMode\" : \"$1\"/" "$CFG" || return 1
  grep -q "\"socketControlMode\"[[:space:]]*:[[:space:]]*\"$1\"" "$CFG"
}

# 실서비스를 안 건드리는 자체 점검: 설정 토글이 왕복하고 JSON이 안 깨지는지.
# 실행:  bash ~/.config/cmux-remote/watchdog.sh --selftest
selftest() {
  real="$CFG"; tmp=$(mktemp -d); CFG="$tmp/cmux.json"
  printf '{\n  "$schema" : "x",\n  "automation" : {\n    "socketControlMode" : "password"\n  }\n}\n' > "$CFG"
  before=$(cat "$CFG")
  toggle_mode off       || { echo "FAIL: off 전환 실패"; return 1; }
  python3 -c "import json,sys;json.load(open('$CFG'))" || { echo "FAIL: off 후 JSON 깨짐"; return 1; }
  grep -q '"socketControlMode" : "off"' "$CFG" || { echo "FAIL: off 값 미반영"; return 1; }
  toggle_mode password  || { echo "FAIL: 복원 실패"; return 1; }
  [ "$(cat "$CFG")" = "$before" ] || { echo "FAIL: 왕복 후 원본과 불일치"; diff <(echo "$before") "$CFG"; return 1; }
  # 값이 없는 설정이면 repair_socket이 손대지 않고 빠져야 한다
  echo '{"automation":{}}' > "$CFG"
  repair_socket && { echo "FAIL: 모드 없는 설정인데 복구를 시도함"; return 1; }
  rm -rf "$tmp"; CFG="$real"
  echo "OK: 설정 토글 왕복·JSON 무결성·무설정 방어 통과"
}

restart_cmux() {
  now=$(date +%s); last=$(cat "$STATE" 2>/dev/null || echo 0)
  [ $((now - last)) -lt 300 ] && { log "쿨다운 중 — 재시작 생략"; return 1; }
  echo "$now" > "$STATE"
  log "cmux 재시작 (자동화 소켓 무응답)"
  osascript -e 'tell application "cmux" to quit' >/dev/null 2>&1
  for _ in $(seq 1 20); do app_running || break; sleep 1; done
  if app_running; then log "우아한 종료 실패 → 강제 종료"; pkill -f "cmux.app/Contents/MacOS/cmux"; sleep 3; fi
  open -a cmux
  for _ in $(seq 1 30); do sleep 2; socket_ok && { log "소켓 복구됨"; return 0; }; done
  log "소켓 복구 실패"
  return 1
}

# 장애 시뮬레이터(watchdog-sim.sh)가 함수만 가져다 쓰기 위한 진입점.
# source 될 때만 평가되므로 실서비스 실행 경로에는 영향이 없다.
[ -n "$WATCHDOG_LIB" ] && return 0

# ── main ──
[ "$1" = "--selftest" ] && { selftest; exit $?; }

# 아이폰이 안 붙을 때 제일 먼저 칠 명령. 어느 층이 죽었는지 한눈에 보여준다.
if [ "$1" = "--status" ]; then
  socket_ok  && echo "cmux 소켓    정상" || echo "cmux 소켓    ✗ 죽음"
  if bridge_ok; then echo "브리지 9393  정상(응답)"
  elif bridge_listening; then echo "브리지 9393  ✗ 좀비(LISTEN이나 /ping 무응답)"
  else echo "브리지 9393  ✗ 안 열림"; fi
  app_running && echo "cmux 앱      실행중" || echo "cmux 앱      ✗ 미실행"
  if [ -f "$BEAT" ]; then
    age=$(( $(date +%s) - $(date -j -f '%F %T' "$(cat "$BEAT")" +%s 2>/dev/null || echo 0) ))
    [ "$age" -lt 180 ] && echo "워치독       살아있음 (${age}초 전)" \
                       || echo "워치독       ✗ ${age}초째 멈춤 — launchctl kickstart gui/$(id -u)/io.dk.cmux-watchdog"
  else
    echo "워치독       ✗ 한 번도 안 돎"
  fi
  # 로그가 수십만 줄이라 전체 집계는 하지 않는다 — 연결 여부와 마지막 응답만
  n=$(netstat -an 2>/dev/null | grep -c "\.9393 .*ESTABLISHED")
  echo "아이폰       연결 ${n}개 / 최근 응답: $(tail -200 "$BRIDGE_LOG" 2>/dev/null | grep '^res:' | tail -1)"
  echo "브리지 로그  $(du -h "$BRIDGE_LOG" 2>/dev/null | cut -f1) ($BRIDGE_LOG)"
  [ -s "$LOG" ] && { echo "--- 최근 사고 기록 ---"; tail -5 "$LOG"; }
  exit 0
fi

# launchd의 StartInterval이 이 맥에서 발화하지 않는다 (2026-07-26 확인:
# runs=0인 채 5분 경과, RunAtLoad조차 안 뜸). 그래서 브리지와 같은
# KeepAlive + 자체 루프 방식으로 돈다 — 그쪽은 멀쩡히 살아있는 게 검증됨.
[ "$1" = "--loop" ] && { while :; do bash "$0"; sleep 60; done; }

date '+%F %T' > "$BEAT"   # 매 실행 갱신 — 워치독 자체가 도는지 확인용
rotate_bridge_log

if socket_ok; then
  ensure_bridge
  check_update   # 정상일 때만 갱신 — 장애 복구 중에 바이너리를 바꾸면 원인이 뒤엉킨다
  exit 0
fi
# 일시적 오류 배제: 5초 후 재확인
sleep 5
socket_ok && { ensure_bridge; exit 0; }

if app_running; then
  # 가벼운 복구부터 — 성공하면 앱 재시작(=워크스페이스 손실) 없이 끝난다
  repair_socket && { ensure_bridge; exit 0; }
  restart_cmux && { sleep 3; ensure_bridge; }
else
  log "cmux 미실행 → 실행"
  open -a cmux
  for _ in $(seq 1 30); do sleep 2; socket_ok && break; done
  ensure_bridge
fi
