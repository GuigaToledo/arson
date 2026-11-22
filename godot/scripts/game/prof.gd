class_name Prof
extends RefCounted
## Medidor de desempenho leve: soma o tempo gasto em cada parte (desenho dos personagens,
## IA dos monstros, efeitos) e o Perf escreve a cada 5 s no registro ("ARSONPERF ...").
## No Android o registro sai no logcat (dá para ler pelo cabo, adb logcat).

static var acc := {}
static var count := {}
static var on := OS.has_feature("android") or OS.has_feature("editor")


static func t() -> int:
	return Time.get_ticks_usec() if on else 0


static func add(key: String, t0: int) -> void:
	if not on:
		return
	acc[key] = int(acc.get(key, 0)) + (Time.get_ticks_usec() - t0)
	count[key] = int(count.get(key, 0)) + 1


## Texto com ms por quadro de cada parte e zera.
static func report(frames: int) -> String:
	var parts := PackedStringArray()
	for k in acc:
		parts.append("%s=%.2fms/%d" % [k, float(acc[k]) / 1000.0 / maxi(1, frames), int(count[k]) / maxi(1, frames)])
	acc.clear()
	count.clear()
	return " ".join(parts)
