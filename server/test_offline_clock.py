import concurrent.futures
import unittest
import test_daily_six as fixtures
from pomi_server import RuleError

class OfflineClockTests(unittest.TestCase):
    setUp=fixtures.DailySixTests.setUp
    tearDown=fixtures.DailySixTests.tearDown
    report=fixtures.DailySixTests.report
    today=fixtures.DailySixTests.today
    def activate(self):
        day=self.today()
        s=self.report(day,0,offlineClockSupported=True,lifetimeEnabled=False,issuedTotal=0)
        self.assertTrue(s['activitySync']['clockBootstrap'])
        self.report(day,0,offlineClockSupported=True,lifetimeEnabled=True,issuedTotal=0)
        return day
    def test_multiple_offline_cycles_are_funded_by_total_not_last_day(self):
        day=self.activate();self.report(day,6,lifetimeEnabled=True,issuedTotal=6)
        self.now+=86400*3
        s=self.report(day+3,2,lifetimeEnabled=True,issuedTotal=20)
        self.assertEqual(len(s['boxes']),20);self.assertEqual(s['activitySync']['granted'],14)
        self.assertEqual(len(self.report(day+3,2,lifetimeEnabled=True,issuedTotal=20)['boxes']),20)
    def test_concurrent_total_receipts_and_restart_never_duplicate(self):
        day=self.activate();self.now+=86400*2
        with concurrent.futures.ThreadPoolExecutor() as pool:
            list(pool.map(lambda _:self.report(day+2,6,lifetimeEnabled=True,issuedTotal=18),range(8)))
        self.assertEqual(len(self.report(day+2,6,lifetimeEnabled=True,issuedTotal=18)['boxes']),18)
    def test_rollback_disabled_counter_and_impossible_totals_are_rejected(self):
        day=self.activate();self.report(day,2,lifetimeEnabled=True,issuedTotal=2)
        with self.assertRaises(RuleError):self.report(day,2,lifetimeEnabled=True,issuedTotal=1)
        with self.assertRaises(RuleError):self.report(day,2,lifetimeEnabled=False,issuedTotal=0)
        with self.assertRaises(RuleError):self.report(day,2,lifetimeEnabled=True,issuedTotal=7)
    def test_legacy_rewards_are_not_reissued_at_counter_activation(self):
        day=self.today();s=self.report(day,3)
        self.assertEqual(len(s['boxes']),3)
        s=self.report(day,3,offlineClockSupported=True,lifetimeEnabled=False,issuedTotal=0)
        self.assertEqual(len(s['boxes']),3)
        self.assertEqual(len(self.report(day,3,lifetimeEnabled=True,issuedTotal=0)['boxes']),3)
        self.assertEqual(len(self.report(day,4,lifetimeEnabled=True,issuedTotal=1)['boxes']),4)
    def test_cold_boot_same_total_does_not_fund_again(self):
        day=self.activate();self.report(day,1,lifetimeEnabled=True,issuedTotal=1)
        self.now+=86400*4
        s=self.report(day+4,0,lifetimeEnabled=True,issuedTotal=1)
        self.assertEqual(len(s['boxes']),1)
    def test_issued_box_opened_before_retry_stays_consumed(self):
        day=self.activate();s=self.report(day,1,lifetimeEnabled=True,issuedTotal=1)
        p=self.world.run(self.token,'/prepare',dict(requestID='open',kind='open',boxID=s['boxes'][0],petID=self.pet))['pending']
        self.world.run(self.token,'/settle',dict(requestID='settle',operationID=p['id'],receiptID=p['id'],petID=self.pet))
        s=self.report(day,1,lifetimeEnabled=True,issuedTotal=1)
        self.assertEqual(len(s['boxes']),0);self.assertEqual(len(s['items']),1)
