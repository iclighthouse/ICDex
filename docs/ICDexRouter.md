# ICDexRouter
* Actor      : ICDexRouter
 * Author     : ICLighthouse Team
 * Stability  : Experimental
 * Github     : https://github.com/iclighthouse/ICDex/

## Overview

ICDexRouter is a factory that is responsible for creating and managing ICDexPair, and also for creating and managing ICDexMaker.

## 1 Concepts

### Owner (DAO)

Owner is the controller of the ICDexRouter, the initial value is creator, which can be modified to DAO canister for decentralization.

### System Token (Eco-Token, ICL)

System Token is ICDex's economic incentive token, i.e. ICL, a governance and utility token.

### ICDexPair (Trading Pair, TP)

ICDexPair, Trading Pair (TP), is deployed in a separate canister, managed by ICDexRouter. For example, the TP "AAA/BBB", 
AAA means base token and BBB eans quote token.

### ICDexMaker (Orderbook Automated Market Maker, OAMM)

ICDexMaker is Orderbook Automated Market Maker (OAMM) canister that provides liquidity to a trading pair. An OAMM is deployed 
in a separate canister that is managed by ICDexRouter.  OAMM simulates the effect of Uniswap AMM using grid strategy orders. 
It includes Public Maker and Private Maker:
- Public Maker is the public market making pool to which any user (LP) can add liquidity.
- Private Maker is a private market making pool to which only the creator (LP) can add liquidity.

### NFT

The NFT collection ICLighthouse Planet Cards (goncb-kqaaa-aaaap-aakpa-cai) has special qualifications for some of the features 
of ICDex, in addition to its own NFT properties. NFT holders have a discounted fee for creating an ICDexMaker. 
NFT holders of #NEPTUNE have the permission to bind a Vip-maker role.

## 2 Deployment

### Deploy ICDexRouter
args:
- initDAO: Principal.  // Owner (DAO) principal
- isDebug: Bool

### (optional) Config ICDexRouter
- call sys_config()
```
args: { // (If you fill in null for item, it means that this item will not be modified.)
    aggregator: ?Principal; // External trading pair aggregator. If not configured, it will not affect use.
    blackhole: ?Principal; // Black hole canister, which can be used as a controller for canisters to monitor their cycles and memory.
    icDao: ?Principal; // Owner (DAO) principal. The canister that governs ICDex is assigned the value initDAO at installation. a private principal can be filled in testing.
    nftPlanetCards: ?Principal; // ICLighthouse NFT.
    sysToken: ?Principal; // ICDex governance token canister-id.
    sysTokenFee: ?Nat; // smallest units. Transfer fee for ICDex governance token.
    creatingPairFee: ?Nat; // smallest units. The fee to be paid for creating a trading pair by pubCreate().
    creatingMakerFee: ?Nat; // smallest units. The fee to be paid for creating an automated market maker pool canister.
}
```

## 3 Fee model

- Creating ICDexPair: The user creates an ICDexPair and will be charged creatingPairFee (initial value is 5000 ICL); Owner (DAO) 
creates ICDexPair and is not charged.
- Creating ICDexMaker: The user creates an ICDexMaker and will be charged creatingMakerFee (initial value is 50 ICL).

## 4 Core functionality

### Trading pair creation and governance

- Trading pair creation: ICDexRouter is the contract factory for ICDexPair. Users can pay a fee (ICL) to create a trading pair; 
and Owner (DAO) can create a trading pair directly.
- Trading pair governance: The management of trading pairs by the Owner (DAO) includes upgrading, modifying the controller, 
and adding (deleting) the list of trading pairs, etc. ICDexRouter wraps the methods related to the governance of trading pair, so that 
the trading pair methods can be called through ICDexRouter to realize the governance.

### Automated market maker creation and governance

- Automated market maker creation: ICDexRouter is the contract factory for ICDexMaker. To create an OAMM pool, a fee (ICL) is 
required and NFT holders have a discount on the fee.
- Automated market maker governance: The management of Automated market makers by the Owner (DAO) includes upgrading, modifying the 
controller, and setting up vip-maker qualifications, etc. ICDexRouter wraps the methods related to the governance of automated market 
maker, so that the automated market maker methods can be called through ICDexRouter to realize the governance.

