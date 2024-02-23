# ICDexPair
* Actor      : ICDexPair
 * Author     : ICLighthouse Team
 * Stability  : Experimental
 * Github     : https://github.com/iclighthouse/ICDex/

## Overview

ICDexPair is a trading pair contract where each trading pair is deployed into a separate canister.

ICDexPair is created by the ICDexRouter, its controller is by default the ICDexRouter and can be modified.

## 1 Concepts

### Order Book and Matching Engine
The basic function of the Order Book is to match buyers and sellers in the market. The order book is the mechanism used by 
the majority of electronic exchanges today, both in the financial and the cryptocurrency markets. The book has two sides, 
asks and bids. Asks are sometimes called offers. Asks consists of orders from other traders offering to sell an asset. Bids 
are orders from traders offering to buy an asset.

### Accounts and Roles

The traders are identified by `AccountId` in the pair, and support subaccounts. An account has one or more of the following identities:
- Trader (User): Ordinary trader, no authorization required.
    - Maker: A trader who submits an order into the order book to increase liquidity when trading, is the `Maker` of the order, 
    and has a default trading fee of 0.
    - Taker: A trader who submits an order that immediately matches other orders in the order book and thus takes away liquidity, 
    is the `Taker` of the order and has to pay a trading fee.
- Vip-Maker: The Owner (ICDexRouter) grants the role of `Vip-Maker` to a trader and specifies a rebate percentage, so that when he 
is on the `Maker` side of an order, he will receive a rebate on the trading fee.
- Trading Ambassador (Referrer): A trader with a volume greater than 0 becomes a Trading Ambassador (Referrer) without authorization.
He can refer new users to the trading pair which will count the number of users referred by him and the total volume of their trades.
- Broker: Other Dapps can integrate with ICDex as a `Broker`, specifying the broker parameter when calling the trading interface, 
in order to get the fee income, which is paid by Taker. No authorization is required for Broker role.
- Pro-Trader: A Trader who trades using the Strategy Order feature, called `Pro-Trader`, requires no authorization.

Dedicated accounts in trading pair:
- TxAccount: An account dedicated to an order in tunnel mode, is used to temporarily hold funds for the order. It is in a locked state 
and funds are not sent from that account to the recipient until that order is filled or canceled.  Each order has a separate 
account from each other with the address `{ owner = pair_canister_id; subaccount = ?txid }`. Funds left in TxAccount due to 
an exception can be retrieved by the fallback operation.
- PoolAccount: A pool account for trading pairs that is used to centrally hold temporary funds for all orders, the ownership 
and status of which is handled by TraderAccount ledger records. e.g. `{ owner = pair_canister_id; subaccount = null }`. 
- TraderAccount: The local ledger in a trading pair is used to keep track of the balances that traders keep in PoolAccount. 
TraderAccount balance is divided into locked and available, and traders can increase or decrease the available balance by 
depositing and withdrawing funds. TraderAccount does not hold the tokens directly, its balance is queried through the 
accountBalance() and safeAccountBalance() methods of the trading pair.
- DepositAccount: A temporary account for traders to deposit funds into the available balance of TraderAccount. Each trader has 
a separate DepositAccount with the address `{ owner = pair_canister_id; subaccount = ?accountId }`. Funds left in DepositAccount 
due to an exception can be retrieved by the fallback operation.

### Exchange Mode

While a trader places an order, the funds will be custodied in the trading pair canister, depending on the custody method. 
Exchange Mode is categorized:
- TunnelMode: While a trader submits an order, the funds are deposited into an order-specific account (`TxAccount`, 
Txn Tunnel Account). When the order is filled, the funds are transferred from the order-specific account to the target trader's 
account. Each order has a separate and unique Tunnel (i.e. `{ owner = pair_canister_id; subaccount = ?txid }`).
- PoolMode: While a trader submits an order, the funds are deposited into the `Pool Account of the pair` (`PoolAccount`). 
When the order is filled, the funds are transferred from the Pool to the target trader's account. The PoolAccount 
(i.e. `{ owner = pair_canister_id; subaccount = null }`) is a fixed account.

### Keeping Funds in TraderAccount

If a trader has "Keeping balance in TraderAccount" enabled, then when he trades, the funds in that TraderAccount will be used by default., 
and the received tokens will be deposited into this TraderAccount by default. All the assets in the trader's TraderAccount are kept in 
PoolAccount, and the trader can deposit funds into his TraderAccount or withdraw funds from his TraderAccount.
### Base Token (token0) and Quote Token (token1)

A trading pair is the quotation of two different cryptocurrencies, with the value of one token (cryptocurrency) being quoted 
against the other. The first listed token (named token0) of a trading pair is called the base token, and the second token 
(named token1) is called the quote token. 

Inside the trading pair, the balances of token0 and token1 are represented as integers whose values refer to the SMALLEST unit token. 
The human-readable representation of the balance is converted in the UI by the front-end code.

### DebitToken and CreditToken

In an MKT order, When adding token0 to purchase token1, we call token0 a DebitToken and token1 a CreditToken. Similarly, 
when adding token1 to buy token0, we call token0 a CreditToken and token1 a DebitToken.

### Token Amount
Unless otherwise specified, the units used to represent the number of tokens in a trading pair are SMALLEST UNITS.

### UNIT_SIZE and Price

- UNIT_SIZE: It is the base number of quotes in the trading pair and the minimum quantity (token0) to be used when placing an order. 
The quantity (token0) of the order placed must be an integer multiple of UNIT_SIZE.
- Price: The amount of token1 (smallest units) is required to purchase UNIT_SIZE token0 (smallest units).
- Human-readable price: Translate to a human-readable representation of the price, using the token's decimals.
`Human-readable price = Price * (10 ** token0Decimals) / (10 ** token1Decimals) / UNIT_SIZE`

### Nonce

ICDexPair uses the nonce mechanism, where each account has a nonce value in a trading pair, which by default is 0. When the trader 
creates a new order, his current nonce value will be used to the order, and then `nonce + 1` as the next available value. The trader 
can create an order without filling in the nonce, the trading pair will automatically take the value and increment it. If a trader 
specifies a nonce value when opening an order, the value must be a currently available value for the account in the pair, it cannot 
be a used value, nor can it be an excessively large value, otherwise an error will be reported.

### Strategy Order

Strategy Orders are also known as Algorithmic Orders. The trader configures the parameters according to the strategy rules of the 
trading pair, and when the market price meets the conditions, the trading pair will automatically place trade orders for the trader. 
Strategy Orders is divided into Pro-Order and Stop-Limit-Order (Stop-Loss-Order).
- Pro-Order: Grid, Iceberg, VWAP and TWAP orders have been implemented.
- Stop-Limit-Order: Stop-loss conditional orders have been implemented.
Clearly indicate:  
A `Strategy order` is a strategy rule configuration that does not place a trade order into the order book until it is triggered. 
A `Trade order` is a real order in the order book and is what is normally referred to as a `Trade`.

