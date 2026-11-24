"""订阅发布器：原子写 + 自验 + 版本保留 + 回滚；失败一律 fail-closed。"""

import os
import shutil

from .crawler import parse_surge_line
from .rules import is_private, load_private_hosts


def self_check(lines, private_hosts, max_lines):
    """返回 (ok, error)：只检查结构与身份，绝不输出行内容。"""
    if not lines:
        return (False, "empty publish refused")
    if len(lines) > max_lines:
        return (False, "over max lines")
    names = set()
    for line in lines:
        name, proto, host, port, ok = parse_surge_line(line)
        if not ok or not name:
            return (False, "malformed line")
        if name in names:
            return (False, "duplicate name")
        names.add(name)
        if is_private(host, private_hosts):
            return (False, "private host in publish")
    return (True, "")


def atomic_publish(publish_dir, filename, lines):
    os.makedirs(publish_dir, exist_ok=True)
    target = os.path.join(publish_dir, filename)
    prev = target + ".prev"
    tmp = target + ".tmp"
    with open(tmp, "w") as f:
        for line in lines:
            f.write(line + "\n")
        f.flush()
        os.fsync(f.fileno())
    os.chmod(tmp, 0o600)
    if os.path.exists(target):
        shutil.copyfile(target, prev)
        try:
            os.chmod(prev, 0o600)
        except OSError:
            pass
    os.rename(tmp, target)
    try:
        dfd = os.open(publish_dir, os.O_DIRECTORY)
        try:
            os.fsync(dfd)
        finally:
            os.close(dfd)
    except OSError:
        pass
    return target


def rollback(publish_dir, filename):
    target = os.path.join(publish_dir, filename)
    prev = target + ".prev"
    if not os.path.exists(prev):
        return (False, "no prev version")
    tmp = target + ".tmp"
    shutil.copyfile(prev, tmp)
    try:
        os.chmod(tmp, 0o600)
    except OSError:
        pass
    os.rename(tmp, target)
    return (True, "")


def read_publish_lines(publish_dir, filename):
    target = os.path.join(publish_dir, filename)
    if not os.path.exists(target):
        return []
    with open(target) as f:
        return [l.rstrip("\n") for l in f if l.strip()]
