#!/usr/bin/python3
"""Read installed CLI capabilities without starting a conversation or a terminal."""
import argparse
import concurrent.futures
import datetime
import fcntl
import hashlib
import json
import os
import pathlib
import re
import selectors
import shutil
import signal
import subprocess
import tempfile
import time


class ProbeError(Exception):
    pass


def clean_text(value, limit=240):
    if not isinstance(value, str) or not value or len(value) > limit:
        raise ProbeError("invalid_response")
    if any(ord(c) < 32 or ord(c) == 127 for c in value):
        raise ProbeError("invalid_response")
    return value


def models_from(provider, rows):
    if not isinstance(rows, list) or not rows or len(rows) > 512:
        raise ProbeError("invalid_response")
    result, seen = [], set()
    for row in rows:
        if not isinstance(row, dict):
            raise ProbeError("invalid_response")
        if provider == "codex" and row.get("hidden") is True:
            continue
        ident = clean_text(row.get("value") if provider == "claude" else row.get("id"))
        if ident in seen:
            raise ProbeError("invalid_response")
        seen.add(ident)
        model = {"id": ident, "name": clean_text(row.get("displayName"))}
        resolved = row.get("resolvedModel") if provider == "claude" else row.get("model")
        if resolved:
            model["resolvedModel"] = clean_text(resolved)
        if provider == "claude":
            efforts = row.get("supportedEffortLevels", [])
        else:
            options = row.get("supportedReasoningEfforts", [])
            if not isinstance(options, list) or any(not isinstance(v, dict) for v in options):
                raise ProbeError("invalid_response")
            efforts = [v.get("reasoningEffort") for v in options]
        if not isinstance(efforts, list) or len(efforts) > 32:
            raise ProbeError("invalid_response")
        model["reasoningEfforts"] = list(dict.fromkeys(clean_text(v, 80) for v in efforts))
        if row.get("defaultReasoningEffort"):
            model["defaultEffort"] = clean_text(row["defaultReasoningEffort"], 80)
        result.append(model)
    if not result:
        raise ProbeError("invalid_response")
    return result


class JSONProcess:
    """Bound both execution and output; only terminate the child group we created."""
    def __init__(self, args, cwd, env, timeout, max_output=4 * 1024 * 1024):
        self.process = subprocess.Popen(args, cwd=cwd, env=env, stdin=subprocess.PIPE,
                                        stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                                        start_new_session=True)
        self.selector = selectors.DefaultSelector()
        self.selector.register(self.process.stdout, selectors.EVENT_READ)
        self.deadline = time.monotonic() + timeout
        self.buffer = b""
        self.received = 0
        self.max_output = max_output

    def send(self, value):
        try:
            self.process.stdin.write(json.dumps(value).encode() + b"\n")
            self.process.stdin.flush()
        except (OSError, BrokenPipeError):
            raise ProbeError("protocol_unavailable")

    def read(self):
        try:
            value = json.loads(self.read_line())
        except (ValueError, UnicodeDecodeError):
            raise ProbeError("invalid_response")
        except EOFError:
            raise ProbeError("protocol_unavailable")
        if not isinstance(value, dict):
            raise ProbeError("invalid_response")
        return value

    def read_line(self):
        while True:
            if b"\n" in self.buffer:
                line, self.buffer = self.buffer.split(b"\n", 1)
                return line
            remaining = self.deadline - time.monotonic()
            if remaining <= 0:
                raise ProbeError("timeout")
            if not self.selector.select(min(remaining, 0.25)):
                continue
            chunk = os.read(self.process.stdout.fileno(), 65536)
            if not chunk:
                if self.buffer:
                    line, self.buffer = self.buffer, b""
                    return line
                raise EOFError()
            self.received += len(chunk)
            if self.received > self.max_output:
                raise ProbeError("response_too_large")
            self.buffer += chunk

    def close(self):
        # The CLI may already have exited while one of its helpers is still alive.
        for sig in (signal.SIGTERM, signal.SIGKILL):
            try:
                os.killpg(self.process.pid, sig)
            except ProcessLookupError:
                pass
            if sig == signal.SIGTERM:
                try:
                    self.process.wait(timeout=1)
                except subprocess.TimeoutExpired:
                    pass
        self.process.wait()
        self.selector.close()
        self.process.stdin.close()
        self.process.stdout.close()


