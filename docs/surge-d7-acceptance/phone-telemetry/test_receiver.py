import hashlib
import os
from pathlib import Path
import sqlite3
import tempfile
import unittest
import receiver

PINS=''.join(f'PIN{i} = ss, 192.0.2.{i}, {10000+i}, encrypt-method=aes-128-gcm, password=dummy\n' for i in range(1,22))
NODES=''.join(f'NONPIN{i} = trojan, 198.51.100.{i}, {443+i}, password=dummy\n' for i in range(1,26))
RAW=(PINS+NODES).encode()
SHA=hashlib.sha256(RAW).hexdigest()

def payload(mode='external_policy_id',bearer='cellular'):
 return {'schema':1,'group':'免费节点池','timestamp':1763640000,'nonce':'a'*32,'pool_sha':SHA,'bearer':bearer,'surge_version':'6.0.0','observations':[{'name':'NONPIN1','probe_mode':mode,'results':[{'id':'a','state':'timeout'},{'id':'b','state':'transport_error'}]}]}

class TestReceiver(unittest.TestCase):
 def test_true_fail_external(self):
  self.assertEqual(receiver.validate(payload(),RAW,1763640000)[0][3:6],('failure','external_policy_id',1))
 def test_old_descriptor_fail_not_trusted(self):
  self.assertEqual(receiver.validate(payload('temporary_policy_descriptor'),RAW,1763640000)[0][3],'unknown')
 def test_descriptor_after_device_validation(self):
  self.assertEqual(receiver.validate(payload('temporary_policy_descriptor'),RAW,1763640000,descriptor_accepted=True)[0][3],'failure')
 def test_unknown_bearer_not_dead(self):
  self.assertEqual(receiver.validate(payload(bearer='unknown'),RAW,1763640000)[0][3],'unknown')
 def test_partial_probe_unknown(self):
  x=payload();x['observations'][0]['results'][1]['state']='unknown'
  self.assertEqual(receiver.validate(x,RAW,1763640000)[0][3],'unknown')
 def test_one_reachable_success(self):
  x=payload();x['observations'][0]['results'][0]['state']='reachable'
  self.assertEqual(receiver.validate(x,RAW,1763640000)[0][3],'success')
 def test_outage_batch_downgrades(self):
  x=payload(); x['observations']=[{'name':f'NONPIN{i}','probe_mode':'external_policy_id','results':[{'id':'a','state':'timeout'},{'id':'b','state':'transport_error'}]} for i in (1,2,3)]
  self.assertTrue(all(r[3]=='unknown' for r in receiver.validate(x,RAW,1763640000)))
 def test_same_batch_reachable_control_admits_four_independent_fails(self):
  x=payload()
  x['observations']=[
   {'name':f'NONPIN{i}','probe_mode':'external_policy_id',
    'results':[{'id':'a','state':'timeout'},{'id':'b','state':'transport_error'}]}
   for i in (1,2,3,4)]
  x['network_controls']=[
   {'name':'PIN1','probe_mode':'external_policy_id',
    'results':[{'id':'a','state':'reachable'},{'id':'b','state':'unknown'}]},
   {'name':'PIN2','probe_mode':'external_policy_id',
    'results':[{'id':'a','state':'timeout'},{'id':'b','state':'transport_error'}]}]
  rows=receiver.validate(x,RAW,1763640000)
  self.assertEqual([r[3] for r in rows],['failure']*4)
  self.assertEqual([r[6] for r in rows],['dual_transport_failure']*4)
  self.assertTrue(all(r[7:]==('failure','dual_transport_failure',1) for r in rows))
 def test_four_all_failed_control_unreachable_stays_unknown(self):
  x=payload()
  x['observations']=[
   {'name':f'NONPIN{i}','probe_mode':'external_policy_id',
    'results':[{'id':'a','state':'timeout'},{'id':'b','state':'transport_error'}]}
   for i in (1,2,3,4)]
  x['network_controls']=[
   {'name':'PIN1','probe_mode':'external_policy_id',
    'results':[{'id':'a','state':'timeout'},{'id':'b','state':'transport_error'}]}]
  rows=receiver.validate(x,RAW,1763640000)
  self.assertEqual([r[3] for r in rows],['unknown']*4)
  self.assertEqual([r[6] for r in rows],['batch_unverified_network']*4)
  self.assertEqual([r[7] for r in rows],['failure']*4)
  self.assertEqual([r[8] for r in rows],['dual_transport_failure']*4)
 def test_legacy_four_failed_without_controls_stays_unknown_and_raw_kept(self):
  x=payload()
  x['observations']=[
   {'name':f'NONPIN{i}','probe_mode':'external_policy_id',
    'results':[{'id':'a','state':'timeout'},{'id':'b','state':'transport_error'}]}
   for i in (1,2,3,4)]
  rows=receiver.validate(x,RAW,1763640000)
  self.assertEqual([r[3] for r in rows],['unknown']*4)
  self.assertTrue(all(r[7]=='failure' and r[9]==0 for r in rows))
 def test_network_control_cannot_overlap_or_be_forged(self):
  x=payload()
  a={'name':'NONPIN1','probe_mode':'external_policy_id','results':[
    {'id':'a','state':'reachable'},{'id':'b','state':'unknown'}]}
  x['network_controls']=[a]
  with self.assertRaisesRegex(receiver.InputRejected,'unsafe_network_control_identity'):
   receiver.validate(x,RAW,1763640000)
  x['network_controls']=[dict(a,name='PIN1'),dict(a,name='PIN1')]
  with self.assertRaisesRegex(receiver.InputRejected,'unsafe_network_control_identity'):
   receiver.validate(x,RAW,1763640000)
  x['network_controls']=[dict(a,name='OUTSIDER')]
  with self.assertRaisesRegex(receiver.InputRejected,'unsafe_network_control_identity'):
   receiver.validate(x,RAW,1763640000)
  x['network_controls']=[dict(a,name='PIN1',probe_mode='temporary_policy_descriptor')]
  with self.assertRaisesRegex(receiver.InputRejected,'untrusted_network_control_mode'):
   receiver.validate(x,RAW,1763640000)
  x['network_controls']=[dict(a,name='PIN1'),dict(a,name='PIN2'),dict(a,name='PIN3')]
  with self.assertRaisesRegex(receiver.InputRejected,'invalid_network_controls'):
   receiver.validate(x,RAW,1763640000)
 def test_controls_not_counted_as_candidate_and_db_raw_evidence_persisted(self):
  x=payload()
  x['observations']=[
   {'name':f'NONPIN{i}','probe_mode':'external_policy_id',
    'results':[{'id':'a','state':'timeout'},{'id':'b','state':'transport_error'}]}
   for i in (1,2,3,4)]
  x['network_controls']=[
   {'name':'PIN1','probe_mode':'external_policy_id',
    'results':[{'id':'a','state':'reachable'},{'id':'b','state':'unknown'}]}]
  with tempfile.TemporaryDirectory() as t:
   db=os.path.join(t,'staging.sqlite')
   receiver.initialize_db(db)
   rows=receiver.validate(x,RAW,1763640000)
   self.assertEqual(receiver.record_batch(db,x,rows,1763640000),'stored')
   self.assertEqual(receiver.record_batch(db,x,rows,1763640001),'duplicate')
   with sqlite3.connect(db) as c:
    saved=c.execute('SELECT status,reason,raw_status,raw_reason,control_verified FROM phone_observations').fetchall()
    self.assertEqual(saved,[('failure','dual_transport_failure','failure','dual_transport_failure',1)]*4)
    self.assertEqual(c.execute('SELECT count(*) FROM phone_observations').fetchone()[0],4)
 def test_mixed_batch_without_control_preserves_failed_and_successful(self):
  x=payload()
  x['observations']=[
   {'name':f'NONPIN{i}','probe_mode':'external_policy_id',
    'results':[{'id':'a','state':'reachable' if i==1 else 'timeout'},
               {'id':'b','state':'transport_error'}]} for i in (1,2,3,4)]
  rows=receiver.validate(x,RAW,1763640000)
  self.assertEqual([r[3] for r in rows],['success','failure','failure','failure'])
 def test_untrusted_descriptor_records_raw_failure_without_admission(self):
  r=receiver.validate(payload(mode='temporary_policy_descriptor'),RAW,1763640000)[0]
  self.assertEqual((r[3],r[6],r[7],r[8]),('unknown','untrusted_policy_descriptor','failure','dual_transport_failure'))
 def test_stale_pool_rejected(self):
  x=payload();x['pool_sha']='0'*64
  with self.assertRaisesRegex(receiver.InputRejected,'stale_pool_sha'): receiver.validate(x,RAW,1763640000)
 def test_name_unknown_and_duplicate(self):
  x=payload();x['observations'][0]['name']='UNKNOWN'
  with self.assertRaises(receiver.InputRejected): receiver.validate(x,RAW,1763640000)
  x=payload();x['observations']*=2
  with self.assertRaises(receiver.InputRejected): receiver.validate(x,RAW,1763640000)
 def test_invalid_source_pool(self):
  with self.assertRaises(receiver.InputRejected):receiver.validate(payload(),RAW+b'nonproxy\n',1763640000)
 def test_no_raw_secrets_in_database(self):
  with tempfile.TemporaryDirectory() as t:
   path=os.path.join(t,'obs.sqlite')
   receiver.initialize_db(path)
   p=payload();rows=receiver.validate(p,RAW,1763640000)
   self.assertEqual(receiver.record_batch(path,p,rows,1763640000),'stored')
   self.assertEqual(receiver.record_batch(path,p,rows,1763640001),'duplicate')
   conn=sqlite3.connect(path)
   self.assertEqual(conn.execute('select count(*) from phone_observations').fetchone()[0],1)
   self.assertNotIn('password=dummy',Path(path).read_bytes().decode('latin1'))

if __name__=='__main__':unittest.main()