### NFT binding

Users who deposit NFTs into the ICDexRouter are granted specific qualifications, and some operations require locking the NFT. 
The currently supported NFT is ICLighthouse Planet Cards (goncb-kqaaa-aaaap-aakpa-cai), and qualifications that can be granted for 
the operations include:
- Creating an automated market maker canister: Accounts that have NFT cards deposited to 
the ICDexRouter will be eligible for a discounted fee on creating an automated market maker canister.
- Binding vip-maker qualifications: An account that has an NFT card with #NEPTUNE, #URANUS or #SATURN deposited into the ICDexRouter 
can set up to 5 target accounts as vip-maker roles, which will receive rebates when trading as maker roles. If the holder of the NFT 
removes the NFT from ICDexRouter, all the vip-maker roles he has bound will be invalidated.

### ICTC governance

Both ICDexPair and ICDexMaker use the ICTC module. In normal circumstances, ICTC completes transactions and automatically 
compensates for them, but under abnormal conditions, transactions are blocked and need to be compensated for through governance. 
If more than 5 transaction orders are blocked and not resolved, ICDexPair or ICDexMaker will be in a suspended state waiting for 
processing. ICTC accomplishes governance in two ways:
- The DAO calls the ICDexRouter's methods starting with "pair_ictc" to complete the governance of the ICDexPair or ICDexMaker, 
and these operations are logged in the ICDexRouter's Events, which is the preferred way.
- Set the DAO canister-id to the controller of ICDexPair/ICDexMaker or to the ICTCAdmin of ICDexPair/ICDexMaker. then the DAO can 
directly call the methods of ICDexPair or ICDexMaker that start with "ictc_" to complete the governance. This way of operations 
have more authority, only go to this way when the previous way can not complete the governance, the disadvantage is that you can 
not record Events in the ICDexRouter.

### Eco-economy

Various fees charged in ICDex are held in account `{ owner = ICDexRouter_canister_id; subaccount = null }`, a part of them is owned 
by the platform, and their main use is for transferring to an account for risk reserve, transferring to a blackhole account, 
trading in pairs (e.g., making a market, buying a certain token).

### Trading pair snapshots (backup and recovery)

ICDexRouter manages data snapshots of trading pairs. It is mainly used for backup and recovery of trading pairs, backing up data 
snapshots to another canister for some operations, such as airdrops.

### Events

Operations that call the core methods of the ICDexRouter and produce a state change are recorded in the Events system, sorted by 
ascending id number, making it easy for ecological participants to follow the behavior of the ICDexRouter. Older events may be 
deleted if the ICDexRouter's memory is heavily consumed, so someone could store the event history as needed.

### Cycles monitor

The CyclesMonitor module is used to monitor the Cycles balance and memory usage of trading pair and automated market maker 
canisters. The ICDexRouter will automatically top up Cycles for the monitored canisters, provided that the ICDexRouter has 
sufficient Cycles balance or ICP balance.

## 5 API


## Function `pubCreate`
``` motoko no-repl
func pubCreate(_token0 : Principal, _token1 : Principal, _openingTimeNS : Time.Time) : async (canister : PairCanister)
```

Publicly create a trading pair by paying creatingPairFee.

Arguments:
- token0: Principal. Base token canister-id.
- token1: Principal. Quote token canister-id.
- openingTimeNS: Set the time in nanoseconds when the pair is open for trading. If an IDO needs to be started, it is recommended that at least 4 days be set aside.

Returns:
- canister: PairCanister. Trading pair canister-id.

## Function `setWasm`
``` motoko no-repl
func setWasm(_wasm : Blob, _version : Text, _append : Bool, _backup : Bool) : async ()
```

Set the wasm of the ICDexPair.

Arguments:
- wasm: Blob. wasm file.
- version: Text. The current version of wasm.
- append: Bool. Whether to continue uploading the rest of the chunks of the same wasm file. If a wasm file is larger than 2M, 
it can't be uploaded at once, the solution is to upload it in multiple chunks. `append` is set to false when uploading the 
first chunk. `append` is set to true when uploading subsequent chunks, and version must be filled in with the same value.
- backup: Bool. Whether to backup the previous version of wasm.


