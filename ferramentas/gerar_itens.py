import sys,os
out=sys.argv[1]
S=dict(HEAD=0,CHEST=1,SHOULDERS=2,HANDS=3,LEGS=4,FEET=5,CAPE=6,MAIN_HAND=7,OFF_HAND=8,ACCESSORIES=9)
items=[
("capuz_aprendiz","Capuz do Aprendiz","armadura","HEAD","hood",(0.30,0.07,0.06),(1,0.62,0.15),0,{"defesa":1,"magia":1}),
("elmo_ferro","Elmo de Ferro","armadura","HEAD","helm",(0.40,0.40,0.43),(1,0.62,0.15),0,{"defesa":3}),
("tunica_aprendiz","Túnica do Aprendiz","armadura","CHEST","robe",(0.11,0.09,0.09),(0.45,0.08,0.05),0,{"defesa":2,"magia":2}),
("peitoral_couro","Peitoral de Couro","armadura","CHEST","vest",(0.33,0.22,0.13),(0.18,0.11,0.06),0,{"defesa":3}),
("avental_taverna","Avental de Taverna","roupa","CHEST","apron",(0.52,0.44,0.32),(0.26,0.12,0.08),0,{}),
("gibao_verde","Gibão Verde","roupa","CHEST","vest",(0.18,0.24,0.14),(0.10,0.08,0.05),0,{"defesa":1}),
("ombreiras_ferro","Ombreiras de Ferro","armadura","SHOULDERS","pauldron",(0.38,0.38,0.40),(0.20,0.18,0.17),0,{"defesa":2}),
("luvas_couro","Luvas de Couro","armadura","HANDS","gloves",(0.24,0.16,0.10),(0,0,0),0,{"defesa":1}),
("calca_tecido","Calça de Tecido","armadura","LEGS","pants",(0.14,0.12,0.11),(0,0,0),0,{"defesa":1}),
("botas_couro","Botas de Couro","armadura","FEET","boots",(0.20,0.13,0.08),(0,0,0),0,{"defesa":1,"velocidade":1}),
("capa_viagem","Capa de Viagem","armadura","CAPE","cape",(0.26,0.05,0.04),(0.12,0.03,0.02),0,{"defesa":1}),
("cajado_brasa","Cajado de Brasa","arma","MAIN_HAND","staff",(0.25,0.16,0.09),(1,0.5,0.12),0.9,{"magia":8}),
("escudo_mimico","Escudo Mímico","escudo especial","OFF_HAND","mimic",(0.30,0.16,0.10),(1,0.55,0.12),0.25,{"defesa":6,"mordida":4}),
("capa_lobo_infernal","Capa de Lobo Infernal","armadura","CAPE","wolfcape",(0.16,0.03,0.03),(1,0.25,0.08),0,{"defesa":4,"fogo":3}),
("saia_lobo_infernal","Saia de Lobo Infernal","armadura","LEGS","wolfskirt",(0.17,0.04,0.035),(1,0.25,0.08),0,{"defesa":3,"fogo":2}),
("amuleto_nucleo","Amuleto do Núcleo de Fogo","acessório","ACCESSORIES","amulet",(0.20,0.18,0.16),(1,0.45,0.1),0.35,{"magia":3}),
]
def col(c): return "Color(%g, %g, %g, 1)"%c
for (i,n,t,s,st,c,a,g,stats) in items:
    st_s="{"+", ".join('"%s": %d'%kv for kv in stats.items())+"}"
    txt=f'''[gd_resource type="Resource" script_class="EquipmentItem" load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/equipment/equipment_item.gd" id="1"]

[resource]
script = ExtResource("1")
id = &"{i}"
display_name = "{n}"
item_type = "{t}"
slot = {S[s]}
stats = {st_s}
placeholder_style = &"{st}"
placeholder_color = {col(c)}
placeholder_accent = {col(a)}
glow = {g}
'''
    open(os.path.join(out,i+".tres"),"w").write(txt)
