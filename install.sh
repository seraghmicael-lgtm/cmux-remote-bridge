#!/bin/bash
# cmux-remote 브리지 원라인 설치:
#   curl -fsSL https://raw.githubusercontent.com/seraghmicael-lgtm/cmux-remote-bridge/main/install.sh | bash
# 끝나면 iPhone용 자동 설정 링크(cmuxremote://…)를 클립보드에 복사합니다.
set -u

# 본문 전체를 함수로 감싼다 — curl | bash 는 스크립트를 스트리밍하므로, 중간에 네트워크가
# 끊기면 받은 데까지만 실행된다. 함수는 닫는 괄호까지 다 받아야 실행되므로 반쪽 실행이 없다.
main() {
RAW="https://raw.githubusercontent.com/seraghmicael-lgtm/cmux-remote-bridge/main"

say()  { printf '%s\n' "$*"; }
ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; }
STEP=0; STEPS=7
step() { STEP=$((STEP+1)); printf '\n\033[1m[%d/%d] %s\033[0m\n' "$STEP" "$STEPS" "$*"; }
NFAIL=0; FAILTXT=""
err()  { printf '  \033[31m✗\033[0m %s\n' "$*"; NFAIL=$((NFAIL+1)); FAILTXT="$FAILTXT     · $*"$'\n'; }
err_soft() { printf '  \033[33m!\033[0m %s\n' "$*"; }   # 재시도 중인 안내 — 실패 집계엔 안 넣는다
b()    { printf '\033[1m%s\033[0m\n' "$*"; }        # 굵게

clear 2>/dev/null || true
say ""
b   "  ┌─────────────────────────────────────────┐"
b   "  │   cmux 원격 연결 — 아이폰에서 내 Mac 쓰기   │"
b   "  └─────────────────────────────────────────┘"
say ""
say "  이 창은 딱 한 번만 실행하면 됩니다. 아래를 자동으로 준비해요:"
say "    • 아이폰과 Mac을 안전하게 잇는 Tailscale (없으면 설치·로그인 안내)"
say "    • Mac 화면을 아이폰에 보여주는 연결 프로그램"
say "    • 뚜껑 닫아도 계속 켜두는 상시전원 설정"
say ""
b   "  진행 중 두 가지만 눌러주시면 됩니다:"
say "    ① Tailscale 로그인 (아이폰과 '같은 계정' — 반드시 동일해야 서로 보여요)"
say "    ② 상시전원용 관리자 암호 (Mac 로그인 암호, 한 번만)"
say ""
say "  다 끝나면 아이폰 cmux 앱만 열면 자동으로 연결됩니다. 시작할게요…"
say "  ----------------------------------------------------------"
say ""

# 1) cmux 설치 확인 — 없으면 끝내지 않고 받게 안내한 뒤 기다린다(한 번에 끝나야 한다).
step "cmux 앱 확인"
CMUX=/Applications/cmux.app/Contents/Resources/bin/cmux
if [ ! -x "$CMUX" ]; then
  say "  cmux 앱이 아직 없습니다. 다운로드 페이지를 엽니다 — 받아서 '응용 프로그램'에 넣고 한 번 실행하세요."
  open "https://cmux.com" 2>/dev/null || true
  while [ ! -x "$CMUX" ]; do
    printf "  설치·첫 실행이 끝나면 엔터를 누르세요 (그만두려면 Ctrl+C)… "; read -r _ < /dev/tty
    [ -x "$CMUX" ] || err_soft "아직 /Applications/cmux.app 이 없습니다"
  done
fi
# 한 번은 실행돼 있어야 설정 파일·자동화 소켓이 생긴다. 안 켜져 있으면 켜준다.
pgrep -xq cmux || { open -a cmux 2>/dev/null || true; sleep 3; }
ok "cmux 발견"