## Function `getWasmVersion`
``` motoko no-repl
func getWasmVersion() : async (version : Text, hash : Text, size : Nat)
```

Returns the current version of ICDexPair wasm.

## Function `create`
``` motoko no-repl
func create(_token0 : Principal, _token1 : Principal, _openingTimeNS : Time.Time, _unitSize : ?Nat64, _initCycles : ?Nat) : async (canister : PairCanister)
```

Create a new trading pair by governance.

Arguments:
- token0: Principal. Base token canister-id.
- token1: Principal. Quote token canister-id.
- openingTimeNS: Set the time in nanoseconds when the pair is open for trading. If an IDO needs to be started, it is recommended that at least 4 days be set aside.
- unitSize: ?Nat64. Smallest units of base token when placing an order, the order's quantity must be an integer 
multiple of UnitSize. See the ICDexPair documentation.
- initCycles: ?Nat. The initial Cycles amount added to the new canister.

Returns:
- canister: PairCanister. Trading pair canister-id.

## Function `update`
``` motoko no-repl
func update(_pair : Principal, _version : Text) : async (canister : ?PairCanister)
```

Upgrade a trading pair canister.

Arguments:
- pair: Principal. trading pair canister-id.
- version: Text. Check the current version to be upgraded.

Returns:
- canister: ?PairCanister. Trading pair canister-id. Returns null if the upgrade was unsuccessful.

## Function `updateAll`
``` motoko no-repl
func updateAll(_version : Text) : async { total : Nat; success : Nat; failures : [Principal] }
```

Upgrade all ICDexPairs.  

## Function `rollback`
``` motoko no-repl
func rollback(_pair : Principal) : async (canister : ?PairCanister)
```

Rollback to previous version (the last version that was saved).  
Note: Operate with caution.

## Function `setControllers`
``` motoko no-repl
func setControllers(_pair : Principal, _controllers : [Principal]) : async Bool
```

Modifying the controllers of the trading pair.

## Function `reinstall`
``` motoko no-repl
func reinstall(_pair : Principal, _version : Text, _snapshot : Bool) : async (canister : ?PairCanister)
```

Reinstall a trading pair canister which is paused.

Arguments:
- pair: Principal. trading pair canister-id.
- version: Text. Check the current version to be upgraded.
- snapshot: Bool. Whether to back up a snapshot.

Returns:
- canister: ?PairCanister. Trading pair canister-id. Returns null if the upgrade was unsuccessful.
Note: Operate with caution. Consider calling this method only if upgrading is not possible.

## Function `sync`
``` motoko no-repl
func sync() : async ()
```

Synchronize trading fees for all pairs.

## Function `getSnapshots`
``` motoko no-repl
func getSnapshots(_pair : Principal) : async [ICDexTypes.Timestamp]
```

Returns all snapshot timestamps for a trading pair.

## Function `removeSnapshot`
``` motoko no-repl
func removeSnapshot(_pair : Principal, _timeBefore : Timestamp) : async ()
```

Removes all snapshots prior to the specified timestamp of the trading pair.

## Function `backup`
``` motoko no-repl
func backup(_pair : Principal) : async ICDexTypes.Timestamp
```

Backs up and saves a snapshot of a trading pair.

## Function `recovery`
``` motoko no-repl
func recovery(_pair : Principal, _snapshotTimestamp : ICDexTypes.Timestamp) : async Bool
```

Recover data for a trading pair.  
Note: You need to check the wasm version and the status of the trading pair, the operation may lead to data loss.

## Function `backupToTempCanister`
``` motoko no-repl
func backupToTempCanister(_pairFrom : Principal, _pairTo : Principal) : async Bool
```

Backup the data of a trading pair to another canister.  
Note: Canister `_pairTo` is created only for backing up data and should not be used for trading. It needs to implement 
the recover() method like ICDexPair.

## Function `snapshotToTempCanister`
``` motoko no-repl
func snapshotToTempCanister(_pair : Principal, _snapshotTimestamp : ICDexTypes.Timestamp, _pairTo : Principal) : async Bool
```

