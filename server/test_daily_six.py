import concurrent.futures
import datetime
import os
import tempfile
import unittest
import uuid
from pomi_server import World, RuleError
from activity_rewards import target

class DailySixTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.path=os.path.join(self.tmp.name,'world.sqlite')
        self.now=datetime.datetime(2026,11,8,12,tzinfo=datetime.timezone.utc).timestamp()
        self.world=World(self.path,lambda:self.now,activity_profile='daily6')
        self.token=self.world.create()['token'];self.pet=str(uuid.uuid4())
    def tearDown(self):self.tmp.cleanup()
    def report(self,day,earned,progress=0,profile=3,configured=3,**extra):
        body=dict(requestID=str(uuid.uuid4()),petID=self.pet,profile=profile,configuredProfile=configured,
                  day=day,earnedToday=earned,progressSeconds=progress,intervalSeconds=target(profile or 2,earned))
        body.update(extra);return self.world.run(self.token,'/activity/sync',body)
    def today(self):return self.report(0,0)['activitySync']['day']
    def test_six_cumulative_counts_and_seventh_rejected(self):
        day=self.today()
        for i in range(1,7):
            s=self.report(day,i);self.assertEqual(len(s['boxes']),i)
            self.assertEqual(s['activitySync']['refreshHour'],8)
            self.assertEqual(s['activitySync']['dailyLimit'],6)
            self.assertEqual(len(self.report(day,i)['boxes']),i)
        with self.assertRaises(RuleError):self.report(day,7)
    def test_0800_and_midnight_boundaries(self):
        self.now=datetime.datetime(2026,11,8,6,59,59,tzinfo=datetime.timezone.utc).timestamp() # 07:59:59 Stockholm
        day=self.today();self.now+=1;self.assertEqual(self.today(),day+1)
        self.now=datetime.datetime(2026,11,8,23,30,tzinfo=datetime.timezone.utc).timestamp()
        self.assertEqual(self.today(),day+1) # 00:30 next date is still previous cycle
    def test_dst_uses_local_8_not_fixed_utc_hour(self):
        self.now=datetime.datetime(2026,7,1,5,59,59,tzinfo=datetime.timezone.utc).timestamp()
        day=self.today();self.now+=1;self.assertEqual(self.today(),day+1) # Summer UTC+2
    def test_sensor_stage_and_device_configuration_must_match(self):
        day=self.today()
        with self.assertRaises(RuleError):self.report(day,1,intervalSeconds=60)
        with self.assertRaises(RuleError):self.report(day,1,progress=180)
        with self.assertRaises(RuleError):self.report(day,1,configured=1)
        self.assertEqual(len(self.report(day,1,progress=179)['boxes']),1)
    def test_concurrent_claims_and_restart(self):
        day=self.today()
        with concurrent.futures.ThreadPoolExecutor() as pool:list(pool.map(lambda _:self.report(day,6),range(8)))
        self.world=World(self.path,lambda:self.now,activity_profile='daily6')
        self.assertEqual(len(self.report(day,6)['boxes']),6)
    def test_old_cycle_is_settled_before_new_cycle(self):
        day=self.today();self.report(day,2);self.now+=86400
        s=self.report(day,6);self.assertEqual(len(s['boxes']),6);self.assertEqual(s['activitySync']['day'],day+1)
        self.assertEqual(len(self.report(day+1,1)['boxes']),7)
        with self.assertRaises(RuleError):self.report(day,6)
    def test_initial_v4_bootstrap_lost_reply_is_retryable(self):
        first=self.report(0,0,profile=0)
        retry=self.report(0,0,profile=0)
        self.assertEqual(first['activitySync']['day'],retry['activitySync']['day'])
        s=self.report(first['activitySync']['day'],0)
        self.assertFalse(s['boxes'])
    def test_test30_upgrade_before_8_keeps_count_and_old_reply_retry(self):
        # The old test uses midnight; new daily6 is still yesterday before 08:00.
        self.now=datetime.datetime(2026,11,8,5,tzinfo=datetime.timezone.utc).timestamp()
        self.world=World(self.path,lambda:self.now,activity_seconds=30)
        oldday=datetime.date(2026,11,8).toordinal()
        self.report(oldday,3,profile=1,configured=1)
        self.world=World(self.path,lambda:self.now,activity_profile='daily6')
        s=self.report(oldday,3,profile=0,configured=3)
        ack=s['activitySync'];self.assertEqual(ack['day'],oldday-1);self.assertEqual(ack['carryEarned'],3)
        self.assertEqual(len(self.report(oldday,3,profile=0)['boxes']),3)
        s=self.report(ack['day'],3);self.assertEqual(len(s['boxes']),3)
        s=self.report(ack['day'],4);self.assertEqual(len(s['boxes']),4)
    def test_migration_progress_can_advance_before_ack_without_duplicate(self):
        self.world=World(self.path,lambda:self.now,activity_seconds=30)
        day=datetime.date(2026,11,8).toordinal();self.report(day,1,profile=1,configured=1)
        self.world=World(self.path,lambda:self.now,activity_profile='daily6')
        self.report(day,1,profile=1,configured=3)
        s=self.report(day,2,profile=1,configured=3)
        self.assertEqual(s['activitySync']['carryEarned'],2);self.assertEqual(len(s['boxes']),2)
        s=self.report(day,2);self.assertEqual(len(s['boxes']),2)
        with self.assertRaises(RuleError):self.report(day,2,profile=1,configured=3)
    def test_round_trip_profiles_never_reopens_allowance(self):
        day=self.today();self.report(day,6)
        self.world=World(self.path,lambda:self.now,activity_seconds=30)
        ack=self.report(day,6,profile=3,configured=1)['activitySync'];self.assertEqual(ack['carryEarned'],3)
        self.report(day,3,profile=1,configured=1)
        self.world=World(self.path,lambda:self.now,activity_profile='daily6')
        ack=self.report(day,3,profile=1,configured=3)['activitySync'];self.assertEqual(ack['carryEarned'],6)
        self.assertEqual(len(self.report(day,6)['boxes']),6)

if __name__=='__main__':unittest.main()
