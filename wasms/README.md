# ICDex Wasm

- ICDexPair Wasm
    - Module hash: 93665f829a34b399e96eddd3dc56aa98ad4e8b19a2613f076a6fa1fa91d9a53e
    - Version: 0.12.36
    - DFX version: 0.15.3 (moc 0.10.3)
    - Build: {
        "args": "--compacting-gc"
    }
    - Wasm tool: ic-wasm 0.7.0, Command `$ ic-wasm ICDexPair.wasm -o ICDexPair.wasm metadata candid:service -f Pair.did -v public`

- ICDexMaker Wasm
    - Module hash: 9d1fff5a63acdeeabd0e0f216ea1b520745fd644f7328390a571b53d1472e7da
    - Version: 0.5.2
    - DFX version: 0.15.3 (moc 0.10.3)
    - Build: {
        "args": "--compacting-gc", 
        "optimize": "size"
    }


ic-wasm tool: https://github.com/dfinity/ic-wasm
