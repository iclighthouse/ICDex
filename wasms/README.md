# ICDex Wasm

- ICDexPair Wasm
    - Module hash: 2cbaf623ced768faedeea4a5ce26cce93bf067bf38200d84157b8faa28424b23
    - Version: 0.12.25
    - DFX version: 0.15.0 (moc 0.9.7)
    - Build: {
        "args": "--compacting-gc"
    }
    - Wasm tool: ic-wasm 0.7.0, Command `$ ic-wasm ICDexPair.wasm -o ICDexPair.wasm metadata candid:service -f Pair.did -v public`

- ICDexMaker Wasm
    - Module hash: e5eebe5356b0ac132abcb6965644402d72756460d55c6d94ff86ab53affd95d3
    - Version: 0.4.10
    - DFX version: 0.15.0 (moc 0.9.7)
    - Build: {
        "args": "--compacting-gc", 
        "optimize": "size"
    }


ic-wasm tool: https://github.com/dfinity/ic-wasm