def find_cli(name):
    found = shutil.which(name)
    if found:
        return found
    home = pathlib.Path.home()
    candidates = [home / ".local/bin" / name, pathlib.Path("/opt/homebrew/bin") / name,
                  pathlib.Path("/usr/local/bin") / name]
    candidates += sorted(home.glob(".nvm/versions/node/*/bin/" + name), reverse=True)
    return next((str(p) for p in candidates if p.is_file() and os.access(str(p), os.X_OK)), None)


def probe(provider, executable, timeout=25):
    env = dict(os.environ)
    # Model discovery must never upgrade either the running or installed CLI.
    env["DISABLE_AUTOUPDATER"] = "1"
    for key in ("CLAUDECODE", "CODEX_THREAD_ID", "CMUX_WORKSPACE_ID", "CMUX_SURFACE_ID"):
        env.pop(key, None)
    # npm launchers use /usr/bin/env node; launchd's PATH does not include nvm.
    node = find_cli("node")
    dirs = [str(pathlib.Path(executable).parent)]
    if node:
        dirs.append(str(pathlib.Path(node).parent))
    env["PATH"] = os.pathsep.join(dirs + [env.get("PATH", "/usr/bin:/bin")])
    with tempfile.TemporaryDirectory(prefix="cmux-model-catalog-") as cwd:
        version_process = JSONProcess([executable, "--version"], cwd, env, 4, max_output=4096)
        try:
            version = None
            while version is None:
                line = version_process.read_line()
                match = re.search(rb"\b(\d+\.\d+\.\d+(?:[-+][A-Za-z0-9.-]+)?)\b", line)
                if match:
                    version = match.group(1).decode()
        except EOFError:
            pass
        finally:
            version_process.close()
        if provider == "claude":
            args = [executable, "--safe-mode", "--print", "--input-format", "stream-json",
                    "--output-format", "stream-json", "--verbose", "--no-session-persistence",
                    "--permission-prompts", "none"]
        else:
            # No thread/start or turn/start request is ever sent. Explicitly suppress
            # integrations as well as using a neutral cwd, even with user config loaded.
            args = [executable, "app-server", "-c", "mcp_servers={}", "-c", "plugins={}",
                    "-c", "features.hooks=false", "-c", "features.apps=false",
                    "-c", "features.plugins=false"]
        child = JSONProcess(args, cwd, env, timeout)
        try:
            if provider == "claude":
                child.send({"type": "control_request", "request_id": "models-probe",
                            "request": {"subtype": "initialize"}})
                while True:
                    value = child.read()
                    response = value.get("response", {})
                    if value.get("type") != "control_response" or not isinstance(response, dict):
                        continue
                    if response.get("request_id") != "models-probe":
                        continue
                    if response.get("subtype") != "success":
                        raise ProbeError("protocol_unavailable")
                    body = response.get("response", {})
                    if not isinstance(body, dict):
                        raise ProbeError("invalid_response")
                    return version, models_from(provider, body.get("models"))
            child.send({"id": 1, "method": "initialize", "params": {
                "clientInfo": {"name": "cmux-model-catalog", "version": "1.0"}}})
            request_id, models, cursors = 1, [], set()
            while True:
                value = child.read()
                if value.get("id") != request_id:
                    continue
                if "error" in value:
                    raise ProbeError("protocol_unavailable")
                body = value.get("result", {})
                if not isinstance(body, dict):
                    raise ProbeError("invalid_response")
                if request_id == 1:
                    child.send({"method": "initialized", "params": {}})
                    cursor = None
                else:
                    page = body.get("data")
                    if not isinstance(page, list):
                        raise ProbeError("invalid_response")
                    models.extend(page)
                    if len(models) > 512:
                        raise ProbeError("response_too_large")
                    cursor = body.get("nextCursor")
                    if cursor is None:
                        return version, models_from(provider, models)
                    cursor = clean_text(cursor, 1024)
                    if cursor in cursors or len(cursors) >= 20:
                        raise ProbeError("invalid_response")
                    cursors.add(cursor)
                request_id += 1
                params = {"includeHidden": False, "limit": 100}
                if cursor is not None:
                    params["cursor"] = cursor
                child.send({"id": request_id, "method": "model/list", "params": params})
        finally:
            child.close()


