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
    - Module hash: aaa28bbea4ab1e18b69bef77b292867bb02d67bc59c02ee15602db004792bc73
    - Version: 0.4.5
    - DFX version: 0.15.0 (moc 0.9.7)
    - Build: {
        "args": "--compacting-gc", 
        "optimize": "size"
    }


ic-wasm tool: https://github.com/dfinity/ic-wasm