Save the data of snapshot to another canister.  
Note: Canister `_pairTo` is created only for backing up data and should not be used for trading. It needs to implement 
the recover() method like ICDexPair.

## Function `put`
``` motoko no-repl
func put(_pair : SwapPair) : async ()
```

Puts a pair into a list of trading pairs.

## Function `remove`
``` motoko no-repl
func remove(_pairCanister : Principal) : async ()
```

Removes a pair from the list of trading pairs.

## Function `getTokens`
``` motoko no-repl
func getTokens() : async [TokenInfo]
```

Returns all the tokens in the list of pairs.

## Function `getPairs`
``` motoko no-repl
func getPairs(_page : ?Nat, _size : ?Nat) : async TrieList<PairCanister, SwapPair>
```

Returns all trading pairs.

## Function `getPairsByToken`
``` motoko no-repl
func getPairsByToken(_token : Principal) : async [(PairCanister, SwapPair)]
```

Returns the trading pairs containing a specified token.

## Function `route`
``` motoko no-repl
func route(_token0 : Principal, _token1 : Principal) : async [(PairCanister, SwapPair)]
```

Returns the trading pairs based on the two tokens provided.

## Function `pair_pause`
``` motoko no-repl
func pair_pause(_app : Principal, _pause : Bool, _openingTime : ?Time.Time) : async Bool
```

Suspend (true) or open (false) a trading pair. If `_openingTime` is specified, it means that the pair will be opened automatically after that time.

## Function `pair_pauseAll`
``` motoko no-repl
func pair_pauseAll(_pause : Bool) : async { total : Nat; success : Nat; failures : [Principal] }
```

Suspend (true) or open (false) all trading pairs. 

## Function `pair_setAuctionMode`
``` motoko no-repl
func pair_setAuctionMode(_app : Principal, _enable : Bool, _funder : ?AccountId) : async (Bool, AccountId)
```

Enable/disable Auction Mode

## Function `pair_IDOSetFunder`
``` motoko no-repl
func pair_IDOSetFunder(_app : Principal, _funder : ?Principal, _requirement : ?ICDexPrivate.IDORequirement) : async ()
```

Open IDO of a trading pair and configure parameters

## Function `pair_config`
``` motoko no-repl
func pair_config(_app : Principal, _config : ?ICDexTypes.DexConfig, _drc205config : ?DRC205.Config) : async Bool
```

Configure the trading pair parameters and configure its DRC205 parameters.

## Function `pair_setUpgradeMode`
``` motoko no-repl
func pair_setUpgradeMode(_app : Principal, _mode : {#Base; #All}) : async ()
```

When the data is too large to be backed up, you can set the UpgradeMode to #Base.

## Function `pair_setOrderFail`
``` motoko no-repl
func pair_setOrderFail(_app : Principal, _txid : Text, _refund0 : Nat, _refund1 : Nat) : async Bool
```

Sets an order with #Todo status as an error order.

## Function `pair_enableStratOrder`
``` motoko no-repl
func pair_enableStratOrder(_app : Principal, _arg : {#Enable; #Disable}) : async ()
```

Enable strategy orders for a trading pair.

## Function `sto_config`
``` motoko no-repl
func sto_config(_app : Principal, _config : { poFee1 : ?Nat; poFee2 : ?Float; sloFee1 : ?Nat; sloFee2 : ?Float; gridMaxPerSide : ?Nat; proCountMax : ?Nat; stopLossCountMax : ?Nat }) : async ()
```

Configuring strategy order parameters for a trading pair.

## Function `pair_pendingAll`
``` motoko no-repl
func pair_pendingAll(_app : Principal, _page : ?Nat, _size : ?Nat) : async ICDexTypes.TrieList<ICDexTypes.Txid, ICDexTypes.TradingOrder>
```

Query all orders in pending status.

## Function `pair_withdrawCycles`
``` motoko no-repl
func pair_withdrawCycles(_app : Principal, _amount : Nat) : async ()
```

Withdraw cycles.

## Function `pair_ictcSetAdmin`
``` motoko no-repl
func pair_ictcSetAdmin(_app : Principal, _admin : Principal, _addOrRemove : Bool) : async Bool
```

