# -*- coding: utf-8 -*-
"""Non-destructive overlay for a VPS-proven candidate proposal.

The new generator may discover additions while older uncalibrated phone
evidence prohibits auto-removal. Keep every byte of the current pool and
append at most four independently VPS-eligible fresh nodes. Ignore any
attempted rotation pruning; do not silently edit old proxy declarations.
Changes are not phone-native calibrated and are NEVER auto-deletions.

This function is pure. Production writer release/STOP, source authenticity,
candidate SHA revalidation and rollback are separate mandatory gates.
"""
from __future__ import annotations
from collections import Counter
import hashlib
import importlib.util
import math
from pathlib import Path

class AdditionRefused(ValueError):
    pass

def _import_core():
    p=Path(__file__).resolve().with_name("build_candidate.py")
    sp=importlib.util.spec_from_file_location("_surge_addition_core",p)
    m=importlib.util.module_from_spec(sp)
    sp.loader.exec_module(m)
    return m

def _lines(raw):
    if not isinstance(raw, bytes) or not raw or len(raw)>2*1024*1024:
        raise AdditionRefused("bad_pool_bytes")
    if not raw.endswith(b"\n") or b"\r" in raw:
        raise AdditionRefused("pool_newline_not_canonical")
    try:
        lines=[s for s in raw.decode("utf-8").splitlines()
               if s and not s.startswith("#")]
    except UnicodeError as exc:
        raise AdditionRefused("pool_invalid_utf8") from exc
    if not lines:
        raise AdditionRefused("empty_pool")
    return lines

def _parse(raw, parse_fn):
    keys, names={},{};
    for line in _lines(raw):
        name=line.split("=",1)[0].strip()
        k=parse_fn(line)
        if (not isinstance(name,str) or not name or
                not isinstance(k,tuple) or len(k)!=3 or
                k[0] not in ("trojan","vmess","ss") or
                k in keys or name in names):
            raise AdditionRefused("invalid_or_duplicate_proxy")
        keys[k]=(name,line)
        names[name]=k
    return keys,names

def safe_overlay(*, current, proposed, db_snapshot, config,
                 parse_fn, country_fn, now):
    """Return an additive-only candidate and a redaction-safe decision."""
    if not callable(parse_fn) or not callable(country_fn):
        raise AdditionRefused("missing_real_parser")
    c=_import_core()._check_config(config)
    old,oldnames=_parse(current,parse_fn)
    new,_=_parse(proposed,parse_fn)
    blocked=set(db_snapshot["blocked_keys"])
    if old.keys() & blocked:
        raise AdditionRefused("blocked_proxy_already_served")
    if new.keys() & blocked:
        raise AdditionRefused("blocked_proxy_in_proposal")
    source_pins={k:n for k,n in db_snapshot["db_pins"].items()
                 if k not in blocked}
    if len(source_pins)!=21 or len(set(source_pins.values()))!=21:
        raise AdditionRefused("pin_source_not_21")
    for k,n in source_pins.items():
        if k not in old or old[k][0]!=n:
            raise AdditionRefused("pinned_identity_missing")
        if k not in new or new[k][0]!=n or new[k][1]!=old[k][1]:
            raise AdditionRefused("pinned_definition_changed")
    if not isinstance(now,(int,float)) or isinstance(now,bool) or not math.isfinite(now):
        raise AdditionRefused("clock_invalid")
    eligible=_import_core()._eligible(
        _import_core()._normal_nodes(db_snapshot["node_rows"]),
        db_snapshot["latest_pass_ms"],c,now)
    newkeys=[k for k in new if k not in old]
    if len(newkeys)>4:
        raise AdditionRefused("additions_exceed_four")
    if len(old)+len(newkeys)>c["publish_max_lines"]:
        raise AdditionRefused("pool_limit_exceeded")
    countries=Counter()
    for name,line in old.values():
        countries[country_fn(name) or "unknown"]+=1
    addition_lines=[]
    for k in newkeys:
        if k not in eligible:
            raise AdditionRefused("new_node_lacks_fresh_vps_evidence")
        name,line=new[k]
        if name in oldnames:
            raise AdditionRefused("new_node_name_collision")
        country=country_fn(name) or "unknown"
        if countries[country]>=c["per_country_cap"]:
            raise AdditionRefused("per_country_cap")
        countries[country]+=1
        addition_lines.append(line)
    if not addition_lines:
        merged=current
        decision="HOLD_NO_ADDITIONS"
    else:
        merged=current+("\n".join(addition_lines)+"\n").encode("utf-8")
        decision="REVIEW_VPS_ADDITIONS"
    return {
        "candidate_bytes":merged,
        "decision":decision,
        "added_count":len(addition_lines),
        "protected_count":21,
        "retained_count":len(old),
        "candidate_count":len(old)+len(addition_lines),
        "candidate_sha256":hashlib.sha256(merged).hexdigest(),
        "vps_evidence_only":True,
        "phone_native_calibrated":False,
        "auto_delete_authorized":False,
        "production_write_authorized":False,
    }
