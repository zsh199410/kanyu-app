"""Adversarial isolated contract tests. No phone, network or real credentials."""
import copy
import unittest

from id_allocator_oracle import canonical_ms, plan_issue, commit_issue, MAX_SAFE, MAX_KEYS

OLD_SEC = 1795063030
OLD_MS = 1795055213880
NOW = 1795100000000
K1 = "a" * 24
K2 = "b" * 24
CMD = {"actions": [{"type": "api", "method": "GET", "path": "/synthetic"}]}


def fixture(last=NOW-10, pending=None, result=None):
    return {"cmd": pending, "result": result,
            "id_allocator": {"version": 1, "last_id": last, "keys": {}}}


def invoke(state=None, command=None, key=K1, time=NOW):
    return plan_issue(fixture() if state is None else state,
                      CMD if command is None else command,
                      request_key=key, now_ms=time)


class CanonicalContract(unittest.TestCase):
    def test_legacy_seconds_ms_order(self):
        self.assertGreater(canonical_ms(OLD_SEC), canonical_ms(OLD_MS))
    def test_same_second_one_millisecond_distinct(self):
        self.assertEqual(canonical_ms(NOW+1)-canonical_ms(NOW), 1)
    def test_bad_unit_11_12_digits_fail(self):
        for v in (99999999999, 999999999999, 0, 1):
            with self.subTest(v=v), self.assertRaises(ValueError): canonical_ms(v)
    def test_non_integer_fail(self):
        for v in (True, False, "1795063030", 1795063030.0, None):
            with self.subTest(v=v), self.assertRaises(ValueError): canonical_ms(v)


