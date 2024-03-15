# ICDexMaker
* Actor      : ICDexMaker
 * Author     : ICLighthouse Team
 * Stability  : Experimental
 * Github     : https://github.com/iclighthouse/ICDex/

## Overview

ICDexMaker is ICDex's Automated Market Maker contract (Canister) that provides liquidity to a trading pair. An Automated 
Market Maker is deployed in a separate canister that is managed by ICDexRouter.  
ICDexMaker simulates the effect of Uniswap AMM using grid strategy orders. It will create two grid strategies, e.g. if 
the first grid strategy has a grid spread = 1%, then the second grid strategy will have a grid spread of 5% which is 
5 times that of the first.
It includes Public Maker and Private Maker:
- Public Maker is the public market making pool to which any user (LP) can add liquidity.
- Private Maker is a private market making pool to which only the creator (LP) can add liquidity.
Note: The #NEPTUNE NFT holder can bind the ICDexMaker canister-id to a vip-maker on ICDexRouter, then this ICDexMaker can 
obtain vip-maker status with rebate feature.

## 1 Concepts

### Roles
- Owner and DAO: The Owner (ICDexRouter) and DAO are the controllers of the ICDexMaker.
- Creator: The creator of ICDexMaker, the private ICDexMaker is only available to the creator.
- Liquidity provider (LP): Liquidity Providers (LPs) are holders of shares of liquidity in the ICDexMaker pool.

### Automated Market Maker (AMM)
Decentralized automated market maker contract (ICDexMaker) is similar to Uniswap's AMM, but instead of a constant 
k model, it is based on order book DEX using a grid strategy for automated market making.

### Liquidity Pool
In an AMM contract, the liquidity provided by the LPs are aggregated into a pool account which participates in 
the trading of the pair. Liquid assets include token0 and token1, whose balances are kept partly in trading pair 
and partly in local account.

### Liquidity Share
Liquidity share is proof of the amount of assets held in the liquidity pool by the liquidity provider. When 
an LP adds liquidity, the liquidity pool calculates an increase of shares based on the NAV at 
that time; when an LP removes liquidity, the liquidity pool calculates the destruction of the corresponding shares 
based on the NAV at that time.

### Net Asset Value (NAV)
Net Asset Value (NAV), Unit Value, is the token0 and token1 value per `shareUnitSize` shares in the liquidity pool.
```
Token0 value (smallest_units) = shareUnitSize * Pool.token0Balance / TotalShares
Token1 value (smallest_units) = shareUnitSize * Pool.token1Balance / TotalShares
```
where shareUnitSize is the UnitSize of the pair.

### APY
The annual percentage yield (APY) is the real rate of return earned on providing liquidity. Since there are both token0 
and token1 assets in the liquidity pool, there is a difference between token0-based and token1-based calculation of APY. 
In token0-based, token1 is converted to token0 value at the current price before calculating APY; in token1-based, token0 
is converted to token1 value at the current price before calculating APY.
```
24h APY = (Current_NAV - NAV_24h_ago) / NAV_24h_ago * 365
7d APY = (Current_NAV - NAV_7d_ago) / NAV_7d_ago / 7 * 365
```

### System Transaction Lock
ICDexMaker and trading pairs are in two different canisters, the transfer of funds between them is carried out asynchronously, 
and the execution of ICTC is also asynchronous, which affects the calculation of the NAV of the liquidity pool. In order to 
safely and accurately calculate the asset balance and NAV of the liquidity pool, a system transaction lock is designed so that 
parallel operations cannot be performed in the locked state.

## 2 Deployment

### Deploy ICDexMaker by ICDexRouter or manually
args:
```
{
    pair: Principal; // Trading pair caniser-id.
    allow: {#Public; #Private}; // Visibility. #Public / #Private.
    name: Text; // Name. e.g. "AAA_BBB AMM-1"
    lowerLimit: Nat; // Lower price limit. How much token1 (smallest units) are needed to purchase UNIT_SIZE token0 (smallest units).
    upperLimit: Nat; // Upper price limit. How much token1 (smallest units) are needed to purchase UNIT_SIZE token0 (smallest units).
    spreadRate: Nat; // ppm. Inter-grid spread ratio for grid orders. e.g. 10_000, it means 1%. Recommended between 5000 and 50000 (i.e. 0.5% to 5%).
    threshold: Nat; // token1 (smallest units). e.g. 1_000_000_000_000. After the total liquidity exceeds this threshold, the LP adds liquidity up to a limit of volFactor times his trading volume.
    volFactor: Nat; // LP‘s liquidity limit = LP's trading volume * volFactor.  e.g. 2
}
```
### Preparing requirements for creating a grid order (with at least one requirement)
- Make ICDexMaker get the vip-maker role via NFT bindings to create/update a grid order for free. 
- Deposit enough ICLs to ICDexMaker as fees for creating/updating a grid order.

