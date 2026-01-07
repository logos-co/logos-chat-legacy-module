# logos-chat-module

## How to Build

### Using Nix (Recommended)

#### Build Complete Module (Library + Headers)

```bash
# Build everything (default)
nix build

# Or explicitly
nix build '.#default'
```

The result will include:
- `/lib/chat_plugin.dylib` (or `.so` on Linux) - The Chat module plugin
- `/include/` - Generated headers for the module API

#### Build Individual Components

```bash
# Build only the library (plugin)
nix build '.#lib'

# Build only the generated headers
nix build '.#logos-chat-module-include'
```

#### Development Shell

```bash
# Enter development shell with all dependencies
nix develop
```

**Note:** In zsh, you need to quote the target (e.g., `'.#default'`) to prevent glob expansion.

If you don't have flakes enabled globally, add experimental flags:

```bash
nix build --extra-experimental-features 'nix-command flakes'
```

The compiled artifacts can be found at `result/`

#### Modular Architecture

The nix build system is organized into modular files in the `/nix` directory:
- `nix/default.nix` - Common configuration (dependencies, flags, metadata)
- `nix/lib.nix` - Module plugin compilation
- `nix/include.nix` - Header generation using logos-cpp-generator

## Output Structure

When built with Nix:

```
result/
├── lib/
│   └── chat_plugin.dylib        # Logos chat module plugin
└── include/
    ├── chat_api.h       # Generated SDK header
    ├── chat_api.cpp              # Generated SDK code
```

### Requirements

#### Build Tools
- CMake (3.14 or later)
- Ninja build system
- pkg-config

#### Dependencies
- Qt6 (qtbase)
- Qt6 Remote Objects (qtremoteobjects)
- logos-liblogos
- logos-cpp-sdk (for header generation)
- zstd
- krb5
- protobuf
- abseil-cpp
