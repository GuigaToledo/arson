"""Visual Factory etapa 9: inspeção das regiões do mapa (não altera nada).

Lê godot/data/maps/ilha.txt e responde:
- quanto de cada terreno existe em cada região (blocos de 30x30 tiles);
- se todos os pontos de interesse dão para alcançar a pé saindo do início (@);
- áreas andáveis isoladas (bolsões onde o jogador nunca chega).
Uso: python3 ferramentas/vf/checar_regioes.py
"""
from collections import Counter, deque
import pathlib, sys

RAIZ = pathlib.Path(__file__).resolve().parents[2]
MAPA = RAIZ / "godot/data/maps/ilha.txt"
BLOQ = set("~HR")
NOMES = {"~": "água", ".": "grama", ":": "terra", ",": "areia", "#": "calçamento", "f": "floresta",
         "r": "rocha", "=": "ponte", "H": "construção", "T": "templo", "@": "início", "g": "cemitério",
         "j": "selva", "k": "caverna", "R": "parede", "b": "acamp.", "o": "acamp. orc", "y": "acamp."}
# mesmos pontos das fotos do Visual QA (island.gd FOTO_CENAS)
PONTOS = {"vila": (27, 26), "vila_casas": (22, 22), "floresta_ilha": (12, 36), "campos": (82, 30),
          "cemiterio": (86, 12), "caverna": (116, 22), "selva": (96, 84), "acampamento_orc": (124, 77),
          "ciclopes_lava": (104, 100)}

rows = [l.rstrip("\n") for l in MAPA.read_text(encoding="utf-8").splitlines() if l.strip()]
h, w = len(rows), max(len(r) for r in rows)
at = lambda x, y: rows[y][x] if 0 <= y < h and 0 <= x < len(rows[y]) else "~"
anda = lambda x, y: at(x, y) not in BLOQ

ini = next((x, y) for y in range(h) for x in range(w) if at(x, y) == "@")


def bfs(s):
    vis = {s}
    q = deque([s])
    while q:
        x, y = q.popleft()
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            n = (x + dx, y + dy)
            if n not in vis and anda(*n):
                vis.add(n)
                q.append(n)
    return vis


alc = bfs(ini)
print(f"Mapa {w}x{h}, início em {ini}, {len(alc)} tiles alcançáveis a pé\n")
falhas = 0
print("Pontos de interesse:")
for nome, (x, y) in PONTOS.items():
    ok = (x, y) in alc
    falhas += not ok
    print(f"  {'ok ' if ok else 'XX '} {nome:16s} ({x},{y}) chão '{NOMES.get(at(x, y), at(x, y))}'")

todos = {(x, y) for y in range(h) for x in range(w) if anda(x, y)}
resto = todos - alc
bolsoes = []
while resto:
    p = next(iter(resto))
    b = bfs(p) & resto
    resto -= b
    bolsoes.append(b)
bolsoes = [b for b in bolsoes if len(b) >= 4]
print(f"\nBolsões andáveis isolados (>=4 tiles): {len(bolsoes)}")
for b in sorted(bolsoes, key=len, reverse=True)[:8]:
    x, y = min(b)
    print(f"  {len(b):4d} tiles perto de ({x},{y})")

print("\nTerreno por região (blocos 30x30, % dos tiles):")
for by in range(0, h, 30):
    for bx in range(0, w, 30):
        c = Counter(at(x, y) for y in range(by, min(by + 30, h)) for x in range(bx, min(bx + 30, w)))
        tot = sum(c.values())
        top = ", ".join(f"{NOMES.get(k, k)} {v * 100 // tot}%" for k, v in c.most_common(4) if v * 100 // tot)
        print(f"  [{bx:3d},{by:3d}] {top}")
sys.exit(1 if falhas else 0)
