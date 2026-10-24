# Astro Adventure / 回声航路

一款融合异星采集、航程选择与塔防发射的原型。每张星球区域就是一个关卡：玩家在关卡中寻找燃油，用同一份燃油建造炮台并支付航程。选定目的地后，飞船进入发射倒计时，敌群会围攻着陆船；撑过防守窗口才能起飞。

## 核心循环

```text
降落到区域
→ 探索并采集橙色燃油
→ 用燃油在四个炮位建造、升级炮台
→ 返回着陆船打开航程图
→ 选择燃油足够抵达的目的地
→ 支付航程燃油并进入发射防守
→ 炮台与玩家共同撑过倒计时
→ 起飞并加载新的区域地图
```

燃油是唯一的共享经济：

- 花在炮台上，更容易守住发射窗口，但能飞的距离会缩短。
- 留给航程，可以前往更远的区域，但发射防守会更危险。
- 燃油不足的航程节点不可确认。
- 已访问区域可以再次进入补充燃油。
- 飞船耐久归零则本局失败，按 `R` 重开。

## 当前关卡

地图为 Khepri-9 的不同区域，使用固定地形种子生成：

- **赤砂盆地**：初始区域，低产燃油较多。
- **铁锈裂谷**：中距离区域，燃油产量提高，围攻强度增加。
- **琉璃沙海**：另一条中距离路线，燃油点更稀疏。
- **深核高原**：远距离区域，需要积累足够燃油才能抵达。

## 操作

| 操作 | 按键 |
| --- | --- |
| 移动 | `WASD` / 方向键 |
| 冲刺 | 按住 `Shift` |
| 应急脉冲击退 | `Space` |
| 建造 / 升级炮台 | 靠近炮位按 `E` |
| 打开航程图 / 防守时修复飞船 | 靠近着陆船按 `E` |
| 航程图选择 | `1–9`、方向键或鼠标 |
| 航程图确认 | `Enter` 或再次点击可达节点 |
| 航程图关闭 | `Esc` |
| 失败后重新开始 | `R` |

玩家没有持续射击武器。应急脉冲只击退近身怪物；守住发射窗口主要依靠炮台和路线判断。

## 当前 HUD

- 顶部：当前区域、剩余燃油、生命和体力
- 发射防守时：飞船耐久、起飞倒计时和剩余围攻敌人
- 右上：联机状态与对端数量
- 左下：基础操作提示
- 底部中央：当前交互
- 短暂通知：采集、建造、防御和连接状态

## 基础联机测试

当前只验证“同一地图内两名玩家的移动同步”，暂不处理多人经济、航程和怪物权威同步。

- `F2`：创建本机 ENet 主机
- `F3`：连接 `127.0.0.1:7777`
- `F4`：断开联机

联机状态下暂时禁止打开航程图，避免不同步的关卡切换。

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
godot --headless --path . --script tests/launch_defense.gd
godot --headless --path . --script tests/music_assets.gd
tests/network_smoke.sh
```

## 背景音乐

背景音乐由 [tools/generate_8bit_music.py](tools/generate_8bit_music.py) 生成，不使用原曲录音或原曲旋律。两个原创动机分别在探索、发现和异常段中复用。

```bash
python3 tools/generate_8bit_music.py
```

脚本只依赖 Python 标准库，输出到 `assets/audio/generated/`：

- `astral_signal_a_main.wav`：稳定探索段
- `astral_signal_b_discovery.wav`：航程图与发现段
- `astral_signal_c_anomaly.wav`：发射防守与异常段
- `astral_signal_suite.wav`：三段连续试听版

修改脚本顶部的 `SIGNAL_A`、`SIGNAL_B` 和段落乐句数据后重新运行脚本，Godot 会重新导入 WAV。

## 目录

```text
scenes/   主场景
scripts/  主循环、航程图、星球地表、怪物、炮台、HUD 与音频
tests/    航程、发射防守和双进程联机测试
assets/   后续美术、音频和字体资源
systems/  后续独立系统
data/     后续星球、区域与怪物配置
```
