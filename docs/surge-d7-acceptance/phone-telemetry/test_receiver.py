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