### The creator activates ICDexMaker by adding the first liquidity
The creator activates ICDexMaker by adding the first liquidity.
The first liquidity must be added by the creator, requiring the amount of token0 to be greater than token0_fee * 100000, and 
the amount of token1 to be greater than token1_fee * 100000.

## 3 Fee model

- Withdrawal fee: LP removes liquidity with a withdrawal fee, charged as a fixed fee plus a percentage of the withdrawal amount, 
which is calculated as `Fee = 10 * tokenFee + withdrawalFeeRate * value`, where tokenFee is the transfer fee for the token, 
withdrawalFeeRate is the fee rate, and value is the amount of the withdrawal.

## 4 Core functionality

### Liquidity pool

1) Settlement

When liquidity is added and removed, both the NAV and the shares are recalculated once. The liquidity asset amount is fetched 
for each calculation and the following formula is adhered to as a guideline:
```
NAV / shareUnitSize * shares = total liquidity
```
2) Funds in transit

Funds in transit occurs when trade orders are matched and when deposits or withdrawals are made between ICDexMaker and the pair, 
it can affect the accuracy of liquidity pool balances and NAVs, which may jeopardize asset security. Critical operations involving 
assets should be avoided when funds in transit exist. Security measures include:
- Use system transaction lock to avoid execution when funds in transit or transaction conflicts exist;
- Interrupts adding or removing liquidity when funds in transit or a transaction conflict exists;
- use the safeAccountBalance() method of the trading pair to query for funds in trading.

3) Reserve funds

Most of the liquidity is deposited into the trading pair to participate in market making trading, while approximately 5-10% of 
the funds are kept in ICDexMaker's local account as a reserve for small liquidity removals. If the reserve balance is too low, 
some amount will be withdrawn from the pair to the local account when the LP removes liquidity.

4) Grid strategy for market-making

ICDexMaker uses a grid strategy to participate in market making trading, which is a very simple and effective strategy. 
Uniswap's AMM model is a special case of a grid trading strategy (the grid interval is infinitely close to zero). In order to 
be able to maintain decentralized long-term execution, the strategy parameters are configured as relative values, avoiding the 
need to tweak the parameters. Important parameters include:
- spread = #Geom(gridSpread). The grid spread is configured as a ratio (ppm).
- amount = #Percent(null). The quantity (amount) of orders traded per grid is configured as #Percent and is specified as null, 
indicating that the proportion takes the value ppmFactor.
    - ppmFactor: Default grid order amount factor, initialized when the strategy is created. `ppmFactor = 1000000 * 1/n * (n ** (1/10))`, 
Where n is `(n1 + n2) / 2`, and n1, n2 is between 2 and 200. n1 is the number of grids between the latest price and the lowerLimit, 
and n2 is the number of grids between the latest price and the upperLimit.

5) Liquidity limit

ICDexMaker initially adds liquidity without limit, after the token1 balance of total liquidity reaches `threshold`, the liquidity limit 
rule will be activated and the user's liquidity limit (measured in token1) = the user's token1 volume in the current pair * volFactor. 
Note: threshold and volFactor are specified when ICDexMaker is created.  
The reason for this is that when a market making pool is more popular, there are too many users trying to add liquidity to it, 
which leads to the result that the liquidity yield will be lower. In order to prioritize users with higher contribution levels, 
the contribution level is measured by the user's volume of the pair, and this is used to calculate a limit on the amount of liquidity 
a user can add. 

6) LP yield

