## data/*.json 검증기 — CLI 단독 실행용. (DEMO-SPEC §2, BRIEF §5.5)
##
##   godot --headless --script tools/validate_data.gd
##   godot --headless --script tools/validate_data.gd -- --all   # prototype:false 종까지 전부
##   godot --headless --script tools/validate_data.gd -- --animals=/경로/animals.json
##
## 종료 코드: 0 = 통과(경고는 있을 수 있음), 1 = 로드 거부
extends SceneTree

func _initialize() -> void:
	var prototype_only := true
	var animals_path := DataLoader.ANIMALS_PATH
	var tags_path := DataLoader.TAGS_PATH
	for arg in OS.get_cmdline_user_args():
		if arg == "--all":
			prototype_only = false
		elif arg.begins_with("--animals="):
			animals_path = arg.trim_prefix("--animals=")
		elif arg.begins_with("--tags="):
			tags_path = arg.trim_prefix("--tags=")

	print("=== 태그 검증 (%s) ===" % ("prototype 종만" if prototype_only else "전체 종"))
	var result := DataLoader.load_all(prototype_only, tags_path, animals_path)
	print(result.report())

	var ambient_bad := 0
	if result.ok:
		print("")
		print("--- 앰비언트 생물 (BRIEF §3.10) ---")
		ambient_bad = _check_ambient(result)
		print("")
		print("--- 감각 × 흔적 대조표 (trait_to_sense + sense_profile 로만 생성) ---")
		print("    O = 몸이 보인다   △ = 방향·단서까지   X = 못 찾는다")
		_print_guide_matrix(result)

	quit(0 if result.ok and ambient_bad == 0 else 1)


## 어느 동료가 어느 대상을 감지하는지 표로 찍는다.
## 코드 어디에도 종 id 가 없다는 것을 눈으로 확인하기 위한 출력이다.

## 지역이 적어둔 앰비언트 생물이 실제로 있는가. (BRIEF §3.10)
## 오타 하나로 그 지역에서 나비가 조용히 사라지는 것을 막는다.
func _check_ambient(result) -> int:
	var path := "res://sprites/extracted/ambient/ambient.json"
	if not FileAccess.file_exists(path):
		print("  앰비언트 정의가 없다 — 건너뛴다")
		return 0
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	var known: Dictionary = (parsed as Dictionary).get("creatures", {}) if parsed is Dictionary else {}
	var bad := 0
	for id in result.regions:
		var region: Dictionary = result.regions[id]
		for name in region.get("ambient", {}):
			if known.has(name):
				continue
			print("  [오류] 지역 %s 의 앰비언트 '%s' 는 ambient.json 에 없다" % [id, name])
			bad += 1
	if bad == 0:
		print("  앰비언트 %d 종 · 지역 표 이상 없음" % known.size())
	return bad

func _print_guide_matrix(result: DataLoader.Result) -> void:
	var companions := []
	var targets := []
	for id in result.species:
		var species: Dictionary = result.species[id]
		if species.get("senses", []).is_empty():
			targets.append(species)
		else:
			companions.append(species)
			targets.append(species)

	for companion in companions:
		var senses: Array = companion.get("senses", [])
		var line := "%s(%s) → " % [companion["name"], ", ".join(PackedStringArray(senses))]
		for target in targets:
			if target["id"] == companion["id"]:
				continue
			var mark := "X"
			for trait_name in target.get("traits", []):
				var sense := result.schema.sense_for_trait(String(trait_name))
				if not (sense in senses):
					continue
				if result.schema.sense_reveals_body(sense):
					mark = "O"
					break
				mark = "△"
			line += "%s %s  " % [target["name"], mark]
		print("  " + line)
