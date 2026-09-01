from datetime import date, datetime, timedelta, timezone
import re
import sqlite3

import pytest
from fastapi.testclient import TestClient

from backend.main import create_app


TEST_TODAY = date(2026, 8, 30)


@pytest.fixture
def client(tmp_path):
    app = create_app(
        db_path=tmp_path / "smart-ledger.sqlite",
        today_provider=lambda: TEST_TODAY,
    )
    with TestClient(app) as test_client:
        yield test_client


@pytest.mark.parametrize(
    "text, amount, transaction_type, category, note, transaction_date",
    [
        ("5块买菜", 500, "expense", "groceries_food", "买菜", "2026-08-30"),
        ("18块吃面", 1800, "expense", "dining", "吃面", "2026-08-30"),
        ("300加油", 30000, "expense", "vehicle_fuel", "加油", "2026-08-30"),
        ("20打车", 2000, "expense", "transportation", "打车", "2026-08-30"),
        ("8000工资", 800000, "income", "salary", "工资", "2026-08-30"),
        ("工资到账8000", 800000, "income", "salary", "工资", "2026-08-30"),
        ("昨天买菜35", 3500, "expense", "groceries_food", "买菜", "2026-08-29"),
        ("今天午饭15块", 1500, "expense", "dining", "午饭", "2026-08-30"),
        ("给孩子买东西80", 8000, "expense", "children", "给孩子买东西", "2026-08-30"),
        ("带孩子吃饭86", 8600, "expense", "dining", "带孩子吃饭", "2026-08-30"),
        ("奖金500", 50000, "income", "other_income", "奖金", "2026-08-30"),
        ("话费50", 5000, "expense", "communication", "话费", "2026-08-30"),
        ("医院挂号20", 2000, "expense", "medical", "医院挂号", "2026-08-30"),
        ("房租800", 80000, "expense", "housing", "房租", "2026-08-30"),
        ("买衣服200", 20000, "expense", "other_expense", "买衣服", "2026-08-30"),
    ],
)
def test_parse_normal_examples(
    client,
    text,
    amount,
    transaction_type,
    category,
    note,
    transaction_date,
):
    response = client.post("/api/parse", json={"text": text})

    assert response.status_code == 200
    body = response.json()
    assert body["draft"] == {
        "amount_cents": amount,
        "type": transaction_type,
        "category": category,
        "note": note,
        "original_text": text,
        "transaction_date": transaction_date,
    }


def test_parse_abnormal_examples(client):
    only_amount = client.post("/api/parse", json={"text": "35"}).json()
    assert only_amount["status"] == "needs_input"
    assert only_amount["draft"]["amount_cents"] == 3500
    assert only_amount["draft"]["type"] is None
    assert only_amount["draft"]["category"] is None
    assert set(["type", "category"]).issubset(only_amount["missing_fields"])
    assert any(item["code"] == "TYPE_UNKNOWN" for item in only_amount["warnings"])

    missing_amount = client.post("/api/parse", json={"text": "买菜"}).json()
    assert missing_amount["status"] == "needs_input"
    assert missing_amount["draft"]["amount_cents"] is None
    assert missing_amount["draft"]["category"] == "groceries_food"
    assert "amount_cents" in missing_amount["missing_fields"]
    assert any(item["code"] == "MISSING_AMOUNT" for item in missing_amount["warnings"])

    multiple = client.post(
        "/api/parse", json={"text": "买菜35又打车20"}
    ).json()
    assert multiple["status"] == "needs_input"
    assert multiple["draft"]["amount_cents"] is None
    assert multiple["draft"]["category"] is None
    assert multiple["draft"]["note"] == "买菜又打车"
    warning_codes = {item["code"] for item in multiple["warnings"]}
    assert {"MULTIPLE_AMOUNTS", "CATEGORY_AMBIGUOUS"}.issubset(warning_codes)

    child_meal = client.post("/api/parse", json={"text": "带孩子吃饭86"}).json()
    assert any(item["code"] == "CATEGORY_CONFLICT" for item in child_meal["warnings"])

    empty = client.post("/api/parse", json={"text": ""}).json()
    assert empty == {
        "status": "no_draft",
        "needs_confirmation": False,
        "draft": None,
        "missing_fields": [],
        "warnings": [],
    }