LPs may benefit from adding liquidity to the liquidity pool, but it is risky and does not result in a stable gain or may result 
in a loss. Possible gains include:
- Grid spread gain: ICDexMaker opens a grid strategy in the trading pair, there exists a spread between every two grids, if the 
price shows upward and downward fluctuations, ICDexMaker can get the grid spread gain. However, if the price fluctuates in one 
direction, the number of ICDexMaker's one token will become more and the number of the other token will become less, and it will 
not get the spread gain. Therefore, the amount of grid spread gain is related to the volatility of the trading pair.   
- Vip-maker rebate: When ICDexMaker has the role of Vip-maker, it can get the trading fee rebate, and this part of the gain will 
go to the liquidity pool.
- Remove liquidity withdrawal fee: When an LP withdraws liquidity, he will be charged a withdrawal fee to be added to the liquidity 
pool.
- Liquidity mining/airdrop: this is a contingent benefit, ICDexMaker itself does not provide liquidity mining or token airdrop, 
which requires LPs to pay attention to the Dex platform side or the project side of the liquidity mining or airdrop activity 
announcement.

### ICTC (This module is shared with the ICDexPair)

The purpose of ICTC module is to alleviate the atomicity problem in Defi development, and it mainly adopts Saga mode to centralize the 
management of asynchronous calls, improve data consistency, and increase the number of concurrency. The main application scenario of ICTC 
is the proactive (the current canister is the coordinator) multitasking transaction management, because such a scenario requires lower 
probability of external participation in compensation. ICTC is used for most token transfer transactions in ICDex and not during deposits. 
ICTC effectively reduces the number of times `await` is used in the core logic, improves concurrency, and provides a standardized way 
for testing and exception handling.   

A transaction order (id: toid) can contain multiple transaction tasks (id: ttid). Saga transaction execution modes include #Forward and 
#Backward.
- Forward: When an exception is encountered, the transaction will be in the #Blocking state, requiring the Admin (DAO) to perform a 
compensating operation.
- Backward: When an exception is encountered, the compensation function is automatically called to rollback. If no compensation function 
is provided, or if there is an error in executing the compensation function, the transaction will also be in #Blocking state, requiring 
the Admin (DAO) to compensate.

ICTC module is placed in the ICTC directory of the project, CallType.mo is a project customization file, SagaTM.mo and other files are 
from ICTC library https://github.com/iclighthouse/ICTC/

ICTC Explorer: https://cmqwp-uiaaa-aaaaj-aihzq-cai.raw.ic0.app/saga/  
Docs: https://github.com/iclighthouse/ICTC/blob/main/README.md  
      https://github.com/iclighthouse/ICTC/blob/main/docs/ictc_reference-2.0.md

### Events

Operations that call the core methods of the ICDexMaker are recorded in the Events system, sorted by ascending id number, making 
it easy for ecological participants to follow the behavior of the ICDexMaker. Older events may be deleted if the ICDexMaker's 
memory is heavily consumed, so someone could store the event history as needed.

## 5 Backup and Recovery

The backup and recovery functions are not normally used, but are used when canister cannot be upgraded and needs to be reinstalled:
- call backup() method to back up the data.
- reinstall cansiter.
- call recovery() to restore the data.

Caution:
- If the data in this canister has a dependency on canister-id, it must be reinstalled in the same canister and cannot be migrated 
to a new canister.
- Normal access needs to be stopped during backup and recovery, otherwise the data may be contaminated.
- Backup and recovery operations have been categorized by variables, and each operation can only target one category of data, so 
multiple operations are required to complete the backup and recovery of all data.
- The backup and recovery operations are not paged for single-variable datasets. If you encounter a failure due to large data size, 
please try the following:
    - Calling canister's cleanup function or configuration will delete stale data for some variables.
    - Backup and recovery of non-essential data can be ignored.
    - Query the necessary data through other query functions, and then call recovery() to restore the data.
    - Abandon this solution and seek other data recovery solutions.

## 6 API


## Function `getDepositAccount`
``` motoko no-repl
func getDepositAccount(_account : Address) : async (ICRC1.Account, Address)
```

Deposit account when adding liquidity. 
This is a query method, if called off-chain (e.g., web-side), You should generate the account address directly using the 
following rule: `{owner = maker_canister_id; subaccount = ?your_accountId }`.

## Function `fallback`
``` motoko no-repl
func fallback(_sa : ?Sa) : async (value0 : Amount, value1 : Amount)
```

Retrieve funds when an LP has a deposit exception and the funds are left in his DepositAccount.

## Function `add`
``` motoko no-repl
func add(_token0 : Amount, _token1 : Amount, _sa : ?Sa) : async Shares
```

Adds liquidity.  
The ratio of token0 to token1 needs to be estimated based on the current NAV, and the excess side of the token will be refunded.

