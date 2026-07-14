# cmux-remote bridge

Mac-side bridge for the CmuxPhone iOS app. One-line install (Mac Terminal):

```bash
curl -fsSL https://raw.githubusercontent.com/seraghmicael-lgtm/cmux-remote-bridge/main/install.sh | bash
```

Requires: [cmux](https://cmux.com) running, [Tailscale](https://tailscale.com/download) logged in (same account as your iPhone).

After install, the script copies a `cmuxremote://` setup link to your Mac clipboard — on your iPhone, tap **자동 연결** in the app (Universal Clipboard) and you're done. Manual IP/token entry is still available in ⚙️ settings.
