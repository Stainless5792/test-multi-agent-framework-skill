# 契约目录

本目录是模块间接口的唯一事实源。格式见 `skills/multi-agent-framework/references/contract-format.md`。

## 结构

```
contracts/
├── _contract-template.yaml
├── <module>/
│   ├── v1.yaml            # 当前版本
│   ├── v0.yaml            # 兼容窗口内的旧版本（可选）
│   ├── CHANGELOG.md
│   ├── mocks/             # 下游使用的 mock，必须与契约同源
│   └── proposals/         # 变更提案
```

## 硬规则

1. `status: draft` 的契约不得被下游依赖；`approved` 才能开工。
2. 使用者不得直接改别人拥有的契约。
3. 删字段、改类型、改枚举、改语义 → major + 提案 + 兼容窗口。
4. 新增可选字段 → minor，通知使用者即可。
5. 契约与实现不一致时，以契约为准。

## 校验

```bash
bash scripts/contract-check.sh            # schema + 状态 + 版本连续性
bash scripts/contract-check.sh --gen      # 从契约生成 shared/contracts 类型
```