import tempfile
import unittest
import uuid
from pathlib import Path

from accounts import account_auth
from pomi_server import RuleError, World


class ShopTests(unittest.TestCase):
    def test_friend_exchange_moves_each_item_once_and_cancel_returns_item(self):
        with tempfile.TemporaryDirectory() as directory:
            world = World(str(Path(directory) / "shop.sqlite"))

            def register(email):
                return account_auth.authenticate(
                    world, "/account/register", {"email": email, "password": "test-only"}, RuleError
                )["token"]

            def account(token, path, **body):
                return account_auth.account_request(world, token, "/account/" + path, body, RuleError)

            def mutate(token, path, **body):
                body.setdefault("requestID", str(uuid.uuid4()))
                return world.run(token, "/shop/" + path, body)

            seller = register("seller@example.test")
            buyer = register("buyer@example.test")
            seller_code = account(seller, "profile")["friendCode"]
            buyer_code = account(buyer, "profile")["friendCode"]
            seller_items = mutate(seller, "starter")["items"]
            buyer_items = mutate(buyer, "starter")["items"]
            self.assertEqual(mutate(seller, "starter")["items"], seller_items)

            offered = next(item for item in seller_items if item["kind"] == "shell")
            payment = next(item for item in buyer_items if item["kind"] == "plant")
            for invalid in ([], ["plant", "plant"], ["plant", "invalid"], ["plant", "berry", "picture", "shell"]):
                with self.assertRaises(RuleError):
                    mutate(seller, "list", itemID=offered["id"], wantedKinds=invalid)
            after_listing = mutate(seller, "list", itemID=offered["id"], wantedKinds=["picture", "plant"])
            self.assertNotIn(offered, after_listing["items"])
            listing = account(seller, "shop/listings")["listings"][0]
            self.assertEqual(listing["wantedKinds"], ["picture", "plant"])
            with self.assertRaises(RuleError):
                account(buyer, "shop/listings", friendCode=seller_code)
            with self.assertRaises(RuleError):
                mutate(buyer, "exchange", listingID=listing["id"], itemID=payment["id"])
            with self.assertRaises(RuleError):
                mutate(buyer, "cancel", listingID=listing["id"])

            account(buyer, "friend/request", friendCode=seller_code)
            account(seller, "friend/accept", friendCode=buyer_code)
            self.assertEqual(account(buyer, "shop/listings", friendCode=seller_code)["listings"], [listing])
            with self.assertRaises(RuleError):
                mutate(buyer, "exchange", listingID=listing["id"], itemID=buyer_items[0]["id"])
            purchase = dict(listingID=listing["id"], itemID=payment["id"], requestID="exchange")
            mutate(buyer, "exchange", **purchase)
            result = mutate(buyer, "exchange", **purchase)
            self.assertEqual(result["items"].count(offered), 1)
            self.assertNotIn(payment, result["items"])
            self.assertEqual(world.run(seller, "/state", {})["items"].count(payment), 1)
            self.assertEqual(account(seller, "shop/listings")["listings"], [])

            mutate(seller, "list", itemID=payment["id"], wantedKind="berry")
            with world.db() as db:
                db.execute("UPDATE shop_listings SET wanted_kinds=NULL")
            listing = account(seller, "shop/listings")["listings"][0]
            self.assertEqual(listing["wantedKinds"], ["berry"])
            account(seller, "friend/remove", friendCode=buyer_code)
            with self.assertRaises(RuleError):
                account(buyer, "shop/listings", friendCode=seller_code)
            returned = mutate(seller, "cancel", listingID=listing["id"])
            self.assertEqual(returned["items"].count(payment), 1)
