# P0 开发执行 — 生产池 SHA 对照记录

## 开发前（2026-11-18 19:57 CST，开发开始前实查）

- served `/opt/surge-bridge/modules/pool-new.txt`：
  `606dcfca229e26c0ac83882085f957be40e43cc0b0904d8388cb34398c51247a`（30 行）
- staging `/opt/free-node-program/publish/pool-new.txt`：
  `606dcfca229e26c0ac83882085f957be40e43cc0b0904d8388cb34398c51247a`（30 行）
- staging ＝ served，一致。
- member_set_sha（30 行集合）：`dcfdcadb17aad6923c891dd56ace35c7ced92db5b93ad4e435b055388c712688`

## 开发后（2026-11-18 20:0x CST，开发完成后实查）

- served `/opt/surge-bridge/modules/pool-new.txt`：
  `606dcfca229e26c0ac83882085f957be40e43cc0b0904d8388cb34398c51247a`（30 行）
- staging `/opt/free-node-program/publish/pool-new.txt`：
  `606dcfca229e26c0ac83882085f957be40e43cc0b0904d8388cb34398c51247a`（30 行）
- staging ＝ served，一致；与开发前 SHA 完全相同。
- 5 个 timer 全部 active（pool-publish／pool-sync／pool-crawl／pool-test／pool-test-full），未停用任何 timer。

## 结论（待填）

- 生产配置及订阅是否保持不变：是。池 SHA 开发前后一致（`606dcfca…`，30 行），timer 全在跑，未改生产配置、未删节点、未动 blocklist／STOP／21 钉选。
