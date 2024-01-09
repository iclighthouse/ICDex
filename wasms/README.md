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
    - Module hash: 9b4b8be30837d2391adc177ea5f02e53e28f6c593df08a55e5a4dedb0e3c7d75
    - Version: 0.5.0
    - DFX version: 0.15.3 (moc 0.10.3)
    - Build: {
        "args": "--compacting-gc", 
        "optimize": "size"
    }


ic-wasm tool: https://github.com/dfinity/ic-wasm
