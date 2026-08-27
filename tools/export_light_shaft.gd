## weather/light_shaft.png 을 굽는다.
##
## ⚠️ 이 파일은 원래 설계 세션 소유다 (`sprites/build_weather.py`).
##    넘겨받은 도트가 **화면 끝까지 이어지는 사선 격자**여서 줄무늬 필터로 보였고,
##    구름 사이로 새는 빛이 되지 못했다. 규칙은 `PlaceholderArt.light_shaft_texture()`
##    한 곳에만 있으므로 여기서는 그걸 그대로 구워 낼 뿐이다.
##    같은 규칙의 파이썬 판을 `sprites/HANDOVER-light_shaft.md` 로 넘겼다 —
##    **설계 세션이 build_weather.py 에 반영하면 이 스크립트는 지운다.**
extends SceneTree

const OUT := "res://sprites/extracted/weather/light_shaft.png"

func _initialize() -> void:
	var image := PlaceholderArt.light_shaft_texture().get_image()
	var err := image.save_png(ProjectSettings.globalize_path(OUT))
	print("light_shaft %dx%d -> %s (err %d)" % [image.get_width(), image.get_height(), OUT, err])
	quit(0 if err == OK else 1)
