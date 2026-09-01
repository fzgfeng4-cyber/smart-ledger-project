from __future__ import annotations

import os
import re
import sqlite3
import tempfile
from dataclasses import dataclass
from datetime import date, datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Callable, Iterable

from fastapi import FastAPI, Request, Response
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, JSONResponse
from starlette.background import BackgroundTask
from starlette.exceptions import HTTPException as StarletteHTTPException


MAX_SQLITE_INTEGER = 9_223_372_036_854_775_807
MAX_RESTORE_SECONDS = 10
DEFAULT_DB_PATH = Path(__file__).resolve().parent / "data" / "smart-ledger.sqlite"


CATEGORIES: tuple[dict[str, str], ...] = (
    {"code": "dining", "name": "餐饮", "type": "expense"},
    {"code": "groceries_food", "name": "买菜/食品", "type": "expense"},
    {"code": "daily_necessities", "name": "日用品", "type": "expense"},
    {"code": "transportation", "name": "交通", "type": "expense"},
    {"code": "vehicle_fuel", "name": "车辆/加油", "type": "expense"},
    {"code": "housing", "name": "居住", "type": "expense"},
    {"code": "communication", "name": "通讯", "type": "expense"},
    {"code": "entertainment", "name": "娱乐", "type": "expense"},
    {"code": "children", "name": "孩子", "type": "expense"},
    {"code": "medical", "name": "医疗", "type": "expense"},
    {"code": "other_expense", "name": "其他支出", "type": "expense"},
    {"code": "salary", "name": "工资", "type": "income"},
    {"code": "other_income", "name": "其他收入", "type": "income"},
)
CATEGORY_BY_CODE = {item["code"]: item for item in CATEGORIES}
ALLOWED_CATEGORIES_BY_TYPE = {
    "expense": {
        item["code"] for item in CATEGORIES if item["type"] == "expense"
    },
    "income": {
        item["code"] for item in CATEGORIES if item["type"] == "income"
    },
}


@dataclass(frozen=True)
class CategoryRule:
    code: str
    keywords: tuple[str, ...]


CATEGORY_RULES: tuple[CategoryRule, ...] = (
    CategoryRule(
        "dining",
        (
            "麦当劳",
            "餐馆",
            "火锅",
            "早餐",
            "午饭",
            "午餐",
            "晚饭",
            "晚餐",
            "夜宵",
            "吃饭",
            "吃面",
            "外卖",
            "奶茶",
            "咖啡",
            "饮料",
            "吃",
            "饭",
            "面",
            "粉",
            "餐",
        ),
    ),
    CategoryRule(
        "groceries_food",
        (
            "菜市场",
            "蔬菜",
            "粮油",
            "食品",
            "水果",
            "零食",
            "生鲜",
            "食材",
            "买菜",
            "买肉",
            "肉",
            "买米",
            "米",
        ),
    ),
    CategoryRule(
        "daily_necessities",
        (
            "日用品",
            "纸巾",
            "厕纸",
            "洗衣液",
            "洗发水",
            "牙膏",
            "肥皂",
            "清洁用品",
            "家居消耗品",
        ),
    ),
    CategoryRule(
        "transportation",
        (
            "出租车",
            "公交车",
            "打车",
            "公交",
            "地铁",
            "出行",
            "车票",
            "乘车",
            "通勤",
        ),
    ),
    CategoryRule(
        "vehicle_fuel",
        (
            "车辆保养",
            "车辆维修",
            "汽车充电",
            "高速费",
            "加油",
            "油费",
            "停车",
            "洗车",
        ),
    ),
    CategoryRule(
        "housing",
        (
            "房租",
            "租金",
            "物业",
            "水费",
            "电费",
            "燃气",
            "房贷",
            "居住费用",
        ),
    ),
    CategoryRule(
        "communication",
        (
            "手机费",
            "宽带",
            "流量",
            "电话费",
            "通讯费",
            "网络费",
            "话费",
        ),
    ),
    CategoryRule(
        "entertainment",
        (
            "演唱会",
            "游戏充值",
            "电影票",
            "电影",
            "游戏",
            "会员",
            "娱乐",
            "唱歌",
            "游玩",
        ),
    ),
    CategoryRule(
        "children",
        (
            "儿童用品",
            "孩子学费",
            "奶粉",
            "尿布",
            "给孩子",
            "带孩子",
            "孩子",
            "小孩",
            "宝宝",
            "娃",
        ),
    ),
    CategoryRule(
        "medical",
        (
            "医院",
            "看病",
            "挂号",
            "买药",
            "检查",
            "治疗",
            "体检",
            "医疗",
            "药",
        ),
    ),
)

INCOME_KEYWORDS: tuple[str, ...] = (
    "工资到账",
    "发工资",
    "兼职收入",
    "红包收入",
    "工资",
    "薪资",
    "月薪",
    "薪酬",
    "奖金",
    "分红",
    "收款",
    "收到",
    "到账",
    "赚到",
    "收入",
)
EXPENSE_KEYWORDS: tuple[str, ...] = (
    "购买",
    "支出",
    "付款",
    "支付",
    "消费",
    "花了",
    "买菜",
    "买东西",
    "买",
    "吃饭",
    "吃面",
    "早餐",
    "午饭",
    "午餐",
    "晚饭",
    "晚餐",
    "奶茶",
    "咖啡",
    "买肉",
    "水果",
    "打车",
    "出租车",
    "公交",
    "地铁",
    "加油",
    "停车",
    "房租",
    "话费",
    "看病",
    "挂号",
    "买药",
    "电影",
    "游戏",
    "买衣服",
)
UNSUPPORTED_DATE_MARKERS: tuple[str, ...] = (
    "明天",
    "后天",
    "上周",
    "下周",
    "本周",
    "去年",
    "明年",
    "上个月",
    "下个月",
    "这个月最后",
    "春节前",
)
DATE_TIME_WORDS: tuple[str, ...] = (
    "今天",
    "昨天",
    "前天",
    "早上",
    "上午",
    "中午",
    "下午",
    "晚上",
)
SENTENCE_SKELETON_WORDS: tuple[str, ...] = (
    "花了",
    "花费",
    "支付了",
    "支付",
    "付款了",
    "付款",
    "消费了",
    "消费",
    "支出",
    "记一笔",
    "记账",
    "到账",
)

