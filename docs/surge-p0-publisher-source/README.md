# P0 整改：旧发布器源码隔离包（供 GPT 直接改核心代码）

**来源**：VPS `/opt/free-node-program/pool/cli.py`（生产实际使用的发布器），
2026-11-18 06:55 从服务器原样取回，SHA256 见 `SHA_MANIFEST.md`。
**用途**：GPT 直接改核心筛选逻辑。Muse 只负责环境与测试，不并行覆盖 GPT 的实现。
**状态**：隔离 Draft PR，不合并进 main，不改生产文件、不改定时器、不删节点。

## 文件

| 文件 | 说明 |
|---|---|
| `pool-cli-dev-copy.py` | cli.py 完整开发副本（687 行，与 VPS 字节一致） |
| `FILTER_LOGIC.md` | 关键筛选逻辑摘录（行号引用）与已确认的缺口 |
| `INPUT_SCHEMA.md` | 输入数据 schema（pool.db、订阅格式、探针状态、配置键、定时器） |
| `SHA_MANIFEST.md` | 各文件 SHA256 与版本锚点 |

## 脱敏声明

- 本包只含代码，不含任何节点 URI、密码、令牌、订阅 URL、私人 IP。
- 唯一与凭据沾边的文本是代码里的字段名 `"password"`（记录 schema 的键名，无值）。
- 已用 `grep -Ei "password=|token=|secret|api[_-]?key\s*=|http://|https://"` 全文件核查：0 命中。

## 运行依赖（仅说明，GPT 按需索取）

`pool-cli-dev-copy.py` 属于 `pool` 包，依赖同包 `dbmod`（SQLite 访问）、
`rules.assign_names`（命名）、`IpApi`（国家判定）及 `pre_filter` /
`build_surge_line` / `parse_surge_line` / `hint_to_code`（同包内函数）。
本包暂不含这些兄弟模块；GPT 需要时由 Muse 再行提供。

## 已确认的事实（2026-11-18 06:07 发布日志）

- 发布组成：`pinned 21 + kept_old 30 + new 7 = 58`，`winner_clean_removed 0`。
- `kept_old` 只认 VPS 侧 `db_pass`，不读手机探针证据；探针服务
  （quarantined / retired / expired）从未被发布逻辑读取。
- `/opt/pool-gate` 不存在；PR #77 / #78 / #80 仍 Draft。
