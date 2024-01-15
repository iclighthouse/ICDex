# ICDex Wasm

- ICDexPair Wasm
    - Module hash: 53beec3e608afc409db26498980942a08784c208df6794a1ca2983d884c01e3f
    - Version: 0.12.43
    - DFX version: 0.15.3 (moc 0.10.3)
    - Build: {
        "args": "--incremental-gc"
    }
    - Wasm tool: ic-wasm 0.7.0, Command `$ ic-wasm ICDexPair.wasm -o ICDexPair.wasm metadata candid:service -f Pair.did -v public`

- ICDexMaker Wasm
    - Module hash: 895821bdabe71b54e990efc26837a60a3e5934a29144e6cbe5113a8feea58966
    - Version: 0.5.5
    - DFX version: 0.15.3 (moc 0.10.3)
    - Build: {
        "args": "--compacting-gc", 
        "optimize": "size"
    }


ic-wasm tool: https://github.com/dfinity/ic-wasm
