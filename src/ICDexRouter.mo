/**
 * Actor      : ICDexRouter
 * Author     : ICLighthouse Team
 * Stability  : Experimental
 * Github     : https://github.com/iclighthouse/ICDex/
 */
///
/// ## Overview
///
/// ICDexRouter is a factory that is responsible for creating and managing ICDexPair, and also for creating and managing ICDexMaker.
///
/// ## 1 Concepts
/// 
/// ### Owner (DAO)
///
/// Owner is the controller of the ICDexRouter, the initial value is creator, which can be modified to DAO canister for decentralization.
///
/// ### System Token (Eco-Token, ICL)
///
/// System Token is ICDex's economic incentive token, i.e. ICL, a governance and utility token.
///
/// ### ICDexPair (Trading Pair, TP)
///
/// ICDexPair, Trading Pair (TP), is deployed in a separate canister, managed by ICDexRouter. For example, the TP "AAA/BBB", 
/// AAA means base token and BBB eans quote token.
///
/// ### ICDexMaker (Orderbook Automated Market Maker, OAMM)
///
/// ICDexMaker is Orderbook Automated Market Maker (OAMM) canister that provides liquidity to a trading pair. An OAMM is deployed 
/// in a separate canister that is managed by ICDexRouter.  OAMM simulates the effect of Uniswap AMM using grid strategy orders. 
/// It includes Public Maker and Private Maker:
/// - Public Maker is the public market making pool to which any user (LP) can add liquidity.
/// - Private Maker is a private market making pool to which only the creator (LP) can add liquidity.
///
/// ### NFT
///
/// The NFT collection ICLighthouse Planet Cards (goncb-kqaaa-aaaap-aakpa-cai) has special qualifications for some of the features 
/// of ICDex, in addition to its own NFT properties. NFT holders of #NEPTUNE,#URANUS,#SATURN have the qualification to create an 
/// ICDexMaker; NFT holders of #NEPTUNE have the permission to bind a Vip-maker role.
///
/// ## 2 Deployment
///
/// ### Deploy ICDexRouter
/// args:
/// - initDAO: Principal.  // Owner (DAO) principal
///
/// ### (optional) Config ICDexRouter
/// - call sys_config()
/// ```
/// args: { // (If you fill in null for item, it means that this item will not be modified.)
///     aggregator: ?Principal; // External trading pair aggregator. If not configured, it will not affect use.
///     blackhole: ?Principal; // Black hole canister, which can be used as a controller for canisters to monitor their cycles and memory.
///     icDao: ?Principal; // Owner (DAO) principal. The canister that governs ICDex is assigned the value initDAO at installation. a private principal can be filled in testing.
///     nftPlanetCards: ?Principal; // ICLighthouse NFT.
///     sysToken: ?Principal; // ICDex governance token canister-id.
///     sysTokenFee: ?Nat; // smallest units. Transfer fee for ICDex governance token.
///     creatingPairFee: ?Nat; // smallest units. The fee to be paid for creating a trading pair by pubCreate().
///     creatingMakerFee: ?Nat; // smallest units. The fee to be paid for creating an automated market maker pool canister.
/// }
/// ```
///
/// ## 3 Fee model
///
/// - Creating ICDexPair: The user creates an ICDexPair and will be charged creatingPairFee (initial value is 5000 ICL); Owner (DAO) 
/// creates ICDexPair and is not charged.
/// - Creating ICDexMaker: The user creates an ICDexMaker and will be charged creatingMakerFee (initial value is 50 ICL).
///
/// ## 4 Core functionality
///
/// ### Trading pair creation and governance
///
/// - Trading pair creation: ICDexRouter is the contract factory for ICDexPair. Users can pay a fee (ICL) to create a trading pair; 
/// and Owner (DAO) can create a trading pair directly.
/// - Trading pair governance: The management of trading pairs by the Owner (DAO) includes upgrading, modifying the controller, 
/// and adding (deleting) the list of trading pairs, etc. ICDexRouter wraps the methods related to the governance of trading pair, so that 
/// the trading pair methods can be called through ICDexRouter to realize the governance.
///
/// ### Automated market maker creation and governance
/// 
/// - Automated market maker creation: ICDexRouter is the contract factory for ICDexMaker. To create an automated market maker the user 
/// needs to have an NFT ICLighthouse Planet Card with #NEPTUNE,#URANUS or #SATURN and pay a fee (ICL). Owner (DAO) can create an 
/// automated market maker directly.
/// - Automated market maker governance: The management of Automated market makers by the Owner (DAO) includes upgrading, modifying the 
/// controller, and setting up vip-maker qualifications, etc. ICDexRouter wraps the methods related to the governance of automated market 
/// maker, so that the automated market maker methods can be called through ICDexRouter to realize the governance.
///
/// ### NFT binding
///
/// Users who deposit NFTs into the ICDexRouter are granted specific qualifications, and some operations require locking the NFT. 
/// The currently supported NFT is ICLighthouse Planet Cards (goncb-kqaaa-aaaap-aakpa-cai), and qualifications that can be granted for 
/// the operations include:
/// - Creating an automated market maker canister: Accounts that have an NFT card with #NEPTUNE, #URANUS or #SATURN deposited into 
/// the ICDexRouter will be qualified to create an automated market maker canister.
/// - Binding vip-maker qualifications: An account that has an NFT card with #NEPTUNE, #URANUS or #SATURN deposited into the ICDexRouter 
/// can set up to 5 target accounts as vip-maker roles, which will receive rebates when trading as maker roles. If the holder of the NFT 
/// removes the NFT from ICDexRouter, all the vip-maker roles he has bound will be invalidated.
///
/// ### ICTC governance
/// 
/// Both ICDexPair and ICDexMaker use the ICTC module. In normal circumstances, ICTC completes transactions and automatically 
/// compensates for them, but under abnormal conditions, transactions are blocked and need to be compensated for through governance. 
/// If more than 5 transaction orders are blocked and not resolved, ICDexPair or ICDexMaker will be in a suspended state waiting for 
/// processing. ICTC accomplishes governance in two ways:
/// - The DAO calls the ICDexRouter's methods starting with "pair_ictc" to complete the governance of the ICDexPair or ICDexMaker, 
/// and these operations are logged in the ICDexRouter's Events, which is the preferred way.
/// - Set the DAO canister-id to the controller of ICDexPair/ICDexMaker or to the ICTCAdmin of ICDexPair/ICDexMaker. then the DAO can 
/// directly call the methods of ICDexPair or ICDexMaker that start with "ictc_" to complete the governance. This way of operations 
/// have more authority, only go to this way when the previous way can not complete the governance, the disadvantage is that you can 
/// not record Events in the ICDexRouter.
///
/// ### Eco-economy
/// 
/// Various fees charged in ICDex are held in account `{ owner = ICDexRouter_canister_id; subaccount = null }`, a part of them is owned 
/// by the platform, and their main use is for transferring to an account for risk reserve, transferring to a blackhole account, 
/// trading in pairs (e.g., making a market, buying a certain token).
///
/// ### Trading pair snapshots (backup and recovery)
///
/// ICDexRouter manages data snapshots of trading pairs. It is mainly used for backup and recovery of trading pairs, backing up data 
/// snapshots to another canister for some operations, such as airdrops.
///
/// ### Events
///
/// Operations that call the core methods of the ICDexRouter and produce a state change are recorded in the Events system, sorted by 
/// ascending id number, making it easy for ecological participants to follow the behavior of the ICDexRouter. Older events may be 
/// deleted if the ICDexRouter's memory is heavily consumed, so someone could store the event history as needed.
///
/// ### Cycles monitor
///
/// The CyclesMonitor module is used to monitor the Cycles balance and memory usage of trading pair and automated market maker 
/// canisters. The ICDexRouter will automatically top up Cycles for the monitored canisters, provided that the ICDexRouter has 
/// sufficient Cycles balance or ICP balance.
///
/// ## 5 API
///
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
import MakerBackup "./lib/MakerBackupTypes";
import Timer "mo:base/Timer";
import Error "mo:base/Error";
import CF "mo:icl/CF";
import CyclesMonitor "mo:icl/CyclesMonitor";
import Maker "mo:icl/ICDexMaker";
import EventTypes "./lib/EventTypes";
import ICEvents "mo:icl/ICEvents";

