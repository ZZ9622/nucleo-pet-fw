"""Email accounts and short-lived sessions for the local account prototype."""
import hashlib
import re
import secrets
import uuid

from . import shop

SESSION_SECONDS = 7 * 86400


def migrate(db):
    db.executescript("""
        CREATE TABLE IF NOT EXISTS accounts(
            owner TEXT PRIMARY KEY, email TEXT NOT NULL UNIQUE,
            salt BLOB NOT NULL, password_hash BLOB NOT NULL, friend_code TEXT NOT NULL UNIQUE);
        CREATE TABLE IF NOT EXISTS account_sessions(
            token_hash TEXT PRIMARY KEY, owner TEXT NOT NULL, expires INTEGER NOT NULL);
        CREATE TABLE IF NOT EXISTS account_pomi(
            pomi TEXT PRIMARY KEY, owner TEXT NOT NULL);
        CREATE INDEX IF NOT EXISTS account_pomi_owner ON account_pomi(owner);
        CREATE TABLE IF NOT EXISTS account_friends(
            first TEXT NOT NULL, second TEXT NOT NULL, sender TEXT NOT NULL,
            accepted INTEGER NOT NULL DEFAULT 0, PRIMARY KEY(first, second));
    """)
    shop.migrate(db)


def digest(token):
    return hashlib.sha256(token.encode()).hexdigest()


def password_hash(password, salt):
    return hashlib.pbkdf2_hmac("sha256", password.encode(), salt, 600_000)


def authenticate(world, path, body, error):
    email, password = body.get("email"), body.get("password")
    if not isinstance(email, str) or not isinstance(password, str):
        raise error("请输入邮箱和密码")
    email = email.strip().lower()
    if len(email) > 254 or not re.fullmatch(r"[^@\s]+@[^@\s]+\.[^@\s]+", email):
        raise error("请输入有效邮箱")
    if not 8 <= len(password) <= 128:
        raise error("密码需为 8 到 128 个字符")
    token = secrets.token_urlsafe(32)
    now = int(world.clock())
    if path == "/account/register":
        salt = secrets.token_bytes(16)
        verifier = password_hash(password, salt)
        owner = str(uuid.uuid4())
        code = secrets.token_hex(8).upper()
        with world.db() as db:
            if db.execute("SELECT 1 FROM accounts WHERE email=?", (email,)).fetchone():
                raise error("该邮箱已注册")
            world.insert_user(db, owner, None)
            db.execute("INSERT INTO accounts VALUES(?,?,?,?,?)", (owner, email, salt, verifier, code))
            db.execute("INSERT INTO account_sessions VALUES(?,?,?)", (digest(token), owner, now+SESSION_SECONDS))
    else:
        with world.db() as db:
            account = db.execute("SELECT * FROM accounts WHERE email=?", (email,)).fetchone()
        verifier = password_hash(password, account["salt"] if account else bytes(16))
        if not account or not secrets.compare_digest(verifier, account["password_hash"]):
            raise error("邮箱或密码错误")
        owner = account["owner"]
        with world.db() as db:
            db.execute("DELETE FROM account_sessions WHERE expires<=?", (now,))
            db.execute("INSERT INTO account_sessions VALUES(?,?,?)", (digest(token), owner, now+SESSION_SECONDS))
    return {"token": token}


def account_request(world, token, path, body, error):
    with world.db() as db:
        row = db.execute(
            "SELECT a.* FROM accounts a JOIN account_sessions s ON s.owner=a.owner "
            "WHERE s.token_hash=? AND s.expires>?", (digest(token), int(world.clock()))
        ).fetchone()
        if not row:
            raise error("登录已失效，请重新登录")
        owner = row["owner"]
        if path == "/account/logout":
            db.execute("DELETE FROM account_sessions WHERE token_hash=?", (digest(token),))
            return {}
        if path == "/account/shop/listings":
            return shop.listings(db, owner, body, error)
        if path == "/account/test-bind":
            try:
                pomi = str(uuid.UUID(body.get("pomiID", "")))
            except (ValueError, TypeError, AttributeError):
                raise error("Pomi 编号必须是有效的 UUID")
            binding = db.execute("SELECT owner FROM account_pomi WHERE pomi=?", (pomi,)).fetchone()
            if binding and binding["owner"] != owner:
                raise error("这只 Pomi 已绑定其他账号")
            db.execute("INSERT OR IGNORE INTO account_pomi VALUES(?,?)", (pomi, owner))
        elif path in ("/account/friend/request", "/account/friend/accept", "/account/friend/remove"):
            code = body.get("friendCode")
            if not isinstance(code, str):
                raise error("请输入好友码")
            target = db.execute("SELECT owner FROM accounts WHERE friend_code=?", (code.strip().upper(),)).fetchone()
            if not target or target["owner"] == owner:
                raise error("找不到这个好友码，或它是你自己的")
            first, second = sorted((owner, target["owner"]))
            if path == "/account/friend/request":
                db.execute("INSERT OR IGNORE INTO account_friends(first,second,sender) VALUES(?,?,?)",
                           (first, second, owner))
            elif path == "/account/friend/remove":
                db.execute("DELETE FROM account_friends WHERE first=? AND second=? AND accepted=1",
                           (first, second))
            else:
                changed = db.execute("UPDATE account_friends SET accepted=1 "
                                     "WHERE first=? AND second=? AND sender!=?",
                                     (first, second, owner)).rowcount
                if not changed:
                    raise error("没有这条待确认的好友申请")
        elif path != "/account/profile":
            raise error("未知账号操作")
        devices = db.execute("SELECT pomi FROM account_pomi WHERE owner=? ORDER BY pomi", (owner,))
        links = db.execute(
            "SELECT a.friend_code, f.accepted, f.sender FROM account_friends f JOIN accounts a "
            "ON a.owner=CASE WHEN f.first=? THEN f.second ELSE f.first END "
            "WHERE f.first=? OR f.second=? ORDER BY a.friend_code", (owner, owner, owner)
        ).fetchall()
        return {
            "email": row["email"], "friendCode": row["friend_code"], "pomiIDs": [r["pomi"] for r in devices],
            "friends": [r["friend_code"] for r in links if r["accepted"]],
            "incomingFriends": [r["friend_code"] for r in links if not r["accepted"] and r["sender"] != owner],
            "outgoingFriends": [r["friend_code"] for r in links if not r["accepted"] and r["sender"] == owner],
        }
