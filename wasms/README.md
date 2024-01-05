# ICDex Wasm

- ICDexPair Wasm
    - Module hash: 30d75d7b62b533bf5e7862c0039d1fe9b96106ad93712d3ab20352627bd79064
    - Version: 0.12.22
    - DFX version: 0.15.0 (moc 0.9.7)
    - Build: {
        "args": "--compacting-gc"
    }
    - Wasm tool: ic-wasm 0.7.0, Command `$ ic-wasm ICDexPair.wasm -o ICDexPair.wasm metadata candid:service -f Pair.did -v public`

- ICDexMaker Wasm
    - Module hash: 17b648f8831c13646747cc25f5b27bec3ddfe5eda05a932c97594f5ce945f9ba
    - Version: 0.4.9
    - DFX version: 0.15.0 (moc 0.9.7)
    - Build: {
        "args": "--compacting-gc", 
        "optimize": "size"
    }


ic-wasm tool: https://github.com/dfinity/ic-wasm