_ISO_DATE_PATTERN = re.compile(
    r"(?<!\d)(?P<iso>\d{4}-\d{2}-\d{2})(?!\d)"
)
_CHINESE_DATE_PATTERN = re.compile(
    r"(?<!\d)(?P<year>\d{4})年(?P<year_month>\d{1,2})月"
    r"(?P<year_day>\d{1,2})(?:日|号)"
    r"|(?<!\d)(?P<month>\d{1,2})月(?P<day>\d{1,2})(?:日|号)"
)
_AMOUNT_PATTERN = re.compile(r"(?<![\d.])-?\d+(?:\.\d+)?(?![\d.])")
_POSITIVE_INTEGER_PATTERN = re.compile(r"^[1-9]\d*$")


class ApiError(Exception):
    def __init__(
        self,
        status_code: int,
        code: str,
        message: str,
        details: list[dict[str, str]] | None = None,
    ) -> None:
        super().__init__(message)
        self.status_code = status_code
        self.code = code
        self.message = message
        self.details = details or []


class BackupError(Exception):
    """SQLite 安全备份失败。"""


def _warning(
    code: str,
    field: str | None,
    message: str,
    candidates: Iterable[str] = (),
) -> dict[str, Any]:
    return {
        "code": code,
        "field": field,
        "message": message,
        "candidates": list(candidates),
    }


def _masked_text(text: str, spans: Iterable[tuple[int, int]]) -> str:
    mask = [False] * len(text)
    for start, end in spans:
        for index in range(max(0, start), min(len(text), end)):
            mask[index] = True
    return "".join(" " if masked else character for character, masked in zip(text, mask))


def _without_spans(text: str, spans: Iterable[tuple[int, int]]) -> str:
    pieces: list[str] = []
    cursor = 0
    for start, end in sorted(spans):
        if start < cursor:
            continue
        pieces.append(text[cursor:start])
        cursor = min(len(text), end)
    pieces.append(text[cursor:])
    return "".join(pieces)


def _parse_date(
    text: str,
    today: date,
) -> tuple[date | None, list[tuple[int, int]], list[dict[str, Any]], bool]:
    spans: list[tuple[int, int]] = []
    date_values: list[date | None] = []
    warnings: list[dict[str, Any]] = []

    for match in _ISO_DATE_PATTERN.finditer(text):
        spans.append(match.span())
        try:
            date_values.append(date.fromisoformat(match.group("iso")))
        except ValueError:
            date_values.append(None)

    for match in _CHINESE_DATE_PATTERN.finditer(text):
        spans.append(match.span())
        try:
            if match.group("year") is not None:
                date_values.append(
                    date(
                        int(match.group("year")),
                        int(match.group("year_month")),
                        int(match.group("year_day")),
                    )
                )
            else:
                date_values.append(
                    date(
                        today.year,
                        int(match.group("month")),
                        int(match.group("day")),
                    )
                )
        except ValueError:
            date_values.append(None)

    relative_matches = list(re.finditer(r"今天|昨天|前天", text))
    for match in relative_matches:
        spans.append(match.span())
        if match.group() == "今天":
            date_values.append(today)
        elif match.group() == "昨天":
            date_values.append(today - timedelta(days=1))
        else:
            date_values.append(today - timedelta(days=2))

    if len(date_values) > 1:
        warnings.append(
            _warning(
                "DATE_AMBIGUOUS",
                "transaction_date",
                "识别到多个日期，请只保留一个账务日期。",
            )
        )
        return None, spans, warnings, True

    if date_values:
        parsed_date = date_values[0]
        if parsed_date is None:
            warnings.append(
                _warning(
                    "INVALID_DATE",
                    "transaction_date",
                    "日期格式或日期值无效，请改成有效日期。",
                )
            )
            return None, spans, warnings, True
        if parsed_date > today:
            warnings.append(
                _warning(
                    "FUTURE_DATE",
                    "transaction_date",
                    "这个日期在未来，请检查日期。",
                )
            )
        return parsed_date, spans, warnings, False

    if any(marker in text for marker in UNSUPPORTED_DATE_MARKERS):
        warnings.append(
            _warning(
                "UNSUPPORTED_DATE",
                "transaction_date",
                "暂不支持这种日期表达，请选择有效的日期。",
            )
        )
        return None, spans, warnings, True

    return today, spans, warnings, False


def _amount_to_cents(raw_amount: str) -> int | None:
    if raw_amount.startswith("-"):
        return None
    integer_part, dot, fraction_part = raw_amount.partition(".")
    if dot and len(fraction_part) > 2:
        return None
    if not integer_part.isdigit():
        return None
    fraction = fraction_part.ljust(2, "0") if dot else "00"
    cents = int(integer_part) * 100 + int(fraction or "0")
    if cents <= 0 or cents > MAX_SQLITE_INTEGER:
        return None
    return cents


