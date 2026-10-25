# 内容数据约定

所有可扩展玩法内容优先放在 `data/`。稳定 id 使用小写 snake_case，一旦进入存档或事件就不要随显示名称修改。

## 新增星球

1. 复制 `data/planets/khepri_9.tres`。
2. 修改 `id`、显示键、地形种子、调色板和音乐 id。
3. 在 `data/levels/*.tres` 的 `planet_id` 中引用它。
4. 运行 `tests/run_all.sh`，ContentRegistry 会检查跨资源引用。

## 新增关卡

1. 复制现有 `data/levels/*.tres`。
2. 设置稳定的 `id`、`planet_id` 和 `map_position`。
3. 填写准备时间、总波次、`wave_enemy_counts` 和 `enemy_spawn_table`。
4. 在 `data/localization/zh_CN.json`、`en.json` 增加名称与描述键。

刷新表条目字段：

```text
enemy_id   敌人物种 id
weight     相对权重
min_wave   最早出现的波次
max_wave   最晚出现的波次
```

## 新增敌人

1. 复制 `data/enemies/*.tres`。
2. 设置数值、`visual_kind`、`behavior_id` 和 `traits`。
3. 在关卡刷新表中按 `enemy_id` 引用。

当前 `visual_kind` 复用三种基础绘制外观。未来增加新绘制时，再扩展 Enemy 的表现注册表；数值和行为不再写死在 Enemy 中。

## 新增遗物与成就

- 遗物只保存修正字典，具体效果由玩法层查询 `RelicSystem.get_modifier()`。
- 成就保存一个 EventBus 事件名、目标次数，以及可选的数值参数索引。
- `amount_argument_index = -1` 表示每次事件计 1；`0` 表示使用事件第一个数值参数作为本次进度。

## 验证

```bash
godot --headless --path . --script tests/content_registry.gd
tests/run_all.sh
```
