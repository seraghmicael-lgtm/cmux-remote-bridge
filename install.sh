#!/bin/bash
# cmux-remote 브리지 원라인 설치:
#   curl -fsSL https://raw.githubusercontent.com/seraghmicael-lgtm/cmux-remote-bridge/main/install.sh | bash
# 안전한 설정 복구는 공식 DMG의 네이티브 설치 앱에서만 실행합니다.
set -u

# 기존 실행 파일은 다운로드·검증이 모두 끝난 뒤에만 교체한다. curl -o 를
# 설치 경로에 바로 쓰면 연결이 끊기는 순간 정상 브리지까지 반쪽 파일이 된다.
# 같은 디렉터리의 임시 파일을 rename 해 교체하므로 실행 중인 inode 도 보존된다.
install_bridge_binary() {
  local url="$1" destination="$2" staged
  staged=$(mktemp "${destination}.download.XXXXXX") || return 1
  if ! curl -fsSL --connect-timeout 15 --max-time 120 "$url" -o "$staged"; then
    rm -f "$staged"; return 1
  fi
  if ! file -b "$staged" | grep -q 'Mach-O' || [ "$(stat -f %z "$staged")" -lt 100000 ]; then
    rm -f "$staged"; return 1
  fi
  chmod 755 "$staged" || { rm -f "$staged"; return 1; }
  # Preserve the release identity so macOS can recognize later permission updates.
  if ! codesign --verify --strict --all-architectures -R '=identifier "io.dk.cmux-bridge" and anchor apple generic and certificate leaf[subject.OU] = "HQ94KCSV26"' "$staged" >/dev/null 2>&1; then
    printf '%s\n' '브리지 서명 검증 실패. 기존 설치를 유지합니다.' >&2
    rm -f "$staged"; return 1
  fi
  mv -f "$staged" "$destination" || { rm -f "$staged"; return 1; }
}

install_model_watchdog_file() {
  local url="$1" destination="$2" language="$3" staged
  staged=$(mktemp "${destination}.download.XXXXXX") || return 1
  if ! curl -fsSL --connect-timeout 15 --max-time 60 "$url" -o "$staged"; then
    rm -f "$staged"; return 1
  fi
  case "$language" in
    bash) bash -n "$staged" >/dev/null 2>&1 ;;
    python) /usr/bin/python3 -c 'import ast,sys; ast.parse(open(sys.argv[1]).read())' "$staged" >/dev/null 2>&1 ;;
    *) rm -f "$staged"; return 1 ;;
  esac
  if [ "$?" -ne 0 ] || [ ! -s "$staged" ]; then rm -f "$staged"; return 1; fi
  chmod 700 "$staged" || { rm -f "$staged"; return 1; }
  mv -f "$staged" "$destination" || { rm -f "$staged"; return 1; }
}

write_model_watchdog_plist() {
  local destination="$1" watcher="$2" logfile="$3" watcher_xml logfile_xml
  watcher_xml=$(printf '%s' "$watcher" | sed 's/\&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')
  logfile_xml=$(printf '%s' "$logfile" | sed 's/\&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')
  cat > "$destination" <<MODEL_PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>io.dk.cmux-model-watchdog</string>
    <key>ProgramArguments</key>
    <array><string>/bin/bash</string><string>$watcher_xml</string><string>--loop</string></array>
    <key>KeepAlive</key><true/>
    <key>RunAtLoad</key><true/>
    <key>ThrottleInterval</key><integer>30</integer>
    <key>StandardOutPath</key><string>$logfile_xml</string>
    <key>StandardErrorPath</key><string>$logfile_xml</string>
</dict>
</plist>
MODEL_PLIST_EOF
  /usr/bin/plutil -lint "$destination" >/dev/null
}

# Native installation preserves JSONC, existing socket credentials and live services.
main() {
  printf '%s\n' '셸 설치는 중단되었습니다. 기존 설정과 실행 중인 작업은 변경하지 않았습니다.'
  printf '%s\n' 'https://klcb.co.kr 에서 최신 cmux Bridge DMG를 받아 설치 앱을 실행해 주세요.'
  printf '%s\n' '설치 앱이 cmux 소켓 암호와 watchdog을 확인하고 기존 설치를 안전하게 복구합니다.'
  return 1
}

# Offline checks load helper functions without installation or network activity.
if [ "${CMUX_INSTALL_LIB:-0}" != "1" ]; then main "$@"; fi
