import os
import tempfile
import unittest
import uuid

from accounts import account_auth
from pomi_server import Handler, RuleError, World


class AccountTests(unittest.TestCase):
    def test_registration_login_binding_and_logout(self):
        with tempfile.TemporaryDirectory() as directory:
            world = World(os.path.join(directory, "account.sqlite"))
            credentials = {"email": "Test@example.com", "password": "test password"}

            def auth(action, data):
                return account_auth.authenticate(world, "/account/" + action, data, RuleError)["token"]

            def request(token, action, **data):
                return account_auth.account_request(world, token, "/account/" + action, data, RuleError)

            first = auth("register", credentials)
            with self.assertRaises(RuleError):
                auth("register", dict(credentials, email=" test@example.com "))
            with self.assertRaises(RuleError):
                auth("login", dict(credentials, password="wrong password"))
            second = auth("login", credentials)
            other = auth("register", dict(credentials, email="other@example.com"))
            first_pomi, second_pomi = str(uuid.uuid4()), str(uuid.uuid4())
            request(first, "test-bind", pomiID=first_pomi)
            request(second, "test-bind", pomiID=second_pomi)
            self.assertEqual(request(first, "profile"), request(second, "profile"))
            self.assertCountEqual(request(second, "profile")["pomiIDs"], [first_pomi, second_pomi])
            self.assertEqual(request(other, "profile")["pomiIDs"], [])
            with self.assertRaises(RuleError):
                request(other, "test-bind", pomiID=first_pomi)
            world.run(first, "/activity", {"requestID": "test", "eventID": "test"})
            self.assertEqual(len(world.run(second, "/state", {})["boxes"]), 1)
            self.assertEqual(world.run(other, "/state", {})["boxes"], [])
            request(first, "logout")
            with self.assertRaises(RuleError):
                world.run(first, "/state", {})
            self.assertEqual(request(second, "profile")["email"], "test@example.com")

    def test_friend_request_requires_receiver_confirmation(self):
        with tempfile.TemporaryDirectory() as directory:
            world = World(os.path.join(directory, "friends.sqlite"))

            def request(token, action, **data):
                return account_auth.account_request(world, token, "/account/" + action, data, RuleError)

            def register(email):
                token = account_auth.authenticate(world, "/account/register",
                                                  {"email": email, "password": "test password"}, RuleError)["token"]
                return token, request(token, "profile")["friendCode"]

            first, first_code = register("first@example.com")
            second, second_code = register("second@example.com")
            request(first, "friend/request", friendCode=second_code.lower())
            self.assertEqual(request(first, "profile")["outgoingFriends"], [second_code])
            self.assertEqual(request(second, "profile")["incomingFriends"], [first_code])
            with self.assertRaises(RuleError):
                request(first, "friend/accept", friendCode=second_code)
            request(second, "friend/accept", friendCode=first_code)
            self.assertEqual(request(first, "profile")["friends"], [second_code])
            self.assertEqual(request(second, "profile")["friends"], [first_code])
            self.assertEqual(request(second, "friend/remove", friendCode=first_code)["friends"], [])
            self.assertEqual(request(first, "profile")["friends"], [])
            request(first, "friend/request", friendCode=second_code)
            request(first, "friend/remove", friendCode=second_code)
            self.assertEqual(request(second, "profile")["incomingFriends"], [first_code])


class AccountNetworkTests(unittest.TestCase):
    def test_network_gate_requires_development_and_lan_opt_in(self):
        from types import SimpleNamespace

        handler = Handler.__new__(Handler)
        handler.server = SimpleNamespace(development=True, lan_account_tests=False)
        handler.client_address = ("127.0.0.1", 50000)
        self.assertTrue(handler.account_tests_allowed())
        handler.client_address = ("192.168.10.42", 50000)
        self.assertFalse(handler.account_tests_allowed())
        handler.server.lan_account_tests = True
        self.assertTrue(handler.account_tests_allowed())
        handler.client_address = ("8.8.8.8", 50000)
        self.assertFalse(handler.account_tests_allowed())
        handler.server.development = False
        handler.client_address = ("127.0.0.1", 50000)
        self.assertFalse(handler.account_tests_allowed())
