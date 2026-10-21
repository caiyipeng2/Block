# 闯关 96 关配额与标记供给重校准快照（2026-10-21）

- 配置：`config/adventure_levels.csv`（MD5 `64f1290f371a664f5139b07480e134a9`）
- 模板：`docs/difficulty/adventure_curve_spec.json`（MD5 `85961f119d4ff57cc5cffbb9f26b0cb2`）
- 参考模型：`casual` 三块托盘规划 + 疲劳失误（mistake=0.35, base=0.05, slope=3.0, power=2.0），每关 24 次、seed-mode=level
- 本次只重跑 `casual`（验收口径即 casual）；`greedy` / `random` 上下界沿用上一份快照，未随本轮杠杆重测
- 验收：|casual 通过率 − 目标| ≤ 15pp（全部关卡）；FUUU ≤ 10（仅 peak / secondary_peak / final_peak）

## 表现与难度解耦机制

- 显示目标总量 28–140（相差 5 倍），种类在 2–4 种之间按权重轮换，初始标记 2–10 枚随总量缩放。
- 真实长度由每关 `marker_rounds`（标记供给时长）决定，取值 5–15 盘；配额只改变每盘标记密度。
- 每盘标记预算 = `ceil(剩余配额 / 剩余时长)`，下限 2，上限为整盘格数；重试辅助再提升 25%。

## 结果

- 最大绝对偏差：14.8pp；平均绝对偏差：7.1pp
- 通过率越界关卡：无
- 峰值 FUUU 越界关卡：无
- 非峰值一次性失败哨兵（不计入门槛）：16、17、30、36、45、57、60、69、72、75、80、87
- 单关调参：18, 24, 37, 59, 70, 79, 86, 90, 93

| 阶段 | 关卡数 | 平均 casual 通过率 |
|---|---:|---:|
| build | 36 | 96.3% |
| peak | 9 | 69.4% |
| secondary_peak | 10 | 73.3% |
| relax | 37 | 98.6% |
| final_peak | 1 | 70.8% |
| finale_relax | 1 | 100.0% |

## 峰值与终局

| 关 | 阶段 | 目标 | casual | 偏差 | FUUU | 盘数 | 配额 | 种类 | 标记时长 | 难度 | 形状档 | 随机度 | 额外方块 | 近胜线 |
|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|---:|---:|---:|
| 4 | peak | 72.0 | 62.5 | -9.5 | 2.2 | 11.9 | 81 | 3 | 12 | 25 | pressure | 30 | 8 | 2 |
| 8 | secondary_peak | 73.9 | 75.0 | +1.1 | 2.0 | 10.2 | 69 | 2 | 10 | 24 | pressure | 36 | 4 | 1 |
| 14 | peak | 71.8 | 62.5 | -9.3 | 1.8 | 12.3 | 86 | 3 | 12 | 25 | pressure | 30 | 8 | 2 |
| 18 | secondary_peak | 73.1 | 83.3 | +10.2 | 4.0 | 12.0 | 73 | 4 | 11 | 24 | pressure | 40 | 3 | 1 |
| 24 | peak | 71.6 | 75.0 | +3.4 | 2.0 | 12.2 | 91 | 2 | 12 | 30 | pressure | 30 | 11 | 3 |
| 28 | secondary_peak | 72.3 | 70.8 | -1.5 | 2.3 | 10.6 | 78 | 3 | 10 | 25 | pressure | 36 | 5 | 1 |
| 34 | peak | 71.4 | 75.0 | +3.6 | 3.0 | 12.5 | 97 | 4 | 12 | 26 | pressure | 30 | 10 | 2 |
| 38 | secondary_peak | 71.5 | 70.8 | -0.7 | 1.4 | 10.8 | 82 | 3 | 10 | 26 | pressure | 36 | 6 | 1 |
| 44 | peak | 71.2 | 58.3 | -12.9 | 2.5 | 11.6 | 102 | 3 | 12 | 26 | pressure | 30 | 10 | 2 |
| 48 | secondary_peak | 70.7 | 75.0 | +4.3 | 1.5 | 10.6 | 87 | 2 | 10 | 26 | pressure | 36 | 6 | 1 |
| 54 | peak | 71.0 | 70.8 | -0.2 | 2.3 | 12.2 | 107 | 3 | 12 | 26 | pressure | 30 | 10 | 2 |
| 58 | secondary_peak | 69.9 | 75.0 | +5.1 | 1.5 | 11.0 | 91 | 4 | 10 | 27 | pressure | 36 | 6 | 1 |
| 64 | peak | 70.8 | 83.3 | +12.5 | 2.0 | 12.7 | 113 | 2 | 12 | 26 | pressure | 30 | 11 | 2 |
| 68 | secondary_peak | 69.1 | 79.2 | +10.1 | 2.5 | 10.7 | 96 | 3 | 10 | 28 | pressure | 36 | 7 | 1 |
| 74 | peak | 70.6 | 62.5 | -8.1 | 1.8 | 12.3 | 118 | 4 | 12 | 26 | pressure | 30 | 12 | 2 |
| 78 | secondary_peak | 68.3 | 79.2 | +10.9 | 1.7 | 11.0 | 100 | 3 | 10 | 29 | pressure | 36 | 8 | 1 |
| 84 | peak | 70.4 | 75.0 | +4.6 | 1.5 | 12.5 | 123 | 3 | 12 | 27 | pressure | 30 | 12 | 2 |
| 88 | secondary_peak | 67.5 | 66.7 | -0.8 | 2.0 | 10.7 | 105 | 2 | 10 | 29 | pressure | 36 | 8 | 1 |
| 93 | final_peak | 68.0 | 70.8 | +2.8 | 3.5 | 13.8 | 45 | 2 | 15 | 29 | pressure | 28 | 12 | 3 |
| 95 | secondary_peak | 72.0 | 58.3 | -13.7 | 2.0 | 10.0 | 58 | 4 | 10 | 25 | pressure | 36 | 8 | 2 |
| 96 | finale_relax | 90.0 | 100.0 | +10.0 | 0.0 | 20.2 | 140 | 2 | 8 | 9 | friendly | 72 | 0 | 0 |

## 首个周期的表现差异（关 3–12）

| 关 | 阶段 | 配额总量 | 分项 | 初始标记 | 标记时长 | 每盘首标记预算 |
|---:|---|---:|---|---:|---:|---:|
| 3 | build | 28 | blue_diamond 17、gold_gem 11 | 2 | 6 | 5 |
| 4 | peak | 81 | blue_diamond 41、gold_gem 24、yellow_star 16 | 6 | 12 | 7 |
| 5 | relax | 36 | gold_gem 15、red_star 21 | 3 | 7 | 6 |
| 6 | relax | 92 | blue_diamond 44、yellow_star 30、red_star 18 | 7 | 7 | 14 |
| 7 | build | 30 | blue_diamond 12、gold_gem 8、yellow_star 6、red_star 4 | 2 | 6 | 5 |
| 8 | secondary_peak | 69 | gold_gem 38、yellow_star 31 | 5 | 10 | 7 |
| 9 | relax | 42 | blue_diamond 27、gold_gem 9、yellow_star 6 | 3 | 7 | 6 |
| 10 | relax | 79 | blue_diamond 22、gold_gem 17、yellow_star 10、red_star 30 | 6 | 7 | 12 |
| 11 | build | 33 | blue_diamond 20、gold_gem 13 | 2 | 6 | 6 |
| 12 | build | 57 | blue_diamond 29、gold_gem 17、yellow_star 11 | 4 | 6 | 10 |
