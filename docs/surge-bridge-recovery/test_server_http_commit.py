"""C-stage explicit HTTP 503 on uncertain commit; no real server."""
from __future__ import annotations
import unittest
import server_http_commit as h

ID=1795063030
def fixture():
    return {"cmd":{"id":ID,"actions":[]},
            "result":{"at":1,"data":{"id":12,"outputs":[]}},
            "last_poll":12,"polls":24}
def result(id_=ID):
    return {"id":id_,"timestamp":1795064000,"outputs":[]}

class CommitTests(unittest.TestCase):
    def test_commit_written_before_ack(self):
        state=fixture()
        persisted=[]
        def store(next_state):
            persisted.append(next_state)
            self.assertIsNone(next_state["cmd"])
        status,body=h.post_result(state,result(),now=20,persist=store)
        self.assertEqual(status,200)
        self.assertTrue(body["accepted"])
        self.assertEqual(len(persisted),1)
        self.assertIsNotNone(state["cmd"])

    def test_explicit_503_after_disk_failure_not_fake_ack(self):
        old=fixture()
        def fail(next_state):
            raise OSError("private path should never be exposed")
        status,body=h.post_result(old,result(),now=20,persist=fail)
        self.assertEqual(status,503)
        self.assertFalse(body["accepted"])
        self.assertEqual(body["commit_state"],"unknown")
        self.assertNotIn("private",str(body))
        self.assertEqual(old["cmd"]["id"],ID)

    def test_503_even_if_persist_wrote_then_failed(self):
        state=fixture()
        durable=[]
        def store_then_throw(next_state):
            durable.append(next_state)
            raise OSError("ACK lost after filesystem completed")
        status,body=h.post_result(state,result(),now=20,persist=store_then_throw)
        self.assertEqual(status,503)
        self.assertEqual(body["commit_state"],"unknown")
        self.assertIsNone(durable[0]["cmd"])
        self.assertEqual(state["cmd"]["id"],ID)

    def test_no_write_on_wrong_id(self):
        state=fixture()
        called=[]
        status,body=h.post_result(state,result(ID+1),now=20,
                                 persist=lambda data:called.append(data))
        self.assertEqual(status,409)
        self.assertFalse(body["accepted"])
        self.assertEqual(called,[])

    def test_no_write_on_idempotent_duplicate(self):
        state=fixture()
        committed=[]
        h.post_result(state,result(),now=20,persist=lambda s:committed.append(s))
        again=[]
        status,body=h.post_result(committed[0],result(),now=22,
                                 persist=lambda s:again.append(s))
        self.assertEqual(status,200)
        self.assertTrue(body["duplicate"])
        self.assertEqual(again,[])

    def test_diagnostic_503_never_clears_old_pending(self):
        state=fixture()
        posted={"code":"LEGACY_PENDING_FENCED","command_id":ID,
                "legacy_last_id":ID,"phase":"none"}
        status,body=h.post_diagnostic(state,posted,now=30,
                                     persist=lambda s:(_ for _ in ()).throw(OSError("disk")))
        self.assertEqual(status,503)
        self.assertEqual(state["cmd"]["id"],ID)

    def test_diagnostic_success_keeps_result_and_cmd(self):
        state=fixture()
        posted={"code":"LEGACY_PENDING_FENCED","command_id":ID,
                "legacy_last_id":ID,"phase":"none"}
        stored=[]
        status,body=h.post_diagnostic(state,posted,now=30,
                                     persist=lambda s:stored.append(s))
        self.assertEqual(status,200)
        self.assertEqual(stored[0]["cmd"],state["cmd"])
        self.assertEqual(stored[0]["result"],state["result"])

    def test_get_receipt_readonly_no_persistence(self):
        state=fixture()
        status,body=h.get_receipt(state,ID)
        self.assertEqual(status,200)
        self.assertFalse(body["confirmed"])
        self.assertEqual(state["cmd"]["id"],ID)

    def test_issue_without_pending_rejected_no_commit(self):
        state=fixture()
        called=[]
        status,body=h.post_issue(state,{"id":ID+1,"actions":[]},
                                 now=25,persist=lambda s:called.append(s))
        self.assertEqual(status,409)
        self.assertEqual(called,[])

    def test_persister_explicit_false_never_acks(self):
        state=fixture()
        status,body=h.post_result(state,result(),now=25,
                                  persist=lambda updated:False)
        self.assertEqual(status,503)
        self.assertFalse(body["accepted"])
        self.assertEqual(body["commit_state"],"unknown")
        self.assertEqual(state["cmd"]["id"],ID)

    def test_missing_persister_never_acknowledges(self):
        state=fixture()
        status,body=h.post_result(state,result(),now=25,persist=None)
        self.assertEqual(status,503)
        self.assertEqual(body["commit_state"],"unknown")

if __name__=="__main__":
    unittest.main()