Finance reference: (Note: There are some differences in the implementation details of ICDex)
- Stop-limit Order: https://corporatefinanceinstitute.com/resources/career-map/sell-side/capital-markets/stop-loss-order/
- Grid Order: https://www.binance.com/en/support/faq/what-is-spot-grid-trading-and-how-does-it-work-d5f441e8ab544a5b98241e00efb3a4ab
- Iceberg Order: https://corporatefinanceinstitute.com/resources/career-map/sell-side/capital-markets/iceberg-order/
- VWAP Order: https://en.wikipedia.org/wiki/Volume-weighted_average_price
- TWAP Order: https://en.wikipedia.org/wiki/Time-weighted_average_price

### IDO

IDO is a decentralized sale on Dex. ICDex trading pairs can have the IDO functionality activated by the Owner (DAO) and an IDO Funder 
set up before opening of trading. The IDO configuration is done by the IDO Funder and orders are placed according to the configuration 
and then the IDO is opened.

## 2 Fee model

The fee rules for trading pair are calculated based on the status of an order and the matching of the order, and a post-fee model is 
used for filling the order, i.e., the fee is charged based on the token (token0 or token1) amount multiplied by the commission rate that 
the trader's account that is being charged has received in the order.  
The fees collected by ICDex, after deducting Vip-maker incentives, network gas, etc., are reserved in the ICDexRouter account, and there 
is a DAO who decides on their use, e.g., destruction, repurchase, etc.  
- Maker-fee: When an order is filled, the maker pays a commission rate which is currently 0% by default, a negative value means that the 
maker receives a commission.
- Taker-fee: When an order is filled, taker pays a fee based on the filled amount, and fee rate is currently 0.5% by default.
- Vip-maker rebate: When an order is filled, if the maker's role is as a Vip-maker, then he can get a specified percentage of the commission 
paid by the taker as a reward, which may vary from Vip-maker to Vip-maker.
- Cancelling-fee: An order canceled within 1 hour of placing it will be charged a fee (Taker_fee * 20%) if nothing is filled, 
This fee is limited to a range from `token fee * 2` to `token fee * 1000`.
No cancellation fee is paid for strategic orders.
- Strategic order
    - Pro-Order: 
    When configuring a pro-order strategy, traders are charged a fixed amount of ICL as a fee (poFee1) and the fee for updating the 
    strategy is poFee1 * 5%. Vip-maker is not be charged poFee1. When the strategy is triggered and the new trade order is closed, the 
    trader is charged the amount of tokens (token0 or token1) he receives multiplied by the rate (poFee2) as a pro-trade fee.
    - Stop-Limit-Order: 
    When configuring a stop-limit-order strategy, traders are charged a fixed amount of ICL as a fee (sloFee1) and the fee for 
    updating the strategy is sloFee1 * 5%. Vip-maker is not be charged sloFee1. When the strategy is triggered and the new trade order 
    is closed, the trader is charged the amount of tokens (token0 or token1) he receives multiplied by the rate (sloFee2) as a 
    stop-limit-trade fee.

## 3 Core functionality

### Order Book and Matching Engine

The basic function of the Order Book is to match buyers and sellers in the market. The order book is the mechanism used by the majority 
of electronic exchanges today, both in the financial and the cryptocurrency markets.
More instructions are available at https://github.com/iclighthouse/ICDex/blob/main/OrderBook.md

### TunnelMode Trade

By default, traders trade in Tunnel Mode, where the funds for each order are stored in a dedicated address (TxAccount), and different 
orders are segregated from each other, as if each order had a tunnel.  
Trading process in tunnel mode:
- Step1  
Call getTxAccount() to get the TxAccount, nonce and txid of the new order. This is a query method, if called off-chain (e.g., web-side) 
you need to use the generateTxid() method of DRC205 to generate a txid and TxAccount.
- Step2  
Deposit to TxAccount the funds needed for the order.
    - DebitToken is DRC20/ICRC2 token: not needed to transfer funds to TxAccount, but need to approve sufficient amount (value + 
    token_fee) PoolAccount could spend.
    - DebitToken is ICRC1 token: need to call icrc1_transfer to transfer the required funds (value) to TxAccount.
- Step3  
Calls the trade(), trade_b(), tradeMKT(), or tradeMKT_b() methods to submit a trade order. When submitting an order nonce can be filled 
with null, if a specific value is filled it must be the currently available nonce value, otherwise an exception is thrown. The advantage 
of providing a nonce value for a trade is that the txid can be calculated in advance from the nonce value.

### PoolMode Trade
The trader is required to call the accountConfig() method to enable PoolMode. Funds for PoolMode orders are kept in PoolAccount and 
are recorded in the trader's TraderAccounts and are in the locked state. The funds are sent to the recipients when the order is matched 
or canceled.    
Notes:   
In PoolMode, it is compatible with TunnelMode's trading process, the difference is that the approving amount in Step2 should be 
added with an additional token_fee (approve: (value + token_fee * 2) or transfer: (value + token_fee)).   
The following is the trading process of TunnelMode:   
If the available balance in the trader's TraderAccount is sufficient, the operation starts from Step4. Otherwise the operation starts 
from Step1. 
- Step1
Call getDepositAccount() to get the DepositAccount. This is a query method, if called off-chain (e.g., web-side),  
You should generate the account address directly using the following rule: `{owner = pair_canister_id; subaccount = ?your_accountId }`.
- Step2  
Deposit funds to DepositAccount.
    - DebitToken is DRC20/ICRC2 token: not needed to transfer funds to DepositAccount, but need to approve sufficient amount (value + 
    token_fee * 2) PoolAccount could spend.
    - DebitToken is ICRC1 token: need to call icrc1_transfer to transfer the required funds (value + token_fee) to DepositAccount.
- Step3  
Calling deposit() completes the deposit operation, the funds are deposited into PoolAccount, and TraderAccount increases the available 
balance.
- Step4  
Calls the trade(), trade_b(), tradeMKT(), or tradeMKT_b() methods to submit a trade order. When submitting an order nonce can be filled 
with null, if a specific value is filled it must be the currently available nonce value, otherwise an exception is thrown. The advantage 
of providing a nonce value for a trade is that the txid can be calculated in advance from the nonce value.  
- Step5  
If the trader has not enabled "Keeping balance in TraderAccount", the funds in TraderAccount will be automatically withdrawn to the 
trader's wallet. If he has enabled this option, he needs to call withdraw() method to complete the withdrawal operation. Withdrawal is 
sending funds from PoolAccount to Trader's Wallet while decreasing the available balance in his TraderAccount.

### Strategy Order

The Strategy Order function is a strategy manager for pro-traders. Strategy Order includes pro-order and stop-limit-order.  
The strategy order lifecycle is divided into two segments: 
1) Configure a strategy: Pro-trader selects a strategy type, configures the strategy parameters and starts a strategy.
2) Trigger Order: When the latest price of the trading pair changes and meets the conditions of the strategy order, the Strategy Manager 
(Worktop) will automatically trigger the order.  
Notes:
- Ordinary orders may trigger a strategy to place an order when they are filled, while strategy orders will not trigger a strategy to 
place an order again.
- The triggers of the strategy do not guarantee that the order will be placed successfully or that it will be filled immediately, and 
there may be multiple uncertainties.
- When it is busy, the trigger price may have a deviation of about 0.5%, and the system will ignore multiple triggers within 10 seconds 
and trigger only once.

Strategy orders use the hook mechanism. When an order is submitted, it executes the strategy worktop function _hook_stoWorktop(). 
When an order is filled with matches, it executes _hook_fill(). When an order is fully filled, it executes _hook_close(). When an 
order is canceled, it executes _hook_cancel().

