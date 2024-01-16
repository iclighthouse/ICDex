# ICDex Wasm

- ICDexPair Wasm
    - Module hash: 006782996688e802ae4b8f5d6ea228b370b778855e52d10051a8598b5881405f
    - Version: 0.12.45
    - DFX version: 0.15.3 (moc 0.10.3)
    - Build: {
        "args": "--incremental-gc"
    }
    - Wasm tool: ic-wasm 0.7.0, Command `$ ic-wasm ICDexPair.wasm -o ICDexPair.wasm metadata candid:service -f Pair.did -v public`

- ICDexMaker Wasm
    - Module hash: 66eb5eab4513cacc85288924f25d860ca7ce46918a456663433b806ddd694ae3
    - Version: 0.5.6
    - DFX version: 0.15.3 (moc 0.10.3)
    - Build: {
        "args": "--compacting-gc", 
        "optimize": "size"
    }


ic-wasm tool: https://github.com/dfinity/ic-wasm
