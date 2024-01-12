# ICDex Wasm

- ICDexPair Wasm
    - Module hash: e33ffc62f93107ec624e8ef9ad93135c5f6e64df0eaf300c1bd32268458c8557
    - Version: 0.12.38
    - DFX version: 0.15.3 (moc 0.10.3)
    - Build: {
        "args": "--incremental-gc"
    }
    - Wasm tool: ic-wasm 0.7.0, Command `$ ic-wasm ICDexPair.wasm -o ICDexPair.wasm metadata candid:service -f Pair.did -v public`

- ICDexMaker Wasm
    - Module hash: 96ce5cf5d8ad4a5f7a631879384e1136c801999a2e5169738234ec1f14113fd1
    - Version: 0.5.3
    - DFX version: 0.15.3 (moc 0.10.3)
    - Build: {
        "args": "--compacting-gc", 
        "optimize": "size"
    }


ic-wasm tool: https://github.com/dfinity/ic-wasm
