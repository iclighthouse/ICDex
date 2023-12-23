# ICDex Wasm

- ICDexPair Wasm
    - Module hash: 2d4e38526b7374381257b3f1f41eacfd60a9deff3b4c1a7043cd830a4b16ed3b
    - Version: 0.12.18
    - DFX version: 0.15.0 (moc 0.9.7)
    - Build: {
        "args": "--compacting-gc"
    }
    - Wasm tool: ic-wasm 0.7.0, Command `$ ic-wasm ICDexPair.wasm -o ICDexPair.wasm metadata candid:service -f Pair.did -v public`

- ICDexMaker Wasm
    - Module hash: aba1cf379c6f697ada348ef78dcb56ee17e43c8452f367aaf359fd4aafa58cdd
    - Version: 0.4.8
    - DFX version: 0.15.0 (moc 0.9.7)
    - Build: {
        "args": "--compacting-gc", 
        "optimize": "size"
    }


ic-wasm tool: https://github.com/dfinity/ic-wasm
