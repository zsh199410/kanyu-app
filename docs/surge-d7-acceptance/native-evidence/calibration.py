# -*- coding: utf-8 -*-
"""
F3. 原生测速口径对照校准 (calibration.py)

任务 F 第三步: Surge API 值 vs 手机界面显示值 vs 策略组选择结果
vs HTTP/HTTPS 测试口径的对照校准。

必须区分的四种量 (绝不混用):
  * API_VALUE      Surge HTTP API 返回的原始测速字段
                   (round_one_total / available / tcp / receive /
                   latency_ms 等, 各字段保留原始数值与类型)。
  * UI_DISPLAY     手机 Surge App 界面 (策略组内) 显示的延迟数字,
                   须由人工在手机上读数并记录, 不是 API 推导值。
  * GROUP_SELECTION Smart / url-test 策略组实际选中的出口
                   (policy 名), 不是延迟数字。
  * TEST_URL_SCHEME 本次测速目标 URL 的 scheme (http / https),
                   不同口径的测速结果不得混在同一对照行里。

校准结论 (calibration_verdict):
  * "CALIBRATED"   满足全部条件: 配对样本数 >= MIN_PAIRED_SAMPLES (3),
                   全部样本同一节点 / 同一 bearer / 同一 test_url 口径,
                   API 字段到 UI 显示值的映射规则唯一确定
                   (例如 UI 值恒等于某一 API 字段, 或恒等于两轮中
                   某一轮的值), 且映射残差为 0。
                   只有 CALIBRATED 才能把 measurement_verified 置 True。
  * "UNCALIBRATED" 任一条件不满足: 样本不足、映射不唯一、
                   残差非零、口径混用、时间 / bearer 不一致。
                   measurement_verified 必须保持 False,
                   judge_evidence() 据此判 UNVERIFIED。
  * "CONTRADICTED" 配对样本互相矛盾 (同一 API 值对应不同 UI 值,
                   或 UI 值无法由任何 API 字段解释): 映射假设被证伪,
                   须重新实测, 不得强行校准。

硬规则:
  * 延迟只取 raw_result 中显式的数值型 latency_ms,
    不从 round_one_total / available / tcp / receive 推导
    (与 native-collector.py 一致)。
  * UI 显示值必须有人工读数来源 (ui_source="manual_read"),
    没有人工读数的行不计入配对样本。
  * HTTP 与 HTTPS 口径分开校准: 同一节点 http 与 https 的
    API/UI 映射可能不同, 混用即判 UNCALIBRATED。
  * 只要校准未通过, 就维持 UNVERIFIED 和 NO_SAFE_REMOVAL,
    不得硬凑 PASS。

只用 Python 3 标准库, 不联网, 不读 / 不写生产路径。
测试夹具一律用 TEST-NET 假值 (192.0.2.0/24 + test123)。
"""

from __future__ import annotations

from datetime import datetime, timezone

# 校准成立所需的最少配对样本数 (同一节点、同一口径)。
MIN_PAIRED_SAMPLES = 3

# 映射残差容差 (毫秒): UI 显示值与映射 API 值必须逐样本完全相等。
# Surge 界面显示整数毫秒, API 返回数值毫秒, 容差 0 即要求逐样本相等,
# 任何偏差都说明映射假设错误, 不得用容差掩盖。
MAPPING_TOLERANCE_MS = 0

# 可识别的 API 测速字段 (原始 JSON 里的字段名 -> 规范名)。
API_LATENCY_FIELDS = {
    "round_one_total": ("round-one-total", "round_one_total", "roundOneTotal"),
    "available": ("available",),
    "tcp": ("tcp",),
    "receive": ("receive",),
    "latency_ms": ("latency_ms", "latency"),
}

CALIBRATION_VERDICTS = ("CALIBRATED", "UNCALIBRATED", "CONTRADICTED")