class IssuerContract(unittest.TestCase):
    def test_initial_issue_is_durable_transition_not_mutation(self):
        s=fixture(); before=copy.deepcopy(s)
        updated,code,r,w=invoke(s)
        self.assertEqual(code,200); self.assertTrue(w)
        self.assertEqual(s,before); self.assertEqual(updated["cmd"]["id"],NOW)
    def test_raw_caller_id_forbidden(self):
        _,code,_,w=invoke(command={"id":NOW,"actions":[]})
        self.assertEqual(code,400); self.assertFalse(w)
    def test_same_millisecond_second_issue_increments(self):
        s=fixture(); one,_,_,_=invoke(s)
        one["cmd"]=None
        two,code,r,w=invoke(one,key=K2)
        self.assertEqual((code,w,r["id"]),(200,True,NOW+1))
    def test_clock_rollback_increments(self):
        s=fixture(last=NOW+12)
        _,code,r,w=invoke(s,time=NOW-500)
        self.assertEqual((code,w,r["id"]),(200,True,NOW+13))
    def test_same_key_returns_old_id_even_when_new_pending(self):
        one,_,r,_=invoke()
        original=copy.deepcopy(one)
        _,code,receipt,w=invoke(one,time=NOW+100)
        self.assertEqual((code,w,receipt["id"]),(200,False,r["id"]))
        self.assertEqual(one,original)
    def test_key_reuse_different_actions_fails(self):
        one,_,_,_=invoke()
        cmd={"actions": [{"type":"api","path":"/other"}]}
        _,code,receipt,w=invoke(one,command=cmd)
        self.assertEqual((code,receipt["error"],w),(409,"idempotency_key_conflict",False))
    def test_pending_blocks_different_key_without_overwrite(self):
        one,_,_,_=invoke(); orig=copy.deepcopy(one)
        _,code,receipt,w=invoke(one,key=K2)
        self.assertEqual((code,receipt["error"],w),(409,"pending_command_exists",False))
        self.assertEqual(one,orig)
    def test_old_pending_not_removed(self):
        s=fixture(last=NOW-1,pending={"id":OLD_SEC,"actions":[]})
        _,code,receipt,w=invoke(s)
        self.assertEqual((code,receipt["error"],w),(409,"pending_command_exists",False))
    def test_legacy_result_high_water_detects_rollback(self):
        s=fixture(last=OLD_MS-1,result={"data":{"id":OLD_MS,"outputs":[]}})
        _,code,receipt,w=invoke(s,time=NOW)
        self.assertEqual((code,receipt["error"],w),(503,"allocator_high_water_inconsistent",False))
    def test_sec_pending_high_water_detects_rollback(self):
        s=fixture(last=OLD_MS,pending={"id":OLD_SEC,"actions":[]})
        _,code,r,w=invoke(s)
        self.assertEqual((code,r["error"],w),(503,"allocator_high_water_inconsistent",False))
    def test_missing_allocator_fail_closed(self):
        _,code,r,w=invoke({"cmd":None,"result":None})
        self.assertEqual((code,r["error"],w),(503,"allocator_uninitialized_or_corrupt",False))
    def test_corrupt_allocator_fail_closed(self):
        s=fixture();s["id_allocator"]["last_id"]="1795"
        _,code,r,w=invoke(s)
        self.assertEqual((code,r["error"],w),(503,"allocator_uninitialized_or_corrupt",False))
    def test_corrupt_history_fail_closed(self):
        s=fixture();s["id_allocator"]["keys"]["faked"]={"id":NOW+100,"digest":"0"*64}
        _,code,r,w=invoke(s)
        self.assertEqual((code,r["error"],w),(503,"allocator_history_corrupt",False))
    def test_invalid_now_fails(self):
        for value in (True, 0, "1795", 1795063030, 10**14):
            with self.subTest(value=value):
                _,code,_,w=invoke(time=value)
                self.assertEqual((code,w),(503,False))
    def test_invalid_key_fails(self):
        for key in ("short", "x"*129, None, "non-ASCII-密钥"):
            with self.subTest(key=key):
                _,code,_,w=invoke(key=key)
                self.assertEqual((code,w),(400,False))
    def test_command_non_json_fails(self):
        _,code,_,w=invoke(command={"actions":[],"bad":{2,1}})
        self.assertEqual((code,w),(400,False))
    def test_history_full_fails_closed(self):
        s=fixture();s["id_allocator"]["keys"]={str(i):{"id":NOW-50,"digest":"0"*64} for i in range(MAX_KEYS)}
        _,code,r,w=invoke(s)
        self.assertEqual((code,r["error"],w),(503,"idempotency_history_full",False))
    def test_success_ack_after_persist_only(self):
        calls=[]
        def persist(x): calls.append(copy.deepcopy(x));return True
        status,r=commit_issue(fixture(),CMD,request_key=K1,now_ms=NOW,persist=persist)
        self.assertEqual(status,200);self.assertEqual(len(calls),1)
        self.assertEqual(r["id"],calls[0]["cmd"]["id"])
    def test_disk_failure_never_fake_ack(self):
        status,r=commit_issue(fixture(),CMD,request_key=K1,now_ms=NOW,
                              persist=lambda x: False)
        self.assertEqual((status,r["commit_state"]),(503,"unknown"))
    def test_ack_lost_post_commit_same_key_only_returns_old_id(self):
        saved=[]
        def persist_then_throw(x):saved.append(x);raise OSError("disk completed but response lost")
        status,r=commit_issue(fixture(),CMD,request_key=K1,now_ms=NOW,persist=persist_then_throw)
        self.assertEqual((status,r["commit_state"]),(503,"unknown"))
        _,code,replayed,w=invoke(saved[0],time=NOW+100)
        self.assertEqual((code,replayed["id"],w),(200,NOW,False))
    def test_no_commit_callable_503(self):
        status,r=commit_issue(fixture(),CMD,request_key=K1,now_ms=NOW,persist=None)
        self.assertEqual((status,r["commit_state"]),(503,"unknown"))
    def test_sequential_reboot_state_no_duplicate(self):
        one,_,r,_=invoke()
        rebooted=copy.deepcopy(one)
        rebooted["cmd"]=None
        two,_,r2,_=invoke(rebooted,key=K2,time=NOW)
        self.assertEqual((r["id"],r2["id"]),(NOW,NOW+1))
    def test_max_safe_rejected_ambiguous_timestamp(self):
        s=fixture(last=MAX_SAFE)
        _,code,_,w=invoke(s,time=NOW)
        self.assertEqual((code,w),(503,False))
    def test_concurrent_requires_external_lock(self):
        s=fixture()
        a,_,r1,_=invoke(s,key=K1)
        b,_,r2,_=invoke(s,key=K2)
        # Demonstrates limitation: same stale snapshot chooses same ID.
        # The production caller MUST serialize lock+commit.
        self.assertEqual(r1["id"],r2["id"])
        self.assertEqual(a["cmd"]["id"],b["cmd"]["id"])


if __name__ == "__main__":
    unittest.main()
