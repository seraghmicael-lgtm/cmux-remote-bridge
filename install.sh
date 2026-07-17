#!/bin/bash
# cmux-remote 브리지 원라인 설치:
#   curl -fsSL https://raw.githubusercontent.com/seraghmicael-lgtm/cmux-remote-bridge/main/install.sh | bash
# 끝나면 iPhone용 자동 설정 링크(cmuxremote://…)를 클립보드에 복사합니다.
set -u
RAW="https://raw.githubusercontent.com/seraghmicael-lgtm/cmux-remote-bridge/main"

say()  { printf '%s\n' "$*"; }
ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; }
err()  { printf '  \033[31m✗\033[0m %s\n' "$*"; }
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

# 1) cmux 설치 확인
CMUX=/Applications/cmux.app/Contents/Resources/bin/cmux
if [ ! -x "$CMUX" ]; then
  err "cmux 앱이 없습니다. 먼저 설치·실행하세요: https://cmux.com"
  exit 1
fi
ok "cmux 발견"

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
      printf "  설치가 끝나면 엔터를 누르세요… "; read -r _
    fi
  fi
  # 설치됐으면 실행 + 로그인 유도 (아이폰과 같은 계정이어야 서로 보임)
  open -a Tailscale 2>/dev/null || true
  say ""
  say "  Tailscale 창에서 [Log in] → 아이폰과 '같은 계정'으로 로그인하세요."
  say "  로그인되면 자동으로 이어집니다 (창을 닫지 마세요)…"
  # IP가 잡힐 때까지 폴링 (최대 5분) — 재실행 불필요.
  for _ in $(seq 1 60); do
    sleep 5
    IP="$(ts_ip)"
    [ -n "$IP" ] && break
    printf "."
  done
  say ""
fi
if [ -z "$IP" ]; then
  err "Tailscale 로그인을 확인하지 못했습니다. 로그인 후 이 명령을 다시 실행하세요."
  exit 1
fi
ok "Tailscale IP: $IP"

# 3) 브리지 바이너리 다운로드
DEST="$HOME/.config/cmux-remote"
mkdir -p "$DEST"
if curl -fsSL "$RAW/CmuxBridge" -o "$DEST/CmuxBridge"; then
  chmod +x "$DEST/CmuxBridge"
  codesign --force --sign - "$DEST/CmuxBridge" >/dev/null 2>&1 || true
  ok "브리지 설치: $DEST/CmuxBridge"

# 3.5) CPU/GPU 온도 표시용 macmon (Apple Silicon, 선택 — 없어도 브리지는 동작)
if ! command -v macmon >/dev/null 2>&1 && [ ! -x /opt/homebrew/bin/macmon ]; then
  command -v brew >/dev/null 2>&1 && brew install macmon >/dev/null 2>&1 && ok "macmon 설치 (온도 표시)" || true
fi
else
  err "브리지 다운로드 실패 (네트워크 확인)"
  exit 1
fi

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

# 6) 기존 브리지 정리 후 cmux 안에서 실행
"$CMUX" workspace list 2>/dev/null | awk '/cmux-bridge/{print $1}' | sed 's/^\*//' | while read -r w; do
  CMUX_QUIET=1 "$CMUX" workspace close --workspace "$w" >/dev/null 2>&1 || true
done
pkill -f "CmuxBridge" >/dev/null 2>&1 || true
for pid in $(lsof -tiTCP:9393 -sTCP:LISTEN 2>/dev/null); do kill "$pid" 2>/dev/null || true; done
sleep 1
CMUX_QUIET=1 "$CMUX" new-workspace --name "cmux-bridge" --focus false \
  --command "exec env BRIDGE_HOST=$IP $DEST/CmuxBridge 2>&1 | tee /tmp/cmux-bridge.log" >/dev/null 2>&1 || true
sleep 3

if lsof -iTCP:9393 -sTCP:LISTEN -n -P 2>/dev/null | grep -q "$IP"; then
  ok "브리지 실행 중 ($IP:9393)"
else
  err "브리지가 아직 안 떴습니다. /tmp/cmux-bridge.log 를 확인하세요."
fi

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
b   "  ✅ 다 됐어요! 이제 아이폰만 있으면 됩니다."
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
