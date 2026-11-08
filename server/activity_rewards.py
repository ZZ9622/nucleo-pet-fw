"""Cumulative board receipts, server calendar, single warehouse binding.

This prototype trusts the app's CRC-checked receipt. Cryptographic device
attestation is a separate production requirement, not provided by CRC.
"""
import datetime
import uuid
from zoneinfo import ZoneInfo

def sync(world, db, user, state, body, error):
    def integer(name, lower, upper):
        v=body.get(name)
        if type(v) is not int or not lower<=v<=upper:raise error('活动回执字段无效：'+name)
        return v
    try:pet=str(uuid.UUID(body.get('petID',''))).lower()
    except (ValueError,TypeError,AttributeError):raise error('挂件身份无效')
    if pet==str(uuid.UUID(int=0)):raise error('挂件身份无效')
    interval=integer('intervalSeconds',30,600)
    if interval!=world.activity_seconds:raise error('活动周期不匹配，请让挂件和小屋服务使用相同的正式/测试配置')
    day=integer('day',0,3652059);earned=integer('earnedToday',0,3)
    progress=integer('progressSeconds',0,interval-1)
    today=datetime.datetime.fromtimestamp(world.clock(),ZoneInfo(world.timezone)).date()
    ordinal=today.toordinal()
    if day>ordinal or (day==0 and (earned or progress)):raise error('活动归属日期无效')
    device=db.execute('SELECT * FROM activity_devices WHERE pet=?',(pet,)).fetchone()
    if device and device['owner']!=user:raise error('这个挂件已绑定其他仓库，请使用原手机身份')
    other=db.execute('SELECT pet FROM activity_devices WHERE owner=?',(user,)).fetchone()
    if other and other['pet']!=pet:raise error('当前仓库已有活动挂件，请保留原绑定')
    if not device:db.execute('INSERT INTO activity_devices(pet,owner,last_day) VALUES(?,?,0)',(pet,user))
    elif day and day<device['last_day']:raise error('挂件活动存档比已确认记录旧，已停止发放以防重复')
    granted=0
    if day:
        claim=db.execute('SELECT earned,interval FROM activity_claims WHERE pet=? AND day=?',(pet,day)).fetchone()
        previous=claim['earned'] if claim else 0
        if claim and interval!=claim['interval'] and earned!=previous:raise error('切换周期前请先用原配置同步所有活动奖励')
        if earned<previous:raise error('挂件奖励计数回退，请保留存档并检查设备')
        granted=earned-previous
        # pet/day is a unique cumulative entitlement, committed with the inventory.
        db.execute('INSERT INTO activity_claims VALUES(?,?,?,?) ON CONFLICT(pet,day) DO UPDATE SET earned=excluded.earned,interval=excluded.interval',(pet,day,earned,interval))
        if granted:
            state['boxes'].extend(str(uuid.uuid4()) for _ in range(granted))
            world.note(state,('短周期测试：' if interval==30 else '')+f'活动获得 {granted} 个盒子（{datetime.date.fromordinal(day).isoformat()}）')
        db.execute('UPDATE activity_devices SET last_day=max(last_day,?) WHERE pet=?',(day,pet))
    state['activitySync']=dict(petID=pet,day=ordinal,dayLabel=today.isoformat(),timezone=world.timezone,
                               intervalSeconds=interval,ackDay=day,ackEarned=earned,granted=granted)
