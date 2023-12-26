# ICDex Wasm

- ICDexPair Wasm
    - Module hash: 9cebe039e346ebe9f72d2d85fc68bff9c2accc77ffa5002fad00bde6bcf9f7df
    - Version: 0.12.19
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
