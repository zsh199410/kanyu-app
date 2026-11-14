# D0 单测聚合日志（脱敏）

> 来源：美国 VPS `/opt/p2p3-d0/` 现场运行四套测试的完整输出，
> 原始输出见同目录 `test-output-timestamp.txt`。
> 本文件只含通过数与断言名，不含任何节点数据、密码、URI、token、
> 订阅 URL。运行时间：2026-11-14 10:36（CST 前后，修复后复跑）。

## 总表

| 套件 | 通过 | 失败 | 说明 |
|---|---|---|---|
| `tests/test_phone_gate.py` | 23 | 0 | 门禁核心（原有） |
| `tests/test_select_publish.py` | 14 | 0 | 发布选择（原有） |
| `tests/test_cmd_publish_gate.py` | 11 | 0 | 发布命令门禁集成（原有） |
| `tests/test_timestamp_priority.py` | 33 | 0 | 时间戳选最近报告（新增，GPT 审查项 2） |
| **合计** | **81** | **0** | |

各套件退出码均为 0。`grep -c ^PASS test-output-timestamp.txt` = 81，
`grep -c ^FAIL` = 0。

## 断言清单（按套件）

### test_phone_gate.py（23）
fingerprint_matches_probe_service、fingerprint_param_order_invariant、
parse_surge_line_ok、parse_excludes_name_from_fp、parse_rejects_bad_proto、
parse_rejects_malformed、admit_good、admit_recovered、admit_boundary_280、
reject_latest_failed、reject_latest_slow、reject_stale、reject_wifi、
reject_status200、reject_state_pending、reject_no_report、admitted_count_is_3、
diag_counts、gate_keeps_good_and_recovered、gate_drops_failed、
gate_drops_unparsable、gate_same_fp_twice_kept、missing_db_fails_closed。

### test_select_publish.py（14）
no_gate_keeps_all、no_gate_stats、gate_keeps_only_allowed、
gate_keeps_verified_pinned、gate_drops_unverified_pinned、
gate_keeps_verified_rotation、gate_drops_unverified_rotation、
gate_skipped_count、gate_empty_set_publishes_nothing、
gate_empty_set_counts、blocklist_still_wins、blocklist_counted、
same_name_distinguished_by_fp、same_name_other_dropped。

### test_cmd_publish_gate.py（11）
gate_on_publish_rc0、gate_on_keeps_verified_pinned、
gate_on_keeps_verified_rotation、gate_on_drops_unverified_pinned、
gate_on_total_is_2、published_first_only_kept、zero_qualified_refuses_rc1、
zero_qualified_keeps_old_file、zero_qualified_reports_safe_state、
gate_off_restores_old_behaviour、gate_off_keeps_unverified_pinned。

### test_timestamp_priority.py（33，新增）
reject_fail_after_good、admit_good_after_fail、reject_timeout_after_good、
reject_timeout_flag_missing_ms、admit_good_after_timeout、
reject_slow_310_after_good、reject_slow_500_after_good、
reject_slow_281_after_good、admit_good_after_slow、reject_wifi_after_good、
reject_iface_empty_after_good、reject_iface_none_after_good、
admit_good_after_wifi、admit_cellular_pdp_ip1、reject_future_ts_far、
admit_future_ts_within_skew、reject_ts_zero、reject_stale_far_past、
admit_ttl_boundary_exact、reject_ttl_boundary_over、diag_counts、
diag_reason_latest_failed、diag_reason_latest_slow、
diag_reason_latest_interface、diag_reason_latest_ts_invalid、
diag_reason_latest_stale、fp_change_old_fp_admitted、
fp_change_port_dropped、fp_change_param_dropped、fp_change_old_line_kept、
insert_order_ids_misleading、reject_insert_order_bad_wins、
admit_insert_order_good_wins。

## 修复前基线（复现漏洞用，非最终结果）

修复前同一套新增测试为 **29 通过 / 4 失败**，失败的 4 项全部源于
同一根因（未来时间戳被当作“最新鲜”放行）：
reject_future_ts_far、diag_counts、diag_reason_latest_ts_invalid、
diag_reason_latest_stale。修复后 33/33 全过，原有 48 项不受影响。
