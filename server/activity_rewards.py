"""Cumulative receipts and profile migration, atomically committed with boxes.
CRC checks transport corruption; production device attestation is separate.
"""
import datetime
import json
import uuid
from zoneinfo import ZoneInfo

STAGES=(60,180,300,480,720,900)
PROFILE_IDS={'test30':1,'fixed600':2,'daily6':3}
def limit(profile):return 6 if profile==3 else 3
def target(profile,earned):return STAGES[min(earned,5)] if profile==3 else 30 if profile==1 else 600

def migrate(db):
    db.execute('CREATE TABLE IF NOT EXISTS activity_totals(pet TEXT PRIMARY KEY, claimed INTEGER NOT NULL, last_day INTEGER NOT NULL, enabled_seen INTEGER NOT NULL)')
    total_columns={r[1] for r in db.execute('PRAGMA table_info(activity_totals)')}
    if 'profile' not in total_columns:db.execute('ALTER TABLE activity_totals ADD COLUMN profile INTEGER NOT NULL DEFAULT 0')
    if 'earned' not in total_columns:db.execute('ALTER TABLE activity_totals ADD COLUMN earned INTEGER NOT NULL DEFAULT 0')
    columns={r[1] for r in db.execute('PRAGMA table_info(activity_devices)')}
    if 'profile' not in columns:db.execute('ALTER TABLE activity_devices ADD COLUMN profile INTEGER NOT NULL DEFAULT 0')
    if 'migration' not in columns:db.execute('ALTER TABLE activity_devices ADD COLUMN migration TEXT')
    db.execute('CREATE TABLE IF NOT EXISTS activity_cycle_claims(pet TEXT,profile INTEGER,day INTEGER,earned INTEGER,PRIMARY KEY(pet,profile,day))')
    db.execute('INSERT OR IGNORE INTO activity_cycle_claims SELECT pet,CASE WHEN interval=30 THEN 1 ELSE 2 END,day,earned FROM activity_claims')
    db.execute('''UPDATE activity_devices SET profile=COALESCE((SELECT CASE WHEN interval=30 THEN 1 ELSE 2 END
                  FROM activity_claims WHERE pet=activity_devices.pet ORDER BY day DESC LIMIT 1),0) WHERE profile=0''')

def _sync(world,db,user,state,body,error):
    def integer(name,lo,hi,default=None):
        v=body.get(name,default)
        if type(v) is not int or not lo<=v<=hi:raise error('活动回执字段无效：'+name)
        return v
    try:pet=str(uuid.UUID(body.get('petID',''))).lower()
    except (ValueError,TypeError,AttributeError):raise error('挂件身份无效')
    if pet==str(uuid.UUID(int=0)):raise error('挂件身份无效')
    interval=integer('intervalSeconds',30,900)
    inferred=1 if interval==30 else 2
    wire=integer('profile',0,3,inferred)
    configured=integer('configuredProfile',1,3,inferred if wire==0 else wire)
    desired=PROFILE_IDS[world.activity_profile]
    if configured!=desired:raise error('活动配置不匹配，请让挂件和小屋服务使用相同版本')
    device=db.execute('SELECT * FROM activity_devices WHERE pet=?',(pet,)).fetchone()
    day=integer('day',0,3652059)
    pending=json.loads(device['migration']) if device and device['migration'] else None
    source=pending['source'] if pending and wire==pending['wire'] and day==pending['fromDay'] else wire or (device['profile'] if device and device['profile'] else inferred)
    if source not in (1,2,3):raise error('活动版本无效')
    earned=integer('earnedToday',0,limit(source))
    progress=integer('progressSeconds',0,(600 if wire==0 else target(source,earned))-1)
    if wire!=0 and interval!=target(source,earned):raise error('阶段目标与活动计数不匹配')
    local=datetime.datetime.fromtimestamp(world.clock(),ZoneInfo(world.timezone))
    calendar_day=local.date()
    def cycle(profile):return (calendar_day-datetime.timedelta(days=1) if profile==3 and local.hour<8 else calendar_day).toordinal()
    if day>cycle(source) or (day==0 and (earned or progress)):raise error('活动归属日期无效')
    if device and device['owner']!=user:raise error('这个挂件已绑定其他仓库，请使用原手机身份')
    other=db.execute('SELECT pet FROM activity_devices WHERE owner=?',(user,)).fetchone()
    if other and other['pet']!=pet:raise error('当前仓库已有活动挂件，请保留原绑定')
    if device and device['last_day'] and not day and not (pending and pending['fromDay']==0 and wire==pending['wire']):raise error('挂件活动存档已重置，请保留记录并检查设备')
    if device and pending:
        if wire==pending['wire'] and day==pending['fromDay']:
            source=pending['source']
        elif wire==device['profile'] and day>=device['last_day']:
            db.execute('UPDATE activity_devices SET migration=NULL WHERE pet=?',(pet,));pending=None
        else:raise error('活动版本切换尚未确认，请连接原挂件继续')
    elif device and device['profile']:
        if source!=device['profile'] or (day and day<device['last_day']):raise error('挂件活动存档比已确认记录旧，已停止发放')
    if not device:
        db.execute('INSERT INTO activity_devices(pet,owner,last_day,profile) VALUES(?,?,?,?)',(pet,user,day,source))
    granted=0
    if day:
        old=db.execute('SELECT earned FROM activity_cycle_claims WHERE pet=? AND profile=? AND day=?',(pet,source,day)).fetchone()
        previous=old['earned'] if old else 0
        if earned<previous:raise error('挂件奖励计数回退，请保留存档并检查设备')
        granted=earned-previous
        db.execute('INSERT INTO activity_cycle_claims VALUES(?,?,?,?) ON CONFLICT(pet,profile,day) DO UPDATE SET earned=excluded.earned',(pet,source,day,earned))
        if granted:
            state['boxes'].extend(str(uuid.uuid4()) for _ in range(granted))
            world.note(state,('短周期测试：' if source==1 else '')+f'活动获得 {granted} 个盒子（{datetime.date.fromordinal(day).isoformat()}）')
    changing=source!=desired or wire==0
    next_day=cycle(desired)
    if changing:
        if pending:
            if pending['target']!=desired:raise error('请先完成原来的活动配置切换')
            next_day=pending['toDay']
        baseline=min(limit(desired),earned)
        # Already issued boxes consume the new profile's allowance too. Switching
        # profiles never creates a fresh full allowance or reissues old rewards.
        db.execute('INSERT INTO activity_cycle_claims VALUES(?,?,?,?) ON CONFLICT(pet,profile,day) DO UPDATE SET earned=max(earned,excluded.earned)',(pet,desired,next_day,baseline))
        carry=db.execute("SELECT earned FROM activity_cycle_claims WHERE pet=? AND profile=? AND day=?",(pet,desired,next_day)).fetchone()[0]
        pending=dict(wire=wire,source=source,fromDay=day,target=desired,toDay=next_day)
        db.execute('UPDATE activity_devices SET profile=?,last_day=?,migration=? WHERE pet=?',(desired,next_day,json.dumps(pending),pet))
    else:
        carry=0
        db.execute('UPDATE activity_devices SET last_day=max(last_day,?) WHERE pet=?',(day,pet))
    state['activitySync']=dict(petID=pet,day=next_day,dayLabel=datetime.date.fromordinal(next_day).isoformat(),timezone=world.timezone,
        intervalSeconds=target(desired,carry if changing else (earned if day==next_day else 0)),
        ackDay=day,ackEarned=earned,granted=granted,profile=desired,ackProfile=wire,carryEarned=carry,dailyLimit=limit(desired),refreshHour=8 if desired==3 else 0)

