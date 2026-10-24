# Astro Adventure

《回声航路》的灰盒原型工程，当前使用 Godot 4.7 和 GDScript。

## 环境

- macOS Apple Silicon
- Godot 4.7.2
- Git

Godot 已安装到：

```text
/Applications/Godot.app
```

终端中的 Godot 命令：

```bash
godot --version
```

## 打开工程

在 Finder 中双击 `project.godot`，或者执行：

```bash
open -a Godot /Users/zhaojingyan/Documents/Codex/2026-10-25/start-loop-ui-ui-end-loop/code/Astro-Adventure
```

## 命令行运行

```bash
cd /Users/zhaojingyan/Documents/Codex/2026-10-25/start-loop-ui-ui-end-loop/code/Astro-Adventure
godot --path .
```

只检查导入和启动，不打开游戏窗口：

```bash
godot --headless --path . --editor --quit
godot --headless --path . --quit-after 2
```

## 当前验证内容

- 主场景可以启动。
- WASD 或方向键控制玩家移动。
- 飞船、基地范围和四个炮台占位可以绘制。
- Esc 可以退出游戏。

## 目录约定

```text
scenes/   场景
scripts/  脚本
assets/   美术、音频和字体
systems/  敌潮、经济、胜负等系统
data/     可配置的数据资源
```

当前仍是环境与启动验证版本，尚未加入敌人、资源采集、炮台建造和飞船耐久。

如果按键后画面没有移动，请先点击游戏窗口再操作。场景左上角显示“键盘输入：已收到”后，表示窗口已经成功接收到键盘事件。
