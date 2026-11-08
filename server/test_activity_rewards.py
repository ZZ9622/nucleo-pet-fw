import concurrent.futures
import datetime
import json
import os
import tempfile
import unittest
import uuid
from pomi_server import World, RuleError

class ActivityTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory()
        self.now=datetime.datetime(2026,11,8,12,tzinfo=datetime.timezone.utc).timestamp()
        self.world=World(os.path.join(self.tmp.name,'world.sqlite'),lambda:self.now)
        self.token=self.world.create()['token'];self.pet=str(uuid.uuid4())
    def tearDown(self):self.tmp.cleanup()
    def report(self,day,earned,**extra):
        b=dict(requestID=str(uuid.uuid4()),petID=self.pet,day=day,earnedToday=earned,progressSeconds=0,intervalSeconds=600)
        b.update(extra);return self.world.run(self.token,'/activity/sync',b)
    def today(self):return self.report(0,0)['activitySync']['day']
    def test_cumulative_retry_no_duplicate_and_three_cap(self):
        day=self.today()
        self.assertEqual(len(self.report(day,1)['boxes']),1)
        self.assertEqual(len(self.report(day,1)['boxes']),1)
        self.assertEqual(len(self.report(day,3)['boxes']),3)
        self.assertEqual(len(self.report(day,3)['boxes']),3)
        with self.assertRaises(RuleError):self.report(day,4)
    def test_concurrent_delivery_and_database_restart(self):
        day=self.today()
        with concurrent.futures.ThreadPoolExecutor() as pool:
            list(pool.map(lambda _:self.report(day,2),range(8)))
        self.world=World(self.world.path,lambda:self.now)
        self.assertEqual(len(self.report(day,2)['boxes']),2)
    def test_next_day_offline_backlog_and_rollover_ack(self):
        day=self.today();self.report(day,1)
        self.now+=86400
        s=self.report(day,3)
        self.assertEqual(s['activitySync']['ackEarned'],3)
        self.assertEqual(s['activitySync']['day'],day+1)
        self.assertEqual(len(s['boxes']),3)
        self.assertEqual(len(self.report(day+1,3)['boxes']),6)
        with self.assertRaises(RuleError):self.report(day,3)
    def test_server_stockholm_midnight_not_phone_date(self):
        self.now=datetime.datetime(2026,11,8,22,59,tzinfo=datetime.timezone.utc).timestamp()
        day=self.today();self.now+=120
        self.assertEqual(self.today(),day+1)
        with self.assertRaises(RuleError):self.report(day+2,1)
    def test_binding_blocks_second_account_and_second_pet(self):
        day=self.today();other=self.world.create()['token']
        original=self.token;self.token=other
        with self.assertRaises(RuleError):self.report(day,1)
        self.token=original;self.pet=str(uuid.uuid4())
        with self.assertRaises(RuleError):self.report(day,1)
    def test_profiles_invalid_receipts_and_rollback(self):
        day=self.today()
        with self.assertRaises(RuleError):self.report(day,1,intervalSeconds=30)
        with self.assertRaises(RuleError):self.report(day,1,progressSeconds=600)
        with self.assertRaises(RuleError):self.report(day,True)
        with self.assertRaises(RuleError):self.report(0,1)
        self.report(day,2)
        with self.assertRaises(RuleError):self.report(day,1)
    def test_short_profile_matches_and_legacy_inventory_is_kept(self):
        self.world=World(self.world.path,lambda:self.now,activity_seconds=30)
        s=self.report(0,0,intervalSeconds=30);day=s['activitySync']['day']
        s=self.report(day,1,intervalSeconds=30)
        self.assertEqual(len(s['boxes']),1);self.assertTrue(s['log'][0]['text'].startswith('短周期测试'))
    def test_short_to_production_keeps_daily_count_and_never_reissues(self):
        self.world=World(self.world.path,lambda:self.now,activity_seconds=30)
        day=self.report(0,0,intervalSeconds=30)['activitySync']['day']
        self.report(day,3,intervalSeconds=30)
        self.world=World(self.world.path,lambda:self.now,activity_seconds=600)
        self.assertEqual(len(self.report(day,3)['boxes']),3)
        self.assertEqual(len(self.report(day,3)['boxes']),3)

    def test_retry_after_box_was_opened_does_not_restore_it(self):
        day=self.today();s=self.report(day,1)
        prepare=dict(requestID='prepare',kind='open',boxID=s['boxes'][0],petID=self.pet)
        s=self.world.run(self.token,'/prepare',prepare);p=s['pending']
        self.world.run(self.token,'/settle',dict(requestID='settle',operationID=p['id'],receiptID=p['id'],petID=self.pet))
        s=self.report(day,1);self.assertFalse(s['boxes']);self.assertEqual(len(s['items']),1)

if __name__=='__main__':unittest.main()
