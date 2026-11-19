"""Isolated, no-network tests for private one-slot bridge mailbox semantics."""
from __future__ import annotations
import unittest
import mailbox_ack as m

ID=1795063030
def cmd(id=ID):
    return {"id":id,"actions":[{"type":"api","method":"GET","path":"redacted"}]}
def result(id=ID):
    return {"id":id,"timestamp":1795064000,"outputs":[{"kind":"GET","ok":True}]}
def mailbox():
    return {"cmd":cmd(),"result":{"at":10.0,"data":{"id":101}},
            "last_poll":20.0,"polls":2406}

class MailboxAckTests(unittest.TestCase):
    def test_matched_ack_persists_then_clears(self):
        old=mailbox()
        new,status,response,write=m.accept_result(old,result(),now=25.0)
        self.assertEqual(status,200)
        self.assertTrue(response["accepted"])
        self.assertEqual(response["acked_id"],ID)
        self.assertTrue(write)
        self.assertIsNone(new["cmd"])
        self.assertEqual(new["result"]["data"],result())
        self.assertEqual(old["cmd"],cmd())

    def test_duplicate_ack_is_idempotent_and_does_not_write(self):
        committed,_,_,_=m.accept_result(mailbox(),result(),now=25.0)
        new,status,body,write=m.accept_result(committed,result(),now=35.0)
        self.assertEqual(status,200)
        self.assertTrue(body["duplicate"])
        self.assertFalse(write)
        self.assertEqual(new,committed)

    def test_stale_result_never_erases_a_new_command(self):
        old=mailbox()
        new,status,body,write=m.accept_result(old,result(ID-1),now=25)
        self.assertEqual(status,409)
        self.assertFalse(write)
        self.assertEqual(new,old)
        self.assertEqual(new["cmd"],cmd())

    def test_reissued_result_with_changed_outputs_is_conflict(self):
        committed,_,_,_=m.accept_result(mailbox(),result(),now=25)
        altered=result()
        altered["outputs"].append({"extra":"changed"})
        new,status,body,write=m.accept_result(committed,altered,now=30)
        self.assertEqual(status,409)
        self.assertFalse(write)
        self.assertEqual(new,committed)

    def test_plain_bad_timestamp_boolean_id_invalid(self):
        for payload in ({"id":True,"outputs":[]},
                        {"id":0,"outputs":[]},
                        {"id":ID,"outputs":"not-a-list"}):
            with self.subTest(payload=payload):
                old=mailbox()
                new,status,body,write=m.accept_result(old,payload,now=20)
                self.assertEqual(status,400)
                self.assertFalse(write)
                self.assertEqual(new,old)

    def test_oversized_result_is_blocked(self):
        old=mailbox()
        payload=result()
        payload["outputs"]=[{"secretish":"x"*9000}]
        new,status,_,write=m.accept_result(old,payload,now=20)
        self.assertEqual(status,413)
        self.assertFalse(write)
        self.assertEqual(new,old)

    def test_diagnostic_never_clears_or_replaces_mailbox(self):
        old=mailbox()
        data={"code":"LEGACY_PENDING_FENCED","command_id":ID,
              "legacy_last_id":ID,"phase":"none"}
        new,status,body,write=m.accept_diagnostic(old,data,now=30)
        self.assertEqual(status,200)
        self.assertTrue(write)
        self.assertEqual(new["cmd"],old["cmd"])
        self.assertEqual(new["result"],old["result"])
        self.assertEqual(new["polls"],old["polls"])
        self.assertEqual(new["bridge_diagnostic"]["legacy_last_id"],ID)
        self.assertNotIn("outputs",new["bridge_diagnostic"])

    def test_diagnostic_unknown_code_rejected(self):
        old=mailbox()
        data={"code":"RUN_ME","command_id":ID,"legacy_last_id":ID,
              "phase":"none"}
        new,status,_,write=m.accept_diagnostic(old,data,now=30)
        self.assertEqual(status,400)
        self.assertFalse(write)
        self.assertEqual(new,old)

    def test_readonly_receipt_matches_result_after_lost_ack(self):
        committed,_,_,_=m.accept_result(mailbox(),result(),now=25)
        status,body=m.receipt_status(committed,ID,result())
        self.assertEqual(status,200)
        self.assertTrue(body["confirmed"])
        self.assertEqual(committed["cmd"],None)
        self.assertFalse(m.receipt_status(committed,ID,result(ID-1))[1]["confirmed"])

    def test_receipt_does_not_consume_next_command(self):
        committed,_,_,_=m.accept_result(mailbox(),result(),now=25)
        committed["cmd"]=cmd(ID+100)
        _,body=m.receipt_status(committed,ID,result())
        self.assertTrue(body["confirmed"])
        self.assertEqual(committed["cmd"]["id"],ID+100)

    def test_issue_refuses_overwrite_of_ambiguous_pending(self):
        old=mailbox()
        new,status,_,write=m.issue_if_empty(old,cmd(ID+1))
        self.assertEqual(status,409)
        self.assertFalse(write)
        self.assertEqual(new,old)

    def test_issue_allows_only_increasing_id_when_idle(self):
        old=mailbox()
        old["cmd"]=None
        old["result"]={"data":{"id":ID}}
        new,status,_,write=m.issue_if_empty(old,cmd(ID+1))
        self.assertEqual(status,200)
        self.assertTrue(write)
        self.assertEqual(new["cmd"]["id"],ID+1)
        failed,status2,_,write2=m.issue_if_empty(old,cmd(ID))
        self.assertEqual(status2,409)
        self.assertFalse(write2)

    def test_no_duplicate_result_overwrites_single_slot(self):
        saved,_,_,_=m.accept_result(mailbox(),result(),now=25)
        before=saved["result"].copy()
        state,status,_,write=m.accept_result(saved,result(),now=26)
        self.assertFalse(write)
        self.assertEqual(state["result"],before)

    def test_future_result_does_not_ack_until_issue(self):
        old=mailbox()
        future=result(ID+200)
        state,status,body,write=m.accept_result(old,future,now=26)
        self.assertEqual(status,409)
        self.assertFalse(body["accepted"])
        self.assertEqual(state,old)
        self.assertFalse(write)

if __name__=="__main__":
    unittest.main()
