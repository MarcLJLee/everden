## 한국어 조사 — 받침이 있으면 이/은/을, 없으면 가/는/를.
##
## ★ "개 가 좋아할 거예요" 처럼 띄어 쓰거나 "청설모이" 처럼 틀리면 아이가 읽다가 걸린다.
##   글자 하나 차이지만 **읽히느냐 아니냐**의 차이다.
##
## 한글 음절은 0xAC00 부터고 종성이 28가지다 — (코드 − 0xAC00) % 28 이 0 이면 받침이 없다.
## 한글이 아닌 글자(숫자·영문)로 끝나면 받침 있는 쪽으로 붙인다. 틀려도 덜 어색하다.
class_name Josa
extends RefCounted


static func has_final(word: String) -> bool:
	if word.is_empty():
		return true
	var last := word.unicode_at(word.length() - 1)
	if last < 0xAC00 or last > 0xD7A3:
		return true
	return (last - 0xAC00) % 28 != 0


static func 이가(word: String) -> String:
	return word + ("이" if has_final(word) else "가")


static func 은는(word: String) -> String:
	return word + ("은" if has_final(word) else "는")


static func 을를(word: String) -> String:
	return word + ("을" if has_final(word) else "를")


static func 와과(word: String) -> String:
	return word + ("과" if has_final(word) else "와")
