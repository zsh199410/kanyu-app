import json, os, tempfile, unittest, sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import pool

class PoolTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory()
        self.cx=pool.connect(str(Path(self.tmp.name)/'test.db'))
        self.now=1794560000
        self.items=[{'name':'A','line':'A = trojan, domain.example, 443, password=secret','class':'pinned',
                     'vps_checks':[{'ts':self.now-100,'handshake_ok':False,'http_ok':False}]},
                    {'name':'B','line':'B = vmess, example.org, 443, username=aaaa','class':'rotating',
                     'vps_checks':[{'ts':self.now-j*100,'handshake_ok':True,'latency_ms':50+j,'http_ok':True}
                                   for j in range(3)]},
                    {'name':'C','line':'C = ss, foo.example, 1000, encrypt-method=aes-128-gcm, password=x'}]
        pool.import_candidates(self.cx,self.items,now=self.now)
    def tearDown(self):
        self.cx.close();self.tmp.cleanup()
    def observe(self, name, delay, ts=None,network='cellular',device='phone'):
        return pool.ingest(self.cx,{'group':'免费节点池','network':network,'device':device,
            'observations':[{'name':name,'ts':ts or self.now-20,'latency_ms':delay,'ok':delay is not None}]},
            now=self.now)
    def test_protocol_exact(self):
        self.assertEqual(pool.extract_protocol('X = vmess, example'), 'vmess')
        self.assertEqual(pool.extract_protocol('X = ss, example'), 'ss')
    def test_no_phone_no_publish(self):
        r=pool.publish(self.cx,str(Path(self.tmp.name)/'feed'),now=self.now)
        self.assertFalse(r['updated'])
    def test_mobile_success_outranks_bad_vps(self):
        self.observe('A',150)
        r=pool.publish(self.cx,str(Path(self.tmp.name)/'feed'),now=self.now)
        self.assertTrue(r['updated'])
        self.assertEqual(r['published'],1)
        self.assertIn('A = trojan',Path(self.tmp.name,'feed').read_text())
    def test_wifi_not_qualified(self):
        self.observe('A',140,network='wifi')
        self.assertEqual(pool.state(self.cx,self.cx.execute('SELECT * FROM nodes WHERE name="A"').fetchone(),self.now)[0],'PROBATION')
    def test_timeout_fails(self):
        self.observe('B',400)
        self.assertFalse(pool.publish(self.cx,str(Path(self.tmp.name)/'feed'),now=self.now)['updated'])
    def test_2_fails_quarantine(self):
        self.observe('B',400,ts=self.now-30,device='x')
        self.observe('B',500,ts=self.now-20,device='x')
        self.assertEqual(pool.state(self.cx,self.cx.execute('SELECT * FROM nodes WHERE name="B"').fetchone(),self.now)[0],'QUARANTINED')
    def test_three_failures_spaced_retire(self):
        for offset in (2000, 1000, 20):
            self.observe('B',450,ts=self.now-offset,device='x')
        self.assertEqual(pool.state(self.cx,self.cx.execute('SELECT * FROM nodes WHERE name="B"').fetchone(),self.now)[0],'RETIRED')
    def test_vps_gate(self):
        node=self.cx.execute('SELECT * FROM nodes WHERE name="B"').fetchone()
        self.assertEqual(pool.vps_gate(node),'PASS')
    def test_expired_mobile_excluded(self):
        self.observe('B',160)
        self.assertFalse(pool.publish(self.cx,str(Path(self.tmp.name)/'feed'),now=self.now+86500)['updated'])
    def test_stale_cache_rejected(self):
        self.assertEqual(self.observe('B',150,ts=self.now-7200),0)
    def test_unknown_rejected(self):
        self.assertEqual(self.observe('not-in-inventory',120),0)
    def test_bad_name_mismatch(self):
        with self.assertRaises(ValueError):pool.import_candidates(self.cx,[{'name':'A','line':'C = ss, example'}],now=self.now)

if __name__=='__main__':unittest.main()