def _amount_spans(text: str, masked_text: str) -> tuple[
    list[tuple[int, int]], list[int], bool
]:
    spans: list[tuple[int, int]] = []
    values: list[int] = []
    has_unit = True
    matches = list(_AMOUNT_PATTERN.finditer(masked_text))
    if len(matches) == 1:
        has_unit = False

    for match in matches:
        start, end = match.span()
        extended_end = end
        if text.startswith("块钱", end):
            extended_end += 2
            has_unit = True
        elif text.startswith("元", end) or text.startswith("块", end):
            extended_end += 1
            has_unit = True
        elif start > 0 and text[start - 1] in {"元", "块"}:
            start -= 1
            has_unit = True
        spans.append((start, extended_end))
        parsed = _amount_to_cents(match.group())
        if parsed is not None:
            values.append(parsed)
    return spans, values, has_unit


def _find_keywords(text: str, keywords: Iterable[str]) -> list[str]:
    return [keyword for keyword in keywords if keyword in text]


def _category_candidates(text: str) -> list[str]:
    candidates: list[str] = []
    for rule in CATEGORY_RULES:
        if any(keyword in text for keyword in rule.keywords):
            candidates.append(rule.code)

    salary_keywords = ("工资到账", "发工资", "工资", "薪资", "月薪", "薪酬")
    other_income_keywords = (
        "奖金",
        "分红",
        "兼职收入",
        "收款",
        "收到",
        "赚到",
        "红包收入",
        "收入",
        "到账",
    )
    has_salary = any(keyword in text for keyword in salary_keywords)
    has_other_income = any(keyword in text for keyword in other_income_keywords)
    if has_salary:
        candidates.append("salary")
    if has_other_income:
        candidates.append("other_income")
    return list(dict.fromkeys(candidates))


def _choose_category(
    transaction_type: str | None,
    candidates: list[str],
    amount_count: int,
) -> tuple[str | None, list[dict[str, Any]]]:
    if transaction_type is None:
        return None, []

    matching = [
        code for code in candidates if code in ALLOWED_CATEGORIES_BY_TYPE[transaction_type]
    ]
    if transaction_type == "income":
        if "salary" in matching:
            return "salary", []
        if len(matching) == 1:
            if matching[0] == "other_income":
                return matching[0], [
                    _warning(
                        "CATEGORY_FALLBACK",
                        "category",
                        "收入分类需要确认，请确认是工资还是其他收入。",
                    )
                ]
            return matching[0], []
        if len(matching) > 1:
            return "other_income", [
                _warning(
                    "CATEGORY_AMBIGUOUS",
                    "category",
                    "这句话可能包含多个收入事项，请选择一笔账对应的分类。",
                    matching,
                )
            ]
        return "other_income", [
            _warning(
                "CATEGORY_FALLBACK",
                "category",
                "未能确定具体收入分类，请确认其他收入或修改分类。",
            )
        ]

    if not matching:
        return "other_expense", [
            _warning(
                "CATEGORY_FALLBACK",
                "category",
                "未能确定具体分类，请确认其他支出或修改分类。",
            )
        ]

    if len(matching) == 1:
        return matching[0], []

    if set(matching) == {"dining", "children"}:
        return "dining", [
            _warning(
                "CATEGORY_CONFLICT",
                "category",
                "同时出现孩子和餐饮信息，已按核心消费行为建议餐饮，可修改。",
                ("dining", "children"),
            )
        ]

    if "children" in matching:
        core_categories = [code for code in matching if code != "children"]
        if len(core_categories) == 1:
            return core_categories[0], [
                _warning(
                    "CATEGORY_AMBIGUOUS",
                    "category",
                    "同时出现人物和消费事项，已按核心消费行为建议分类，可修改。",
                    matching,
                )
            ]

    if amount_count > 1:
        return None, [
            _warning(
                "CATEGORY_AMBIGUOUS",
                "category",
                "这句话可能包含多个事项，请选择一笔账对应的分类。",
                matching,
            )
        ]

    return "other_expense", [
        _warning(
            "CATEGORY_AMBIGUOUS",
            "category",
            "这句话可能包含多个事项，请选择一笔账对应的分类。",
            matching,
        )
    ]


def _make_note(
    text: str,
    date_spans: Iterable[tuple[int, int]],
    amount_spans: Iterable[tuple[int, int]],
) -> str | None:
    note = _without_spans(text, [*date_spans, *amount_spans])
    for word in DATE_TIME_WORDS:
        note = note.replace(word, " ")
    for word in SENTENCE_SKELETON_WORDS:
        note = note.replace(word, " ")
    note = re.sub(r"[，,。！？!?；;：:、]+", " ", note)
    note = re.sub(r"\s+", " ", note).strip()
    return note or None