Add/Remove ICTC Administrator

## Function `pair_ictcClearLog`
``` motoko no-repl
func pair_ictcClearLog(_app : Principal, _expiration : ?Int, _delForced : Bool) : async ()
```

Clear logs of transaction orders and transaction tasks. 

## Function `pair_ictcRedoTT`
``` motoko no-repl
func pair_ictcRedoTT(_app : Principal, _toid : Nat, _ttid : Nat) : async (?Nat)
```

Try the task again.

## Function `pair_ictcCompleteTO`
``` motoko no-repl
func pair_ictcCompleteTO(_app : Principal, _toid : Nat, _status : SagaTM.OrderStatus) : async Bool
```

Complete a blocking order.

## Function `pair_ictcDoneTT`
``` motoko no-repl
func pair_ictcDoneTT(_app : Principal, _toid : Nat, _ttid : Nat, _toCallback : Bool) : async (?Nat)
```

Set status of a pending task.

## Function `pair_ictcDoneTO`
``` motoko no-repl
func pair_ictcDoneTO(_app : Principal, _toid : Nat, _status : SagaTM.OrderStatus, _toCallback : Bool) : async Bool
```

Set status of a pending order.

## Function `pair_ictcRunTO`
``` motoko no-repl
func pair_ictcRunTO(_app : Principal, _toid : Nat) : async ?SagaTM.OrderStatus
```

Run the ICTC actuator and check the status of the transaction order `toid`.

## Function `pair_ictcBlockTO`
``` motoko no-repl
func pair_ictcBlockTO(_app : Principal, _toid : Nat) : async (?Nat)
```

Change the status of a transaction order to #Blocking.

## Function `pair_sync`
``` motoko no-repl
func pair_sync(_app : Principal) : async ()
```

Synchronizing token0 and token1 transfer fees.

## Function `pair_setVipMaker`
``` motoko no-repl
func pair_setVipMaker(_app : Principal, _account : Address, _rate : Nat) : async ()
```

Set up vip-maker qualification and configure rebate rate.

## Function `pair_removeVipMaker`
``` motoko no-repl
func pair_removeVipMaker(_app : Principal, _account : Address) : async ()
```

Removes vip-maker qualification.

## Function `pair_fallbackByTxid`
``` motoko no-repl
func pair_fallbackByTxid(_app : Principal, _txid : Txid, _sa : ?ICDexPrivate.Sa) : async Bool
```

Retrieve missing funds from the order's TxAccount. The funds of the TxAccount will be refunded to the ICDexRouter canister-id.

## Function `pair_cancelByTxid`
``` motoko no-repl
func pair_cancelByTxid(_app : Principal, _txid : Txid, _sa : ?ICDexPrivate.Sa) : async ()
```

Cancels an order.

## Function `pair_taSetDescription`
``` motoko no-repl
func pair_taSetDescription(_app : Principal, _desc : Text) : async ()
```

Submit a text description of the Trading Ambassadors (referral) system.

## Function `dex_addCompetition`
``` motoko no-repl
func dex_addCompetition(_id : ?Nat, _name : Text, _content : Text, _start : Time.Time, _end : Time.Time, _addPairs : [{ dex : Text; canisterId : Principal; quoteToken : {#token0; #token1}; minCapital : Nat }]) : async Nat
```

This is a feature to be opened in the future. Register a trading competition with a third party for display.

## Function `getDAO`
``` motoko no-repl
func getDAO() : async Principal
```

Returns the canister-id of the DAO

## Function `sys_withdraw`
``` motoko no-repl
func sys_withdraw(_token : Principal, _tokenStd : TokenStd, _to : Principal, _value : Nat) : async ()
```

Withdraw the token to the specified account.  
Withdrawals can only be made to a DAO address, or to a blackhole address (destruction), not to a private address.

## Function `sys_order`
``` motoko no-repl
func sys_order(_token : Principal, _tokenStd : TokenStd, _value : Nat, _pair : Principal, _order : ICDexTypes.OrderPrice) : async ICDexTypes.TradingResult
```

Placing an order in a trading pair as a trader.