step "Tailscale 연결 (아이폰과 같은 계정)"
# 2) Tailscale IP 자동 감지 (없으면 설치·로그인을 유도하고 대기)
TS=/Applications/Tailscale.app/Contents/MacOS/Tailscale
ts_ip() {
  local ip=""
  [ -x "$TS" ] && ip="$("$TS" ip -4 2>/dev/null | head -1)"
  [ -z "$ip" ] && ip="$(/usr/sbin/ipconfig getifaddr utun4 2>/dev/null || true)"
  [ -z "$ip" ] && ip="$(ifconfig 2>/dev/null | awk '/inet 100\./{print $2; exit}')"
  printf '%s' "$ip"
}
IP="$(ts_ip)"
if [ -z "$IP" ]; then
  say ""
  # brew 없는 Mac이 대부분 → Mac App Store를 바로 열어 아이폰과 동일한 "받기" 경험.
  # (brew가 있으면 무인 설치로 더 빠름)
  if [ ! -d /Applications/Tailscale.app ]; then
    if command -v brew >/dev/null 2>&1; then
      say "  Tailscale 설치 중 (Homebrew)…"
      brew install --cask tailscale-app >/dev/null 2>&1 || true
    fi
    if [ ! -d /Applications/Tailscale.app ]; then
      say "  Mac App Store에서 Tailscale을 엽니다 — [받기]를 눌러 설치하세요."
      open "macappstore://apps.apple.com/app/id1475387142" 2>/dev/null \
        || open "https://apps.apple.com/app/tailscale/id1475387142" 2>/dev/null
      printf "  설치가 끝나면 엔터를 누르세요… "; read -r _ < /dev/tty
    fi
  fi
  # 설치됐으면 실행 + 로그인 유도 (아이폰과 같은 계정이어야 서로 보임)
  open -a Tailscale 2>/dev/null || true
  say ""
  say "  Tailscale 창에서 [Log in] → 아이폰과 '같은 계정'으로 로그인하세요."
  say "  로그인되면 자동으로 이어집니다 (창을 닫지 마세요)…"
  # IP가 잡힐 때까지 폴링. 5분이 지나면 종료하지 않고 엔터로 계속 기다린다 —
  # 앱스토어 설치 + 계정 만들기 + 로그인은 5분을 넘기기 쉽고, 그때 "다시 실행" 은
  # 신규 사용자에게 "한 번에 안 된다" 로 보인다(2026-09-12 보고).
  while [ -z "$IP" ]; do
    for _ in $(seq 1 60); do
      sleep 5
      IP="$(ts_ip)"
      [ -n "$IP" ] && break
      printf "."
    done
    say ""
    if [ -z "$IP" ]; then
      say "  아직 Tailscale 로그인이 확인되지 않습니다."
      printf "  로그인을 마친 뒤 엔터를 누르세요 (그만두려면 Ctrl+C)… "; read -r _ < /dev/tty
      IP="$(ts_ip)"
    fi
  done
fi
ok "Tailscale IP: $IP"

step "연결 프로그램(브리지) 설치"
# 3) 브리지 바이너리 다운로드
DEST="$HOME/.config/cmux-remote"
mkdir -p "$DEST"
if curl -fsSL "$RAW/CmuxBridge" -o "$DEST/CmuxBridge"; then
  chmod +x "$DEST/CmuxBridge"
  codesign --force --sign - "$DEST/CmuxBridge" >/dev/null 2>&1 || true
  ok "브리지 설치: $DEST/CmuxBridge"

# 3.5) CPU/GPU 온도 표시용 macmon (Apple Silicon, 선택 — 없어도 브리지는 동작)
if ! command -v macmon >/dev/null 2>&1 && [ ! -x /opt/homebrew/bin/macmon ]; then
  if command -v brew >/dev/null 2>&1; then
    say "  온도 표시용 macmon 설치 중 (Homebrew, 1~3분)…"
    brew install macmon >/dev/null 2>&1 && ok "macmon 설치 (온도 표시)" || err "macmon 설치 실패 — 온도만 안 보이고 나머지는 정상"
  fi
fi
else
  err "브리지 다운로드 실패 (네트워크 확인)"
  exit 1
fi

step "접속 토큰·cmux 연동"
# 4) 앱 접속 토큰 (없으면 생성)
TOKENFILE="$DEST/token"
[ -s "$TOKENFILE" ] || openssl rand -hex 16 > "$TOKENFILE"
TOKEN="$(tr -d '[:space:]' < "$TOKENFILE")"
ok "토큰 준비 완료"

# 5) 빠른 경로용 cmux 소켓 암호 설정 (best-effort; 실패해도 CLI 폴백으로 동작)
PW="$(tr -d '[:space:]' < "$DEST/socket-password" 2>/dev/null || true)"
if [ -z "$PW" ]; then PW="$(openssl rand -hex 12)"; printf '%s' "$PW" > "$DEST/socket-password"; fi
CJSON="$HOME/.config/cmux/cmux.json"
if [ -f "$CJSON" ] && ! grep -q '"socketControlMode"' "$CJSON" 2>/dev/null; then
  cp "$CJSON" "$CJSON.bak.$(date +%Y%m%d%H%M)" 2>/dev/null || true
  /usr/bin/python3 - "$CJSON" "$PW" <<'PY' 2>/dev/null || true
import sys
p, pw = sys.argv[1], sys.argv[2]
s = open(p).read()
anchor = '"schemaVersion": 1,'
if anchor in s and 'socketControlMode' not in s:
    block = anchor + f'\n\n  "automation": {{\n    "socketControlMode": "password",\n    "socketPassword": "{pw}"\n  }},'
    open(p, 'w').write(s.replace(anchor, block, 1))
PY
  "$CMUX" reload-config >/dev/null 2>&1 || true
