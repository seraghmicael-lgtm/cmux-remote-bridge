#!/bin/bash
# cmux-remote 브리지 원라인 설치:
#   curl -fsSL https://raw.githubusercontent.com/seraghmicael-lgtm/cmux-remote-bridge/main/install.sh | bash
# 끝나면 iPhone용 자동 설정 링크(cmuxremote://…)를 클립보드에 복사합니다.
set -u
RAW="https://raw.githubusercontent.com/seraghmicael-lgtm/cmux-remote-bridge/main"

say()  { printf '%s\n' "$*"; }
ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; }
err()  { printf '  \033[31m✗\033[0m %s\n' "$*"; }

say ""
say "======================================"
say "  cmux-remote 브리지 설치"
say "======================================"
say ""

# 1) cmux 설치 확인
CMUX=/Applications/cmux.app/Contents/Resources/bin/cmux
if [ ! -x "$CMUX" ]; then
  err "cmux 앱이 없습니다. 먼저 설치·실행하세요: https://cmux.com"
  exit 1
fi
ok "cmux 발견"

# 2) Tailscale IP 자동 감지
TS=/Applications/Tailscale.app/Contents/MacOS/Tailscale
IP=""
[ -x "$TS" ] && IP="$("$TS" ip -4 2>/dev/null | head -1)"
[ -z "$IP" ] && IP="$(/usr/sbin/ipconfig getifaddr utun4 2>/dev/null || true)"
[ -z "$IP" ] && IP="$(ifconfig 2>/dev/null | awk '/inet 100\./{print $2; exit}')"
if [ -z "$IP" ]; then
  err "Tailscale IP를 못 찾았습니다. Mac에 Tailscale 설치·로그인 후 다시 실행하세요."
  say "     https://tailscale.com/download"
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
"$CMUX" workspace list 2>/dev/null | awk '/cmux-bridge/{print $2}' | while read -r w; do
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

# 7) iPhone 자동 설정 링크 → Mac 클립보드 (Universal Clipboard로 iPhone에 전달)
LINK="cmuxremote://setup?host=$IP&token=$TOKEN"
printf '%s' "$LINK" | pbcopy 2>/dev/null || true

say ""
say "======================================"
say "  설치 완료! iPhone 연결 방법:"
say "======================================"
say ""
say "  ★ 자동: 설정 링크가 클립보드에 복사됐습니다."
say "     iPhone cmux 앱을 열기만 하면 자동으로 연결됩니다."
say "     (붙여넣기 허용을 한 번 눌러주세요 · 같은 Apple 계정이면 클립보드 자동 공유)"
say ""
say "  수동 입력이 필요하면 앱 ⚙️ 설정에:"
say "   Tailscale IP :  $IP"
say "   토큰         :  $TOKEN"
say ""
say "  · cmux 앱이 실행 중이어야 폰에 세션이 보입니다."
say "  · Mac과 iPhone이 같은 Tailscale 계정이어야 합니다."