## Function `sys_cancelOrder`
``` motoko no-repl
func sys_cancelOrder(_pair : Principal, _txid : ?Txid) : async ()
```

Cancel own orders as a trader.

## Function `sys_config`
``` motoko no-repl
func sys_config(_args : { aggregator : ?Principal; blackhole : ?Principal; icDao : ?Principal; nftPlanetCards : ?Principal; sysToken : ?Principal; sysTokenFee : ?Nat; creatingPairFee : ?Nat; creatingMakerFee : ?Nat }) : async ()
```

Configure the system parameters of the ICDexRouter.

## Function `sys_getConfig`
``` motoko no-repl
func sys_getConfig() : async { aggregator : Principal; blackhole : Principal; icDao : Principal; nftPlanetCards : Principal; sysToken : Principal; sysTokenFee : Nat; creatingPairFee : Nat; creatingMakerFee : Nat }
```

Returns the configuration items of ICDexRouter.

## Function `NFTs`
``` motoko no-repl
func NFTs() : async [(AccountId, [NFT])]
```

Returns a list of holders of staked NFTs in the ICDexRouter.

## Function `NFTBalance`
``` motoko no-repl
func NFTBalance(_owner : Address) : async [NFT]
```

Returns an account's NFT balance staked in the ICDexRouter.

## Function `NFTDeposit`
``` motoko no-repl
func NFTDeposit(_collectionId : CollectionId, _nftId : ERC721.TokenIdentifier, _sa : ?[Nat8]) : async ()
```

The user deposits the NFT to the ICDexRouter.

## Function `NFTWithdraw`
``` motoko no-repl
func NFTWithdraw(_nftId : ?ERC721.TokenIdentifier, _sa : ?[Nat8]) : async ()
```

The user withdraws the NFT to his wallet.

## Function `NFTBindingMakers`
``` motoko no-repl
func NFTBindingMakers(_nftId : Text) : async [(pair : Principal, account : AccountId)]
```

Returns vip-makers to which an NFT has been bound.

## Function `NFTBindMaker`
``` motoko no-repl
func NFTBindMaker(_nftId : Text, _pair : Principal, _maker : AccountId, _sa : ?[Nat8]) : async ()
```

The NFT owner binds a new vip-maker.

## Function `NFTUnbindMaker`
``` motoko no-repl
func NFTUnbindMaker(_nftId : Text, _pair : Principal, _maker : AccountId, _sa : ?[Nat8]) : async ()
```

The NFT owner unbinds a vip-maker.

## Function `maker_setWasm`
``` motoko no-repl
func maker_setWasm(_wasm : Blob, _version : Text, _append : Bool, _backupPreVersion : Bool) : async ()
```

Set the wasm of the ICDexMaker.

Arguments:
- wasm: Blob. wasm file.
- version: Text. The current version of wasm.
- append: Bool. Whether to continue uploading the rest of the chunks of the same wasm file. If a wasm file is larger than 2M, 
it can't be uploaded at once, the solution is to upload it in multiple chunks. `append` is set to false when uploading the 
first chunk. `append` is set to true when uploading subsequent chunks, and version must be filled in with the same value.
- backup: Bool. Whether to backup the previous version of wasm.

## Function `maker_getWasmVersion`
``` motoko no-repl
func maker_getWasmVersion() : async (Text, Text, Nat)
```

Returns the current version of ICDexMaker wasm.

## Function `maker_getPublicMakers`
``` motoko no-repl
func maker_getPublicMakers(_pair : ?Principal, _page : ?Nat, _size : ?Nat) : async TrieList<PairCanister, [(Principal, AccountId)]>
```

Returns all public automated market makers.

## Function `maker_getPrivateMakers`
``` motoko no-repl
func maker_getPrivateMakers(_account : AccountId, _page : ?Nat, _size : ?Nat) : async TrieList<PairCanister, [(Principal, AccountId)]>
```

Returns all private automated market makers.

## Function `maker_create`
``` motoko no-repl
func maker_create(_arg : { pair : Principal; allow : {#Public; #Private}; name : Text; lowerLimit : Nat; upperLimit : Nat; spreadRate : Nat; threshold : Nat; volFactor : Nat; creator : ?AccountId }) : async (canister : Principal)
```