shared(installMsg) actor class ICDexRouter(initDAO: Principal, isDebug: Bool) = this {
    type Txid = T.Txid;  // Blob
    type AccountId = T.AccountId; // Blob
    type Address = T.Address; // Text
    type Nonce = T.Nonce; // Nat
    type DexName = T.DexName; // Text
    type TokenStd = T.TokenStd; // Variant{....}
    type TokenSymbol = T.TokenSymbol; // Text
    type TokenInfo = T.TokenInfo;
    type PairCanister = T.PairCanister; // Principal
    type SwapPair = T.SwapPair; // Data structure for trading pair information.
    type TrieList<K, V> = T.TrieList<K, V>; // [(K, V)]
    type InstallMode = {#reinstall; #upgrade; #install};
    type Timestamp = Nat; // seconds
    type BlockHeight = EventTypes.BlockHeight; // Nat
    type Event = EventTypes.Event; // Event data structure of the ICEvents module.

    private var icdex_debug : Bool = isDebug; /*config*/
    private let version_: Text = "0.12.20";
    private var ICP_FEE: Nat64 = 10_000; // e8s 
    private let ic: IC.Self = actor("aaaaa-aa");
    private var cfAccountId: AccountId = Blob.fromArray([]);
    // Blackhole
    // Blackhole canister-id acts as a controller for a canister and is used to monitor its canister_status, can be reconfigured.
    // blackhole canister: 7hdtw-jqaaa-aaaak-aaccq-cai
    // ModuleHash(dfx: 0.8.4): 603692eda4a0c322caccaff93cf4a21dc44aebad6d71b40ecefebef89e55f3be
    // Github: https://github.com/iclighthouse/ICMonitor/blob/main/Blackhole.mo
    private var blackhole: Principal = Principal.fromText("7hdtw-jqaaa-aaaak-aaccq-cai");
    // Governance canister-id, can be reconfigured.
    private stable var icDao: Principal = initDAO;
    // Aggregator: External trading pair catalog listings, which are not substantive dependencies of ICDex, can be reconfigured.
    private stable var aggregator: Text = "i2ied-uqaaa-aaaar-qaaza-cai"; // pwokq-miaaa-aaaak-act6a-cai
    if (icdex_debug){
        aggregator := "pwokq-miaaa-aaaak-act6a-cai";
    };
    // ICLighthouse Planet NFT, can be reconfigured.
    private stable var nftPlanetCards: Principal = Principal.fromText("goncb-kqaaa-aaaap-aakpa-cai");
    // ICDex's governance token that can be reconfigured.
    private stable var sysToken: Principal = Principal.fromText("5573k-xaaaa-aaaak-aacnq-cai"); // will be configured as an SNS token
    private stable var sysTokenFee: Nat = 1_000_000; // 0.01 ICL
    private stable var creatingPairFee: Nat = 500_000_000_000; // 5000 ICL
    private stable var creatingMakerFee: Nat = 5_000_000_000; // 50 ICL
    private stable var pause: Bool = false; // Most of the operations will be disabled when it is in the paused state (pause = true).
    // - private stable var owner: Principal = installMsg.caller;
    private stable var pairs: Trie.Trie<PairCanister, SwapPair> = Trie.empty(); // Trading Pair Information List
    private stable var wasm: [Nat8] = []; // ICDexPair wasm
    private stable var wasm_preVersion: [Nat8] = []; // Pre-version wasm of ICDexPair
    private stable var wasmVersion: Text = ""; // Name of the current version of ICDexPair wasm
    private stable var IDOPairs = List.nil<Principal>(); // List of trading pairs with IDO enabled
    // ICDexMaker
    private stable var maker_wasm: [Nat8] = []; // ICDexMaker wasm
    private stable var maker_wasm_preVersion: [Nat8] = []; // // Pre-version wasm of ICDexMaker
    private stable var maker_wasmVersion: Text = ""; // Name of the current version of ICDexMaker wasm
    // List of public maker canisters (Everyone can add liquidity)
    private stable var maker_publicCanisters: Trie.Trie<PairCanister, [(maker: Principal, creator: AccountId)]> = Trie.empty(); 
    // List of private maker canisters (Only the creator can add liquidity)
    private stable var maker_privateCanisters: Trie.Trie<PairCanister, [(maker: Principal, creator: AccountId)]> = Trie.empty(); 
    // Events
    private stable var eventBlockIndex : BlockHeight = 0; // ID. Consecutive incremental event index number
    private stable var firstBlockIndex : BlockHeight = 0; // The id of the first event that remains after the data has been cleared
    private stable var icEvents : ICEvents.ICEvents<Event> = Trie.empty(); // Event records
    private stable var icAccountEvents : ICEvents.AccountEvents = Trie.empty(); // Relationship index table for accounts and events
    // Monitor
    private stable var cyclesMonitor: CyclesMonitor.MonitoredCanisters = Trie.empty(); // (For upgrade) List of canisters with monitored status
    private stable var lastMonitorTime: Nat = 0;
    private stable var hotPairs : List.List<Principal> = List.nil(); // The more popular pairs, they may take up more memory and need to be cleaned up.
    private let canisterCyclesInit : Nat = if (icdex_debug) {200_000_000_000} else {2_000_000_000_000}; // Initialized Cycles amount when creating a trading pair.
    private let monitor = CyclesMonitor.CyclesMonitor(canisterCyclesInit, canisterCyclesInit * 50, 1_000_000_000); // CyclesMonitor object
    // private let pairMaxMemory: Nat = 2*1000*1000*1000; // When the trading pair memory exceeds this value it signals risk.

    private func keyp(t: Principal) : Trie.Key<Principal> { return { key = t; hash = Principal.hash(t) }; };
    private func keyn(t: Nat) : Trie.Key<Nat> { return { key = t; hash = Tools.natHash(t) }; };
    private func keyb(t: Blob) : Trie.Key<Blob> { return { key = t; hash = Blob.hash(t) }; };
    private func keyt(t: Text) : Trie.Key<Text> { return { key = t; hash = Text.hash(t) }; };
    private func trieItems<K, V>(_trie: Trie.Trie<K,V>, _page: Nat, _size: Nat) : TrieList<K, V> {
        return Tools.trieItems(_trie, _page, _size);
    };
    
    /* 
    * Local Functions
    */
    private func _now() : Timestamp{
        return Int.abs(Time.now() / 1_000_000_000);
    };
    private func _onlyOwner(_caller: Principal) : Bool { 
        return _caller == icDao or Principal.isController(_caller);
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
    // Convert principal and account-id in Text format to accountId in Blob format.
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
    // private func _drc20Transfer(_token: Principal, _to: AccountId, _value: Nat) : async Bool{
    //     let token0: DRC20.Self = actor(Principal.toText(_token));
    //     let res = await token0.drc20_transfer(_accountIdToHex(_to), _value, null,null,null);
    //     switch(res){
    //         case(#ok(txid)){ return true; };
    //         case(#err(e)){ return false; };
    //     };
    // };
    private func _syncFee(_pairId: Principal) : async (){
        let pair: ICDexTypes.Self = actor(Principal.toText(_pairId));
        let feeRate = (await pair.fee()).taker.sell;
        switch(Trie.get(pairs, keyp(_pairId), Principal.equal)){
            case(?pair){
                pairs := Trie.put(pairs, keyp(_pairId), Principal.equal, {
                    token0 = pair.token0; 
                    token1 = pair.token1; 
                    dexName = pair.dexName; 
                    canisterId = _pairId; 
                    feeRate = feeRate; 
                }).0;
            };
            case(_){};
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
    
    // Convert Hex to [Nat8], ignoring failures
    private func _hexToBytes(_hex: Text) : [Nat8]{
        switch(Hex.decode(_hex)){
            case(#ok(v)){ return v };
            case(#err(e)){ return [] };
        };
    };

    // Candid encoding of arguments
    private func _generateArg(_token0: Principal, _token1: Principal, _unitSize: Nat64, _pairName: Text) : [Nat8]{
        let arg : ICDexTypes.InitArgs = {
            name = _pairName;
            token0 = _token0;
            token1 = _token1;
            unitSize = _unitSize;
            owner = ?Principal.fromActor(this);
        };
        return Blob.toArray(to_candid(arg, icdex_debug));
    };

    // Get the standard type of the token and other information by trying to query it.
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

    // Create a new trading pair. See the document for ICDexPair for the parameter _unitSize.
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
        let tokenInfo0 = await _testToken(token0Principal); //{symbol: Text; decimals: Nat8; std: ICDexTypes.TokenStd}
        token0Symbol := tokenInfo0.symbol;
        token0Decimals := tokenInfo0.decimals;
        token0Std := tokenInfo0.std;
        assert(token0Std == #drc20 or token0Std == #icrc1 or token0Std == #icp);
        let tokenInfo1 = await _testToken(token1Principal); //{symbol: Text; decimals: Nat8; std: ICDexTypes.TokenStd}
        token1Symbol := tokenInfo1.symbol;
        token1Decimals := tokenInfo1.decimals;
        token1Std := tokenInfo1.std;
        assert(token1Std == #drc20 or token1Std == #icrc1 or token1Std == #icp);
        swapName := "icdex:" # token0Symbol # "/" # token1Symbol;

        // create
        let addCycles : Nat = Option.get(_initCycles, canisterCyclesInit);
        Cycles.add(addCycles);
        let canister = await ic.create_canister({ settings = null });
        let pairCanister = canister.canister_id;
        var unitSize = Nat64.fromNat(10 ** Nat.min(Nat.sub(Nat.max(Nat8.toNat(token0Decimals), 1), 1), 19)); // max 10**19
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
        var controllers: [Principal] = [icDao, blackhole, Principal.fromActor(this)];
        if (icdex_debug){
            controllers := [icDao, blackhole, Principal.fromActor(this), installMsg.caller];
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
        let router: Router.Self = actor(aggregator);
        try{ // Used to push pair to external directory listings, if it fails it has no effect on ICDex.
            await router.putByDex(
                (token0Principal, token0Symbol, token0Std), 
                (token1Principal, token1Symbol, token1Std), 
                pairCanister);
        }catch(e){};
        // cyclesMonitor := await* CyclesMonitor.put(cyclesMonitor, pairCanister);
        await* monitor.putCanister(pairCanister);
        return pairCanister;
    };

    // Upgrade a trading pair canister
    private func _update(_pair: Principal, _wasm: [Nat8], _mode: InstallMode) : async* (canister: ?PairCanister){
        switch(Trie.get(pairs, keyp(_pair), Principal.equal)){
            case(?(pair)){
                let pairActor: ICDexPrivate.Self = actor(Principal.toText(_pair));
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
                let tokenInfo0 = await _testToken(token0Principal); //{symbol: Text; decimals: Nat8; std: ICDexTypes.TokenStd}
                token0Symbol := tokenInfo0.symbol;
                token0Decimals := tokenInfo0.decimals;
                token0Std := tokenInfo0.std;
                let tokenInfo1 = await _testToken(token1Principal); //{symbol: Text; decimals: Nat8; std: ICDexTypes.TokenStd}
                token1Symbol := tokenInfo1.symbol;
                token1Decimals := tokenInfo1.decimals;
                token1Std := tokenInfo1.std;
                swapName := pair.dexName # ":" # token0Symbol # "/" # token1Symbol;
                Cycles.add(canisterCyclesInit);
                var unitSize = Nat64.fromNat(10 ** Nat.min(Nat.sub(Nat.max(Nat8.toNat(token0Decimals), 1), 1), 19)); // max 10**19
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
                    feeRate: Float = (await pairActor.fee()).taker.sell; //  0.5%
                };
                pairs := Trie.put(pairs, keyp(pairCanister), Principal.equal, pairNew).0;
                let router: Router.Self = actor(aggregator);
                try{ // Used to push pair to external directory listings, if it fails it has no effect on ICDex.
                    await router.putByDex(
                        (token0Principal, token0Symbol, token0Std), 
                        (token1Principal, token1Symbol, token1Std), 
                        pairCanister);
                }catch(e){};
                return ?pairCanister;
            };
            case(_){
                return null;
            };
        };
    };

    /// Publicly create a trading pair by paying creatingPairFee.
    ///
    /// Arguments:
    /// - token0: Principal. Base token canister-id.
    /// - token1: Principal. Quote token canister-id.
    /// 
    /// Returns:
    /// - canister: PairCanister. Trading pair canister-id.
    public shared(msg) func pubCreate(_token0: Principal, _token1: Principal): async (canister: PairCanister){
        assert(not(_isExistedByToken(_token0, _token1)));
        let token: ICRC1.Self = actor(Principal.toText(sysToken));
        let arg: ICRC1.TransferFromArgs = {
            spender_subaccount = null; // *
            from = {owner = msg.caller; subaccount = null};
            to = {owner = Principal.fromActor(this); subaccount = null};
            amount = creatingPairFee;
            fee = null;
            memo = null;
            created_at_time = null;
        };
        let result = await token.icrc2_transfer_from(arg);
        ignore _putEvent(#chargeFee({ token = sysToken; arg = arg; result = result; }), ?Tools.principalToAccountBlob(msg.caller, null));
        switch(result){
            case(#Ok(blockNumber)){
                try{
                    let canisterId = await* _create(_token0, _token1, null, null);
                    let pairActor: ICDexPrivate.Self = actor(Principal.toText(canisterId));
                    ignore await pairActor.setPause(false, null);
                    ignore _putEvent(#createPairByUser({ token0 = _token0; token1 = _token1; pairCanisterId = canisterId }), ?Tools.principalToAccountBlob(msg.caller, null));
                    ignore _putEvent(#pairStart({ pair = canisterId; message = ?"Pair is launched." }), ?Tools.principalToAccountBlob(Principal.fromActor(this), null));
                    return canisterId;
                }catch(e){
                    if (creatingPairFee > sysTokenFee){
                        let arg: ICRC1.TransferArgs = {
                            from_subaccount = null;
                            to = {owner = msg.caller; subaccount = null};
                            amount = Nat.sub(creatingPairFee, sysTokenFee);
                            fee = null;
                            memo = null;
                            created_at_time = null;
                        };
                        let r = await token.icrc1_transfer(arg);
                        ignore _putEvent(#refundFee({ token = sysToken; arg = arg; result = r; }), ?Tools.principalToAccountBlob(msg.caller, null));
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

    /// Set the wasm of the ICDexPair.
    ///
    /// Arguments:
    /// - wasm: Blob. wasm file.
    /// - version: Text. The current version of wasm.
    /// - append: Bool. Whether to continue uploading the rest of the chunks of the same wasm file. If a wasm file is larger than 2M, 
    /// it can't be uploaded at once, the solution is to upload it in multiple chunks. `append` is set to false when uploading the 
    /// first chunk. `append` is set to true when uploading subsequent chunks, and version must be filled in with the same value.
    /// - backup: Bool. Whether to backup the previous version of wasm.
    /// 
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
        ignore _putEvent(#setICDexPairWasm({ version = _version; append = _append; backupPreVersion = _backup }), ?Tools.principalToAccountBlob(msg.caller, null));
    };

    /// Returns the current version of ICDexPair wasm.
    public query func getWasmVersion() : async (version: Text, hash: Text, size: Nat){
        let offset = wasm.size() / 2;
        var hash224 = SHA224.sha224(Tools.arrayAppend(Tools.slice(wasm, 0, ?1024), Tools.slice(wasm, offset, ?(offset+1024))));
        var crc : [Nat8] = CRC32.crc32(hash224);
        let hash = Tools.arrayAppend(crc, hash224); // Because the sha224 computation of the entire wasm will report an insufficient number of instructions to execute, a "strange" hash computation method has been adopted
        return (wasmVersion, Hex.encode(hash), wasm.size());
    };

    /* =======================
      Managing trading pairs
    ========================= */

    /// Create a new trading pair by governance.
    ///
    /// Arguments:
    /// - token0: Principal. Base token canister-id.
    /// - token1: Principal. Quote token canister-id.
    /// - unitSize: ?Nat64. Smallest units of base token when placing an order, the order's quantity must be an integer 
    /// multiple of UnitSize. See the ICDexPair documentation.
    /// - initCycles: ?Nat. The initial Cycles amount added to the new canister.
    /// 
    /// Returns:
    /// - canister: PairCanister. Trading pair canister-id.
    public shared(msg) func create(_token0: Principal, _token1: Principal, _unitSize: ?Nat64, _initCycles: ?Nat): async (canister: PairCanister){
        assert(_onlyOwner(msg.caller));
        let canisterId = await* _create(_token0, _token1, _unitSize, _initCycles);
        ignore _putEvent(#createPair({ token0 = _token0; token1 = _token1; unitSize = _unitSize; initCycles = _initCycles; pairCanisterId = canisterId }), ?Tools.principalToAccountBlob(msg.caller, null));
        return canisterId;
    };
    
    /// Upgrade a trading pair canister.
    ///
    /// Arguments:
    /// - pair: Principal. trading pair canister-id.
    /// - version: Text. Check the current version to be upgraded.
    /// 
    /// Returns:
    /// - canister: ?PairCanister. Trading pair canister-id. Returns null if the upgrade was unsuccessful.
    public shared(msg) func update(_pair: Principal, _version: Text): async (canister: ?PairCanister){
        assert(_onlyOwner(msg.caller));
        assert(wasm.size() > 0);
        assert(_version == wasmVersion);
        let res = await* _update(_pair, wasm, #upgrade);
        ignore _putEvent(#upgradePairWasm({ pair = _pair; version = _version; success = Option.isSome(res) }), ?Tools.principalToAccountBlob(msg.caller, null));
        return res;
    };

    /// Upgrade all ICDexPairs.  
    public shared(msg) func updateAll(_version: Text) : async {total: Nat; success: Nat; failures: [Principal]}{ 
        assert(_onlyOwner(msg.caller));
        assert(wasm.size() > 0);
        assert(_version == wasmVersion);
        var total : Nat = 0;
        var success : Nat = 0;
        var failures: [Principal] = [];
        for ((canisterId, info) in Trie.iter(pairs)){
            total += 1;
            try{
                let res = await* _update(canisterId, wasm, #upgrade);
                ignore _putEvent(#upgradePairWasm({ pair = canisterId; version = _version; success = Option.isSome(res) }), ?Tools.principalToAccountBlob(msg.caller, null));
                success += 1;
            }catch(e){
                failures := Tools.arrayAppend(failures, [canisterId]);
            };
        };
        return {total = total; success = success; failures = failures};
    };

    /// Rollback to previous version (the last version that was saved).  
    /// Note: Operate with caution.
    public shared(msg) func rollback(_pair: Principal): async (canister: ?PairCanister){
        assert(_onlyOwner(msg.caller));
        assert(wasm_preVersion.size() > 0);
        let pair : ICDexPrivate.Self = actor(Principal.toText(_pair));
        let info = await pair.info();
        assert(info.paused);
       let res = await* _update(_pair, wasm_preVersion, #upgrade);
       ignore _putEvent(#rollbackPairWasm({ pair = _pair; success = Option.isSome(res) }), ?Tools.principalToAccountBlob(msg.caller, null));
       return res;
    };

    /// Modifying the controllers of the trading pair.
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
        ignore _putEvent(#setPairControllers({ pair = _pair; controllers = _controllers }), ?Tools.principalToAccountBlob(msg.caller, null));
        return true;
    };

    /// Reinstall a trading pair canister which is paused.
    ///
    /// Arguments:
    /// - pair: Principal. trading pair canister-id.
    /// - version: Text. Check the current version to be upgraded.
    /// - snapshot: Bool. Whether to back up a snapshot.
    /// 
    /// Returns:
    /// - canister: ?PairCanister. Trading pair canister-id. Returns null if the upgrade was unsuccessful.
    /// Note: Operate with caution. Consider calling this method only if upgrading is not possible.
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

        ignore _putEvent(#reinstallPairWasm({ pair = _pair; version = _version; success = true; }), ?Tools.principalToAccountBlob(msg.caller, null));
        return res; //?Principal.fromText("");
    };

    /// Synchronize trading fees for all pairs.
    public shared(msg) func sync() : async (){ // sync fee
        assert(_onlyOwner(msg.caller));
        for ((canister, pair) in Trie.iter(pairs)){
            let f = await _syncFee(canister);
        };
    };
    
    /* =======================
      Data snapshots (backup & recovery)
    ========================= */

    private stable var backupData : [Backup.BackupResponse] = []; // temp for debug
    private stable var snapshots : Trie.Trie<PairCanister, List.List<(ICDexTypes.Timestamp, [Backup.BackupResponse])>> = Trie.empty(); // Snapshots of the trading pairs' data. 

    private func _setSnapshot(_pair: Principal, _backupData: [Backup.BackupResponse]): ICDexTypes.Timestamp{
        let now = _now();
        switch(Trie.get(snapshots, keyp(_pair), Principal.equal)){
            case(?list){
                snapshots := Trie.put(snapshots, keyp(_pair), Principal.equal, List.push((now, _backupData), list)).0;
            };
            case(_){
                snapshots := Trie.put(snapshots, keyp(_pair), Principal.equal, List.push((now, _backupData), null)).0;
            };
        };
        return now;
    };
    private func _removeSnapshot(_pair: Principal, _timeBefore: Timestamp): (){
        switch(Trie.get(snapshots, keyp(_pair), Principal.equal)){
            case(?list){
                let temp = List.filter(list, func(t: (Nat, [Backup.BackupResponse])): Bool{ t.0 > _timeBefore });
                snapshots := Trie.put(snapshots, keyp(_pair), Principal.equal, temp).0;
                ignore _putEvent(#removePairDataSnapshot({ pair = _pair; timeBefore = _timeBefore; }), ?Tools.principalToAccountBlob(Principal.fromActor(this), null));
            };
            case(_){};
        };
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
    // Returns the timestamps of all snapshots of a trading pair.
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
    // Get the data for a trading pair (it is recommended to pause the pair first).
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
        // let rounds = await pair.backup(#rounds);
        // backupData := Tools.arrayAppend(backupData, [rounds]);
        // let competitors = await pair.backup(#competitors);
        // backupData := Tools.arrayAppend(backupData, [competitors]);
        var sagaData = await pair.backup(#sagaData(#Base));
        try { sagaData := await pair.backup(#sagaData(#All)); } catch(e){};
        backupData := Tools.arrayAppend(backupData, [sagaData]);
        var drc205Data = await pair.backup(#drc205Data(#Base));
        try { drc205Data := await pair.backup(#drc205Data(#All)); } catch(e){};
        backupData := Tools.arrayAppend(backupData, [drc205Data]);
        let traderReferrerTemps = await pair.backup(#traderReferrerTemps);
        backupData := Tools.arrayAppend(backupData, [traderReferrerTemps]);
        // let ictcTaskCallbackEvents = await pair.backup(#ictcTaskCallbackEvents);
        // backupData := Tools.arrayAppend(backupData, [ictcTaskCallbackEvents]);
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

        assert(backupData.size() == 27);
        ignore _putEvent(#backupPairData({ pair = _pair; timestamp = _now(); }), ?Tools.principalToAccountBlob(Principal.fromActor(this), null));
        return backupData;
    };
    // Recover data for a trading pair.
    private func _recovery(_pair: Principal, _backupData: [Backup.BackupResponse]) : async (){
        let pair : ICDexPrivate.Self = actor(Principal.toText(_pair));
        let info = await pair.info();
        assert(info.paused);
        assert(_backupData.size() == 27);
        for (item in _backupData.vals()){
            ignore await pair.recovery(item);
        };
        ignore _putEvent(#recoveryPairData({ pair = _pair; timestamp = _now(); }), ?Tools.principalToAccountBlob(Principal.fromActor(this), null));
    };

    /// Returns all snapshot timestamps for a trading pair.
    public query func getSnapshots(_pair: Principal): async [ICDexTypes.Timestamp]{
        return _getSnapshotTs(_pair);
    };

    /// Removes all snapshots prior to the specified timestamp of the trading pair.
    public shared(msg) func removeSnapshot(_pair: Principal, _timeBefore: Timestamp): async (){
        assert(_onlyOwner(msg.caller));
        _removeSnapshot(_pair, _timeBefore);
    };

    /// Backs up and saves a snapshot of a trading pair.
    public shared(msg) func backup(_pair: Principal): async ICDexTypes.Timestamp{
        assert(_onlyOwner(msg.caller));
        let data = await _backup(_pair);
        return _setSnapshot(_pair, data);
    };

    /// Recover data for a trading pair.  
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

    /// Backup the data of a trading pair to another canister.  
    /// Note: Canister `_pairTo` is created only for backing up data and should not be used for trading. It needs to implement 
    /// the recover() method like ICDexPair.
    public shared(msg) func backupToTempCanister(_pairFrom: Principal, _pairTo: Principal) : async Bool{
        assert(_onlyOwner(msg.caller));
        let data = await _backup(_pairFrom);
        await _recovery(_pairTo, data);
        return true;
    };

    /// Save the data of snapshot to another canister.  
    /// Note: Canister `_pairTo` is created only for backing up data and should not be used for trading. It needs to implement 
    /// the recover() method like ICDexPair.
    public shared(msg) func snapshotToTempCanister(_pair: Principal, _snapshotTimestamp: ICDexTypes.Timestamp, _pairTo: Principal) : async Bool{
        assert(_onlyOwner(msg.caller));
        switch(_getSnapshot(_pair, ?_snapshotTimestamp)){
            case(?data){
                await _recovery(_pairTo, data);
                return true;
            };
            case(_){
                return false;
            };
        };
    };
    
    /* =======================
      Managing the list of pairs
    ========================= */

    /// Puts a pair into a list of trading pairs.
    public shared(msg) func put(_pair: SwapPair) : async (){
        assert(_onlyOwner(msg.caller));
        // let pair = _adjustPair2(_pair);
        pairs := Trie.put(pairs, keyp(_pair.canisterId), Principal.equal, _pair).0;
        await _syncFee(_pair.canisterId);
        let router: Router.Self = actor(aggregator);
        try{ // Used to push pair to external directory listings, if it fails it has no effect on ICDex.
            await router.putByDex(
                _pair.token0, 
                _pair.token1, 
                _pair.canisterId);
        }catch(e){};
        ignore _putEvent(#addPairToList({ pair = _pair.canisterId;}), ?Tools.principalToAccountBlob(msg.caller, null));
    };

    /// Removes a pair from the list of trading pairs.
    public shared(msg) func remove(_pairCanister: Principal) : async (){
        assert(_onlyOwner(msg.caller));
        pairs := Trie.filter(pairs, func (k: PairCanister, v: SwapPair): Bool{ 
            _pairCanister != k;
        });
        let router: Router.Self = actor(aggregator);
        try{ // Manager external directory listings, if it fails it has no effect on ICDex.
            await router.removeByDex(_pairCanister);
        }catch(e){};
        // cyclesMonitor := CyclesMonitor.remove(cyclesMonitor, _pairCanister);
        monitor.removeCanister(_pairCanister);
        ignore _putEvent(#removePairFromList({ pair = _pairCanister;}), ?Tools.principalToAccountBlob(msg.caller, null));
    };

    /// Returns all the tokens in the list of pairs.
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

    /// Returns all trading pairs.
    public query func getPairs(_page: ?Nat, _size: ?Nat) : async TrieList<PairCanister, SwapPair>{
        var trie = pairs;
        let page = Option.get(_page, 1);
        let size = Option.get(_size, 1000);
        return trieItems(trie, page, size);
    };

    /// Returns the trading pairs containing a specified token.
    public query func getPairsByToken(_token: Principal) : async [(PairCanister, SwapPair)]{
        return _getPairsByToken(_token, null);
    };

    /// Returns the trading pairs based on the two tokens provided.
    public query func route(_token0: Principal, _token1: Principal) : async [(PairCanister, SwapPair)]{
        let paris =  _getPairsByToken(_token0, ?_token1);

    };
    
    /* =======================
      Governance on trading pairs
    ========================= */

    /// Suspend (true) or open (false) a trading pair. If `_openingTime` is specified, it means that the pair will be opened automatically after that time.
    public shared(msg) func pair_pause(_app: Principal, _pause: Bool, _openingTime: ?Time.Time) : async Bool{ 
        assert(_onlyOwner(msg.caller));
        let pair: ICDexPrivate.Self = actor(Principal.toText(_app));
        let res = await pair.setPause(_pause, _openingTime);
        if (_pause){
            ignore _putEvent(#pairSuspend({ pair = _app;  message = ?"Pair is suspended by DAO."}), ?Tools.principalToAccountBlob(msg.caller, null));
        }else{
            ignore _putEvent(#pairStart({ pair = _app; message = ?"Pair is opened by DAO."}), ?Tools.principalToAccountBlob(msg.caller, null));
        };
        return res;
    };

    /// Suspend (true) or open (false) all trading pairs. 
    public shared(msg) func pair_pauseAll(_pause: Bool) : async {total: Nat; success: Nat; failures: [Principal]}{ 
        assert(_onlyOwner(msg.caller));
        var total : Nat = 0;
        var success : Nat = 0;
        var failures: [Principal] = [];
        for ((canisterId, info) in Trie.iter(pairs)){
            total += 1;
            let pair: ICDexPrivate.Self = actor(Principal.toText(canisterId));
            try{
                let res = await pair.setPause(_pause, null);
                if (_pause){
                    ignore _putEvent(#pairSuspend({ pair = canisterId;  message = ?"Pair is suspended by DAO."}), ?Tools.principalToAccountBlob(msg.caller, null));
                }else{
                    ignore _putEvent(#pairStart({ pair = canisterId; message = ?"Pair is opened by DAO."}), ?Tools.principalToAccountBlob(msg.caller, null));
                };
                success += 1;
            }catch(e){
                failures := Tools.arrayAppend(failures, [canisterId]);
            };
        };
        return {total = total; success = success; failures = failures};
    };

    /// Enable/disable Auction Mode
    public shared(msg) func pair_setAuctionMode(_app: Principal, _enable: Bool, _funder: ?AccountId) : async (Bool, AccountId){
        assert(_onlyOwner(msg.caller));
        let pair: ICDexPrivate.Self = actor(Principal.toText(_app));
        let res = await pair.setAuctionMode(_enable, _funder);
        ignore _putEvent(#pairSetAuctionMode({ pair = _app; result = res }), ?Tools.principalToAccountBlob(msg.caller, null));
        return res;
    };

    /// Open IDO of a trading pair and configure parameters
    public shared(msg) func pair_IDOSetFunder(_app: Principal, _funder: ?Principal, _requirement: ?ICDexPrivate.IDORequirement) : async (){ 
        assert(_onlyOwner(msg.caller));
        let pair: ICDexPrivate.Self = actor(Principal.toText(_app));
        IDOPairs := List.filter(IDOPairs, func (t: Principal): Bool{ t != _app });
        if (Option.isSome(_funder)){
            IDOPairs := List.push(_app, IDOPairs);
        };
        await pair.IDO_setFunder(_funder, _requirement);
        ignore _putEvent(#pairEnableIDOAndSetFunder({ pair = _app; funder = _funder; _requirement = _requirement}), ?Tools.principalToAccountBlob(msg.caller, null));
    };

    // public shared(msg) func pair_changeOwner(_app: Principal, _newOwner: Principal) : async Bool{ 
    //     assert(_onlyOwner(msg.caller));
    //     let pair: ICDexPrivate.Self = actor(Principal.toText(_app));
    //     let res = await pair.changeOwner(_newOwner);
    //     ignore _putEvent(#pairChangeOwner({ pair = _app; newOwner = _newOwner}), ?Tools.principalToAccountBlob(msg.caller, null));
    //     return res;
    // };
    // pair_config '(principal "", opt record{UNIT_SIZE=opt 100_000_000:opt nat}, null)'
    // pair_config '(principal "", null, opt record{MAX_CACHE_TIME= opt 5_184_000_000_000_000})'

    /// Configure the trading pair parameters and configure its DRC205 parameters.
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
        ignore _putEvent(#pairConfig({ pair = _app; setting = _config; drc205config = _drc205config}), ?Tools.principalToAccountBlob(msg.caller, null));
        return res;
    };

    /// When the data is too large to be backed up, you can set the UpgradeMode to #Base.
    public shared(msg) func pair_setUpgradeMode(_app: Principal, _mode: {#Base; #All}) : async (){
        assert(_onlyOwner(msg.caller));
        let pair: ICDexPrivate.Self = actor(Principal.toText(_app));
        let res = await pair.setUpgradeMode(_mode);
        ignore _putEvent(#pairSetUpgradeMode({ pair = _app; mode = _mode}), ?Tools.principalToAccountBlob(msg.caller, null));
        return res;
    };

    /// Sets an order with #Todo status as an error order.
    public shared(msg) func pair_setOrderFail(_app: Principal, _txid: Text, _refund0: Nat, _refund1: Nat) : async Bool{
        assert(_onlyOwner(msg.caller));
        let pair: ICDexPrivate.Self = actor(Principal.toText(_app));
        let res = await pair.setOrderFail(_txid, _refund0, _refund1);
        ignore _putEvent(#pairSetOrderFail({ pair = _app; txidHex = _txid; refundToken0 = _refund0; refundToken1 = _refund1 }), ?Tools.principalToAccountBlob(msg.caller, null));
        return res;
    };

    /// Enable strategy orders for a trading pair.
    public shared(msg) func pair_enableStratOrder(_app: Principal, _arg: {#Enable; #Disable}) : async (){
        assert(_onlyOwner(msg.caller));
        let pair: ICDexPrivate.Self = actor(Principal.toText(_app));
        await pair.sto_enableStratOrder(_arg);
        ignore _putEvent(#pairEnableStratOrder({ pair = _app; arg = _arg }), ?Tools.principalToAccountBlob(msg.caller, null));
    };

    /// Configuring strategy order parameters for a trading pair.
    public shared(msg) func sto_config(_app: Principal, _config: {
        poFee1: ?Nat; // ICL
        poFee2: ?Float; // Fee rate of filled token0 or token1
        sloFee1: ?Nat; // ICL
        sloFee2: ?Float; // Fee rate of filled token0 or token1
        gridMaxPerSide: ?Nat; 
        proCountMax: ?Nat;
        stopLossCountMax: ?Nat;
    }) : async (){
        assert(_onlyOwner(msg.caller));
        let pair: ICDexPrivate.Self = actor(Principal.toText(_app));
        await pair.sto_config(_config);
        ignore _putEvent(#pairSTOConfig({ pair = _app; config = _config }), ?Tools.principalToAccountBlob(msg.caller, null));
    };

    /// Query all orders in pending status.
    public shared(msg) func pair_pendingAll(_app: Principal, _page: ?Nat, _size: ?Nat) : async ICDexTypes.TrieList<ICDexTypes.Txid, ICDexTypes.TradingOrder>{
        assert(_onlyOwner(msg.caller));
        let pair: ICDexPrivate.Self = actor(Principal.toText(_app));
        return await pair.pendingAll(_page, _size);
    };

    /// Withdraw cycles.
    public shared(msg) func pair_withdrawCycles(_app: Principal, _amount: Nat): async (){
        assert(_onlyOwner(msg.caller));
        let pair: ICDexPrivate.Self = actor(Principal.toText(_app));
        await pair.withdraw_cycles(_amount);
    };

    /// Add/Remove ICTC Administrator
    public shared(msg) func pair_ictcSetAdmin(_app: Principal, _admin: Principal, _addOrRemove: Bool) : async Bool{ 
        assert(_onlyOwner(msg.caller));
        let pair: ICDexPrivate.Self = actor(Principal.toText(_app));
        if (_addOrRemove){
            await pair.ictc_addAdmin(_admin);
            ignore _putEvent(#pairICTCSetAdmin({ app = _app; admin = _admin; act = #Add }), ?Tools.principalToAccountBlob(msg.caller, null));
        }else{
            await pair.ictc_removeAdmin(_admin);
            ignore _putEvent(#pairICTCSetAdmin({ app = _app; admin = _admin; act = #Remove }), ?Tools.principalToAccountBlob(msg.caller, null));
        };
        return true;
    };

    /* ICTC governance */

    /// Clear logs of transaction orders and transaction tasks. 
    public shared(msg) func pair_ictcClearLog(_app: Principal, _expiration: ?Int, _delForced: Bool) : async (){ 
        assert(_onlyOwner(msg.caller));
        let pair: ICDexPrivate.Self = actor(Principal.toText(_app));
        await pair.ictc_clearLog(_expiration, _delForced);
        ignore _putEvent(#pairICTCClearLog({ app = _app; expiration = _expiration; forced = _delForced }), ?Tools.principalToAccountBlob(msg.caller, null));
    };

    // public shared(msg) func pair_ictcClearTTPool(_app: Principal) : async (){ 
    //     assert(_onlyOwner(msg.caller));
    //     let pair: ICDexPrivate.Self = actor(Principal.toText(_app));
    //     await pair.ictc_clearTTPool();
    //     // ignore _putEvent(#pairICTCClearTTPool({ pair = _app; }), ?Tools.principalToAccountBlob(msg.caller, null));
    // };
    // public shared(msg) func pair_ictcManageOrder1(_app: Principal, _txid: Txid, _orderStatus: ICDexTypes.TradingStatus, _token0Fallback: Nat, _token1Fallback: Nat, _token0FromPair: Nat, _token1FromPair: Nat) : async Bool{
    //     assert(_onlyOwner(msg.caller));
    //     let pair: ICDexPrivate.Self = actor(Principal.toText(_app));
    //     await pair.ictc_manageOrder1(_txid, _orderStatus, _token0Fallback, _token1Fallback, _token0FromPair, _token1FromPair);
    // };

    /// Try the task again.
    public shared(msg) func pair_ictcRedoTT(_app: Principal, _toid: Nat, _ttid: Nat) : async (?Nat){ 
        assert(_onlyOwner(msg.caller));
        let pair: ICDexPrivate.Self = actor(Principal.toText(_app));
        let res = await pair.ictc_redoTT(_toid, _ttid);
        ignore _putEvent(#pairICTCRedoTT({ app = _app; toid = _toid; ttid = _ttid; completed = Option.isSome(res)}), ?Tools.principalToAccountBlob(msg.caller, null));
        return res;
    };

    /// Complete a blocking order.
    public shared(msg) func pair_ictcCompleteTO(_app: Principal, _toid: Nat, _status: SagaTM.OrderStatus) : async Bool{ 
        assert(_onlyOwner(msg.caller));
        let pair: actor{ ictc_completeTO: shared (_toid: Nat, _status: SagaTM.OrderStatus) -> async Bool } = actor(Principal.toText(_app));
        let res = await pair.ictc_completeTO(_toid, _status);
        ignore _putEvent(#pairICTCCompleteTO({ app = _app; toid = _toid; status = _status; completed = res}), ?Tools.principalToAccountBlob(msg.caller, null));
        return res;
    };

    /// Set status of a pending task.
    public shared(msg) func pair_ictcDoneTT(_app: Principal, _toid: Nat, _ttid: Nat, _toCallback: Bool) : async (?Nat){ 
        assert(_onlyOwner(msg.caller));
        let pair: ICDexPrivate.Self = actor(Principal.toText(_app));
        let res = await pair.ictc_doneTT(_toid, _ttid, _toCallback);
        ignore _putEvent(#pairICTCDoneTT({ app = _app; toid = _toid; ttid = _ttid; callbacked = _toCallback; completed = Option.isSome(res)}), ?Tools.principalToAccountBlob(msg.caller, null));
        return res;
    };

    /// Set status of a pending order.
    public shared(msg) func pair_ictcDoneTO(_app: Principal, _toid: Nat, _status: SagaTM.OrderStatus, _toCallback: Bool) : async Bool{ 
        assert(_onlyOwner(msg.caller));
        let pair: ICDexPrivate.Self = actor(Principal.toText(_app));
        let res = await pair.ictc_doneTO(_toid, _status, _toCallback);
        ignore _putEvent(#pairICTCDoneTO({ app = _app; toid = _toid; status = _status; callbacked = _toCallback; completed = res}), ?Tools.principalToAccountBlob(msg.caller, null));
        return res;
    };

    /// Run the ICTC actuator and check the status of the transaction order `toid`.
    public shared(msg) func pair_ictcRunTO(_app: Principal, _toid: Nat) : async ?SagaTM.OrderStatus{ 
        assert(_onlyOwner(msg.caller));
        let pair: ICDexPrivate.Self = actor(Principal.toText(_app));
        let res = await pair.ictc_runTO(_toid);
        ignore _putEvent(#pairICTCRunTO({ app = _app; toid = _toid; result = res }), ?Tools.principalToAccountBlob(msg.caller, null));
        return res;
    };

    /// Change the status of a transaction order to #Blocking.
    public shared(msg) func pair_ictcBlockTO(_app: Principal, _toid: Nat) : async (?Nat){ 
        assert(_onlyOwner(msg.caller));
        let pair: ICDexPrivate.Self = actor(Principal.toText(_app));
        let res = await pair.ictc_blockTO(_toid);
        ignore _putEvent(#pairICTCBlockTO({ app = _app; toid = _toid; completed = Option.isSome(res) }), ?Tools.principalToAccountBlob(msg.caller, null));
        return res;
    };

    /// Synchronizing token0 and token1 transfer fees.
    public shared(msg) func pair_sync(_app: Principal) : async (){
        assert(_onlyOwner(msg.caller));
        let pair: ICDexPrivate.Self = actor(Principal.toText(_app));
        await pair.sync();
        ignore _putEvent(#pairSync({ pair = _app; }), ?Tools.principalToAccountBlob(msg.caller, null));
    };

    /// Set up vip-maker qualification and configure rebate rate.
    public shared(msg) func pair_setVipMaker(_app: Principal, _account: Address, _rate: Nat) : async (){
        assert(_onlyOwner(msg.caller));
        let pair: ICDexPrivate.Self = actor(Principal.toText(_app));
        await pair.setVipMaker(_account, _rate);
        ignore _putEvent(#pairSetVipMaker({ pair = _app; account = _account; rebateRate = _rate }), ?Tools.principalToAccountBlob(msg.caller, null));
    };

    /// Removes vip-maker qualification.
    public shared(msg) func pair_removeVipMaker(_app: Principal, _account: Address) : async (){
        assert(_onlyOwner(msg.caller));
        let pair: ICDexPrivate.Self = actor(Principal.toText(_app));
        await pair.removeVipMaker(_account);
        ignore _putEvent(#pairRemoveVipMaker({ pair = _app; account = _account }), ?Tools.principalToAccountBlob(msg.caller, null));
    };

    /// Retrieve missing funds from the order's TxAccount. The funds of the TxAccount will be refunded to the ICDexRouter canister-id.
    public shared(msg) func pair_fallbackByTxid(_app: Principal, _txid: Txid, _sa: ?ICDexPrivate.Sa) : async Bool{
        assert(_onlyOwner(msg.caller));
        let pair: ICDexPrivate.Self = actor(Principal.toText(_app));
        let res = await pair.fallbackByTxid(_txid, _sa);
        ignore _putEvent(#pairFallbackByTxid({ pair = _app; txid = _txid; result = res}), ?Tools.principalToAccountBlob(msg.caller, null));
        return res;
    };

    /// Cancels an order.
    public shared(msg) func pair_cancelByTxid(_app: Principal,  _txid: Txid, _sa: ?ICDexPrivate.Sa) : async (){
        assert(_onlyOwner(msg.caller));
        let pair: ICDexPrivate.Self = actor(Principal.toText(_app));
        await pair.cancelByTxid(_txid, _sa);
        ignore _putEvent(#pairCancelByTxid({ pair = _app; txid = _txid }), ?Tools.principalToAccountBlob(msg.caller, null));
    };

    /// Submit a text description of the Trading Ambassadors (referral) system.
    public shared(msg) func pair_taSetDescription(_app: Principal, _desc: Text) : async (){ 
        assert(_onlyOwner(msg.caller));
        let pair: ICDexPrivate.Self = actor(Principal.toText(_app));
        await pair.ta_setDescription(_desc);
        ignore _putEvent(#pairTASetDescription({ pair = _app; desc = _desc }), ?Tools.principalToAccountBlob(msg.caller, null));
    };

    /* =======================
      Trading Competitions 
      (Registering to an external trading competition organizer has no effect on ICDex.)
    ========================= */

    /// This is a feature to be opened in the future. Register a trading competition with a third party for display.
    public shared(msg) func dex_addCompetition(_id: ?Nat, _name: Text, _content: Text, _start: Time.Time, _end: Time.Time, 
    _addPairs: [{dex: Text; canisterId: Principal; quoteToken:{#token0; #token1}; minCapital: Nat}]) : async Nat{ 
        assert(_onlyOwner(msg.caller));
        var pairList : [(DexName, Principal, {#token0; #token1})] = [];
        for (pair in _addPairs.vals()){
            pairList := Tools.arrayAppend(pairList, [(pair.dex, pair.canisterId, pair.quoteToken)]);
        };
        let router : Router.Self = actor(aggregator);
        let res = await router.pushCompetitionByDex(_id, _name, _content, _start, _end, pairList);
        ignore _putEvent(#dexAddCompetition({ id = _id; name = _name; start = _start; end = _end; addPairs = _addPairs }), ?Tools.principalToAccountBlob(msg.caller, null));
        return res;
    };

    /* =======================
      System management
    ========================= */

    /// Returns the canister-id of the DAO
    public query func getDAO() : async Principal{  
        return icDao;
    };

    // public shared(msg) func changeOwner(_newOwner: Principal) : async Bool{ 
    //     assert(_onlyOwner(msg.caller));
    //     owner := _newOwner;
    //     ignore _putEvent(#changeOwner({ newOwner = _newOwner }), ?Tools.principalToAccountBlob(msg.caller, null));
    //     return true;
    // };

    /// Withdraw the token to the specified account.  
    /// Withdrawals can only be made to a DAO address, or to a blackhole address (destruction), not to a private address.
    public shared(msg) func sys_withdraw(_token: Principal, _tokenStd: TokenStd, _to: Principal, _value: Nat) : async (){ 
        assert(_onlyOwner(msg.caller));
        assert(_to == icDao or _to == blackhole);
        let account = Tools.principalToAccountBlob(_to, null);
        let address = Tools.principalToAccountHex(_to, null);
        var _txid : {#txid: Txid; #index: Nat} = #index(0);
        if (_tokenStd == #drc20){
            let token: DRC20.Self = actor(Principal.toText(_token));
            let res = await token.drc20_transfer(address, _value, null, null, null);
            switch(res){
                case(#ok(txid)){ _txid := #txid(txid) };
                case(_){ throw Error.reject("Transfer error."); };
            };
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
            switch(res){
                case(#Ok(index)){ _txid := #index(index) };
                case(_){ throw Error.reject("Transfer error."); };
            };
        }else if (_tokenStd == #icp or _tokenStd == #ledger){
            let token: Ledger.Self = actor(Principal.toText(_token));
            let args : Ledger.TransferArgs = {
                memo = 0;
                amount = { e8s = Nat64.fromNat(_value) };
                fee = { e8s = 10_000 };
                from_subaccount = null;
                to = account;
                created_at_time = null;
            };
            let res = await token.transfer(args);
            switch(res){
                case(#Ok(index)){ _txid := #index(Nat64.toNat(index)) };
                case(_){ throw Error.reject("Transfer error."); };
            };
        };
        ignore _putEvent(#sysWithdraw({ token = _token; to = _to; value = _value; txid = _txid }), ?Tools.principalToAccountBlob(msg.caller, null));
    };

    /// Placing an order in a trading pair as a trader.
    public shared(msg) func sys_order(_token: Principal, _tokenStd: TokenStd, _value: Nat, _pair: Principal, _order: ICDexTypes.OrderPrice) : async ICDexTypes.TradingResult{
        assert(_onlyOwner(msg.caller));
        let account = Tools.principalToAccountBlob(Principal.fromActor(this), null);
        let address = Tools.principalToAccountHex(Principal.fromActor(this), null);
        let pairAddress = Tools.principalToAccountHex(_pair, null);
        let pair: ICDexTypes.Self = actor(Principal.toText(_pair));
        var _txid : {#txid: Txid; #index: Nat} = #index(0);
        if (_tokenStd == #drc20){
            let token: DRC20.Self = actor(Principal.toText(_token));
            let res = await token.drc20_approve(pairAddress, _value, null,null,null);
            switch(res){
                case(#ok(txid)){ _txid := #txid(txid) };
                case(_){ throw Error.reject("Transfer error."); };
            };
        }else{ // ICRC1
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
            switch(res){
                case(#Ok(index)){ _txid := #index(index) };
                case(_){ throw Error.reject("Transfer error."); };
            };
        };
        let res = await pair.trade(_order, #LMT, null,null,null,null);
        ignore _putEvent(#sysTrade({ pair = _pair; tokenTxid = _txid; order = _order; orderType = #LMT; result = res }), ?Tools.principalToAccountBlob(msg.caller, null));
        return res;
    };

    /// Cancel own orders as a trader.
    public shared(msg) func sys_cancelOrder(_pair: Principal, _txid: ?Txid) : async (){
        assert(_onlyOwner(msg.caller));
        let address = Tools.principalToAccountHex(Principal.fromActor(this), null);
        let pair: ICDexTypes.Self = actor(Principal.toText(_pair));
        switch(_txid){
            case(?(txid)){ //cancelByTxid : shared (_txid: Txid, _sa: ?Sa) -> async ();
                await pair.cancelByTxid(txid, null);
            };
            case(_){ // cancelAll(_args: {#management: ?AccountId; #self_sa: ?Sa}, _side: ?OrderBook.OrderSide)
                await pair.cancelAll(#self_sa(null), null);
            };
        };
        ignore _putEvent(#sysCancelOrder({ pair = _pair; txid = _txid }), ?Tools.principalToAccountBlob(msg.caller, null));
    };

    /// Configure the system parameters of the ICDexRouter.
    public shared(msg) func sys_config(_args: {
        aggregator: ?Principal;
        blackhole: ?Principal;
        icDao: ?Principal;
        nftPlanetCards: ?Principal;
        sysToken: ?Principal;
        sysTokenFee: ?Nat;
        creatingPairFee: ?Nat;
        creatingMakerFee: ?Nat;
    }) : async (){
        assert(_onlyOwner(msg.caller));
        aggregator := Principal.toText(Option.get(_args.aggregator, Principal.fromText(aggregator)));
        blackhole := Option.get(_args.blackhole, blackhole);
        icDao := Option.get(_args.icDao, icDao);
        nftPlanetCards := Option.get(_args.nftPlanetCards, nftPlanetCards);
        sysToken := Option.get(_args.sysToken, sysToken);
        sysTokenFee := Option.get(_args.sysTokenFee, sysTokenFee);
        creatingPairFee := Option.get(_args.creatingPairFee, creatingPairFee);
        creatingMakerFee := Option.get(_args.creatingMakerFee, creatingMakerFee);
        ignore _putEvent(#sysConfig(_args), ?Tools.principalToAccountBlob(msg.caller, null));
    };

    /// Returns the configuration items of ICDexRouter.
    public query func sys_getConfig() : async {
        aggregator: Principal;
        blackhole: Principal;
        icDao: Principal;
        nftPlanetCards: Principal;
        sysToken: Principal;
        sysTokenFee: Nat;
        creatingPairFee: Nat;
        creatingMakerFee: Nat;
    }{
        return {
            aggregator = Principal.fromText(aggregator);
            blackhole = blackhole;
            icDao = icDao;
            nftPlanetCards = nftPlanetCards;
            sysToken = sysToken;
            sysTokenFee = sysTokenFee;
            creatingPairFee = creatingPairFee;
            creatingMakerFee = creatingMakerFee;
        };
    };

    /* =======================
      NFT
    ========================= */
    // private stable var nftVipMakers: Trie.Trie<Text, (AccountId, [Principal])> = Trie.empty(); 
    type NFTType = {#NEPTUNE/*0-4*/; #URANUS/*5-14*/; #SATURN/*15-114*/; #JUPITER/*115-314*/; #MARS/*315-614*/; #EARTH/*615-1014*/; #VENUS/*1015-1514*/; #MERCURY/*1515-2021*/; #UNKNOWN};
    type CollectionId = Principal;
    type NFT = (ERC721.User, ERC721.TokenIdentifier, ERC721.Balance, NFTType, CollectionId);
    private stable var nfts: Trie.Trie<AccountId, [NFT]> = Trie.empty(); // The record set where the users deposited the NFT to the ICDexRouter.
    private let sa_zero : [Nat8] = [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0];
    
    // Determines whether an account holds the specified NFT based on local records.
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

    // Returns the type of NFT by accessing remote canister.
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

    // Returns whether an account is the holder of the specified NFT by accessing a remote canister.
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
        ignore _putEvent(#nftTransferFrom({ collId = _collId; nftId = _nftId; args = args; result = res }), null);
        return res;
    };

    private func _NFTWithdraw(_caller: Principal, _nftId: ?ERC721.TokenIdentifier, _sa: ?[Nat8]) : async* (){
        let accountId = Tools.principalToAccountBlob(_caller, _sa);
        switch(Trie.get(nfts, keyb(accountId), Blob.equal)){
            case(?(item)){ 
                for(nft in item.vals()){
                    let collId = nft.4;
                    let nftId = nft.1;
                    let nftActor: ERC721.Self = actor(Principal.toText(collId));
                    let args: ERC721.TransferRequest = {
                        from = #principal(Principal.fromActor(this));
                        to = nft.0;
                        token = nftId;
                        amount = nft.2;
                        memo = Blob.fromArray([]);
                        notify = false;
                        subaccount = null;
                    };
                    let res = await nftActor.transfer(args);
                    switch(res){
                        case(#ok(balance)){
                            _NFTRemove(accountId, nft.1);
                            // Hooks used to unbind all
                            await* _hook_NFTUnbindAllMaker(nft.1);
                        };
                        case(#err(e)){};
                    };
                    ignore _putEvent(#nftWithdraw({ collId = collId; nftId = nftId; args = args; result = res }), null);
                };
             };
            case(_){};
        };
    };

    /// Returns a list of holders of staked NFTs in the ICDexRouter.
    public query func NFTs() : async [(AccountId, [NFT])]{
        return Trie.toArray<AccountId, [NFT], (AccountId, [NFT])>(nfts, func (k:AccountId, v:[NFT]) : (AccountId, [NFT]){  (k, v) });
    };

    /// Returns an account's NFT balance staked in the ICDexRouter.
    public query func NFTBalance(_owner: Address) : async [NFT]{
        let accountId = _getAccountId(_owner);
        switch(Trie.get(nfts, keyb(accountId), Blob.equal)){
            case(?(items)){ return items };
            case(_){ return []; };
        };
    };

    /// The user deposits the NFT to the ICDexRouter.
    public shared(msg) func NFTDeposit(_collectionId: CollectionId, _nftId: ERC721.TokenIdentifier, _sa: ?[Nat8]) : async (){
        assert(_collectionId == nftPlanetCards);
        let r = await* _NFTTransferFrom(msg.caller, _collectionId, _nftId, _sa);
    };

    /// The user withdraws the NFT to his wallet.
    public shared(msg) func NFTWithdraw(_nftId: ?ERC721.TokenIdentifier, _sa: ?[Nat8]) : async (){
        let accountId = Tools.principalToAccountBlob(msg.caller, _sa);
        assert(_onlyNFTHolder(accountId, _nftId, null));
        await* _NFTWithdraw(msg.caller, _nftId, _sa);
    };

    /* ===== functions for Makers ==== */
    // NFT binding vip-maker qualifications
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
        ignore _putEvent(#nftSetVipMaker({ pair = _pair; nftId = _nftId; vipMaker = _accountIdToHex(_a); rebateRate = 90 }), null);
    };
    private func _remote_removeVipMaker(_pair: Principal, _a: AccountId) : async* (){
        let pair: ICDexPrivate.Self = actor(Principal.toText(_pair));
        await pair.removeVipMaker(_accountIdToHex(_a));
        ignore _putEvent(#nftRemoveVipMaker({ pair = _pair; vipMaker = _accountIdToHex(_a) }), null);
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

    /// Returns vip-makers to which an NFT has been bound.
    public query func NFTBindingMakers(_nftId: Text) : async [(pair: Principal, account: AccountId)]{
        switch(Trie.get(nftBindingMakers, keyt(_nftId), Text.equal)){
            case(?(items)){ return items };
            case(_){ return []; };
        };
    };

    /// The NFT owner binds a new vip-maker.
    public shared(msg) func NFTBindMaker(_nftId: Text, _pair: Principal, _maker: AccountId, _sa: ?[Nat8]) : async (){
        let accountId = Tools.principalToAccountBlob(msg.caller, _sa);
        assert(_onlyNFTHolder(accountId, ?_nftId, ?#NEPTUNE));
        await* _NFTBindMaker(_nftId, _pair, _maker);
    };

    /// The NFT owner unbinds a vip-maker.
    public shared(msg) func NFTUnbindMaker(_nftId: Text, _pair: Principal, _maker: AccountId, _sa: ?[Nat8]) : async (){
        let accountId = Tools.principalToAccountBlob(msg.caller, _sa);
        assert(_onlyNFTHolder(accountId, ?_nftId, ?#NEPTUNE));
        await* _NFTUnbindMaker(_nftId, _pair, _maker);
    };

    /* =======================
      ICDexMaker
    ========================= */
    
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
    // Upgrade an ICDexMaker canister.
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
                            spreadRate = makerInfo.gridSetting.gridSpread; // ppm  x/1_000_000
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

    /// Set the wasm of the ICDexMaker.
    ///
    /// Arguments:
    /// - wasm: Blob. wasm file.
    /// - version: Text. The current version of wasm.
    /// - append: Bool. Whether to continue uploading the rest of the chunks of the same wasm file. If a wasm file is larger than 2M, 
    /// it can't be uploaded at once, the solution is to upload it in multiple chunks. `append` is set to false when uploading the 
    /// first chunk. `append` is set to true when uploading subsequent chunks, and version must be filled in with the same value.
    /// - backup: Bool. Whether to backup the previous version of wasm.
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
        ignore _putEvent(#setMakerWasm({ version = _version; append = _append; backupPreVersion = _backupPreVersion }), ?Tools.principalToAccountBlob(msg.caller, null));
    };

    /// Returns the current version of ICDexMaker wasm.
    public query func maker_getWasmVersion() : async (Text, Text, Nat){
        let offset = maker_wasm.size() / 2;
        var hash224 = SHA224.sha224(Tools.arrayAppend(Tools.slice(maker_wasm, 0, ?1024), Tools.slice(maker_wasm, offset, ?(offset+1024))));
        var crc : [Nat8] = CRC32.crc32(hash224);
        let hash = Tools.arrayAppend(crc, hash224);  
        return (maker_wasmVersion, Hex.encode(hash), maker_wasm.size());
    };

    /// Returns all public automated market makers.
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

    /// Returns all private automated market makers.
    public query func maker_getPrivateMakers(_account: AccountId, _page: ?Nat, _size: ?Nat) : async TrieList<PairCanister, [(Principal, AccountId)]>{
        var trie = Trie.mapFilter(maker_privateCanisters, func (k: PairCanister, v: [(Principal, AccountId)]): ?[(Principal, AccountId)]{
            let items = Array.filter(v, func (t: (Principal, AccountId)): Bool{ t.1 == _account});
            if (items.size() > 0){ ?items } else { null };
        });
        let page = Option.get(_page, 1);
        let size = Option.get(_size, 100);
        return trieItems(trie, page, size);
    };

    /// Create a new Automated Market Maker (ICDexMaker).  
    /// Trading pairs and automated market makers are in a one-to-many relationship, with one trading pair corresponding to zero or more 
    /// automated market makers.  
    /// permissions: Dao, NFT#NEPTUNE,#URANUS,#SATURN holders
    ///
    /// Arguments:
    /// - arg: 
    /// ```
    /// {
    ///     pair: Principal; // Trading pair caniser-id.
    ///     allow: {#Public; #Private}; // Visibility. #Public / #Private.
    ///     name: Text; // Name. e.g. "AAA_BBB AMM-1"
    ///     lowerLimit: Nat; // Lower price limit. How much token1 (smallest units) are needed to purchase UNIT_SIZE token0 (smallest units).
    ///     upperLimit: Nat; // Upper price limit. How much token1 (smallest units) are needed to purchase UNIT_SIZE token0 (smallest units).
    ///     spreadRate: Nat; // ppm. Inter-grid spread ratio for grid orders. e.g. 10_000, it means 1%.
    ///     threshold: Nat; // token1 (smallest units). e.g. 1_000_000_000_000. After the total liquidity exceeds this threshold, the LP adds liquidity up to a limit of volFactor times his trading volume.
    ///     volFactor: Nat; // LP liquidity limit = LP's trading volume * volFactor.  e.g. 2
    /// }
    /// ```
    /// 
    /// Returns:
    /// - canister: Principal. Automated Market Maker canister-id.
    public shared(msg) func maker_create(_arg: {
            pair: Principal;
            allow: {#Public; #Private};
            name: Text; // "AAA_BBB AMM-1"
            lowerLimit: Nat; // Price
            upperLimit: Nat; // Price
            spreadRate: Nat; // e.g. 10_000, it means 1%.
            threshold: Nat; // e.g. 1_000_000_000_000
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
        if (not(_onlyOwner(msg.caller))){
            let arg: ICRC1.TransferFromArgs = {
                spender_subaccount = null; // *
                from = {owner = msg.caller; subaccount = null};
                to = {owner = Principal.fromActor(this); subaccount = null};
                amount = creatingMakerFee;
                fee = null;
                memo = null;
                created_at_time = null;
            };
            let result = await token.icrc2_transfer_from(arg);
            switch(result){
                case(#Ok(blockNumber)){};
                case(#Err(e)){
                    throw Error.reject("Error: Error when paying the fee for creating an ICDexMaker."); 
                };
            };
            ignore _putEvent(#chargeFee({ token = sysToken; arg = arg; result = result; }), ?Tools.principalToAccountBlob(msg.caller, null));
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
                spreadRate = _arg.spreadRate; // ppm  x/1_000_000
                threshold = _arg.threshold;
                volFactor = _arg.volFactor; // multi 
            }: Maker.InitArgs));
            await ic.install_code({
                arg : [Nat8] = args;
                wasm_module = maker_wasm;
                mode = #install; // #reinstall; #upgrade; #install
                canister_id = makerCanister;
            });
            var controllers: [Principal] = [icDao, blackhole, Principal.fromActor(this)]; 
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

            let arg: ICRC1.TransferArgs = {
                from_subaccount = null;
                to = {owner = makerCanister; subaccount = null};
                amount = sysTokenFee;
                fee = null;
                memo = null;
                created_at_time = null;
            };
            ignore await token.icrc1_transfer(arg);
            let maker : actor{
                approveToPair : shared (_token: Principal, _std: TokenStd, _amount: Nat) -> async Bool;
            } = actor(Principal.toText(makerCanister));
            ignore await maker.approveToPair(sysToken, #icrc1, 2 ** 255);

            // cyclesMonitor := await* CyclesMonitor.put(cyclesMonitor, makerCanister);
            await* monitor.putCanister(makerCanister);
            ignore _putEvent(#createMaker({ version = maker_wasmVersion; arg = _arg; makerCanisterId = makerCanister }), ?Tools.principalToAccountBlob(msg.caller, null));
            return makerCanister;
        }catch(e){
            if (not(_onlyOwner(msg.caller)) and creatingMakerFee > sysTokenFee){
                let arg: ICRC1.TransferArgs = {
                    from_subaccount = null;
                    to = {owner = msg.caller; subaccount = null};
                    amount = Nat.sub(creatingMakerFee, sysTokenFee);
                    fee = null;
                    memo = null;
                    created_at_time = null;
                };
                let r = await token.icrc1_transfer(arg);
                ignore _putEvent(#refundFee({ token = sysToken; arg = arg; result = r; }), ?Tools.principalToAccountBlob(msg.caller, null));
            };
            throw Error.reject(Error.message(e));
        };
    };
    
    /// Reinstall an ICDexMaker canister which is paused.
    ///
    /// Arguments:
    /// - pair: Principal. trading pair canister-id.
    /// - maker: Principal. ICDexMaker canister-id.
    /// - version: Text. Check the current version to be upgraded.
    /// 
    /// Returns:
    /// - canister: ?Principal. ICDexMaker canister-id. Returns null if the upgrade was unsuccessful.
    /// Note: Operate with caution. Consider calling this method only if upgrading is not possible.
    public shared(msg) func maker_reinstall(_pair: Principal, _maker: Principal, _version: Text) : async (canister: ?Principal){
        assert(_onlyOwner(msg.caller));
        assert(maker_wasm.size() > 0);
        assert(_version == maker_wasmVersion);

        let maker0 : Maker.Self = actor(Principal.toText(_maker));
        let maker : actor{
            backup: shared (MakerBackup.BackupRequest) -> async MakerBackup.BackupResponse;
            recovery: shared (MakerBackup.BackupResponse) -> async Bool;
        } = actor(Principal.toText(_maker));
        let info = await maker0.info();
        assert(info.paused);
        var makerData : [MakerBackup.BackupResponse] = [];
        let otherData = await maker.backup(#otherData);
        makerData := Tools.arrayAppend(makerData, [otherData]);
        var unitNetValues = await maker.backup(#unitNetValues(#Base));
        try { unitNetValues := await maker.backup(#unitNetValues(#All)); } catch(e){};
        makerData := Tools.arrayAppend(makerData, [unitNetValues]);
        var accountShares = await maker.backup(#accountShares(#Base));
        try { accountShares := await maker.backup(#accountShares(#All)); } catch(e){};
        makerData := Tools.arrayAppend(makerData, [accountShares]);
        var accountVolUsed = await maker.backup(#accountVolUsed(#Base));
        try { accountVolUsed := await maker.backup(#accountVolUsed(#All)); } catch(e){};
        makerData := Tools.arrayAppend(makerData, [accountVolUsed]);
        var blockEvents: MakerBackup.BackupResponse = #blockEvents([]);
        try { blockEvents := await maker.backup(#blockEvents); } catch(e){};
        makerData := Tools.arrayAppend(makerData, [blockEvents]);
        var accountEvents: MakerBackup.BackupResponse = #accountEvents([]);
        try { accountEvents := await maker.backup(#accountEvents); } catch(e){};
        makerData := Tools.arrayAppend(makerData, [accountEvents]);
        var fallbacking_accounts: MakerBackup.BackupResponse = #fallbacking_accounts([]);
        try { fallbacking_accounts := await maker.backup(#fallbacking_accounts); } catch(e){};
        makerData := Tools.arrayAppend(makerData, [fallbacking_accounts]);
        assert(makerData.size() == 7);

        let res = await* _maker_update(_pair, _maker, maker_wasm, #reinstall, { name = null });
        ignore _putEvent(#reinstallMaker({ version = _version; pair = _pair; maker = _maker; completed = Option.isSome(res) }), ?Tools.principalToAccountBlob(msg.caller, null));

        for (item in makerData.vals()){
            ignore await maker.recovery(item);
        };

        return res; 
    };

    /// Upgrade an ICDexMaker canister.  
    /// permissions: Dao, Private Maker Creator
    ///
    /// Arguments:
    /// - pair: Principal. Trading pair canister-id.
    /// - maker: Principal. Automated Market Maker canister-id.
    /// - name:?Text. Maker name.
    /// - version: Text. Check the current version to be upgraded.
    /// 
    /// Returns:
    /// - canister: ?Principal. Automated Market Maker canister-id. Returns null if the upgrade was unsuccessful.
    public shared(msg) func maker_update(_pair: Principal, _maker: Principal, _name:?Text, _version: Text): async (canister: ?Principal){
        let accountId = Tools.principalToAccountBlob(msg.caller, null);
        assert(_onlyOwner(msg.caller) or (not(_isPublicMaker(_pair, _maker)) and _OnlyMakerCreator(_pair, _maker, accountId))); 
        assert(_version == maker_wasmVersion);
        let res = await* _maker_update(_pair, _maker, maker_wasm, #upgrade, { name = _name });
        ignore _putEvent(#upgradeMaker({ version = _version; pair = _pair; maker = _maker; name = _name; completed = Option.isSome(res) }), ?Tools.principalToAccountBlob(msg.caller, null));
        return res;
    };

    /// Upgrade all ICDexMakers.  
    public shared(msg) func maker_updateAll(_version: Text, _updatePrivateMakers: Bool) : async {total: Nat; success: Nat; failures: [(Principal, Principal)]}{ 
        assert(_onlyOwner(msg.caller));
        assert(_version == maker_wasmVersion);
        var total : Nat = 0;
        var success : Nat = 0;
        var failures: [(Principal, Principal)] = [];
        for ((pair, makers) in Trie.iter(maker_publicCanisters)){
            for ((maker, creator) in makers.vals()){
                total += 1;
                try{
                    let res = await* _maker_update(pair, maker, maker_wasm, #upgrade, { name = null });
                    ignore _putEvent(#upgradeMaker({ version = _version; pair = pair; maker = maker; name = null; completed = Option.isSome(res) }), ?Tools.principalToAccountBlob(msg.caller, null));
                    success += 1;
                }catch(e){
                    failures := Tools.arrayAppend(failures, [(pair, maker)]);
                };
            };
        };
        if (_updatePrivateMakers){
            for ((pair, makers) in Trie.iter(maker_privateCanisters)){
                for ((maker, creator) in makers.vals()){
                    total += 1;
                    try{
                        let res = await* _maker_update(pair, maker, maker_wasm, #upgrade, { name = null });
                        ignore _putEvent(#upgradeMaker({ version = _version; pair = pair; maker = maker; name = null; completed = Option.isSome(res) }), ?Tools.principalToAccountBlob(msg.caller, null));
                        success += 1;
                    }catch(e){
                        failures := Tools.arrayAppend(failures, [(pair, maker)]);
                    };
                };
            };
        };
        return {total = total; success = success; failures = failures};
    };

    /// Rollback an ICDexMaker canister.
    /// permissions: Dao, Private Maker Creator
    public shared(msg) func maker_rollback(_pair: Principal, _maker: Principal): async (canister: ?Principal){
        let accountId = Tools.principalToAccountBlob(msg.caller, null);
        assert(_onlyOwner(msg.caller) or (not(_isPublicMaker(_pair, _maker)) and _OnlyMakerCreator(_pair, _maker, accountId)));
        let res = await* _maker_update(_pair, _maker, maker_wasm_preVersion, #upgrade, { name = null });
        ignore _putEvent(#rollbackMaker({ pair = _pair; maker = _maker; completed = Option.isSome(res) }), ?Tools.principalToAccountBlob(msg.caller, null));
        return res;
    };

    /// Let ICDexMaker approve the `_amount` of the sysToken the trading pair could spend.
    public shared(msg) func maker_approveToPair(_pair: Principal, _maker: Principal, _amount: Nat): async Bool{
        let accountId = Tools.principalToAccountBlob(msg.caller, null);
        assert(_onlyOwner(msg.caller) or _OnlyMakerCreator(_pair, _maker, accountId));
        let token: ICRC1.Self = actor(Principal.toText(sysToken));
        let arg: ICRC1.TransferArgs = {
            from_subaccount = null;
            to = {owner = _maker; subaccount = null};
            amount = sysTokenFee;
            fee = null;
            memo = null;
            created_at_time = null;
        };
        ignore await token.icrc1_transfer(arg);
        let maker : actor{
            approveToPair : shared (_token: Principal, _std: TokenStd, _amount: Nat) -> async Bool;
        } = actor(Principal.toText(_maker));
        return await maker.approveToPair(sysToken, #icrc1, _amount);
    };

    /// Remove an Automated Market Maker (ICDexMaker).
    /// permissions: Dao, Private Maker Creator
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
        // cyclesMonitor := CyclesMonitor.remove(cyclesMonitor, _maker);
        monitor.removeCanister(_maker);
        ignore _putEvent(#removeMaker({ pair = _pair; maker = _maker; }), ?Tools.principalToAccountBlob(msg.caller, null));
    };
    
    /// Modify the controllers of an ICDexMaker canister.
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
        ignore _putEvent(#makerSetControllers({ pair = _pair; maker = _maker; controllers = _controllers }), ?Tools.principalToAccountBlob(msg.caller, null));
        return true;
    };
    
    /// Configure an Automated Market Maker (ICDexMaker).
    public shared(msg) func maker_config(_maker: Principal, _config: Maker.Config) : async Bool{ 
        assert(_onlyOwner(msg.caller));
        let makerActor: Maker.Self = actor(Principal.toText(_maker));
        let res = await makerActor.config(_config);
        ignore _putEvent(#makerConfig({ maker = _maker; config = _config }), ?Tools.principalToAccountBlob(msg.caller, null));
        return res;
    };

    /// Lock or unlock an Automated Market Maker (ICDexMaker) system transaction lock.
    public shared(msg) func maker_transactionLock(_maker: Principal, _act: {#lock; #unlock}) : async Bool{ 
        assert(_onlyOwner(msg.caller));
        let makerActor: Maker.Self = actor(Principal.toText(_maker));
        let res = await makerActor.transactionLock(_act);
        ignore _putEvent(#makerTransactionLock({ maker = _maker; act = _act }), ?Tools.principalToAccountBlob(msg.caller, null));
        return res;
    };

    /// Pause or enable Automated Market Maker (ICDexMaker).
    public shared(msg) func maker_setPause(_maker: Principal, _pause: Bool) : async Bool{ 
        assert(_onlyOwner(msg.caller));
        let makerActor: Maker.Self = actor(Principal.toText(_maker));
        let res = await makerActor.setPause(_pause);
        if (_pause){
            ignore _putEvent(#makerSuspend({ maker = _maker}), ?Tools.principalToAccountBlob(msg.caller, null));
        }else{
            ignore _putEvent(#makerStart({ maker = _maker}), ?Tools.principalToAccountBlob(msg.caller, null));
        };
        return res;
    };

    /// Reset Automated Market Maker (ICDexMaker) local account balance.
    public shared(msg) func maker_resetLocalBalance(_maker: Principal) : async Maker.PoolBalance{ 
        assert(_onlyOwner(msg.caller));
        let makerActor: Maker.Self = actor(Principal.toText(_maker));
        let res = await makerActor.resetLocalBalance();
        ignore _putEvent(#makerResetLocalBalance({ maker = _maker; balance = res }), ?Tools.principalToAccountBlob(msg.caller, null));
        return res;
    };

    /// Withdraw funds from the trading pair to an Automated Market Maker (ICDexMaker) local account.
    public shared(msg) func maker_dexWithdraw(_maker: Principal, _token0: Nat, _token1: Nat) : async (token0: Nat, token1: Nat){ 
        assert(_onlyOwner(msg.caller));
        let makerActor: Maker.Self = actor(Principal.toText(_maker));
        let res = await makerActor.dexWithdraw(_token0, _token1);
        ignore _putEvent(#makerDexWithdraw({ maker = _maker; token0 = _token0; token1 = _token1; result = res }), ?Tools.principalToAccountBlob(msg.caller, null));
        return res;
    };

    /// Deposit from Automated Market Maker (ICDexMaker) to TraderAccount for the trading pair.
    public shared(msg) func maker_dexDeposit(_maker: Principal, _token0: Nat, _token1: Nat) : async (token0: Nat, token1: Nat){ 
        assert(_onlyOwner(msg.caller));
        let makerActor: Maker.Self = actor(Principal.toText(_maker));
        let res = await makerActor.dexDeposit(_token0, _token1);
        ignore _putEvent(#makerDexDeposit({ maker = _maker; token0 = _token0; token1 = _token1; result = res }), ?Tools.principalToAccountBlob(msg.caller, null));
        return res;
    };

    /// Deletes grid order from Automated Market Maker (ICDexMaker).
    public shared(msg) func maker_deleteGridOrder(_maker: Principal) : async (){ 
        assert(_onlyOwner(msg.caller));
        let makerActor: Maker.Self = actor(Principal.toText(_maker));
        await makerActor.deleteGridOrder();
        ignore _putEvent(#makerDeleteGridOrder({ maker = _maker; }), ?Tools.principalToAccountBlob(msg.caller, null));
    };

    /// Creates a grid order for Automated Market Maker (ICDexMaker) on the trading pair.
    public shared(msg) func maker_createGridOrder(_maker: Principal) : async (){ 
        assert(_onlyOwner(msg.caller));
        let makerActor: Maker.Self = actor(Principal.toText(_maker));
        await makerActor.createGridOrder();
        ignore _putEvent(#makerCreateGridOrder({ maker = _maker; }), ?Tools.principalToAccountBlob(msg.caller, null));
    };

    /// Cancels trade orders in pending on the trading pair placed by Automated Market Maker (ICDexMaker).
    public shared(msg) func maker_cancelAllOrders(_maker: Principal) : async (){ 
        assert(_onlyOwner(msg.caller));
        let makerActor: Maker.Self = actor(Principal.toText(_maker));
        await makerActor.cancelAllOrders();
        ignore _putEvent(#makerCancelAllOrders({ maker = _maker; }), ?Tools.principalToAccountBlob(msg.caller, null));
    };

    /* ===========================
      Events section
    ============================== */

    private func _putEvent(_event: Event, _a: ?AccountId) : BlockHeight{
        icEvents := ICEvents.putEvent<Event>(icEvents, eventBlockIndex, _event);
        switch(_a){
            case(?(accountId)){ 
                icAccountEvents := ICEvents.putAccountEvent(icAccountEvents, firstBlockIndex, accountId, eventBlockIndex);
            };
            case(_){};
        };
        eventBlockIndex += 1;
        return Nat.sub(eventBlockIndex, 1);
    };

    ignore _putEvent(#initOrUpgrade({version = version_}), ?Tools.principalToAccountBlob(installMsg.caller, null));

    /// Returns an event based on the block height of the event.
    public query func get_event(_blockIndex: BlockHeight) : async ?(Event, Timestamp){
        return ICEvents.getEvent(icEvents, _blockIndex);
    };

    /// Returns the height of the first block of the saved event record set. (Possibly earlier event records have been cleared).
    public query func get_event_first_index() : async BlockHeight{
        return firstBlockIndex;
    };

    /// Returns events list.
    public query func get_events(_page: ?ICDexTypes.ListPage, _size: ?ICDexTypes.ListSize) : async TrieList<BlockHeight, (Event, Timestamp)>{
        let page = Option.get(_page, 1);
        let size = Option.get(_size, 100);
        return ICEvents.trieItems2<(Event, Timestamp)>(icEvents, firstBlockIndex, eventBlockIndex, page, size);
    };

    /// Returns events by account.
    public query func get_account_events(_accountId: AccountId) : async [(Event, Timestamp)]{ //latest 1000 records
        return ICEvents.getAccountEvents<Event>(icEvents, icAccountEvents, _accountId);
    };

    /// Returns the total number of events (height of event blocks).
    public query func get_event_count() : async Nat{
        return eventBlockIndex;
    };

    /* =======================
      Cycles monitor
    ========================= */

    /// Put a canister-id into Cycles Monitor.
    public shared(msg) func monitor_put(_canisterId: Principal): async (){
        assert(_onlyOwner(msg.caller));
        // cyclesMonitor := await* CyclesMonitor.put(cyclesMonitor, _canisterId);
        await* monitor.putCanister(_canisterId);
    };

    /// Remove a canister-id from Cycles Monitor.
    public shared(msg) func monitor_remove(_canisterId: Principal): async (){
        assert(_onlyOwner(msg.caller));
        // cyclesMonitor := CyclesMonitor.remove(cyclesMonitor, _canisterId);
        monitor.removeCanister(_canisterId);
    };

    /// Returns the list of canister-ids in Cycles Monitor.
    public query func monitor_canisters(): async [(Principal, Nat)]{
        return Iter.toArray(Trie.iter(monitor.getCanisters()));
    };

    /// Returns a canister's caniter_status information.
    public shared(msg) func debug_canister_status(_canisterId: Principal): async CyclesMonitor.canister_status {
        assert(_onlyOwner(msg.caller));
        return await* CyclesMonitor.get_canister_status(_canisterId);
    };

    /// Perform a monitoring. Typically, monitoring is implemented in a timer.
    public shared(msg) func debug_monitor(): async (){
        assert(_onlyOwner(msg.caller));
        await monitor.run(Principal.fromActor(this));
    };

    /* =======================
      DRC207
    ========================= */
    // Default blackhole canister: 7hdtw-jqaaa-aaaak-aaccq-cai
    // ModuleHash(dfx: 0.8.4): 603692eda4a0c322caccaff93cf4a21dc44aebad6d71b40ecefebef89e55f3be
    // Github: https://github.com/iclighthouse/ICMonitor/blob/main/Blackhole.mo

    /// Returns the monitorability configuration of the canister.
    public query func drc207() : async DRC207.DRC207Support{
        return {
            monitorable_by_self = false;
            monitorable_by_blackhole = { allowed = true; canister_id = ?blackhole; };
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
                lastMonitorTime := _now();
                await monitor.run(Principal.fromActor(this));
            }catch(e){};
            for ((canisterId, totalCycles) in Trie.iter(monitor.getCanisters())){
                if (totalCycles >= canisterCyclesInit * 20 and Option.isNull(List.find(hotPairs, func(t: Principal): Bool{ t == canisterId }))){
                    hotPairs := List.push(canisterId, hotPairs);
                };
            };
            for (canisterId in List.toArray(hotPairs).vals()){
                try{ 
                    let pair: ICDexPrivate.Self = actor(Principal.toText(canisterId));
                    await pair.ictc_clearLog(?(2 * 30 * 24 * 3600 * 1_000_000_000), false);
                }catch(e){};
            };
        };
    };
    private var timerId: Nat = 0;

    /// Start the Timer, it will be started automatically when upgrading the canister.
    public shared(msg) func timerStart(_intervalSeconds: Nat): async (){
        assert(_onlyOwner(msg.caller));
        Timer.cancelTimer(timerId);
        timerId := Timer.recurringTimer(#seconds(_intervalSeconds), timerLoop);
        ignore _putEvent(#timerStart({ intervalSeconds = _intervalSeconds}), ?Tools.principalToAccountBlob(msg.caller, null));
    };

    /// Stop the Timer
    public shared(msg) func timerStop(): async (){
        assert(_onlyOwner(msg.caller));
        Timer.cancelTimer(timerId);
        ignore _putEvent(#timerStop, ?Tools.principalToAccountBlob(msg.caller, null));
    };

    /* =======================
      Upgrade
    ========================= */
    system func preupgrade() {
        cyclesMonitor := monitor.getCanisters();
        Timer.cancelTimer(timerId);
    };
    system func postupgrade() {
        monitor.setCanisters(cyclesMonitor);
        cyclesMonitor := Trie.empty();
        timerId := Timer.recurringTimer(#seconds(3*3600), timerLoop); //  /*config*/
    };

};