def prior_public(row):
    result = {}
    for key in ("updatedAt", "changedAt"):
        value = row.get(key)
        if isinstance(value, str) and len(value) <= 40:
            try:
                parsed = datetime.datetime.fromisoformat(value.replace("Z", "+00:00"))
                if parsed.tzinfo is not None:
                    result[key] = value
            except ValueError:
                pass
    for key, pattern in (("cliVersion", r"\d+\.\d+\.\d+(?:[-+][A-Za-z0-9.-]+)?"),
                         ("fingerprint", r"[a-f0-9]{64}")):
        value = row.get(key)
        if isinstance(value, str) and len(value) <= 80 and re.fullmatch(pattern, value):
            result[key] = value
    rows = row.get("models")
    if not isinstance(rows, list) or len(rows) > 512:
        return {}
    models, seen = [], set()
    try:
        for row in rows:
            if not isinstance(row, dict):
                return {}
            ident = clean_text(row.get("id"))
            if ident in seen:
                return {}
            seen.add(ident)
            model = {"id": ident, "name": clean_text(row.get("name"))}
            efforts = row.get("reasoningEfforts")
            if not isinstance(efforts, list) or len(efforts) > 32:
                return {}
            model["reasoningEfforts"] = [clean_text(v, 80) for v in efforts]
            for key in ("resolvedModel", "defaultEffort"):
                if row.get(key) is not None:
                    model[key] = clean_text(row[key])
            models.append(model)
    except ProbeError:
        return {}
    result["models"] = models
    return result


def refresh(previous, now, probe_fn=probe, find_fn=find_cli):
    previous = previous if isinstance(previous, dict) and previous.get("schemaVersion") == 1 else {}
    old_rows = previous.get("providers", [])
    old = {}
    if isinstance(old_rows, list):
        for row in old_rows:
            if isinstance(row, dict) and row.get("provider") in ("codex", "claude"):
                old[row["provider"]] = prior_public(row)
    providers, failed = [], False
    # Both probes are independent, each with its own process group and deadline.
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        jobs = {p: pool.submit(probe_fn, p, exe) if exe else None
                for p in ("codex", "claude") for exe in [find_fn(p)]}
        for provider, job in jobs.items():
            source = "app-server/model/list" if provider == "codex" else "sdk/initialize/models"
            row = {"provider": provider, "source": source, "checkedAt": now, "models": []}
            prior = old.get(provider, {})
            # Only our public schema survives a failed refresh, never native payloads.
            row.update(prior)
            if job is None:
                row.update(status="unavailable", error="cli_not_installed")
            else:
                try:
                    version, models = job.result()
                    canonical = json.dumps(sorted(models, key=lambda m: m["id"]),
                                           sort_keys=True, separators=(",", ":"))
                    fingerprint = hashlib.sha256(canonical.encode()).hexdigest()
                    row.update(status="ok", models=models, updatedAt=now, fingerprint=fingerprint,
                               changedAt=prior.get("changedAt", now) if prior.get("fingerprint") == fingerprint else now)
                    row.pop("cliVersion", None)
                    if version:
                        row["cliVersion"] = version
                except ProbeError as error:
                    row.update(status="error", error=str(error))
                    failed = True
                except Exception:
                    # Exceptions may include paths, arguments or credentials. Never persist them.
                    row.update(status="error", error="probe_failed")
                    failed = True
            providers.append(row)
    return {"schemaVersion": 1, "checkedAt": now, "providers": providers}, failed


def atomic_save(path, value):
    fd, temporary = tempfile.mkstemp(prefix=".agent-models-", dir=str(path.parent))
    try:
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, "w") as stream:
            json.dump(value, stream, separators=(",", ":"), ensure_ascii=False)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config-dir", type=pathlib.Path, required=True)
    args = parser.parse_args()
    args.config_dir.mkdir(mode=0o700, parents=True, exist_ok=True)
    lock_fd = os.open(str(args.config_dir / "agent-models.lock"), os.O_CREAT | os.O_RDWR, 0o600)
    with os.fdopen(lock_fd, "w") as lock:
        os.fchmod(lock.fileno(), 0o600)
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return 75
        path = args.config_dir / "agent-models.json"
        try:
            previous = json.loads(path.read_bytes()) if path.stat().st_size <= 2 * 1024 * 1024 else {}
        except (OSError, ValueError):
            previous = {}
        now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
        value, failed = refresh(previous, now)
        atomic_save(path, value)
        return 1 if failed else 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError):
        # Watchdog retries; do not log native process output or credential-bearing errors.
        raise SystemExit(1)