Arguments:
- token0: Amount(smallest_units) of token0 to add
- token1: Amount(smallest_units) of token1 to add
- sa: ?Sa. Optionally specify the subaccount of the caller

Results:
- res: Shares. Share of the liquidity pool received

## Function `remove`
``` motoko no-repl
func remove(_shares : Amount, _sa : ?Sa) : async (value0 : Amount, value1 : Amount)
```

Removes liquidity.  

Arguments:
- shares: Share of liquidity to be removed
- sa: ?Sa. Optionally specify the subaccount of the caller

Results:
- res: (value0: Amount, value1: Amount). Amounts of token0 and token1 received

## Function `getAccountShares`
``` motoko no-repl
func getAccountShares(_account : Address) : async (Shares, ShareWeighted)
```

Returns the LP's liquidity share and time-weighted value.

## Function `getAccountVolUsed`
``` motoko no-repl
func getAccountVolUsed(_account : Address) : async Nat
```

Returns the liquidity quota that has been used by the LP.

## Function `getUnitNetValues`
``` motoko no-repl
func getUnitNetValues() : async { shareUnitSize : Nat; data : [UnitNetValue] }
```

Returns NAV values.

## Function `accountSharesAll`
``` motoko no-repl
func accountSharesAll(_page : ?ICEvents.ListPage, _size : ?ICEvents.ListSize) : async TrieList<AccountId, (Nat, ShareWeighted)>
```

Resturns the amount of pool shares for all users.

## Function `info`
``` motoko no-repl
func info() : async { version : Text; name : Text; paused : Bool; initialized : Bool; sysTransactionLock : Bool; sysGlobalLock : ?Bool; visibility : {#Public; #Private}; creator : AccountId; withdrawalFee : Float; poolThreshold : Amount; volFactor : Nat; gridSoid : [?Nat]; shareDecimals : Nat8; pairInfo : { pairPrincipal : Principal; pairUnitSize : Nat; token0 : (Principal, Text, ICDex.TokenStd); token1 : (Principal, Text, ICDex.TokenStd) }; gridSetting : { gridLowerLimit : Price; gridUpperLimit : Price; gridSpread : Price } }
```

Returns ICDexMaker information.

## Function `stats`
``` motoko no-repl
func stats() : async { holders : Nat; poolBalance : PoolBalance; poolLocalBalance : PoolBalance; poolShares : Shares; poolShareWeighted : ShareWeighted; latestUnitNetValue : UnitNetValue }
```

Returns the latest status data for ICDexMaker. (Data may be delayed).

## Function `stats2`
``` motoko no-repl
func stats2() : async { holders : Nat; poolBalance : PoolBalance; poolLocalBalance : PoolBalance; poolShares : Shares; poolShareWeighted : ShareWeighted; latestUnitNetValue : UnitNetValue; apy24h : { token0 : Float; token1 : Float }; apy7d : { token0 : Float; token1 : Float } }
```

Returns the latest status data for ICDexMaker.  
This is a composite query that will fetch the latest data.

## Function `config`
``` motoko no-repl
func config(_config : T.Config) : async Bool
```

Configure the ICDexMaker.

## Function `transactionLock`
``` motoko no-repl
func transactionLock(_sysTransactionLock : ?{#lock; #unlock}, _sysGlobalLock : ?{#lock; #unlock}) : async Bool
```

Lock or unlock system transaction lock. Operate with caution! 
Only need to call this method to unlock if there is a deadlock situation.

## Function `setPause`
``` motoko no-repl
func setPause(_pause : Bool) : async Bool
```

Pause or enable this ICDexMaker.

## Function `resetLocalBalance`
``` motoko no-repl
func resetLocalBalance() : async PoolBalance
```

Reset ICDexMaker's local account balance, which is only allowed to be operated when ICDexMaker is suspended. 
Note that no funds in transit should exist at the time of operation.

## Function `dexWithdraw`
``` motoko no-repl
func dexWithdraw(_token0 : Amount, _token1 : Amount) : async (token0 : Amount, token1 : Amount)
```

Withdraw funds from the trading pair to ICDexMaker local account. This operation is not required for non-essential purposes.

## Function `dexDeposit`
``` motoko no-repl
func dexDeposit(_token0 : Amount, _token1 : Amount) : async (toid : Nat)
```