def parse_natural_language(text: str, today: date) -> dict[str, Any]:
    original_text = text
    parse_text = text.strip()
    if not parse_text:
        return {
            "status": "no_draft",
            "needs_confirmation": False,
            "draft": None,
            "missing_fields": [],
            "warnings": [],
        }

    parsed_date, date_spans, date_warnings, date_blocking = _parse_date(
        parse_text, today
    )
    masked_dates = _masked_text(parse_text, date_spans)
    amount_spans, valid_amounts, has_unit = _amount_spans(parse_text, masked_dates)
    amount_matches = list(_AMOUNT_PATTERN.finditer(masked_dates))
    amount_count = len(amount_matches)

    warnings: list[dict[str, Any]] = list(date_warnings)
    amount_cents: int | None = None
    if amount_count == 0:
        warnings.append(
            _warning("MISSING_AMOUNT", "amount_cents", "缺少金额")
        )
    elif amount_count > 1:
        warnings.append(
            _warning(
                "MULTIPLE_AMOUNTS",
                "amount_cents",
                "识别到多个金额，一次只能记一笔账，请拆成两笔记录。",
            )
        )
    elif len(valid_amounts) == 1:
        amount_cents = valid_amounts[0]
        if not has_unit:
            warnings.append(
                _warning(
                    "BARE_AMOUNT",
                    "amount_cents",
                    "未写元/块，请核对金额。",
                )
            )
    else:
        warnings.append(
            _warning(
                "INVALID_AMOUNT",
                "amount_cents",
                "金额必须大于 0，且最多保留两位小数。",
            )
        )

    income_hits = _find_keywords(parse_text, INCOME_KEYWORDS)
    expense_hits = _find_keywords(parse_text, EXPENSE_KEYWORDS)
    transaction_type: str | None
    if income_hits and expense_hits:
        transaction_type = None
        warnings.append(
            _warning(
                "TYPE_CONFLICT",
                "type",
                "同时包含收入和支出含义，请改写为一笔账。",
            )
        )
    elif income_hits:
        transaction_type = "income"
    elif expense_hits:
        transaction_type = "expense"
    else:
        transaction_type = None
        warnings.append(
            _warning(
                "TYPE_UNKNOWN",
                "type",
                "无法判断是收入还是支出，请选择方向。",
            )
        )

    candidates = _category_candidates(parse_text)
    category, category_warnings = _choose_category(
        transaction_type, candidates, amount_count
    )
    warnings.extend(category_warnings)
    if transaction_type is not None and category is None:
        warnings.append(
            _warning(
                "MISSING_CATEGORY",
                "category",
                "无法确定分类，请选择一个固定分类。",
                candidates,
            )
        )

    note = _make_note(parse_text, date_spans, amount_spans)

    meaningful_signal = bool(
        amount_count or income_hits or expense_hits or candidates or date_spans
    )
    if not meaningful_signal:
        return {
            "status": "no_draft",
            "needs_confirmation": False,
            "draft": None,
            "missing_fields": [],
            "warnings": [],
        }

    missing_fields: list[str] = []
    if amount_cents is None:
        missing_fields.append("amount_cents")
    if transaction_type is None:
        missing_fields.append("type")
    if category is None:
        missing_fields.append("category")
    if parsed_date is None:
        missing_fields.append("transaction_date")

    draft = {
        "amount_cents": amount_cents,
        "type": transaction_type,
        "category": category,
        "note": note,
        "original_text": original_text,
        "transaction_date": parsed_date.isoformat() if parsed_date else None,
    }

    blocking_codes = {
        "MISSING_AMOUNT",
        "MULTIPLE_AMOUNTS",
        "INVALID_AMOUNT",
        "TYPE_UNKNOWN",
        "TYPE_CONFLICT",
        "MISSING_CATEGORY",
        "INVALID_DATE",
        "UNSUPPORTED_DATE",
        "DATE_AMBIGUOUS",
        "FUTURE_DATE",
    }
    is_blocking = bool(missing_fields) or date_blocking or any(
        item["code"] in blocking_codes for item in warnings
    )
    if is_blocking:
        status = "needs_input"
    elif warnings:
        status = "needs_confirmation"
    else:
        status = "ready"

    return {
        "status": status,
        "needs_confirmation": status != "ready",
        "draft": draft,
        "missing_fields": missing_fields,
        "warnings": warnings,
    }


def _utc_now_string(value: datetime) -> str:
    if value.tzinfo is None:
        value = value.replace(tzinfo=timezone.utc)
    return value.astimezone(timezone.utc).isoformat(timespec="microseconds").replace(
        "+00:00", "Z"
    )


def _parse_utc_string(value: str) -> datetime:
    parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc)


def _row_to_transaction(row: sqlite3.Row) -> dict[str, Any]:
    return {
        "id": int(row["id"]),
        "amount_cents": int(row["amount_cents"]),
        "type": row["type"],
        "category": row["category"],
        "note": row["note"],
        "original_text": row["original_text"],
        "transaction_date": row["transaction_date"],
        "created_at": row["created_at"],
        "updated_at": row["updated_at"],
        "deleted_at": row["deleted_at"],
    }


def _detail(field: str, message: str) -> dict[str, str]:
    return {"field": field, "message": message}


