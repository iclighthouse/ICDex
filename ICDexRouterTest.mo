/**
 * Module     : ICDexRouter.mo
 * Author     : ICLighthouse Team
 * Stability  : Experimental
 * Github     : https://github.com/iclighthouse/
 */
import Array "mo:base/Array";
import Binary "mo:icl/Binary";
import Blob "mo:base/Blob";
import Cycles "mo:base/ExperimentalCycles";
import DRC20 "mo:icl/DRC20";
//import DIP20 "mo:icl/DIP20";
import ICRC1 "mo:icl/ICRC1";
import DRC207 "mo:icl/DRC207";
import Float "mo:base/Float";
import Hash "mo:base/Hash";
import Hex "mo:icl/Hex";
import IC "mo:icl/IC";
import ICDexTypes "mo:icl/ICDexTypes";
import Int "mo:base/Int";
import Int64 "mo:base/Int64";
import Iter "mo:base/Iter";
import Nat "mo:base/Nat";
import Nat8 "mo:base/Nat8";
import Nat32 "mo:base/Nat32";
import Nat64 "mo:base/Nat64";
import Option "mo:base/Option";
import Principal "mo:base/Principal";
import T "mo:icl/ICDexRouter";
import Text "mo:base/Text";
import Time "mo:base/Time";
import Tools "mo:icl/Tools";
import List "mo:base/List";
import Trie "mo:base/Trie";
import Router "mo:icl/DexRouter";
import SHA224 "mo:sha224/SHA224";
import CRC32 "mo:icl/CRC32";
import DRC205 "mo:icl/DRC205";
import ICDexPrivate "./lib/ICDexPrivate";
import Ledger "mo:icl/Ledger";
import ICTokens "mo:icl/ICTokens";
import ERC721 "mo:icl/ERC721";
import SagaTM "./ICTC/SagaTM";
import Backup "./lib/ICDexBackupTypes";
import Timer "mo:base/Timer";
import Error "mo:base/Error";
import CF "mo:icl/CF";
import CyclesMonitor "mo:icl/CyclesMonitor";
import Maker "mo:icl/ICDexMaker";

