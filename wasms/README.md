# ICDex Wasm

- ICDexPair Wasm
    - Module hash: 5e0785a0607aa7d6ff32c3cee4f3d50b15aa0ac74cf6b0110a1c664c0fb803ae
    - Version: 0.12.37
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
