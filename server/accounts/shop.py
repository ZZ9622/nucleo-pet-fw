"""Account shop listings hold items until cancellation or a completed exchange."""
import json
import uuid


def migrate(db):
    db.execute("""
        CREATE TABLE IF NOT EXISTS shop_listings(
            id TEXT PRIMARY KEY, seller TEXT NOT NULL,
            item TEXT NOT NULL, wanted_kind TEXT NOT NULL)
    """)
    columns = {row[1] for row in db.execute("PRAGMA table_info(shop_listings)")}
    if "wanted_kinds" not in columns:
        db.execute("ALTER TABLE shop_listings ADD COLUMN wanted_kinds TEXT")
    db.execute("CREATE INDEX IF NOT EXISTS shop_seller ON shop_listings(seller)")



def wanted_kinds(listing):
    return json.loads(listing["wanted_kinds"]) if listing["wanted_kinds"] else [listing["wanted_kind"]]


def require_friend(db, owner, friend, error):
    first, second = sorted((owner, friend))
    if not db.execute(
        "SELECT 1 FROM account_friends WHERE first=? AND second=? AND accepted=1",
        (first, second),
    ).fetchone():
        raise error("只有好友可以访问这间小卖部")


def listings(db, owner, body, error):
    code = body.get("friendCode")
    seller = owner
    if code is not None:
        if not isinstance(code, str):
            raise error("好友码无效")
        target = db.execute("SELECT owner FROM accounts WHERE friend_code=?", (code,)).fetchone()
        if not target:
            raise error("找不到这位好友")
        seller = target["owner"]
        require_friend(db, owner, seller, error)
    return {"listings": [
        {
            "id": row["id"],
            "item": json.loads(row["item"]),
            "wantedKind": row["wanted_kind"],
            "wantedKinds": wanted_kinds(row),
        }
        for row in db.execute("SELECT * FROM shop_listings WHERE seller=? ORDER BY rowid DESC", (seller,))
    ]}


def mutate(world, db, owner, state, path, body, catalog, find_item, error):
    if path == "/shop/starter":
        if not state.get("shopStarterClaimed"):
            state["items"].extend(world.item(entry["id"]) for entry in catalog)
            state["shopStarterClaimed"] = True
            world.note(state, "领取了小卖部测试物品")
        return
    if path == "/shop/list":
        wanted = body.get("wantedKinds", [body.get("wantedKind")])
        catalog_ids = {entry["id"] for entry in catalog}
        if (not isinstance(wanted, list) or not 1 <= len(wanted) <= 3
                or any(not isinstance(kind, str) or kind not in catalog_ids for kind in wanted)
                or len(set(wanted)) != len(wanted)):
            raise error("请选择 1 到 3 种不同的交换物品")
        item = find_item()
        if db.execute("SELECT COUNT(*) FROM shop_listings WHERE seller=?", (owner,)).fetchone()[0] >= 30:
            raise error("小卖部最多上架 30 件物品")
        db.execute(
            "INSERT INTO shop_listings(id,seller,item,wanted_kind,wanted_kinds) VALUES(?,?,?,?,?)",
            (str(uuid.uuid4()), owner, json.dumps(item), wanted[0], json.dumps(wanted)),
        )
        state["items"].remove(item)
        world.note(state, "把一件物品放到了小卖部")
        return

    if path not in ("/shop/cancel", "/shop/exchange"):
        raise error("未知小卖部操作")
    listing_id = body.get("listingID")
    if not isinstance(listing_id, str):
        raise error("挂单编号无效")
    listing = db.execute("SELECT * FROM shop_listings WHERE id=?", (listing_id,)).fetchone()
    if not listing:
        raise error("这件物品已经下架或换走了")
    offered = json.loads(listing["item"])
    seller = listing["seller"]
    if path == "/shop/cancel":
        if seller != owner:
            raise error("只能下架自己的物品")
        state["items"].append(offered)
        world.note(state, "从小卖部收回了一件物品")
    else:
        require_friend(db, owner, seller, error)
        payment = find_item()
        if payment["kind"] not in wanted_kinds(listing) or payment["level"] != 1:
            raise error("请选择对方想要的 Lv1 物品")
        other = db.execute("SELECT data FROM users WHERE id=?", (seller,)).fetchone()
        if not other:
            raise error("对方仓库暂时不可用")
        seller_state = json.loads(other["data"])
        seller_state["items"].append(payment)
        world.note(seller_state, "在小卖部换到了一件物品")
        db.execute("UPDATE users SET data=? WHERE id=?", (json.dumps(seller_state), seller))
        state["items"].remove(payment)
        state["items"].append(offered)
        world.note(state, "在好友的小卖部换到了一件物品")
    db.execute("DELETE FROM shop_listings WHERE id=?", (listing_id,))
