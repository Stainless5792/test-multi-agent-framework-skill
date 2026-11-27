# Proposal: <一句话说清要改什么>

- 提案人: <worker-id>
- 目标契约: contracts/<module>/v<major>.yaml
- 判定: additive | breaking
- 影响面: <列出受影响的模块与具体调用点>

## 动机

为什么现有契约不够用。给出触发它的真实场景，不写「将来可能需要」。

## 变更内容

before:

```
<现有定义>
```

after:

```
<新定义>
```

## 迁移步骤

1. 契约升版（minor / major）
2. 下游适配顺序：<谁先改>
3. 兼容窗口：<保留几个发布周期>
4. 回滚方式：<撤哪个文件、恢复到哪个版本>

## 判定与批准

- Orchestrator 判定: pending | accepted | rejected
- 批准人 / 日期: TBD
- 批准后需同步的任务: <task ids>