# ICDex Wasm

- ICDexPair Wasm
    - Module hash: f0f70778a3db8e891c6ab94b35f1554a826bbe623d63f6c0a8d3da81a31e3d92
    - Version: 0.12.17
    - DFX version: 0.15.0 (moc 0.9.7)
    - Build: {
        "args": "--compacting-gc"
    }
    - Wasm tool: ic-wasm 0.7.0, Command `$ ic-wasm ICDexPair.wasm -o ICDexPair.wasm metadata candid:service -f Pair.did -v public`

- ICDexMaker Wasm
    - Module hash: 4d2a8998167ebca2ca0b4eaf6f9d2c4f0c245b529436aa47f108069815646650
    - Version: 0.4.7
    - DFX version: 0.15.0 (moc 0.9.7)
    - Build: {
        "args": "--compacting-gc", 
        "optimize": "size"
    }


ic-wasm tool: https://github.com/dfinity/ic-wasm