def _validate_transaction_payload(
    payload: Any,
    *,
    today: date,
    update: bool,
) -> dict[str, Any]:
    if not isinstance(payload, dict):
        raise ApiError(400, "INVALID_REQUEST", "请求体必须是 JSON 对象")

    allowed = (
        {"amount_cents", "type", "category", "note", "transaction_date"}
        if update
        else {
            "amount_cents",
            "type",
            "category",
            "note",
            "original_text",
            "transaction_date",
            "confirm_duplicate",
        }
    )
    required = (
        {"amount_cents", "type", "category", "note", "transaction_date"}
        if update
        else {
            "amount_cents",
            "type",
            "category",
            "original_text",
            "transaction_date",
        }
    )
    details: list[dict[str, str]] = []
    for field in sorted(set(payload) - allowed):
        details.append(_detail(field, "不支持该字段"))
    for field in sorted(required - set(payload)):
        details.append(_detail(field, "字段为必填"))
    if details:
        raise ApiError(400, "VALIDATION_ERROR", "请求字段校验失败", details)

    amount_cents = payload.get("amount_cents")
    if type(amount_cents) is not int:
        details.append(_detail("amount_cents", "金额必须是整数分"))
    elif amount_cents <= 0:
        details.append(_detail("amount_cents", "金额必须大于 0"))
    elif amount_cents > MAX_SQLITE_INTEGER:
        details.append(_detail("amount_cents", "金额超出可保存范围"))

    transaction_type = payload.get("type")
    if not isinstance(transaction_type, str) or transaction_type not in {
        "expense",
        "income",
    }:
        details.append(_detail("type", "收支类型只能是 expense 或 income"))

    category = payload.get("category")
    if not isinstance(category, str) or category not in CATEGORY_BY_CODE:
        details.append(_detail("category", "分类 code 不合法"))
    elif (
        isinstance(transaction_type, str)
        and transaction_type in {"expense", "income"}
        and category not in ALLOWED_CATEGORIES_BY_TYPE[transaction_type]
    ):
        details.append(_detail("category", "分类与收支类型不匹配"))

    note_value = payload.get("note")
    normalized_note: str | None
    if note_value is not None and not isinstance(note_value, str):
        details.append(_detail("note", "备注必须是字符串或 null"))
        normalized_note = None
    elif isinstance(note_value, str):
        normalized_note = note_value.strip() or None
        if normalized_note is not None and len(normalized_note) > 200:
            details.append(_detail("note", "备注不能超过 200 个字符"))
    else:
        normalized_note = None

    original_text: str | None = None
    if not update:
        original_value = payload.get("original_text")
        if not isinstance(original_value, str):
            details.append(_detail("original_text", "原始输入必须是字符串"))
        else:
            original_text = original_value
            if not original_value.strip():
                details.append(_detail("original_text", "原始输入不能为空"))
            if len(original_value) > 500:
                details.append(_detail("original_text", "原始输入不能超过 500 个字符"))

    transaction_date = payload.get("transaction_date")
    parsed_transaction_date: date | None = None
    if not isinstance(transaction_date, str) or not re.fullmatch(
        r"\d{4}-\d{2}-\d{2}", transaction_date
    ):
        details.append(_detail("transaction_date", "日期必须是 YYYY-MM-DD"))
    else:
        try:
            parsed_transaction_date = date.fromisoformat(transaction_date)
        except ValueError:
            details.append(_detail("transaction_date", "日期不是有效的日历日期"))
        else:
            if parsed_transaction_date > today:
                details.append(_detail("transaction_date", "不能保存未来日期"))

    confirm_duplicate = False
    if not update and "confirm_duplicate" in payload:
        confirm_duplicate = payload["confirm_duplicate"]
        if type(confirm_duplicate) is not bool:
            details.append(_detail("confirm_duplicate", "confirm_duplicate 必须是布尔值"))

    if details:
        raise ApiError(400, "VALIDATION_ERROR", "请求字段校验失败", details)

    return {
        "amount_cents": amount_cents,
        "type": transaction_type,
        "category": category,
        "note": normalized_note,
        "original_text": original_text,
        "transaction_date": parsed_transaction_date.isoformat(),
        "confirm_duplicate": bool(confirm_duplicate),
    }


SCHEMA_SQL = """
CREATE TABLE IF NOT EXISTS transactions (
    id INTEGER PRIMARY KEY,
    amount_cents INTEGER NOT NULL CHECK (amount_cents > 0),
    type TEXT NOT NULL CHECK (type IN ('expense', 'income')),
    category TEXT NOT NULL,
    note TEXT CHECK (note IS NULL OR length(note) <= 200),
    original_text TEXT NOT NULL CHECK (
        length(trim(original_text)) >= 1 AND length(original_text) <= 500
    ),
    transaction_date TEXT NOT NULL,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    deleted_at TEXT
);

CREATE INDEX IF NOT EXISTS idx_transactions_date_status
    ON transactions (transaction_date, deleted_at);
"""


