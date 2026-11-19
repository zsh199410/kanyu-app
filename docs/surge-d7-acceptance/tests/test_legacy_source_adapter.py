"""Legacy installed-function adapter, mocked and no actual external HTTP."""
from __future__ import annotations
import importlib.util
from pathlib import Path
import tempfile
import unittest
from types import SimpleNamespace

F = Path(__file__).resolve().parent.parent / "single-writer"
spec = importlib.util.spec_from_file_location("surge_legacy_source_adapter", F / "legacy_source_adapter.py")
adapt = importlib.util.module_from_spec(spec)
spec.loader.exec_module(adapt)

NOW = 1800000000
PINS = [("trojan", f"192.0.2.{i}", 440+i) for i in range(1,22)]
OLD = ("trojan", "198.51.100.10", 443)
NEW = ("trojan", "198.51.100.11", 443)


def line(name,k):
    return f"{name} = trojan, {k[1]}, {k[2]}, password=test123"


def parse(l):
    try:
        n, rhs = l.split("=", 1)
        p = [s.strip() for s in rhs.split(",")]
        return n.strip(), p[0], p[1], int(p[2]), True
    except Exception:
        return None, None, None, None, False


def snapshot():
    return {
        "config_raw": {"publish_max_lines": "150", "per_country_cap": "40"},
        "node_rows": [
            {"key": k, "last_result":"pass", "last_test_at":NOW-10,
             "pass_count":10,"test_count":10,"first_seen":i}
            for i,k in enumerate([OLD,NEW])
        ],
        "latest_pass_ms": {OLD:190, NEW:180},
        "db_pins": {},
        "blocked_keys": set(),
        "winner_reports": [],
        "first_published": {},
    }


def modules():
    crawler = SimpleNamespace(parse_surge_line=parse, crawl_records=lambda path,skip=None: ([],{}))
    rules = SimpleNamespace(
        pre_filter=lambda rec,priv:(True,""),
        build_surge_line=lambda rec,name:line(name,rec["key"]),
        assign_names=lambda rows, used, ipapi:[
            (record, f"新-{i}", "US") for i,(record,rate,ts) in enumerate(rows)],
        load_private_hosts=lambda p:set()
    )
    geo = SimpleNamespace(IpApi=lambda:object(),
                          hint_to_code=lambda n: "US")
    winner = SimpleNamespace(clean_rotation=lambda *a: (a[0],set()))
    return crawler,rules,geo,winner


def yaml_loader(_):
    return {
        "publish_max_lines":150,"per_country_cap":40,
        "publish_fresh_hours":24,"publish_max_vps_ms":300,
        "publish_min_pass_rate":0.5,"winner_clean_enabled":False,
        "winner_clean_window_days":1,"winner_clean_min_winner_days":1,
        "vmess_tls_only":True,"disabled_sources":[]
    }


class AdapterTests(unittest.TestCase):
    def setup_root(self,d):
        root = Path(d)
        (root / "config.yaml").write_text("unused: valid",encoding="utf8")
        (root / "private-hosts.txt").write_text("# test denylist",encoding="utf8")
        return root

    def make_preview(self,root,**kw):
        return adapt.make_preview(
            db_snapshot=snapshot(),
            current_pool=("\n".join(
                [line(f"美国{i}",k) for i,k in enumerate(PINS,start=1)]
                + [line("旧-1",OLD)])+"\n").encode(),
            legacy_root=str(root), now=NOW,
            modules=modules(),
            fresh_record_provider=lambda root, cfg:[{"key":NEW, "protocol":NEW[0],
                                                     "host":NEW[1], "port":NEW[2]}],
            pinned_lines_provider=lambda root:[
                line(f"美国{i}", k) for i,k in enumerate(PINS,start=1)],
            yaml_loader=yaml_loader, **kw)

    def test_callback_wiring_creates_pure_preview(self):
        with tempfile.TemporaryDirectory() as d:
            root=self.setup_root(d)
            out=self.make_preview(root)
            self.assertEqual(out["proposed_count"],23)
            self.assertEqual(out["canonical_pin_count"],21)
            self.assertEqual(out["kept_old_count"],1)
            self.assertEqual(out["new_count"],1)
            self.assertFalse(out["production_write_authorized"])
            self.assertEqual(out["decision"],"PREVIEW_ONLY_NOT_ADMITTED")

    def test_disabled_source_config_parses_json(self):
        with tempfile.TemporaryDirectory() as d:
            root=self.setup_root(d)
            cfg=adapt.normalize_config(
                root/"config.yaml",
                {"disabled_sources":'["source1","source2"]'},yaml_loader=yaml_loader)
            self.assertEqual(cfg["disabled_sources"],["source1","source2"])

    def test_invalid_config_rejected(self):
        with tempfile.TemporaryDirectory() as d:
            root=self.setup_root(d)
            with self.assertRaisesRegex(adapt.LegacyAdapterRefused,"invalid_disabled_sources"):
                adapt.normalize_config(root/"config.yaml",
                    {"disabled_sources":"not-json"},yaml_loader=yaml_loader)

    def test_missing_config_rejected(self):
        with tempfile.TemporaryDirectory() as d:
            with self.assertRaisesRegex(adapt.LegacyAdapterRefused,"missing_legacy_yaml"):
                adapt.normalize_config(Path(d)/"missing.yml",{},yaml_loader=yaml_loader)

    def test_parser_rejects_malformed_proxy(self):
        with self.assertRaisesRegex(adapt.LegacyAdapterRefused,"legacy_proxy_line_invalid"):
            adapt._parse_fn(modules()[0])("not a proxy")

    def test_winner_clean_drops_old_after_grace_if_day_present(self):
        inp=snapshot()
        inp["winner_reports"]=[(NOW-30,"其他")]
        inp["first_published"]={OLD: NOW-90000}
        c=yaml_loader("")
        c["winner_clean_enabled"]=True
        out=adapt._winner_filter([line("旧-1",OLD)],snapshot=inp,
                        now=NOW,config=c,parse=lambda l: parse(l)[1:4])
        self.assertEqual(out,[])

    def test_winner_clean_grace_keeps_recent(self):
        inp=snapshot()
        inp["winner_reports"]=[(NOW-30,"其他")]
        inp["first_published"]={OLD: NOW-100}
        c=yaml_loader("")
        c["winner_clean_enabled"]=True
        out=adapt._winner_filter([line("旧-1",OLD)],snapshot=inp,
                        now=NOW,config=c,parse=lambda l: parse(l)[1:4])
        self.assertEqual(len(out),1)

    def test_invalid_import_root_rejected(self):
        with tempfile.TemporaryDirectory() as d:
            with self.assertRaisesRegex(adapt.LegacyAdapterRefused,"legacy_source_path_invalid"):
                adapt._load_installed_modules(d)


if __name__=="__main__":
    unittest.main()
