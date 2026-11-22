"""Assinatura do app Android: muda quando o APK precisa ser reinstalado.

O app baixa só o pacote do jogo (.pck). Isso funciona enquanto não mudam coisas lidas quando
o Godot abre: nomes de classe (class_name), autoloads, a versão do Godot e o boot.gd.
Esta assinatura junta tudo isso; se o pacote novo tiver outra assinatura, o app pede para
baixar o APK novo em vez do pacote.
Uso: python3 ferramentas/app/assinatura.py godot  (escreve godot/app/assinatura.txt)
"""
import hashlib, pathlib, re, sys

raiz = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "godot")
partes = []
for f in sorted(raiz.rglob("*.gd")):
    if ".godot" in f.parts:
        continue
    for m in re.finditer(r"^class_name\s+(\w+)", f.read_text(encoding="utf-8"), re.M):
        partes.append(f"{m.group(1)}={f.relative_to(raiz).as_posix()}")
proj = (raiz / "project.godot").read_text(encoding="utf-8")
auto = re.search(r"\[autoload\](.*?)(\n\[|\Z)", proj, re.S)
partes.append("autoload:" + (auto.group(1).strip() if auto else ""))
partes.append("boot:" + hashlib.md5((raiz / "scripts/app/boot.gd").read_bytes()).hexdigest())
partes.append("godot:" + (sys.argv[2] if len(sys.argv) > 2 else "4.4.1"))
sig = hashlib.md5("\n".join(partes).encode()).hexdigest()[:12]
(raiz / "app").mkdir(exist_ok=True)
(raiz / "app/assinatura.txt").write_text(sig + "\n")
print(sig)
