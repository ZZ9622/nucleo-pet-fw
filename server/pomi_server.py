"""Pomi prototype service. Python 3.10+, SQLite, no third party dependencies."""
import argparse
import hashlib
import json
import secrets
import sqlite3
import time
import uuid
import activity_rewards
from contextlib import contextmanager
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

CATALOG = [
    dict(id='berry', name='蓝莓点心', category='food', symbol='carrot', slot=None),
    dict(id='cushion', name='云朵坐垫', category='decor', symbol='square.fill', slot='floor'),
    dict(id='plant', name='窗边小草', category='decor', symbol='leaf.fill', slot='corner'),
    dict(id='picture', name='海边挂画', category='decor', symbol='photo', slot='wall'),
    dict(id='shell', name='散步贝壳', category='souvenir', symbol='sparkles', slot='table'),
]

class RuleError(Exception):
    pass

class World:
    def __init__(self, path, clock=time.time, activity_seconds=600, timezone="Europe/Stockholm", activity_profile=None):
        self.path, self.clock = path, clock
        if activity_seconds not in (30,600):raise ValueError("activity_seconds must be 30 or 600")
        self.activity_seconds,self.timezone=activity_seconds,timezone
        self.activity_profile=activity_profile or ('test30' if activity_seconds==30 else 'fixed600')
        if self.activity_profile not in activity_rewards.PROFILE_IDS:raise ValueError('Unknown activity profile')
        if self.activity_profile=='test30':self.activity_seconds=30
        with self.db() as db:
            db.executescript('''
            CREATE TABLE IF NOT EXISTS users(id TEXT PRIMARY KEY, token TEXT UNIQUE, data TEXT);
            CREATE TABLE IF NOT EXISTS bottles(id TEXT PRIMARY KEY, owner TEXT, item TEXT);
            CREATE TABLE IF NOT EXISTS activity_devices(pet TEXT PRIMARY KEY, owner TEXT UNIQUE, last_day INTEGER NOT NULL);
            CREATE TABLE IF NOT EXISTS activity_claims(pet TEXT, day INTEGER, earned INTEGER, interval INTEGER, PRIMARY KEY(pet,day));
            CREATE TABLE IF NOT EXISTS requests(user TEXT, id TEXT, path TEXT, body TEXT, result TEXT,
              PRIMARY KEY(user,id));
            ''')
            activity_rewards.migrate(db)
    @contextmanager
    def db(self):
        db = sqlite3.connect(self.path, timeout=10, isolation_level=None)
        db.row_factory = sqlite3.Row
        try:
            db.execute('BEGIN IMMEDIATE')
            yield db
            db.commit()
        except Exception:
            db.rollback()
            raise
        finally:
            db.close()
    def create(self):
        token = secrets.token_urlsafe(32)
        data = dict(boxes=[], items=[], room={}, log=[], pending=None, completed=[],
                    chances=3, anchor=int(self.clock()), preferences={}, activities=[], day='', daily=0)
        with self.db() as db:
            db.execute('INSERT INTO users VALUES(?,?,?)', (str(uuid.uuid4()), hashlib.sha256(token.encode()).hexdigest(), json.dumps(data)))
        return dict(token=token)
    def refill(self, s):
        now = int(self.clock())
        n = max(0, (now-s['anchor'])//10800)
        s['chances'] = min(3, s['chances']+n)
        if s['chances'] == 3: s['anchor'] = now
        else: s['anchor'] += n*10800
    def view(self, s):
        return dict(catalog=CATALOG, boxes=s['boxes'], items=s['items'], room=s['room'], log=s['log'],
                    pending=s['pending'], chances=s['chances'], nextChanceAt=s['anchor']+10800,
                    preferences=s['preferences'], activitySync=s.get('activitySync'))
    def item(self, kind, level=1):
        return dict(id=str(uuid.uuid4()), kind=kind, level=level)
    def note(self,s,text):
        s['log'].insert(0, dict(id=str(uuid.uuid4()), text=text, date=int(self.clock())))
        s['log'] = s['log'][:100]
    def run(self, token, path, b):
        with self.db() as db:
            row = db.execute('SELECT * FROM users WHERE token=?', (hashlib.sha256(token.encode()).hexdigest(),)).fetchone()
            if not row: raise RuleError('身份已失效，请检查服务地址和本机身份备份。')
            user, s = row['id'], json.loads(row['data'])
            rid = b.get('requestID')
            canonical = json.dumps(b, sort_keys=True)
            if path != '/state':
                if not isinstance(rid,str) or len(rid)>64 or not rid: raise RuleError('缺少操作编号')
                old = db.execute('SELECT * FROM requests WHERE user=? AND id=?',(user,rid)).fetchone()
                if old:
                    if old['path']!=path or old['body']!=canonical: raise RuleError('操作编号已被使用')
                    # Return current state, not an old inventory snapshot.
                    self.refill(s)
                    db.execute('UPDATE users SET data=? WHERE id=?',(json.dumps(s),user))
                    return self.view(s)
            self.refill(s)
            def find_item():
                item = next((i for i in s['items'] if i['id']==b.get('itemID')),None)
                if not item: raise RuleError('物品不存在')
                if item['id'] in s['room'].values(): raise RuleError('请先将物品从小屋收回')
                if s['pending'] and s['pending'].get('itemID')==item['id']: raise RuleError('物品正在等待挂件确认')
                return item
            if path == '/state': pass
            elif path == '/activity/sync':
                activity_rewards.sync(self,db,user,s,b,RuleError)
            elif path == '/activity':
                # Device integration reports cumulative eligible 10-minute segments.
                # Until trusted sensor receipts exist this endpoint is disabled by HTTP layer.
                event = str(b.get('eventID',''))
                if not event or len(event)>100: raise RuleError('活动编号无效')
                if event not in s['activities']:
                    day = time.strftime('%Y-%m-%d',time.gmtime(self.clock()))
                    if s['day']!=day: s['day'],s['daily']=day,0
                    if s['daily']>=3: raise RuleError('今天的活动盒子已收集完')
                    s['boxes'].append(str(uuid.uuid4()));s['daily']+=1
                    s['activities']=(s['activities']+[event])[-1000:]
                    self.note(s,'散步带回了一个盒子')
            elif path == '/prepare':
                if s['pending']: raise RuleError('请先完成上一次挂件操作')
                kind = b.get('kind')
                pet = str(b.get('petID',''))
                try: uuid.UUID(pet)
                except ValueError: raise RuleError('缺少挂件身份')
                if kind == 'open':
                    box = b.get('boxID')
                    if box not in s['boxes']: raise RuleError('盒子不存在')
                    # Familiar items become more likely gradually, capped at +4 weight.
                    weights=[3+min(4,s['preferences'].get(c['id'],0)//3) for c in CATALOG]
                    roll=secrets.randbelow(sum(weights)); chosen=CATALOG[0]
                    for c,w in zip(CATALOG,weights):
                        if roll<w: chosen=c;break
                        roll-=w
                    s['pending']=dict(id=str(uuid.uuid4()),kind=kind,boxID=box,itemID=None,petID=pet,
                                      reward=self.item(chosen['id']), level=1)
                elif kind == 'food':
                    item=find_item()
                    if item['kind']!='berry': raise RuleError('这不是食物')
                    s['pending']=dict(id=str(uuid.uuid4()),kind=kind,boxID=None,itemID=item['id'],petID=pet,
                                      reward=None,level=item['level'])
                else: raise RuleError('操作类型无效')
            elif path == '/settle':
                p=s['pending']
                if not p or p['id']!=b.get('operationID'): raise RuleError('没有对应的待确认操作')
                # Prototype trusts the app's CRC-checked board receipt; production needs signed receipts.
                if b.get('receiptID')!=p['id'] or b.get('petID')!=p['petID']: raise RuleError('挂件回执不匹配')
                if p['kind']=='open':
                    s['boxes'].remove(p['boxID']);s['items'].append(p['reward']);self.note(s,'打开盒子，发现了新物品')
                else:
                    s['items']=[i for i in s['items'] if i['id']!=p['itemID']]
                    s['preferences']['berry']=s['preferences'].get('berry',0)+1
                    self.note(s,'在挂件上确认使用了点心')
                s['completed']=(s['completed']+[p['id']])[-100:];s['pending']=None
            elif path == '/decorate':
                slot=b.get('slot')
                if slot not in ['floor','corner','wall','table']: raise RuleError('摆放位置无效')
                if b.get('itemID') is None: s['room'].pop(slot,None)
                else:
                    item=find_item();c=next(c for c in CATALOG if c['id']==item['kind'])
                    if c['slot']!=slot: raise RuleError('这个物品不适合放在这里')
                    s['room'][slot]=item['id'];s['preferences'][item['kind']]=s['preferences'].get(item['kind'],0)+1
                self.note(s,'为小屋换了一点风景')
            elif path == '/merge':
                item=find_item()
                if item['level']>=2: raise RuleError('首版最高为 Lv2')
                eligible=[i for i in s['items'] if i['kind']==item['kind'] and i['level']==item['level']
                          and i['id'] not in s['room'].values() and (not s['pending'] or i['id']!=s['pending'].get('itemID'))]
                if len(eligible)<3: raise RuleError('需要三个相同的闲置 Lv1 物品')
                ids={i['id'] for i in eligible[:3]};s['items']=[i for i in s['items'] if i['id'] not in ids]
                s['items'].append(self.item(item['kind'],2));self.note(s,'三个小收藏合成了 Lv2')
            elif path == '/release':
                item=find_item();s['items'].remove(item)
                db.execute('INSERT INTO bottles VALUES(?,?,?)',(str(uuid.uuid4()),user,json.dumps(item)))
                self.note(s,'让一件物品乘着漂流瓶出发')
            elif path == '/fish':
                if s['chances']<1: raise RuleError('捞取机会还在恢复中')
                bottles=db.execute('SELECT * FROM bottles WHERE owner!=? ORDER BY random() LIMIT 1',(user,)).fetchone()
                if not bottles: raise RuleError('海面暂时没有漂流瓶，机会已保留')
                item=json.loads(bottles['item']);item['id']=str(uuid.uuid4());s['items'].append(item)
                db.execute('DELETE FROM bottles WHERE id=?',(bottles['id'],));s['chances']-=1
                self.note(s,'从放生海捞到了一份惊喜')
            else: raise RuleError('未知操作')
            db.execute('UPDATE users SET data=? WHERE id=?',(json.dumps(s),user))
            result=self.view(s)
            if path!='/state': db.execute('INSERT INTO requests VALUES(?,?,?,?,?)',(user,rid,path,canonical,'{}'))
            return result
    def seed(self,count):
        with self.db() as db:
            for _ in range(count):
                db.execute('INSERT INTO bottles VALUES(?,?,?)',(str(uuid.uuid4()),'official',json.dumps(self.item(secrets.choice(CATALOG)['id']))))

class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        try:
            length=int(self.headers.get('Content-Length','0'))
            if length<0 or length>16384: raise RuleError('请求过大')
            b=json.loads(self.rfile.read(length) or b'{}')
            if not isinstance(b,dict): raise RuleError('请求格式无效')
            if self.path=='/identity': result=self.server.world.create()
            else:
                if self.path=='/activity' and not self.server.development: raise RuleError('活动奖励等待传感器接入，当前服务未开放模拟发放')
                if self.path=='/activity/sync' and self.server.world.activity_profile=='test30' and not self.server.development: raise RuleError('30秒活动测试需显式启用开发模式')
                auth=self.headers.get('Authorization','')
                if not auth.startswith('Bearer '): raise RuleError('请先创建身份')
                result=self.server.world.run(auth[7:],self.path,b)
            status=200
        except (RuleError,ValueError,KeyError,TypeError) as e: status,result=400,dict(error=str(e))
        except Exception: status,result=500,dict(error='服务暂时不可用，请保留记录稍后重试')
        data=json.dumps(result,ensure_ascii=False).encode()
        self.send_response(status);self.send_header('Content-Type','application/json');self.send_header('Content-Length',str(len(data)));self.end_headers();self.wfile.write(data)
    def log_message(self,*args): pass

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--db',default='pomi.sqlite');p.add_argument('--host',default='127.0.0.1');p.add_argument('--port',type=int,default=8787);p.add_argument('--development',action='store_true');p.add_argument('--seed',type=int,default=0);p.add_argument('--activity-seconds',type=int,choices=[30,600],default=None);p.add_argument('--activity-profile',choices=['daily6','fixed600','test30']);p.add_argument('--timezone',default='Europe/Stockholm');a=p.parse_args()
    if a.activity_profile and a.activity_seconds is not None and a.activity_profile!=('test30' if a.activity_seconds==30 else 'fixed600'):p.error('Choose either --activity-profile or a matching legacy --activity-seconds value')
    profile=a.activity_profile or ('test30' if a.activity_seconds==30 else 'fixed600' if a.activity_seconds==600 else 'daily6')
    if profile=='test30' and not a.development:p.error('30-second test requires --development')
    world=World(a.db,activity_seconds=30 if profile=='test30' else 600,timezone=a.timezone,activity_profile=profile)
    if a.seed: world.seed(a.seed)
    server=ThreadingHTTPServer((a.host,a.port),Handler);server.world=world;server.development=a.development
    print(f'Pomi service listening on {a.host}:{a.port}',flush=True);server.serve_forever()