Create a new Automated Market Maker (ICDexMaker).  
Trading pairs and automated market makers are in a one-to-many relationship, with one trading pair corresponding to zero or more 
automated market makers.  
permissions: Dao, NFT holders, users

Arguments:
- arg: 
```
{
    pair: Principal; // Trading pair caniser-id.
    allow: {#Public; #Private}; // Visibility. #Public / #Private.
    name: Text; // Name. e.g. "AAA_BBB AMM-1"
    lowerLimit: Nat; // Lower price limit. How much token1 (smallest units) are needed to purchase UNIT_SIZE token0 (smallest units).
    upperLimit: Nat; // Upper price limit. How much token1 (smallest units) are needed to purchase UNIT_SIZE token0 (smallest units).
    spreadRate: Nat; // ppm. Inter-grid spread ratio for grid orders. e.g. 10_000, it means 1%. It will create 2 grid strategies, the second strategy has a spreadRate that is 5 times this value.
    threshold: Nat; // token1 (smallest units). e.g. 1_000_000_000_000. After the total liquidity exceeds this threshold, the LP adds liquidity up to a limit of volFactor times his trading volume.
    volFactor: Nat; // LP liquidity limit = LP's trading volume * volFactor.  e.g. 2
    creator: ?AccountId; // Specify the creator.
}
```

Returns:
- canister: Principal. Automated Market Maker canister-id.

## Function `maker_reinstall`
``` motoko no-repl
func maker_reinstall(_pair : Principal, _maker : Principal, _version : Text) : async (canister : ?Principal)
```

Reinstall an ICDexMaker canister which is paused.

Arguments:
- pair: Principal. trading pair canister-id.
- maker: Principal. ICDexMaker canister-id.
- version: Text. Check the current version to be upgraded.

Returns:
- canister: ?Principal. ICDexMaker canister-id. Returns null if the upgrade was unsuccessful.
Note: Operate with caution. Consider calling this method only if upgrading is not possible.

## Function `maker_update`
``` motoko no-repl
func maker_update(_pair : Principal, _maker : Principal, _name : ?Text, _version : Text) : async (canister : ?Principal)
```

Upgrade an ICDexMaker canister.  
permissions: Dao, Private Maker Creator

Arguments:
- pair: Principal. Trading pair canister-id.
- maker: Principal. Automated Market Maker canister-id.
- name:?Text. Maker name.
- version: Text. Check the current version to be upgraded.

Returns:
- canister: ?Principal. Automated Market Maker canister-id. Returns null if the upgrade was unsuccessful.

## Function `maker_updateAll`
``` motoko no-repl
func maker_updateAll(_version : Text, _updatePrivateMakers : Bool) : async { total : Nat; success : Nat; failures : [(Principal, Principal)] }
```

Upgrade all ICDexMakers.  

## Function `maker_rollback`
``` motoko no-repl
func maker_rollback(_pair : Principal, _maker : Principal) : async (canister : ?Principal)
```

Rollback an ICDexMaker canister.
permissions: Dao, Private Maker Creator

## Function `maker_approveToPair`
``` motoko no-repl
func maker_approveToPair(_pair : Principal, _maker : Principal, _amount : Nat) : async Bool
```

Let ICDexMaker approve the `_amount` of the sysToken the trading pair could spend.

## Function `maker_remove`
``` motoko no-repl
func maker_remove(_pair : Principal, _maker : Principal) : async ()
```

Remove an Automated Market Maker (ICDexMaker).
permissions: Dao, Private Maker Creator

## Function `maker_setControllers`
``` motoko no-repl
func maker_setControllers(_pair : Principal, _maker : Principal, _controllers : [Principal]) : async Bool
```

Modify the controllers of an ICDexMaker canister.

## Function `maker_config`
``` motoko no-repl
func maker_config(_maker : Principal, _config : Maker.Config) : async Bool
```

Configure an Automated Market Maker (ICDexMaker).

## Function `maker_transactionLock`
``` motoko no-repl
func maker_transactionLock(_maker : Principal, _act : {#lock; #unlock}) : async Bool
```

