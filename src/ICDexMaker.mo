/**
 * Actor      : ICDexMaker
 * Author     : ICLighthouse Team
 * Stability  : Experimental
 * Github     : https://github.com/iclighthouse/ICDex/
 */
///
/// ## Overview
///
/// ICDexMaker is ICDex's Automated Market Maker contract (Canister) that provides liquidity to a trading pair. An Automated 
/// Market Maker is deployed in a separate canister that is managed by ICDexRouter.  
/// ICDexMaker simulates the effect of Uniswap AMM using grid strategy orders. It includes Public Maker and Private Maker:
/// - Public Maker is the public market making pool to which any user (LP) can add liquidity.
/// - Private Maker is a private market making pool to which only the creator (LP) can add liquidity.
/// Note: The #NEPTUNE NFT holder can bind the ICDexMaker canister-id to a vip-maker on ICDexRouter, then this ICDexMaker can 
/// obtain vip-maker status with rebate feature.
///
/// ## 1 Concepts
/// 
/// ### Roles
/// - Owner and DAO: The Owner (ICDexRouter) and DAO are the controllers of the ICDexMaker.
/// - Creator: The creator of ICDexMaker, the private ICDexMaker is only available to the creator.
/// - Liquidity provider (LP): Liquidity Providers (LPs) are holders of shares of liquidity in the ICDexMaker pool.
///
/// ### Automated Market Maker (AMM)
/// Decentralized automated market maker contract (ICDexMaker) is similar to Uniswap's AMM, but instead of a constant 
/// k model, it is based on order book DEX using a grid strategy for automated market making.
///
/// ### Liquidity Pool
/// In an AMM contract, the liquidity provided by the LPs are aggregated into a pool account which participates in 
/// the trading of the pair. Liquid assets include token0 and token1, whose balances are kept partly in trading pair 
/// and partly in local account.
/// 
/// ### Liquidity Share
/// Liquidity share is proof of the amount of assets held in the liquidity pool by the liquidity provider. When 
/// an LP adds liquidity, the liquidity pool calculates an increase of shares based on the NAV at 
/// that time; when an LP removes liquidity, the liquidity pool calculates the destruction of the corresponding shares 
/// based on the NAV at that time.
///
/// ### Net Asset Value (NAV)
/// Net Asset Value (NAV), Unit Value, is the token0 and token1 value per `shareUnitSize` shares in the liquidity pool.
/// ```
/// Token0 value (smallest_units) = shareUnitSize * Pool.token0Balance / TotalShares
/// Token1 value (smallest_units) = shareUnitSize * Pool.token1Balance / TotalShares
/// ```
/// where shareUnitSize is the UnitSize of the pair.
/// 
/// ### APY
/// The annual percentage yield (APY) is the real rate of return earned on providing liquidity. Since there are both token0 
/// and token1 assets in the liquidity pool, there is a difference between token0-based and token1-based calculation of APY. 
/// In token0-based, token1 is converted to token0 value at the current price before calculating APY; in token1-based, token0 
/// is converted to token1 value at the current price before calculating APY.
/// ```
/// 24h APY = (Current_NAV - NAV_24h_ago) / NAV_24h_ago * 365
/// 7d APY = (Current_NAV - NAV_7d_ago) / NAV_7d_ago / 7 * 365
/// ```
///
/// ### System Transaction Lock
/// ICDexMaker and trading pairs are in two different canisters, the transfer of funds between them is carried out asynchronously, 
/// and the execution of ICTC is also asynchronous, which affects the calculation of the NAV of the liquidity pool. In order to 
/// safely and accurately calculate the asset balance and NAV of the liquidity pool, a system transaction lock is designed so that 
/// parallel operations cannot be performed in the locked state.
///
/// ## 2 Deployment
///
/// ### Deploy ICDexMaker by ICDexRouter or manually
/// args:
/// ```
/// {
///     pair: Principal; // Trading pair caniser-id.
///     allow: {#Public; #Private}; // Visibility. #Public / #Private.
///     name: Text; // Name. e.g. "AAA_BBB AMM-1"
///     lowerLimit: Nat; // Lower price limit. How much token1 (smallest units) are needed to purchase UNIT_SIZE token0 (smallest units).
///     upperLimit: Nat; // Upper price limit. How much token1 (smallest units) are needed to purchase UNIT_SIZE token0 (smallest units).
///     spreadRate: Nat; // ppm. Inter-grid spread ratio for grid orders. e.g. 10_000, it means 1%. Recommended between 5000 and 50000 (i.e. 0.5% to 5%).
///     threshold: Nat; // token1 (smallest units). e.g. 1_000_000_000_000. After the total liquidity exceeds this threshold, the LP adds liquidity up to a limit of volFactor times his trading volume.
///     volFactor: Nat; // LP‘s liquidity limit = LP's trading volume * volFactor.  e.g. 2
/// }
/// ```
/// ### 
///
/// ## 3 Fee model
///
/// - Withdrawal fee: LP removes liquidity with a withdrawal fee, charged as a fixed fee plus a percentage of the withdrawal amount, 
/// which is calculated as `Fee = 10 * tokenFee + withdrawalFeeRate * value`, where tokenFee is the transfer fee for the token, 
/// withdrawalFeeRate is the fee rate, and value is the amount of the withdrawal.
/// 
/// ## 4 Core functionality
/// 
/// ### Liquidity pool
/// 
/// 1) Settlement
///
/// When liquidity is added and removed, both the NAV and the shares are recalculated once. The liquidity asset amount is fetched 
/// for each calculation and the following formula is adhered to as a guideline:
/// ```
/// NAV / shareUnitSize * shares = total liquidity
/// ```
/// 2) Funds in transit
///
/// Funds in transit occurs when trade orders are matched and when deposits or withdrawals are made between ICDexMaker and the pair, 
/// it can affect the accuracy of liquidity pool balances and NAVs, which may jeopardize asset security. Critical operations involving 
/// assets should be avoided when funds in transit exist. Security measures include:
/// - Use system transaction lock to avoid execution when funds in transit or transaction conflicts exist;
/// - Interrupts adding or removing liquidity when funds in transit or a transaction conflict exists;
/// - use the safeAccountBalance() method of the trading pair to query for funds in trading.
///
/// 3) Reserve funds
/// 
/// Most of the liquidity is deposited into the trading pair to participate in market making trading, while approximately 5-10% of 
/// the funds are kept in ICDexMaker's local account as a reserve for small liquidity removals. If the reserve balance is too low, 
/// some amount will be withdrawn from the pair to the local account when the LP removes liquidity.
///
/// 4) Grid strategy for market-making
///
/// ICDexMaker uses a grid strategy to participate in market making trading, which is a very simple and effective strategy. 
/// Uniswap's AMM model is a special case of a grid trading strategy (the grid interval is infinitely close to zero). In order to 
/// be able to maintain decentralized long-term execution, the strategy parameters are configured as relative values, avoiding the 
/// need to tweak the parameters. Important parameters include:
/// - spread = #Geom(gridSpread). The grid spread is configured as a ratio (ppm).
/// - amount = #Percent(null). The quantity (amount) of orders traded per grid is configured as #Percent and is specified as null, 
/// indicating that the proportion takes the value ppmFactor.
///     - ppmFactor: Default grid order amount factor, initialized when the strategy is created. `ppmFactor = 1000000 * 1/n * (n ** (1/10))`, 
/// Where n is `(n1 + n2) / 2`, and n1, n2 is between 2 and 200. n1 is the number of grids between the latest price and the lowerLimit, 
/// and n2 is the number of grids between the latest price and the upperLimit.
/// 
/// 5) Liquidity limit
///
/// ICDexMaker initially adds liquidity without limit, after the token1 balance of total liquidity reaches `threshold`, the liquidity limit 
/// rule will be activated and the user's liquidity limit (measured in token1) = the user's token1 volume in the current pair * volFactor. 
/// Note: threshold and volFactor are specified when ICDexMaker is created.  
/// The reason for this is that when a market making pool is more popular, there are too many users trying to add liquidity to it, 
/// which leads to the result that the liquidity yield will be lower. In order to prioritize users with higher contribution levels, 
/// the contribution level is measured by the user's volume of the pair, and this is used to calculate a limit on the amount of liquidity 
/// a user can add. 
/// 
/// 6) LP yield
///
/// LPs may benefit from adding liquidity to the liquidity pool, but it is risky and does not result in a stable gain or may result 
/// in a loss. Possible gains include:
/// - Grid spread gain: ICDexMaker opens a grid strategy in the trading pair, there exists a spread between every two grids, if the 
/// price shows upward and downward fluctuations, ICDexMaker can get the grid spread gain. However, if the price fluctuates in one 
/// direction, the number of ICDexMaker's one token will become more and the number of the other token will become less, and it will 
/// not get the spread gain. Therefore, the amount of grid spread gain is related to the volatility of the trading pair.   
/// - Vip-maker rebate: When ICDexMaker has the role of Vip-maker, it can get the trading fee rebate, and this part of the gain will 
/// go to the liquidity pool.
/// - Remove liquidity withdrawal fee: When an LP withdraws liquidity, he will be charged a withdrawal fee to be added to the liquidity 
/// pool.
/// - Liquidity mining/airdrop: this is a contingent benefit, ICDexMaker itself does not provide liquidity mining or token airdrop, 
/// which requires LPs to pay attention to the Dex platform side or the project side of the liquidity mining or airdrop activity 
/// announcement.
///
/// ### ICTC (This module is shared with the ICDexPair)
///
/// The purpose of ICTC module is to alleviate the atomicity problem in Defi development, and it mainly adopts Saga mode to centralize the 
/// management of asynchronous calls, improve data consistency, and increase the number of concurrency. The main application scenario of ICTC 
/// is the proactive (the current canister is the coordinator) multitasking transaction management, because such a scenario requires lower 
/// probability of external participation in compensation. ICTC is used for most token transfer transactions in ICDex and not during deposits. 
/// ICTC effectively reduces the number of times `await` is used in the core logic, improves concurrency, and provides a standardized way 
/// for testing and exception handling.   
///
/// A transaction order (id: toid) can contain multiple transaction tasks (id: ttid). Saga transaction execution modes include #Forward and 
/// #Backward.
/// - Forward: When an exception is encountered, the transaction will be in the #Blocking state, requiring the Admin (DAO) to perform a 
/// compensating operation.
/// - Backward: When an exception is encountered, the compensation function is automatically called to rollback. If no compensation function 
/// is provided, or if there is an error in executing the compensation function, the transaction will also be in #Blocking state, requiring 
/// the Admin (DAO) to compensate.
///
/// ICTC module is placed in the ICTC directory of the project, CallType.mo is a project customization file, SagaTM.mo and other files are 
/// from ICTC library https://github.com/iclighthouse/ICTC/
///
/// ICTC Explorer: https://cmqwp-uiaaa-aaaaj-aihzq-cai.raw.ic0.app/saga/  
/// Docs: https://github.com/iclighthouse/ICTC/blob/main/README.md  
///       https://github.com/iclighthouse/ICTC/blob/main/docs/ictc_reference-2.0.md
///
/// ### Events
///
/// Operations that call the core methods of the ICDexMaker are recorded in the Events system, sorted by ascending id number, making 
/// it easy for ecological participants to follow the behavior of the ICDexMaker. Older events may be deleted if the ICDexMaker's 
/// memory is heavily consumed, so someone could store the event history as needed.
///
/// ## 5 Backup and Recovery
///
/// The backup and recovery functions are not normally used, but are used when canister cannot be upgraded and needs to be reinstalled:
/// - call backup() method to back up the data.
/// - reinstall cansiter.
/// - call recovery() to restore the data.
/// 
/// Caution:
/// - If the data in this canister has a dependency on canister-id, it must be reinstalled in the same canister and cannot be migrated 
/// to a new canister.
/// - Normal access needs to be stopped during backup and recovery, otherwise the data may be contaminated.
/// - Backup and recovery operations have been categorized by variables, and each operation can only target one category of data, so 
/// multiple operations are required to complete the backup and recovery of all data.
/// - The backup and recovery operations are not paged for single-variable datasets. If you encounter a failure due to large data size, 
/// please try the following:
///     - Calling canister's cleanup function or configuration will delete stale data for some variables.
///     - Backup and recovery of non-essential data can be ignored.
///     - Query the necessary data through other query functions, and then call recovery() to restore the data.
///     - Abandon this solution and seek other data recovery solutions.
///
/// ## 6 API
///
import T "mo:icl/ICDexMaker";
import STO "mo:icl/STOTypes";
import Array "mo:base/Array";
import Binary "mo:icl/Binary";
import Blob "mo:base/Blob";
import Cycles "mo:base/ExperimentalCycles";
import DRC20 "mo:icl/DRC20";
import DRC207 "mo:icl/DRC207";
import Error "mo:base/Error";
import Float "mo:base/Float";
import Hash "mo:base/Hash";
import Hex "mo:icl/Hex";
import ICRC1 "mo:icl/ICRC1";
import ICRC2 "mo:icl/ICRC1";
import Int "mo:base/Int";
import Int64 "mo:base/Int64";
import List "mo:base/List";
import Nat "mo:base/Nat";
import Nat8 "mo:base/Nat8";
import Nat32 "mo:base/Nat32";
import Nat64 "mo:base/Nat64";
import Option "mo:base/Option";
import Principal "mo:base/Principal";
import Result "mo:base/Result";
import SagaTM "./ICTC/SagaTM";
import Text "mo:base/Text";
import Time "mo:base/Time";
import Tools "mo:icl/Tools";
import Trie "mo:base/Trie";
import ICDex "mo:icl/ICDexTypes";
import Iter "mo:base/Iter";
import Timer "mo:base/Timer";
import ICEvents "mo:icl/ICEvents";
import Backup "./lib/MakerBackupTypes";
 
