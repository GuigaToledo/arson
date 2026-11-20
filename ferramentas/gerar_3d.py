#!/usr/bin/env python3
"""Gera modelos 3D de graça a partir de imagens, usando o Hunyuan3D (Tencent,
código aberto) num Space do Hugging Face. Roda no GitHub Actions.

  arte/gerar3d/personagens/<nome>.png|jpg  ->  arte/modelos_gerados/<nome>.glb

Usa a variável HF_TOKEN se existir (mais cota diária); sem ela tenta anônimo.
Só gera o que ainda não tem modelo.
"""
import os, sys, shutil, glob, json, traceback

SRC = 'arte/gerar3d/personagens'
DST = 'arte/modelos_gerados'
SPACES = ['tencent/Hunyuan3D-2.1', 'tencent/Hunyuan3D-2']
WANT = {
    'caption': '', 'steps': 30, 'guidance_scale': 5.0, 'seed': 1234, 'octree_resolution': 256,
    'check_box_rembg': True, 'num_chunks': 8000, 'randomize_seed': False,
}


def pending():
    out = []
    for f in sorted(glob.glob(os.path.join(SRC, '*'))):
        stem, ext = os.path.splitext(os.path.basename(f))
        if ext.lower() in ('.png', '.jpg', '.jpeg', '.webp') and not os.path.exists(os.path.join(DST, stem + '.glb')):
            out.append((stem, f))
    return out


def find_glb(x, found):
    if isinstance(x, str):
        if x.lower().endswith(('.glb', '.gltf', '.obj')) and os.path.exists(x):
            found.append(x)
    elif isinstance(x, dict):
        for v in x.values():
            find_glb(v, found)
    elif isinstance(x, (list, tuple)):
        for v in x:
            find_glb(v, found)
    return found


def generate(client, api, img):
    from gradio_client import handle_file
    eps = api.get('named_endpoints', {})
    order = [e for e in ('/generation_all', '/shape_generation') if e in eps]
    for ep in order:
        params = eps[ep]['parameters']
        args = []
        for p in params:
            name = p.get('parameter_name') or p.get('label', '')
            if name in ('image', 'img', 'input_image') or 'image' in name.lower() and 'mv' not in name.lower():
                args.append(handle_file(img))
            elif name in WANT:
                args.append(WANT[name])
            elif p.get('parameter_has_default'):
                args.append(p.get('parameter_default'))
            else:
                args.append(None)
        print('chamando', ep, [p.get('parameter_name') for p in params], flush=True)
        try:
            res = client.predict(*args, api_name=ep)
        except Exception:
            traceback.print_exc()
            continue
        files = find_glb(res, [])
        print('arquivos:', files)
        if files:
            textured = [f for f in files if 'textur' in f.lower()]
            return (textured or files)[-1] if ep == '/generation_all' else files[0]
    return None


def main():
    todo = pending()
    if '--listar' in sys.argv:
        print(' '.join(n for n, _ in todo))
        return
    if not todo:
        print('nada para gerar')
        return
    from gradio_client import Client
    os.makedirs(DST, exist_ok=True)
    token = os.environ.get('HF_TOKEN') or None
    for space in SPACES:
        try:
            client = Client(space, hf_token=token)
            api = client.view_api(return_format='dict', print_info=False)
            print('Space:', space, 'endpoints:', list(api.get('named_endpoints', {}).keys()))
        except Exception:
            traceback.print_exc()
            continue
        for name, img in list(todo):
            out = generate(client, api, img)
            if out:
                ext = os.path.splitext(out)[1]
                shutil.copy(out, os.path.join(DST, name + ext))
                print('gerado:', name, out)
                todo.remove((name, img))
        if not todo:
            break
    if todo:
        print('::warning::Não consegui gerar:', [n for n, _ in todo], '(cota do Hugging Face? coloque HF_TOKEN nos segredos do GitHub)')


main()
