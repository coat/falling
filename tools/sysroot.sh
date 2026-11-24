#!/usr/bin/env sh

export EM_CACHE="$(pwd)/.emscripten"
if [ ! -d "$EM_CACHE/sysroot/include" ]; then
  embuilder build sysroot
fi