def parse_api_latency(raw_result: dict) -> dict:
    """解析 Surge API 原始测速响应, 保留字段名、数值与类型。

    返回 {"fields": {规范名: 数值或 None}, "present": [出现的规范名],
          "raw_keys": [原始键], "types": {规范名: 类型名}}。
    数值只认 int/float (bool 除外); 其他类型记为 None 并在 types 中
    标注实际类型, 绝不强转、绝不编造。
    """
    if not isinstance(raw_result, dict):
        raise TypeError("raw_result 必须是 dict")
    fields = {}
    types = {}
    present = []
    for canonical, aliases in API_LATENCY_FIELDS.items():
        value = None
        found = None
        for alias in aliases:
            if alias in raw_result:
                found = raw_result[alias]
                break
        if isinstance(found, bool) or not isinstance(found, (int, float)):
            if found is not None:
                types[canonical] = type(found).__name__
            fields[canonical] = None
        else:
            fields[canonical] = found
            types[canonical] = type(found).__name__
            present.append(canonical)
    return {
        "fields": fields,
        "present": present,
        "raw_keys": sorted(str(k) for k in raw_result.keys()),
        "types": types,
    }


def test_url_scheme(test_url) -> str:
    """取测速目标 URL 的 scheme: "http" / "https" / "UNKNOWN"。

    非字符串、缺 scheme、或 scheme 不是 http/https 时记 "UNKNOWN",
    不得默认按 https 处理。
    """
    if not isinstance(test_url, str):
        return "UNKNOWN"
    text = test_url.strip().lower()
    if text.startswith("https://"):
        return "https"
    if text.startswith("http://"):
        return "http"
    return "UNKNOWN"


def classify_measurement_source(sample: dict) -> str:
    """判定一条测速样本的来源类型。

    sample 须含 kind 字段:
      * "api"        Surge HTTP API 原始响应。
      * "ui"         手机界面人工读数。
      * "group"      策略组选择结果 (选中的 policy 名)。
      * "paired"     API + UI 同节点同时间的配对样本。
    其他值 -> ValueError。缺 kind -> "UNKNOWN" (不猜测)。
    """
    if not isinstance(sample, dict):
        raise TypeError("sample 必须是 dict")
    kind = sample.get("kind")
    if kind is None:
        return "UNKNOWN"
    if kind not in ("api", "ui", "group", "paired"):
        raise ValueError("无法识别的 measurement kind: {!r}".format(kind))
    return kind


def build_paired_row(api_sample: dict, ui_value, group_selection=None,
                     test_url=None, network_bearer="UNKNOWN",
                     sampled_at=None) -> dict:
    """构造一行 API/UI 配对样本 (对照表的一行)。

    参数:
        api_sample: API 原始响应 dict (须含 node_name/identifier,
            以及 round_one_total / available 等原始字段)。
        ui_value: 手机界面人工读数的延迟毫秒 (数值型; None 表示
            本次未读到界面值, 该行不计入配对样本)。
        group_selection: Smart/url-test 组实际选中的 policy 名 (可选)。
        test_url: 本次测速目标 URL (用于区分 http/https 口径)。
        network_bearer: wifi / cellular / UNKNOWN。
        sampled_at: ISO8601 采样时间 (可选, 用于同时间核对)。

    返回配对行 dict, 含 api_fields (解析后)、ui_value、
    scheme、bearer、node、group_selection。
    """
    if not isinstance(api_sample, dict):
        raise TypeError("api_sample 必须是 dict")
    if ui_value is not None and (
        isinstance(ui_value, bool) or not isinstance(ui_value, (int, float))
    ):
        raise ValueError("ui_value 必须是数值毫秒或 None")
    if ui_value is not None and ui_value < 0:
        raise ValueError("ui_value 不得为负数")
    node = None
    for key in ("node_name", "name", "identifier"):
        value = api_sample.get(key)
        if isinstance(value, str) and value.strip():
            node = value.strip()
            break
    parsed = parse_api_latency(api_sample)
    return {
        "kind": "paired",
        "node": node,
        "api_fields": parsed["fields"],
        "api_present": parsed["present"],
        "ui_value": ui_value,
        "ui_source": "manual_read" if ui_value is not None else None,
        "group_selection": group_selection,
        "test_url": test_url,
        "scheme": test_url_scheme(test_url),
        "network_bearer": network_bearer,
        "sampled_at": sampled_at,
    }


