#!/bin/bash
# Baixa o Blender 4.2 (só na primeira vez no job) e repassa os argumentos.
B=$HOME/blender-4.2.3-linux-x64/blender
if [ ! -x "$B" ]; then
  wget -q https://download.blender.org/release/Blender4.2/blender-4.2.3-linux-x64.tar.xz -O /tmp/blender.tar.xz
  tar -xf /tmp/blender.tar.xz -C $HOME
fi
exec "$B" "$@"
