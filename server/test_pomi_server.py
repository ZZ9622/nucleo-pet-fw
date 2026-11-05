import concurrent.futures
import os
import tempfile
import unittest
import uuid
from pomi_server import World, RuleError

class WorldTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.now=100000
        self.w=World(os.path.join(self.tmp.name,'test.sqlite'),lambda:self.now)
        self.a=self.w.create()['token'];self.b=self.w.create()['token']
    def tearDown(self): self.tmp.cleanup()
    def runop(self,token,path,**body):
        body.setdefault('requestID',str(uuid.uuid4()));return self.w.run(token,path,body)
    def grant(self,token,event='walk'):
        return self.runop(token,'/activity',eventID=event)
    def opened(self,token,kind='berry'):
        s=self.grant(token,str(uuid.uuid4()))
        s=self.runop(token,'/prepare',kind='open',boxID=s['boxes'][0],petID=str(uuid.uuid4()))
        p=s['pending']
        # Fix reward for focused rule testing; this is test-only database access.
        with self.w.db() as db:
            import json,hashlib
            row=db.execute('SELECT data FROM users WHERE token=?',(hashlib.sha256(token.encode()).hexdigest(),)).fetchone()
            data=json.loads(row['data']);data['pending']['reward']['kind']=kind
            db.execute('UPDATE users SET data=? WHERE token=?',(json.dumps(data),hashlib.sha256(token.encode()).hexdigest()))
        return self.runop(token,'/settle',operationID=p['id'],receiptID=p['id'],petID=p['petID'])
    def test_activity_dedup_daily_limit(self):
        self.assertEqual(len(self.grant(self.a)['boxes']),1)
        self.assertEqual(len(self.grant(self.a)['boxes']),1)
        self.grant(self.a,'two');self.grant(self.a,'three')
        with self.assertRaises(RuleError): self.grant(self.a,'four')
    def test_pending_survives_restart_and_settle_retry(self):
        s=self.grant(self.a);pet=str(uuid.uuid4())
        s=self.runop(self.a,'/prepare',kind='open',boxID=s['boxes'][0],petID=pet);p=s['pending']
        self.w=World(self.w.path,lambda:self.now)
        self.assertEqual(self.w.run(self.a,'/state',{})['pending']['id'],p['id'])
        with self.assertRaises(RuleError): self.runop(self.a,'/settle',operationID=p['id'],receiptID='wrong',petID=pet)
        body=dict(requestID='settle',operationID=p['id'],receiptID=p['id'],petID=pet)
        s=self.w.run(self.a,'/settle',body);self.assertEqual(len(s['items']),1)
        s=self.w.run(self.a,'/settle',body);self.assertEqual(len(s['items']),1);self.assertFalse(s['boxes'])
    def test_release_own_bottle_excluded_and_transfer_once(self):
        s=self.opened(self.a);item=s['items'][0]
        self.runop(self.a,'/release',itemID=item['id'])
        with self.assertRaises(RuleError): self.runop(self.a,'/fish')
        s=self.runop(self.b,'/fish');self.assertEqual(len(s['items']),1);self.assertEqual(s['chances'],2)
        with self.assertRaises(RuleError): self.runop(self.b,'/fish')
    def test_concurrent_fish_single_bottle(self):
        self.w.seed(1)
        def fish(token):
            try: self.runop(token,'/fish');return True
            except RuleError:return False
        with concurrent.futures.ThreadPoolExecutor() as pool:
            results=list(pool.map(fish,[self.a,self.b]))
        self.assertEqual(sum(results),1)
    def test_three_hour_cap(self):
        self.w.seed(10)
        for _ in range(3):s=self.runop(self.a,'/fish')
        self.assertEqual(s['chances'],0)
        self.now+=10799
        with self.assertRaises(RuleError):self.runop(self.a,'/fish')
        self.now+=1;self.assertEqual(self.w.run(self.a,'/state',{})['chances'],1)
        self.now+=10800*20;self.assertEqual(self.w.run(self.a,'/state',{})['chances'],3)
    def test_decor_blocks_release_merge(self):
        s=self.opened(self.a,'plant');item=s['items'][0]
        self.runop(self.a,'/decorate',slot='corner',itemID=item['id'])
        with self.assertRaises(RuleError):self.runop(self.a,'/release',itemID=item['id'])
        self.runop(self.a,'/decorate',slot='corner')
        self.runop(self.a,'/release',itemID=item['id'])
    def test_merge_and_food_confirmation(self):
        for _ in range(3):s=self.opened(self.a)
        s=self.runop(self.a,'/merge',itemID=s['items'][0]['id']);self.assertEqual(len(s['items']),1);self.assertEqual(s['items'][0]['level'],2)
        item=s['items'][0];pet=str(uuid.uuid4())
        s=self.runop(self.a,'/prepare',kind='food',itemID=item['id'],petID=pet);self.assertEqual(len(s['items']),1)
        with self.assertRaises(RuleError):self.runop(self.a,'/release',itemID=item['id'])
        p=s['pending'];s=self.runop(self.a,'/settle',operationID=p['id'],receiptID=p['id'],petID=pet)
        self.assertFalse(s['items']);self.assertEqual(s['preferences']['berry'],1)
    def test_invalid_identity_and_id_reuse(self):
        with self.assertRaises(RuleError):self.w.run('wrong','/state',{})
        self.runop(self.a,'/activity',eventID='one',requestID='same')
        with self.assertRaises(RuleError):self.runop(self.a,'/fish',requestID='same')


class HTTPTests(unittest.TestCase):
    def test_http_identity_auth_and_production_activity_gate(self):
        import threading
        import json
        import urllib.request
        import urllib.error
        from http.server import ThreadingHTTPServer
        from pomi_server import Handler
        with tempfile.TemporaryDirectory() as directory:
            server=ThreadingHTTPServer(('127.0.0.1',0),Handler)
            server.world=World(os.path.join(directory,'world.sqlite'));server.development=False
            thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start()
            def post(path,body,token=None):
                req=urllib.request.Request(f'http://127.0.0.1:{server.server_port}'+path,data=json.dumps(body).encode(),headers={'Content-Type':'application/json',**({'Authorization':'Bearer '+token} if token else {})})
                with urllib.request.urlopen(req) as response:return json.load(response)
            try:
                token=post('/identity',{})['token']
                self.assertEqual(post('/state',{},token)['chances'],3)
                with self.assertRaises(urllib.error.HTTPError):post('/state',{})
                with self.assertRaises(urllib.error.HTTPError):post('/activity',{'requestID':'one','eventID':'walk'},token)
                server.development=True
                self.assertEqual(len(post('/activity',{'requestID':'one','eventID':'walk'},token)['boxes']),1)
            finally:server.shutdown();server.server_close();thread.join()

if __name__=='__main__':unittest.main()
