# ICDex Wasm

- ICDexPair Wasm
    - Module hash: 3dda93e2c1af4ee5b32c85d830bf0f1e7fc3671d430cc28a7fff06efa486c5e0
    - Version: 0.12.15
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
