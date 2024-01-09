# ICDex Wasm

- ICDexPair Wasm
    - Module hash: 77695e3f1dc9f021048671fd00d56d44bd74d5ad150907800d48891ca9bde92c
    - Version: 0.12.32
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