class LedgerService:
    def __init__(
        self,
        db_path: str | Path,
        *,
        today_provider: Callable[[], date] | None = None,
        now_provider: Callable[[], datetime] | None = None,
    ) -> None:
        self.db_path = Path(db_path)
        self.today_provider = today_provider or date.today
        self.now_provider = now_provider or (lambda: datetime.now(timezone.utc))

    def today(self) -> date:
        provided = self.today_provider()
        if isinstance(provided, datetime):
            return provided.date()
        return provided

    def now(self) -> datetime:
        provided = self.now_provider()
        if provided.tzinfo is None:
            provided = provided.replace(tzinfo=timezone.utc)
        return provided.astimezone(timezone.utc)

    def _connect(self) -> sqlite3.Connection:
        self.db_path.parent.mkdir(parents=True, exist_ok=True)
        connection = sqlite3.connect(str(self.db_path), timeout=5.0)
        connection.row_factory = sqlite3.Row
        connection.execute("PRAGMA foreign_keys = ON")
        connection.execute("PRAGMA busy_timeout = 5000")
        return connection

    def initialize(self) -> None:
        connection = self._connect()
        try:
            connection.executescript(SCHEMA_SQL)
            connection.commit()
        finally:
            connection.close()

    def _find_active(self, connection: sqlite3.Connection, transaction_id: int) -> sqlite3.Row | None:
        return connection.execute(
            """
            SELECT id, amount_cents, type, category, note, original_text,
                   transaction_date, created_at, updated_at, deleted_at
            FROM transactions
            WHERE id = ? AND deleted_at IS NULL
            """,
            (transaction_id,),
        ).fetchone()

    def _find_any(self, connection: sqlite3.Connection, transaction_id: int) -> sqlite3.Row | None:
        return connection.execute(
            """
            SELECT id, amount_cents, type, category, note, original_text,
                   transaction_date, created_at, updated_at, deleted_at
            FROM transactions
            WHERE id = ?
            """,
            (transaction_id,),
        ).fetchone()

    def create_transaction(self, payload: Any) -> dict[str, Any]:
        validated = _validate_transaction_payload(
            payload, today=self.today(), update=False
        )
        current_time = self.now()
        now = _utc_now_string(current_time)
        connection = self._connect()
        try:
            connection.execute("BEGIN IMMEDIATE")
            recent = connection.execute(
                """
                SELECT id, amount_cents, type, category, note, original_text,
                       transaction_date, created_at, updated_at, deleted_at
                FROM transactions
                WHERE deleted_at IS NULL
                ORDER BY id DESC
                LIMIT 1
                """
            ).fetchone()
            if (
                not validated["confirm_duplicate"]
                and recent is not None
                and self._is_recent_duplicate(recent, validated, current_time)
            ):
                connection.commit()
                similar = _row_to_transaction(recent)
                return {
                    "transaction": None,
                    "duplicate_warning": True,
                    "similar_transaction": similar,
                    "message": self._duplicate_message(similar),
                }

            cursor = connection.execute(
                """
                INSERT INTO transactions (
                    amount_cents, type, category, note, original_text,
                    transaction_date, created_at, updated_at, deleted_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, NULL)
                """,
                (
                    validated["amount_cents"],
                    validated["type"],
                    validated["category"],
                    validated["note"],
                    validated["original_text"],
                    validated["transaction_date"],
                    now,
                    now,
                ),
            )
            transaction_id = int(cursor.lastrowid)
            row = self._find_any(connection, transaction_id)
            if row is None:
                raise sqlite3.IntegrityError("inserted transaction not found")
            connection.commit()
            return {
                "transaction": _row_to_transaction(row),
                "duplicate_warning": False,
                "similar_transaction": None,
            }
        except Exception:
            if connection.in_transaction:
                connection.rollback()
            raise
        finally:
            connection.close()

    @staticmethod
    def _is_recent_duplicate(
        row: sqlite3.Row,
        validated: dict[str, Any],
        now: datetime,
    ) -> bool:
        try:
            created_at = _parse_utc_string(row["created_at"])
        except (TypeError, ValueError):
            return False
        age = (now - created_at).total_seconds()
        if age < 0 or age > 600:
            return False
        return (
            row["transaction_date"] == validated["transaction_date"]
            and row["amount_cents"] == validated["amount_cents"]
            and row["type"] == validated["type"]
            and row["category"] == validated["category"]
            and row["note"] == validated["note"]
        )

    @staticmethod
    def _duplicate_message(transaction: dict[str, Any]) -> str:
        cents = transaction["amount_cents"]
        amount_text = f"¥{cents // 100}.{cents % 100:02d}"
        note = transaction["note"] or "相同内容"
        return f"刚刚似乎记过一笔 {amount_text} {note}"

    def list_transactions(self, page: int, page_size: int) -> dict[str, Any]:
        connection = self._connect()
        try:
            total = connection.execute(
                "SELECT count(*) FROM transactions WHERE deleted_at IS NULL"
            ).fetchone()[0]
            offset = (page - 1) * page_size
            rows = connection.execute(
                """
                SELECT id, amount_cents, type, category, note, original_text,
                       transaction_date, created_at, updated_at, deleted_at
                FROM transactions
                WHERE deleted_at IS NULL
                ORDER BY transaction_date DESC, updated_at DESC, id DESC
                LIMIT ? OFFSET ?
                """,
                (page_size, offset),
            ).fetchall()
            return {
                "items": [_row_to_transaction(row) for row in rows],
                "page": page,
                "page_size": page_size,
                "total": int(total),
                "has_next": offset + len(rows) < total,
            }
        finally:
            connection.close()

    def get_transaction(self, transaction_id: int) -> dict[str, Any]:
        connection = self._connect()
        try:
            row = self._find_active(connection, transaction_id)
            if row is None:
                raise ApiError(404, "NOT_FOUND", "账目不存在")
            return _row_to_transaction(row)
        finally:
            connection.close()

    def update_transaction(self, transaction_id: int, payload: Any) -> dict[str, Any]:
        validated = _validate_transaction_payload(
            payload, today=self.today(), update=True
        )
        now = _utc_now_string(self.now())
        connection = self._connect()
        try:
            connection.execute("BEGIN IMMEDIATE")
            row = self._find_active(connection, transaction_id)
            if row is None:
                raise ApiError(404, "NOT_FOUND", "账目不存在")
            connection.execute(
                """
                UPDATE transactions
                SET amount_cents = ?, type = ?, category = ?, note = ?,
                    transaction_date = ?, updated_at = ?
                WHERE id = ? AND deleted_at IS NULL
                """,
                (
                    validated["amount_cents"],
                    validated["type"],
                    validated["category"],
                    validated["note"],
                    validated["transaction_date"],
                    now,
                    transaction_id,
                ),
            )
            updated = self._find_active(connection, transaction_id)
            if updated is None:
                raise sqlite3.IntegrityError("updated transaction not found")
            connection.commit()
            return _row_to_transaction(updated)
        except Exception:
            if connection.in_transaction:
                connection.rollback()
            raise
        finally:
            connection.close()

    def delete_transaction(self, transaction_id: int) -> dict[str, Any]:
        deleted_at = _utc_now_string(self.now())
        connection = self._connect()
        try:
            connection.execute("BEGIN IMMEDIATE")
            row = self._find_active(connection, transaction_id)
            if row is None:
                raise ApiError(404, "NOT_FOUND", "账目不存在")
            connection.execute(
                """
                UPDATE transactions
                SET deleted_at = ?, updated_at = ?
                WHERE id = ? AND deleted_at IS NULL
                """,
                (deleted_at, deleted_at, transaction_id),
            )
            connection.commit()
            restore_until = _utc_now_string(
                _parse_utc_string(deleted_at) + timedelta(seconds=MAX_RESTORE_SECONDS)
            )
            return {
                "deleted": True,
                "id": transaction_id,
                "deleted_at": deleted_at,
                "restore_available_until": restore_until,
                "restore_url": f"/api/transactions/{transaction_id}/restore",
                "message": "已删除这笔账",
            }
        except Exception:
            if connection.in_transaction:
                connection.rollback()
            raise
        finally:
            connection.close()

    def restore_transaction(self, transaction_id: int) -> dict[str, Any]:
        now = self.now()
        connection = self._connect()
        try:
            connection.execute("BEGIN IMMEDIATE")
            row = self._find_any(connection, transaction_id)
            if row is None:
                raise ApiError(404, "NOT_FOUND", "账目不存在")
            if row["deleted_at"] is None:
                raise ApiError(409, "NOT_DELETED", "账目当前不是已删除状态")
            try:
                deleted_at = _parse_utc_string(row["deleted_at"])
            except (TypeError, ValueError):
                raise ApiError(409, "RESTORE_WINDOW_EXPIRED", "撤销窗口已过")
            if now >= deleted_at + timedelta(seconds=MAX_RESTORE_SECONDS):
                raise ApiError(409, "RESTORE_WINDOW_EXPIRED", "撤销窗口已过")

            updated_at = _utc_now_string(now)
            connection.execute(
                """
                UPDATE transactions
                SET deleted_at = NULL, updated_at = ?
                WHERE id = ? AND deleted_at IS NOT NULL
                """,
                (updated_at, transaction_id),
            )
            restored = self._find_active(connection, transaction_id)
            if restored is None:
                raise sqlite3.IntegrityError("restored transaction not found")
            connection.commit()
            return {"restored": True, "transaction": _row_to_transaction(restored)}
        except Exception:
            if connection.in_transaction:
                connection.rollback()
            raise
        finally:
            connection.close()

    def summary(self) -> dict[str, int]:
        today = self.today()
        month_start = today.replace(day=1)
        if month_start.month == 12:
            next_month = date(month_start.year + 1, 1, 1)
        else:
            next_month = date(month_start.year, month_start.month + 1, 1)
        connection = self._connect()
        try:
            today_expense = connection.execute(
                """
                SELECT coalesce(sum(amount_cents), 0)
                FROM transactions
                WHERE deleted_at IS NULL
                  AND type = 'expense'
                  AND transaction_date = ?
                """,
                (today.isoformat(),),
            ).fetchone()[0]
            month_expense = connection.execute(
                """
                SELECT coalesce(sum(amount_cents), 0)
                FROM transactions
                WHERE deleted_at IS NULL
                  AND type = 'expense'
                  AND transaction_date >= ?
                  AND transaction_date < ?
                """,
                (month_start.isoformat(), next_month.isoformat()),
            ).fetchone()[0]
            month_income = connection.execute(
                """
                SELECT coalesce(sum(amount_cents), 0)
                FROM transactions
                WHERE deleted_at IS NULL
                  AND type = 'income'
                  AND transaction_date >= ?
                  AND transaction_date < ?
                """,
                (month_start.isoformat(), next_month.isoformat()),
            ).fetchone()[0]
            return {
                "today_expense_cents": int(today_expense),
                "month_expense_cents": int(month_expense),
                "month_income_cents": int(month_income),
            }
        finally:
            connection.close()

    def create_backup(self) -> tuple[Path, str]:
        backup_fd, backup_name = tempfile.mkstemp(
            prefix="smart-ledger-backup-", suffix=".sqlite"
        )
        os.close(backup_fd)
        backup_path = Path(backup_name)
        source: sqlite3.Connection | None = None
        destination: sqlite3.Connection | None = None
        try:
            source = self._connect()
            destination = sqlite3.connect(str(backup_path), timeout=5.0)
            source.backup(destination)
            destination.commit()
            filename = f"smart-ledger-backup-{self.now().strftime('%Y%m%d-%H%M%S')}.sqlite"
            return backup_path, filename
        except Exception as exc:
            _remove_file(backup_path)
            raise BackupError from exc
        finally:
            if destination is not None:
                destination.close()
            if source is not None:
                source.close()


