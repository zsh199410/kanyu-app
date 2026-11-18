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

## F 轮开发后（2026-11-18 20:48 CST，P0-F 执行者实查）

- served `/opt/surge-bridge/modules/pool-new.txt`：
  `606dcfca229e26c0ac83882085f957be40e43cc0b0904d8388cb34398c51247a`（30 行）
- staging `/opt/free-node-program/publish/pool-new.txt`：
  `606dcfca229e26c0ac83882085f957be40e43cc0b0904d8388cb34398c51247a`（30 行）
- staging ＝ served，一致；与开发前 SHA 完全相同。
- 5 个 timer 全部 active（`systemctl is-active` 逐个核对，5/5 active），未停用任何 timer。
- F 轮只做了 7 次只读 GET（桥指令 1795004725、1795005131），有副作用 POST 0 次；未改生产配置、未删节点、未动 blocklist／STOP／21 钉选。

## G 轮开发后（2026-11-18 20:49 CST，P0-G 执行者实查）

- 开发前（20:24 CST 实查）与开发后（20:49 CST 实查）生产池 SHA 完全一致：
- served `/opt/surge-bridge/modules/pool-new.txt`：
  `606dcfca229e26c0ac83882085f957be40e43cc0b0904d8388cb34398c51247a`（30 行）
- staging `/opt/free-node-program/publish/pool-new.txt`：
  `606dcfca229e26c0ac83882085f957be40e43cc0b0904d8388cb34398c51247a`（30 行）
- staging ＝ served，一致；与开发前 SHA 完全相同。
- 5 个 timer 全部 active（`systemctl is-active` 逐个核对，5/5 active），未停用任何 timer。
- G 轮未写生产 served／staging，未改生产 Surge 配置，未删节点，未动 blocklist／STOP／21 钉选；全部测试在隔离目录 `/opt/p2p3-single-writer/`（700）内完成，测试单元（p2p3-*，/run 运行时单元）已全部清理，`systemctl list-units "p2p3-*"` 0 个。
- 本地 16/16、VPS systemd 36/36（run6），回执 `[SINGLE_WRITER_LOCK_VALIDATED]` PASS。

## 结论（待填）

- 生产配置及订阅是否保持不变：是。池 SHA 开发前后一致（`606dcfca…`，30 行），timer 全在跑，未改生产配置、未删节点、未动 blocklist／STOP／21 钉选。
