#!/bin/bash

podman run -it --replace --name wasm4-c -v .:/project -p 4444:4444 wasm4-c bash
