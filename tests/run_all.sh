#!/usr/bin/env bash

# 统一验证入口：项目加载、全部 GDScript 测试和双进程联机测试。
set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
godot_bin="${GODOT_BIN:-godot}"

cd "${project_dir}"

echo "[1/3] 校验项目导入与脚本"
"${godot_bin}" --headless --path . --editor --quit

echo "[2/3] 运行独立 GDScript 测试"
for test_script in tests/*.gd; do
	if [[ ! -f "${test_script}" ]]; then
		continue
	fi
	echo "  → ${test_script}"
	"${godot_bin}" --headless --path . --script "${test_script}"
done

echo "[3/3] 运行双进程联机测试"
tests/network_smoke.sh

echo "全部验证通过。"
