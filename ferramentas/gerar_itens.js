// Gera os itens de mago (inspirados nos tipos de item de mago do Tibia, com nomes próprios) em godot/data/items/.
// uso: node ferramentas/gerar_itens.js
// stats: vida, mana, defesa, magia (% em todas as magias), <elemento> (% nas magias do elemento), ataque (ataque básico).
const fs = require('fs');
const path = require('path');
const DIR = path.join(__dirname, '..', 'godot', 'data', 'items');
// slots: 0 cabeça, 1 peito, 2 ombros, 3 mãos, 4 pernas, 5 pés, 6 capa, 7 arma, 8 escudo, 9 acessório
const ITENS = [
  // cabeça
  ['chapeu_aprendiz', 'Chapéu de Aprendiz', 0, 'wizardhat', [0.25, 0.2, 0.35], [0.8, 0.7, 0.3], 1, { defesa: 1, magia: 2 }, 0],
  ['turbante_mistico', 'Turbante Místico', 0, 'turban', [0.15, 0.3, 0.6], [0.95, 0.8, 0.3], 8, { defesa: 2, magia: 5, mana: 20 }, 0],
  ['chapeu_feiticeiro', 'Chapéu do Feiticeiro', 0, 'wizardhat', [0.08, 0.06, 0.2], [0.75, 0.55, 1], 20, { defesa: 3, magia: 10, mana: 50 }, 0.2],
  ['diadema_arcano', 'Diadema Arcano', 0, 'circlet', [0.75, 0.65, 0.3], [0.6, 0.85, 1], 35, { defesa: 4, magia: 15, mana: 90 }, 0.4],
  // peito
  ['manto_estudioso', 'Manto do Estudioso', 1, 'robe', [0.2, 0.25, 0.45], [0.85, 0.75, 0.4], 1, { defesa: 2, mana: 20 }, 0],
  ['manto_mistico', 'Manto Místico', 1, 'robe', [0.3, 0.1, 0.35], [0.95, 0.75, 0.35], 12, { defesa: 4, mana: 60, magia: 5 }, 0],
  ['manto_arquimago', 'Manto do Arquimago', 1, 'robe', [0.06, 0.05, 0.12], [0.85, 0.65, 1], 30, { defesa: 6, mana: 150, magia: 10, vida: 40 }, 0.15],
  // pernas
  ['saia_linho', 'Saia de Linho', 4, 'kilt', [0.45, 0.4, 0.32], [0.6, 0.5, 0.3], 1, { defesa: 1 }, 0],
  ['calca_encantada', 'Calça Encantada', 4, 'pants', [0.15, 0.12, 0.3], [0.7, 0.6, 1], 15, { defesa: 3, magia: 4 }, 0],
  // pés
  ['sandalias', 'Sandálias', 5, 'sandals', [0.4, 0.3, 0.2], [0.6, 0.45, 0.3], 1, { defesa: 1 }, 0],
  ['botas_ligeiras', 'Botas Ligeiras', 5, 'boots', [0.3, 0.2, 0.12], [0.9, 0.8, 0.4], 10, { defesa: 1, velocidade: 15 }, 0],
  ['botas_macias', 'Botas Macias', 5, 'boots', [0.5, 0.45, 0.4], [0.7, 0.9, 1], 25, { defesa: 2, vida: 30, mana: 30 }, 0],
  // capa
  ['capa_estelar', 'Capa Estelar', 6, 'cape', [0.05, 0.06, 0.18], [0.75, 0.8, 1], 18, { defesa: 3, magia: 5 }, 0],
  // escudo (livros de feitiço)
  ['livro_feiticos', 'Livro de Feitiços', 8, 'book', [0.35, 0.18, 0.1], [0.9, 0.75, 0.35], 1, { defesa: 2, magia: 3 }, 0],
  ['grimorio_chamas', 'Grimório das Chamas', 8, 'book', [0.45, 0.08, 0.04], [1, 0.5, 0.1], 15, { defesa: 3, fogo: 10, lava: 10 }, 0.3],
  ['grimorio_mares', 'Grimório das Marés', 8, 'book', [0.06, 0.18, 0.4], [0.4, 0.85, 1], 15, { defesa: 3, agua: 10, gelo: 10 }, 0.3],
  ['grimorio_tempestade', 'Grimório da Tempestade', 8, 'book', [0.3, 0.32, 0.38], [0.75, 0.7, 1], 15, { defesa: 3, vento: 10, raio: 10 }, 0.3],
  ['grimorio_raizes', 'Grimório das Raízes', 8, 'book', [0.22, 0.3, 0.12], [0.5, 0.9, 0.3], 15, { defesa: 3, terra: 10, natureza: 10 }, 0.3],
  ['tomo_ancestral', 'Tomo Ancestral', 8, 'book', [0.12, 0.1, 0.08], [1, 0.85, 0.5], 30, { defesa: 5, magia: 10 }, 0.5],
  // armas: varinhas e cetros
  ['varinha_aprendiz', 'Varinha do Aprendiz', 7, 'wand', [0.35, 0.25, 0.15], [0.9, 0.9, 0.7], 1, { ataque: 6 }, 0.4],
  ['varinha_brasa', 'Varinha de Brasa', 7, 'wand', [0.25, 0.12, 0.08], [1, 0.45, 0.1], 7, { ataque: 14, fogo: 5 }, 0.8],
  ['varinha_gelo', 'Varinha de Gelo', 7, 'wand', [0.6, 0.75, 0.85], [0.6, 0.9, 1], 7, { ataque: 14, agua: 5 }, 0.8],
  ['varinha_trovao', 'Varinha do Trovão', 7, 'wand', [0.3, 0.3, 0.35], [0.75, 0.75, 1], 7, { ataque: 14, vento: 5 }, 0.8],
  ['varinha_espinho', 'Varinha de Espinho', 7, 'wand', [0.3, 0.22, 0.12], [0.5, 0.95, 0.35], 7, { ataque: 14, natureza: 5 }, 0.8],
  ['cetro_magma', 'Cetro de Magma', 7, 'rod', [0.15, 0.08, 0.06], [1, 0.4, 0.05], 22, { ataque: 30, fogo: 8, lava: 8, magia: 4 }, 1.1],
  ['cetro_glacial', 'Cetro Glacial', 7, 'rod', [0.5, 0.65, 0.8], [0.7, 0.95, 1], 22, { ataque: 30, agua: 8, gelo: 8, magia: 4 }, 1.1],
  ['cetro_tempestade', 'Cetro da Tempestade', 7, 'rod', [0.25, 0.25, 0.3], [0.8, 0.8, 1], 22, { ataque: 30, vento: 8, raio: 8, magia: 4 }, 1.1],
  ['cetro_ancestral', 'Cetro Ancestral', 7, 'rod', [0.25, 0.18, 0.1], [0.55, 1, 0.35], 22, { ataque: 30, terra: 8, natureza: 8, magia: 4 }, 1.1],
  // acessórios
  ['colar_protecao', 'Colar de Proteção', 9, 'amulet', [0.6, 0.55, 0.4], [0.9, 0.9, 1], 5, { defesa: 3 }, 0.2],
  ['amuleto_mana', 'Amuleto de Mana', 9, 'amulet', [0.4, 0.4, 0.5], [0.35, 0.55, 1], 12, { mana: 80 }, 0.3],
  // mãos (anéis/luvas)
  ['anel_energia', 'Anel de Energia', 3, 'ring', [0.7, 0.6, 0.3], [0.6, 0.8, 1], 10, { magia: 5 }, 0.3],
];
const c = a => `Color(${a[0]}, ${a[1]}, ${a[2]}, 1)`;
const gd = o => '{' + Object.entries(o).map(([k, v]) => `"${k}": ${v}`).join(', ') + '}';
for (const [id, nome, slot, estilo, cor, acento, nivel, stats, brilho] of ITENS) {
  fs.writeFileSync(path.join(DIR, id + '.tres'), `[gd_resource type="Resource" script_class="EquipmentItem" load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/equipment/equipment_item.gd" id="1"]

[resource]
script = ExtResource("1")
id = &"${id}"
display_name = "${nome}"
item_type = "${['cabeça', 'armadura', 'ombreira', 'anel', 'pernas', 'botas', 'capa', 'arma', 'livro', 'amuleto'][slot]}"
slot = ${slot}
level_req = ${nivel}
stats = ${gd(stats)}
placeholder_style = &"${estilo}"
placeholder_color = ${c(cor)}
placeholder_accent = ${c(acento)}
glow = ${brilho}
`);
}
console.log('itens gerados:', ITENS.length);