def _remove_file(path: str | Path) -> None:
    try:
        Path(path).unlink(missing_ok=True)
    except OSError:
        pass


def _parse_id(value: str) -> int:
    if not re.fullmatch(r"\d+", value):
        raise ApiError(400, "VALIDATION_ERROR", "账目 id 必须是正整数")
    transaction_id = int(value)
    if transaction_id <= 0:
        raise ApiError(400, "VALIDATION_ERROR", "账目 id 必须是正整数")
    return transaction_id


def _parse_page(value: str, field: str, maximum: int | None = None) -> int:
    if not _POSITIVE_INTEGER_PATTERN.fullmatch(value):
        raise ApiError(400, "VALIDATION_ERROR", f"{field} 必须是正整数")
    parsed = int(value)
    if maximum is not None and parsed > maximum:
        raise ApiError(400, "VALIDATION_ERROR", f"{field} 不能超过 {maximum}")
    return parsed


async def _read_json_object(request: Request) -> dict[str, Any]:
    try:
        payload = await request.json()
    except (ValueError, UnicodeDecodeError):
        raise ApiError(400, "INVALID_REQUEST", "请求 JSON 格式不正确")
    if not isinstance(payload, dict):
        raise ApiError(400, "INVALID_REQUEST", "请求体必须是 JSON 对象")
    return payload