Deposit from ICDexMaker local account to TraderAccount in trading pair. This operation is not required for non-essential purposes.

## Function `deleteGridOrder`
``` motoko no-repl
func deleteGridOrder(_gridOrder : {#First; #Second}) : async ()
```

Deletes the grid order for ICDexMaker.

## Function `createGridOrder`
``` motoko no-repl
func createGridOrder(_gridOrder : {#First; #Second}) : async ()
```

Creates a grid order for ICDexMaker.

## Function `cancelAllOrders`
``` motoko no-repl
func cancelAllOrders() : async ()
```

Cancels all trade orders that the strategy order placed in the pair's order book.

## Function `approveToPair`
``` motoko no-repl
func approveToPair(_token : Principal, _std : ICDex.TokenStd, _amount : Amount) : async Bool
```

Approves the `amount` of a `token` the trading pair could spend.

## Function `debug_sync`
``` motoko no-repl
func debug_sync() : async Bool
```

Synchronize token information

## Function `get_event`
``` motoko no-repl
func get_event(_blockIndex : ICEvents.BlockHeight) : async ?(T.Event, ICEvents.Timestamp)
```

Returns an event based on the block height of the event.

## Function `get_event_first_index`
``` motoko no-repl
func get_event_first_index() : async ICEvents.BlockHeight
```

Returns the height of the first block of the saved event record set. (Possibly earlier event records have been cleared).

## Function `get_events`
``` motoko no-repl
func get_events(_page : ?ICEvents.ListPage, _size : ?ICEvents.ListSize) : async ICEvents.TrieList<ICEvents.BlockHeight, (T.Event, ICEvents.Timestamp)>
```

Returns events list.

## Function `get_account_events`
``` motoko no-repl
func get_account_events(_accountId : ICEvents.AccountId) : async [(T.Event, ICEvents.Timestamp)]
```

Returns events by account.

## Function `get_event_count`
``` motoko no-repl
func get_event_count() : async Nat
```

Returns the total number of events (height of event blocks).

## Function `ictc_getAdmins`
``` motoko no-repl
func ictc_getAdmins() : async [Principal]
```

Returns the list of ICTC administrators

## Function `ictc_addAdmin`
``` motoko no-repl
func ictc_addAdmin(_admin : Principal) : async ()
```

Add ICTC Administrator

## Function `ictc_removeAdmin`
``` motoko no-repl
func ictc_removeAdmin(_admin : Principal) : async ()
```

Rmove ICTC Administrator

## Function `ictc_TM`
``` motoko no-repl
func ictc_TM() : async Text
```

Returns TM name for SagaTM Scan

## Function `ictc_getTOCount`
``` motoko no-repl
func ictc_getTOCount() : async Nat
```

Returns total number of transaction orders

## Function `ictc_getTO`
``` motoko no-repl
func ictc_getTO(_toid : SagaTM.Toid) : async ?SagaTM.Order
```

Returns a transaction order

## Function `ictc_getTOs`
``` motoko no-repl
func ictc_getTOs(_page : Nat, _size : Nat) : async { data : [(SagaTM.Toid, SagaTM.Order)]; totalPage : Nat; total : Nat }
```

Returns transaction order list

## Function `ictc_getPool`
``` motoko no-repl
func ictc_getPool() : async { toPool : { total : Nat; items : [(SagaTM.Toid, ?SagaTM.Order)] }; ttPool : { total : Nat; items : [(SagaTM.Ttid, SagaTM.Task)] } }
```

Returns lists of active transaction orders and transaction tasks

## Function `ictc_getTOPool`
``` motoko no-repl
func ictc_getTOPool() : async [(SagaTM.Toid, ?SagaTM.Order)]
```

Returns a list of active transaction orders

## Function `ictc_getTT`
``` motoko no-repl
func ictc_getTT(_ttid : SagaTM.Ttid) : async ?SagaTM.TaskEvent
```

Returns a record of a transaction task 

## Function `ictc_getTTByTO`
``` motoko no-repl
func ictc_getTTByTO(_toid : SagaTM.Toid) : async [SagaTM.TaskEvent]
```

Returns all tasks of a transaction order

## Function `ictc_getTTs`
``` motoko no-repl
func ictc_getTTs(_page : Nat, _size : Nat) : async { data : [(SagaTM.Ttid, SagaTM.TaskEvent)]; totalPage : Nat; total : Nat }
```

Returns a list of transaction tasks