### IDO

IDO (Initial DEX Offering), is a mechanism for tokens to be sold to traders or specific parties at the beginning of the token's 
listing on ICDex, which is authorized by owner (DAO) and configured by the Funder of the base token. 
- Configure: 
    - Open IDO: Owner (DAO) calls IDO_setFunder() method of the trading pair to open IDO, set the participation threshold, specify 
    Funder.
    - Funder Configuration: Funder calls the IDO_config() method for configuration, and the configuration items include IDO time, 
    whitelist, tiered supply rules, and participation limits.
- Tiered supply rules:
    - Funder sets the total supply of tokens to be used for IDO and sets a tiered supply of one or more price levels, with the lowest 
    priced supply being prioritized for purchase, and users getting first come, first served within the purchase limit.
- IDO Timeline: Funder configures IDO's IDOpeningTime and IDOClosingTime. IDOOpeningTime is also the time when the trading pair opens, 
and IDOClosingTime is also the time when the trading pair officially opens for trading.
    - Funder can modify the IDO configuration up to 24 hours before the IDOOpeningTime and in case the trading pair does not have any orders;
    - Prior to IDOOpeningTime, Funder can place orders (LMT type, Sell side, order price and quantity must be exactly a tiered price 
    and supply) according to the IDO configured tiered supply data, and can set up whitelisting and participation limits;
    - During IDOpeningTime ~ IDOClosingTime, the user (purchaser) can buy tokens (FOK type, Buy side, the order quantity must be 
    within the participation limit);
    - After IDOClosingTime, Funder's orders that are not fully filled will be canceled and the trading pair will be opened for normal trading.
- Participation Limits: 
    - Whitelist mode: if Funder has enabled whitelist mode, only users in the whitelist are eligible to purchase the number of tokens 
    within the whitelist quota.
    - Non-whitelist mode: Funder does not enable whitelist, any eligible account can participate in IDO:
        - Qualification for participation: 1) If ICDexRouter does not configure the participation threshold (threshold=0) when it enabled IDO, 
        it means that all users are eligible to participate in IDO. 2) If ICDexRouter configures the participation threshold (threshold>0) 
        when it enabled IDO, the user's volume of a specified pairs of trading converted to USD value exceeds the threshold, he is eligible 
        to participate in IDO. If the value does not exceed threshold, Funder can directly set the whitelist quota for the user, then he 
        is also eligible to participate in IDO.
        - Participation limit: A user who is eligible to participate in IDO can purchase a number of tokens within the default limit (if 
        the user has been assigned a whitelisted quota, then the whitelisted quota shall prevail).
- How users (purchasers) participate: 
    - Step1: (Optional) Call IDO_updateQualification() to confirm qualification and quota. It must be called if the IDO is configured with 
    a participation threshold (threshold>0). Qualification and quota can be queried via IDO_qualification().
    - Step2: Call the trade() method of the trading pair as a FOK order to complete the purchase during IDO opening time.

### Trading Ambassador (Referrer)

Each trading pair has a referrer system, where any user with a trading volume greater than 0 can become a referrer, also known as a 
Trading Ambassador. The referrer can get the referral link on ICDex UI and send it to the receiver, and the receiver will call ta_setReferrer() 
when he enters the trading pair for the first time through the link, and the trading pair will record the referral relationship and count 
the trading volume.

Referral rewards: The trading pair only counts the referral relationship and trading volume, there is no mechanism for direct rewards. 
Referral rewards need to be organized by DEX platform side or token project side, and the referral statistics of the trading pair can 
provide reference for them to distribute rewards.

### ICTC

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

### DRC205

