extends Node

## 全局事件总线。UI 与系统之间只通过信号通信。

signal notify(text: String, kind: String)
signal state_changed
signal objective_completed(objective_id: String)
signal lab_completed(lab_id: String)
signal knowledge_unlocked(knowledge_id: String)
signal economy_changed
signal chapter_completed(chapter_id: String)
signal screen_changed(screen_id: String)
signal game_event(event_name: String)
signal tutorial_updated(step: Dictionary)

func toast(text: String, kind: String = "info") -> void:
	notify.emit(text, kind)

func fire(event_name: String) -> void:
	game_event.emit(event_name)