shared(installMsg) actor class ICDexRouter() = this {
    type Txid = T.Txid;  //Blob
    type AccountId = T.AccountId;
    type Address = T.Address;
    type Nonce = T.Nonce;
    type DexName = T.DexName;
    type TokenStd = T.TokenStd;
    type TokenSymbol = T.TokenSymbol;
    type TokenInfo = T.TokenInfo;
    type PairCanister = T.PairCanister;
    type PairRequest = T.PairRequest;
    type SwapPair = T.SwapPair;
    type TrieList<K, V> = T.TrieList<K, V>;
    type InstallMode = {#reinstall; #upgrade; #install};
    type Timestamp = Nat;

    private var icdex_debug : Bool = true; /*config*/
    private let version_: Text = "0.11.0";
    private var ICP_FEE: Nat64 = 10000; // e8s 
    private let ic: IC.Self = actor("aaaaa-aa");
    private let blackhole: Principal = Principal.fromText("7hdtw-jqaaa-aaaak-aaccq-cai");
    private var cfAccountId: AccountId = Blob.fromArray([]);
    private stable var icRouter: Text = "i2ied-uqaaa-aaaar-qaaza-cai"; // pwokq-miaaa-aaaak-act6a-cai
    if (icdex_debug){
        icRouter := "pwokq-miaaa-aaaak-act6a-cai";
    };
    private stable var sysToken: Principal = Principal.fromText("5573k-xaaaa-aaaak-aacnq-cai"); // Test: 7jf3t-siaaa-aaaak-aezna-cai
    private stable var sysTokenFee: Nat = 1000000; // 0.01 ICL
    private stable var creatingPairFee: Nat = 500000000000; // 5000 ICL
    private stable var creatingMakerFee: Nat = 5000000000; // 50 ICL
    private stable var pause: Bool = false; 
    private stable var owner: Principal = installMsg.caller;
    private stable var pairs: Trie.Trie<PairCanister, SwapPair> = Trie.empty(); 
    // private stable var topups: Trie.Trie<PairCanister, Nat> = Trie.empty(); 
    private stable var wasm: [Nat8] = [];
    private stable var wasm_preVersion: [Nat8] = [];
    private stable var wasmVersion: Text = "";
    private stable var IDOPairs = List.nil<Principal>();
    // ICDexMaker
    private stable var maker_wasm: [Nat8] = [];
    private stable var maker_wasm_preVersion: [Nat8] = [];
    private stable var maker_wasmVersion: Text = "";
    private stable var maker_publicCanisters: Trie.Trie<PairCanister, [(maker: Principal, creator: AccountId)]> = Trie.empty(); 
    private stable var maker_privateCanisters: Trie.Trie<PairCanister, [(maker: Principal, creator: AccountId)]> = Trie.empty(); 
    // Monitor
    private stable var cyclesMonitor: CyclesMonitor.MonitoredCanisters = Trie.empty(); 
    private stable var lastMonitorTime: Nat = 0;
    private stable var hotPairs : List.List<Principal> = List.nil();
    private let canisterCyclesInit : Nat = if (icdex_debug) {200_000_000_000} else {2_000_000_000_000}; /*config*/
    private let pairMaxMemory: Nat = 2*1000*1000*1000; // 2G

    private func keyp(t: Principal) : Trie.Key<Principal> { return { key = t; hash = Principal.hash(t) }; };
    private func keyn(t: Nat) : Trie.Key<Nat> { return { key = t; hash = Tools.natHash(t) }; };
    private func keyb(t: Blob) : Trie.Key<Blob> { return { key = t; hash = Blob.hash(t) }; };
    private func keyt(t: Text) : Trie.Key<Text> { return { key = t; hash = Text.hash(t) }; };
    private func trieItems<K, V>(_trie: Trie.Trie<K,V>, _page: Nat, _size: Nat) : TrieList<K, V> {
        let length = Trie.size(_trie);
        if (_page < 1 or _size < 1){
            return {data = []; totalPage = 0; total = length; };
        };
        let offset = Nat.sub(_page, 1) * _size;
        var totalPage: Nat = length / _size;
        if (totalPage * _size < length) { totalPage += 1; };
        if (offset >= length){
            return {data = []; totalPage = totalPage; total = length; };
        };
        let end: Nat = offset + Nat.sub(_size, 1);
        var i: Nat = 0;
        var res: [(K, V)] = [];
        for ((k,v) in Trie.iter<K, V>(_trie)){
            if (i >= offset and i <= end){
                res := Tools.arrayAppend(res, [(k,v)]);
            };
            i += 1;
        };
        return {data = res; totalPage = totalPage; total = length; };
    };
    
    /* 
    * Local Functions
    */
    private func _now() : Timestamp{
        return Int.abs(Time.now() / 1000000000);
    };
    private func _onlyOwner(_caller: Principal) : Bool { 
        return _caller == owner;
    };  // assert(_onlyOwner(msg.caller));
    private func _notPaused() : Bool { 
        return not(pause);
    };
    private func _toSaBlob(_sa: ?ICDexTypes.Sa) : ?Blob{
        switch(_sa){
            case(?(sa)){ return ?Blob.fromArray(sa); };
            case(_){ return null; };
        }
    };
    private func _toSaNat8(_sa: ?Blob) : ?[Nat8]{
        switch(_sa){
            case(?(sa)){ return ?Blob.toArray(sa); };
            case(_){ return null; };
        }
    };
    private func _accountIdToHex(_a: AccountId) : Text{
        return Hex.encode(Blob.toArray(_a));
    };
    private func _getAccountId(_address: Address): AccountId{
        switch (Tools.accountHexToAccountBlob(_address)){
            case(?(a)){
                return a;
            };
            case(_){
                var p = Principal.fromText(_address);
                var a = Tools.principalToAccountBlob(p, null);
                return a;
                // switch(Tools.accountDecode(Principal.toBlob(p))){
                //     case(#ICRC1Account(account)){
                //         switch(account.subaccount){
                //             case(?(sa)){ return Tools.principalToAccountBlob(account.owner, ?Blob.toArray(sa)); };
                //             case(_){ return Tools.principalToAccountBlob(account.owner, null); };
                //         };
                //     };
                //     case(#AccountId(account)){ return account; };
                //     case(#Other(account)){ return account; };
                // };
            };
        };
    }; 
    // private func _drc20TransferFrom(_token: Principal, _from: AccountId, _to: AccountId, _value: Nat) : async Bool{
    //     let token0: DRC20.Self = actor(Principal.toText(_token));
    //     let res = await token0.drc20_transferFrom(_accountIdToHex(_from), _accountIdToHex(_to), _value, null,null,null);
    //     switch(res){
    //         case(#ok(txid)){ return true; };
    //         case(#err(e)){ return false; };
    //     };
    // };
    private func _drc20Transfer(_token: Principal, _to: AccountId, _value: Nat) : async Bool{
        let token0: DRC20.Self = actor(Principal.toText(_token));
        let res = await token0.drc20_transfer(_accountIdToHex(_to), _value, null,null,null);
        switch(res){
            case(#ok(txid)){ return true; };
            case(#err(e)){ return false; };
        };
    };
    private func _syncFee(_pair: SwapPair) : async (){
        let swap: ICDexTypes.Self = actor(Principal.toText(_pair.canisterId));
        let feeRate = (await swap.feeStatus()).feeRate;
        pairs := Trie.put(pairs, keyp(_pair.canisterId), Principal.equal, {
            token0 = _pair.token0; 
            token1 = _pair.token1; 
            dexName = _pair.dexName; 
            canisterId = _pair.canisterId; 
            feeRate = feeRate; 
        }).0;
    };

    private func _adjustPair(_pair: PairRequest) : (pair: PairRequest){
        var value0: Nat64 = 0;
        var value1: Nat64 = 0;
        if (_pair.token0.1 == "ICP") { value0 := 1; };
        if (_pair.token1.1 == "ICP") { value1 := 1; };
        assert(value0 != value1);
        if (value0 < value1){
            return _pair;
        }else{
            return {token0 = _pair.token1; token1 = _pair.token0; dexName = _pair.dexName; };
        };
    };
    private func _adjustPair2(_pair: SwapPair) : (pair: SwapPair){
        var value0: Nat64 = 0;
        var value1: Nat64 = 0;
        if (_pair.token0.1 == "ICP") { value0 := 1; };
        if (_pair.token1.1 == "ICP") { value1 := 1; };
        assert(value0 != value1);
        if (value0 < value1){
            return _pair;
        }else{
            return {token0 = _pair.token1; token1 = _pair.token0; dexName = _pair.dexName; canisterId = _pair.canisterId; feeRate = _pair.feeRate; };
        };
    };
    private func _isExisted(_pair: Principal) : Bool{
        return Option.isSome(Trie.find(pairs, keyp(_pair), Principal.equal));
    };
    private func _isExistedByToken(_token0: Principal, _token1: Principal) : Bool{
        let temp = Trie.filter(pairs, func (k: PairCanister, v: SwapPair): Bool{ v.token0.0 == _token0 and v.token1.0 == _token1 });
        return Trie.size(temp) > 0;
    };
    private func _getPairsByToken(_token0: Principal, _token1: ?Principal) : [(PairCanister, SwapPair)]{
        var trie = pairs;
        trie := Trie.filter(trie, func (k:PairCanister, v:SwapPair):Bool{ 
            switch(_token1){
                case(?(token1)){ return (v.token0.0 == _token0 and v.token1.0 == token1) or (v.token1.0 == _token0 and v.token0.0 == token1) };
                case(_){ return v.token0.0 == _token0 or v.token1.0 == _token0 };
            };
        });
        return Trie.toArray<PairCanister, SwapPair, (PairCanister, SwapPair)>(trie, func (k:PairCanister, v:SwapPair):
        (PairCanister, SwapPair){
            return (k, v);
        });
    };
    
    private func _hexToBytes(_hex: Text) : [Nat8]{
        switch(Hex.decode(_hex)){
            case(#ok(v)){ return v };
            case(#err(e)){ return [] };
        };
    };
    // private func _generateArgs(_token0: Principal, _token1: Principal, _unitSize: Nat64, _pairName: Text) : [Nat8]{
    //     //let unitSize = Nat64.fromNat(10 ** Nat.min(Nat.sub(Nat.max(Nat8.toNat(_decimals), 1), 1), 12)); // max 1000000000000
    //     let unitSize = _unitSize;
    //     var args: [Nat8] = []; // arg : [Nat8];   owner / name / token0 / token1 / unitSize
    //     //4449444c026c05b3b0dac30301cbe4fdc7047197ae9c8f096898ae9c8f0968e5d2a0fb0f786e68010001 011d 6eeb31de7e19c1ed16db121ef00c3d03914de4d79637f1d6860901b202 07 5454542f494350 010a 00000000014003780101 010a 00000000000000020101 40420f0000000000
    //     //4449444c026c05b3b0dac30301cbe4fdc7047197ae9c8f096898ae9c8f0968e5d2a0fb0f786e68010001 010a 00000000000000020101 07 5454542f494350 010a 00000000000000020101 010a 00000000000000020101 40420f0000000000
    //     args := _hexToBytes("4449444c026c05b3b0dac30301cbe4fdc7047197ae9c8f096898ae9c8f0968e5d2a0fb0f786e68010001010a");
    //     args := Tools.arrayAppend(args, Blob.toArray(Principal.toBlob(Principal.fromActor(this))));
    //     args := Tools.arrayAppend(args, [Nat8.fromNat(_pairName.size())]);
    //     args := Tools.arrayAppend(args, Blob.toArray(Text.encodeUtf8(_pairName)));
    //     args := Tools.arrayAppend(args, _hexToBytes("010a")); // 01011d
    //     args := Tools.arrayAppend(args, Blob.toArray(Principal.toBlob(_token0)));
    //     args := Tools.arrayAppend(args, _hexToBytes("010a")); // 01011d
    //     args := Tools.arrayAppend(args, Blob.toArray(Principal.toBlob(_token1)));
    //     args := Tools.arrayAppend(args, Binary.LittleEndian.fromNat64(unitSize));
    //     return args;
    // };
    private func _generateArg(_token0: Principal, _token1: Principal, _unitSize: Nat64, _pairName: Text) : [Nat8]{
        let arg : ICDexTypes.InitArgs = {
            name = _pairName;
            token0 = _token0;
            token1 = _token1;
            unitSize = _unitSize;
            owner = ?Principal.fromActor(this);
        };
        return Blob.toArray(to_candid(arg));
    };
    private func _testToken(_canisterId: Principal) : async {symbol: Text; decimals: Nat8; std: ICDexTypes.TokenStd}{
        if (_canisterId == Principal.fromText("ryjl3-tyaaa-aaaaa-aaaba-cai")){
            return {
                symbol = "ICP";
                decimals = 8;
                std = #icp;
            };
        }else{
            try{
                let token: DRC20.Self = actor(Principal.toText(_canisterId));
                return {
                    symbol = await token.drc20_symbol();
                    decimals = await token.drc20_decimals();
                    std = #drc20;
                };
            } catch(e){
                try{
                    let token: ICRC1.Self = actor(Principal.toText(_canisterId));
                    return {
                        symbol = await token.icrc1_symbol();
                        decimals = await token.icrc1_decimals();
                        std = #icrc1;
                    };
                } catch(e){
                    throw Error.reject("Error: "# Error.message(e)); 
                };
            };
        };
    };
    private func _create(_token0: Principal, _token1: Principal, _unitSize: ?Nat64, _initCycles: ?Nat): async* (canister: PairCanister){
        assert(wasm.size() > 0);
        var token0Principal = _token0;
        var token0Std: ICDexTypes.TokenStd = #drc20;
        var token0Symbol: Text = "";
        var token0Decimals: Nat8 = 0;
        var token1Principal = _token1;
        var token1Std: ICDexTypes.TokenStd = #icp;
        var token1Symbol: Text = "ICP";
        var token1Decimals: Nat8 = 0;
        var swapName: Text = "";
        if (token0Principal == Principal.fromText("ryjl3-tyaaa-aaaaa-aaaba-cai")){
            token0Symbol := "ICP";
            token0Decimals := 8;
            token0Std := #icp;
        }else{
            let tokenInfo = await _testToken(token0Principal); //{symbol: Text; decimals: Nat8; std: ICDexTypes.TokenStd}
            token0Symbol := tokenInfo.symbol;
            token0Decimals := tokenInfo.decimals;
            token0Std := tokenInfo.std;
            assert(token0Std == #drc20 or token0Std == #icrc1);
        };
        if (token1Principal == Principal.fromText("ryjl3-tyaaa-aaaaa-aaaba-cai")){
            token1Symbol := "ICP";
            token1Decimals := 8;
            token1Std := #icp;
        }else{
            let tokenInfo = await _testToken(token1Principal); //{symbol: Text; decimals: Nat8; std: ICDexTypes.TokenStd}
            token1Symbol := tokenInfo.symbol;
            token1Decimals := tokenInfo.decimals;
            token1Std := tokenInfo.std;
            assert(token1Std == #drc20 or token1Std == #icrc1);
        };
        swapName := "icdex:" # token0Symbol # "/" # token1Symbol;

        // create
        let addCycles : Nat = Option.get(_initCycles, canisterCyclesInit);
        Cycles.add(addCycles);
        let canister = await ic.create_canister({ settings = null });
        let pairCanister = canister.canister_id;
        var unitSize = Nat64.fromNat(10 ** Nat.min(Nat.sub(Nat.max(Nat8.toNat(token0Decimals), 1), 1), 12)); // max 1000000000000
        switch (_unitSize){
            case(?(value)){ if (value > 0) { unitSize := value } };
            case(_){};
        };
        let args: [Nat8] = _generateArg(token0Principal, token1Principal, unitSize, swapName);
        await ic.install_code({
            arg : [Nat8] = args;
            wasm_module = wasm;
            mode = #install; // #reinstall; #upgrade; #install
            canister_id = pairCanister;
        });
        let pairActor: ICDexPrivate.Self = actor(Principal.toText(pairCanister));
        ignore await pairActor.setPause(true, null);
        let pair: SwapPair = {
            token0: TokenInfo = (token0Principal, token0Symbol, token0Std); 
            token1: TokenInfo = (token1Principal, token1Symbol, token1Std); 
            dexName: DexName = "icdex"; 
            canisterId: PairCanister = pairCanister;
            feeRate: Float = 0.005; //  0.5%
        };
        pairs := Trie.put(pairs, keyp(pairCanister), Principal.equal, pair).0;
        var controllers: [Principal] = [pairCanister, blackhole, Principal.fromActor(this)];
        if (icdex_debug){
            controllers := [pairCanister, blackhole, Principal.fromActor(this), owner];
        };
        let settings = await ic.update_settings({
            canister_id = pairCanister; 
            settings={ 
                compute_allocation = null;
                controllers = ?controllers; 
                freezing_threshold = null;
                memory_allocation = null;
            };
        });
        await pairActor.init();
        await pairActor.timerStart(900);
        let router: Router.Self = actor(icRouter);
        await router.putByDex(
            (token0Principal, token0Symbol, token0Std), 
            (token1Principal, token1Symbol, token1Std), 
            pairCanister);
        cyclesMonitor := await* CyclesMonitor.put(cyclesMonitor, pairCanister);
        return pairCanister;
    };
    private func _update(_pair: Principal, _wasm: [Nat8], _mode: InstallMode) : async* (canister: ?PairCanister){
        switch(Trie.get(pairs, keyp(_pair), Principal.equal)){
            case(?(pair)){
                let pairActor: ICDexPrivate.Self = actor(Principal.toText(_pair));
                //await pairActor.timerStop();
                var token0Principal = pair.token0.0;
                var token0Std = pair.token0.2;
                var token0Symbol = pair.token0.1;
                var token0Decimals: Nat8 = 0;
                var token1Principal = pair.token1.0;
                var token1Std = pair.token1.2;
                var token1Symbol = pair.token1.1;
                var token1Decimals: Nat8 = 0;
                var swapName = pair.dexName # ":" # token0Symbol # "/" # token1Symbol;
                var pairCanister = pair.canisterId;
                if (token0Principal == Principal.fromText("ryjl3-tyaaa-aaaaa-aaaba-cai")){
                    token0Symbol := "ICP";
                    token0Decimals := 8;
                    token0Std := #icp;
                }else{
                    let tokenInfo = await _testToken(token0Principal); //{symbol: Text; decimals: Nat8; std: ICDexTypes.TokenStd}
                    token0Symbol := tokenInfo.symbol;
                    token0Decimals := tokenInfo.decimals;
                    token0Std := tokenInfo.std;
                };
                if (token1Principal == Principal.fromText("ryjl3-tyaaa-aaaaa-aaaba-cai")){
                    token1Symbol := "ICP";
                    token1Decimals := 8;
                    token1Std := #icp;
                }else{
                    let tokenInfo = await _testToken(token1Principal); //{symbol: Text; decimals: Nat8; std: ICDexTypes.TokenStd}
                    token1Symbol := tokenInfo.symbol;
                    token1Decimals := tokenInfo.decimals;
                    token1Std := tokenInfo.std;
                };
                swapName := pair.dexName # ":" # token0Symbol # "/" # token1Symbol;
                Cycles.add(canisterCyclesInit);
                var unitSize = Nat64.fromNat(10 ** Nat.min(Nat.sub(Nat.max(Nat8.toNat(token0Decimals), 1), 1), 12)); // max 1000000000000
                //let pairActor: ICDexPrivate.Self = actor(Principal.toText(pairCanister));
                try{
                    let pairSetting = await pairActor.getConfig();
                    unitSize := Nat64.fromNat(pairSetting.UNIT_SIZE);
                }catch(e){
                    let pairActor: ICDexPrivate.V0_9_0 = actor(Principal.toText(pairCanister));
                    let pairSetting = await pairActor.getConfig();
                    unitSize := Nat64.fromNat(pairSetting.UNIT_SIZE);
                };
                assert(unitSize > 0);
                let args: [Nat8] = _generateArg(token0Principal, token1Principal, unitSize, swapName);
                var installMode : InstallMode = _mode;
                // if (_onlyOwner(msg.caller) and Option.get(_reinstall, false)){
                //     installMode := #reinstall;
                // };
                await ic.install_code({
                    arg : [Nat8] = args;
                    wasm_module = _wasm;
                    mode = installMode; // #reinstall; #upgrade; #install
                    canister_id = pairCanister;
                });
                if (_mode == #reinstall){
                    await pairActor.init();
                    await pairActor.timerStart(900);
                    ignore await pairActor.setPause(true, null);
                };
                let pairNew: SwapPair = {
                    token0: TokenInfo = (token0Principal, token0Symbol, token0Std); 
                    token1: TokenInfo = (token1Principal, token1Symbol, token1Std); 
                    dexName: DexName = "icdex"; 
                    canisterId: PairCanister = pairCanister;
                    feeRate: Float = (await pairActor.feeStatus()).feeRate; //  0.5%
                };
                pairs := Trie.put(pairs, keyp(pairCanister), Principal.equal, pairNew).0;
                let router: Router.Self = actor(icRouter);
                await router.putByDex(
                    (token0Principal, token0Symbol, token0Std), 
                    (token1Principal, token1Symbol, token1Std), 
                    pairCanister);
                
                return ?pairCanister;
            };
            case(_){
                return null;
            };
        };
    };

    public shared(msg) func pubCreate(_token0: Principal, _token1: Principal): async (canister: PairCanister){
        assert(not(_isExistedByToken(_token0, _token1)));
        let token: ICRC1.Self = actor(Principal.toText(sysToken));
        let result = await token.icrc2_transfer_from({
            spender_subaccount = null; // *
            from = {owner = msg.caller; subaccount = null};
            to = {owner = Principal.fromActor(this); subaccount = null};
            amount = creatingPairFee;
            fee = null;
            memo = null;
            created_at_time = null;
        });
        switch(result){
            case(#Ok(blockNumber)){
                try{
                    let canisterId = await* _create(_token0, _token1, null, null);
                    let pairActor: ICDexPrivate.Self = actor(Principal.toText(canisterId));
                    ignore await pairActor.setPause(false, null);
                    return canisterId;
                }catch(e){
                    if (creatingPairFee > sysTokenFee){
                        let r = await token.icrc1_transfer({
                            from_subaccount = null;
                            to = {owner = msg.caller; subaccount = null};
                            amount = Nat.sub(creatingPairFee, sysTokenFee);
                            fee = null;
                            memo = null;
                            created_at_time = null;
                        });
                    };
                    throw Error.reject("Error: Creation Failed. "# Error.message(e)); 
                };
            };
            case(#Err(e)){
                throw Error.reject("Error: Error when paying the fee for creating a trading pair."); 
            };
        };
    };

    /* =======================
      Managing Wasm
    ========================= */
    public shared(msg) func setWasm(_wasm: Blob, _version: Text, _append: Bool, _backup: Bool) : async (){
        assert(_onlyOwner(msg.caller));
        if (not(_append)){
            if (_backup){
                wasm_preVersion := wasm;
            };
            wasm := Blob.toArray(_wasm);
            wasmVersion := _version;
        }else{
            assert(_version == wasmVersion);
            wasm := Tools.arrayAppend(wasm, Blob.toArray(_wasm));
        };
    };
    public query func getWasmVersion() : async (Text, Text, Nat){
        let offset = wasm.size() / 2;
        var hash224 = SHA224.sha224(Tools.arrayAppend(Tools.slice(wasm, 0, ?1024), Tools.slice(wasm, offset, ?(offset+1024))));
        var crc : [Nat8] = CRC32.crc32(hash224);
        let hash = Tools.arrayAppend(crc, hash224);  
        return (wasmVersion, Hex.encode(hash), wasm.size());
    };
    /* =======================
      Managing trading pairs
    ========================= */
    /// Create a new pair
    // create '(principal "", principal "ryjl3-tyaaa-aaaaa-aaaba-cai", null, null)'
    public shared(msg) func create(_token0: Principal, _token1: Principal, _unitSize: ?Nat64, _initCycles: ?Nat): async (canister: PairCanister){
        assert(_onlyOwner(msg.caller));
        return await* _create(_token0, _token1, _unitSize, _initCycles);
    };
    
    /// Upgrade pair canister
    public shared(msg) func update(_pair: Principal, _version: Text): async (canister: ?PairCanister){
        assert(_onlyOwner(msg.caller));
        assert(wasm.size() > 0);
        assert(_version == wasmVersion);
        return await* _update(_pair, wasm, #upgrade);
    };
    /// Rollback to previous version (the last version that was saved)
    public shared(msg) func rollback(_pair: Principal): async (canister: ?PairCanister){
        assert(_onlyOwner(msg.caller));
        assert(wasm_preVersion.size() > 0);
        let pair : ICDexPrivate.Self = actor(Principal.toText(_pair));
        let info = await pair.info();
        assert(info.paused);
       return await* _update(_pair, wasm_preVersion, #upgrade);
    };
    /// Modifying the controllers of the pair
    public shared(msg) func setControllers(_pair: Principal, _controllers: [Principal]): async Bool{
        assert(_onlyOwner(msg.caller));
        assert(Option.isSome(Array.find(_controllers, func (t: Principal): Bool{ t == Principal.fromActor(this) })));
        let settings = await ic.update_settings({
            canister_id = _pair; 
            settings={ 
                compute_allocation = null;
                controllers = ?_controllers; 
                freezing_threshold = null;
                memory_allocation = null;
            };
        });
        return true;
    };
    /// Note: A reinstallation of a pair canister would not be usable as a production environment, as its nonce is contaminated by the previous version.
    public shared(msg) func reinstall(_pair: Principal, _version: Text, _snapshot: Bool) : async (canister: ?PairCanister){
        assert(_onlyOwner(msg.caller));
        assert(wasm.size() > 0);
        assert(_version == wasmVersion);

        let data = await _backup(_pair);
        backupData := data;
        if (_snapshot){
            let ts = _setSnapshot(_pair, data);
        };

        let pair : ICDexPrivate.Self = actor(Principal.toText(_pair));
        let res =  await* _update(_pair, wasm, #reinstall);

        await _recovery(_pair, data);

        return res; //?Principal.fromText("");
    };
    public shared(msg) func sync() : async (){ // sync fee
        assert(_onlyOwner(msg.caller));
        for ((canister, pair) in Trie.iter(pairs)){
            let f = await _syncFee(pair);
        };
    };
    
    /* =======================
      Data snapshots (backup & recovery)
    ========================= */
    private stable var backupData : [Backup.BackupResponse] = []; // temporary cache for debug
    private stable var snapshots : Trie.Trie<PairCanister, List.List<(ICDexTypes.Timestamp, [Backup.BackupResponse])>> = Trie.empty(); 
    private func _setSnapshot(_pair: Principal, _backupData: [Backup.BackupResponse]): ICDexTypes.Timestamp{
        let now = Int.abs(Time.now()) / 1000000000;
        switch(Trie.get(snapshots, keyp(_pair), Principal.equal)){
            case(?list){
                let temp = List.filter(list, func(t: (Nat, [Backup.BackupResponse])): Bool{ now < t.0 + 60 * 24 * 3600 }); // 60days
                snapshots := Trie.put(snapshots, keyp(_pair), Principal.equal, List.push((now, _backupData), temp)).0;
            };
            case(_){
                snapshots := Trie.put(snapshots, keyp(_pair), Principal.equal, List.push((now, _backupData), null)).0;
            };
        };
        return now;
    };
    private func _getSnapshot(_pair: Principal, _ts: ?ICDexTypes.Timestamp): ?[Backup.BackupResponse]{
        switch(Trie.get(snapshots, keyp(_pair), Principal.equal), _ts){
            case(?list, ?ts){
                var temp = list;
                while(Option.isSome(temp)){
                    let (t, l) = List.pop(temp);
                    temp := l;
                    switch(t){
                        case(?(ts_, data)){ 
                            if (ts == ts_){
                                return ?data;
                            };
                        };
                        case(_){};
                    };
                };
                return null;
            };
            case(?list, null){
                switch(List.pop(list).0){
                    case(?(ts, data)){ return ?data };
                    case(_){ return null };
                };
            };
            case(_, _){
                return null;
            };
        };
    };
    private func _getSnapshotTs(_pair: Principal): [ICDexTypes.Timestamp]{
        switch(Trie.get(snapshots, keyp(_pair), Principal.equal)){
            case(?list){
                return Array.map(List.toArray(list), func (t: (ICDexTypes.Timestamp, [Backup.BackupResponse])): ICDexTypes.Timestamp{
                    t.0
                });
            };
            case(_){
                return [];
            };
        };
    };
    private func _backup(_pair: Principal) : async [Backup.BackupResponse]{
        let pair : ICDexPrivate.Self = actor(Principal.toText(_pair));
        let info = await pair.info();
        assert(info.paused);
        var backupData : [Backup.BackupResponse] = [];
        let otherData = await pair.backup(#otherData);
        backupData := Tools.arrayAppend(backupData, [otherData]);
        let icdex_orders = await pair.backup(#icdex_orders);
        backupData := Tools.arrayAppend(backupData, [icdex_orders]);
        let icdex_failedOrders = await pair.backup(#icdex_failedOrders);
        backupData := Tools.arrayAppend(backupData, [icdex_failedOrders]);
        let icdex_orderBook = await pair.backup(#icdex_orderBook);
        backupData := Tools.arrayAppend(backupData, [icdex_orderBook]);
        let icdex_klines2 = await pair.backup(#icdex_klines2);
        backupData := Tools.arrayAppend(backupData, [icdex_klines2]);
        let icdex_vols = await pair.backup(#icdex_vols);
        backupData := Tools.arrayAppend(backupData, [icdex_vols]);
        let icdex_nonces = await pair.backup(#icdex_nonces);
        backupData := Tools.arrayAppend(backupData, [icdex_nonces]);
        let icdex_pendingOrders = await pair.backup(#icdex_pendingOrders);
        backupData := Tools.arrayAppend(backupData, [icdex_pendingOrders]);
        let icdex_makers = await pair.backup(#icdex_makers);
        backupData := Tools.arrayAppend(backupData, [icdex_makers]);
        let icdex_dip20Balances = await pair.backup(#icdex_dip20Balances);
        backupData := Tools.arrayAppend(backupData, [icdex_dip20Balances]);
        let clearingTxids = await pair.backup(#clearingTxids);
        backupData := Tools.arrayAppend(backupData, [clearingTxids]);
        let timeSortedTxids = await pair.backup(#timeSortedTxids);
        backupData := Tools.arrayAppend(backupData, [timeSortedTxids]);
        let ambassadors = await pair.backup(#ambassadors);
        backupData := Tools.arrayAppend(backupData, [ambassadors]);
        let traderReferrers = await pair.backup(#traderReferrers);
        backupData := Tools.arrayAppend(backupData, [traderReferrers]);
        let rounds = await pair.backup(#rounds);
        backupData := Tools.arrayAppend(backupData, [rounds]);
        let competitors = await pair.backup(#competitors);
        backupData := Tools.arrayAppend(backupData, [competitors]);
        var sagaData = await pair.backup(#sagaData(#Base));
        try { sagaData := await pair.backup(#sagaData(#All)); } catch(e){};
        backupData := Tools.arrayAppend(backupData, [sagaData]);
        var drc205Data = await pair.backup(#drc205Data(#Base));
        try { drc205Data := await pair.backup(#drc205Data(#All)); } catch(e){};
        backupData := Tools.arrayAppend(backupData, [drc205Data]);
        let traderReferrerTemps = await pair.backup(#traderReferrerTemps);
        backupData := Tools.arrayAppend(backupData, [traderReferrerTemps]);
        let ictcTaskCallbackEvents = await pair.backup(#ictcTaskCallbackEvents);
        backupData := Tools.arrayAppend(backupData, [ictcTaskCallbackEvents]);
        let ictc_admins = await pair.backup(#ictc_admins);
        backupData := Tools.arrayAppend(backupData, [ictc_admins]);
        let icdex_RPCAccounts = await pair.backup(#icdex_RPCAccounts);
        backupData := Tools.arrayAppend(backupData, [icdex_RPCAccounts]);
        let icdex_accountSettings = await pair.backup(#icdex_accountSettings);
        backupData := Tools.arrayAppend(backupData, [icdex_accountSettings]);
        let icdex_keepingBalances = await pair.backup(#icdex_keepingBalances);
        backupData := Tools.arrayAppend(backupData, [icdex_keepingBalances]);
        let icdex_poolBalance = await pair.backup(#icdex_poolBalance);
        backupData := Tools.arrayAppend(backupData, [icdex_poolBalance]);

        let icdex_sto = await pair.backup(#icdex_sto);
        backupData := Tools.arrayAppend(backupData, [icdex_sto]);
        let icdex_stOrderRecords = await pair.backup(#icdex_stOrderRecords);
        backupData := Tools.arrayAppend(backupData, [icdex_stOrderRecords]);
        let icdex_userProOrderList = await pair.backup(#icdex_userProOrderList);
        backupData := Tools.arrayAppend(backupData, [icdex_userProOrderList]);
        let icdex_userStopLossOrderList = await pair.backup(#icdex_userStopLossOrderList);
        backupData := Tools.arrayAppend(backupData, [icdex_userStopLossOrderList]);
        let icdex_stOrderTxids = await pair.backup(#icdex_stOrderTxids);
        backupData := Tools.arrayAppend(backupData, [icdex_stOrderTxids]);

        assert(backupData.size() == 30);
        return backupData;
    };
    private func _recovery(_pair: Principal, _backupData: [Backup.BackupResponse]) : async (){
        let pair : ICDexPrivate.Self = actor(Principal.toText(_pair));
        let info = await pair.info();
        assert(info.paused);
        assert(_backupData.size() == 30);
        ignore await pair.recovery(_backupData[0]);
        ignore await pair.recovery(_backupData[1]);
        ignore await pair.recovery(_backupData[2]);
        ignore await pair.recovery(_backupData[3]);
        ignore await pair.recovery(_backupData[4]);
        ignore await pair.recovery(_backupData[5]);
        ignore await pair.recovery(_backupData[6]);
        ignore await pair.recovery(_backupData[7]);
        ignore await pair.recovery(_backupData[8]);
        ignore await pair.recovery(_backupData[9]);
        ignore await pair.recovery(_backupData[10]);
        ignore await pair.recovery(_backupData[11]);
        ignore await pair.recovery(_backupData[12]);
        ignore await pair.recovery(_backupData[13]);
        ignore await pair.recovery(_backupData[14]);
        ignore await pair.recovery(_backupData[15]);
        ignore await pair.recovery(_backupData[16]);
        ignore await pair.recovery(_backupData[17]);
        ignore await pair.recovery(_backupData[18]);
        ignore await pair.recovery(_backupData[19]);
        ignore await pair.recovery(_backupData[20]);
        ignore await pair.recovery(_backupData[21]);
        ignore await pair.recovery(_backupData[22]);
        ignore await pair.recovery(_backupData[23]);
        ignore await pair.recovery(_backupData[24]);
        ignore await pair.recovery(_backupData[25]);
        ignore await pair.recovery(_backupData[26]);
        ignore await pair.recovery(_backupData[27]);
        ignore await pair.recovery(_backupData[28]);
        ignore await pair.recovery(_backupData[29]);
    };
    public query func getSnapshots(_pair: Principal): async [ICDexTypes.Timestamp]{
        return _getSnapshotTs(_pair);
    };
    public shared(msg) func backup(_pair: Principal): async ICDexTypes.Timestamp{
        assert(_onlyOwner(msg.caller));
        let data = await _backup(_pair);
        return _setSnapshot(_pair, data);
    };
    /// Note: You need to check the wasm version and the status of the trading pair, the operation may lead to data loss.
    public shared(msg) func recovery(_pair: Principal, _snapshotTimestamp: ICDexTypes.Timestamp): async Bool{
        assert(_onlyOwner(msg.caller));
        switch(_getSnapshot(_pair, ?_snapshotTimestamp)){
            case(?data){
                await _recovery(_pair, data);
                return true;
            };
            case(_){
                return false;
            };
        };
    };
    // Note: Pair `_pairTo` is created only for backing up data and should not be used for trading.
    public shared(msg) func backupToTempCanister(_pairFrom: Principal, _pairTo: Principal) : async Bool{
        assert(_onlyOwner(msg.caller));
        let data = await _backup(_pairFrom);
        await _recovery(_pairTo, data);
        return true;
    };
    
    
    /* =======================
      Managing the list of pairs
    ========================= */
    public shared(msg) func put(_pair: SwapPair) : async (){
        assert(_onlyOwner(msg.caller));
        let pair = _adjustPair2(_pair);
        pairs := Trie.put(pairs, keyp(pair.canisterId), Principal.equal, pair).0;
        await _syncFee(pair);
        let router: Router.Self = actor(icRouter);
        await router.putByDex(
            _pair.token0, 
            _pair.token1, 
            _pair.canisterId);
    };
    public shared(msg) func remove(_pairCanister: Principal) : async (){
        assert(_onlyOwner(msg.caller));
        pairs := Trie.filter(pairs, func (k: PairCanister, v: SwapPair): Bool{ 
            _pairCanister != k;
        });
        let router: Router.Self = actor(icRouter);
        try{
            await router.removeByDex(_pairCanister);
            cyclesMonitor := CyclesMonitor.remove(cyclesMonitor, _pairCanister);
        }catch(e){};
    };
    public query func getTokens() : async [TokenInfo]{
        var trie = pairs;
        var res: [TokenInfo] = [];
        for ((canister, pair) in Trie.iter(trie)){
            if (Option.isNull(Array.find(res, func (t:TokenInfo):Bool{ t.0 == pair.token0.0 }))){
                res := Tools.arrayAppend(res, [pair.token0]);
            };
            // if (Option.isNull(Array.find(res, func (t:TokenInfo):Bool{ t.0 == pair.token1.0 }))){
            //     res := Tools.arrayAppend(res, [pair.token1]);
            // };
        };
        return res;
    };
    public query func getPairs(_page: ?Nat, _size: ?Nat) : async TrieList<PairCanister, SwapPair>{
        var trie = pairs;
        let page = Option.get(_page, 1);
        let size = Option.get(_size, 100);
        return trieItems(trie, page, size);
    };
    public query func getPairsByToken(_token: Principal) : async [(PairCanister, SwapPair)]{
        return _getPairsByToken(_token, null);
    };
    public query func route(_token0: Principal, _token1: Principal) : async [(PairCanister, SwapPair)]{
        let paris =  _getPairsByToken(_token0, ?_token1);

    };
    
    /* =======================
      Governance operations on trading pairs
    ========================= */
    public shared(msg) func pair_pause(_app: Principal, _pause: Bool, _openingTime: ?Time.Time) : async Bool{ 
        assert(_onlyOwner(msg.caller));
        let pair: ICDexPrivate.Self = actor(Principal.toText(_app));
        return await pair.setPause(_pause, _openingTime);
    };
    public shared(msg) func pair_IDOSetFunder(_app: Principal, _funder: ?Principal, _requirement: ?ICDexPrivate.IDORequirement) : async (){ 
        assert(_onlyOwner(msg.caller));
        let pair: ICDexPrivate.Self = actor(Principal.toText(_app));
        IDOPairs := List.filter(IDOPairs, func (t: Principal): Bool{ t != _app });
        if (Option.isSome(_funder)){
            IDOPairs := List.push(_app, IDOPairs);
        };
        return await pair.IDO_setFunder(_funder, _requirement);
    };
    public shared(msg) func pair_changeOwner(_app: Principal, _newOwner: Principal) : async Bool{ 
        assert(_onlyOwner(msg.caller));
        let pair: ICDexPrivate.Self = actor(Principal.toText(_app));
        return await pair.changeOwner(_newOwner);
    };
    // pair_config '(principal "", opt record{UNIT_SIZE=opt 100000000:opt nat}, null)'
    // pair_config '(principal "", null, opt record{MAX_CACHE_TIME= opt 5184000000000000})'
    public shared(msg) func pair_config(_app: Principal, _config: ?ICDexTypes.DexConfig, _drc205config: ?DRC205.Config) : async Bool{ 
        assert(_onlyOwner(msg.caller));
        let pair: ICDexPrivate.Self = actor(Principal.toText(_app));
        var res : Bool = false;
        switch(_config){
            case(?(dexConfig)){
                ignore await pair.config(dexConfig);
                res := true;
            };
            case(_){};
        };
        switch(_drc205config){
            case(?(drc205Config)){
                ignore await pair.drc205_config(drc205Config);
                res := true;
            };
            case(_){};
        };
        return res;
    };
    public shared(msg) func pair_setUpgradeMode(_app: Principal, _mode: {#Base; #All}) : async (){
        assert(_onlyOwner(msg.caller));
        let pair: ICDexPrivate.Self = actor(Principal.toText(_app));
        return await pair.setUpgradeMode(_mode);
    };
    public shared(msg) func pair_setOrderFail(_app: Principal, _txid: Text) : async Bool{
        assert(_onlyOwner(msg.caller));
        let pair: ICDexPrivate.Self = actor(Principal.toText(_app));
        return await pair.setOrderFail(_txid);
    };
    public shared(msg) func pair_pendingAll(_app: Principal, _page: ?Nat, _size: ?Nat) : async ICDexTypes.TrieList<ICDexTypes.Txid, ICDexTypes.TradingOrder>{
        assert(_onlyOwner(msg.caller));
        let pair: ICDexPrivate.Self = actor(Principal.toText(_app));
        return await pair.pendingAll(_page, _size);
    };
    public shared(msg) func pair_withdrawCycles(_app: Principal, _amount: Nat): async (){
        assert(_onlyOwner(msg.caller));
        let pair: ICDexPrivate.Self = actor(Principal.toText(_app));
        await pair.withdraw_cycles(_amount);
    };
    // public shared(msg) func pair_setMaxTPS(_app: Principal, _tps: Nat, _storageIntervalSeconds: Nat, _ICTCRunInterval: Nat) : async Bool{
    //     assert(_onlyOwner(msg.caller));
    //     let pair: ICDexPrivate.Self = actor(Principal.toText(_app));
    //     var res : Bool = false;
    //     return await pair.setMaxTPS(_tps, _storageIntervalSeconds, _ICTCRunInterval);
    // };
    public shared(msg) func pair_ictcSetAdmin(_app: Principal, _admin: Principal, _addOrRemove: Bool) : async Bool{ 
        assert(_onlyOwner(msg.caller));
        let pair: ICDexPrivate.Self = actor(Principal.toText(_app));
        if (_addOrRemove){
            await pair.ictc_addAdmin(_admin);
        }else{
            await pair.ictc_removeAdmin(_admin);
        };
        return true;
    };
    public shared(msg) func pair_ictcClearLog(_app: Principal, _expiration: ?Int, _delForced: Bool) : async (){ 
        assert(_onlyOwner(msg.caller));
        let pair: ICDexPrivate.Self = actor(Principal.toText(_app));
        await pair.ictc_clearLog(_expiration, _delForced);
    };
    public shared(msg) func pair_ictcClearTTPool(_app: Principal) : async (){ 
        assert(_onlyOwner(msg.caller));
        let pair: ICDexPrivate.Self = actor(Principal.toText(_app));
        await pair.ictc_clearTTPool();
    };
    // public shared(msg) func pair_ictcManageOrder1(_app: Principal, _txid: Txid, _orderStatus: ICDexTypes.TradingStatus, _token0Fallback: Nat, _token1Fallback: Nat, _token0FromPair: Nat, _token1FromPair: Nat) : async Bool{
    //     assert(_onlyOwner(msg.caller));
    //     let pair: ICDexPrivate.Self = actor(Principal.toText(_app));
    //     await pair.ictc_manageOrder1(_txid, _orderStatus, _token0Fallback, _token1Fallback, _token0FromPair, _token1FromPair);
    // };
    public shared(msg) func pair_ictcRedoTT(_app: Principal, _toid: Nat, _ttid: Nat) : async (?Nat){ 
        assert(_onlyOwner(msg.caller));
        let pair: ICDexPrivate.Self = actor(Principal.toText(_app));
        await pair.ictc_redoTT(_toid, _ttid);
    };
    public shared(msg) func pair_ictcCompleteTO(_app: Principal, _toid: Nat, _status: SagaTM.OrderStatus) : async Bool{ 
        assert(_onlyOwner(msg.caller));
        let pair: actor{ ictc_completeTO: shared (_toid: Nat, _status: SagaTM.OrderStatus) -> async Bool } = actor(Principal.toText(_app));
        await pair.ictc_completeTO(_toid, _status);
    };
    public shared(msg) func pair_ictcDoneTT(_app: Principal, _toid: Nat, _ttid: Nat, _toCallback: Bool) : async (?Nat){ 
        assert(_onlyOwner(msg.caller));
        let pair: ICDexPrivate.Self = actor(Principal.toText(_app));
        await pair.ictc_doneTT(_toid, _ttid, _toCallback);
    };
    public shared(msg) func pair_ictcDoneTO(_app: Principal, _toid: Nat, _status: SagaTM.OrderStatus, _toCallback: Bool) : async Bool{ 
        assert(_onlyOwner(msg.caller));
        let pair: ICDexPrivate.Self = actor(Principal.toText(_app));
        await pair.ictc_doneTO(_toid, _status, _toCallback);
    };
    public shared(msg) func pair_ictcRunTO(_app: Principal, _toid: Nat) : async ?SagaTM.OrderStatus{ 
        assert(_onlyOwner(msg.caller));
        let pair: ICDexPrivate.Self = actor(Principal.toText(_app));
        await pair.ictc_runTO(_toid);
    };
    public shared(msg) func pair_ictcBlockTO(_app: Principal, _toid: Nat) : async (?Nat){ 
        assert(_onlyOwner(msg.caller));
        let pair: ICDexPrivate.Self = actor(Principal.toText(_app));
        await pair.ictc_blockTO(_toid);
    };
    public shared(msg) func pair_sync(_app: Principal) : async (){
        assert(_onlyOwner(msg.caller));
        let pair: ICDexPrivate.Self = actor(Principal.toText(_app));
        await pair.sync();
    };
    public shared(msg) func pair_setVipMaker(_app: Principal, _account: Address, _rate: Nat) : async (){
        assert(_onlyOwner(msg.caller));
        let pair: ICDexPrivate.Self = actor(Principal.toText(_app));
        await pair.setVipMaker(_account, _rate);
    };
    public shared(msg) func pair_removeVipMaker(_app: Principal, _account: Address) : async (){
        assert(_onlyOwner(msg.caller));
        let pair: ICDexPrivate.Self = actor(Principal.toText(_app));
        await pair.removeVipMaker(_account);
    };
    public shared(msg) func pair_fallbackByTxid(_app: Principal, _txid: Txid, _sa: ?ICDexPrivate.Sa) : async Bool{
        assert(_onlyOwner(msg.caller));
        let pair: ICDexPrivate.Self = actor(Principal.toText(_app));
        await pair.fallbackByTxid(_txid, _sa);
    };
    public shared(msg) func pair_cancelByTxid(_app: Principal,  _txid: Txid, _sa: ?ICDexPrivate.Sa) : async (){
        assert(_onlyOwner(msg.caller));
        let pair: ICDexPrivate.Self = actor(Principal.toText(_app));
        await pair.cancelByTxid(_txid, _sa);
    };
    public shared(msg) func pair_taSetDescription(_app: Principal, _desc: Text) : async (){ 
        assert(_onlyOwner(msg.caller));
        let pair: ICDexPrivate.Self = actor(Principal.toText(_app));
        await pair.ta_setDescription(_desc);
    };

    /* =======================
      Trading Competitions
    ========================= */
    //$call RouterTest pair_compNewRound '(principal "po4px-oiaaa-aaaak-acubq-cai", "CompTest2", "test2", 1665468703000000000, 1665540000000000000, variant{token1}, 100000, false)'
    // public shared(msg) func pair_compNewRound(_app: Principal, _name: Text, _content: Text, _start: Time.Time, _end: Time.Time, _quoteToken:{#token0; #token1}, _minCapital: Nat, _forced: Bool) : async Nat{ 
    //     assert(_onlyOwner(msg.caller));
    //     let pair: ICDexPrivate.Self = actor(Principal.toText(_app));
    //     return await pair.comp_newRound(_name, _content, _start, _end, _quoteToken, _minCapital, _forced);
    // };
    // dex competition
    // $call RouterTest dex_addCompetition '(null, "Test1", "", 1684208349000000000, 1684209600000000000, vec {record{dex="icdex"; canisterId=principal "ynbvm-hiaaa-aaaak-adbqa-cai";quoteToken=variant{token1};minCapital=1}; record{dex="icdex"; canisterId=principal "fpwot-xyaaa-aaaak-adp2a-cai";quoteToken=variant{token0};minCapital=1}})'
    public shared(msg) func dex_addCompetition(_id: ?Nat, _name: Text, _content: Text, _start: Time.Time, _end: Time.Time, 
    pairs: [{dex: Text; canisterId: Principal; quoteToken:{#token0; #token1}; minCapital: Nat}]) : async Nat{ 
        assert(_onlyOwner(msg.caller));
        var pairList : [(DexName, Principal, {#token0; #token1})] = [];
        for (pair in pairs.vals()){
            pairList := Tools.arrayAppend(pairList, [(pair.dex, pair.canisterId, pair.quoteToken)]);
        };
        let router : Router.Self = actor(icRouter);
        return await router.pushCompetitionByDex(_id, _name, _content, _start, _end, pairList);
    };

    /* =======================
      System management
    ========================= */
    public query func getOwner() : async Principal{  
        return owner;
    };
    public shared(msg) func changeOwner(_newOwner: Principal) : async Bool{ 
        assert(_onlyOwner(msg.caller));
        owner := _newOwner;
        return true;
    };
    public shared(msg) func sys_withdraw(_token: Principal, _tokenStd: TokenStd, _to: Principal, _value: Nat) : async (){ 
        assert(_onlyOwner(msg.caller));
        let account = Tools.principalToAccountBlob(_to, null);
        let address = Tools.principalToAccountHex(_to, null);
        if (_tokenStd == #drc20){
            let token: DRC20.Self = actor(Principal.toText(_token));
            let res = await token.drc20_transfer(address, _value, null, null, null);
        }else if (_tokenStd == #icrc1){
            let token: ICRC1.Self = actor(Principal.toText(_token));
            let args : ICRC1.TransferArgs = {
                memo = null;
                amount = _value;
                fee = null;
                from_subaccount = null;
                to = {owner = _to; subaccount = null};
                created_at_time = null;
            };
            let res = await token.icrc1_transfer(args);
        }else if (_tokenStd == #icp or _tokenStd == #ledger){
            let token: Ledger.Self = actor(Principal.toText(_token));
            let args : Ledger.TransferArgs = {
                memo = 0;
                amount = { e8s = Nat64.fromNat(_value) };
                fee = { e8s = 10000 };
                from_subaccount = null;
                to = account;
                created_at_time = null;
            };
            let res = await token.transfer(args);
        }
    };
    public shared(msg) func sys_order(_token: Principal, _tokenStd: TokenStd, _value: Nat, _pair: Principal, _order: ICDexTypes.OrderPrice) : async ICDexTypes.TradingResult{
        assert(_onlyOwner(msg.caller));
        let account = Tools.principalToAccountBlob(Principal.fromActor(this), null);
        let address = Tools.principalToAccountHex(Principal.fromActor(this), null);
        let pairAddress = Tools.principalToAccountHex(_pair, null);
        //getTxAccount : shared query (_account: Address) -> async ({owner: Principal; subaccount: ?Blob}, Text, Nonce, Txid);
        //trade : shared (_order: OrderPrice, _orderType: OrderType, _expiration: ?Int, _nonce: ?Nat, _sa: ?Sa, _data: ?Data)
        let pair: ICDexTypes.Self = actor(Principal.toText(_pair));
        if (_tokenStd == #drc20){
            let token: DRC20.Self = actor(Principal.toText(_token));
            let r = await token.drc20_approve(pairAddress, _value, null,null,null);
        }else if (_tokenStd == #icrc1){
            let token: ICRC1.Self = actor(Principal.toText(_token));
            let fee = await token.icrc1_fee();
            let prepares = await pair.getTxAccount(address);
            let tx_icrc1Account = prepares.0;
            let args : ICRC1.TransferArgs = {
                memo = null;
                amount = _value;
                fee = ?fee;
                from_subaccount = null;
                to = tx_icrc1Account;
                created_at_time = null;
            };
            let res = await token.icrc1_transfer(args);
        }else if (_tokenStd == #icp or _tokenStd == #ledger){
            let token: Ledger.Self = actor(Principal.toText(_token));
            let fee : Nat = 10000;
            let prepares = await pair.getTxAccount(address);
            let tx_icrc1Account = prepares.0;
            let args : Ledger.TransferArgs = {
                memo = 0;
                amount = { e8s = Nat64.fromNat(_value) };
                fee = { e8s = Nat64.fromNat(fee) };
                from_subaccount = null;
                to = Tools.principalToAccountBlob(tx_icrc1Account.owner, _toSaNat8(tx_icrc1Account.subaccount));
                created_at_time = null;
            };
            let res = await token.transfer(args);
        };
        return await pair.trade(_order, #LMT, null,null,?[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],null);
    };
    public shared(msg) func sys_cancelOrder(_pair: Principal, _txid: ?Txid) : async (){
        assert(_onlyOwner(msg.caller));
        let address = Tools.principalToAccountHex(Principal.fromActor(this), null);
        let pair: ICDexTypes.Self = actor(Principal.toText(_pair));
        let prepares = await pair.getTxAccount(address);
        let nonce = prepares.2;
        switch(_txid){
            case(?(txid)){ //cancel2 : shared (_txid: Txid, _sa: ?Sa) -> async ();
                let res = await pair.cancelByTxid(txid, null);
            };
            case(_){
                if (nonce > 0){ //cancel : shared (_nonce: Nat, _sa: ?Sa) -> async ();
                    let res = await pair.cancel(Nat.sub(nonce, 1), null);
                };
            };
        };
    };
    public shared(msg) func sys_config(_args: {
        icRouter: ?Principal;
        sysToken: ?Principal;
        sysTokenFee: ?Nat;
        creatingPairFee: ?Nat;
        creatingMakerFee: ?Nat;
    }) : async (){
        assert(_onlyOwner(msg.caller));
        icRouter := Principal.toText(Option.get(_args.icRouter, Principal.fromText(icRouter)));
        sysToken := Option.get(_args.sysToken, sysToken);
        sysTokenFee := Option.get(_args.sysTokenFee, sysTokenFee);
        creatingPairFee := Option.get(_args.creatingPairFee, creatingPairFee);
        creatingMakerFee := Option.get(_args.creatingMakerFee, creatingMakerFee);
    };

    /* =======================
      NFT
    ========================= */
    // private stable var nftVipMakers: Trie.Trie<Text, (AccountId, [Principal])> = Trie.empty(); 
    type NFTType = {#NEPTUNE/*0-4*/; #URANUS/*5-14*/; #SATURN/*15-114*/; #JUPITER/*115-314*/; #MARS/*315-614*/; #EARTH/*615-1014*/; #VENUS/*1015-1514*/; #MERCURY/*1515-2021*/; #UNKNOWN};
    type CollectionId = Principal;
    type NFT = (ERC721.User, ERC721.TokenIdentifier, ERC721.Balance, NFTType, CollectionId);
    private stable var nfts: Trie.Trie<AccountId, [NFT]> = Trie.empty();
    private let sa_zero : [Nat8] = [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0];
    // private let nftPlanetCards = "goncb-kqaaa-aaaap-aakpa-cai"; // ICLighthouse Planet Cards
    private func _onlyNFTHolder(_owner: AccountId, _nftId: ?ERC721.TokenIdentifier, _nftType: ?NFTType) : Bool{
        switch(Trie.get(nfts, keyb(_owner), Blob.equal), _nftId, _nftType){
            case(?(items), null, null){ return items.size() > 0 };
            case(?(items), ?(nftId), ?(nftType)){
                switch(Array.find(items, func(t: NFT): Bool{ nftId == t.1 and nftType == t.3 and t.2 > 0 })){
                    case(?(user, nftId, balance, nType, collId)){ return balance > 0 };
                    case(_){};
                };
            };
            case(?(items), ?(nftId), null){
                switch(Array.find(items, func(t: NFT): Bool{ nftId == t.1 and t.2 > 0 })){
                    case(?(user, nftId, balance, nType, collId)){ return balance > 0 };
                    case(_){};
                };
            };
            case(?(items), null, ?(nftType)){
                switch(Array.find(items, func(t: NFT): Bool{ nftType == t.3 and t.2 > 0 })){
                    case(?(user, nftId, balance, nType, collId)){ return balance > 0 };
                    case(_){};
                };
            };
            case(_, _, _){};
        };
        return false;
    };
    private func _nftType(_a: ?AccountId, _nftId: Text): NFTType{
        switch(_a){
            case(?(accountId)){
                switch(Trie.get(nfts, keyb(accountId), Blob.equal)){
                    case(?(items)){ 
                        switch(Array.find(items, func(t: NFT): Bool{ _nftId == t.1 })){
                            case(?(user, nftId, balance, nftType, collId)){ return nftType };
                            case(_){};
                        };
                    };
                    case(_){};
                };
            };
            case(_){
                for ((accountId, items) in Trie.iter(nfts)){
                    switch(Array.find(items, func(t: NFT): Bool{ _nftId == t.1 })){
                        case(?(user, nftId, balance, nftType, collId)){ return nftType };
                        case(_){};
                    };
                };
            };
        };
        return #UNKNOWN;
    };
    private func _remote_nftType(_collId: CollectionId, _nftId: Text): async* NFTType{
        let nft: ERC721.Self = actor(Principal.toText(_collId));
        let metadata = await nft.metadata(_nftId);
        switch(metadata){
            case(#ok(#nonfungible({metadata=?(data)}))){
                if (data.size() > 0){
                    switch(Text.decodeUtf8(data)){
                        case(?(json)){
                            let str = Text.replace(json, #char(' '), "");
                            if (Text.contains(str, #text("\"name\":\"NEPTUNE")) or Text.contains(str, #text("name:\"NEPTUNE"))){
                                return #NEPTUNE;
                            }else if (Text.contains(str, #text("\"name\":\"URANUS")) or Text.contains(str, #text("name:\"URANUS"))){
                                return #URANUS;
                            }else if (Text.contains(str, #text("\"name\":\"SATURN")) or Text.contains(str, #text("name:\"SATURN"))){
                                return #SATURN;
                            }else if (Text.contains(str, #text("\"name\":\"JUPITER")) or Text.contains(str, #text("name:\"JUPITER"))){
                                return #JUPITER;
                            }else if (Text.contains(str, #text("\"name\":\"MARS")) or Text.contains(str, #text("name:\"MARS"))){
                                return #MARS;
                            }else if (Text.contains(str, #text("\"name\":\"EARTH")) or Text.contains(str, #text("name:\"EARTH"))){
                                return #EARTH;
                            }else if (Text.contains(str, #text("\"name\":\"VENUS")) or Text.contains(str, #text("name:\"VENUS"))){
                                return #VENUS;
                            }else if (Text.contains(str, #text("\"name\":\"MERCURY")) or Text.contains(str, #text("name:\"MERCURY"))){
                                return #MERCURY;
                            };
                        };
                        case(_){};
                    };
                };
            };
            case(_){};
        };
        return #UNKNOWN;
    };
    private func _remote_isNftHolder(_collId: CollectionId, _a: AccountId, _nftId: Text) : async* Bool{
        let nft: ERC721.Self = actor(Principal.toText(_collId));
        let balance = await nft.balance({ user = #address(_accountIdToHex(_a)); token = _nftId; });
        switch(balance){
            case(#ok(amount)){ return amount > 0; };
            case(_){ return false; };
        };
    };
    private func _NFTPut(_a: AccountId, _nft: NFT) : (){
        switch(Trie.get(nfts, keyb(_a), Blob.equal)){
            case(?(items)){ 
                let _items = Array.filter(items, func(t: NFT): Bool{ t.1 != _nft.1 });
                nfts := Trie.put(nfts, keyb(_a), Blob.equal, Tools.arrayAppend(_items, [_nft])).0 
            };
            case(_){ 
                nfts := Trie.put(nfts, keyb(_a), Blob.equal, [_nft]).0 
            };
        };
    };
    private func _NFTRemove(_a: AccountId, _nftId: ERC721.TokenIdentifier) : (){
        switch(Trie.get(nfts, keyb(_a), Blob.equal)){
            case(?(items)){ 
                let _items = Array.filter(items, func(t: NFT): Bool{ t.1 != _nftId });
                if (_items.size() > 0){
                    nfts := Trie.put(nfts, keyb(_a), Blob.equal, _items).0;
                }else{
                    nfts := Trie.remove(nfts, keyb(_a), Blob.equal).0;
                };
            };
            case(_){};
        };
    };
    private func _NFTTransferFrom(_caller: Principal, _collId: CollectionId, _nftId: ERC721.TokenIdentifier, _sa: ?[Nat8]) : async* ERC721.TransferResponse{
        let accountId = Tools.principalToAccountBlob(_caller, _sa);
        var user: ERC721.User = #principal(_caller);
        if (Option.isSome(_sa) and _sa != ?sa_zero){
            user := #address(Tools.principalToAccountHex(_caller, _sa));
        };
        let nftActor: ERC721.Self = actor(Principal.toText(_collId));
        let args: ERC721.TransferRequest = {
            from = user;
            to = #principal(Principal.fromActor(this));
            token = _nftId;
            amount = 1;
            memo = Blob.fromArray([]);
            notify = false;
            subaccount = null;
        };
        let nftType = await* _remote_nftType(_collId, _nftId);
        let res = await nftActor.transfer(args);
        switch(res){
            case(#ok(v)){ 
                _NFTPut(accountId, (user, _nftId, v, nftType, _collId));
            };
            case(_){};
        };
        return res;
    };
    private func _NFTWithdraw(_caller: Principal, _nftId: ?ERC721.TokenIdentifier, _sa: ?[Nat8]) : async* (){
        let accountId = Tools.principalToAccountBlob(_caller, _sa);
        // Hooks used to check binding
        // assert(not(_hook_NFTStakedForXXX(accountId, _nftId)));
        switch(Trie.get(nfts, keyb(accountId), Blob.equal)){
            case(?(item)){ 
                for(nft in item.vals()){
                    let nftActor: ERC721.Self = actor(Principal.toText(nft.4));
                    let args: ERC721.TransferRequest = {
                        from = #principal(Principal.fromActor(this));
                        to = nft.0;
                        token = nft.1;
                        amount = nft.2;
                        memo = Blob.fromArray([]);
                        notify = false;
                        subaccount = null;
                    };
                    switch(await nftActor.transfer(args)){
                        case(#ok(balance)){
                            _NFTRemove(accountId, nft.1);
                            // Hooks used to unbind all
                            await* _hook_NFTUnbindAllMaker(nft.1);
                        };
                        case(#err(e)){};
                    };
                };
             };
            case(_){};
        };
    };
    public query func NFTs() : async [(AccountId, [NFT])]{
        return Trie.toArray<AccountId, [NFT], (AccountId, [NFT])>(nfts, func (k:AccountId, v:[NFT]) : (AccountId, [NFT]){  (k, v) });
    };
    public query func NFTBalance(_owner: Address) : async [NFT]{
        let accountId = _getAccountId(_owner);
        switch(Trie.get(nfts, keyb(accountId), Blob.equal)){
            case(?(items)){ return items };
            case(_){ return []; };
        };
    };
    public shared(msg) func NFTDeposit(_collectionId: CollectionId, _nftId: ERC721.TokenIdentifier, _sa: ?[Nat8]) : async (){
        let r = await* _NFTTransferFrom(msg.caller, _collectionId, _nftId, _sa);
    };
    public shared(msg) func NFTWithdraw(_nftId: ?ERC721.TokenIdentifier, _sa: ?[Nat8]) : async (){
        let accountId = Tools.principalToAccountBlob(msg.caller, _sa);
        assert(_onlyNFTHolder(accountId, _nftId, null));
        await* _NFTWithdraw(msg.caller, _nftId, _sa);
    };

    /* ===== functions for Makers ==== */
    private stable var nftBindingMakers: Trie.Trie<ERC721.TokenIdentifier, [(pair: Principal, account: AccountId)]> = Trie.empty();
    private let maxNumberBindingPerNft: Nat = 5;
    private func _OnlyNFTBindingMaker(_nftId: ERC721.TokenIdentifier, _pair: Principal, _account: AccountId) : Bool{
        switch(Trie.get(nftBindingMakers, keyt(_nftId), Text.equal)){
            case(?(items)){ 
                return Option.isSome(Array.find(items, func(t: (Principal, AccountId)): Bool{ t.0 == _pair and t.1 == _account }));
             };
            case(_){};
        };
        return false;
    };
    private func _remote_setVipMaker(_nftId: ERC721.TokenIdentifier, _pair: Principal, _a: AccountId) : async* (){
        assert(_nftType(null, _nftId) == #NEPTUNE);
        assert(_OnlyNFTBindingMaker(_nftId, _pair, _a));
        let pair: ICDexPrivate.Self = actor(Principal.toText(_pair));
        await pair.setVipMaker(_accountIdToHex(_a), 90);
    };
    private func _remote_removeVipMaker(_pair: Principal, _a: AccountId) : async* (){
        let pair: ICDexPrivate.Self = actor(Principal.toText(_pair));
        await pair.removeVipMaker(_accountIdToHex(_a));
    };
    private func _NFTBindMaker(_nftId: ERC721.TokenIdentifier, _pair: Principal, _a: AccountId) : async* (){
        switch(Trie.get(nftBindingMakers, keyt(_nftId), Text.equal)){
            case(?(items)){ 
                assert(items.size() < maxNumberBindingPerNft);
                let _items = Array.filter(items, func(t: (Principal, AccountId)): Bool{ t.0 != _pair or t.1 != _a });
                nftBindingMakers := Trie.put(nftBindingMakers, keyt(_nftId), Text.equal, Tools.arrayAppend(_items, [(_pair, _a)])).0 
            };
            case(_){ 
                nftBindingMakers := Trie.put(nftBindingMakers, keyt(_nftId), Text.equal, [(_pair, _a)]).0 
            };
        };
        await* _remote_setVipMaker(_nftId, _pair, _a);
    };
    private func _NFTUnbindMaker(_nftId: ERC721.TokenIdentifier, _pair: Principal, _a: AccountId) : async* (){
        switch(Trie.get(nftBindingMakers, keyt(_nftId), Text.equal)){
            case(?(items)){
                let _items = Array.filter(items, func(t: (Principal, AccountId)): Bool{ t.0 != _pair or t.1 != _a });
                nftBindingMakers := Trie.put(nftBindingMakers, keyt(_nftId), Text.equal, _items).0;
            };
            case(_){};
        };
        await* _remote_removeVipMaker(_pair, _a);
    };
    private func _hook_NFTUnbindAllMaker(_nftId: ERC721.TokenIdentifier) : async* (){
        switch(Trie.get(nftBindingMakers, keyt(_nftId), Text.equal)){
            case(?(items)){
                for ((pair, account) in items.vals()){
                    await* _NFTUnbindMaker(_nftId, pair, account);
                };
            };
            case(_){};
        };
    };
    public query func NFTBindingMakers(_nftId: Text) : async [(pair: Principal, account: AccountId)]{
        switch(Trie.get(nftBindingMakers, keyt(_nftId), Text.equal)){
            case(?(items)){ return items };
            case(_){ return []; };
        };
    };
    public shared(msg) func NFTBindMaker(_nftId: Text, _pair: Principal, _maker: AccountId, _sa: ?[Nat8]) : async (){
        let accountId = Tools.principalToAccountBlob(msg.caller, _sa);
        assert(_onlyNFTHolder(accountId, ?_nftId, ?#NEPTUNE));
        await* _NFTBindMaker(_nftId, _pair, _maker);
    };
    public shared(msg) func NFTUnbindMaker(_nftId: Text, _pair: Principal, _maker: AccountId, _sa: ?[Nat8]) : async (){
        let accountId = Tools.principalToAccountBlob(msg.caller, _sa);
        assert(_onlyNFTHolder(accountId, ?_nftId, ?#NEPTUNE));
        await* _NFTUnbindMaker(_nftId, _pair, _maker);
    };

    /* =======================
      ICDexMaker
    ========================= */
    // private stable var maker_publicCanisters: Trie.Trie<PairCanister, [(maker: Principal, creator: AccountId)]> = Trie.empty(); 
    // private stable var maker_privateCanisters: Trie.Trie<PairCanister, [(maker: Principal, creator: AccountId)]> = Trie.empty(); 
    private func _isPublicMaker(_pair: Principal, _maker: Principal): Bool{
        switch(Trie.get(maker_publicCanisters, keyp(_pair), Principal.equal)){
            case(?(items)){
                return Option.isSome(Array.find(items, func (t: (Principal, AccountId)): Bool{ t.0 == _maker }));
            };
            case(_){ return false };
        };
    };
    private func _OnlyMakerCreator(_pair: Principal, _maker: Principal, _creator: AccountId): Bool{
        switch(Trie.get(maker_publicCanisters, keyp(_pair), Principal.equal)){
            case(?items){
                if (Option.isSome(Array.find(items, func (t: (Principal, AccountId)): Bool{ t.0 == _maker and t.1 == _creator }))){
                    return true;
                };
            };
            case(_){};
        };
        switch(Trie.get(maker_privateCanisters, keyp(_pair), Principal.equal)){
            case(?items){
                if (Option.isSome(Array.find(items, func (t: (Principal, AccountId)): Bool{ t.0 == _maker and t.1 == _creator }))){
                    return true;
                };
            };
            case(_){};
        };
        return false;
    };
    private func _countMaker(_creator: AccountId, _type: {#Public; #Private; #All}): Nat{
        var count: Nat = 0;
        if (_type == #Public or _type == #All){
            for ((pair, items) in Trie.iter(maker_publicCanisters)){
                for ((maker, creator) in items.vals()){
                    if (creator == _creator) { count += 1 };
                };
            };
        };
        if (_type == #Private or _type == #All){
            for ((pair, items) in Trie.iter(maker_privateCanisters)){
                for ((maker, creator) in items.vals()){
                    if (creator == _creator) { count += 1 };
                };
            };
        };
        return count;
    };
    private func _putPublicMaker(_pair: Principal, _maker: Principal, _creator: AccountId) : (){
        switch(Trie.get(maker_publicCanisters, keyp(_pair), Principal.equal)){
            case(?(items)){ 
                let _items = Array.filter(items, func(t: (Principal, AccountId)): Bool{ t.0 != _maker });
                maker_publicCanisters := Trie.put(maker_publicCanisters, keyp(_pair), Principal.equal, Tools.arrayAppend(_items, [(_maker, _creator)])).0 
            };
            case(_){ 
                maker_publicCanisters := Trie.put(maker_publicCanisters, keyp(_pair), Principal.equal, [(_maker, _creator)]).0 
            };
        };
    };
    private func _removePublicMaker(_pair: Principal, _maker: Principal) : (){
        switch(Trie.get(maker_publicCanisters, keyp(_pair), Principal.equal)){
            case(?(items)){ 
                let _items = Array.filter(items, func(t: (Principal, AccountId)): Bool{ t.0 != _maker });
                if (_items.size() > 0){
                    maker_publicCanisters := Trie.put(maker_publicCanisters, keyp(_pair), Principal.equal, _items).0;
                }else{
                    maker_publicCanisters := Trie.remove(maker_publicCanisters, keyp(_pair), Principal.equal).0;
                };
            };
            case(_){};
        };
    };
    private func _putPrivateMaker(_pair: Principal, _maker: Principal, _creator: AccountId) : (){
        switch(Trie.get(maker_privateCanisters, keyp(_pair), Principal.equal)){
            case(?(items)){ 
                let _items = Array.filter(items, func(t: (Principal, AccountId)): Bool{ t.0 != _maker });
                maker_privateCanisters := Trie.put(maker_privateCanisters, keyp(_pair), Principal.equal, Tools.arrayAppend(_items, [(_maker, _creator)])).0 
            };
            case(_){ 
                maker_privateCanisters := Trie.put(maker_privateCanisters, keyp(_pair), Principal.equal, [(_maker, _creator)]).0 
            };
        };
    };
    private func _removePrivateMaker(_pair: Principal, _maker: Principal) : (){
        switch(Trie.get(maker_privateCanisters, keyp(_pair), Principal.equal)){
            case(?(items)){ 
                let _items = Array.filter(items, func(t: (Principal, AccountId)): Bool{ t.0 != _maker });
                if (_items.size() > 0){
                    maker_privateCanisters := Trie.put(maker_privateCanisters, keyp(_pair), Principal.equal, _items).0;
                }else{
                    maker_privateCanisters := Trie.remove(maker_privateCanisters, keyp(_pair), Principal.equal).0;
                };
            };
            case(_){};
        };
    };
    private func _maker_update(_pair: Principal, _maker: Principal, _wasm: [Nat8], _mode: InstallMode, _arg: {
            name: ?Text; // "AAA_BBB DeMM-1"
        }) : async* (canister: ?Principal){
        var data = maker_privateCanisters;
        if (_isPublicMaker(_pair, _maker)){
            data := maker_publicCanisters;
        };
        switch(Trie.get(data, keyp(_pair), Principal.equal)){
            case(?items){
                for ((maker, creator) in items.vals()){
                    if (maker == _maker){
                        let pairActor: ICDexPrivate.Self = actor(Principal.toText(_pair));
                        let makerActor: Maker.Self = actor(Principal.toText(_maker));
                        let makerInfo = await makerActor.info();
                        assert(_wasm.size() > 0);
                        //upgrade
                        let args: [Nat8] = Blob.toArray(to_candid({
                            creator = makerInfo.creator;
                            allow = makerInfo.visibility;
                            pair = makerInfo.pairInfo.pairPrincipal;
                            unitSize = makerInfo.pairInfo.pairUnitSize;
                            name = Option.get(_arg.name, makerInfo.name);
                            token0 = makerInfo.pairInfo.token0.0;
                            token0Std = makerInfo.pairInfo.token0.2;
                            token1 = makerInfo.pairInfo.token1.0;
                            token1Std = makerInfo.pairInfo.token1.2;
                            lowerLimit = makerInfo.gridSetting.gridLowerLimit; //Price
                            upperLimit = makerInfo.gridSetting.gridUpperLimit; //Price
                            spreadRate = makerInfo.gridSetting.gridSpread; // ppm  x/1000000
                            threshold = makerInfo.poolThreshold;
                            volFactor = makerInfo.volFactor; // multi 
                        }));
                        await ic.install_code({
                            arg : [Nat8] = args;
                            wasm_module = _wasm;
                            mode = _mode; // #reinstall; #upgrade; #install
                            canister_id = _maker;
                        });
                        return ?_maker;
                    };
                };
            };
            case(_){};
        };
        return null;
    };
    // permissions: Dao
    public shared(msg) func maker_setWasm(_wasm: Blob, _version: Text, _append: Bool, _backupPreVersion: Bool) : async (){
        assert(_onlyOwner(msg.caller));
        if (not(_append)){
            if (_backupPreVersion){
                maker_wasm_preVersion := maker_wasm;
            };
            maker_wasm := Blob.toArray(_wasm);
            maker_wasmVersion := _version;
        }else{
            assert(_version == maker_wasmVersion);
            maker_wasm := Tools.arrayAppend(maker_wasm, Blob.toArray(_wasm));
        };
    };
    public query func maker_getWasmVersion() : async (Text, Text, Nat){
        let offset = maker_wasm.size() / 2;
        var hash224 = SHA224.sha224(Tools.arrayAppend(Tools.slice(maker_wasm, 0, ?1024), Tools.slice(maker_wasm, offset, ?(offset+1024))));
        var crc : [Nat8] = CRC32.crc32(hash224);
        let hash = Tools.arrayAppend(crc, hash224);  
        return (maker_wasmVersion, Hex.encode(hash), maker_wasm.size());
    };
    public query func maker_getPublicMakers(_pair: ?Principal, _page: ?Nat, _size: ?Nat) : async TrieList<PairCanister, [(Principal, AccountId)]>{
        switch(_pair){
            case(?(pairCanisterId)){
                switch(Trie.get(maker_publicCanisters, keyp(pairCanisterId), Principal.equal)){
                    case(?(items)){ return {data = [(pairCanisterId, items)]; totalPage = 1; total = 1; } };
                    case(_){ return {data = []; totalPage = 0; total = 0; } };
                };
            };
            case(_){
                var trie = maker_publicCanisters;
                let page = Option.get(_page, 1);
                let size = Option.get(_size, 100);
                return trieItems(trie, page, size);
            };
        };
    };
    public query func maker_getPrivateMakers(_account: AccountId, _page: ?Nat, _size: ?Nat) : async TrieList<PairCanister, [(Principal, AccountId)]>{
        var trie = Trie.mapFilter(maker_privateCanisters, func (k: PairCanister, v: [(Principal, AccountId)]): ?[(Principal, AccountId)]{
            let items = Array.filter(v, func (t: (Principal, AccountId)): Bool{ t.1 == _account});
            if (items.size() > 0){ ?items } else { null };
        });
        let page = Option.get(_page, 1);
        let size = Option.get(_size, 100);
        return trieItems(trie, page, size);
    };
    // permissions: Dao, NFT#NEPTUNE,#URANUS,#SATURN
    public shared(msg) func maker_create(_arg: {
            pair: Principal;
            allow: {#Public; #Private};
            name: Text; // "AAA_BBB DeMM-1"
            lowerLimit: Nat; //Price
            upperLimit: Nat; //Price
            spreadRate: Nat; // e.g. 10000, ppm  x/1000000
            threshold: Nat; // e.g. 1000000000000 token1, After the total liquidity exceeds this threshold, the LP adds liquidity up to a limit of volFactor times his trading volume.
            volFactor: Nat; // e.g. 2
        }): async (canister: Principal){
        let accountId = Tools.principalToAccountBlob(msg.caller, null);
        assert(_onlyNFTHolder(accountId, null, ?#NEPTUNE) or _onlyNFTHolder(accountId, null, ?#URANUS) or _onlyNFTHolder(accountId, null, ?#SATURN) or _onlyOwner(msg.caller));
        assert(_arg.lowerLimit > 0 and _arg.upperLimit > _arg.lowerLimit);
        assert(_arg.spreadRate >= 1000);
        assert(maker_wasm.size() > 0);
        if(not(_onlyOwner(msg.caller)) and _countMaker(accountId, #All) > 3){
            throw Error.reject("You can create up to 3 Maker Canisters per account.");
        };
        let pairActor: ICDexPrivate.Self = actor(Principal.toText(_arg.pair));
        let pairSetting = await pairActor.getConfig();
        let unitSize = pairSetting.UNIT_SIZE;
        let info = await pairActor.info();
        // charge fee
        let token: ICRC1.Self = actor(Principal.toText(sysToken));
        let result = await token.icrc2_transfer_from({
            spender_subaccount = null; // *
            from = {owner = msg.caller; subaccount = null};
            to = {owner = Principal.fromActor(this); subaccount = null};
            amount = creatingMakerFee;
            fee = null;
            memo = null;
            created_at_time = null;
        });
        switch(result){
            case(#Ok(blockNumber)){};
            case(#Err(e)){
                throw Error.reject("Error: Error when paying the fee for creating a trading pair."); 
            };
        };
        // create
        try{
            Cycles.add(canisterCyclesInit);
            let canister = await ic.create_canister({ settings = null });
            let makerCanister = canister.canister_id;
            let args: [Nat8] = Blob.toArray(to_candid({
                creator = accountId;
                allow = _arg.allow;
                pair = _arg.pair;
                unitSize = unitSize;
                name = _arg.name;
                token0 = info.token0.0;
                token0Std = info.token0.2;
                token1 = info.token1.0;
                token1Std = info.token1.2;
                lowerLimit = _arg.lowerLimit; //Price
                upperLimit = _arg.upperLimit; //Price
                spreadRate = _arg.spreadRate; // ppm  x/1000000
                threshold = _arg.threshold;
                volFactor = _arg.volFactor; // multi 
            }: Maker.InitArgs));
            await ic.install_code({
                arg : [Nat8] = args;
                wasm_module = maker_wasm;
                mode = #install; // #reinstall; #upgrade; #install
                canister_id = makerCanister;
            });
            var controllers: [Principal] = [makerCanister, blackhole, Principal.fromActor(this)]; 
            if (_arg.allow == #Private){
                controllers := Tools.arrayAppend(controllers, [msg.caller]);
            };
            let settings = await ic.update_settings({
                canister_id = makerCanister; 
                settings={ 
                    compute_allocation = null;
                    controllers = ?controllers;
                    freezing_threshold = null;
                    memory_allocation = null;
                };
            });
            if (_arg.allow == #Public){
                _putPublicMaker(_arg.pair, makerCanister, accountId);
            }else{
                _putPrivateMaker(_arg.pair, makerCanister, accountId);
            };
            cyclesMonitor := await* CyclesMonitor.put(cyclesMonitor, makerCanister);
            return makerCanister;
        }catch(e){
            if (creatingMakerFee > sysTokenFee){
                let r = await token.icrc1_transfer({
                    from_subaccount = null;
                    to = {owner = msg.caller; subaccount = null};
                    amount = Nat.sub(creatingMakerFee, sysTokenFee);
                    fee = null;
                    memo = null;
                    created_at_time = null;
                });
            };
            throw Error.reject(Error.message(e));
        };
    };
    // permissions: Dao, Private Maker Creator
    public shared(msg) func maker_update(_pair: Principal, _maker: Principal, _name:?Text, _version: Text): async (canister: ?Principal){
        let accountId = Tools.principalToAccountBlob(msg.caller, null);
        assert(_onlyOwner(msg.caller) or (not(_isPublicMaker(_pair, _maker)) and _OnlyMakerCreator(_pair, _maker, accountId))); 
        assert(_version == maker_wasmVersion);
        return await* _maker_update(_pair, _maker, maker_wasm, #upgrade, { name = _name });
    };
    // permissions: Dao, Private Maker Creator
    public shared(msg) func maker_rollback(_pair: Principal, _maker: Principal): async (canister: ?Principal){
        let accountId = Tools.principalToAccountBlob(msg.caller, null);
        assert(_onlyOwner(msg.caller) or (not(_isPublicMaker(_pair, _maker)) and _OnlyMakerCreator(_pair, _maker, accountId)));
        return await* _maker_update(_pair, _maker, maker_wasm_preVersion, #upgrade, { name = null });
    };
    // permissions: Dao, Private Maker Creator
    public shared(msg) func maker_remove(_pair: Principal, _maker: Principal): async (){
        let accountId = Tools.principalToAccountBlob(msg.caller, null);
        assert(_onlyOwner(msg.caller) or (not(_isPublicMaker(_pair, _maker)) and _OnlyMakerCreator(_pair, _maker, accountId)));
        let makerActor: Maker.Self = actor(Principal.toText(_maker));
        let paused = await makerActor.setPause(true);
        await makerActor.deleteGridOrder();
        await makerActor.cancelAllOrders();
        ignore await makerActor.setPause(false);
        _removePublicMaker(_pair, _maker);
        _removePrivateMaker(_pair, _maker);
        cyclesMonitor := CyclesMonitor.remove(cyclesMonitor, _maker);
    };
    // permissions: Dao
    public shared(msg) func maker_setControllers(_pair: Principal, _maker: Principal, _controllers: [Principal]): async Bool{
        let accountId = Tools.principalToAccountBlob(msg.caller, null);
        assert(_onlyOwner(msg.caller));
        assert(Option.isSome(Array.find(_controllers, func (t: Principal): Bool{ t == Principal.fromActor(this) })));
        let settings = await ic.update_settings({
            canister_id = _maker; 
            settings={ 
                compute_allocation = null;
                controllers = ?_controllers; 
                freezing_threshold = null;
                memory_allocation = null;
            };
        });
        return true;
    };
    // permissions: Dao
    public shared(msg) func maker_config(_maker: Principal, _config: Maker.Config) : async Bool{ 
        assert(_onlyOwner(msg.caller));
        let makerActor: Maker.Self = actor(Principal.toText(_maker));
        await makerActor.config(_config);
    };
    public shared(msg) func maker_transactionLock(_maker: Principal, _act: {#lock; #unlock}) : async Bool{ 
        assert(_onlyOwner(msg.caller));
        let makerActor: Maker.Self = actor(Principal.toText(_maker));
        await makerActor.transactionLock(_act);
    };
    public shared(msg) func maker_setPause(_maker: Principal, _pause: Bool) : async Bool{ 
        assert(_onlyOwner(msg.caller));
        let makerActor: Maker.Self = actor(Principal.toText(_maker));
        await makerActor.setPause(_pause);
    };
    public shared(msg) func maker_resetLocalBalance(_maker: Principal) : async Maker.PoolBalance{ 
        assert(_onlyOwner(msg.caller));
        let makerActor: Maker.Self = actor(Principal.toText(_maker));
        await makerActor.resetLocalBalance();
    };
    public shared(msg) func maker_dexWithdraw(_maker: Principal, _token0: Nat, _token1: Nat) : async (token0: Nat, token1: Nat){ 
        assert(_onlyOwner(msg.caller));
        let makerActor: Maker.Self = actor(Principal.toText(_maker));
        await makerActor.dexWithdraw(_token0, _token1);
    };
    public shared(msg) func maker_dexDeposit(_maker: Principal, _token0: Nat, _token1: Nat) : async (token0: Nat, token1: Nat){ 
        assert(_onlyOwner(msg.caller));
        let makerActor: Maker.Self = actor(Principal.toText(_maker));
        await makerActor.dexDeposit(_token0, _token1);
    };
    public shared(msg) func maker_deleteGridOrder(_maker: Principal) : async (){ 
        assert(_onlyOwner(msg.caller));
        let makerActor: Maker.Self = actor(Principal.toText(_maker));
        await makerActor.deleteGridOrder();
    };
    public shared(msg) func maker_createGridOrder(_maker: Principal) : async (){ 
        assert(_onlyOwner(msg.caller));
        let makerActor: Maker.Self = actor(Principal.toText(_maker));
        await makerActor.createGridOrder();
    };
    public shared(msg) func maker_cancelAllOrders(_maker: Principal) : async (){ 
        assert(_onlyOwner(msg.caller));
        let makerActor: Maker.Self = actor(Principal.toText(_maker));
        await makerActor.cancelAllOrders();
    };

    /* =======================
      Cycles monitor
    ========================= */
    public shared(msg) func monitor_put(_canisterId: Principal): async (){
        assert(_onlyOwner(msg.caller));
        cyclesMonitor := await* CyclesMonitor.put(cyclesMonitor, _canisterId);
    };
    public shared(msg) func monitor_remove(_canisterId: Principal): async (){
        assert(_onlyOwner(msg.caller));
        cyclesMonitor := CyclesMonitor.remove(cyclesMonitor, _canisterId);
    };
    public query func monitor_canisters(): async [(Principal, Nat)]{
        return Iter.toArray(Trie.iter(cyclesMonitor));
    };
    public shared(msg) func debug_canister_status(_canisterId: Principal): async CyclesMonitor.canister_status {
        assert(_onlyOwner(msg.caller));
        return await* CyclesMonitor.get_canister_status(_canisterId);
    };
    public shared(msg) func debug_monitor(): async (){
        assert(_onlyOwner(msg.caller));
        if (Trie.size(cyclesMonitor) == 0){
            for ((canisterId, value) in Trie.iter(cyclesMonitor)){
                try{
                    cyclesMonitor := await* CyclesMonitor.put(cyclesMonitor, canisterId);
                }catch(e){};
            };
        };
        cyclesMonitor := await* CyclesMonitor.monitor(Principal.fromActor(this), cyclesMonitor, canisterCyclesInit, canisterCyclesInit * 50, 500000000);
    };

    /* =======================
      DRC207
    ========================= */
    /// DRC207 support
    public query func drc207() : async DRC207.DRC207Support{
        return {
            monitorable_by_self = false;
            monitorable_by_blackhole = { allowed = true; canister_id = ?Principal.fromText("7hdtw-jqaaa-aaaak-aaccq-cai"); };
            cycles_receivable = true;
            timer = { enable = false; interval_seconds = ?(4*3600); }; 
        };
    };
    /// canister_status
    // public func canister_status() : async DRC207.canister_status {
    //     let ic : DRC207.IC = actor("aaaaa-aa");
    //     await ic.canister_status({ canister_id = Principal.fromActor(this) });
    // };
    /// receive cycles
    public func wallet_receive(): async (){
        let amout = Cycles.available();
        let accepted = Cycles.accept(amout);
    };
    /// timer tick
    // public func timer_tick(): async (){
    //     let f = monitor();
    // };

    /* =======================
      Timer
    ========================= */
    private func timerLoop() : async (){
        if (_now() > lastMonitorTime + 6 * 3600){
            try{ 
                cyclesMonitor := await* CyclesMonitor.monitor(Principal.fromActor(this), cyclesMonitor, canisterCyclesInit, canisterCyclesInit * 50, 0);
                lastMonitorTime := _now();
            }catch(e){};
            for ((canisterId, totalCycles) in Trie.iter(cyclesMonitor)){
                if (totalCycles >= canisterCyclesInit * 10 and Option.isNull(List.find(hotPairs, func(t: Principal): Bool{ t == canisterId }))){
                    try{ 
                        let canisterStatus = await* CyclesMonitor.get_canister_status(canisterId);
                        if (canisterStatus.memory_size > pairMaxMemory){
                            let pair: ICDexPrivate.Self = actor(Principal.toText(canisterId));
                            ignore await pair.config({
                                UNIT_SIZE = null;
                                ICP_FEE = null;
                                TRADING_FEE = null;
                                MAKER_BONUS_RATE = null;
                                MAX_TPS = null; 
                                MAX_PENDINGS = null;
                                STORAGE_INTERVAL = null; // seconds
                                ICTC_RUN_INTERVAL = null; // seconds
                                ORDER_EXPIRATION_DURATION = ?(2 * 30 * 24 * 3600) // seconds
                            });
                            ignore await pair.drc205_config({
                                EN_DEBUG = null;
                                MAX_CACHE_TIME = ?(2 * 30 * 24 * 3600 * 1000000000);
                                MAX_CACHE_NUMBER_PER = ?600;
                                MAX_STORAGE_TRIES = null;
                            });
                            hotPairs := List.push(canisterId, hotPairs);
                        };
                    }catch(e){};
                };
            };
            for (canisterId in List.toArray(hotPairs).vals()){
                try{ 
                    let pair: ICDexPrivate.Self = actor(Principal.toText(canisterId));
                    await pair.ictc_clearLog(?(2 * 30 * 24 * 3600 * 1000000000), false);
                }catch(e){};
            };
        };
    };
    private var timerId: Nat = 0;
    public shared(msg) func timerStart(_intervalSeconds: Nat): async (){
        assert(_onlyOwner(msg.caller));
        Timer.cancelTimer(timerId);
        timerId := Timer.recurringTimer(#seconds(_intervalSeconds), timerLoop);
    };
    public shared(msg) func timerStop(): async (){
        assert(_onlyOwner(msg.caller));
        Timer.cancelTimer(timerId);
    };

    /* =======================
      Upgrade
    ========================= */
    system func preupgrade() {
        Timer.cancelTimer(timerId);
    };
    system func postupgrade() {
        timerId := Timer.recurringTimer(#seconds(3*3600), timerLoop); //  /*config*/
    };

};