shared(installMsg) actor class ICDexMaker(initArgs: T.InitArgs) = this {
    type Timestamp = T.Timestamp;  // seconds
    type Address = T.Address; // Text. Principal (text) or AccountId (hex text)
    type AccountId = T.AccountId;  // Blob
    type Amount = T.Amount; // Nat
    type Sa = T.Sa; // [Nat8]
    type Shares = T.Shares; // Nat
    type Nonce = T.Nonce; // Nat
    type Price = T.Price; // Nat
    type Data = T.Data; // [Nat8]
    type Txid = T.Txid; // Blob
    type PoolBalance = T.PoolBalance; // { balance0: Amount; balance1: Amount; ts: Timestamp };
    type UnitNetValue = T.UnitNetValue; // { ts: Timestamp; token0: Nat; token1: Nat; price: Price; shares: Nat; };
    type ShareWeighted = T.ShareWeighted; // { shareTimeWeighted: Nat; updateTime: Timestamp; };
    type TrieList<K, V> = T.TrieList<K, V>; // {data: [(K, V)]; total: Nat; totalPage: Nat; };

    private let version_: Text = "0.4.0";
    private let ns_: Nat = 1_000_000_000;
    private let sa_zero : [Nat8] = [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0];
    private var name_: Text = initArgs.name; // ICDexMaker name
    private stable var shareDecimals: Nat8 = 0; // The decimals of the shares, which is assigned at initialization time.
    private stable var shareUnitSize : Nat = 1; // Minimum base value of shares as UnitSize of NAV.
    private stable var paused: Bool = false;
    // private stable var owner: Principal = installMsg.caller;
    private var icdex_: Principal = installMsg.caller; // ICDexRouter canister-id
    private stable var creator: AccountId = initArgs.creator; // Creator account-id
    private stable var visibility: {#Public; #Private} = initArgs.allow;
    private stable var initialized: Bool = false;
    private stable var sysTransactionLock: Bool = false; // Global transaction lock
    private stable var withdrawalFee: Nat = 100; // ppm. 10000 means 1%.  (Fee: 10 * tokenFee + withdrawalFee * Value / 1000000)
    private stable var pairPrincipal: Principal = initArgs.pair; // Trading pair canister-id. An ICDexMaker can be bound to only one trading pair.
    private stable var token0Principal: Principal = initArgs.token0;
    private stable var token0Symbol: Text = "";
    private stable var token0Std: ICDex.TokenStd = initArgs.token0Std;
    private stable var token0Decimals: Nat8 = 0;
    private stable var token0Fee: Nat = 0;
    private stable var token1Principal: Principal = initArgs.token1;
    private stable var token1Symbol: Text = "";
    private stable var token1Std: ICDex.TokenStd = initArgs.token1Std;
    private stable var token1Decimals: Nat8 = 0;
    private stable var token1Fee: Nat = 0;
    private stable var pairUnitSize: Nat = initArgs.unitSize; // UnitSize of the pair.
    private stable var poolThreshold: Amount = initArgs.threshold; // token1 (smallest_units). Threshold for activating liquidity limit.
    private stable var volFactor: Nat = initArgs.volFactor; // A factor for calculating liquidity limits based on volumes.
    private stable var poolLocalBalance: PoolBalance = { balance0 = 0; balance1 = 0; ts = 0; };
    private stable var poolBalance: PoolBalance = { balance0 = 0; balance1 = 0; ts = 0; }; // poolBalance = poolLocalBalance + pair.traderAccountBalance
    private stable var poolShares: Nat = 0; // Total shares
    private stable var poolShareWeighted: ShareWeighted = { shareTimeWeighted = 0; updateTime = 0; }; // Time-weighted shares.
    private stable var unitNetValues: List.List<UnitNetValue> = List.nil<UnitNetValue>(); // NAVs. How much token0(smallest_units) and token1(smallest_units) per shareUnitSize share
    private stable var accountShares: Trie.Trie<AccountId, (Nat, ShareWeighted)> = Trie.empty(); // LPs shareholding data
    private stable var accountVolUsed: Trie.Trie<AccountId, Nat> = Trie.empty(); // Liquidity quotas utilized (Amount of token1)
    // Grid strategy parameters
    private stable var gridLowerLimit: Price = Nat.max(initArgs.lowerLimit, 1); // Lowest grid price
    private stable var gridUpperLimit: Price = initArgs.upperLimit; // Highest grid price
    private stable var gridSpread: Nat = Nat.max(initArgs.spreadRate, 100); // ppm. Inter-grid spread ratio for grid orders. e.g. 10_000, it means 1%.
    private stable var gridSoid : ?Nat = null; // If the grid order has been successfully created, save the strategy id.
    private stable var gridOrderDeleted : Bool = false; // Whether the strategy order has been canceled.
    // Events
    private stable var blockIndex : ICEvents.BlockHeight = 0;
    private stable var firstBlockIndex : ICEvents.BlockHeight = 0;
    private stable var blockEvents : ICEvents.ICEvents<T.Event> = Trie.empty(); 
    private stable var accountEvents : ICEvents.AccountEvents = Trie.empty(); 

    private func keyb(t: Blob) : Trie.Key<Blob> { return { key = t; hash = Blob.hash(t) }; };
    private func keyn(t: Nat) : Trie.Key<Nat> { return { key = t; hash = Tools.natHash(t) }; };
    private func keyt(t: Text) : Trie.Key<Text> { return { key = t; hash = Text.hash(t) }; };
    private func trieItems<K, V>(_trie: Trie.Trie<K,V>, _page: Nat, _size: Nat) : TrieList<K, V> {
        return Tools.trieItems(_trie, _page, _size);
    };

    private func _now() : Timestamp{
        return Int.abs(Time.now() / ns_);
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

    private func _accountIdToHex(_a: AccountId) : Text{
        return Hex.encode(Blob.toArray(_a));
    };

    private func _getThisAccount(_sub: Blob) : AccountId{
        let main = Principal.fromActor(this);
        let sa = Blob.toArray(_sub);
        return Blob.fromArray(Tools.principalToAccount(main, ?sa));
    };
    
    private func _toSaBlob(_sa: ?[Nat8]) : ?Blob{
        switch(_sa){
            case(?(sa)){ 
                if (sa.size() == 0 or sa == sa_zero){
                    return null;
                }else{
                    return ?Blob.fromArray(sa); 
                };
            };
            case(_){ return null; };
        }
    };

    private func _toSaNat8(_sa: ?Blob) : ?[Nat8]{
        switch(_sa){
            case(?(sa)){ 
                if (sa.size() == 0 or sa == Blob.fromArray(sa_zero)){
                    return null;
                }else{
                    return ?Blob.toArray(sa); 
                };
            };
            case(_){ return null; };
        }
    };

    private func _natToInt(_n: Nat) : Int{
        let n: Int = _n;
        return n;
    };

    private func _natToFloat(_n: Nat) : Float{
        return Tools.natToFloat(_n);
    };

    private func _floatToNat(_f: Float) : Nat{
        assert(_f >= 0);
        return Tools.floatToNat(_f);
    };

    private func _onlyOwner(_caller: Principal) : Bool { 
        return Principal.isController(_caller);
    }; 

    private func _onlyCreator(_a: AccountId) : Bool { 
        return _a == creator;
    }; 

    // Create saga object
    private var saga: ?SagaTM.SagaTM = null;
    private func _getSaga() : SagaTM.SagaTM {
        switch(saga){
            case(?(_saga)){ return _saga };
            case(_){
                let _saga = SagaTM.SagaTM(Principal.fromActor(this), ?_local, null, null); //?_taskCallback, ?_orderCallback
                saga := ?_saga;
                return _saga;
            };
        };
    };

    // Execute ICTC
    private func _ictcSagaRun(_toid: Nat, _forced: Bool): async* (){
        let saga = _getSaga();
        if (_toid == 0){
            try{
                let sagaRes = await* saga.getActuator().run();
            }catch(e){
                throw Error.reject("430: ICTC error: "# Error.message(e)); 
            };
        }else{
            try{
                if (_forced){
                    let sagaRes = await saga.runSync(_toid);
                }else{
                    let sagaRes = await saga.run(_toid);
                };
            }catch(e){
                throw Error.reject("430: ICTC error: "# Error.message(e)); 
            };
        };
    };

    // Local task entrance
    private func _local(_args: SagaTM.CallType, _receipt: ?SagaTM.Receipt) : async (SagaTM.TaskResult){
        switch(_args){
            case(#This(method)){
                switch(method){
                    case(_){return (#Error, null, ?{code=#future(9901); message="Non-local function."; });};
                };
            };
            case(_){ return (#Error, null, ?{code=#future(9901); message="Non-local function."; });};
        };
    };

    // // Task callback
    // private func _taskCallback(_toName: Text, _ttid: SagaTM.Ttid, _task: SagaTM.Task, _result: SagaTM.TaskResult) : async (){
    //     //taskLogs := Tools.arrayAppend(taskLogs, [(_ttid, _task, _result)]);
    // };
    // // Order callback
    // private func _orderCallback(_toName: Text, _toid: SagaTM.Toid, _status: SagaTM.OrderStatus, _data: ?Blob) : async (){
    //     //orderLogs := Tools.arrayAppend(orderLogs, [(_toid, _status)]);
    // };

    // Task builder
    private func _buildTask(_data: ?Data, _callee: Principal, _callType: SagaTM.CallType, _preTtid: [SagaTM.Ttid]) : SagaTM.PushTaskRequest{
        var cycles = 0;
        return {
            callee = _callee;
            callType = _callType;
            preTtid = _preTtid;
            attemptsMax = ?1;
            recallInterval = null; // nanoseconds  5 seconds
            cycles = cycles;
            data = _data;
        };
    };

    // Whether all transaction orders have been completed
    private func _ictcAllDone(): Bool{
        let tos = _getSaga().getAliveOrders();
        var res: Bool = true;
        for ((toid, order) in tos.vals()){
            switch(order){
                case(?(order_)){
                    if (order_.status != #Done and order_.status != #Recovered){
                        res := false;
                    };
                };
                case(_){};
            };
        };
        return res;
    };

    // Whether the specified transaction orders have been completed
    private func _ictcDone(_toids: [SagaTM.Toid]) : Bool{
        var completed: Bool = true;
        for (toid in _toids.vals()){
            let status = _getSaga().status(toid);
            if (status != ?#Done and status != ?#Recovered){
                completed := false;
            };
        };
        return completed;
    };
    
    // ICDexMaker will be suspended when there are 5 unprocessed transaction order errors
    private func _checkICTCError() : (){
        let count = _getSaga().getBlockingOrders().size();
        if (count >= 5){
            paused := true;
        };
    };

    private func _getBaseBalance(_sub: Blob) : async* Nat{  // token0
        let _a = _getThisAccount(_sub);
        var balance : Nat = 0;
        try{
            if (token0Std == #drc20){
                let token: DRC20.Self = actor(Principal.toText(token0Principal));
                let res = await token.drc20_balanceOf(_accountIdToHex(_a));
                balance := res;
            }else { // if (token0Std == #icrc1 or token0Std == #icp) 
                let token : ICRC1.Self = actor(Principal.toText(token0Principal));
                let res = await token.icrc1_balance_of({owner = Principal.fromActor(this); subaccount = ?_sub});
                balance := res;
            };
            return balance;
        }catch(e){
            throw Error.reject("query token0 balance error: "# Error.message(e)); 
        };
    };

    private func _getQuoteBalance(_sub: Blob) : async* Nat{ // token1
        let _a = _getThisAccount(_sub);
        var balance : Nat = 0;
        try{
            if (token1Std == #drc20){ // drc20
                let token: DRC20.Self = actor(Principal.toText(token1Principal));
                let res = await token.drc20_balanceOf(_accountIdToHex(_a));
                balance := res;
            }else { // #icrc1 or #icp
                let token : ICRC1.Self = actor(Principal.toText(token1Principal));
                let res = await token.icrc1_balance_of({owner = Principal.fromActor(this); subaccount = ?_sub});
                balance := res;
            };
            return balance;
        }catch(e){
            throw Error.reject("query token1 balance error: "# Error.message(e)); 
        };
    };

    private func _tokenTransfer(_token: Principal, _fromSa: Blob, _toIcrc1Account: ICRC1.Account, _value: Nat, _data: ?Blob) : async* (){  
        var _fee : Nat = 0;
        var _std : ICDex.TokenStd = #icrc1;
        if (_token == token0Principal){
            _fee := token0Fee;
            _std := token0Std;
        }else if (_token == token1Principal){
            _fee := token1Fee;
            _std := token1Std;
        };
        let _toAccount = Tools.principalToAccountBlob(_toIcrc1Account.owner, _toSaNat8(_toIcrc1Account.subaccount));
        if (_std == #drc20){
            let token: DRC20.Self = actor(Principal.toText(_token));
            try{
                let res = await token.drc20_transfer(_accountIdToHex(_toAccount), _value, null, ?Blob.toArray(_fromSa), _data);
                switch(res){
                    case(#ok(txid)){ 
                    };
                    case(#err(e)){ 
                        throw Error.reject("DRC20 token.drc20_transfer() error: "# e.message); 
                    };
                };
            }catch(e){
                throw Error.reject("Error transferring token: "# Error.message(e)); 
            };
        }else{ // #icrc1
            let token: ICRC1.Self = actor(Principal.toText(_token));
            try{
                let res = await token.icrc1_transfer({
                    from_subaccount = ?_fromSa;
                    to = _toIcrc1Account;
                    amount = _value;
                    fee = null;
                    memo = _data;
                    created_at_time = null; // nanos
                });
                switch(res){
                    case(#Ok(blockNumber)){ 
                    };
                    case(#Err(e)){ 
                        throw Error.reject("ICRC1 token.icrc1_transfer() error."); 
                    };
                };
            }catch(e){
                throw Error.reject("Error transferring token: "# Error.message(e)); 
            };
        };
    };

    private func _transferFrom(_token: Principal, _from: ICRC1.Account, _to: ICRC1.Account, _value: Nat, _data: ?Blob) : async* (){  
        var std : ICDex.TokenStd = #icrc1;
        if (_token == token0Principal){
            std := token0Std;
        }else if (_token == token1Principal){
            std := token1Std;
        };
        if (std == #drc20){
            let _fromAccount = Tools.principalToAccountBlob(_from.owner, _toSaNat8(_from.subaccount));
            let _toAccount = Tools.principalToAccountBlob(_to.owner, _toSaNat8(_to.subaccount));
            ignore await* _drc20TransferFrom(_token, _fromAccount, _toAccount, _value, _data);
        }else{
            ignore await* _icrc1TransferFrom(_token, _from, _to, _value, _data);
        };
    };

    private func _drc20TransferFrom(_token: Principal, _from: AccountId, _to: AccountId, _value: Nat, _data: ?Blob) : async* Txid{  
        let token: DRC20.Self = actor(Principal.toText(_token));
        try{
            let res = await token.drc20_transferFrom(_accountIdToHex(_from), _accountIdToHex(_to), _value, null, null, _data);
            switch(res){
                case(#ok(txid)){ 
                    return txid;
                };
                case(#err(e)){ 
                    throw Error.reject("DRC20 token.drc20_transferFrom() error: "# e.message); 
                };
            };
        }catch(e){
            throw Error.reject("Error transferring token: "# Error.message(e)); 
        };
    };

    private func _icrc1TransferFrom(_token: Principal, _from: ICRC1.Account, _to: ICRC1.Account, _value: Nat, _data: ?Blob): async* Nat{
        let token: ICRC1.Self = actor(Principal.toText(_token));
        let arg: ICRC1.TransferFromArgs = {
            spender_subaccount = null; // _toSaBlob(_sa); 
            from = _from;
            to = _to;
            amount = _value;
            fee = null;
            memo = _data;
            created_at_time = null;
        };
        try{
            let result = await token.icrc2_transfer_from(arg);
            switch(result){
                case(#Ok(blockNumber)){
                    return blockNumber;
                };
                case(#Err(e)){
                    throw Error.reject("ICRC1 token.icrc2_transfer_from() error: "# debug_show(e)); 
                };
            };
        }catch(e){
            throw Error.reject("Error transferring token: "# Error.message(e)); 
        };
    };

    // ICTC: send token from canister's subaccount
    private func _sendToken(_tokenSide: {#token0;#token1}, _toid: SagaTM.Toid, _fromSa: Blob, _preTtids: [SagaTM.Ttid], _toIcrc1Account: [ICRC1.Account], _value: [Nat], _transferData: ?Blob, _callback: ?SagaTM.Callback) : [SagaTM.Ttid]{
        assert(_toIcrc1Account.size() == _value.size());
        var ttids : [SagaTM.Ttid] = [];
        let saga = _getSaga();
        var std = token0Std;
        var tokenPrincipal = token0Principal;
        var fee = token0Fee;
        if (_tokenSide == #token1){
            std := token1Std;
            tokenPrincipal := token1Principal;
            fee := token1Fee;
        };
        var sub = ?_fromSa;
        var sa = ?Blob.toArray(_fromSa);
        if (Blob.toArray(_fromSa).size() == 0 or _fromSa == Blob.fromArray(sa_zero)){
            sub := null;
            sa := null;
        };
        if (std == #drc20 and _toIcrc1Account.size() > 1){
            let accountArr = Array.map<ICRC1.Account, Address>(_toIcrc1Account, func (t:ICRC1.Account): Address{
                _accountIdToHex(Tools.principalToAccountBlob(t.owner, _toSaNat8(t.subaccount)))
            });
            let valueArr = Array.map<Nat, Nat>(_value, func (t:Nat): Nat{
                if (t > fee){ Nat.sub(t, fee) }else{ 0 };
            });
            let task = _buildTask(sub, tokenPrincipal, #DRC20(#transferBatch(accountArr, valueArr, null, sa, _transferData)), _preTtids);
            let ttid = saga.push(_toid, task, null, _callback);
            // if (Option.isSome(_callback)){ _putTTCallback(ttid) };
            ttids := Tools.arrayAppend(ttids, [ttid]);
        }else{
            var i : Nat = 0;
            for (_to in _toIcrc1Account.vals()){
                let accountPrincipal = _toIcrc1Account[i].owner;
                let account = Tools.principalToAccountBlob(_toIcrc1Account[i].owner, _toSaNat8(_toIcrc1Account[i].subaccount));
                let icrc1Account = _toIcrc1Account[i];
                let value = (if (_value[i] > fee){ Nat.sub(_value[i], fee) }else{ 0 });
                if (std == #drc20){
                    let task = _buildTask(sub, tokenPrincipal, #DRC20(#transfer(_accountIdToHex(account), value, null, sa, _transferData)), _preTtids);
                    let ttid = saga.push(_toid, task, null, _callback);
                    // if (Option.isSome(_callback)){ _putTTCallback(ttid) };
                    ttids := Tools.arrayAppend(ttids, [ttid]);
                } else { // if (std == #icrc1 or std == #icp)
                    let args : ICRC1.TransferArgs = {
                        memo = _transferData;
                        amount = value;
                        fee = ?fee;
                        from_subaccount = sub;
                        to = icrc1Account;
                        created_at_time = null;
                    };
                    let task = _buildTask(sub, tokenPrincipal, #ICRC1New(#icrc1_transfer(args)), _preTtids);
                    let ttid = saga.push(_toid, task, null, _callback);
                    // if (Option.isSome(_callback)){ _putTTCallback(ttid) };
                    ttids := Tools.arrayAppend(ttids, [ttid]);
                };
                i += 1;
            };
        };
        return ttids;
    };

    private func _sendToken0(_toid: SagaTM.Toid, _fromSa: Blob, _preTtids: [SagaTM.Ttid], _toIcrc1Account: [ICRC1.Account], _value: [Nat], _transferData: ?Blob, _callback: ?SagaTM.Callback) : [SagaTM.Ttid]{
        return _sendToken(#token0, _toid, _fromSa, _preTtids, _toIcrc1Account, _value, _transferData, _callback);
    };

    private func _sendToken1(_toid: SagaTM.Toid, _fromSa: Blob, _preTtids: [SagaTM.Ttid], _toIcrc1Account: [ICRC1.Account], _value: [Nat], _transferData: ?Blob, _callback: ?SagaTM.Callback) : [SagaTM.Ttid] {
        return _sendToken(#token1, _toid, _fromSa, _preTtids, _toIcrc1Account, _value, _transferData, _callback);
    };

    private func _getNAV(_ts: ?Timestamp, _tsAdjust: Bool): UnitNetValue{
        let ts = Option.get(_ts, _now());
        var list: List.List<UnitNetValue> = unitNetValues;
        let (tempItem, tempList) = List.pop(list);
        var optItem = tempItem;
        list := tempList;
        var preItem: [UnitNetValue] = [];
        while(Option.isSome(optItem)){
            switch(optItem){
                case(?item){
                    if (item.ts <= ts and _tsAdjust and preItem.size() > 0){
                        let factor: Int = 100 * (Nat.sub(ts, item.ts)) / (Nat.sub(preItem[0].ts, item.ts)); // * 100
                        return {
                            ts = ts; 
                            token0 = Int.abs(_natToInt(item.token0) + (_natToInt(preItem[0].token0) - _natToInt(item.token0)) * factor / 100); 
                            token1 = Int.abs(_natToInt(item.token1) + (_natToInt(preItem[0].token1) - _natToInt(item.token1)) * factor / 100); 
                            price = Int.abs(_natToInt(item.price) + (_natToInt(preItem[0].price) - _natToInt(item.price)) * factor / 100);
                            shares = item.shares;
                        };
                    }else if (item.ts <= ts){
                        return item;
                    };
                    preItem := [item];
                };
                case(_){};
            };
            let (tempItem, tempList) = List.pop(list);
            optItem := tempItem;
            list := tempList;
        };
        return {
            ts = 0; 
            token0 = 0; 
            token1 = 0; 
            price = 0;
            shares = 0;
        };
    };

    private func _putNAV(_token0: Nat, _token1: Nat, _price: Price, _shares: Nat) : (){
        unitNetValues := List.push({
            ts = _now(); 
            token0 = _token0; 
            token1 = _token1; 
            price = _price;
            shares = _shares;
        }, unitNetValues);
    };

    private func _updateNAV(_price: ?Price) : (){
        let unitValue0 = shareUnitSize * poolBalance.balance0 / poolShares;
        let unitValue1 = shareUnitSize * poolBalance.balance1 / poolShares;
        let price = Option.get(_price, _getNAV(null, false).price);
        _putNAV(unitValue0, unitValue1, price, poolShares);
    };

    // Convert amounts to shares when adding liquidity.
    private func _amountToShares(_value: Amount, _tokenSide: {#token0; #token1}) : Nat{
        switch(_tokenSide){
            case(#token0){
                return shareUnitSize * _value / _getNAV(null, false).token0;
            };
            case(#token1){
                return shareUnitSize * _value / _getNAV(null, false).token1;
            };
        };
    };

    // Convert shares to amounts when removing liquidity.
    private func _sharesToAmount(_shares: Shares) : {value0: Amount; value1: Amount}{
        return {
            value0 = _shares * _getNAV(null, false).token0 / shareUnitSize; 
            value1 = _shares * _getNAV(null, false).token1 / shareUnitSize;
        };
    };

    private func _updatePoolLocalBalance(_token0: ?{#add: Amount; #sub: Amount; #set: Amount}, _token1: ?{#add: Amount; #sub: Amount; #set: Amount}) : (){
        var balance0 = poolLocalBalance.balance0;
        var balance1 = poolLocalBalance.balance1;
        switch(_token0){
            case(?#add(v)){ balance0 += v };
            case(?#sub(v)){ balance0 -= v };
            case(?#set(v)){ balance0 := v };
            case(_){};
        };
        switch(_token1){
            case(?#add(v)){ balance1 += v };
            case(?#sub(v)){ balance1 -= v };
            case(?#set(v)){ balance1 := v };
            case(_){};
        };
        poolLocalBalance := { balance0 = balance0; balance1 = balance1; ts = _now(); };
    };

    private func _updatePoolBalance(_token0: ?{#add: Amount; #sub: Amount; #set: Amount}, _token1: ?{#add: Amount; #sub: Amount; #set: Amount}) : (){
        var balance0 = poolBalance.balance0;
        var balance1 = poolBalance.balance1;
        switch(_token0){
            case(?#add(v)){ balance0 += v };
            case(?#sub(v)){ balance0 -= v };
            case(?#set(v)){ balance0 := v };
            case(_){};
        };
        switch(_token1){
            case(?#add(v)){ balance1 += v };
            case(?#sub(v)){ balance1 -= v };
            case(?#set(v)){ balance1 := v };
            case(_){};
        };
        poolBalance := { balance0 = balance0; balance1 = balance1; ts = _now(); };
    };

    private func _updatePoolShares(_act: {#add: Shares; #sub: Shares; #set: Shares}) : (){
        poolShareWeighted := _calcuShareWeighted(poolShareWeighted, poolShares);
        switch(_act){
            case(#add(v)){ poolShares += v };
            case(#sub(v)){ poolShares -= v };
            case(#set(v)){ poolShares := v };
        };
    };

    private func _getAccountShares(_a: AccountId) : (Nat, ShareWeighted){ 
        var now = _now();
        switch(Trie.get(accountShares, keyb(_a), Blob.equal)){
            case(?(shares)){
                if (now < shares.1.updateTime){ now := shares.1.updateTime; };
                let newShareTimeWeighted = shares.1.shareTimeWeighted + shares.0 * Nat.sub(now, shares.1.updateTime);
                return (shares.0, {shareTimeWeighted = newShareTimeWeighted; updateTime = now;});
            };
            case(_){
                return (0, {shareTimeWeighted = 0; updateTime = now;});
            };
        };
    };

    private func _updateAccountShares(_a: AccountId, _act: {#add: Shares; #sub: Shares; #set: Shares}) : (){
        let shares = _getAccountShares(_a);
        var newShares = shares.0;
        switch(_act){
            case(#add(v)){ newShares += v };
            case(#sub(v)){ newShares -= v };
            case(#set(v)){ newShares := v };
        };
        accountShares := Trie.put(accountShares, keyb(_a), Blob.equal, (newShares, shares.1)).0;
    };

    // Calculate the time-weighted value of the share.
    private func _calcuShareWeighted(_shareWeighted: ShareWeighted, _sheres: Shares) : ShareWeighted{
        var now = _now();
        if (now < _shareWeighted.updateTime){ now := _shareWeighted.updateTime; };
        return {
            shareTimeWeighted = _shareWeighted.shareTimeWeighted + _sheres * Nat.sub(now, _shareWeighted.updateTime);
            updateTime = now;
        };
    };

    // Push a task of creating a grid order to ICTC
    private func _ictcCreateGridOrder(_toid: Nat): (ttid: Nat){
        let saga = _getSaga();
        let task = _buildTask(null, pairPrincipal, #StratOrder(#sto_createProOrder(#GridOrder({
                lowerLimit = gridLowerLimit;
                upperLimit = gridUpperLimit;
                spread = #Geom(gridSpread);
                amount = #Percent(null);
            }), null)), []);
        // Assign soid to gridSoid when the task is completed
        return saga.push(_toid, task, null, ?(func(_toName: Text, _ttid: SagaTM.Ttid, _task: SagaTM.Task, _result: SagaTM.TaskResult) : async (){
            switch(_result.0, _result.1, _result.2){
                case(#Done, ?(#StratOrder(#sto_createProOrder(soid))), _){ gridSoid := ?soid };
                case(_, _, _){};
            };
        }));
    };

    // Push a task of updating a grid order to ICTC
    private func _ictcUpdateGridOrder(_toid: Nat, _status: STO.STStatus): (ttid: Nat){
        let saga = _getSaga();
        let task = _buildTask(null, pairPrincipal, #StratOrder(#sto_updateProOrder(Option.get(gridSoid, 0), #GridOrder({
                lowerLimit = ?gridLowerLimit;
                upperLimit = ?gridUpperLimit;
                spread = ?#Geom(gridSpread);
                amount = ?#Percent(null);
                status = ?_status;
            }), null)), []);
        return saga.push(_toid, task, null, null);
    };

    // Fetch the volume of an account in a trading pair
    private func _fetchAccountVol(_accountId: AccountId) : async* ICDex.Vol{
        let pair: ICDex.Self = actor(Principal.toText(pairPrincipal));
        let userLiquidity = await pair.liquidity2(?_accountIdToHex(_accountId));
        return userLiquidity.vol;
    };

    // Fetch ICDexMaker's balance in a trading pair
    private func _fetchPoolBalance() : async* (available0: Amount, available1: Amount){ // sysTransactionLock
        if (sysTransactionLock){
            throw Error.reject("401: The system transaction is locked, please try again later.");
        };
        let makerSubaccount = Blob.fromArray(sa_zero);
        let makerAccountId = _getThisAccount(makerSubaccount);
        let token0_: DRC20.Self = actor(Principal.toText(token0Principal));
        let token1_: DRC20.Self = actor(Principal.toText(token1Principal));
        let pair: ICDex.Self = actor(Principal.toText(pairPrincipal));
        let sto: STO.Self = actor(Principal.toText(pairPrincipal));
        var available0 : Amount = 0;
        var available1 : Amount = 0;
        sysTransactionLock := true;
        try{
            let dexBalance = await pair.safeAccountBalance(_accountIdToHex(makerAccountId));
            sysTransactionLock := false;
            let price = dexBalance.price;
            let localBalance0 = poolLocalBalance.balance0; // await* _getBaseBalance(makerSubaccount);
            let localBalance1 = poolLocalBalance.balance1; // await* _getQuoteBalance(makerSubaccount);
            let balance0 = localBalance0 + dexBalance.balance.token0.locked + dexBalance.balance.token0.available;
            available0 := localBalance0 + dexBalance.balance.token0.available;
            let balance1 = localBalance1 + dexBalance.balance.token1.locked + dexBalance.balance.token1.available;
            available1 := localBalance1 + dexBalance.balance.token1.available;
            _updatePoolBalance(?#set(balance0), ?#set(balance1));
            if (not(initialized) and  balance0 > 0 and balance1 > 0){
                let unitValue0 = pairUnitSize;
                let shares = shareUnitSize * balance0 / unitValue0;
                let unitValue1 = shareUnitSize * balance1 / shares;
                // _updatePoolShares(#add(shares));
                _putNAV(unitValue0, unitValue1, price, shares);
                // let accountId = Option.get(_initAccountId, Tools.principalToAccountBlob(owner, null));
                // _updateAccountShares(accountId, #add(shares));
                initialized := true;
            }else if (poolShares > 0){
                // _updatePoolShares(#add(0));
                _updateNAV(?price);
            };
            ignore _putEvent(#updateUnitNetValue({ 
                pairBalance = ?dexBalance.balance;
                localBalance = poolLocalBalance;
                poolBalance = poolBalance;
                poolShares = poolShares;
                unitNetValue = _getNAV(null, false);
            }), null);
        }catch(e){
            sysTransactionLock := false;
            throw Error.reject("402: There was a conflict or error fetching the data, please try again later.");
        };
        return (available0, available1);
    };

    // LP deposits to ICDexMaker's local account.
    private func _deposit(_side:{#token0; #token1}, _icrc1Account: ICRC1.Account, _amount: Amount) : async* Amount{
        var _fee : Nat = 0;
        var _canisterId : Principal = Principal.fromActor(this);
        var _std : ICDex.TokenStd = #drc20;
        if (_side == #token0){
            _fee := token0Fee;
            _canisterId := token0Principal;
            _std := token0Std;
        }else if (_side == #token1){
            _fee := token1Fee;
            _canisterId := token1Principal;
            _std := token1Std;
        };
        let _account = Tools.principalToAccountBlob(_icrc1Account.owner, _toSaNat8(_icrc1Account.subaccount));
        let _depositAccount = _getThisAccount(_account);
        var _depositIcrc1Account = {owner = Principal.fromActor(this); subaccount = ?_account};
        let _poolAccount = _getThisAccount(Blob.fromArray(sa_zero));
        var _poolIcrc1Account = {owner = Principal.fromActor(this); subaccount = null};
        var depositBalance: Nat = 0;
        var valueFromDepositBalance: Nat = 0; // 1: funds from DepositAccount
                                              // 2: funds from transferFrom()
        if (_side == #token0){
            depositBalance := await* _getBaseBalance(_account);
        }else{
            depositBalance := await* _getQuoteBalance(_account);
        };
        if (depositBalance >= _fee){
            valueFromDepositBalance := Nat.min(Nat.sub(depositBalance, _fee), _amount);
        } else {
            valueFromDepositBalance := 0;
        };
        // transferFrom
        if (valueFromDepositBalance < _amount){ // ICRC2 and DRC20
            let value = Nat.sub(_amount, valueFromDepositBalance) + _fee;
            try{
                await* _transferFrom(_canisterId, _icrc1Account, _depositIcrc1Account, value, null);
                depositBalance += value;
                if (depositBalance >= _fee){
                    valueFromDepositBalance := Nat.min(Nat.sub(depositBalance, _fee), _amount);
                } else {
                    valueFromDepositBalance := 0;
                };
            }catch(e){
                throw Error.reject("405: Insufficient token balance! " # Error.message(e));
            };
        };
        // depositAccount -> pool
        if (valueFromDepositBalance > 0){ 
            if (_isFallbacking(_account)){
                throw Error.reject("407: You are fallbacking. Try again later.");
            };
            try{
                await* _tokenTransfer(_canisterId, _account, _poolIcrc1Account, valueFromDepositBalance, ?_account);
            }catch(e){
                throw Error.reject("406: Token transfer error: " # Error.message(e));
            };
        };
        return valueFromDepositBalance;
    };

    private stable var fallbacking_accounts = List.nil<(AccountId, Time.Time)>();
    private func _putFallbacking(_account: AccountId) : (){
        fallbacking_accounts := List.filter(fallbacking_accounts, func (t: (AccountId, Time.Time)): Bool{
            Time.now() < t.1 +  72 * 3600 * ns_  // 72h
        });
        fallbacking_accounts := List.push((_account, Time.now()), fallbacking_accounts);
    };
    private func _removeFallbacking(_account: AccountId) : (){
        fallbacking_accounts := List.filter(fallbacking_accounts, func (t: (Txid, Time.Time)): Bool{
            t.0 != _account
        });
    };
    private func _isFallbacking(_account: AccountId): Bool{
        return Option.isSome(List.find(fallbacking_accounts, func (t: (AccountId, Time.Time)): Bool{
            t.0 == _account and Time.now() < t.1 + 72 * 3600 * ns_  // 72h
        }));
    };

    // Retrieve funds when an LP has a deposit exception and the funds are left in his DepositAccount.
    private func _fallback(_icrc1Account: ICRC1.Account, instantly: Bool) : async* (value0: Amount, value1: Amount, toids: [Nat]){
        let sa_account = Tools.principalToAccountBlob(_icrc1Account.owner, _toSaNat8(_icrc1Account.subaccount));
        let icrc1Account = _icrc1Account;
        var value0: Nat = 0;
        var value1: Nat = 0;
        var toids: [Nat] = [];
        if (instantly or not(_isFallbacking(sa_account))){
            _putFallbacking(sa_account);
            try{
                value0 := await* _getBaseBalance(sa_account);
            }catch(e){
                throw Error.reject("420: internal call error: "# Error.message(e)); 
            };
            let saga = _getSaga();
            if (value0 > token0Fee){
                let toid = saga.create("fallback_1", #Backward, ?sa_account, ?(func (_toName: Text, _toid: Nat, _status: SagaTM.OrderStatus, _data: ?Blob) : async (){
                    if (_status == #Done or _status == #Recovered){
                        switch(_data){
                            case(?a){ _removeFallbacking(a) };
                            case(_){};
                        };
                    };
                }));
                toids := Tools.arrayAppend(toids, [toid]);
                ignore _sendToken0(toid, sa_account, [], [icrc1Account], [value0], ?sa_account, null);
                saga.close(toid);
                await* _ictcSagaRun(toid, true);
            };
            
            try{
                value1 := await* _getQuoteBalance(sa_account);
            }catch(e){
                throw Error.reject("420: internal call error: "# Error.message(e)); 
            };
            if (value1 > token1Fee){
                let toid = saga.create("fallback_1", #Backward, ?sa_account, ?(func (_toName: Text, _toid: Nat, _status: SagaTM.OrderStatus, _data: ?Blob) : async (){
                    if (_status == #Done or _status == #Recovered){
                        switch(_data){
                            case(?a){ _removeFallbacking(a) };
                            case(_){};
                        };
                    };
                }));
                toids := Tools.arrayAppend(toids, [toid]);
                ignore _sendToken1(toid, sa_account, [], [icrc1Account], [value1], ?sa_account, null);
                saga.close(toid);
                await* _ictcSagaRun(toid, true);
            };
        };
        return (value0, value1, toids);
    };

    // Pushes a transaction to ICTC to update the grid order, returning the transaction id.
    private func _updateGridOrder(_accountId: AccountId, _token0: Amount, _token1: Amount, _updateMode: {#auto; #instantly}) : SagaTM.Toid{ // sysTransactionLock
        assert(not(sysTransactionLock));
        sysTransactionLock := true;
        let pair: ICDex.Self = actor(Principal.toText(pairPrincipal));
        let makerAccount = Tools.principalToAccountBlob(Principal.fromActor(this), null);
        let dexDepositIcrc1Account = {owner = pairPrincipal; subaccount = ?makerAccount };
        let dexDepositAccount = Tools.principalToAccountBlob(pairPrincipal, ?Blob.toArray(makerAccount));
        let dexAccount = Tools.principalToAccountBlob(pairPrincipal, null);
        let saga = _getSaga();
        var ttidSize : Nat = 0;
        let toid = saga.create("dex_deposit", #Forward, null, ?(func (_toName: Text, _toid: SagaTM.Toid, _status: SagaTM.OrderStatus, _data: ?Blob) : async (){
            if (_status == #Done or _status == #Recovered){
                sysTransactionLock := false;
            };
        })); 
        if (_token0 > token0Fee){
            _updatePoolLocalBalance(?#sub(_token0), null);
            if (token0Std == #drc20){ 
                _updatePoolLocalBalance(?#sub(token0Fee), null);
                let task0 = _buildTask(?_accountId, token0Principal, #DRC20(#approve(_accountIdToHex(dexAccount), Nat.max(_token0, 10**Nat8.toNat(token0Decimals + 10)), null, null, null)), []);
                let ttid0 = saga.push(toid, task0, null, null);
            }else{
                let ttids0 = _sendToken0(toid, Blob.fromArray(sa_zero), [], [dexDepositIcrc1Account], [_token0], ?_accountId, null);
            };
            let task1 = _buildTask(?_accountId, pairPrincipal, #ICDex(#deposit(#token0, Nat.sub(_token0, token0Fee), null)), []);
            let ttid1 = saga.push(toid, task1, null, null);
            ttidSize += 2;
        };
        if (_token1 > token1Fee){
            _updatePoolLocalBalance(null, ?#sub(_token1));
            if (token1Std == #drc20){
                _updatePoolLocalBalance(null, ?#sub(token1Fee));
                let task0 = _buildTask(?_accountId, token1Principal, #DRC20(#approve(_accountIdToHex(dexAccount), Nat.max(_token1, 10**Nat8.toNat(token1Decimals + 10)), null, null, null)), []);
                let ttid0 = saga.push(toid, task0, null, null);
            }else{
                let ttids1 = _sendToken1(toid, Blob.fromArray(sa_zero), [], [dexDepositIcrc1Account], [_token1], ?_accountId, null);
            };
            let task1 = _buildTask(?_accountId, pairPrincipal, #ICDex(#deposit(#token1, Nat.sub(_token1, token1Fee), null)), []);
            let ttid1 = saga.push(toid, task1, null, null);
            ttidSize += 2;
        };
        if (_token0 > 0 or _token1 > 0){
            ignore _putEvent(#dexDeposit({token0 = _token0; token1 = _token1: Nat; toid=?toid}), null);
        };
        if (Option.isNull(gridSoid) and not(gridOrderDeleted)){
            let ttid2 = _ictcCreateGridOrder(toid);
            ignore _putEvent(#createGridOrder({toid=?toid}), ?_accountId);
            ttidSize += 1;
        }else if (not(gridOrderDeleted) and (_updateMode == #instantly or _token0 > poolBalance.balance0 / 5 or _token1 > poolBalance.balance1 / 5)){
            let ttid3 = _ictcUpdateGridOrder(toid, #Running);
            ignore _putEvent(#updateGridOrder({soid=gridSoid; toid=?toid}), ?_accountId);
            ttidSize += 1;
        };
        saga.close(toid);
        if (ttidSize == 0){
            sysTransactionLock := false;
            ignore saga.doneEmpty(toid);
        };
        return toid;
    };

    // Updates the amount of liquidity an account has utilized.
    private func _updateAccountVolUsed(_accountId: AccountId, _addVol: Amount): (){ // Amount of token1
        switch(Trie.get(accountVolUsed, keyb(_accountId), Blob.equal)){
            case(?v){
                accountVolUsed := Trie.put(accountVolUsed, keyb(_accountId), Blob.equal, v + _addVol).0;
            };
            case(_){
                accountVolUsed := Trie.put(accountVolUsed, keyb(_accountId), Blob.equal, _addVol).0;
            };
        };
    };

    // Calculate annualized rate of return (APY)
    private func _apy(_period: Timestamp, _nowToken0: Int, _nowToken1: Int, _nowPrice: Price) : {token0: Float; token1: Float}{
        let year = 365 * 24 * 3600; //seconds
        let now = _now();
        let start = Nat.sub(now, _period);
        var list = unitNetValues;
        var startToken0 : Int = 0;
        var startToken1 : Int = 0;
        var preTs: Timestamp = now;
        var preToken0: Int = _nowToken0;
        var preToken1: Int = _nowToken1;
        var prePrice: Price = _nowPrice;
        var isCompleted: Bool = false;
        while (not(isCompleted)){
            let item = List.pop(list);
            list := item.1;
            switch(item.0){
                case(?(unit)){
                    if (unit.ts >= start){
                        preTs := unit.ts;
                        preToken0 := unit.token0;
                        preToken1 := unit.token1;
                        prePrice := unit.price;
                    } else {
                        isCompleted := true;
                        let partial: Int = 100 * Int.sub(start, unit.ts) / Int.sub(preTs, unit.ts);
                        startToken0 := unit.token0 + Int.sub(preToken0, unit.token0) * partial / 100;
                        startToken1 := unit.token1 + Int.sub(preToken1, unit.token1) * partial / 100;
                    };
                };
                case(_){ isCompleted := true; };
            };
        };
        if (startToken0 == 0 or startToken1 == 0){
            return {token0 = 0.0; token1 = 0.0};
        }else{
            let nowValue0 = _nowToken0 + pairUnitSize * _nowToken1 / _nowPrice;
            let nowValue1 = _nowToken0 * _nowPrice / pairUnitSize + _nowToken1;
            let startValue0 = startToken0 + pairUnitSize * startToken1 / prePrice;
            let startValue1 = startToken0 * prePrice / pairUnitSize + startToken1;
            return {
                token0 = Float.fromInt(nowValue0 - startValue0) / Float.fromInt(startValue0) * Float.fromInt(year) / Float.fromInt(_period);
                token1 = Float.fromInt(nowValue1 - startValue1) / Float.fromInt(startValue1) * Float.fromInt(year) / Float.fromInt(_period);
            };
        };
    };

    // Synchronizes the basic information of the two tokens of the trading pair.
    private func _syncTokens() : async* (){
        //if (Time.now() > tokenSyncTime + setting.SYNC_INTERVAL){
            // token0
            if (token0Std == #drc20){
                let token0_: DRC20.Self = actor(Principal.toText(token0Principal));
                token0Symbol := await token0_.drc20_name();
                token0Fee := await token0_.drc20_fee();
                token0Decimals := await token0_.drc20_decimals();
            }else{
                let token0_: ICRC1.Self = actor(Principal.toText(token0Principal));
                token0Symbol := await token0_.icrc1_name();
                token0Fee := await token0_.icrc1_fee();
                token0Decimals := await token0_.icrc1_decimals();
            };
            // token1
            if (token1Std == #drc20){
                let token1_: DRC20.Self = actor(Principal.toText(token1Principal));
                token1Symbol := await token1_.drc20_name();
                token1Fee := await token1_.drc20_fee();
                token1Decimals := await token1_.drc20_decimals();
            }else{
                let token1_: ICRC1.Self = actor(Principal.toText(token1Principal));
                token1Symbol := await token1_.icrc1_name();
                token1Fee := await token1_.icrc1_fee();
                token1Decimals := await token1_.icrc1_decimals();
            };
        //};
    };

    // Initializes ICDexMaker.
    private func _init() : async* Bool{
        if (not(initialized)){
            await* _syncTokens();
            shareDecimals := 0;
            while (10 ** Nat8.toNat(shareDecimals) < pairUnitSize){
                shareDecimals += 1;
            };
            shareUnitSize := 10 ** Nat8.toNat(shareDecimals);
            let pair: ICDex.Self = actor(Principal.toText(pairPrincipal));
            await pair.accountConfig(#PoolMode, true, null);
            return true;
        };
        return false;
    };

    /* public functions */

    /// Deposit account when adding liquidity. 
    /// This is a query method, if called off-chain (e.g., web-side), You should generate the account address directly using the 
    /// following rule: `{owner = maker_canister_id; subaccount = ?your_accountId }`.
    public query func getDepositAccount(_account: Address) : async (ICRC1.Account, Address){ 
        let sa_account = _getAccountId(_account);
        return ({owner = Principal.fromActor(this); subaccount = ?sa_account }, _accountIdToHex(_getThisAccount(sa_account)));
    };

    /// Retrieve funds when an LP has a deposit exception and the funds are left in his DepositAccount.
    public shared(msg) func fallback(_sa: ?Sa) : async (value0: Amount, value1: Amount){
        if (paused or not(initialized)){
            throw Error.reject("400: The canister has been suspended."); 
        };
        let _account = Tools.principalToAccountBlob(msg.caller, _sa);
        let _icrc1Account = {owner = msg.caller; subaccount = _toSaBlob(_sa)};
        let res = await* _fallback(_icrc1Account, false);
        ignore _putEvent(#fallback({account = _icrc1Account; token0 = res.0; token1 = res.1; toids=res.2}), ?_account);
        return (res.0, res.1);
    };

    /// Adds liquidity.  
    /// The ratio of token0 to token1 needs to be estimated based on the current NAV, and the excess side of the token will be refunded.
    ///
    /// Arguments:
    /// - token0: Amount(smallest_units) of token0 to add
    /// - token1: Amount(smallest_units) of token1 to add
    /// - sa: ?Sa. Optionally specify the subaccount of the caller
    ///
    /// Results:
    /// - res: Shares. Share of the liquidity pool received
    public shared(msg) func add(_token0: Amount, _token1: Amount, _sa: ?Sa) : async Shares{
        if (paused){
            throw Error.reject("400: The canister has been suspended."); 
        };
        if (sysTransactionLock){
            throw Error.reject("401: The system transaction is locked, please try again later."); 
        };
        let _account = Tools.principalToAccountBlob(msg.caller, _sa);
        let _icrc1Account = {owner = msg.caller; subaccount = _toSaBlob(_sa)};
        assert(visibility == #Public or _onlyCreator(_account));
        assert(initialized or _onlyCreator(_account));
        let isInitAdd: Bool = not(initialized) or poolShares == 0;
        var isException: Bool = false;
        var exceptMessage: Text = "";
        if (not(initialized)){
            ignore await* _init();
        };
        let saga = _getSaga();
        // get vol
        if (poolBalance.balance1 > poolThreshold){
            var token1AmountLimit : Amount = 0;
            let vol = (await* _fetchAccountVol(_account)).value1 * volFactor;
            let volUsed = switch(Trie.get(accountVolUsed, keyb(_account), Blob.equal)){case(?(v)){ v }; case(_){ 0 }};
            if (vol > volUsed){
                token1AmountLimit := Nat.sub(vol, volUsed);
            };
            if (_token1 > token1AmountLimit){
                throw Error.reject("410: This Market Making Pool limits the amount of liquidity you can add based on historical volume. The maximum amount of liquidity you can add is: "# Nat.toText(token1AmountLimit / (10**Nat8.toNat(token1Decimals)))# " " # token1Symbol);
            };
        };
        // check amount
        if (isInitAdd and (_token0 < token0Fee * 100000 or _token1 < token1Fee * 100000)){
            throw Error.reject("411: Unavailable amount. The token0 minimum amount is: "# Nat.toText(token0Fee * 100000) #", the token1 minimum amount is: "# Nat.toText(token1Fee * 100000) #".");
        }else if (_token0 < token0Fee * 1000 or _token1 < token1Fee * 1000){
            throw Error.reject("411: Unavailable amount. The token0 minimum amount is: "# Nat.toText(token0Fee * 1000) #", the token1 minimum amount is: "# Nat.toText(token1Fee * 1000) #".");
        };
        if (_isFallbacking(_account)){
            throw Error.reject("416: The account is performing fallback.");
        };
        // deposit
        var depositedToken0: Amount = 0;
        var depositedToken1: Amount = 0;
        // _putFallbacking(_account); // Prevents calling fallback() during execution.
        try{
            depositedToken0 := await* _deposit(#token0, _icrc1Account, _token0); // transfer token to pool
            ignore _putEvent(#deposit({account=_icrc1Account; token0=_token0; token1=0}), ?_account);
            depositedToken1 := await* _deposit(#token1, _icrc1Account, _token1); // transfer token to pool
            ignore _putEvent(#deposit({account=_icrc1Account; token0=0; token1=_token1}), ?_account);
            // _removeFallbacking(_account);
        }catch(e){
            isException := true;
            // _removeFallbacking(_account);
            exceptMessage := "412: Exception on deposit. ("# Error.message(e) #")";
        };
        if (sysTransactionLock){
            isException := true;
            exceptMessage := "401: The system transaction is locked, please try again later. ";
        };
        // get unit net value and set shares
        var addLiquidityToken0: Amount = 0;
        var addLiquidityToken1: Amount = 0;
        var sharesTest: Nat = 0;
        if (not(isException) and depositedToken0 > 0 and depositedToken1 > 0){
            if (isInitAdd){
                _updatePoolLocalBalance(?#add(depositedToken0), ?#add(depositedToken1));
            };
            try{
                ignore await* _fetchPoolBalance(); // sysTransactionLock
            }catch(e){
                sysTransactionLock := false;
                isException := true;
                exceptMessage := "413: Exception on fetching pool balance. ("# Error.message(e) #")";
            };
            if (sysTransactionLock){
                isException := true;
                exceptMessage := "401: The system transaction is locked, please try again later.  ";
            };
            if (not(isException)){
                let unitNetValue = _getNAV(null, false);
                if (isInitAdd){
                    addLiquidityToken0 := depositedToken0;
                    addLiquidityToken1 := depositedToken1;
                    sharesTest := shareUnitSize * depositedToken0 / unitNetValue.token0;
                    _updateAccountShares(_account, #add(sharesTest));
                    _updatePoolShares(#add(sharesTest));
                }else{
                    // _updatePoolLocalBalance(?#add(depositedToken0), null);
                    // _updatePoolLocalBalance(null, ?#add(depositedToken1));
                    addLiquidityToken0 := depositedToken0;
                    sharesTest := shareUnitSize * addLiquidityToken0 / unitNetValue.token0;
                    addLiquidityToken1 := sharesTest * unitNetValue.token1 / shareUnitSize;
                    if (addLiquidityToken1 > depositedToken1){
                        addLiquidityToken1 := depositedToken1;
                        sharesTest := shareUnitSize * addLiquidityToken1 / unitNetValue.token1;
                        addLiquidityToken0 := sharesTest * unitNetValue.token0 / shareUnitSize;
                    };
                    _updateAccountShares(_account, #add(sharesTest));
                    _updatePoolShares(#add(sharesTest));
                    _updateAccountVolUsed(_account, addLiquidityToken1);
                };
            };
        };
        var toids: [Nat] = [];
        // refund
        if (depositedToken0 > addLiquidityToken0 + token0Fee){
            let toid = saga.create("refund_0", #Forward, null, null);
            let value = Nat.sub(depositedToken0, addLiquidityToken0);
            if (isInitAdd){ _updatePoolLocalBalance(?#sub(value), null); };
            ignore _sendToken0(toid, Blob.fromArray(sa_zero), [], [_icrc1Account], [value], ?_account, null);
            saga.close(toid);
            toids := Tools.arrayAppend(toids, [toid]);
        };
        if (depositedToken1 > addLiquidityToken1 + token1Fee){
            let toid = saga.create("refund_1", #Forward, null, null);
            let value = Nat.sub(depositedToken1, addLiquidityToken1);
            if (isInitAdd){ _updatePoolLocalBalance(null, ?#sub(value)); };
            ignore _sendToken1(toid, Blob.fromArray(sa_zero), [], [_icrc1Account], [value], ?_account, null);
            saga.close(toid);
            toids := Tools.arrayAppend(toids, [toid]);
        };
        // GridOrder
        var gridToid : Nat = 0;
        if (addLiquidityToken0 > 0 and addLiquidityToken1 > 0){
            if (not(isInitAdd)){
                _updatePoolLocalBalance(?#add(addLiquidityToken0), ?#add(addLiquidityToken1));
            };
            if (poolLocalBalance.balance0 > poolBalance.balance0 * 10 / 100 or poolLocalBalance.balance1 > poolBalance.balance1 * 10 / 100){ 
                let value0 = Nat.sub(poolLocalBalance.balance0, poolBalance.balance0 * 5 / 100);
                let value1 = Nat.sub(poolLocalBalance.balance1, poolBalance.balance1 * 5 / 100);
                let toid = _updateGridOrder(_account, value0, value1, #auto); // sysTransactionLock
                gridToid := toid;
                toids := Tools.arrayAppend(toids, [toid]);
            };
        };
        // exception
        if (isException){
            await* _ictcSagaRun(gridToid, false);
            ignore _putEvent(#add(#err({account = _icrc1Account; depositToken0 = depositedToken0; depositToken1 = depositedToken1; toids=toids})), ?_account);
            throw Error.reject(exceptMessage);
        };
        // fallback
        try{
            let r = await* _fallback(_icrc1Account, true);
            ignore _putEvent(#fallback({account = _icrc1Account; token0 = r.0; token1 = r.1; toids=r.2}), ?_account);
        }catch(e){};
        // run ictc
        await* _ictcSagaRun(gridToid, false);
        // return 
        ignore _putEvent(#add(#ok({account = _icrc1Account; shares = sharesTest; token0 = addLiquidityToken0; token1 = addLiquidityToken1; toids=toids})), ?_account);
        return sharesTest;
    };

    /// Removes liquidity.  
    ///
    /// Arguments:
    /// - shares: Share of liquidity to be removed
    /// - sa: ?Sa. Optionally specify the subaccount of the caller
    ///
    /// Results:
    /// - res: (value0: Amount, value1: Amount). Amounts of token0 and token1 received
    public shared(msg) func remove(_shares: Amount, _sa: ?Sa) : async (value0: Amount, value1: Amount){
        if (paused or not(initialized)){
            throw Error.reject("400: The canister has been suspended."); 
        };
        if (sysTransactionLock){
            throw Error.reject("401: The system transaction is locked, please try again later."); 
        };
        let _account = Tools.principalToAccountBlob(msg.caller, _sa);
        let _icrc1Account = {owner = msg.caller; subaccount = _toSaBlob(_sa)};
        // assert(visibility == #Public or _onlyCreator(_account));
        var isException: Bool = false;
        var exceptMessage: Text = "";
        var resValue0 : Amount = 0;
        var resValue1 : Amount = 0;
        var sharesAvailable = _getAccountShares(_account).0;
        if (_shares > sharesAvailable){
            throw Error.reject("415: Insufficient shares balance."); 
        };
        let minShares = Nat.min(100 * (10 ** Nat8.toNat(shareDecimals)), sharesAvailable);
        if (_shares < minShares){
            throw Error.reject("417: The share entered must not be less than the minimum share "# Float.toText(_natToFloat(minShares) / _natToFloat(10 ** Nat8.toNat(shareDecimals))) #"."); 
        };
        let saga = _getSaga();
        // get unit net value
        var available0InPool: Amount = 0;
        var available1InPool: Amount = 0;
        try{
            let (v0, v1) = await* _fetchPoolBalance(); // sysTransactionLock
            available0InPool := v0;
            available1InPool := v1;
        }catch(e){
            sysTransactionLock := false;
            throw Error.reject("413: Exception on fetching pool balance. ("# Error.message(e) #")"); 
        };
        if (sysTransactionLock){
            throw Error.reject("401: The system transaction is locked, please try again later."); 
        };
        var values = _sharesToAmount(_shares);
        if (values.value0 > available0InPool or values.value1 > available1InPool){
            let toid = saga.create("stop_gridOrder", #Forward, null, null); 
            let ttid = _ictcUpdateGridOrder(toid, #Stopped);
            await* _ictcSagaRun(toid, true);
            try{
                let (v0, v1) = await* _fetchPoolBalance(); // sysTransactionLock
                available0InPool := v0;
                available1InPool := v1;
            }catch(e){
                sysTransactionLock := false;
                throw Error.reject("413: Exception on fetching pool balance. ("# Error.message(e) #")"); 
            };
            if (values.value0 > available0InPool or values.value1 > available1InPool){
                throw Error.reject("414: The number of shares entered is not available."); 
            };
        };
        // shares to amounts (Fee: 10 * tokenFee + 0.01% * Value)
        values := _sharesToAmount(_shares);
        if (values.value0 > 10 * token0Fee + values.value0 * withdrawalFee / 1000000){
            resValue0 := Nat.sub(values.value0, 10 * token0Fee + values.value0 * withdrawalFee / 1000000);
        };
        if (values.value1 > 10 * token1Fee + values.value1 * withdrawalFee / 1000000){
            resValue1 := Nat.sub(values.value1, 10 * token1Fee + values.value1 * withdrawalFee / 1000000);
        };
        if (resValue0 == 0 and resValue1 == 0){
            throw Error.reject("414: The number of shares entered is not available."); 
        };
        // withdraw from Dex
        if (resValue0 + token0Fee > poolLocalBalance.balance0 or resValue1 + token1Fee > poolLocalBalance.balance1){
            sysTransactionLock := true;
            let pair: actor{
                withdraw2: shared (_value0: ?Amount, _value1: ?Amount, _sa: ?Sa) -> async (value0: Amount, value1: Amount, status: {#Completed; #Pending});
            } = actor(Principal.toText(pairPrincipal));
            try{
                let value0 = if (resValue0 > 0){ ?Nat.max(Nat.min(resValue0 + token0Fee*2, Nat.sub(poolBalance.balance0, poolLocalBalance.balance0)), poolBalance.balance0 * 5 / 100) }else{ null };
                let value1 = if (resValue1 > 0){ ?Nat.max(Nat.min(resValue1 + token1Fee*2, Nat.sub(poolBalance.balance1, poolLocalBalance.balance1)), poolBalance.balance1 * 5 / 100) }else{ null };
                let (v0, v1, status) = await pair.withdraw2(value0, value1, null); 
                sysTransactionLock := false;
                _updatePoolLocalBalance(?#add(v0), ?#add(v1));
                ignore _putEvent(#dexWithdraw({token0 = v0; token1 = v1: Nat; toid=null}), null);
                if (poolLocalBalance.balance0 < resValue0 or poolLocalBalance.balance1 < resValue1){
                    throw Error.reject("Failed withdrawal");
                };
                if (status == #Pending){
                    throw Error.reject("The Pool account is being transferred, try again later.");
                };
            }catch(e){
                sysTransactionLock := false;
                throw Error.reject(Error.message(e));
            };
        };
        sharesAvailable := _getAccountShares(_account).0;
        // Remove liquidity
        if ((resValue0 > 0 or resValue1 > 0) and _shares <= sharesAvailable){
            // burn account's shares
            _updateAccountShares(_account, #sub(_shares));
            _updatePoolShares(#sub(_shares));
            // ictc: transfer
            _updatePoolLocalBalance(?#sub(resValue0 + token0Fee), ?#sub(resValue1 + token1Fee));
            let toid = saga.create("remove_liquidity", #Forward, null, null); 
            if (resValue0 > 0){
                let ttids = _sendToken0(toid, Blob.fromArray(sa_zero), [], [_icrc1Account], [resValue0 + token0Fee], ?_account, null);
            };
            if (resValue1 > 0){
                let ttids = _sendToken1(toid, Blob.fromArray(sa_zero), [], [_icrc1Account], [resValue1 + token1Fee], ?_account, null);
            };
            ignore _putEvent(#withdraw({account=_icrc1Account; token0=resValue0; token1=resValue1; toid=?toid}), ?_account);
            // update grid order
            if (not(gridOrderDeleted) and (resValue0 > poolBalance.balance0 / 5 or resValue1 > poolBalance.balance1 / 5)){
                let ttid2 = _ictcUpdateGridOrder(toid, #Running);
                ignore _putEvent(#updateGridOrder({soid=gridSoid; toid=?toid}), ?_account);
            };
            saga.close(toid);
            ignore _putEvent(#remove(#ok({account = _icrc1Account; shares = _shares; token0 = resValue0; token1 = resValue1; toid=?toid})), ?_account);
            await* _ictcSagaRun(toid, true);
        }else if (resValue0 > 0 or resValue1 > 0){
            ignore _putEvent(#remove(#err({account = _icrc1Account; addPoolToken0 = resValue0; addPoolToken1 = resValue1; toid=null})), ?_account);
            resValue0 := 0;
            resValue1 := 0;
        };
        return (resValue0, resValue1);
    };

    /// Returns the LP's liquidity share and time-weighted value.
    public query func getAccountShares(_account: Address) : async (Shares, ShareWeighted){
        let accountId = _getAccountId(_account);
        return _getAccountShares(accountId);
    };

    /// Returns the liquidity quota that has been used by the LP.
    public query func getAccountVolUsed(_account: Address): async Nat{ // token1 (smallest_units)
        let accountId = _getAccountId(_account);
        return switch(Trie.get(accountVolUsed, keyb(accountId), Blob.equal)){case(?(v)){ v }; case(_){ 0 }};
    };

    /// Returns NAV values.
    public query func getUnitNetValues() : async {shareUnitSize: Nat; data: [UnitNetValue]}{
        return {
            shareUnitSize = shareUnitSize; 
            data = Tools.slice(List.toArray(unitNetValues), 0, ?2000);
        };
    };

    /// Returns ICDexMaker information.
    public query func info() : async {
        version: Text;
        name: Text;
        paused: Bool;
        initialized: Bool;
        sysTransactionLock: Bool;
        visibility: {#Public; #Private};
        creator: AccountId;
        withdrawalFee: Float;
        poolThreshold: Amount;
        volFactor: Nat; // token1
        gridSoid: ?Nat;
        shareDecimals: Nat8;
        pairInfo: {
            pairPrincipal: Principal;
            pairUnitSize: Nat;
            token0: (Principal, Text, ICDex.TokenStd);
            token1: (Principal, Text, ICDex.TokenStd);
        };
        gridSetting: {
            gridLowerLimit: Price;
            gridUpperLimit: Price;
            gridSpread : Price;
        };
    }{
        return {
            version = version_;
            name = name_;
            paused = paused;
            initialized = initialized;
            sysTransactionLock = sysTransactionLock;
            visibility = visibility;
            creator = creator;
            withdrawalFee = _natToFloat(withdrawalFee) / 1000000;
            poolThreshold = poolThreshold;
            volFactor = volFactor; // token1
            gridSoid = gridSoid;
            shareDecimals = shareDecimals;
            pairInfo = {
                pairPrincipal = pairPrincipal;
                pairUnitSize = pairUnitSize;
                token0 = (token0Principal, token0Symbol, token0Std);
                token1 = (token1Principal, token1Symbol, token1Std);
            };
            gridSetting = {
                gridLowerLimit = gridLowerLimit;
                gridUpperLimit = gridUpperLimit;
                gridSpread = gridSpread;
            };
        };
    };

    /// Returns the latest status data for ICDexMaker. (Data may be delayed).
    public query func stats() : async {
        holders: Nat;
        poolBalance: PoolBalance; // pair.accountBalance + poolLocalBalance
        poolLocalBalance: PoolBalance;
        poolShares: Shares;
        poolShareWeighted: ShareWeighted;
        latestUnitNetValue: UnitNetValue;
    }{
        return {
            holders = Trie.size(accountShares);
            poolBalance = poolBalance;
            poolLocalBalance = poolLocalBalance;
            poolShares = poolShares;
            poolShareWeighted = poolShareWeighted;
            latestUnitNetValue = _getNAV(null, false);
        };
    };

    /// Returns the latest status data for ICDexMaker.  
    /// This is a composite query that will fetch the latest data.
    public shared composite query func stats2() : async {
        holders: Nat;
        poolBalance: PoolBalance; // pair.accountBalance + poolLocalBalance
        poolLocalBalance: PoolBalance;
        poolShares: Shares;
        poolShareWeighted: ShareWeighted;
        latestUnitNetValue: UnitNetValue;
        apy24h: {token0: Float; token1: Float};
        apy7d: {token0: Float; token1: Float};
    }{
        let pair: ICDex.Self = actor(Principal.toText(pairPrincipal));
        let makerAccountId = _getThisAccount(Blob.fromArray(sa_zero));
        let dexBalance = await pair.safeAccountBalance(_accountIdToHex(makerAccountId));
        let price = dexBalance.price;
        let localBalance0 = poolLocalBalance.balance0; // await* _getBaseBalance(Blob.fromArray(sa_zero));
        let localBalance1 = poolLocalBalance.balance1; // await* _getQuoteBalance(Blob.fromArray(sa_zero));
        let balance0 = localBalance0 + dexBalance.balance.token0.locked + dexBalance.balance.token0.available;
        let balance1 = localBalance1 + dexBalance.balance.token1.locked + dexBalance.balance.token1.available;
        let unitNetValue0 = shareUnitSize * balance0 / Nat.max(poolShares, 1);
        let unitNetValue1 = shareUnitSize * balance1 / Nat.max(poolShares, 1);
        return {
            holders = Trie.size(accountShares);
            poolBalance = { balance0 = balance0; balance1 = balance1; ts = _now(); };
            poolLocalBalance = poolLocalBalance;
            poolShares = poolShares;
            poolShareWeighted = poolShareWeighted;
            latestUnitNetValue = {
                ts = _now(); 
                token0 = unitNetValue0; 
                token1 = unitNetValue1; 
                price = price;
                shares = poolShares; 
            };
            apy24h = _apy(24 * 3600, unitNetValue0, unitNetValue1, price);
            apy7d = _apy(7 * 24 * 3600, unitNetValue0, unitNetValue1, price);
        };
    };
    
    /* ===========================
      Admin section
    ============================== */
    // public query func getOwner() : async Principal{  
    //     return owner;
    // };
    // public shared(msg) func changeOwner(_newOwner: Principal) : async Bool{ 
    //     assert(_onlyOwner(msg.caller));
    //     owner := _newOwner;
    //     ignore _putEvent(#changeOwner({newOwner = _newOwner}), ?Tools.principalToAccountBlob(msg.caller, null));
    //     return true;
    // };

    /// Configure the ICDexMaker.
    public shared(msg) func config(_config: T.Config) : async Bool{
        assert(_onlyOwner(msg.caller));
        if (sysTransactionLock){
            throw Error.reject("401: The system transaction is locked, please try again later.");
        };
        gridLowerLimit := Nat.max(Option.get(_config.lowerLimit, gridLowerLimit), 1);
        gridUpperLimit := Option.get(_config.upperLimit, gridUpperLimit);
        assert(gridUpperLimit > gridLowerLimit);
        gridSpread := Nat.max(Option.get(_config.spreadRatePpm, gridSpread), 100);
        poolThreshold := Option.get(_config.threshold, poolThreshold);
        volFactor := Option.get(_config.volFactor, volFactor);
        withdrawalFee := Option.get(_config.withdrawalFeePpm, withdrawalFee);
        ignore _putEvent(#config({setting = _config}), ?Tools.principalToAccountBlob(msg.caller, null));
        let toid = _updateGridOrder(Tools.principalToAccountBlob(msg.caller, null), 0, 0, #instantly); // sysTransactionLock
        ignore _putEvent(#updateGridOrder({soid=gridSoid; toid=?toid}), ?Tools.principalToAccountBlob(msg.caller, null));
        await* _ictcSagaRun(toid, true);
        return true;
    };

    /// Lock or unlock system transaction lock. Operate with caution! 
    /// Only need to call this method to unlock if there is a deadlock situation.
    public shared(msg) func transactionLock(_act: {#lock; #unlock}) : async Bool{
        assert(_onlyOwner(msg.caller) and paused);
        switch(_act){
            case(#lock){
                sysTransactionLock := true;
                ignore _putEvent(#lock({message = ?"sys transaction lock"}), ?Tools.principalToAccountBlob(msg.caller, null));
            };
            case(#unlock){
                sysTransactionLock := false;
                ignore _putEvent(#unlock({message = ?"sys transaction unlock"}), ?Tools.principalToAccountBlob(msg.caller, null));
            };
        };
        return true;
    };

    /// Pause or enable this ICDexMaker.
    public shared(msg) func setPause(_pause: Bool) : async Bool{ 
        assert(_onlyOwner(msg.caller));
        paused := _pause;
        if (paused){
            ignore _putEvent(#suspend({message = ?"Suspension from DAO"}), ?Tools.principalToAccountBlob(msg.caller, null));
        }else{
            ignore _putEvent(#start({message = ?"Starting from DAO"}), ?Tools.principalToAccountBlob(msg.caller, null));
        };
        return true;
    };

    /// Reset ICDexMaker's local account balance, which is only allowed to be operated when ICDexMaker is suspended. 
    /// Note that no funds in transit should exist at the time of operation.
    public shared(msg) func resetLocalBalance() : async PoolBalance{
        assert(_onlyOwner(msg.caller) and paused);
        let makerSubaccount = Blob.fromArray(sa_zero);
        let localBalance0 = await* _getBaseBalance(makerSubaccount);
        let localBalance1 = await* _getQuoteBalance(makerSubaccount);
        _updatePoolLocalBalance(?#set(localBalance0), ?#set(localBalance1));
        return poolLocalBalance;
    };

    /// Withdraw funds from the trading pair to ICDexMaker local account. This operation is not required for non-essential purposes.
    public shared(msg) func dexWithdraw(_token0: Amount, _token1: Amount) : async (token0: Amount, token1: Amount){ 
        assert(_onlyOwner(msg.caller) and paused);
        let pair: actor{
            withdraw2: shared (_value0: ?Amount, _value1: ?Amount, _sa: ?Sa) -> async (value0: Amount, value1: Amount, status: {#Completed; #Pending});
        } = actor(Principal.toText(pairPrincipal));
        if (sysTransactionLock){
            throw Error.reject("401: The system transaction is locked, please try again later.");
        };
        sysTransactionLock := true;
        try{
            let (v0, v1, status) = await pair.withdraw2((if (_token0 > 0){ ?(_token0 + token0Fee) }else{ null }), (if (_token1 > 0){ ?(_token1 + token1Fee) }else{ null }), null);
            sysTransactionLock := false;
            _updatePoolLocalBalance(?#add(v0), ?#add(v1));
            ignore _putEvent(#dexWithdraw({token0 = v0; token1 = v1: Nat; toid=null}), null);
            return (v0, v1);
        }catch(e){
            sysTransactionLock := false;
            throw Error.reject(Error.message(e));
        };
    };

    /// Deposit from ICDexMaker local account to TraderAccount in trading pair. This operation is not required for non-essential purposes.
    public shared(msg) func dexDeposit(_token0: Amount, _token1: Amount) : async (token0: Amount, token1: Amount){ 
        assert(_onlyOwner(msg.caller) and paused);
        var token0: Amount = 0;
        var token1: Amount = 0;
        let makerAccount = Tools.principalToAccountBlob(Principal.fromActor(this), null);
        let dexDepositIcrc1Account = {owner = pairPrincipal; subaccount = ?makerAccount };
        let dexDepositAccount = Tools.principalToAccountBlob(pairPrincipal, ?Blob.toArray(makerAccount));
        let dexAccount = Tools.principalToAccountBlob(pairPrincipal, null);
        let saga = _getSaga();
        if (sysTransactionLock){
            throw Error.reject("401: The system transaction is locked, please try again later.");
        };
        sysTransactionLock := true;
        let toid = saga.create("dex_deposit", #Forward, null, ?(func (_toName: Text, _toid: SagaTM.Toid, _status: SagaTM.OrderStatus, _data: ?Blob) : async (){
            if (_status == #Done or _status == #Recovered){
                sysTransactionLock := false;
            };
        })); 
        var ttidSize: Nat = 0;
        if (_token0 > token0Fee){
            _updatePoolLocalBalance(?#sub(_token0), null);
            if (token0Std == #drc20){ 
                _updatePoolLocalBalance(?#sub(token0Fee), null);
                let task0 = _buildTask(null, token0Principal, #DRC20(#approve(_accountIdToHex(dexAccount), Nat.max(_token0, 10**Nat8.toNat(token0Decimals + 10)), null, null, null)), []);
                let ttid0 = saga.push(toid, task0, null, null);
            }else{
                let ttids0 = _sendToken0(toid, Blob.fromArray(sa_zero), [], [dexDepositIcrc1Account], [_token0], null, null);
            };
            let task1 = _buildTask(null, pairPrincipal, #ICDex(#deposit(#token0, Nat.sub(_token0, token0Fee), null)), []);
            let ttid1 = saga.push(toid, task1, null, null);
            ttidSize += 2;
            token0 := _token0;
        };
        if (_token1 > token1Fee){
            _updatePoolLocalBalance(null, ?#sub(_token1));
            if (token1Std == #drc20){
                _updatePoolLocalBalance(null, ?#sub(token1Fee));
                let task0 = _buildTask(null, token1Principal, #DRC20(#approve(_accountIdToHex(dexAccount), Nat.max(_token1, 10**Nat8.toNat(token1Decimals + 10)), null, null, null)), []);
                let ttid0 = saga.push(toid, task0, null, null);
            }else{
                let ttids1 = _sendToken1(toid, Blob.fromArray(sa_zero), [], [dexDepositIcrc1Account], [_token1], null, null);
            };
            let task1 = _buildTask(null, pairPrincipal, #ICDex(#deposit(#token1, Nat.sub(_token1, token1Fee), null)), []);
            let ttid1 = saga.push(toid, task1, null, null);
            ttidSize += 2;
            token1 := _token1;
        };
        saga.close(toid);
        if (ttidSize == 0){
            ignore saga.doneEmpty(toid);
        };
        ignore _putEvent(#dexDeposit({token0 = token0; token1 = token1: Nat; toid=?toid}), null);
        await* _ictcSagaRun(toid, true);
        return (token0, token1);
    };

    /// Deletes the grid order for ICDexMaker.
    public shared(msg) func deleteGridOrder() : async (){
        assert(_onlyOwner(msg.caller) and paused);
        if (not(gridOrderDeleted)){
            let saga = _getSaga();
            let toid = saga.create("delete_gridOrder", #Forward, null, null); 
            let ttid1 = _ictcUpdateGridOrder(toid, #Deleted);
            saga.close(toid);
            ignore _putEvent(#deleteGridOrder({soid=gridSoid; toid=?toid}), null);
            await* _ictcSagaRun(toid, true);
            gridOrderDeleted := true;
        };
    };

    /// Creates a grid order for ICDexMaker.
    public shared(msg) func createGridOrder() : async (){
        assert(_onlyOwner(msg.caller) and paused);
        assert(Option.isNull(gridSoid) or gridOrderDeleted);
        let pair: ICDex.Self = actor(Principal.toText(pairPrincipal));
        await pair.accountConfig(#PoolMode, true, null);
        let saga = _getSaga();
        let toid = saga.create("create_gridOrder", #Forward, null, null); 
        let ttid1 = _ictcCreateGridOrder(toid);
        saga.close(toid);
        ignore _putEvent(#createGridOrder({toid=?toid}), null);
        await* _ictcSagaRun(toid, true);
        gridOrderDeleted := false;
    };

    /// Cancels all trade orders that the strategy order placed in the pair's order book.
    public shared(msg) func cancelAllOrders() : async (){
        assert(_onlyOwner(msg.caller) and paused);
        let pair: ICDex.Self = actor(Principal.toText(pairPrincipal));
        await pair.cancelAll(#self_sa(null), null);
    };

    /// Synchronize token information
    public shared(msg) func debug_sync() : async Bool{
        assert(_onlyOwner(msg.caller));
        await* _syncTokens();
        return true;
    };

    /* ===========================
      Events section
    ============================== */
    private func _putEvent(_event: T.Event, _a: ?ICEvents.AccountId) : ICEvents.BlockHeight{
        blockEvents := ICEvents.putEvent<T.Event>(blockEvents, blockIndex, _event);
        switch(_a){
            case(?(accountId)){ 
                accountEvents := ICEvents.putAccountEvent(accountEvents, firstBlockIndex, accountId, blockIndex);
            };
            case(_){};
        };
        blockIndex += 1;
        return Nat.sub(blockIndex, 1);
    };
    ignore _putEvent(#init({initArgs = initArgs}), null);

    /// Returns an event based on the block height of the event.
    public query func get_event(_blockIndex: ICEvents.BlockHeight) : async ?(T.Event, ICEvents.Timestamp){
        return ICEvents.getEvent(blockEvents, _blockIndex);
    };

    /// Returns the height of the first block of the saved event record set. (Possibly earlier event records have been cleared).
    public query func get_event_first_index() : async ICEvents.BlockHeight{
        return firstBlockIndex;
    };

    /// Returns events list.
    public query func get_events(_page: ?ICEvents.ListPage, _size: ?ICEvents.ListSize) : async ICEvents.TrieList<ICEvents.BlockHeight, (T.Event, ICEvents.Timestamp)>{
        let page = Option.get(_page, 1);
        let size = Option.get(_size, 100);
        return ICEvents.trieItems2<(T.Event, ICEvents.Timestamp)>(blockEvents, firstBlockIndex, blockIndex, page, size);
    };

    /// Returns events by account.
    public query func get_account_events(_accountId: ICEvents.AccountId) : async [(T.Event, ICEvents.Timestamp)]{ //latest 1000 records
        return ICEvents.getAccountEvents<T.Event>(blockEvents, accountEvents, _accountId);
    };

    /// Returns the total number of events (height of event blocks).
    public query func get_event_count() : async Nat{
        return blockIndex;
    };

    /* ===========================
      ICTC section
    ============================== */
    /**
    * ICTC Transaction Explorer Interface
    * (Optional) Implement the following interface, which allows you to browse transaction records and execute compensation transactions through a UI interface.
    * https://cmqwp-uiaaa-aaaaj-aihzq-cai.raw.ic0.app/
    */
    // ICTC: management functions
    private stable var ictc_admins: [Principal] = [];
    private func _onlyIctcAdmin(_caller: Principal) : Bool { 
        return Option.isSome(Array.find(ictc_admins, func (t: Principal): Bool{ t == _caller }));
    }; 
    private func _onlyBlocking(_toid: Nat) : Bool{
        /// Saga
        switch(_getSaga().status(_toid)){
            case(?(status)){ return status == #Blocking }; // or status == #Compensating
            case(_){ return false; };
        };
    };

    /// Returns the list of ICTC administrators
    public query func ictc_getAdmins() : async [Principal]{
        return ictc_admins;
    };

    /// Add ICTC Administrator
    public shared(msg) func ictc_addAdmin(_admin: Principal) : async (){
        assert(_onlyOwner(msg.caller) or _onlyIctcAdmin(msg.caller));
        if (Option.isNull(Array.find(ictc_admins, func (t: Principal): Bool{ t == _admin }))){
            ictc_admins := Tools.arrayAppend(ictc_admins, [_admin]);
        };
    };

    /// Rmove ICTC Administrator
    public shared(msg) func ictc_removeAdmin(_admin: Principal) : async (){
        assert(_onlyOwner(msg.caller) or _onlyIctcAdmin(msg.caller));
        ictc_admins := Array.filter(ictc_admins, func (t: Principal): Bool{ t != _admin });
    };

    /// Returns TM name for SagaTM Scan
    public query func ictc_TM() : async Text{
        return "Saga";
    };
    
    /// Returns total number of transaction orders
    public query func ictc_getTOCount() : async Nat{
        return _getSaga().count();
    };

    /// Returns a transaction order
    public query func ictc_getTO(_toid: SagaTM.Toid) : async ?SagaTM.Order{
        return _getSaga().getOrder(_toid);
    };

    /// Returns transaction order list
    public query func ictc_getTOs(_page: Nat, _size: Nat) : async {data: [(SagaTM.Toid, SagaTM.Order)]; totalPage: Nat; total: Nat}{
        return _getSaga().getOrders(_page, _size);
    };

    /// Returns lists of active transaction orders and transaction tasks
    public query func ictc_getPool() : async {toPool: {total: Nat; items: [(SagaTM.Toid, ?SagaTM.Order)]}; ttPool: {total: Nat; items: [(SagaTM.Ttid, SagaTM.Task)]}}{
        let tos = _getSaga().getAliveOrders();
        let tts = _getSaga().getActuator().getTaskPool();
        return {
            toPool = { total = tos.size(); items = Tools.slice(tos, 0, ?255)};
            ttPool = { total = tts.size(); items = Tools.slice(tts, 0, ?255)};
        };
    };

    /// Returns a list of active transaction orders
    public query func ictc_getTOPool() : async [(SagaTM.Toid, ?SagaTM.Order)]{
        return _getSaga().getAliveOrders();
    };

    /// Returns a record of a transaction task 
    public query func ictc_getTT(_ttid: SagaTM.Ttid) : async ?SagaTM.TaskEvent{
        return _getSaga().getActuator().getTaskEvent(_ttid);
    };

    /// Returns all tasks of a transaction order
    public query func ictc_getTTByTO(_toid: SagaTM.Toid) : async [SagaTM.TaskEvent]{
        return _getSaga().getTaskEvents(_toid);
    };

    /// Returns a list of transaction tasks
    public query func ictc_getTTs(_page: Nat, _size: Nat) : async {data: [(SagaTM.Ttid, SagaTM.TaskEvent)]; totalPage: Nat; total: Nat}{
        return _getSaga().getActuator().getTaskEvents(_page, _size);
    };

    /// Returns a list of active transaction tasks
    public query func ictc_getTTPool() : async [(SagaTM.Ttid, SagaTM.Task)]{
        return _getSaga().getActuator().getTaskPool();
    };

    /// Returns the transaction task records for exceptions
    public query func ictc_getTTErrors(_page: Nat, _size: Nat) : async {data: [(Nat, SagaTM.ErrorLog)]; totalPage: Nat; total: Nat}{
        return _getSaga().getActuator().getErrorLogs(_page, _size);
    };

    /// Returns the status of callee.
    public query func ictc_getCalleeStatus(_callee: Principal) : async ?SagaTM.CalleeStatus{
        return _getSaga().getActuator().calleeStatus(_callee);
    };

    // Transaction Governance

    /// Clear logs of transaction orders and transaction tasks.  
    /// Warning: Execute this method with caution
    public shared(msg) func ictc_clearLog(_expiration: ?Int, _delForced: Bool) : async (){ // Warning: Execute this method with caution
        assert(_onlyOwner(msg.caller));
        _getSaga().clear(_expiration, _delForced);
    };

    /// Clear the pool of running transaction tasks.  
    /// Warning: Execute this method with caution
    public shared(msg) func ictc_clearTTPool() : async (){ // Warning: Execute this method with caution
        assert(_onlyOwner(msg.caller));
        _getSaga().getActuator().clearTasks();
    };

    /// Change the status of a transaction order to #Blocking.
    public shared(msg) func ictc_blockTO(_toid: SagaTM.Toid) : async ?SagaTM.Toid{
        assert(_onlyOwner(msg.caller) or _onlyIctcAdmin(msg.caller));
        assert(not(_onlyBlocking(_toid)));
        let saga = _getSaga();
        return saga.block(_toid);
    };

    // public shared(msg) func ictc_removeTT(_toid: SagaTM.Toid, _ttid: SagaTM.Ttid) : async ?SagaTM.Ttid{ // Warning: Execute this method with caution
    //     assert(_onlyOwner(msg.caller) or _onlyIctcAdmin(msg.caller));
    //     assert(_onlyBlocking(_toid));
    //     let saga = _getSaga();
    //     saga.open(_toid);
    //     let ttid = saga.remove(_toid, _ttid);
    //     saga.close(_toid);
    //     return ttid;
    // };

    /// Governance or manual compensation (operation allowed only when a transaction order is in blocking status).
    public shared(msg) func ictc_appendTT(_businessId: ?Blob, _toid: SagaTM.Toid, _forTtid: ?SagaTM.Ttid, _callee: Principal, _callType: SagaTM.CallType, _preTtids: [SagaTM.Ttid]) : async SagaTM.Ttid{
        // Governance or manual compensation (operation allowed only when a transaction order is in blocking status).
        assert(_onlyOwner(msg.caller) or _onlyIctcAdmin(msg.caller));
        assert(_onlyBlocking(_toid));
        let saga = _getSaga();
        saga.open(_toid);
        let taskRequest = _buildTask(_businessId, _callee, _callType, _preTtids);
        //let ttid = saga.append(_toid, taskRequest, null, null);
        let ttid = saga.appendComp(_toid, Option.get(_forTtid, 0), taskRequest, null);
        return ttid;
    };

    /// Try the task again.  
    /// Warning: proceed with caution!
    public shared(msg) func ictc_redoTT(_toid: SagaTM.Toid, _ttid: SagaTM.Ttid) : async ?SagaTM.Ttid{
        // Warning: proceed with caution!
        assert(_onlyOwner(msg.caller) or _onlyIctcAdmin(msg.caller));
        let saga = _getSaga();
        let ttid = saga.redo(_toid, _ttid);
        await* _ictcSagaRun(_toid, true);
        return ttid;
    };

    /// Set status of a pending task  
    /// Warning: proceed with caution!
    public shared(msg) func ictc_doneTT(_toid: SagaTM.Toid, _ttid: SagaTM.Ttid, _toCallback: Bool) : async ?SagaTM.Ttid{
        // Warning: proceed with caution!
        assert(_onlyOwner(msg.caller) or _onlyIctcAdmin(msg.caller));
        let saga = _getSaga();
        try{
            let ttid = await* saga.taskDone(_toid, _ttid, _toCallback);
            return ttid;
        }catch(e){
            throw Error.reject("420: internal call error: "# Error.message(e)); 
        };
    };

    /// Set status of a pending order  
    /// Warning: proceed with caution!
    public shared(msg) func ictc_doneTO(_toid: SagaTM.Toid, _status: SagaTM.OrderStatus, _toCallback: Bool) : async Bool{
        // Warning: proceed with caution!
        assert(_onlyOwner(msg.caller) or _onlyIctcAdmin(msg.caller));
        let saga = _getSaga();
        try{
            let res = await* saga.done(_toid, _status, _toCallback);
            return res;
        }catch(e){
            throw Error.reject("420: internal call error: "# Error.message(e)); 
        };
    };

    /// Complete a blocking order  
    /// After governance or manual compensations, this method needs to be called to complete the transaction order.
    public shared(msg) func ictc_completeTO(_toid: SagaTM.Toid, _status: SagaTM.OrderStatus) : async Bool{
        // After governance or manual compensations, this method needs to be called to complete the transaction order.
        assert(_onlyOwner(msg.caller) or _onlyIctcAdmin(msg.caller));
        assert(_onlyBlocking(_toid));
        let saga = _getSaga();
        saga.close(_toid);
        await* _ictcSagaRun(_toid, true);
        try{
            let r = await* _getSaga().complete(_toid, _status);
            return r;
        }catch(e){
            throw Error.reject("430: ICTC error: "# Error.message(e)); 
        };
    };

    /// Run the ICTC actuator and check the status of the transaction order `toid`.
    public shared(msg) func ictc_runTO(_toid: SagaTM.Toid) : async ?SagaTM.OrderStatus{
        assert(_onlyOwner(msg.caller) or _onlyIctcAdmin(msg.caller));
        let saga = _getSaga();
        saga.close(_toid);
        // await* _ictcSagaRun(_toid, true);
        try{
            let r = await saga.run(_toid);
            return r;
        }catch(e){
            throw Error.reject("430: ICTC error: "# Error.message(e)); 
        };
    };

    /// Run the ICTC actuator
    public shared(msg) func ictc_runTT() : async Bool{ 
        // There is no need to call it normally, but can be called if you want to execute tasks in time when a TO is in the Doing state.
        if(_onlyOwner(msg.caller) or _onlyIctcAdmin(msg.caller) or _now() > lastRunTTTime + 30){
            lastRunTTTime := _now();
            await* _ictcSagaRun(0, true);
        };
        return true;
    };
    /**
    * End: ICTC Transaction Explorer Interface
    */


    /* ===========================
      DRC207 section
    ============================== */
    // Default blackhole canister: 7hdtw-jqaaa-aaaak-aaccq-cai
    // ModuleHash(dfx: 0.8.4): 603692eda4a0c322caccaff93cf4a21dc44aebad6d71b40ecefebef89e55f3be
    // Github: https://github.com/iclighthouse/ICMonitor/blob/main/Blackhole.mo

    /// Returns the monitorability configuration of the canister.
    public query func drc207() : async DRC207.DRC207Support{
        return {
            monitorable_by_self = false;
            monitorable_by_blackhole = { allowed = true; canister_id = null; };
            cycles_receivable = true;
            timer = { enable = false; interval_seconds = null; }; 
        };
    };
    /// canister_status
    // public shared(msg) func canister_status() : async DRC207.canister_status {
    //     // _sessionPush(msg.caller);
    //     // if (_tps(15, null).1 > setting.MAX_TPS*5 or _tps(15, ?msg.caller).0 > 2){ 
    //     //     assert(false); 
    //     // };
    //     let ic : DRC207.IC = actor("aaaaa-aa");
    //     await ic.canister_status({ canister_id = Principal.fromActor(this) });
    // };

    /// Receive cycles
    public func wallet_receive(): async (){
        let amout = Cycles.available();
        let accepted = Cycles.accept(amout);
    };

    /// Withdraw cycles
    public shared(msg) func withdraw_cycles(_amount: Nat) : async (){
        assert(_onlyOwner(msg.caller));
        type Wallet = actor{ wallet_receive : shared () -> async (); };
        let wallet : Wallet = actor(Principal.toText(icdex_));
        let amount = Cycles.balance();
        assert(_amount + 20000000000 < amount);
        Cycles.add(_amount);
        await wallet.wallet_receive();
    };

    /* ===========================
      Timer section
    ============================== */
    private var lastRunTTTime : Nat = 0;
    private func timerLoop() : async (){
        if(_now() > lastRunTTTime + 30){
            lastRunTTTime := _now();
            await* _ictcSagaRun(0, true);
        };
    };
    private var timerId: Nat = 0;

    /// Starts timer.
    public shared(msg) func timerStart(_intervalSeconds: Nat): async (){
        assert(_onlyOwner(msg.caller));
        Timer.cancelTimer(timerId);
        timerId := Timer.recurringTimer(#seconds(_intervalSeconds), timerLoop);
    };

    /// Stops timer.
    public shared(msg) func timerStop(): async (){
        assert(_onlyOwner(msg.caller));
        Timer.cancelTimer(timerId);
    };

    /* ===========================
      Upgrade section
    ============================== */
    private stable var __sagaDataNew: ?SagaTM.Data = null;
    private var __upgradeMode : {#Base; #All} = #All;
    public shared(msg) func setUpgradeMode(_mode: {#Base; #All}) : async (){
        assert(_onlyOwner(msg.caller));
        __upgradeMode := _mode;
    };
    system func preupgrade() {
        if (__upgradeMode == #All){
            __sagaDataNew := ?_getSaga().getData();
        }else{
            __sagaDataNew := ?_getSaga().getDataBase();
        };
        // assert(List.size(__sagaData[0].actuator.tasks.0) == 0 and List.size(__sagaData[0].actuator.tasks.1) == 0);
        Timer.cancelTimer(timerId);
    };
    system func postupgrade() {
        switch(__sagaDataNew){
            case(?(data)){
                _getSaga().setData(data);
                __sagaDataNew := null;
            };
            case(_){};
        };
        timerId := Timer.recurringTimer(#seconds(90), timerLoop);
    };
    
    /* ===========================
      Backup / Recovery section
    ============================== */
    /// ## Backup and Recovery
    /// The backup and recovery functions are not normally used, but are used when canister cannot be upgraded and needs to be reinstalled:
    /// - call backup() method to back up the data.
    /// - reinstall cansiter.
    /// - call recovery() to restore the data.
    /// Caution:
    /// - If the data in this canister has a dependency on canister-id, it must be reinstalled in the same canister and cannot be migrated to a new canister.
    /// - Normal access needs to be stopped during backup and recovery, otherwise the data may be contaminated.
    /// - Backup and recovery operations have been categorized by variables, and each operation can only target one category of data, so multiple operations are required to complete the backup and recovery of all data.
    /// - The backup and recovery operations are not paged for single-variable datasets. If you encounter a failure due to large data size, please try the following:
    ///     - Calling canister's cleanup function or configuration will delete stale data for some variables.
    ///     - Backup and recovery of non-essential data can be ignored.
    ///     - Query the necessary data through other query functions, and then call recovery() to restore the data.
    ///     - Abandon this solution and seek other data recovery solutions.
    
    // type Toid = SagaTM.Toid;
    // type Ttid = SagaTM.Ttid;
    type Order = SagaTM.Order;
    type Task = SagaTM.Task;
    type SagaData = Backup.SagaData;
    type BackupRequest = Backup.BackupRequest;
    type BackupResponse = Backup.BackupResponse;

    /// Backs up data of the specified `BackupRequest` classification, and the result is wrapped using the `BackupResponse` type.
    public shared(msg) func backup(_request: BackupRequest) : async BackupResponse{
        assert(_onlyOwner(msg.caller));
        switch(_request){
            case(#otherData){
                return #otherData({
                    shareDecimals = shareDecimals;
                    shareUnitSize = shareUnitSize;
                    creator = creator;
                    visibility = visibility;
                    poolLocalBalance = poolLocalBalance;
                    poolBalance = poolBalance;
                    poolShares = poolShares;
                    poolShareWeighted = poolShareWeighted;
                    gridSoid = gridSoid;
                    gridOrderDeleted = gridOrderDeleted;
                    blockIndex = blockIndex;
                    firstBlockIndex = firstBlockIndex;
                    ictc_admins = ictc_admins;
                });
            };
            case(#unitNetValues(mode)){
                if (mode == #All){
                    return #unitNetValues(List.toArray(unitNetValues));
                }else{
                    return #unitNetValues(Tools.slice(List.toArray(unitNetValues), 0, ?5000));
                };
            };
            case(#accountShares(mode)){
                if (mode == #All){
                    return #accountShares(Trie.toArray<AccountId, (Nat, ShareWeighted), (AccountId, (Nat, ShareWeighted))>(accountShares, 
                        func (k: AccountId, v: (Nat, ShareWeighted)): (AccountId, (Nat, ShareWeighted)){
                            return (k, v);
                        }));
                }else{
                    let trie = Trie.filter(accountShares, func (k: AccountId, v: (Nat, ShareWeighted)): Bool{ v.0 >= shareUnitSize * 10 });
                    return #accountShares(Trie.toArray<AccountId, (Nat, ShareWeighted), (AccountId, (Nat, ShareWeighted))>(trie, 
                        func (k: AccountId, v: (Nat, ShareWeighted)): (AccountId, (Nat, ShareWeighted)){
                            return (k, v);
                        }));
                };
            };
            case(#accountVolUsed(mode)){
                if (mode == #All){
                    return #accountVolUsed(Trie.toArray<AccountId, Nat, (AccountId, Nat)>(accountVolUsed, 
                        func (k: AccountId, v: Nat): (AccountId, Nat){
                            return (k, v);
                        }));
                }else{
                    let trie = Trie.filter(accountVolUsed, func (k: AccountId, v: Nat): Bool{ v >= 10 * 10 ** Nat8.toNat(token1Decimals) });
                    return #accountVolUsed(Trie.toArray<AccountId, Nat, (AccountId, Nat)>(trie, 
                        func (k: AccountId, v: Nat): (AccountId, Nat){
                            return (k, v);
                        }));
                };
            };
            case(#blockEvents){
                return #blockEvents(Trie.toArray<Nat, (T.Event, Timestamp), (Nat, (T.Event, Timestamp))>(blockEvents, 
                    func (k: Nat, v: (T.Event, Timestamp)): (Nat, (T.Event, Timestamp)){
                        return (k, v);
                    }));
            };
            case(#accountEvents){
                return #accountEvents(Trie.toArray<AccountId, List.List<Nat>, (AccountId, [Nat])>(accountEvents, 
                    func (k: AccountId, v: List.List<Nat>): (AccountId, [Nat]){
                        return (k, List.toArray(v));
                    }));
            };
            case(#fallbacking_accounts){
                return #fallbacking_accounts(List.toArray(fallbacking_accounts));
            };
        };
    };
    
    /// Restore `BackupResponse` data to the canister's global variable.
    public shared(msg) func recovery(_request: BackupResponse) : async Bool{
        assert(_onlyOwner(msg.caller));
        switch(_request){
            case(#otherData(data)){
                shareDecimals := data.shareDecimals;
                shareUnitSize := data.shareUnitSize;
                creator := data.creator;
                visibility := data.visibility;
                poolLocalBalance := data.poolLocalBalance;
                poolBalance := data.poolBalance;
                poolShares := data.poolShares;
                poolShareWeighted := data.poolShareWeighted;
                gridSoid := data.gridSoid;
                gridOrderDeleted := data.gridOrderDeleted;
                blockIndex := data.blockIndex;
                firstBlockIndex := data.firstBlockIndex;
                ictc_admins := data.ictc_admins;
            };
            case(#unitNetValues(data)){
                unitNetValues := List.fromArray(data);
            };
            case(#accountShares(data)){
                for ((k, v) in data.vals()){
                    accountShares := Trie.put(accountShares, keyb(k), Blob.equal, v).0;
                };
            };
            case(#accountVolUsed(data)){
                for ((k, v) in data.vals()){
                    accountVolUsed := Trie.put(accountVolUsed, keyb(k), Blob.equal, v).0;
                };
            };
            case(#blockEvents(data)){
                for ((k, v) in data.vals()){
                    blockEvents := Trie.put(blockEvents, keyn(k), Nat.equal, v).0;
                };
            };
            case(#accountEvents(data)){
                for ((k, v) in data.vals()){
                    accountEvents := Trie.put(accountEvents, keyb(k), Blob.equal, List.fromArray(v)).0;
                };
            };
            case(#fallbacking_accounts(data)){
                fallbacking_accounts := List.fromArray(data);
            };
        };
        return true;
    };

};
