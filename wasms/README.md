# ICDex Wasm

- ICDexPair Wasm
    - Module hash: 08c054ec4ee768a88b51bf437e0d917464aec84ed8eb2017098aca770b7f93ca
    - Version: 0.12.37
    - DFX version: 0.15.3 (moc 0.10.3)
    - Build: {
        "args": "--compacting-gc"
    }
    - Wasm tool: ic-wasm 0.7.0, Command `$ ic-wasm ICDexPair.wasm -o ICDexPair.wasm metadata candid:service -f Pair.did -v public`

- ICDexMaker Wasm
    - Module hash: 9d1fff5a63acdeeabd0e0f216ea1b520745fd644f7328390a571b53d1472e7da
    - Version: 0.5.2
    - DFX version: 0.15.3 (moc 0.10.3)
    - Build: {
        "args": "--compacting-gc", 
        "optimize": "size"
    }


ic-wasm tool: https://github.com/dfinity/ic-wasm
