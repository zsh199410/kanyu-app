#!/usr/bin/env python3
"""Fail-closed preflight for the real, UNLOCKED legacy pool writers.

Use as ExecStartPre on BOTH new gate services, and at the start of each
production gate wrapper. A successful preflight proves the old units were
disabled/inactive and no legacy writer was visible AT CHECK TIME. It
does not protect against an administrator manually starting an old writer
after the check. The approved handover must also block such restarts.

All output is metadata-only: no node URIs or process command lines.
"""
import json
import os
import re
import subprocess
import sys

TIMERS = ("pool-publish.timer", "pool-sync.timer")
SERVICES = ("pool-publish.service", "pool-sync.service")
PROPERTIES = "LoadState,UnitFileState,ActiveState,SubState,MainPID,ControlPID,Result,Job"

def _command(argv):
    proc = subprocess.run(argv, capture_output=True, text=True, timeout=8, check=False)
    if proc.returncode != 0:
        raise RuntimeError("command_failed")
    return proc.stdout

def unit_state(unit):
    raw = _command(("/usr/bin/systemctl", "show", "--no-pager",
                    "--property=" + PROPERTIES, unit))
    result = {}
    for line in raw.splitlines():
        if "=" in line:
            key, value = line.split("=", 1)
            result[key] = value.strip()
    return result

def process_rows():
    return _command(("/usr/bin/ps", "-eo", "pid=,args=")).splitlines()

def _bad_process(line):
    """Recognize actual legacy writer commands, not the guard itself."""
    parts = line.strip().split(None, 1)
    if len(parts) != 2 or not parts[0].isdigit():
        return None
    pid, command = parts
    if int(pid) == os.getpid():
        return None
    if re.search(r"pool[.]cli\s+publish(?:\s|$)", command):
        return pid
    if re.search(r"(?:^|[\s/])pool-sync[.]sh(?:\s|$)", command):
        return pid
    return None

def check(show=unit_state, processes=process_rows):
    """Return (allowed, reason, subject). Injection points are for tests."""
    try:
        for unit in TIMERS:
            data = show(unit)
            if data.get("LoadState") != "loaded":
                return False, "timer_not_loaded", unit
            if data.get("UnitFileState") != "disabled":
                return False, "old_timer_not_disabled", unit
            if data.get("ActiveState") != "inactive":
                return False, "old_timer_not_inactive", unit
            if data.get("Job", "") not in ("", "0"):
                return False, "old_timer_has_job", unit

        for unit in SERVICES:
            data = show(unit)
            if data.get("LoadState") != "loaded":
                return False, "service_not_loaded", unit
            if data.get("ActiveState") != "inactive" or data.get("SubState") != "dead":
                return False, "old_service_not_drained", unit
            if data.get("MainPID") != "0" or data.get("ControlPID") != "0":
                return False, "old_service_pid_present", unit
            if data.get("Job", "") not in ("", "0"):
                return False, "old_service_has_job", unit
            if data.get("Result") != "success":
                return False, "old_service_result_not_success", unit

        rows = processes()
        if not isinstance(rows, (list, tuple)):
            return False, "process_scan_invalid", "ps"
        for line in rows:
            pid = _bad_process(line)
            if pid is not None:
                return False, "legacy_writer_process_present", "pid:" + pid
    except (OSError, ValueError, RuntimeError, subprocess.TimeoutExpired):
        return False, "preflight_inspection_failed", "system"
    return True, "legacy_writers_drained", "system"

def main():
    allowed, reason, subject = check()
    print(json.dumps({"ok": allowed, "reason": reason, "subject": subject},
                     ensure_ascii=True))
    return 0 if allowed else 1

if __name__ == "__main__":
    sys.exit(main())
