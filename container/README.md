# WASM-4 C Build Container

This Containerfile provides a complete build environment for [WASM-4](https://wasm4.org) projects written in C.

## What's Included

- **wasm4 CLI**: The official WASM-4 tooling (`w4 build`, `w4 run`, `w4 watch`, etc.)
- **wasi-sdk**: Full C/C++ toolchain with wasm32-wasi target
- **clang**: Compiler configured for WebAssembly output
- **make**, **git**, **python3**: Common build tools


## Useage

### Build the container image

```bash
# Standard build
podman build -t wasm4-c -f Containerfile
```

### Create a new WASM-4 C project

```bash
podman run --rm -v "$PWD":/project wasm4-c w4 new --c my-game
```

### 3. Build your project

```bash
cd my-game

# Build using the container
podman run --rm -v "$PWD":/project wasm4-c make

# Watch your project
podman run --rm -v "$PWD":/project wasm4-c w4 watch

# Enter the container
podman run --rm -v "$PWD":/project wasm4-c bash
```


## Useful Commands

| Command | Description |
|---------|-------------|
| `w4 new --c <name>` | Create new C project |
| `w4 run <cart.wasm>` | Run in browser |
| `w4 run-native <cart.wasm>` | Run natively (requires SDL) |
| `w4 watch <cart.wasm>` | Watch for changes and reload |
| `w4 bundle --html <file> <cart.wasm>` | Create HTML bundle |

## Compiler Flags Explained

WASM-4 requires specific flags when compiling C:

- `--target=wasm32`: Target WebAssembly 32-bit
- `-mbulk-memory`: Enable bulk memory operations
- `-nostdlib`: Don't link standard library (WASM-4 provides its own)
- `-Wl,--no-entry`: No main entry point (WASM-4 calls your update function)
- `-Wl,--export-dynamic`: Export all functions
- `-Wl,--import-undefined`: Allow undefined imports (WASM-4 runtime functions)

## See Also

- [WASM-4 Documentation](https://wasm4.org/docs/)
- [WASM-4 C API Reference](https://wasm4.org/docs/reference/runtime)
