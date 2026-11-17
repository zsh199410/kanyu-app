# 脱敏检查清单（P0-STOP，GPT #6938432964 门禁 4）

PR 包从脱敏副本在全新目录 `~/workspace/p2p3-dual-pr/` 里组装；
分支须从 main 新建、只含脱敏文件；绝不先提交真实路径再删除。
`~/workspace` 不是 git 仓库，`p2p3-dual/` 也不是；真实随机路径段
从未进过任何 git 提交历史（2026-11-17 全仓核查：该段只出现在隔离树
内两个文件——生产脚本快照与补丁脚本——均未进 PR 包原文）。

## 替换记录（PR 包内计数）

- nginx-vhost-conf: 5 处
- orig-script-sha: 1 处
- probe-host: 6 处
- random-path-segment: 2 处
- orig-script-sha: 回滚脚本的 ORIG_SCRIPT_SHA 已换成脱敏后原脚本的
  SHA；部署时须替换为生产原脚本 SHA（隔离树 docs/SHA_MANIFEST.md）。
- CLIENT_VERSION 已按脱敏后脚本内容重算：`dual-v1-23113216f849`
  （J03 自验通过：占位符归一化后 SHA256 前 12 hex 与常量一致）。

## 例外（合成占位符，非真实凭据）

- `password=fixture*`（夹具池假口令）：12 处，
  全部在 `fixtures/pool-fixture.txt` 及其引用中，TEST-NET 主机，
  从未用真实节点做测试。
- `TEST_SEG = "testseg12345678"`（测试用随机路径段）：合成值，
  仅测试进程内使用。
- `203.0.113.11–22`：TEST-NET 文档地址段，夹具主机。
- `127.0.0.1`：本地回环，测试与健康检查用。
- 池内容 SHA（`f151f4b305c2` 等）与夹具池 SHA：内容指纹，
  不是凭据。

## Grep 核验（PR 包全文件，命中数必须为 0）

- node-uri-ss: 0
- node-uri-trojan: 0
- node-uri-vless: 0
- node-uri-vmess: 0
- password-non-fixture: 0
- private-ip-10.x: 0
- private-ip-172.16-31: 0
- private-ip-192.168: 0
- real-random-path-segment: 0
- sgcmd: 0
- vip668: 0

## 脱敏是否影响可执行性

占位符只替换 URL/主机/路径字面量，函数与控制流逐行保留；
审查不受影响。脱敏后的脚本不替换占位符无法直接运行：
部署时须把 `<probe-host>` / `<random-path>` 换成生产值
（部署脚本从 `probe-path.txt` 现读路径段；脚本 URL 由部署方填入）。
测试用 localhost/占位符，不依赖生产值。