def _register_exception_handlers(app: FastAPI) -> None:
    @app.exception_handler(ApiError)
    async def handle_api_error(_: Request, exc: ApiError) -> JSONResponse:
        error: dict[str, Any] = {"code": exc.code, "message": exc.message}
        if exc.details:
            error["details"] = exc.details
        return JSONResponse(status_code=exc.status_code, content={"error": error})

    @app.exception_handler(RequestValidationError)
    async def handle_request_validation(_: Request, __: RequestValidationError) -> JSONResponse:
        return JSONResponse(
            status_code=400,
            content={
                "error": {
                    "code": "INVALID_REQUEST",
                    "message": "请求格式或参数不正确",
                }
            },
        )

    @app.exception_handler(StarletteHTTPException)
    async def handle_http_error(_: Request, exc: StarletteHTTPException) -> JSONResponse:
        if exc.status_code == 404:
            code, message = "NOT_FOUND", "请求的资源不存在"
        else:
            code, message = "INVALID_REQUEST", "请求无法处理"
        return JSONResponse(
            status_code=exc.status_code,
            content={"error": {"code": code, "message": message}},
        )

    @app.exception_handler(sqlite3.Error)
    async def handle_sqlite_error(_: Request, __: sqlite3.Error) -> JSONResponse:
        return JSONResponse(
            status_code=500,
            content={
                "error": {
                    "code": "INTERNAL_ERROR",
                    "message": "服务暂时不可用，请稍后重试",
                }
            },
        )

    @app.exception_handler(Exception)
    async def handle_unexpected_error(_: Request, __: Exception) -> JSONResponse:
        return JSONResponse(
            status_code=500,
            content={
                "error": {
                    "code": "INTERNAL_ERROR",
                    "message": "服务暂时不可用，请稍后重试",
                }
            },
        )


def create_app(
    db_path: str | Path | None = None,
    *,
    today_provider: Callable[[], date] | None = None,
    now_provider: Callable[[], datetime] | None = None,
) -> FastAPI:
    configured_path = db_path or os.environ.get("SMART_LEDGER_DB_PATH") or DEFAULT_DB_PATH
    service = LedgerService(
        configured_path,
        today_provider=today_provider,
        now_provider=now_provider,
    )
    service.initialize()
    app = FastAPI(title="Smart Ledger V1 API", version="1.0.0")
    app.state.ledger_service = service
    app.add_middleware(
        CORSMiddleware,
        allow_origins=["http://127.0.0.1:5173", "http://localhost:5173"],
        allow_credentials=False,
        allow_methods=["GET", "POST", "PUT", "DELETE", "OPTIONS"],
        allow_headers=["Content-Type"],
    )
    _register_exception_handlers(app)

    @app.post("/api/parse")
    async def parse_endpoint(request: Request) -> dict[str, Any]:
        payload = await _read_json_object(request)
        unknown = set(payload) - {"text"}
        if unknown:
            details = [_detail(field, "不支持该字段") for field in sorted(unknown)]
            raise ApiError(400, "VALIDATION_ERROR", "请求字段校验失败", details)
        text = payload.get("text")
        if not isinstance(text, str):
            raise ApiError(400, "INVALID_REQUEST", "text 必须是字符串")
        if len(text) > 500:
            raise ApiError(
                400,
                "VALIDATION_ERROR",
                "原始输入不能超过 500 个字符",
                [_detail("text", "原始输入不能超过 500 个字符")],
            )
        return parse_natural_language(text, service.today())

    @app.get("/api/categories")
    def categories_endpoint() -> dict[str, Any]:
        return {"items": [dict(item) for item in CATEGORIES]}

    @app.post("/api/transactions")
    async def create_transaction_endpoint(
        request: Request, response: Response
    ) -> dict[str, Any]:
        payload = await _read_json_object(request)
        result = service.create_transaction(payload)
        response.status_code = 200 if result["duplicate_warning"] else 201
        return result

    @app.get("/api/transactions")
    def list_transactions_endpoint(request: Request) -> dict[str, Any]:
        page = _parse_page(request.query_params.get("page", "1"), "page")
        page_size = _parse_page(
            request.query_params.get("page_size", "50"), "page_size", maximum=100
        )
        return service.list_transactions(page, page_size)

    @app.get("/api/transactions/{transaction_id}")
    def get_transaction_endpoint(transaction_id: str) -> dict[str, Any]:
        return service.get_transaction(_parse_id(transaction_id))

    @app.put("/api/transactions/{transaction_id}")
    async def update_transaction_endpoint(
        transaction_id: str, request: Request
    ) -> dict[str, Any]:
        payload = await _read_json_object(request)
        return service.update_transaction(_parse_id(transaction_id), payload)

    @app.delete("/api/transactions/{transaction_id}")
    def delete_transaction_endpoint(transaction_id: str) -> dict[str, Any]:
        return service.delete_transaction(_parse_id(transaction_id))

    @app.post("/api/transactions/{transaction_id}/restore")
    def restore_transaction_endpoint(transaction_id: str) -> dict[str, Any]:
        return service.restore_transaction(_parse_id(transaction_id))

    @app.get("/api/summary")
    def summary_endpoint() -> dict[str, int]:
        return service.summary()

    @app.get("/api/backup")
    def backup_endpoint() -> FileResponse:
        try:
            backup_path, filename = service.create_backup()
        except BackupError:
            raise ApiError(500, "BACKUP_FAILED", "备份暂时失败，请稍后重试")
        return FileResponse(
            path=backup_path,
            media_type="application/vnd.sqlite3",
            filename=filename,
            background=BackgroundTask(_remove_file, backup_path),
        )

    return app


app = create_app()
