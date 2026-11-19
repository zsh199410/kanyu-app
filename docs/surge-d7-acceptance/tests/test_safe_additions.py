"""Non-deleting, VPS-trusted additive rotation isolated tests."""
from __future__ import annotations
import importlib.util
from pathlib import Path
import unittest

F=Path(__file__).resolve().parent.parent/"single-writer"
sp=importlib.util.spec_from_file_location("surge_safe_additions",F/"safe_additions.py")
mod=importlib.util.module_from_spec(sp)
sp.loader.exec_module(mod)

NOW=1800000000
PINS=[("trojan",f"192.0.2.{i}",440+i) for i in range(1,22)]
OLD=("trojan","198.51.100.5",443)
NEW=("trojan","198.51.100.6",443)

def line(name,key):
    return f"{name} = trojan, {key[1]}, {key[2]}, password=test123"

def parse(value):
    parts=[v.strip() for v in value.split("=",1)[1].split(",")]
    return parts[0],parts[1],int(parts[2])

def makepool(entries):
    return ("\n".join(line(n,k) for n,k in entries)+"\n").encode()

def data():
    return {"db_pins":{k:f"美国{i}" for i,k in enumerate(PINS,start=1)},
            "blocked_keys":set(),
            "node_rows":[{"key":NEW,"last_result":"pass",
                          "last_test_at":NOW-15,
                          "pass_count":8,"test_count":10,
                          "first_seen":NOW-100}],
            "latest_pass_ms":{NEW:199}}

def config():
    return {"publish_max_lines":150,"per_country_cap":40,
            "publish_fresh_hours":24,"publish_max_vps_ms":300,
            "publish_min_pass_rate":0.5}

def pairs():
    return [(f"美国{i}",k) for i,k in enumerate(PINS,start=1)]

class OverlayTests(unittest.TestCase):
    def args(self,**kwargs):
        x={"current":makepool(pairs()+[("旧-1",OLD)]),
           "proposed":makepool(pairs()+[("新-1",NEW)]),
           "db_snapshot":data(),"config":config(),
           "parse_fn":parse,"country_fn":lambda n:"US","now":NOW}
        x.update(kwargs)
        return x

    def test_additive_preserves_old_and_adds_trusted_one(self):
        args=self.args()
        result=mod.safe_overlay(**args)
        self.assertEqual(result["added_count"],1)
        self.assertEqual(result["retained_count"],22)
        self.assertEqual(result["candidate_count"],23)
        self.assertEqual(result["protected_count"],21)
        self.assertTrue(result["candidate_bytes"].startswith(args["current"]))
        self.assertIn("旧-1",result["candidate_bytes"].decode())
        self.assertIn("新-1",result["candidate_bytes"].decode())
        self.assertFalse(result["production_write_authorized"])
        self.assertFalse(result["auto_delete_authorized"])

    def test_only_removal_requested_returns_exact_current_bytes(self):
        old=makepool(pairs()+[("旧-1",OLD)])
        x=mod.safe_overlay(**self.args(current=old,proposed=makepool(pairs())))
        self.assertEqual(x["candidate_bytes"],old)
        self.assertEqual(x["added_count"],0)
        self.assertEqual(x["decision"],"HOLD_NO_ADDITIONS")

    def test_vps_slow_candidate_refused(self):
        x=self.args()
        x["db_snapshot"]["latest_pass_ms"][NEW]=301
        with self.assertRaisesRegex(mod.AdditionRefused,"new_node_lacks_fresh_vps_evidence"):
            mod.safe_overlay(**x)

    def test_uncertain_freshness_refused(self):
        x=self.args()
        x["db_snapshot"]["node_rows"][0]["last_test_at"]=NOW-25*3600
        with self.assertRaisesRegex(mod.AdditionRefused,"new_node_lacks_fresh_vps_evidence"):
            mod.safe_overlay(**x)

    def test_wrong_pass_rate_refused(self):
        x=self.args()
        x["db_snapshot"]["node_rows"][0]["pass_count"]=1
        with self.assertRaisesRegex(mod.AdditionRefused,"new_node_lacks_fresh_vps_evidence"):
            mod.safe_overlay(**x)

    def test_blocklisted_new_refused(self):
        x=self.args()
        x["db_snapshot"]["blocked_keys"].add(NEW)
        with self.assertRaisesRegex(mod.AdditionRefused,"blocked_proxy_in_proposal"):
            mod.safe_overlay(**x)

    def test_new_name_conflicting_with_old_refused(self):
        x=self.args()
        x["proposed"]=makepool(pairs()+[("旧-1",NEW)])
        with self.assertRaisesRegex(mod.AdditionRefused,"new_node_name_collision"):
            mod.safe_overlay(**x)

    def test_missing_pin_in_preview_refused(self):
        x=self.args()
        x["proposed"]=makepool(pairs()[:-1]+[("新-1",NEW)])
        with self.assertRaisesRegex(mod.AdditionRefused,"pinned_definition_changed"):
            mod.safe_overlay(**x)

    def test_changed_pin_declaration_refused(self):
        x=self.args()
        corrupted=x["proposed"].replace(b"192.0.2.1,",b"192.0.2.32,")
        x["proposed"]=corrupted
        with self.assertRaisesRegex(mod.AdditionRefused,"pinned_definition_changed"):
            mod.safe_overlay(**x)

    def test_wrong_current_pin_identity_refused(self):
        x=self.args()
        x["current"]=x["current"].replace("美国1 =".encode(),"CHANGED =".encode())
        with self.assertRaisesRegex(mod.AdditionRefused,"pinned_identity_missing"):
            mod.safe_overlay(**x)

    def test_more_than_four_new_refused(self):
        x=self.args()
        extra=[(f"新{i}",("trojan",f"203.0.113.{i}",440+i)) for i in range(5)]
        x["proposed"]=makepool(pairs()+[("新-1",NEW)]+extra)
        with self.assertRaisesRegex(mod.AdditionRefused,"additions_exceed_four"):
            mod.safe_overlay(**x)

    def test_max_lines_safety(self):
        x=self.args()
        x["config"]["publish_max_lines"]=22
        with self.assertRaisesRegex(mod.AdditionRefused,"pool_limit_exceeded"):
            mod.safe_overlay(**x)

    def test_no_actual_mutation_of_inputs(self):
        x=self.args()
        before=x["current"]
        mod.safe_overlay(**x)
        self.assertEqual(x["current"],before)

    def test_noncanonical_newline_refused(self):
        x=self.args()
        x["current"]=x["current"].rstrip(b"\n")
        with self.assertRaisesRegex(mod.AdditionRefused,"pool_newline_not_canonical"):
            mod.safe_overlay(**x)

if __name__=="__main__":
    unittest.main()
