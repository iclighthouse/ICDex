# ICDex Wasm

- ICDexPair Wasm
    - Module hash: ec97e995083041b68a335ddc8b19530f8d70704fc849c35d492eab924cfbc5ba
    - Version: 0.12.17
    - DFX version: 0.15.0 (moc 0.9.7)
    - Build: {
        "args": "--compacting-gc"
    }
    - Wasm tool: ic-wasm 0.7.0, Command `$ ic-wasm ICDexPair.wasm -o ICDexPair.wasm metadata candid:service -f Pair.did -v public`

- ICDexMaker Wasm
    - Module hash: 03b5fe502a8a319c4b1280f8f5b525cb869d289fc0989859f0796b5b774a98ac
    - Version: 0.4.2
    - DFX version: 0.15.0 (moc 0.9.7)
    - Build: {
        "args": "--compacting-gc", 
        "optimize": "size"
    }


ic-wasm tool: https://github.com/dfinity/ic-wasm