fi

step "브리지 상주 실행 등록"
# 6) 브리지를 launchd 상주 서비스로 등록.
# cmux 워크스페이스 안에서 돌리면 cmux 재시작·정리에 같이 죽어 연결이 끊겼다.
# launchd LaunchAgent는 죽으면 자동 부활(KeepAlive)하고 로그인 시 자동 시작(RunAtLoad).
UID_NUM="$(id -u)"
LABEL="io.dk.cmux-bridge"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
mkdir -p "$HOME/Library/LaunchAgents"

# 기존 인스턴스 전부 정리 (launchd·cmux 워크스페이스·잔여 프로세스)
launchctl bootout "gui/$UID_NUM/$LABEL" 2>/dev/null || true
"$CMUX" workspace list 2>/dev/null | awk '/cmux-bridge/{print $1}' | sed 's/^\*//' | while read -r w; do
  CMUX_QUIET=1 "$CMUX" workspace close --workspace "$w" >/dev/null 2>&1 || true
done
pkill -f "CmuxBridge" >/dev/null 2>&1 || true
for pid in $(lsof -tiTCP:9393 -sTCP:LISTEN 2>/dev/null); do kill "$pid" 2>/dev/null || true; done
sleep 1

cat > "$PLIST" <<PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>$LABEL</string>
	<key>ProgramArguments</key>
	<array>
		<string>$DEST/CmuxBridge</string>
	</array>
	<key>EnvironmentVariables</key>
	<dict>
		<key>BRIDGE_HOST</key>
		<string>$IP</string>
	</dict>
	<!-- 정상 종료(0)면 되살리지 않는다. 브리지는 9393 을 다른 인스턴스가 이미 쥐고
	     있을 때 0 으로 물러나므로, <true/> 로 두면 5초마다 EADDRINUSE 로 죽고 다시
	     뜨기를 영원히 반복한다(실측 3,556회 · bridge.log 20MB). 진짜 비정상 종료
	     (≠0)와 크래시는 그대로 부활하므로 상주 보장은 그대로다. -->
	<key>KeepAlive</key>
	<dict>
		<key>SuccessfulExit</key>
		<false/>
	</dict>
	<key>RunAtLoad</key>
	<true/>
	<key>ThrottleInterval</key>
	<integer>5</integer>
	<!-- /tmp는 오래된 파일이 자동 삭제된다. 지워져도 브리지는 열린 fd에 계속 쓰므로
	     로그가 사라진 줄도 모르게 된다 — 홈 아래로 둔다. 크기 관리는
	     watchdog.sh의 rotate_bridge_log()가 제자리 절단으로 처리. -->
	<key>StandardOutPath</key>
	<string>$DEST/bridge.log</string>
	<key>StandardErrorPath</key>
	<string>$DEST/bridge.log</string>
</dict>
</plist>
PLIST_EOF

# enable + kickstart 조합이 있어야 최초 실행이 확실히 걸린다(bootstrap만으론 pended).
launchctl bootstrap "gui/$UID_NUM" "$PLIST" 2>/dev/null || launchctl load "$PLIST" 2>/dev/null || true
launchctl enable "gui/$UID_NUM/$LABEL" 2>/dev/null || true
launchctl kickstart "gui/$UID_NUM/$LABEL" 2>/dev/null || true
sleep 3

if lsof -iTCP:9393 -sTCP:LISTEN -n -P 2>/dev/null | grep -q "$IP"; then
  ok "브리지 상주 실행 중 ($IP:9393) — cmux 재시작·재부팅에도 자동 유지"
else
  err "브리지가 아직 안 떴습니다. $DEST/bridge.log 를 확인하세요."
fi

step "자동 복구·자동 업데이트"
# 6.5) 자동 복구 워치독.
# 이전 버전은 9393 포트가 LISTEN인지만 봤는데, 2026-07-26 장애에서 그걸로는
# 부족한 게 드러났다: 포트는 멀쩡히 열려 있는데 뒤쪽 cmux 자동화 소켓이 죽어
# 모든 요청이 500으로 떨어졌고, 포트만 보는 감시는 정상이라고 보고했다.
# 또 StartInterval이 조용히 발화를 멈추는 것도 확인돼(runs=0) KeepAlive 루프로 바꿨다.
WD="$DEST/watchdog.sh"
if curl -fsSL "$RAW/watchdog.sh" -o "$WD"; then
  chmod +x "$WD"
else
  err "워치독 내려받기 실패 — 자동 복구 없이 진행합니다"
  WD=""
fi

# 구버전 워치독 두 개는 정리한다(포트만 보던 것 + 발화 안 하던 StartInterval 잡)
for OLD in io.dk.cmux-bridge-watchdog com.dk.cmux-watchdog; do
  launchctl bootout "gui/$UID_NUM/$OLD" 2>/dev/null || true
  rm -f "$HOME/Library/LaunchAgents/$OLD.plist"
