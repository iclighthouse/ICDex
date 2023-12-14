# ICDex Wasm

- ICDexPair Wasm
    - Module hash: f20b92d422684de454a425a6c18a5dcf7df6ccb70c99bcbad92713cb7307b08f
    - Version: 0.12.12
    - DFX version: 0.15.0 (moc 0.9.7)
    - Build: {
        "args": "--compacting-gc"
    }
    - Wasm tool: ic-wasm 0.7.0, Command `$ ic-wasm ICDexPair.wasm -o ICDexPair.wasm metadata candid:service -f Pair.did -v public`

- ICDexMaker Wasm
    - Module hash: 26d9b6bd9fec7194d0e47327b0bba0da7ae72d8db90f446f1c3f6805bcc53158
    - Version: 0.4.0
    - DFX version: 0.15.0 (moc 0.9.7)
    - Build: {
        "args": "--compacting-gc", 
        "optimize": "size"
    }


ic-wasm tool: https://github.com/dfinity/ic-wasm
