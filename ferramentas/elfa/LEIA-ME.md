# Elyra (NPC elfa) — sprites a partir do STL

Modelo: "Summer Elf with Ice Cream" (Cults3D, autor GeraZyb). O STL **não** fica no repositório.
Para refazer: coloque o STL como `elfa.stl` numa pasta de trabalho e rode, nessa ordem:

1. `python3 -c "from render import *; t=load_stl('elfa.stl'); np.save('t.npy',t); np.save('n.npy',vertex_normals(t))"`
2. `seg.py` → `rough.py` → `cut.py` → `labels.py` (cabelo, sorvete) → `biq2.py` (biquíni: bordas esculpidas, sementes em `pick.py`)
3. `final.py` (cores: pele, cabelo, biquíni rosa, sorvete; fita e adaga na coxa)
4. `shade.py <saida>` → `idle.png` + `sprites.json` (8 direções, 4 quadros de respiração)

Depende de numpy, scipy, numba e pillow. Câmera e luzes iguais às de `ferramentas/sprites3d/render.py`.
