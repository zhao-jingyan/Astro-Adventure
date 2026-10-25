# 回声航路：工程架构

## 目标

玩法设定尚未冻结，但底层结构必须满足以下约束：

- 新星球、敌人、遗物、成就和文本主要通过数据扩展。
- 新增系统不必继续扩大 `main.gd`。
- 单机、联机、存档和 UI 可以依赖稳定服务，而不互相直接读取内部字段。
- 所有基础数据能在无窗口测试中独立加载和验证。

## 分层

```text
data/                         内容资源，面向策划与配置
  planets/                    PlanetDefinition
  levels/                     LevelDefinition
  enemies/                    EnemySpeciesDefinition
  relics/                     RelicDefinition
  achievements/               AchievementDefinition
  localization/               文本字典

scripts/data/                 Resource schema 与 to_dict/validate
scripts/core/                 EventBus、ContentRegistry、SaveStore、Localization
scripts/systems/              Achievement、Relic 等跨玩法状态系统
scripts/world/                Interactable、InteractionResolver、TerrainQuery
scripts/game_hud.gd           表现层，只消费 state Dictionary
scripts/main.gd               组合根：装配系统、连接玩法事件
```

依赖方向固定为：

```text
data → core/data schema → systems → composition root → UI/presentation
```

数据 Resource 不允许反向引用 `main.gd`、HUD 或具体关卡节点。

Autoload 实例名使用 `GameEvents`、`ContentRegistry`、`I18n`、`Relics` 和 `Achievements`。类名与 autoload 单例名分开，避免 Godot 的 singleton 命名冲突；`SaveStore` 是可按 namespace 创建的 `RefCounted`，因此不做全局单例。

## 稳定扩展点

### 星球

`PlanetDefinition` 描述调色板、地形种子、音乐和环境标签。未来新增星球时：

1. 在 `data/planets/` 新增一个 Resource。
2. 在 `data/levels/` 创建引用该星球 id 的关卡。
3. 世界渲染层按 profile 应用颜色和地形参数。

### 敌人

`EnemySpeciesDefinition` 将数值、行为 id、traits 与外观编号分离。敌人脚本负责执行行为契约，内容目录负责选择物种。未来不同星球通过关卡刷新表引用不同 species id，不需要修改敌人绘制类。

### 交互与地形

`Interactable` 提供统一交互 id、提示、优先级和事件 payload。`InteractionResolver` 负责选择当前目标，玩法脚本只处理交互结果。

`TerrainQuery` 从绘制中拆出移动规则，支持速度倍率、危险标签、阻挡和分轴滑动。`PlanetSurface` 作为地形采样适配层，不承担玩家移动政策。

### 事件

`EventBus` 只承载已经发生的游戏事实，例如：

- 波次开始/结束
- 燃油或资源采集
- 关卡完成/失败
- 跨图开始/结束
- 遗物获得

系统不得通过 EventBus 直接修改其他对象内部字段。

### 存档

`SaveStore` 使用带 `schema_version` 的 JSON，按 namespace 隔离数据。成就、设置、遗物和局外解锁可以分别保存；玩法局内状态仍由当前 run 管理。

### i18n

Localization 使用 `key → text` 数据，不允许在稳定系统 API 中传显示文本。资源定义保存 `display_name_key` / `description_key`，表现层负责翻译与插值。

## main.gd 的职责

`main.gd` 是组合根，只应负责：

- 初始化世界和 UI
- 把输入映射为玩法命令
- 协调当前关卡生命周期
- 将系统结果映射为表现

以下内容不应继续放在 `main.gd`：

- 具体星球调色板和生成参数
- 敌人种族数值
- 成就判定和存档格式
- 遗物效果计算
- 本地化文本表
- 通用交互目标选择
- 通用地形移动规则

## 验证策略

基础层使用独立 headless 测试：

- 内容资源：id 唯一、必填字段、validate 通过
- 服务：事件、存档回退、成就幂等、遗物修正、文本回退
- 世界：交互优先级与 payload、地形速度和滑动
- 玩法：关卡生命周期、航程、联机位置同步

测试不得污染真实 `user://` 存档，应使用临时 namespace 或临时目录。

## 尚未冻结的玩法决策

以下内容继续由玩法设计决定，不写死在基础设施中：

- 遗物是局内还是局外成长
- 成就是否影响玩法数值
- 多星球是手工关卡还是程序生成
- 联机对经济和事件的权威规则
- 怪物关系是敌对、中立还是可驯化
- 地形是纯速度影响还是包含硬阻挡/环境伤害
