# ICDex Wasm

- ICDexPair Wasm
    - Module hash: cea367dbe73892fd163b964d4a472f129f48c50d70bb903251944731f2171571
    - Version: 0.12.16
    - DFX version: 0.15.0 (moc 0.9.7)
    - Build: {
        "args": "--compacting-gc"
    }
    - Wasm tool: ic-wasm 0.7.0, Command `$ ic-wasm ICDexPair.wasm -o ICDexPair.wasm metadata candid:service -f Pair.did -v public`

- ICDexMaker Wasm
    - Module hash: eead27b593980b26dace0e6d7fa3fc601686be8f5cd1fd90441eef9808e45d49
    - Version: 0.4.1
    - DFX version: 0.15.0 (moc 0.9.7)
    - Build: {
        "args": "--compacting-gc", 
        "optimize": "size"
    }


ic-wasm tool: https://github.com/dfinity/ic-wasm
