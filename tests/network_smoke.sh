#!/usr/bin/env bash

# 启动两个真实 Godot 进程，验证本机 ENet 主机/客户端能双向同步位置。
set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
godot_bin="${GODOT_BIN:-godot}"
run_dir="$(mktemp -d)"
host_log="${run_dir}/host.log"
client_log="${run_dir}/client.log"
host_pid=""

cleanup() {
	if [[ -n "${host_pid}" ]] && kill -0 "${host_pid}" 2>/dev/null; then
		kill "${host_pid}" 2>/dev/null || true
	fi
	rm -rf "${run_dir}"
}
trap cleanup EXIT

"${godot_bin}" --headless --path "${project_dir}" -- --host --network-smoke \
	>"${host_log}" 2>&1 &
host_pid=$!

for _ in {1..30}; do
	if grep -q "NETWORK_HOST_READY" "${host_log}"; then
		break
	fi
	sleep 0.1
done

if ! "${godot_bin}" --headless --path "${project_dir}" -- --join --network-smoke \
	>"${client_log}" 2>&1; then
	cat "${client_log}"
	exit 1
fi

if ! wait "${host_pid}"; then
	cat "${host_log}"
	exit 1
fi
host_pid=""

if ! grep -q "NETWORK_SMOKE_OK role=host" "${host_log}"; then
	cat "${host_log}"
	exit 1
fi
if ! grep -q "NETWORK_SMOKE_OK role=client" "${client_log}"; then
	cat "${client_log}"
	exit 1
fi

echo "联机冒烟测试通过：主机和客户端均收到对端位置。"
