# 契约所有权

契约由所有者维护，使用者只能消费或提变更提案。这张表是变更审批的依据。

| 契约 | 所有者 | 使用者 | 变更审批人 |
|---|---|---|---|
| `contracts/module-a/v1.yaml` | worker-module-a | worker-module-b | orchestrator |
| `contracts/module-b/v1.yaml` | worker-module-b | 无（对外接口） | orchestrator |

## 规则

1. 所有者负责：定义、版本、兼容性、契约测试、CHANGELOG。
2. 使用者不得直接改别人拥有的契约文件。
3. breaking 变更需要：提案 → orchestrator 批准 → major 升版 → 旧版本保留一个窗口。
4. additive 变更：所有者可在通知使用者后直接升 minor。
5. 契约文件与实现不一致时，以契约为准；实现要改到符合契约，或先改契约。

## 变更记录

| 日期 | 契约 | 版本 | 类型 | 提案 | 批准人 |
|---|---|---|---|---|---|
| TBD | | | | | |