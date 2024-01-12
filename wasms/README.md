# ICDex Wasm

- ICDexPair Wasm
    - Module hash: c1aa419c7096f9fff1bafc483bfbaa16050783c1448cba5449a5253bebd2d1ce
    - Version: 0.12.39
    - DFX version: 0.15.3 (moc 0.10.3)
    - Build: {
        "args": "--incremental-gc"
    }
    - Wasm tool: ic-wasm 0.7.0, Command `$ ic-wasm ICDexPair.wasm -o ICDexPair.wasm metadata candid:service -f Pair.did -v public`

- ICDexMaker Wasm
    - Module hash: 33772f7050d4f6047077150fd83293df53b349c6745c5104d54def7f98d2a4b1
    - Version: 0.5.4
    - DFX version: 0.15.3 (moc 0.10.3)
    - Build: {
        "args": "--compacting-gc", 
        "optimize": "size"
    }


ic-wasm tool: https://github.com/dfinity/ic-wasm
