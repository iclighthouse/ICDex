# ICDex Wasm

- ICDexPair Wasm
    - Module hash: 24d268174856dbdba53fb6538d2ec21baf04df263e8805874bacc3d5d26e4b95
    - Version: 0.12.30
    - DFX version: 0.15.3 (moc 0.10.3)
    - Build: {
        "args": "--compacting-gc"
    }
    - Wasm tool: ic-wasm 0.7.0, Command `$ ic-wasm ICDexPair.wasm -o ICDexPair.wasm metadata candid:service -f Pair.did -v public`

- ICDexMaker Wasm
    - Module hash: 701d2954ec573abc012a3b90d7e221cfb10a9fd3b3f828447d78a99afa75d133
    - Version: 0.5.1
    - DFX version: 0.15.3 (moc 0.10.3)
    - Build: {
        "args": "--compacting-gc", 
        "optimize": "size"
    }


ic-wasm tool: https://github.com/dfinity/ic-wasm