done
rm -f "$DEST/bridge-watchdog.sh"

if [ -n "$WD" ]; then
  WDLABEL="io.dk.cmux-watchdog"
  WDPLIST="$HOME/Library/LaunchAgents/$WDLABEL.plist"
  # StartInterval을 쓰지 않는다 — 이 구조가 조용히 멈추는 걸 실측했다.
  # KeepAlive로 띄우고 주기는 watchdog.sh --loop 안의 sleep 60이 담당.
  cat > "$WDPLIST" <<WDP_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>$WDLABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>$WD</string>
        <string>--loop</string>
    </array>
    <key>KeepAlive</key><true/>
    <key>RunAtLoad</key><true/>
    <key>StandardOutPath</key><string>/tmp/cmux-watchdog.stdout.log</string>
    <key>StandardErrorPath</key><string>/tmp/cmux-watchdog.stdout.log</string>
</dict>
</plist>
WDP_EOF
  launchctl bootout "gui/$UID_NUM/$WDLABEL" 2>/dev/null || true
  launchctl bootstrap "gui/$UID_NUM" "$WDPLIST" 2>/dev/null || launchctl load "$WDPLIST" 2>/dev/null || true
  launchctl enable "gui/$UID_NUM/$WDLABEL" 2>/dev/null || true
  launchctl kickstart "gui/$UID_NUM/$WDLABEL" 2>/dev/null || true
  sleep 3
  if [ -f "$DEST/watchdog.heartbeat" ]; then
    ok "자동 복구 워치독 등록 (60초 주기 — 소켓·브리지·로그 크기까지 확인)"
  else
    err "워치독이 아직 안 돕니다 — launchctl kickstart gui/$UID_NUM/$WDLABEL 로 다시 시도하세요"
  fi
fi

step "상시전원 (뚜껑 닫아도 연결 유지 — 관리자 암호 1회)"
# 6.7) 상시전원 내재화: pmset disablesleep 전용 무암호 sudo 규칙.
# Capsomnia 방식과 동일한 원리 — 고정된 두 명령만 허용, 그 외 sudo 권한 없음.
if [ ! -f /etc/sudoers.d/cmux-remote ]; then
  say ""
  say "  상시전원(뚜껑 닫아도 동작) 설정 — 관리자 암호가 한 번 필요합니다."
  RULE="$USER ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 1, /usr/bin/pmset -a disablesleep 0"
  TMPR=$(mktemp)
  printf '%s\n' "$RULE" > "$TMPR"
  if visudo -c -f "$TMPR" >/dev/null 2>&1 \
     && sudo install -m 440 -o root -g wheel "$TMPR" /etc/sudoers.d/cmux-remote; then
    ok "상시전원 규칙 설치 (앱의 ⇪ 버튼으로 원격 제어)"
  else
    err "상시전원 규칙 설치 실패 — 앱 ⇪ 버튼은 Capsomnia가 있을 때만 동작합니다"
  fi
  rm -f "$TMPR"
fi

# 7) iPhone 자동 설정 링크 → Mac 클립보드 (Universal Clipboard로 iPhone에 전달)
LINK="cmuxremote://setup?host=$IP&token=$TOKEN"
printf '%s' "$LINK" | pbcopy 2>/dev/null || true

say ""
if [ "$NFAIL" -gt 0 ]; then
  b   "  ⚠️ 설치는 끝났지만 아래 ${NFAIL}건은 실패했습니다:"
  printf '%s' "$FAILTXT"
  say "  (연결은 될 수 있습니다. 위 항목은 나중에 이 명령을 다시 실행하면 재시도합니다.)"
else
  b   "  ✅ 다 됐어요! 이제 아이폰만 있으면 됩니다."
fi
say "  ----------------------------------------------------------"
say ""
b   "  아이폰에서 할 일 — 딱 하나:"
say "     cmux 앱을 열기만 하세요. 자동으로 연결됩니다."
say "     (\"붙여넣기 허용\"이 뜨면 한 번 눌러주세요 — 그게 전부예요)"
say ""
say "  혹시 자동으로 안 되면, 앱 ⚙️ 설정에 아래를 직접 넣으세요:"
say "     연결 주소 :  $IP"
say "     토큰      :  $TOKEN"
say ""
say "  참고"
say "     · 이 Mac의 cmux 앱은 켜둔 채로 두세요 (꺼지면 화면이 안 보여요)."
say "     · 아이폰과 이 Mac은 같은 Tailscale 계정이어야 서로 보입니다."
say "     · 이 창은 닫아도 됩니다. 연결은 백그라운드에서 계속 유지돼요."
say ""

}

main "$@"