## Function `ictc_getTTPool`
``` motoko no-repl
func ictc_getTTPool() : async [(SagaTM.Ttid, SagaTM.Task)]
```

Returns a list of active transaction tasks

## Function `ictc_getTTErrors`
``` motoko no-repl
func ictc_getTTErrors(_page : Nat, _size : Nat) : async { data : [(Nat, SagaTM.ErrorLog)]; totalPage : Nat; total : Nat }
```

Returns the transaction task records for exceptions

## Function `ictc_getCalleeStatus`
``` motoko no-repl
func ictc_getCalleeStatus(_callee : Principal) : async ?SagaTM.CalleeStatus
```

Returns the status of callee.

## Function `ictc_clearLog`
``` motoko no-repl
func ictc_clearLog(_expiration : ?Int, _delForced : Bool) : async ()
```

Clear logs of transaction orders and transaction tasks.  
Warning: Execute this method with caution

## Function `ictc_clearTTPool`
``` motoko no-repl
func ictc_clearTTPool() : async ()
```

Clear the pool of running transaction tasks.  
Warning: Execute this method with caution

## Function `ictc_blockTO`
``` motoko no-repl
func ictc_blockTO(_toid : SagaTM.Toid) : async ?SagaTM.Toid
```

Change the status of a transaction order to #Blocking.

## Function `ictc_appendTT`
``` motoko no-repl
func ictc_appendTT(_businessId : ?Blob, _toid : SagaTM.Toid, _forTtid : ?SagaTM.Ttid, _callee : Principal, _callType : SagaTM.CallType, _preTtids : [SagaTM.Ttid]) : async SagaTM.Ttid
```

Governance or manual compensation (operation allowed only when a transaction order is in blocking status).

## Function `ictc_redoTT`
``` motoko no-repl
func ictc_redoTT(_toid : SagaTM.Toid, _ttid : SagaTM.Ttid) : async ?SagaTM.Ttid
```

Try the task again.  
Warning: proceed with caution!

## Function `ictc_doneTT`
``` motoko no-repl
func ictc_doneTT(_toid : SagaTM.Toid, _ttid : SagaTM.Ttid, _toCallback : Bool) : async ?SagaTM.Ttid
```

Set status of a pending task  
Warning: proceed with caution!

## Function `ictc_doneTO`
``` motoko no-repl
func ictc_doneTO(_toid : SagaTM.Toid, _status : SagaTM.OrderStatus, _toCallback : Bool) : async Bool
```

Set status of a pending order  
Warning: proceed with caution!

## Function `ictc_completeTO`
``` motoko no-repl
func ictc_completeTO(_toid : SagaTM.Toid, _status : SagaTM.OrderStatus) : async Bool
```

Complete a blocking order  
After governance or manual compensations, this method needs to be called to complete the transaction order.

## Function `ictc_runTO`
``` motoko no-repl
func ictc_runTO(_toid : SagaTM.Toid) : async ?SagaTM.OrderStatus
```

Run the ICTC actuator and check the status of the transaction order `toid`.

## Function `ictc_runTT`
``` motoko no-repl
func ictc_runTT() : async Bool
```

Run the ICTC actuator

## Function `drc207`
``` motoko no-repl
func drc207() : async DRC207.DRC207Support
```

* End: ICTC Transaction Explorer Interface
Returns the monitorability configuration of the canister.

## Function `wallet_receive`
``` motoko no-repl
func wallet_receive() : async ()
```

canister_status
Receive cycles

## Function `withdraw_cycles`
``` motoko no-repl
func withdraw_cycles(_amount : Nat) : async ()
```

Withdraw cycles

## Function `timerStart`
``` motoko no-repl
func timerStart(_intervalSeconds : Nat) : async ()
```

Starts timer.

## Function `timerStop`
``` motoko no-repl
func timerStop() : async ()
```

Stops timer.

## Function `setUpgradeMode`
``` motoko no-repl
func setUpgradeMode(_mode : {#Base; #All}) : async ()
```


## Function `backup`
``` motoko no-repl
func backup(_request : BackupRequest) : async BackupResponse
```

Backs up data of the specified `BackupRequest` classification, and the result is wrapped using the `BackupResponse` type.

## Function `recovery`
``` motoko no-repl
func recovery(_request : BackupResponse) : async Bool
```

Restore `BackupResponse` data to the canister's global variable.
