# ICDex Wasm

- ICDexPair Wasm
    - Module hash: 1f634d3420ea8bd1e638d35646e07182064902802bdf23ed5e353e05e1a3bfbb
    - Version: 0.12.33
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
