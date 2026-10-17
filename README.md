# cmux 원격 — 아이폰으로 내 맥의 터미널 쓰기

맥에서 돌아가는 [cmux](https://cmux.com) 세션을 아이폰에서 그대로 보고 조작합니다.
외출 중에 빌드를 돌리거나, 에이전트가 뭘 하고 있는지 확인하거나, 음성으로 명령을 보낼 수 있습니다.

이 저장소는 **맥에 설치하는 브리지**입니다. 아이폰 앱은 App Store 에서 받습니다.

---

## 미리 준비할 것 (설치 전에 확인)

| | |
|---|---|
| **cmux 앱** | https://cmux.com — 브리지가 여기에 붙습니다 |
| **Tailscale** | 맥과 아이폰에 **같은 계정**으로 로그인 |
| macOS | Apple Silicon·Intel 모두 됩니다 |

Tailscale 은 맥과 아이폰을 안전하게 잇는 통로입니다. 이게 있어야 밖에서도 집의 맥에 닿습니다.
연결 상태는 설치 앱에서 확인하며, 설치 전에 두 기기에서 실행해 주세요.

---

## DMG로 설치 (macOS 14 이상)

[KLCB 다운로드](https://klcb.co.kr/downloads/cmux-bridge.dmg)에서 **CmuxBridge-2.40.24.dmg**를 받습니다.
DMG 안의 **Cmux Bridge 설치.app**을 열고 **Bridge 설치**를 누릅니다. Apple Silicon과 Intel을 모두 지원합니다.
설치 앱에서 cmux·Tailscale 설치 및 연결 상태를 확인하고, 필요한 공식 다운로드나 앱 열기로 이어집니다.
현재 cmux는 macOS 14 이상이 필요합니다. Tailscale 로그인·VPN 승인과 macOS 권한 승인은 사용자가 진행해야 합니다.
Bridge 설치와 자동 업데이트에는 Homebrew·Python·Xcode 명령줄 도구가 필요하지 않습니다. 기존 연결 토큰은 보존합니다.

설치 완료 화면에서 QR을 바로 스캔하고 화면 기록·손쉬운 사용 권한을 설정할 수 있습니다.
나중에는 Mac 관리창에서 **관리 접기 오른쪽의 QR 연결**을 누릅니다.
iPhone·iPad 앱의 컴퓨터 목록에서 **QR로 추가**를 선택해 스캔하면 이 Mac을 저장할 수 있습니다.
QR에는 접속 키가 들어 있으므로 본인 기기로만 스캔하고 공유하지 마세요.
등록과 별개로 cmux 소켓 접근 및 화면 기록·손쉬운 사용 권한은 해당 기능에 필요합니다.

**2.40.24 정식 배포는 Developer ID 서명과 Apple 공증, Gatekeeper 검증을 통과한 파일만 게시합니다.**
DMG에 공증 티켓을 첨부하며, 설치 후 복사되는 Bridge 실행 파일도 별도로 공증합니다.
Bridge를 처음 실행할 때 macOS의 온라인 확인이 필요할 수 있습니다.
새 Mac에서 격리 다운로드 후 설치하는 전체 과정은 아직 검증하지 않았습니다.

## 기존 터미널 설치 명령

이전 `install.sh`와 `install.command`는 설정을 직접 바꾸지 않고 DMG 설치 안내만 표시합니다.
위 DMG의 **Bridge 설치** 버튼을 사용해 주세요. 설치기는 기존 cmux 소켓 암호를 재사용하고,
cmux 인증과 연결을 실제로 확인한 뒤 Bridge와 복구 워치독을 등록합니다.
안전하게 병합할 수 있는 중복 `automation` 항목은 정리하며, 수정 전 원본 설정을
같은 폴더의 고유 `.cmux-bridge-backup-*.bak` 파일에 사용자 전용 권한으로 보존합니다.
서로 다른 기존 암호나 충돌하는 설정, 암호 모드인데 읽을 수 있는 암호가 없는 경우에는
임의로 덮어쓰지 않고 설치를 중단해 필요한 조치를 안내합니다.
명시적으로 비운 소켓 암호, 사용자가 꺼 둔 Bridge, 복구가 필요한 설치 기록도 보존하고 원인을 표시합니다.

---

## 업데이트

관리창에서 **관리 접기 오른쪽의 업데이트 확인** 버튼으로 공식 안정 버전을 확인합니다.
자동 확인 주기는 **6시간**이며, 확인 실패 시 **15분** 뒤 다시 확인합니다.
수동 확인은 60초마다 한 번 가능합니다. 자동 업데이트를 꺼 둔 경우 확인만 하고 적용하지 않습니다.

업데이트는 활성 원격 연결이 없고 마지막 외부 활동 후 **60초**가 지난 뒤에만 적용합니다.
미전송 초안이나 진행 중인 관리 작업도 적용을 보류합니다. 후보 파일은 공식 릴리스의 고정 커밋,
SHA-256, 양쪽 CPU 아키텍처, Developer ID 서명 및 Apple 공증을 검증합니다.
교체 뒤 새 버전이 정상 응답하지 않으면 검증된 이전 파일 복원을 시도합니다.
복구 상태를 확인할 수 없으면 추가 자동 교체를 중단하고 복구 자료를 보존합니다.

2.40.24의 복구 워치독은 바이너리를 직접 내려받아 교체하지 않습니다.
설치기는 확인된 기존 워치독을 새 방식으로 이관하고, 누락된 script·LaunchAgent 또는
확인된 부분 설치를 복구합니다. 사용자가 명시적으로 꺼 둔 워치독과 사용자 정의·확인 불가
설정은 그대로 보존하고 자동 적용을 보류합니다. cmux 인증 실패 시 새 워치독을 시작하지 않습니다.
브리지 파일만 바꾸면 오래된 워치독 이관이 완료되지 않을 수 있습니다.

자동 적용을 끄려면 Bridge 실행 환경의 `CMUX_AUTO_UPDATE=0`을 사용합니다.
기존 실행 경로·연결 토큰·LaunchAgent와 cmux 세션을 보존합니다.
화면 기록·손쉬운 사용 권한이 필요한 경우 macOS 설정에서 직접 허용해야 합니다.

---

## 메뉴 막대 아이콘

설치하면 화면 오른쪽 위에 **동그란 C** 가 생깁니다. 상시전원 상태를 보여줍니다.

| 모양 | 뜻 |
|---|---|
| 초록 + 빨간 점 | **켜짐** — 뚜껑을 닫아도 맥이 자지 않습니다 |
| 회색 | 꺼짐 |

아이콘을 누르면 Hairline 관리 패널이 열리고, 오른쪽 클릭하면 기존 관리 메뉴가 열립니다.
화면 공유 중지·연결 끊기와 권한 설정, 팬 상태·속도, 모델 목록 갱신을 이곳에서 관리합니다.
팬은 현재 하드웨어가 지원하는 모드에서만 직접 제어할 수 있습니다.
모든 팬에 공통 범위의 같은 목표 RPM을 적용하며 실제 회전수에는 미세한 차이가 있을 수 있습니다.
자동 모드에서는 macOS가 팬별 속도를 결정합니다.
**Caps Lock 을 길게 눌러도** 켜고 끌 수 있습니다.

> **상시전원을 켜면 뚜껑을 닫아도 맥이 깨어 있습니다.** 밖에서 접속하려면 필요하지만,
> 그만큼 발열과 배터리 소모가 있습니다. 전원을 꽂아두는 것을 권합니다.

---

## 음성 기능 (선택)

말로 명령하고, 결과를 읽어주는 기능입니다. **쓰려면 본인 API 키가 필요합니다.**
안 쓰면 이 부분은 무시해도 앱은 정상 동작합니다.

앱 **설정 → 음성 제공자** 에서 고릅니다.

|---|---|---|
| 읽어주기 | 유료 | **무료** (S2.1 Pro) |
| 음성인식 | 유료 | 유료 |
| 실시간 인식 | **됩니다** (말하는 대로 글자가 차오름) | 안 됩니다 (문장을 마치면 인식) |

키는 **맥에만 저장되고 아이폰에는 남지 않습니다**(권한 600). 화면에는 가려진 형태만 보입니다.

---

## 잘 안 될 때

**폰에서 "연결 실패"**

1. 맥과 아이폰이 **같은 Tailscale 계정**인지 확인
2. 맥에서 브리지가 사는지 확인:
   ```bash
   curl -s http://127.0.0.1:9393/ping
   ```
   `unauthorized` 가 나오면 **정상입니다**(인증 뒤에 있는 응답이라 그렇습니다).
3. 그래도 안 되면 DMG 설치 앱을 다시 실행하세요. 기존 키와 설정을 우선 보존합니다.

**뚜껑을 닫으면 끊긴다** → 메뉴 막대의 C 아이콘이 초록인지 확인하세요. 회색이면 **상시전원 → 켜기**를 선택합니다.


**로그 보기**

```bash
tail -f ~/.config/cmux-remote/bridge.log      # 브리지
tail -f ~/.config/cmux-remote/watchdog.log    # 자동 복구
```

---

## 맥을 여러 대 쓰기

맥마다 위 설치를 한 번씩 하면 각자 토큰이 생깁니다.
아이폰 앱의 컴퓨터 선택 화면에 각 Mac을 저장한 뒤 원하는 컴퓨터를 선택합니다.
저장 대수 제한은 없습니다. 별칭을 비우면 해당 Mac의 컴퓨터 이름을 사용합니다.

## 원격 화면과 마우스·키보드

1. Mac 메뉴 막대의 **C → 원격 화면 공유**에서 화면 및 시스템 오디오 기록 권한을 허용합니다.
2. 마우스·키보드도 쓰려면 macOS **손쉬운 사용**에서 `CmuxBridge`를 허용합니다.
3. iPhone에서 저장된 컴퓨터의 원격 화면 버튼을 누릅니다. 터미널 화면 상단에서도 열 수 있습니다.
4. 새 연결에서는 **제어**를 자동으로 요청하며 Mac의 승인 응답 뒤에만 마우스·키보드가 활성화됩니다.
   제어를 직접 끄면 해당 연결과 자동 복구에서는 꺼진 상태를 유지합니다.
5. **Mac 오디오**를 켜면 시스템 오디오를 iPhone·iPad에서 재생합니다. 음량과 출력 장치를 선택할 수 있습니다.

영상은 Tailscale 주소로 직접 연결하며 Relay를 거치지 않습니다. Mac과 iPhone이 모두
Tailscale에 연결돼 있어야 합니다. 화면을 닫거나 앱이 백그라운드로 가면 연결과 누른 키를 해제합니다.

화면 공유 관리 API는 `POST /desktop/control`이며 본문은
`{"action":"enable"}`, `{"action":"disable"}`, `{"action":"disconnect"}` 중 하나입니다.
Authorization Bearer와 실제 Tailscale 연결이 필요하며 LAN·Cloudflare Relay로는 변경할 수 없습니다.
`GET /desktop/status`의 `managementSupported: true`로 지원 여부를 확인합니다.
성공 응답은 202와 `accepted`, `action`, `enabled`, `active`이며 종료는 비동기이므로
`active`가 잠시 true일 수 있습니다. 저장 실패는 500, 잘못된 본문·추가 키·1024바이트 초과는 400입니다.

Apple ScreenCaptureKit과 하드웨어 VideoToolbox를 사용합니다. 기본 목표는 4K·480 FPS이며
목표값을 보존하면서 연결 상한은 Mac·iPhone 디스플레이와 브리지의 공통 지원 범위로 정합니다.
실제 크기는 화면 비율·원본 해상도에 맞춥니다. 목표·연결 상한·실제 수신 및 표시 FPS를 구분하며,
480 FPS 성능을 보장하지 않습니다. 120Hz 화면에서는 연결 상한도 최대 120 FPS입니다.
일시적인 연결 오류는 1·2·4초 간격으로 최대 3회 복구합니다. 기존 제어 의도가 유지된 경우에만
새 영상이 도착한 뒤 제어를 다시 요청하며, Mac 승인 전에는 입력하지 않습니다.
Mac의 제어 거절·철회 뒤에는 자동으로 켜지지 않습니다. 사용자가 명시적으로 다시 연결하면
새 연결의 기본 제어 요청을 시작합니다. 화질 변경 중에도 입력을 해제하고 새 세대 영상과 승인을 기다립니다.
현재 영상은 HEVC/H.264, 8비트 4:2:0 SDR이며 HDR은 포함하지 않습니다.
시스템 오디오는 48kHz 스테레오 PCM으로 전송하며 마이크 입력은 포함하지 않습니다.
오디오 데이터에 약 3.072Mbps가 추가로 필요합니다. 소리를 끄면 Mac의 오디오 전송도 중지합니다.
출력 장치가 바뀌거나 기존 음성 기능과 충돌하면 소리를 일시 중지하고 영상은 유지합니다.
Apple의 Mac 간 High Performance 화면 공유 프로토콜과는 별도의 구현입니다.

---

## 안전에 관해

- 아이폰과 맥 사이 통신은 **Tailscale(WireGuard) 암호화 구간 안**에서만 오갑니다.
- 토큰과 API 키는 맥의 `~/.config/cmux-remote/` 에 **권한 600** 으로 저장됩니다.
- 토큰을 새로 만들려면 그 파일을 지우고 브리지를 재시작합니다:
  ```bash
  rm ~/.config/cmux-remote/token
  launchctl kickstart -k gui/$(id -u)/io.dk.cmux-bridge
  ```
  **이러면 폰 연결이 끊기므로 QR 로 다시 스캔해야 합니다.**

---

## 자동 복구

브리지가 죽거나 응답하지 않으면 워치독이 60초 안에 되살립니다.
cmux 소켓만 끊긴 경우에는 **앱을 재시작하지 않고** 소켓만 복구해 열어둔 워크스페이스를 지킵니다.

상태 확인:

```bash
~/.config/cmux-remote/watchdog.sh --status
```

## 모델 목록 자동 갱신

`io.dk.cmux-model-watchdog`는 복구 워치독과 별도로 실행됩니다. 각 Mac의
Claude·Codex가 제공하는 모델 목록을 5분 간격으로 다시 확인합니다. 새로고침 요청은
다음 60초 점검에서 처리하며, 실패하면 60초 뒤 재시도합니다. CLI 버전이 같아도
목록을 다시 조회하므로 계정에 새 모델이 열리는 경우도 반영할 수 있습니다.

모델 감시기는 실행 중인 cmux·에이전트에 입력을 보내거나 재시작하지 않습니다.
브리지나 CLI 바이너리를 자동 업그레이드하지 않으며, 현재 선택한 모델도 바꾸지 않습니다.
조회 실패 시 마지막으로 확인한 목록과 실패 상태를 함께 유지합니다.

```bash
~/.config/cmux-remote/model-watchdog.sh --status
tail -f ~/.config/cmux-remote/model-watchdog.log
```

모델 캐시는 `~/.config/cmux-remote/agent-models.json`에 사용자 전용 권한으로 저장됩니다.
기존 설치에 모델 감시기만 추가할 때는 전체 설치 스크립트를 다시 실행하지 말고,
`model-watchdog.sh`·`model-catalog.py`와 별도 LaunchAgent만 반영해야 합니다.
전체 설치는 기존 브리지·복구 서비스 설정도 다시 구성합니다.

## 개발자용 브리지 릴리스

`CMUX_CODESIGN_IDENTITY`에 유효한 서명 인증서의 이름 또는 지문을 명시하고
`installer/release-bridge.sh`를 실행합니다. 누락하거나 `-`를 지정하면 빌드 전에 중단합니다.
서명 후 모든 아키텍처에서 `io.dk.cmux-bridge` 식별자와 프로젝트 개발 팀을 다시 검증합니다.
`--dry-run`은 게시만 생략하며, 빌드와 서명 검증은 동일합니다.
기존 셸 설치기는 DMG로 안내하며, DMG 설치 앱은 서명된 배포 바이너리를 검증합니다.


Release 2.40.24 makes plain cmux terminals visible in the Mac dashboard, preserves exact-target read-only context access when agent identity is unavailable, and separates session refresh from fan and system polling. It keeps provider and process-generation checks for command submission.

The dashboard serves its bundled page through a private WKURLSchemeHandler. Network sources remain blocked by its Content Security Policy; its native navigation policy permits only the first exact local page request. Load failures show a retry instruction instead of remaining white.

새 Mac에서 연결이 끊긴 소켓 파일이 남아 있어도 정상 cmux 연결을 찾아 세션 목록과 내용을 표시합니다. 명시적으로 지정한 소켓은 다른 대상으로 바꾸지 않습니다.

## 계정 관리
노치 오른쪽 계정 버튼에서 Claude·Codex 계정을 추가할 수 있습니다. 공식 CLI 로그인 후 등록 확인을 누르세요. 세션 위의 계정별 목록과 로고, 5시간·주간 사용률 게이지를 제공합니다. 계정 전환은 새 세션에 적용되며 실행 중인 세션은 유지합니다. 없는 한도 값은 확인 불가로 표시합니다. 인증정보는 업체 CLI의 저장소에서 관리합니다.

## 승인 자동 확인
계정은 바로 목록에 추가됩니다. Claude·Codex 브라우저 승인을 5초 간격으로 자동 확인하며, 관리 창을 닫아도 10분 동안 계속합니다. 코드가 표시된 경우에만 공식 CLI 로그인 창에 입력하세요. 5시간·주간 한도가 100% 이상이면 로그인과 한도가 확인된 같은 업체의 다른 계정으로 자동 선택합니다. 전환은 새 Bridge 세션에 적용됩니다. 모든 계정에 목록 삭제가 제공됩니다.

## Startup and usage recovery

The watchdog restores a missing, valid Bridge LaunchAgent registration without sending commands to an existing terminal. Explicitly disabled services remain disabled. Newly approved accounts receive their first quota read on the next 5-second poll, including inactive accounts. Missing provider windows are labeled separately from loading and authentication failures. Dashboard name lookup does not wait for network DNS.

Manual update checks bypass the automatic cache; queued manual installs can be retried and do not wait for the quiet timer alone. Actual active connections and unsent drafts still protect replacement. Passive quota reads do not reset automatic idle time. Status-button handlers are restored after temporary menus. Restart uses a detached generation-verified helper, preserving cmux workspaces.

A cached dashboard WebView is explicitly reattached to its popover controller on every reopen. The same view can move between the notch and status item without an empty cached window. Legacy management menus use a native anchored popup independently of the dashboard toggle.

## 2.40.24

cmux 0.65.2의 입력 순번과 확인 응답을 지원합니다. 새 iOS 앱의 명령 입력과 Enter는 같은 터미널 큐에서 순서대로 전달되며, 연결 재시도 시 같은 입력 식별자를 사용합니다. 세션 상태 이벤트와 독립된 조회 소켓으로 관리창 갱신과 목록 조회를 개선했습니다. Mac 전체 화면 스트리밍의 FPS 보장과는 별개입니다.
