extends Node

## 全局游戏事实总线。
##
## 信号只描述已经发生的事件，系统可以监听，但不应借此直接修改其他对象内部状态。

signal level_started(level_id: String)
signal preparation_started(level_id: String, wave: int)
signal wave_started(level_id: String, wave: int)
signal wave_completed(level_id: String, wave: int)
signal wave_cleared(level_id: String, wave: int)
signal level_completed(level_id: String)
signal level_failed(level_id: String, reason: String)
signal level_changed(level_id: String)
signal travel_started(from_level_id: String, to_level_id: String, fuel_cost: int)
signal travel_completed(to_level_id: String)
signal resource_collected(kind: String, amount: int, total: int)
signal fuel_collected(amount: int, total: int)
signal player_damaged(amount: float, remaining_health: float)
signal enemy_defeated(species_id: String)
signal relic_acquired(relic_id: String, stack_count: int)
signal achievement_unlocked(achievement_id: String)
signal locale_changed(locale: String)
signal interaction_performed(target_id: String, payload: Dictionary)