Lock or unlock an Automated Market Maker (ICDexMaker) system transaction lock.

## Function `maker_setPause`
``` motoko no-repl
func maker_setPause(_maker : Principal, _pause : Bool) : async Bool
```

Pause or enable Automated Market Maker (ICDexMaker).

## Function `maker_resetLocalBalance`
``` motoko no-repl
func maker_resetLocalBalance(_maker : Principal) : async Maker.PoolBalance
```

Reset Automated Market Maker (ICDexMaker) local account balance.

## Function `maker_dexWithdraw`
``` motoko no-repl
func maker_dexWithdraw(_maker : Principal, _token0 : Nat, _token1 : Nat) : async (token0 : Nat, token1 : Nat)
```

Withdraw funds from the trading pair to an Automated Market Maker (ICDexMaker) local account.

## Function `maker_dexDeposit`
``` motoko no-repl
func maker_dexDeposit(_maker : Principal, _token0 : Nat, _token1 : Nat) : async (token0 : Nat, token1 : Nat)
```

Deposit from Automated Market Maker (ICDexMaker) to TraderAccount for the trading pair.

## Function `maker_deleteGridOrder`
``` motoko no-repl
func maker_deleteGridOrder(_maker : Principal, _gridOrder : {#First; #Second}) : async ()
```

Deletes grid order from Automated Market Maker (ICDexMaker).

## Function `maker_createGridOrder`
``` motoko no-repl
func maker_createGridOrder(_maker : Principal, _gridOrder : {#First; #Second}) : async ()
```

Creates a grid order for Automated Market Maker (ICDexMaker) on the trading pair.

## Function `maker_cancelAllOrders`
``` motoko no-repl
func maker_cancelAllOrders(_maker : Principal) : async ()
```

Cancels trade orders in pending on the trading pair placed by Automated Market Maker (ICDexMaker).

## Function `get_event`
``` motoko no-repl
func get_event(_blockIndex : BlockHeight) : async ?(Event, Timestamp)
```

Returns an event based on the block height of the event.

## Function `get_event_first_index`
``` motoko no-repl
func get_event_first_index() : async BlockHeight
```

Returns the height of the first block of the saved event record set. (Possibly earlier event records have been cleared).

## Function `get_events`
``` motoko no-repl
func get_events(_page : ?ICDexTypes.ListPage, _size : ?ICDexTypes.ListSize) : async TrieList<BlockHeight, (Event, Timestamp)>
```

Returns events list.

## Function `get_account_events`
``` motoko no-repl
func get_account_events(_accountId : AccountId) : async [(Event, Timestamp)]
```

Returns events by account.

## Function `get_event_count`
``` motoko no-repl
func get_event_count() : async Nat
```

Returns the total number of events (height of event blocks).

## Function `monitor_put`
``` motoko no-repl
func monitor_put(_canisterId : Principal) : async ()
```

Put a canister-id into Cycles Monitor.

## Function `monitor_remove`
``` motoko no-repl
func monitor_remove(_canisterId : Principal) : async ()
```

Remove a canister-id from Cycles Monitor.

## Function `monitor_canisters`
``` motoko no-repl
func monitor_canisters() : async [(Principal, Nat)]
```

Returns the list of canister-ids in Cycles Monitor.

## Function `debug_canister_status`
``` motoko no-repl
func debug_canister_status(_canisterId : Principal) : async CyclesMonitor.canister_status
```

Returns a canister's caniter_status information.

## Function `debug_monitor`
``` motoko no-repl
func debug_monitor() : async ()
```

Perform a monitoring. Typically, monitoring is implemented in a timer.

## Function `drc207`
``` motoko no-repl
func drc207() : async DRC207.DRC207Support
```

Returns the monitorability configuration of the canister.

## Function `wallet_receive`
``` motoko no-repl
func wallet_receive() : async ()
```

canister_status
receive cycles

## Function `timerStart`
``` motoko no-repl
func timerStart(_intervalSeconds : Nat) : async ()
```

Start the Timer, it will be started automatically when upgrading the canister.

## Function `timerStop`
``` motoko no-repl
func timerStop() : async ()
```

Stop the Timer