def test_parse_keeps_original_text_and_does_not_save(client):
    original = "  今天午饭15块  "
    response = client.post("/api/parse", json={"text": original})

    assert response.status_code == 200
    assert response.json()["draft"]["original_text"] == original
    assert client.get("/api/transactions").json()["total"] == 0


def test_parse_negative_and_future_amounts(client):
    negative = client.post("/api/parse", json={"text": "-5元买菜"}).json()
    assert negative["status"] == "needs_input"
    assert negative["draft"]["amount_cents"] is None
    assert any(item["code"] == "INVALID_AMOUNT" for item in negative["warnings"])

    future = client.post("/api/parse", json={"text": "12月20日买菜35"}).json()
    assert future["status"] == "needs_input"
    assert future["draft"]["transaction_date"] == "2026-12-20"
    assert any(item["code"] == "FUTURE_DATE" for item in future["warnings"])


def test_categories_returns_all_fixed_codes(client):
    response = client.get("/api/categories")

    assert response.status_code == 200
    items = response.json()["items"]
    assert len(items) == 13
    assert {item["code"] for item in items} == {
        "dining",
        "groceries_food",
        "daily_necessities",
        "transportation",
        "vehicle_fuel",
        "housing",
        "communication",
        "entertainment",
        "children",
        "medical",
        "other_expense",
        "salary",
        "other_income",
    }


def test_transaction_crud_soft_delete_restore_and_summary(client):
    payload = {
        "amount_cents": 3500,
        "type": "expense",
        "category": "groceries_food",
        "note": "买菜",
        "original_text": "昨天35块买菜",
        "transaction_date": "2026-08-30",
    }
    created_response = client.post("/api/transactions", json=payload)
    assert created_response.status_code == 201
    created = created_response.json()["transaction"]
    transaction_id = created["id"]
    assert created["amount_cents"] == 3500
    assert created["deleted_at"] is None

    listing = client.get("/api/transactions")
    assert listing.status_code == 200
    assert listing.json()["total"] == 1
    assert listing.json()["items"][0]["id"] == transaction_id

    detail = client.get(f"/api/transactions/{transaction_id}")
    assert detail.status_code == 200
    assert detail.json()["original_text"] == "昨天35块买菜"

    updated_response = client.put(
        f"/api/transactions/{transaction_id}",
        json={
            "amount_cents": 3580,
            "type": "expense",
            "category": "groceries_food",
            "note": "买菜和水果",
            "transaction_date": "2026-08-30",
        },
    )
    assert updated_response.status_code == 200
    updated = updated_response.json()
    assert updated["id"] == transaction_id
    assert updated["amount_cents"] == 3580
    assert updated["note"] == "买菜和水果"
    assert updated["original_text"] == "昨天35块买菜"

    summary = client.get("/api/summary")
    assert summary.json() == {
        "today_expense_cents": 3580,
        "month_expense_cents": 3580,
        "month_income_cents": 0,
    }

    deleted_response = client.delete(f"/api/transactions/{transaction_id}")
    assert deleted_response.status_code == 200
    deleted = deleted_response.json()
    assert deleted["deleted"] is True
    assert deleted["id"] == transaction_id
    assert deleted["restore_url"] == f"/api/transactions/{transaction_id}/restore"
    assert client.get("/api/transactions").json()["total"] == 0
    assert client.get("/api/summary").json()["today_expense_cents"] == 0
    assert client.get(f"/api/transactions/{transaction_id}").status_code == 404

    restored_response = client.post(
        f"/api/transactions/{transaction_id}/restore"
    )
    assert restored_response.status_code == 200
    restored = restored_response.json()
    assert restored["restored"] is True
    assert restored["transaction"]["id"] == transaction_id
    assert restored["transaction"]["deleted_at"] is None
    assert client.get("/api/transactions").json()["total"] == 1
    assert client.get("/api/summary").json()["today_expense_cents"] == 3580


