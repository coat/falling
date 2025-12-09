#!/usr/bin/env sh

export EM_CACHE=$(pwd)/.emscripten
if [ ! -d "$EM_CACHE" ]; then
  embuilder.py build sysroot
fi
