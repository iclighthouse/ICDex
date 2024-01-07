# ICDex Wasm

- ICDexPair Wasm
    - Module hash: 06daa8d1cd71b7a6ddc87afb0544181de4b3f4665415b53e85948c52c519578b
    - Version: 0.12.24
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