def _mapping_for_row(row: dict, field: str):
    """一行中 UI 值与某一 API 字段的映射残差 (ui - api), 字段缺失为 None。"""
    api_value = (row.get("api_fields") or {}).get(field)
    ui_value = row.get("ui_value")
    if api_value is None or ui_value is None:
        return None
    return ui_value - api_value


def calibrate(paired_rows) -> dict:
    """对一组配对样本做口径对照校准。

    参数:
        paired_rows: build_paired_row() 产出的配对行列表。

    返回 {"verdict", "mapping_field", "paired_count", "usable_count",
          "scheme", "node", "network_bearer", "residuals",
          "comparison_table": [...], "reasons": [...]}。
    comparison_table 是对照表: 每行含 node / scheme / bearer /
    api 各字段 / ui_value / group_selection / 映射残差。

    判定:
      * 可用样本 = ui_value 非空且 node 非空的行。
      * 可用样本 < MIN_PAIRED_SAMPLES -> UNCALIBRATED (样本不足)。
      * 样本跨节点 / 跨 scheme / 跨 bearer -> UNCALIBRATED (口径混用)。
      * 存在某一 API 字段使全部可用样本残差均为 0
        -> CALIBRATED, mapping_field 为该字段。
      * 多个字段同时满足 -> UNCALIBRATED (映射不唯一, 须更多样本区分)。
      * 无字段满足, 且同一 API 值对应不同 UI 值
        -> CONTRADICTED (映射假设被证伪)。
      * 无字段满足, 其余情况 -> UNCALIBRATED。
    """
    rows = list(paired_rows or [])
    table = []
    usable = []
    for row in rows:
        if not isinstance(row, dict):
            continue
        table.append(
            {
                "node": row.get("node"),
                "scheme": row.get("scheme"),
                "network_bearer": row.get("network_bearer"),
                "api_round_one_total": (row.get("api_fields") or {}).get("round_one_total"),
                "api_available": (row.get("api_fields") or {}).get("available"),
                "api_tcp": (row.get("api_fields") or {}).get("tcp"),
                "api_receive": (row.get("api_fields") or {}).get("receive"),
                "api_latency_ms": (row.get("api_fields") or {}).get("latency_ms"),
                "ui_value": row.get("ui_value"),
                "ui_source": row.get("ui_source"),
                "group_selection": row.get("group_selection"),
                "sampled_at": row.get("sampled_at"),
            }
        )
        if row.get("ui_value") is not None and row.get("node"):
            usable.append(row)

    reasons = []
    base = {
        "paired_count": len(rows),
        "usable_count": len(usable),
        "comparison_table": table,
        "mapping_field": None,
        "residuals": {},
        "scheme": None,
        "node": None,
        "network_bearer": None,
    }
    if len(usable) < MIN_PAIRED_SAMPLES:
        base.update(
            {
                "verdict": "UNCALIBRATED",
                "reasons": reasons
                + [
                    "配对样本不足: 可用 {} 行, 至少需要 {} 行 "
                    "(同一节点、同一口径)".format(len(usable), MIN_PAIRED_SAMPLES)
                ],
            }
        )
        return base
    nodes = {r.get("node") for r in usable}
    schemes = {r.get("scheme") for r in usable}
    bearers = {r.get("network_bearer") for r in usable}
    base.update(
        {
            "node": sorted(nodes)[0] if len(nodes) == 1 else None,
            "scheme": sorted(schemes)[0] if len(schemes) == 1 else None,
            "network_bearer": sorted(bearers)[0] if len(bearers) == 1 else None,
        }
    )
    if len(nodes) != 1 or len(schemes) != 1 or len(bearers) != 1:
        problems = []
        if len(nodes) != 1:
            problems.append("跨节点 ({} 个)".format(len(nodes)))
        if len(schemes) != 1:
            problems.append("跨测试口径 scheme ({} 个: {})".format(len(schemes), sorted(schemes)))
        if len(bearers) != 1:
            problems.append("跨网络类型 ({} 个)".format(len(bearers)))
        base.update(
            {
                "verdict": "UNCALIBRATED",
                "reasons": reasons + ["配对样本口径不一致, 不得混用: " + "; ".join(problems)],
            }
        )
        return base

    candidates = []
    residuals = {}
    for field in ("round_one_total", "available", "tcp", "receive", "latency_ms"):
        diffs = [_mapping_for_row(r, field) for r in usable]
        if any(d is None for d in diffs):
            residuals[field] = None  # 该字段有样本缺失, 不能作为映射
            continue
        residuals[field] = diffs
        if all(abs(d) <= MAPPING_TOLERANCE_MS for d in diffs):
            candidates.append(field)
    base["residuals"] = residuals
    if len(candidates) == 1:
        base.update(
            {
                "verdict": "CALIBRATED",
                "mapping_field": candidates[0],
                "reasons": reasons
                + [
                    "映射唯一确定: 界面显示值恒等于 API 字段 {!r} "
                    "(全部 {} 行残差为 0, 节点 {}, 口径 {}, 网络 {})".format(
                        candidates[0],
                        len(usable),
                        base["node"],
                        base["scheme"],
                        base["network_bearer"],
                    )
                ],
            }
        )
        return base
    if len(candidates) > 1:
        base.update(
            {
                "verdict": "UNCALIBRATED",
                "reasons": reasons
                + [
                    "映射不唯一: 字段 {} 全部满足残差为 0, "
                    "须更多区分样本才能确定映射".format(candidates)
                ],
            }
        )
        return base
    # 无字段满足: 检查是否互相矛盾 (同一 API 向量对应不同 UI 值)。
    api_vectors = {}
    contradicted = False
    for row in usable:
        key = tuple((row.get("api_fields") or {}).get(f) for f in
                    ("round_one_total", "available", "tcp", "receive", "latency_ms"))
        if key in api_vectors and api_vectors[key] != row.get("ui_value"):
            contradicted = True
            break
        api_vectors[key] = row.get("ui_value")
    if contradicted:
        base.update(
            {
                "verdict": "CONTRADICTED",
                "reasons": reasons
                + [
                    "配对样本互相矛盾: 同一 API 值对应不同界面显示值, "
                    "映射假设被证伪, 须重新实测"
                ],
            }
        )
        return base
    base.update(
        {
            "verdict": "UNCALIBRATED",
            "reasons": reasons
            + [
                "无 API 字段能解释界面显示值 (全部 {} 行残差非零), "
                "映射未确定".format(len(usable))
            ],
        }
    )
    return base


