# ICDex Wasm

- ICDexPair Wasm
    - Module hash: 3691ef46a92cde1b5a794f815185b43ef8ee54bda04ff5189b62b3617edf315d
    - Version: 0.12.20
    - DFX version: 0.15.0 (moc 0.9.7)
    - Build: {
        "args": "--compacting-gc"
    }
    - Wasm tool: ic-wasm 0.7.0, Command `$ ic-wasm ICDexPair.wasm -o ICDexPair.wasm metadata candid:service -f Pair.did -v public`

- ICDexMaker Wasm
    - Module hash: ac94ebcf6f62002eb161796a37ce190de0819039507c05660ea93881a7774966
    - Version: 0.4.8
    - DFX version: 0.15.0 (moc 0.9.7)
    - Build: {
        "args": "--compacting-gc", 
        "optimize": "size"
    }


ic-wasm tool: https://github.com/dfinity/ic-wasm
