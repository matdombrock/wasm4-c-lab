#!/bin/bash

echo mounting $1 to /project

podman run --replace --name wasm4-c -v $1:/project -p 4444:4444 wasm4-c w4 watch