def measurement_verified_from_calibration(calibration: dict) -> bool:
    """校准结论 -> measurement_verified (只认 CALIBRATED)。

    非 dict、verdict 不是 CALIBRATED、或 mapping_field 为空时一律 False。
    """
    if not isinstance(calibration, dict):
        return False
    return (
        calibration.get("verdict") == "CALIBRATED"
        and bool(calibration.get("mapping_field"))
    )


def apply_calibration_to_evidence(evidence_record: dict, calibration: dict) -> dict:
    """把校准结论应用到证据记录副本上 (不修改输入)。

    measurement_verified 只在 CALIBRATED 时置 True, 其余一律 False。
    verdict 本函数不改写: 调用方须随后用 judge_evidence() 重判。
    """
    if not isinstance(evidence_record, dict):
        raise TypeError("evidence_record 必须是 dict")
    record = dict(evidence_record)
    record["measurement_verified"] = measurement_verified_from_calibration(calibration)
    record["calibration_verdict"] = (
        calibration.get("verdict") if isinstance(calibration, dict) else "UNCALIBRATED"
    )
    record["calibration_mapping_field"] = (
        calibration.get("mapping_field") if isinstance(calibration, dict) else None
    )
    return record


def now_iso8601() -> str:
    """当前 UTC 时间 ISO8601 (末尾 Z)。"""
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


if __name__ == "__main__":
    print("calibration.py: 原生测速口径对照校准, 无独立 CLI。")
    print("CALIBRATED 需 >= {} 行同节点同口径配对样本且映射唯一、残差为 0。".format(
        MIN_PAIRED_SAMPLES
    ))
    print("未校准时 measurement_verified 保持 False, 判定维持 UNVERIFIED。")