def test_invalid_transaction_values_use_contract_error(client):
    base = {
        "amount_cents": 100,
        "type": "expense",
        "category": "dining",
        "note": None,
        "original_text": "测试账目",
        "transaction_date": "2026-08-30",
    }
    invalid_values = [
        ("amount_cents", 0),
        ("amount_cents", -100),
        ("category", "salary"),
        ("transaction_date", "2026-12-20"),
        ("original_text", "   "),
        ("note", "x" * 201),
    ]

    for field, value in invalid_values:
        payload = dict(base)
        payload[field] = value
        response = client.post("/api/transactions", json=payload)
        assert response.status_code == 400
        assert response.json()["error"]["code"] == "VALIDATION_ERROR"


def test_duplicate_warning_can_be_confirmed(client):
    payload = {
        "amount_cents": 2000,
        "type": "expense",
        "category": "transportation",
        "note": "打车",
        "original_text": "20打车",
        "transaction_date": "2026-08-30",
    }
    first = client.post("/api/transactions", json=payload)
    assert first.status_code == 201

    duplicate = client.post("/api/transactions", json=payload)
    assert duplicate.status_code == 200
    assert duplicate.json()["duplicate_warning"] is True
    assert duplicate.json()["transaction"] is None
    assert duplicate.json()["similar_transaction"]["id"] == first.json()["transaction"]["id"]

    confirmed = client.post(
        "/api/transactions",
        json={**payload, "confirm_duplicate": True},
    )
    assert confirmed.status_code == 201
    assert client.get("/api/transactions").json()["total"] == 2


def test_backup_is_a_valid_sqlite_file(client, tmp_path):
    response = client.post(
        "/api/transactions",
        json={
            "amount_cents": 500,
            "type": "expense",
            "category": "groceries_food",
            "note": "买菜",
            "original_text": "5块买菜",
            "transaction_date": "2026-08-30",
        },
    )
    assert response.status_code == 201

    backup = client.get("/api/backup")
    assert backup.status_code == 200
    assert backup.headers["content-type"].startswith("application/vnd.sqlite3")
    assert re.search(
        r'smart-ledger-backup-\d{8}-\d{6}\.sqlite',
        backup.headers["content-disposition"],
    )

    backup_path = tmp_path / "downloaded.sqlite"
    backup_path.write_bytes(backup.content)
    connection = sqlite3.connect(backup_path)
    try:
        table = connection.execute(
            "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'transactions'"
        ).fetchone()
        count = connection.execute("SELECT count(*) FROM transactions").fetchone()[0]
    finally:
        connection.close()
    assert table == ("transactions",)
    assert count == 1


def test_invalid_json_and_unhashable_types_use_contract_error(client):
    invalid_json = client.post(
        "/api/transactions", content=b"{", headers={"Content-Type": "application/json"}
    )
    assert invalid_json.status_code == 400
    assert invalid_json.json()["error"]["code"] == "INVALID_REQUEST"

    invalid_type = client.post(
        "/api/transactions",
        json={
            "amount_cents": 100,
            "type": [],
            "category": [],
            "note": None,
            "original_text": "测试",
            "transaction_date": "2026-08-30",
        },
    )
    assert invalid_type.status_code == 400
    assert invalid_type.json()["error"]["code"] == "VALIDATION_ERROR"


def test_restore_window_expiry_is_a_conflict(tmp_path):
    current_time = [datetime(2026, 8, 30, 12, 0, tzinfo=timezone.utc)]
    app = create_app(
        db_path=tmp_path / "smart-ledger.sqlite",
        today_provider=lambda: TEST_TODAY,
        now_provider=lambda: current_time[0],
    )
    with TestClient(app) as test_client:
        created = test_client.post(
            "/api/transactions",
            json={
                "amount_cents": 100,
                "type": "expense",
                "category": "dining",
                "note": "测试",
                "original_text": "1块测试",
                "transaction_date": "2026-08-30",
            },
        )
        transaction_id = created.json()["transaction"]["id"]
        assert test_client.delete(f"/api/transactions/{transaction_id}").status_code == 200
        current_time[0] += timedelta(seconds=11)
        expired = test_client.post(
            f"/api/transactions/{transaction_id}/restore"
        )

    assert expired.status_code == 409
    assert expired.json()["error"]["code"] == "RESTORE_WINDOW_EXPIRED"