def sync(world,db,user,state,body,error):
    try:pet=str(uuid.UUID(body.get('petID',''))).lower()
    except (ValueError,TypeError,AttributeError):raise error('挂件身份无效')
    enabled=body.get('lifetimeEnabled',False)
    support=body.get('offlineClockSupported',False)
    if type(enabled) is not bool or type(support) is not bool:raise error('累计奖励标记无效')
    row=db.execute('SELECT * FROM activity_totals WHERE pet=?',(pet,)).fetchone()
    if row and row['enabled_seen'] and not enabled:raise error('挂件累计奖励记录回退，请保留存档并升级App')
    delta=0
    if enabled:
        total=body.get('issuedTotal')
        day=body.get('day')
        if type(total) is not int or not 0<=total<=0xffffffff or type(day) is not int:raise error('累计奖励计数无效')
        if not row:raise error('请先完成一次在线校时，保留挂件存档')
        if total<row['claimed']:raise error('累计奖励计数回退，已停止发放')
        delta=total-row['claimed']
        if type(body.get('earnedToday')) is not int or not 0<=body['earnedToday']<=6:raise error('活动计数无效')
        if body.get('profile')==row['profile'] and day==row['last_day'] and delta>max(0,body.get('earnedToday',0)-row['earned']):raise error('累计奖励与本周期计数不一致')
        if delta>6*(max(0,day-row['last_day'])+1):raise error('离线奖励超过周期上限，已停止发放')
    boxes=list(state['boxes']);log=list(state['log'])
    _sync(world,db,user,state,body,error)
    if enabled:
        # The per-cycle receipt still verifies today's state; the monotonic
        # counter funds all unclaimed cycles, including days spent offline.
        state['boxes']=boxes;state['log']=log
        if delta:
            state['boxes'].extend(str(uuid.uuid4()) for _ in range(delta))
            world.note(state,f'活动获得 {delta} 个盒子（含离线累计）')
        db.execute('UPDATE activity_totals SET claimed=?,last_day=?,enabled_seen=1,profile=?,earned=? WHERE pet=?',(total,day,body.get('profile',0),body.get('earnedToday',0),pet))
        state['activitySync']['granted']=delta
    elif support and body.get('configuredProfile')==3:
        db.execute('INSERT INTO activity_totals(pet,claimed,last_day,enabled_seen,profile,earned) VALUES(?,0,?,0,?,?) ON CONFLICT(pet) DO UPDATE SET last_day=excluded.last_day,profile=excluded.profile,earned=excluded.earned',(pet,body.get('day',0),body.get('profile',0),body.get('earnedToday',0)))
        state['activitySync']['clockBootstrap']=True