ICDex uses DRC205 (https://github.com/iclighthouse/DRC_standards/tree/main/DRC205) for externally scalable storage of DEX transaction records 
so that it is possible to blockchain browser https://ic.house/swaps to to view transaction records. ICDex introduces the DRC205 module 
(https://github.com/iclighthouse/icl-vessel/blob/main/src/DRC205.mo) into the trading pair, which saves the transaction records to DRC205 
bucket while caching the recent records in the trading pair canister. The DRC205 is only responsible for record storage and does not affect 
the security of the assets of the trading pair.

### Preventing DOS Attacks

The reverse-gas model of IC can easily invite DOS attacks, which are damaging to Defi applications. Our strategy is to maximize the 
cost of the attack, limit anomalous accesses, and make controls on several aspects such as access interval, TPS, number of asynchronous 
messages, total number of orders, global locks, and so on. If the number of ICTC exceptions is too large, or the trading pair PoolAccount 
balance is abnormal, the trading pair will be automatically suspended.

## 4 Deployment

Initialize parameters
```
type InitArgs = {
    name: Text; // Name of the trading pair, e.g. "icdex:XYZ/ICP".
    token0: Principal; // The base token canister-id.
    token1: Principal; // The quote token canister-id.
    unitSize: Nat64; // See section "UNIT_SIZE and Price".
    owner: ?Principal; // Deprecated. Instead use Principal.isController()
}
```

- Approach 1  
The Owner (DAO) calls the create() method of the ICDexRouter to create a trading pair, which is in a suspended state. You can configure 
the official opening time, whether to start IDO, etc.

- Approach 2  
The user calls the ICDexRouter's pubCreate() method to create a trading pair, and pays a specified number of ICL tokens as a fee, and 
the created pair is in a tradable state.

Notes:
- Trading pairs have a dependency on their own canister-id, so it is not possible to migrate the data to another canister. you may need 
to redeploy a trading pair and call the mergePair() method to migrate the data such as total volume and k-line charts, etc. 
- Trading pair transaction records are stored via DRC205 and cannot be deleted. To prevent duplication of account trading records, do not 
execute reinstall on pair canister.

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


## Function `init`
``` motoko no-repl
func init() : async ()
```

Initialization function. If it is not called explicitly, _init() will be called on the first trade.

## Function `prepare`
``` motoko no-repl
func prepare(_account : Address) : async (TxAccount, Nonce)
```

@deprecated: This method will be deprecated. The getTxAccount() method will replace it.

## Function `getTxAccount`
``` motoko no-repl
func getTxAccount(_account : Address) : async (ICRC1.Account, TxAccount, Nonce, Txid)
```

In tunnel mode, the trader gets the next order's nonce value, TxAccount, Txid.  
Warning: This is a query function and direct adoption of the results returned by the call may be a security risk. 
    You need to use account and nonce to perform local calculations according to the generateTxid() method in DRC205 
    and verify the TxAccount address.

## Function `tradeCore`
``` motoko no-repl
func tradeCore(_order : OrderPrice, _orderType : OrderType, _expiration : ?PeriodNs, _nonce : ?Nonce, _sa : ?Sa, _data : ?Data, _brokerage : ?{ broker : Principal; rate : Float }, _quickly : ?Bool) : async TradingResult
```

The core, and most versatile, trading function.

Arguments:
- orderPrice: OrderPrice. 
    Type OrderPrice = { quantity: {#Buy: (Quantity, Amount); #Sell: Quantity; }; price: Price; }
    - quantity: Orders are divided into #Buy and #Sell depending on the Side. the quantity must be an integer multiple of UNIT_SIZE.
        - #Buy: Specify the number of token0 to be purchased and the amount of token1 to be used for the purchase. token1 is DebitToken.
        - #Sell: Specify the number of tokens0 to be sold. token0 is DebitToken.
    - price: How much token1 (smallest units) are needed to purchase UNIT_SIZE token0 (smallest units). Orders may be filled 
    at a better price than this. If MKT order type, price can be filled in 0 or a limit price.   
        - If the order side is Buy, the variant {Buy = (x, y)} must be filled in. x indicates the amount (smallest_units) of token0 
    to be purchased and y indicates the amount (smallest_units) of token1 to be paid. y is required for MKT orders and is optional 
    for other types of orders.  
        - If the order side is Sell, the variant {Sell = x } must be filled in. x indicates the amount (smallest_units) 
    of token0 to be sold.  
    Note: If the price of an MKT order is filled with 0, it means that any price is accepted. If price is filled with a 
    non-zero value, it means that the slippage is controlled, e.g. the price limit for buy order is less than or equal to price 
    and the price limit for sell order is greater than or equal to price.
- orderType: OrderType. Order type. Such as: LMT, MKT, FAK, FOK.
- expiration: ?PeriodNs. The order expiration duration (nanoseconds), which is generally 90 days by default.
- nonce: ?Nonce. Optionally specify nonce value.
- sa: ?Sa. Optionally specify the subaccount of the caller
- data: ?Data. Optional Remark data, like memo.
e.g. '(record{ quantity=variant{Sell=5_000_000}; price=10_000_000;}, variant{LMT}, null, null, null, null)'
- brokerage: ?{ broker: Principal; rate: Float; }. Set the broker’s receiving account (principal) and brokerage rates.
- quickly: ?Bool. Sets whether to execute quickly or not, if it is set to true, it will return asynchronously without waiting for the execution of the ICTC to be completed.

Returns:
- res: TradingResult. Returns order result. The execution is asynchronous, Record the txid and you can check the order 
    status through drc205_events() or statusByTxid().

See the `UNIT_SIZE and Price` section for a description of PRICE and human-readable PRICE.

## Function `trade`
``` motoko no-repl
func trade(_order : OrderPrice, _orderType : OrderType, _expiration : ?PeriodNs, _nonce : ?Nonce, _sa : ?Sa, _data : ?Data) : async TradingResult
```

Generic trade method that do not support broker  
@deprecated: This method will be deprecated. Suggested alternative to using tradeCore().

## Function `trade_b`
``` motoko no-repl
func trade_b(_order : OrderPrice, _orderType : OrderType, _expiration : ?PeriodNs, _nonce : ?Nonce, _sa : ?Sa, _data : ?Data, _brokerage : ?{ broker : Principal; rate : Float }) : async TradingResult
```

Generic trade method that support broker  
@deprecated: This method will be deprecated. Suggested alternative to using tradeCore().

## Function `tradeMKT`
``` motoko no-repl
func tradeMKT(_token : DebitToken, _value : Amount, _nonce : ?Nonce, _sa : ?Sa, _data : ?Data) : async TradingResult
```

Fast MKT ordering method  
@deprecated: This method will be deprecated. Suggested alternative to using tradeMKT_b().

## Function `tradeMKT_b`
``` motoko no-repl
func tradeMKT_b(_token : DebitToken, _value : Amount, _limitPrice : ?Nat, _nonce : ?Nonce, _sa : ?Sa, _data : ?Data, _brokerage : ?{ broker : Principal; rate : Float }) : async TradingResult
```

Fast MKT ordering method (supported broker)

The trader adds _value number of DebitToken and if the order match is successful, he will get some number of CreditToken.

Arguments:
- debitToken: Principal. DebitToken’s canister-id (DebitToken: The token that the trader needs to add to the trading pair).
- value: Amount. The amount of DebitToken you want to add.
- limitPrice: ?Nat; The most unfavorable price that can be accepted, null means any price is accepted.
- nonce: ?Nonce. Optionally specify nonce value.
- sa: ?Sa. Optionally specify the subaccount of the caller
- data: ?Data. Optional Remark data, like memo.
- brokerage: ?{ broker: Principal; rate: Float; }. Set the broker’s receiving account (principal) and brokerage rates.

Returns:
- res: TradingResult. Returns order result. The execution is asynchronous, Record the txid and you can check the order 
    status through drc205_events() or statusByTxid().


## Function `cancel`
``` motoko no-repl
func cancel(_nonce : Nonce, _sa : ?Sa) : async ()
```

The trader cancels an order

Arguments:
- nonce: Nat. Nonce of the order. If you don't know the nonce of order, you can call cancelByTxid().
- sa: ?Sa. Optionally specify the subaccount of the caller

## Function `cancelByTxid`
``` motoko no-repl
func cancelByTxid(_txid : Txid, _sa : ?Sa) : async ()
```

The trader or Owner (DAO) cancels an order

Arguments:
- txid: Txid. Specify txid of the order.
- sa: ?Sa. Optionally specify the subaccount of the caller

## Function `cancelAll`
``` motoko no-repl
func cancelAll(_args : {#management : ?AccountId; #self_sa : ?Sa}, _side : ?OrderBook.OrderSide) : async ()
```

Batch cancel orders. If `side` (#Buy or #Sell) is specified, only one side of the orders will be canceled.
1. Owner (DAO) caller: Cancel all orders or orders for a specific account.
2. Trader caller: Cancel all his own orders.

Arguments:
- args: {#management: ?AccountId; #self_sa: ?Sa}. Owner (DAO) specifies #management parameter, Trader specifies #self_sa parameter.
- side: ?OrderBook.OrderSide. Optionally specify the side (#Buy or #Sell), only one side of the orders will be canceled.

## Function `fallback`
``` motoko no-repl
func fallback(_nonce : Nonce, _sa : ?Sa) : async Bool
```

While in tunnel mode, retrieve funds from TxAccount for an order that is inactive and is not in fallbacking lockout.
When fallback() is called, the fallbacking state of the specified txid will be locked for up to 72 hours. 
It is unlocked when the execution of the ICTC associated with the fallback completes, or it is automatically unlocked after 72 hours.

Arguments:
- nonce: Nat. Specify nonce of the order. If you don't know the nonce of order, you can call fallbackByTxid().
- sa: ?Sa. Optionally specify the subaccount of the caller

Results:
- res: Bool

## Function `fallbackByTxid`
``` motoko no-repl
func fallbackByTxid(_txid : Txid, _sa : ?Sa) : async Bool
```

While in tunnel mode, retrieve funds from TxAccount for an order that is inactive and is not in fallbacking lockout.
When fallbackByTxid() is called, the fallbacking state of the specified txid will be locked for up to 72 hours. 
It is unlocked when the execution of the ICTC associated with the fallback completes, or it is automatically unlocked 
after 72 hours.

Note: If the Owner (DAO) calls this method, the funds of the TxAccount will be refunded to the ICDexRouter canister-id.

Arguments:
- txid: Txid. Specify txid of the order.
- sa: ?Sa. Optionally specify the subaccount of the caller

Results:
- res: Bool

## Function `pending`
``` motoko no-repl
func pending(_account : ?Address, _page : ?ListPage, _size : ?ListSize) : async TrieList<Txid, TradingOrder>
```

Query all orders of a trader that are in pending status

Arguments:
- account: ?Address. Specify account of the trader, hex of account-id or principal.
- page: ?ListPage. Page number.
- size: ?ListSize. Number of records per page.

Results:
- res: TrieList<Txid, TradingOrder>. 

## Function `pendingCount`
``` motoko no-repl
func pendingCount() : async Nat
```

Query the total number of orders in pending status for the pair.

## Function `pendingAll`
``` motoko no-repl
func pendingAll(_page : ?ListPage, _size : ?ListSize) : async TrieList<Txid, TradingOrder>
```

Query all orders in pending status. Only the Owner (DAO) is allowed to query it.

Arguments:
- page: ?ListPage. Page number.
- size: ?ListSize. Number of records per page.

Results:
- res: TrieList<Txid, TradingOrder>. 

## Function `volsAll`
``` motoko no-repl
func volsAll(_page : ?ListPage, _size : ?ListSize) : async TrieList<AccountId, Vol>
```

Resturns volume for all users

## Function `status`
``` motoko no-repl
func status(_account : Address, _nonce : Nonce) : async OrderStatusResponse
```

Query the status of an order by account and nonce.

## Function `statusByTxid`
``` motoko no-repl
func statusByTxid(_txid : Txid) : async OrderStatusResponse
```

Query the status of an order by txid.

## Function `latestFilled`
``` motoko no-repl
func latestFilled() : async [(Timestamp, Txid, OrderFilled, OrderSide)]
```

Query the last 50 records of trades

## Function `makerRebate`
``` motoko no-repl
func makerRebate(_maker : Address) : async (rebateRate : Float, feeRebate : Float)
```

Query the rebate rate of a maker. The return value `rebateRate = 0` means that it is an ordinary maker role with 
no rebate; `rebateRate > 0` means that it is a vip-maker role with rebate.

Arguments:
- maker: Address. Account address.

Results:
- res: (rebateRate: Float, feeRebate: Float).  rebateRate (res.0) indicates the rebate rate; 
    feeRebate (res.1) indicates the percentage of commission that can be earned when an order for a maker is filled (trading_fee * rebateRate)

## Function `level10`
``` motoko no-repl
func level10() : async (unitSize : Nat, orderBook : { ask : [PriceResponse]; bid : [PriceResponse] })
```

Query 10 levels of quotes in the order book

## Function `level100`
``` motoko no-repl
func level100() : async (unitSize : Nat, orderBook : { ask : [PriceResponse]; bid : [PriceResponse] })
```

Query 100 levels of quotes in the order book

## Function `name`
``` motoko no-repl
func name() : async Text
```

Name of the trading pair

## Function `version`
``` motoko no-repl
func version() : async Text
```

Version of the trading pair

## Function `token0`
``` motoko no-repl
func token0() : async (DRC205.TokenType, ?Types.TokenStd)
```

Query the infomation of Base Token (token0)

## Function `token1`
``` motoko no-repl
func token1() : async (DRC205.TokenType, ?Types.TokenStd)
```

Query the infomation of Quote Token (token1)

## Function `count`
``` motoko no-repl
func count(_account : ?Address) : async Nat
```

Query the number of orders for a trader (and also the value of nonce currently available for that trader), 
or the number of orders for the trading pair if account is not specified.

## Function `userCount`
``` motoko no-repl
func userCount() : async Nat
```

Counting the number of traders in the pair

## Function `fee`
``` motoko no-repl
func fee() : async { maker : { buy : Float; sell : Float }; taker : { buy : Float; sell : Float } }
```

Query the current trading fee (does not reflect vip-maker rebate and does not reflect broker commission). 
broker commission will be charged additionally and paid additionally by the taker.

## Function `feeStatus`
``` motoko no-repl
func feeStatus() : async Types.FeeStatus
```

@deprecated: This method will be deprecated. 

## Function `liquidity`
``` motoko no-repl
func liquidity(_account : ?Address) : async Types.Liquidity
```


## Function `liquidity2`
``` motoko no-repl
func liquidity2(_account : ?Address) : async Types.Liquidity2
```

Query the liquidity profile of the trading pair, or query the liquidity information of a specified trader.
This is not a very accurate statistic due to performance considerations.

Arguments:
- account: ?Address. Optionally specify a trader's account. If the value is not null it means to query the trader's 
    liquidity information, if the value is null it means to query the pair liquidity information.

Results:
- res: Types.Liquidity2. 
    - Trader Liquidity: 
        ```
        {
            token0: Nat; // Smallest units. Liquidity of the trader (The balance locked in the PENDING status orders for the trader, plus the available balance for the trader kept in the pool of pair.)
            token1: Nat; 
            price: Nat; // Price: How much token1 (smallest units) are needed to purchase UNIT_SIZE token0 (smallest units).
            unitSize: Nat; // UNIT_SIZE
            priceWeighted: Nat; // Time-weighted price
            vol: { value0: Nat; value1: Nat;}; // Smallest units. Cumulative volume of the trader.
            orderCount: Nat64; // Total number of the trader's orders
            userCount: Nat64; // Total number of users of trading pair
            shares = 0; // This field has no meaning and is only for compatibility with the AMM Dex data structure
            unitValue = (0, 0); // This field has no meaning and is only for compatibility with the AMM Dex data structure
            shareWeighted = { shareTimeWeighted=0; updateTime=0 }; // This field has no meaning and is only for compatibility with the AMM Dex data structure
        }
        ```
    - Pair Liquidity:
        ```
        {
            token0: Nat; /* Smallest units. Liquidity in trading pair. Estimated in two ways: 1) when the total 
              number of orders is less than 20,000, the value includes the balances locked in the pending order 
              and the available balances kept in the pair; 2) when the total number of orders is greater than or 
              equal to 20,000, the value includes the total balance kept in the pair (without the balances locked 
              in tunnel mode's pending orders). */
            token1: Nat; 
            price: Nat; // Price: How much token1 (smallest units) are needed to purchase UNIT_SIZE token0 (smallest units).
            unitSize: Nat; // UNIT_SIZE
            priceWeighted: Nat; // Time-weighted price
            vol: { value0: Nat; value1: Nat;}; // Smallest units. Total volume.
            orderCount: Nat64; // Total number of orders of trading pair
            userCount: Nat64; // Total number of users of trading pair
            shares = 0; // This field has no meaning and is only for compatibility with the AMM Dex data structure
            unitValue = (0, 0); // This field has no meaning and is only for compatibility with the AMM Dex data structure
            shareWeighted = { shareTimeWeighted=0; updateTime=0 }; // This field has no meaning and is only for compatibility with the AMM Dex data structure
        }
        ```

## Function `getQuotes`
``` motoko no-repl
func getQuotes(_ki : OrderBook.KInterval) : async [OrderBook.KBar]
```

Query the K chart of the market at the specified time interval (seconds).

## Function `orderExpirationDuration`
``` motoko no-repl
func orderExpirationDuration() : async Int
```

Query default order expiration duration (nanoseconds)

## Function `info`
``` motoko no-repl
func info() : async { name : Text; version : Text; decimals : Nat8; owner : Principal; paused : Bool; setting : DexSetting; token0 : TokenInfo; token1 : TokenInfo }
```

Query the basic information of the trading pair

## Function `stats`
``` motoko no-repl
func stats() : async { price : Float; change24h : Float; vol24h : Vol; totalVol : Vol }
```

Query current price，total volume and 24-hour statistics

Results:
- res: {  
    price: Float; // Converted prices (float). How much token1 (smallest units) are needed to purchase 1 token0 (smallest units).  
    totalVol: Vol; // Smallest units. Total volume.  
    change24h: Float; // 24-hour rate of price change.  
    vol24h: Vol; // Smallest units. 24-hour volume.  
}

## Function `tpsStats`
``` motoko no-repl
func tpsStats() : async (Nat, Float, Nat, Nat, Int, Int)
```

TPS pressure statistics

## Function `sysMode`
``` motoko no-repl
func sysMode() : async { mode : SysMode; openingTime : Time.Time }
```

System access mode, and time to be opened (0 means already opened)

## Function `brokerList`
``` motoko no-repl
func brokerList(_page : ?ListPage, _size : ?ListSize) : async TrieList<AccountId, { vol : Vol; commission : Vol; count : Nat; rate : Float }>
```

List of brokers

## Function `makerList`
``` motoko no-repl
func makerList(_page : ?ListPage, _size : ?ListSize) : async TrieList<AccountId, { vol : Vol; commission : Vol; orders : Nat; filledCount : Nat }>
```

List of vip-makers

## Function `getRole`
``` motoko no-repl
func getRole(_account : Address) : async { broker : Bool; vipMaker : Bool; proTrader : Bool }
```

Query a trader's roles

## Function `isAccountIctcDone`
``` motoko no-repl
func isAccountIctcDone(_a : AccountId) : async (Bool, [Toid])
```

Returns whether there are transactions in process for an account.

## Function `getPairAddress`
``` motoko no-repl
func getPairAddress() : async { pool : (ICRC1.Account, Address); fees : (ICRC1.Account, Address) }
```

Returns PoolAccount and FeeAccount

## Function `poolBalance`
``` motoko no-repl
func poolBalance() : async { token0 : Amount; token1 : Amount }
```

Returns the balance of PoolAccount

## Function `accountBalance`
``` motoko no-repl
func accountBalance(_a : Address) : async KeepingBalance
```

Returns the balance kept in PoolAccount by a trader. (The result of the query may not reflect the latest situation when the ICTC is being executed but has not yet been completed.)

## Function `safeAccountBalance`
``` motoko no-repl
func safeAccountBalance(_a : Address) : async { balance : KeepingBalance; pendingOrders : (Amount, Amount); price : STO.Price; unitSize : Nat }
```

Returns the balance kept in PoolAccount by a trader in a safe way. (An exception will be thrown when the ICTC is executing and has not yet completed. You should try the query again after a while)

## Function `accountSetting`
``` motoko no-repl
func accountSetting(_a : Address) : async AccountSetting
```

Returns a trader's account settings, including whether `PoolMode` is turned on, whether `KeepingBalanceInTraderAccount` is turned on, and so on.

## Function `getDepositAccount`
``` motoko no-repl
func getDepositAccount(_account : Address) : async (ICRC1.Account, Address)
```

In the PoolMode scenario, the trader wants to deposit the ICRC1 token into the TraderAccount, he needs to get the DepositAccount address first.
This is a query method, if called off-chain (e.g., web-side), You should generate the account address directly using the 
following rule: `{owner = pair_canister_id; subaccount = ?your_accountId }`.

## Function `accountConfig`
``` motoko no-repl
func accountConfig(_exMode : {#PoolMode; #TunnelMode}, _enKeepingBalance : Bool, _sa : ?Sa) : async ()
```

Trader configures `ExchangeMode` and `KeepingBalanceInTraderAccount`.  
Some roles require specific configurations
- Fee recipient: enKeepingBalance = true;
- Broker: enKeepingBalance = true;
- Vip-maker: exMode = #PoolMode, enKeepingBalance = true;
- Pro-trader: exMode = #PoolMode, enKeepingBalance = true;

Arguments:
- exMode: {#PoolMode; #TunnelMode}. Set ExchangeMode to #PoolMode or #TunnelMode, default is #TunnelMode.
- enKeepingBalance: Bool. Whether to turn on KeepingBalanceInTraderAccount.

## Function `deposit`
``` motoko no-repl
func deposit(_token : {#token0; #token1}, _value : Amount, _sa : ?Sa) : async ()
```

Trader deposits funds into TraderAccount (tokens are kept in the PoolAccount of the trading pair).

## Function `depositFallback`
``` motoko no-repl
func depositFallback(_sa : ?Sa) : async (value0 : Amount, value1 : Amount)
```

This method can be called by the trader to return funds exceptionally left in the DepositAccount when there are 
no deposits being processed.

## Function `withdraw`
``` motoko no-repl
func withdraw(_value0 : ?Amount, _value1 : ?Amount, _sa : ?Sa) : async (value0 : Amount, value1 : Amount)
```

Trader retrieves funds from TraderAccount (tokens are sent from PoolAccount to trader wallet).

## Function `withdraw2`
``` motoko no-repl
func withdraw2(_value0 : ?Amount, _value1 : ?Amount, _sa : ?Sa) : async (value0 : Amount, value1 : Amount, status : {#Completed; #Pending})
```

Similar to withdraw(), try to call it as synchronous as possible when called by a pro-trader, but still asynchronous when ICTC is busy.

## Function `checkPoolBalance`
``` motoko no-repl
func checkPoolBalance() : async (?Bool, { result : Bool; total : { token0 : Amount; token1 : Amount }; pool : { token0 : Amount; token1 : Amount } })
```

Checks for abnormal PoolAccount balances.

## Function `sto_cancelPendingOrders`
``` motoko no-repl
func sto_cancelPendingOrders(_soid : STO.Soid, _sa : ?Sa) : async ()
```

Cancel all orders in the order book for a strategy.

## Function `sto_createProOrder`
``` motoko no-repl
func sto_createProOrder(_arg : {#GridOrder : STO.GridOrderSetting; #IcebergOrder : STO.IcebergOrderSetting; #VWAP : STO.VWAPSetting; #TWAP : STO.TWAPSetting}, _sa : ?Sa) : async STO.Soid
```

Create a pro-order strategy, which includes GridOrder, IcebergOrder, VWAP, and TWAP.  

Notes (applicable to all strategy order related methods):
- Price: The price of strategy orders is Nat, indicating how much token1 (smallest units) are needed to purchase UNIT_SIZE token0 (smallest units).
- Ppm: parts per million. "1 ppm" means "1 / 1000000".
- Timestamp: Timestamp in seconds.
- #Arith: Arithmetic.
- #Geom: Geometric (ppm).
- ppmFactor: Default grid order amount factor, initialized when the strategy is created. `ppmFactor = 1000000 * 1/n * (n ** (1/10))`, 
    Where n is `(n1 + n2) / 2`, and n1, n2 is between 2 and 200. n1 is the number of grids between the latest price and the lowerLimit, 
    and n2 is the number of grids between the latest price and the upperLimit.

Arguments:
- arg: {  
   ```
   #GridOrder: { // Grid strategy  
       lowerLimit: Price; // Minimum Grid Price Limit  
       upperLimit: Price; // Maximum Grid Price Limit  
       spread: {#Arith: Price; #Geom: Ppm }; // Spread between two neighboring grids  
       amount: {#Token0: Nat; #Token1: Nat; #Percent: ?Ppm }; // Amount of order placed per grid. `#Percent: ?n` Indicates n/1000000 of the funds in the TraderAccount for each grid order, and if n is not specified it defaults to the value `ppmFactor`.  
   };  
   #IcebergOrder: { // Iceberg strategy  
       startingTime: Timestamp; // Strategy start time  
       endTime: Timestamp; // Strategy end time  
       order: {side: OB.OrderSide; price: Price; }; // When the strategy is triggered, place one #Buy/#Sell order at price `price` at a time.  
       amountPerTrigger: {#Token0: Nat; #Token1: Nat}; // The amount of the order placed at each trigger. The minimum value is setting.UNIT_SIZE * 10 smallest_units token0 (or equivalently token0).  
       totalLimit: {#Token0: Nat; #Token1: Nat}; // Maximum cumulative order amount.  
   };  
   #VWAP: { // VWAP strategy  
       startingTime: Timestamp; // Strategy start time  
       endTime: Timestamp; // Strategy end time  
       order: {side: OB.OrderSide; priceSpread: Price; priceLimit: Price; }; // When the strategy is triggered, place one #Buy/#Sell order at the latest price plus slippage (+/- priceSpread) at a time.  
       amountPerTrigger: {#Token0: Nat; #Token1: Nat}; // The amount of the order placed at each trigger. The minimum value is setting.UNIT_SIZE * 10 smallest_units token0 (or equivalently token0).  
       totalLimit: {#Token0: Nat; #Token1: Nat}; // Maximum cumulative order amount.  
       triggerVol: {#Arith: Nat; #Geom: Ppm }; // An order is triggered for each `vol` of change in volume. `vol` is the token1 volume of the trading pair, vol = n when triggerVol is #Arith(n), vol = 24hour_vol * ppm / 1000000 when triggerVol is #Geom(ppm).  
   };  
   #TWAP: { // TWAP strategy  
       startingTime: Timestamp; // Strategy start time  
       endTime: Timestamp; // Strategy end time  
       order: {side: OB.OrderSide; priceSpread: Price; priceLimit: Price; }; // When the strategy is triggered, place one #Buy/#Sell order at the latest price plus slippage (+/- priceSpread) at a time.  
       amountPerTrigger: {#Token0: Nat; #Token1: Nat}; // The amount of the order placed at each trigger. The minimum value is setting.UNIT_SIZE * 10 smallest_units token0 (or equivalently token0).  
       totalLimit: {#Token0: Nat; #Token1: Nat}; // Maximum cumulative order amount.  
       triggerInterval: Nat; // secondsInterval between order triggers.  
   };  
   ```
}
- sa: ?Sa. Optionally specify the subaccount of the caller

Returns:
- res: STO.Soid. Returns strategy order ID.


## Function `sto_updateProOrder`
``` motoko no-repl
func sto_updateProOrder(_soid : STO.Soid, _arg : {#GridOrder : { lowerLimit : ?STO.Price; upperLimit : ?STO.Price; spread : ?{#Arith : STO.Price; #Geom : STO.Ppm}; amount : ?{#Token0 : Nat; #Token1 : Nat; #Percent : ?STO.Ppm}; status : ?STO.STStatus }; #IcebergOrder : { setting : ?STO.IcebergOrderSetting; status : ?STO.STStatus }; #VWAP : { setting : ?STO.VWAPSetting; status : ?STO.STStatus }; #TWAP : { setting : ?STO.TWAPSetting; status : ?STO.STStatus }}, _sa : ?Sa) : async STO.Soid
```

Update a pro-order strategy, arguments similar to the above.

## Function `sto_createStopLossOrder`
``` motoko no-repl
func sto_createStopLossOrder(_arg : { triggerPrice : STO.Price; order : { side : OrderBook.OrderSide; quantity : Nat; price : STO.Price } }, _sa : ?Sa) : async STO.Soid
```

Create a stop-loss-order strategy.  

Arguments:
- arg: {  
   triggerPrice: STO.Price; // Set the trigger price. The triggerPrice must be greater than the current price if a #Buy order is scheduled to be placed, or less than the current price if a #Sell order is scheduled to be placed.   
   order: { side: OrderBook.OrderSide; quantity: Nat; price: STO.Price; }; // Parameters for placing an order when triggered. The minimum value of quantity is setting.UNIT_SIZE * 10.   
}
- sa: ?Sa. Optionally specify the subaccount of the caller

Returns:
- res: STO.Soid. Returns strategy order ID.


## Function `sto_updateStopLossOrder`
``` motoko no-repl
func sto_updateStopLossOrder(_soid : STO.Soid, _arg : { triggerPrice : ?STO.Price; order : ?{ side : OrderBook.OrderSide; quantity : Nat; price : STO.Price }; status : ?STO.STStatus }, _sa : ?Sa) : async STO.Soid
```

Update a stop-loss-order strategy, arguments similar to the above.

## Function `sto_getStratOrder`
``` motoko no-repl
func sto_getStratOrder(_soid : STO.Soid) : async ?STO.STOrder
```

Returns strategy order information and status

## Function `sto_getStratOrderByTxid`
``` motoko no-repl
func sto_getStratOrderByTxid(_txid : Txid) : async ?STO.STOrder
```

Queries the strategy order based on the txid of the trade order, and returns null if the txid does not belong to 
the trade triggered by the strategy.

## Function `sto_getAccountProOrders`
``` motoko no-repl
func sto_getAccountProOrders(_a : Address) : async [STO.STOrder]
```

Returns a trader's strategy pro-orders

## Function `sto_getAccountStopLossOrders`
``` motoko no-repl
func sto_getAccountStopLossOrders(_a : Address) : async [STO.STOrder]
```

Returns a trader's strategy stop-loss-orders

## Function `sto_getConfig`
``` motoko no-repl
func sto_getConfig() : async STO.Setting
```

Returns the global configuration of the strategy platform for the trading pair.

## Function `sto_getActiveProOrders`
``` motoko no-repl
func sto_getActiveProOrders(_page : ?ListPage, _size : ?ListSize) : async TrieList<STO.Soid, STO.STOrder>
```

Returns all active pro-orders, dedicated to Owner (DAO) debugging.

## Function `sto_getActiveStopLossOrders`
``` motoko no-repl
func sto_getActiveStopLossOrders(_side : {#Buy; #Sell}, _page : ?ListPage, _size : ?ListSize) : async TrieList<STO.Soid, STO.STOrder>
```

Returns all active stop-loss-orders, dedicated to Owner (DAO) debugging.

## Function `sto_getStratTxids`
``` motoko no-repl
func sto_getStratTxids(_page : ?ListPage, _size : ?ListSize) : async TrieList<Txid, STO.Soid>
```

Returns all soid to txid relationships, dedicated to Owner (DAO) debugging.

## Function `IDO_config`
``` motoko no-repl
func IDO_config(_setting : IDOSetting) : async ()
```

Funder configures IDO

## Function `IDO_getConfig`
``` motoko no-repl
func IDO_getConfig() : async (funder : ?Principal, setting : IDOSetting, requirement : ?IDORequirement)
```

Returns IDO configuration

## Function `IDO_setWhitelist`
``` motoko no-repl
func IDO_setWhitelist(limits : [(Address, Amount)]) : async ()
```

Funder sets up whitelisting

## Function `IDO_removeWhitelist`
``` motoko no-repl
func IDO_removeWhitelist(users : [Address]) : async ()
```

Funder removes whitelisted members

## Function `IDO_updateQualification`
``` motoko no-repl
func IDO_updateQualification(_sa : ?Sa) : async ?Participant
```

Participant update his qualification status ( fetch cumulative volume from specified trading pairs).

## Function `IDO_qualification`
``` motoko no-repl
func IDO_qualification(_a : ?Address) : async [(Address, Participant)]
```

Returns an account's participation qualification status. If account `_a` is not specified, all qualified accounts are returned.

## Function `sync`
``` motoko no-repl
func sync() : async ()
```

Synchronizing token0 and token1 transfer fees

## Function `getConfig`
``` motoko no-repl
func getConfig() : async DexSetting
```

Returns the basic configuration of the pair.

## Function `config`
``` motoko no-repl
func config(_config : DexConfig) : async Bool
```

Set basic configuration of trading pair.

## Function `setPause`
``` motoko no-repl
func setPause(_pause : Bool, _openingTime : ?Time.Time) : async Bool
```

Suspend (true) or open (false) trading pair. If `_openingTime` is specified, it means that the pair will be opened automatically after that time.

## Function `setVipMaker`
``` motoko no-repl
func setVipMaker(_account : Address, _rate : Nat) : async ()
```

Set up vip-maker qualification and configure rebate rate.

## Function `removeVipMaker`
``` motoko no-repl
func removeVipMaker(_account : Address) : async ()
```

Removes vip-maker qualification

## Function `setOrderFail`
``` motoko no-repl
func setOrderFail(_txid : Text, _unlock0 : Amount, _unlock1 : Amount) : async Bool
```

Sets an order with #Todo status as an error order

## Function `mergePair`
``` motoko no-repl
func mergePair(_pair : Principal) : async Bool
```

Migrate total volume and K-chart data from old trading pair. It can only be migrated once.

## Function `sto_config`
``` motoko no-repl
func sto_config(_config : { poFee1 : ?Nat; poFee2 : ?Float; sloFee1 : ?Nat; sloFee2 : ?Float; gridMaxPerSide : ?Nat; proCountMax : ?Nat; stopLossCountMax : ?Nat }) : async ()
```

Configuring strategy order parameters.

## Function `IDO_setFunder`
``` motoko no-repl
func IDO_setFunder(_funder : ?Principal, _requirement : ?IDORequirement) : async ()
```

Open IDO and configure parameters

## Function `ta_setDescription`
``` motoko no-repl
func ta_setDescription(_desc : Text) : async ()
```

Submit a text description of the Trading Ambassadors (referral) system

## Function `sto_enableStratOrder`
``` motoko no-repl
func sto_enableStratOrder(_arg : {#Enable; #Disable}) : async ()
```

Enable strategy orders

## Function `sto_clearTxidLog`
``` motoko no-repl
func sto_clearTxidLog() : async ()
```

Clear the relationship table between strategy order soid and trade order txid.

## Function `clearAccountSetting`
``` motoko no-repl
func clearAccountSetting() : async ()
```

Clear account settings with no activity.

## Function `clearNonCoreData`
``` motoko no-repl
func clearNonCoreData() : async ()
```

Clear non-core data (volume statistics and referral statistics).

## Function `debug_gridOrders`
``` motoko no-repl
func debug_gridOrders() : async [(STO.Soid, STO.ICRC1Account, OrderPrice)]
```

debug: Returns the current grid-orders

## Function `setAuctionMode`
``` motoko no-repl
func setAuctionMode(_enable : Bool, _funder : ?AccountId) : async (Bool, AccountId)
```

Enable/disable Auction Mode

## Function `getAuctionMode`
``` motoko no-repl
func getAuctionMode() : async (Bool, AccountId)
```

Returns whether auction mode is enabled and its funder

## Function `ta_setReferrer`
``` motoko no-repl
func ta_setReferrer(_ambassador : Address, _entity : ?Text, _sa : ?Sa) : async Bool
```

A trader sets up his referrer, which can only be validly set up once.

## Function `ta_getReferrer`
``` motoko no-repl
func ta_getReferrer(_account : Address) : async ?(Address, Bool)
```

Returns a trader's referrer

## Function `ta_ambassador`
``` motoko no-repl
func ta_ambassador(_ambassador : Address) : async (quality : Bool, entity : Text, referred : Nat, vol : Vol)
```

Returns data of an ambassador.

## Function `ta_stats`
``` motoko no-repl
func ta_stats(_entity : ?Text) : async (ambassadors : Nat, referred : Nat, vol : Vol)
```

Returns summary data of referral based on entity.

## Function `ta_description`
``` motoko no-repl
func ta_description() : async Text
```

Returns trading ambassadors description

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

## Function `drc205_getConfig`
``` motoko no-repl
func drc205_getConfig() : async DRC205.Setting
```

Returns the configuration of DRC205

## Function `drc205_canisterId`
``` motoko no-repl
func drc205_canisterId() : async Principal
```

Returns the canister-id of the DRC205

## Function `drc205_dexInfo`
``` motoko no-repl
func drc205_dexInfo() : async DRC205.DexInfo
```

Returns trading pair information

## Function `drc205_config`
``` motoko no-repl
func drc205_config(config : DRC205.Config) : async Bool
```

Configure DRC205.

## Function `drc205_events`
``` motoko no-repl
func drc205_events(_account : ?DRC205.Address) : async [DRC205.TxnRecord]
```

returns latest events

## Function `drc205_events_filter`
``` motoko no-repl
func drc205_events_filter(_account : ?DRC205.Address, _startTime : ?Time.Time, _endTime : ?Time.Time) : async (data : [DRC205.TxnRecord], mayHaveArchived : Bool)
```

returns events filtered by time

## Function `drc205_txn`
``` motoko no-repl
func drc205_txn(_txid : DRC205.Txid) : async (txn : ?DRC205.TxnRecord)
```

Returns a txn record. This is a query method that looks for record from this canister cache.

## Function `drc205_txn2`
``` motoko no-repl
func drc205_txn2(_txid : DRC205.Txid) : async (txn : ?DRC205.TxnRecord)
```

Returns a txn record. It's an update method that will try to find txn record in the DRC205 canister if it does not exist in this canister.

## Function `drc205_pool`
``` motoko no-repl
func drc205_pool() : async [(Txid, DRC205.TxnRecord, Nat)]
```

Check the data to be stored by DRC205.

## Function `drc207`
``` motoko no-repl
func drc207() : async DRC207.DRC207Support
```

Returns the monitorability configuration of the canister.

## Function `wallet_receive`
``` motoko no-repl
func wallet_receive() : async ()
```

Receive cycles

## Function `withdraw_cycles`
``` motoko no-repl
func withdraw_cycles(_amount : Nat) : async ()
```

Withdraw cycles

## Function `setUpgradeMode`
``` motoko no-repl
func setUpgradeMode(_mode : {#Base; #All}) : async ()
```

When the data is too large to be backed up, you can set the UpgradeMode to #Base

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
