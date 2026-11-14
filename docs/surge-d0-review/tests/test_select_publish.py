"""Unit tests for pool/rules.py select_publish with allowed_fingerprints.

Uses a stub IpApi (no network) and synthetic records. No production files
are touched. No secrets, URIs, or credentials appear in any test.
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from pool import phone_gate
from pool.rules import select_publish


class StubIpApi:
    def country(self, host):
        return ("HK", "Hong Kong")


def run():
    passed = []
    failed = []

    def check(label, cond):
        if cond:
            passed.append(label)
            print("PASS %s" % label)
        else:
            failed.append(label)
            print("FAIL %s" % label)

    ipapi = StubIpApi()
    blocked = set()
    private = set()

    # Pinned lines (verbatim text) and rotation records.
    pinned_lines = [
        ("PinnedA", "trojan", "pa.invalid", 443,
         "PinnedA = trojan, pa.invalid, 443, password=pw1"),
        ("PinnedB", "trojan", "pb.invalid", 443,
         "PinnedB = trojan, pb.invalid, 443, password=pw2"),
    ]
    rotation_items = [
        ({"protocol": "trojan", "host": "ra.invalid", "port": 443,
          "password": "pw3", "name_hint": ""}, 0.9, 1000),
        ({"protocol": "ss", "host": "rb.invalid", "port": 8388,
          "method": "aes-256-gcm", "password": "pw4", "name_hint": ""}, 0.8, 1001),
    ]

    # --- 1. No gate: behaviour unchanged (all pinned + rotation kept) ---
    lines, stats = select_publish(pinned_lines, rotation_items, blocked,
                                  private, 40, 150, ipapi)
    check("no_gate_keeps_all", len(lines) == 4)
    check("no_gate_stats", stats["pinned"] == 2 and stats["rotation"] == 2
          and stats["gate_skipped"] == 0)

    # --- 2. Gate: only fingerprints in the set publish ---
    def fp_of_line(text):
        parsed = phone_gate.parse_surge_line(text)
        return phone_gate.fingerprint_of(parsed[1], parsed[2], parsed[3], parsed[4])

    # Build the rotation lines the same way select_publish would, to get
    # their fingerprints. (Use build_surge_line directly.)
    from pool.rules import build_surge_line
    rot_line_a = build_surge_line(rotation_items[0][0], "RotA")
    rot_line_b = build_surge_line(rotation_items[1][0], "RotB")
    fp_pinned_a = fp_of_line(pinned_lines[0][4])
    fp_rot_b = fp_of_line(rot_line_b)
    allowed = {fp_pinned_a, fp_rot_b}
    lines2, stats2 = select_publish(pinned_lines, rotation_items, blocked,
                                    private, 40, 150, ipapi,
                                    allowed_fingerprints=allowed)
    check("gate_keeps_only_allowed", len(lines2) == 2)
    check("gate_keeps_verified_pinned",
          any("pa.invalid" in l for l in lines2))
    check("gate_drops_unverified_pinned",
          all("pb.invalid" not in l for l in lines2))
    check("gate_keeps_verified_rotation",
          any("rb.invalid" in l for l in lines2))
    check("gate_drops_unverified_rotation",
          all("ra.invalid" not in l for l in lines2))
    check("gate_skipped_count", stats2["gate_skipped"] == 2)

    # --- 3. Gate with empty set: nothing publishes ---
    lines3, stats3 = select_publish(pinned_lines, rotation_items, blocked,
                                    private, 40, 150, ipapi,
                                    allowed_fingerprints=set())
    check("gate_empty_set_publishes_nothing", lines3 == [])
    check("gate_empty_set_counts", stats3["gate_skipped"] == 4)

    # --- 4. Blocklist still wins even when the fingerprint is allowed ---
    blocked2 = {("trojan", "pa.invalid", 443)}
    lines4, stats4 = select_publish(pinned_lines, rotation_items, blocked2,
                                    private, 40, 150, ipapi,
                                    allowed_fingerprints=allowed)
    check("blocklist_still_wins",
          all("pa.invalid" not in l for l in lines4))
    check("blocklist_counted", stats4["blocked_skipped"] == 1)

    # --- 5. Same display name, different fingerprint: distinguished ---
    pinned_same_name = [
        ("Same", "trojan", "sa.invalid", 443,
         "Same = trojan, sa.invalid, 443, password=pwA"),
        ("Same", "trojan", "sb.invalid", 443,
         "Same = trojan, sb.invalid, 443, password=pwB"),
    ]
    fp_sa = fp_of_line(pinned_same_name[0][4])
    lines5, stats5 = select_publish(pinned_same_name, [], blocked,
                                    private, 40, 150, ipapi,
                                    allowed_fingerprints={fp_sa})
    check("same_name_distinguished_by_fp",
          len(lines5) == 1 and "sa.invalid" in lines5[0])
    check("same_name_other_dropped", stats5["gate_skipped"] == 1)

    print("\nselect_publish: %d passed, %d failed" % (len(passed), len(failed)))
    return 0 if not failed else 1


if __name__ == "__main__":
    raise SystemExit(run())
