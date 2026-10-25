# Astro Adventure / 回声航路

一款融合异星探索、波次塔防和关卡间航程选择的原型。

每个关卡内部保持独立的生存防守生命周期；地图与燃油负责关卡之间的关系，不参与炮台建设经济。

## 关卡生命周期

```text
关卡开始
→ 第一波准备倒计时
→ 战斗并清空当前波
→ 下一波准备倒计时
→ 五波全部完成
→ 打开航程图选择下一关
→ 消耗燃油起飞并加载新地图
→ 新关卡从第一波准备倒计时重新开始
```

规则：

- 初始准备时间为 24 秒，后续波次准备时间为 38 秒。
- `Enter` 可以提前结束准备倒计时。
- 第一波只有 3 个侦察体，先在基地周围低速游荡 7 秒，之后才转为进攻。
- 第二波开始增加数量，并逐步引入远程喷吐体和重装体。
- 飞船耐久归零则关卡失败；五波全部清空则进入关卡间航程图。

## 资源职责

资源严格分离：

- **晶尘**：建造和升级炮台、修复飞船。
- **深核**：三级炮台升级材料，只生成在远区。
- **燃油**：只用于关卡之间的航程，不参与炮台建造。

关卡完成后，航程图根据地图距离计算燃油成本。燃油不足的节点无法确认；已经访问过的关卡可以再次进入补充资源。

## 当前地图

地图为 Khepri-9 的不同区域，使用固定种子生成：

- **赤砂盆地**
- **铁锈裂谷**
- **琉璃沙海**
- **深核高原**

玩家会主动受到环境怪物追击，并有冲刺体力与无伤害应急脉冲用于脱离。

## 操作

| 操作 | 按键 |
| --- | --- |
| 移动 | `WASD` / 方向键 |
| 冲刺 | 按住 `Shift` |
| 应急脉冲击退 | `Space` |
| 建造 / 升级炮台、修复飞船 | 靠近目标按 `E` |
| 关卡完成后选择航线 | `E` |
| 提前开始下一波 | `Enter` |
| 航程图选择 | `1–9`、方向键或鼠标 |
| 航程图确认 | `Enter` 或再次点击可达节点 |
| 航程图关闭 | `Esc` |
| 失败后重新开始 | `R` |

## HUD

- 顶部：当前区域、燃油、晶尘、深核、生命和体力
- 波次条：飞船耐久、当前波次、准备倒计时或剩余敌人数
- 右下：紧凑区域小地图，标记着陆船、玩家、晶尘、燃油和敌人
- 左下：基础操作提示
- 底部中央：当前交互

## 基础联机测试

当前只验证同一地图内两名玩家的移动同步，暂不同步波次、资源和航程。

- `F2`：创建本机 ENet 主机
- `F3`：连接 `127.0.0.1:7777`
- `F4`：断开联机

## 工程基建

玩法参数正在迁移到数据资源：

- `data/planets/`：星球调色板、音乐和地形种子。
- `data/levels/`：区域位置、危险度、准备时间、总波次和敌人刷新表。
- `data/enemies/`：敌人物种数值、行为 id、traits、攻击与仇恨参数。
- `data/relics/`、`data/achievements/`：遗物和成就定义。
- `data/localization/`：中英文文本表。

运行时基础服务：

- EventBus：关卡、波次、资源、跨图、遗物和成就事件。
- SaveStore：带 schema 版本和原子写入的 JSON 存档。
- LocalizationService：语言切换、参数插值和中文回退。
- RelicSystem：数据驱动的乘数和平直加值。
- AchievementSystem：事件累计、幂等解锁与进度持久化。
- Interactable / InteractionResolver：统一交互半径、优先级和 payload。
- TerrainQuery：地形速度、阻挡、危险标签和分轴滑动。

详细分层与扩展方法见 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)。

## 运行与验证

要求 Godot 4.7 或兼容的 4.7.x 版本。

```bash
godot --path .
```

完整验证：

```bash
godot --headless --path . --editor --quit
godot --headless --path . --quit-after 120
godot --headless --path . --script tests/runtime_smoke.gd
godot --headless --path . --script tests/travel_loop.gd
godot --headless --path . --script tests/level_lifecycle.gd
tests/network_smoke.sh
tests/run_all.sh
```

## 目录

```text
scenes/   主场景
scripts/  data、core、systems、world 与玩法表现层
data/     星球、关卡、敌人、遗物、成就与 i18n 配置
docs/     架构约束与扩展说明
tests/    内容、服务、世界、玩法与双进程联机测试
assets/   美术、音频和字体资源
```
