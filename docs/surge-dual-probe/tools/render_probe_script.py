#!/usr/bin/env python3
"""Render the production phone script from the desensitized PR copy
(GPT #6940445042 P0-2).

The Draft PR script carries placeholders in its probe URL
(https://<probe-host>:8443/<random-path>). Copying it to the phone
as-is would ship an invalid probe address. This tool renders the
production script on the server, from PRIVATE server-local config
only:

  render conf (default /opt/probe-service/config/deploy-render.conf,
  600 perms, never copied into the PR, never printed):
      PROBE_HOST=<real probe host>          (DNS name, no scheme/port)
      NGINX_CONF=/etc/nginx/conf.d/<vhost>.conf
  path segment: /opt/probe-service/config/probe-path.txt (existing
  600 file, already used by the service and the deploy script).

Steps:
  1. read + validate host (DNS hostname), NGINX_CONF (absolute .conf
     path that exists), segment ([A-Za-z0-9_-]{8,64});
  2. substitute <probe-host> -> host and <random-path> -> segment
     (every occurrence, including the trailing comment);
  3. fail closed if ANY placeholder remains (<probe-host>,
     <random-path>, <nginx-vhost>) or if the rendered PROBE_URL does
     not equal exactly https://<host>:8443/<segment> (an input that
     already carries different real values is rejected, not trusted);
  4. recompute CLIENT_VERSION from the RENDERED content (same
     algorithm as tools/inject_sha.py: sha256 of the file with the
     constant normalized to 'dual-v1-000000000000', first 12 hex);
  5. write the output and print its full SHA256 + CLIENT_VERSION —
     the DEPLOYED product SHA. The desensitized GitHub SHA is NEVER
     the deployed product SHA, and the real host/segment are NEVER
     printed (to stdout, logs, or GitHub).

Usage:
  python3 tools/render_probe_script.py <desensitized_script> \\
      <render_conf> <seg_file> <output>
Stdlib only.
"""
import hashlib
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from inject_sha import compute_sha12, PATTERN  # noqa: E402

HOST_RE = re.compile(
    r"(?=.{1,253}$)(?!-)[A-Za-z0-9-]{1,63}(?<!-)"
    r"(\.(?!-)[A-Za-z0-9-]{1,63}(?<!-))*")
SEG_RE = re.compile(r"[A-Za-z0-9_-]{8,64}")
PLACEHOLDERS = ("<probe-host>", "<random-path>", "<nginx-vhost>")
PROBE_URL_RE = re.compile(
    r"const PROBE_URL = '(https://[^']+)'")


def _read_conf(path):
    vals = {}
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            k, v = line.split("=", 1)
            vals[k.strip()] = v.strip()
    return vals


def render(src_path, render_conf, seg_file, out_path):
    """Return (output_sha256, client_version). Raises on any failure."""
    conf = _read_conf(render_conf)
    host = conf.get("PROBE_HOST", "")
    nginx_conf = conf.get("NGINX_CONF", "")
    if not HOST_RE.fullmatch(host):
        raise ValueError("PROBE_HOST is not a valid DNS hostname")
    if not os.path.isabs(nginx_conf) or not nginx_conf.endswith(".conf"):
        raise ValueError("NGINX_CONF must be an absolute .conf path")
    if not os.path.isfile(nginx_conf):
        raise ValueError("NGINX_CONF file does not exist")
    with open(seg_file, encoding="utf-8") as f:
        seg = f.read().strip()
    if not SEG_RE.fullmatch(seg):
        raise ValueError("path segment is not a valid random path segment")
    src = open(src_path, encoding="utf-8").read()
    rendered = src.replace("<probe-host>", host).replace("<random-path>", seg)
    for ph in PLACEHOLDERS:
        if ph in rendered:
            raise ValueError(f"placeholder {ph} remains after rendering")
    if "<probe" in rendered:
        raise ValueError("unresolved <probe...> placeholder remains")
    m = PROBE_URL_RE.search(rendered)
    if not m:
        raise ValueError("PROBE_URL not found in rendered script")
    expected = f"https://{host}:8443/{seg}"
    if m.group(1) != expected:
        raise ValueError("rendered PROBE_URL does not match private config")
    # Recompute CLIENT_VERSION from the RENDERED content (same
    # algorithm as tools/inject_sha.py; idempotent when already right).
    norm = PATTERN.sub(r"\g<1>000000000000\g<3>", rendered)
    sha12 = compute_sha12(norm.encode("utf-8"))
    rendered = PATTERN.sub(r"\g<1>" + sha12 + r"\g<3>", norm)
    data = rendered.encode("utf-8")
    with open(out_path, "wb") as f:
        f.write(data)
    return hashlib.sha256(data).hexdigest(), "dual-v1-" + sha12


def main(argv):
    if len(argv) != 5:
        print("usage: render_probe_script.py <script> <render_conf> "
              "<seg_file> <output>", file=sys.stderr)
        return 2
    try:
        sha, cver = render(argv[1], argv[2], argv[3], argv[4])
    except Exception as e:
        print(f"render FAILED: {e}", file=sys.stderr)
        return 1
    print(f"render ok: {argv[4]} sha256={sha} CLIENT_VERSION={cver}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
