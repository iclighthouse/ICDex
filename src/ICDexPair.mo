/**
 * Actor      : ICDexPair
 * Author     : ICLighthouse Team
 * Stability  : Experimental
 * Github     : https://github.com/iclighthouse/ICDex/
 */
///
/// ## Overview
///
/// ICDexPair is a trading pair contract where each trading pair is deployed into a separate canister.
///
/// ICDexPair is created by the ICDexRouter, its controller is by default the ICDexRouter and can be modified.
///
/// ## 1 Concepts
///
/// ### Order Book and Matching Engine
/// 
/// https://github.com/iclighthouse/ICDex/blob/main/OrderBook.md 
///
/// ### Accounts and Roles
///
/// The traders are identified by `AccountId` in the pair, and support subaccounts. An account has one or more of the following identities:
/// - Trader (User): Ordinary trader, no authorization required.
///     - Maker: A trader who submits an order into the order book to increase liquidity when trading, is the `Maker` of the order, 
///     and has a default trading fee of 0.
///     - Taker: A trader who submits an order that immediately matches other orders in the order book and thus takes away liquidity, 
///     is the `Taker` of the order and has to pay a trading fee.
/// - Vip-Maker: The Owner (ICDexRouter) grants the role of `Vip-Maker` to a trader and specifies a rebate percentage, so that when he 
/// is on the `Maker` side of an order, he will receive a rebate on the trading fee.
/// - Trading Ambassador (Referrer): A trader with a volume greater than 0 becomes a Trading Ambassador (Referrer) without authorization.
/// He can refer new users to the trading pair which will count the number of users referred by him and the total volume of their trades.
/// - Broker: Other Dapps can integrate with ICDex as a `Broker`, specifying the broker parameter when calling the trading interface, 
/// in order to get the fee income, which is paid by Taker. No authorization is required for Broker role.
/// - Pro-Trader: A Trader who trades using the Strategy Order feature, called `Pro-Trader`, requires no authorization.
///
/// Dedicated accounts in trading pair:
/// - TxAccount: An account dedicated to an order in tunnel mode, is used to temporarily hold funds for the order. It is in a locked state 
/// and funds are not sent from that account to the recipient until that order is filled or canceled.  Each order has a separate 
/// account from each other with the address `{ owner = pair_canister_id; subaccount = ?txid }`. Funds left in TxAccount due to 
/// an exception can be retrieved by the fallback operation.
/// - PoolAccount: A pool account for trading pairs that is used to centrally hold temporary funds for all orders, the ownership 
/// and status of which is handled by TraderAccount ledger records. e.g. `{ owner = pair_canister_id; subaccount = null }`. 
/// - TraderAccount: The local ledger in a trading pair is used to keep track of the balances that traders keep in PoolAccount. 
/// TraderAccount balance is divided into locked and available, and traders can increase or decrease the available balance by 
/// depositing and withdrawing funds. TraderAccount does not hold the tokens directly, its balance is queried through the 
/// accountBalance() and safeAccountBalance() methods of the trading pair.
/// - DepositAccount: A temporary account for traders to deposit funds into the available balance of TraderAccount. Each trader has 
/// a separate DepositAccount with the address `{ owner = pair_canister_id; subaccount = ?accountId }`. Funds left in DepositAccount 
/// due to an exception can be retrieved by the fallback operation.
///
/// ### Exchange Mode
///
/// While a trader places an order, the funds will be custodied in the trading pair canister, depending on the custody method. 
/// Exchange Mode is categorized:
/// - TunnelMode: While a trader submits an order, the funds are deposited into an order-specific account (`TxAccount`, 
/// Txn Tunnel Account). When the order is filled, the funds are transferred from the order-specific account to the target trader's 
/// account. Each order has a separate and unique Tunnel (i.e. `{ owner = pair_canister_id; subaccount = ?txid }`).
/// - PoolMode: While a trader submits an order, the funds are deposited into the `Pool Account of the pair` (`PoolAccount`). 
/// When the order is filled, the funds are transferred from the Pool to the target trader's account. The PoolAccount 
/// (i.e. `{ owner = pair_canister_id; subaccount = null }`) is a fixed account.
///
/// ### Keeping Funds in TraderAccount
///
/// If a trader has "Keeping balance in TraderAccount" enabled, then when he trades, the funds in that TraderAccount will be used by default., 
/// and the received tokens will be deposited into this TraderAccount by default. All the assets in the trader's TraderAccount are kept in 
/// PoolAccount, and the trader can deposit funds into his TraderAccount or withdraw funds from his TraderAccount.
///
/// ### Base Token (token0) and Quote Token (token1)
///
/// A trading pair is the quotation of two different cryptocurrencies, with the value of one token (cryptocurrency) being quoted 
/// against the other. The first listed token (named token0) of a trading pair is called the base token, and the second token 
/// (named token1) is called the quote token. 
///
/// Inside the trading pair, the balances of token0 and token1 are represented as integers whose values refer to the SMALLEST unit token. 
/// The human-readable representation of the balance is converted in the UI by the front-end code.
///
/// ### DebitToken and CreditToken
///
/// When adding token0 to purchase token1, we call token0 a DebitToken and token1 a CreditToken. Similarly, when adding token1 to buy token0, 
/// we call token0 a CreditToken and token1 a DebitToken.
///
/// ### UNIT_SIZE and Price
///
/// - UNIT_SIZE: It is the base number of quotes in the trading pair and the minimum quantity to be used when placing an order. The quantity of 
/// the order placed must be an integer multiple of UNIT_SIZE.
/// - Price: How much token1 (smallest units) are needed to purchase UNIT_SIZE token0 (smallest units).
/// - Human-readable price: `Price * (10 ** token0Decimals) / (10 ** token1Decimals) / UNIT_SIZE`
///
/// ### Nonce
///
/// The ICDex trading function uses the nonce mechanism, where each account has a nonce value in a trading pair, which by default is 0. 
/// When the trader creates a new order, his current nonce value will be bound to the order, and then `nonce + 1` as the next available value.
/// The trader can create an order without filling in the nonce, the system will automatically take the value and increment it. If a trader 
/// specifies a nonce value when creating an order, the value must be a currently available value for the account in the pair, it cannot be 
/// a used value, nor can it be an excessively large value, otherwise an error will be reported.
///
/// ### Strategy Order
///
/// Strategy Orders are also known as Algorithmic Orders. The trader configures the parameters according to the strategy rules of the trading 
/// pair, and when the market price meets the conditions, the trading pair will automatically place orders for the trader. Strategy Order is 
/// divided into Pro-Order and Stop-Loss-Order.
/// - Pro-Order: Grid, Iceberg, VWAP and TWAP orders have been implemented.
/// - Stop-Loss-Order: Stop-loss conditional orders have been implemented.
/// Clearly indicate:  
/// A `Strategy order` is a strategy rule configuration that does not place a trade order into the order book until it is triggered. 
/// A `Trade order` is a real order in the order book and is what is normally referred to as a `Trade`.
///
/// Finance reference: (Note: There are some differences in the implementation details of ICDex)
/// - Stop-loss Order: https://corporatefinanceinstitute.com/resources/career-map/sell-side/capital-markets/stop-loss-order/
/// - Grid Order: https://www.binance.com/en/support/faq/what-is-spot-grid-trading-and-how-does-it-work-d5f441e8ab544a5b98241e00efb3a4ab
/// - Iceberg Order: https://corporatefinanceinstitute.com/resources/career-map/sell-side/capital-markets/iceberg-order/
/// - VWAP Order: https://en.wikipedia.org/wiki/Volume-weighted_average_price
/// - TWAP Order: https://en.wikipedia.org/wiki/Time-weighted_average_price
///
/// ### IDO
///
/// IDO is a decentralized sale on Dex. ICDex trading pairs can have the IDO functionality activated by the Owner (DAO) and an IDO Funder 
/// set up before opening of trading. The IDO configuration is done by the IDO Funder and orders are placed according to the configuration 
/// and then the IDO is opened.
///
/// ## 2 Fee model
///
/// The fee rules for trading pair are calculated based on the status of an order and the matching of the order, and a post-fee model is 
/// used for filling the order, i.e., the fee is charged based on the token (token0 or token1) amount multiplied by the commission rate that 
/// the trader's account that is being charged has received in the order.  
/// The fees collected by ICDex, after deducting Vip-maker incentives, network gas, etc., are reserved in the ICDexRouter account, and there 
/// is a DAO who decides on their use, e.g., destruction, repurchase, etc.  
/// - Maker-fee: When an order is filled, the maker pays a commission rate which is currently 0% by default, a negative value means that the 
/// maker receives a commission.
/// - Taker-fee: When an order is filled, taker pays a fee based on the amount of the filled order, and its rate is currently 0.5% by default.
/// - Vip-maker rebate: When an order is filled, if the maker's role is as a Vip-maker, then he can get a specified percentage of the commission 
/// paid by the taker as a reward, which may vary from Vip-maker to Vip-maker.
/// - Cancelling-fee: An order canceled within 1 hour of placing it will be charged a fee (Taker_fee * 20%) if nothing is filled. 
/// No cancellation fee is paid for strategic orders.
/// - Strategic order
///     - Pro-Order: When configuring a strategy, a fixed amount of ICL is charged as a fee (poFee1), this fee is free for vip-makers; when triggering new trade and filling 
///     it, charge the amount of token (token0 or token1) received by the pro-trader `token_amount * fee_ratio` (poFee2) is charged as the 
///     pro-trading fee.
///     - StopLoss-Order: When configuring a strategy, a fixed amount of ICL is charged as a fee (sloFee1); when triggering new trade and 
///     filling it, charge the amount of token (token0 or token1) received by the pro-trader `token_amount * fee_ratio` (sloFee2) is charged 
///     as the pro-trading fee.
///
/// ## 3 Core functionality
/// 
/// ### Order Book and Matching Engine
///
/// The basic function of the Order Book is to match buyers and sellers in the market. The order book is the mechanism used by the majority 
/// of electronic exchanges today, both in the financial and the cryptocurrency markets.
/// More instructions are available at https://github.com/iclighthouse/ICDex/blob/main/OrderBook.md
///
/// ### TunnelMode Trade
///
/// By default, traders trade in Tunnel Mode, where the funds for each order are stored in a dedicated address (TxAccount), and different 
/// orders are segregated from each other, as if each order had a tunnel.  
/// Trading process in tunnel mode:
/// - Step1  
/// Call getTxAccount() to get the TxAccount, nonce and txid of the new order. This is a query method, if called off-chain (e.g., web-side) 
/// you need to use the generateTxid() method of DRC205 to generate a txid and TxAccount.
/// - Step2  
/// Deposit to TxAccount the funds needed for the order.
///     - DebitToken is DRC20/ICRC2 token: not needed to transfer funds to TxAccount, but need to approve sufficient amount (value + 
///     token_fee) PoolAccount could spend.
///     - DebitToken is ICRC1 token: need to call icrc1_transfer to transfer the required funds (value) to TxAccount.
/// - Step3  
/// Calls the trade(), trade_b(), tradeMKT(), or tradeMKT_b() methods to submit a trade order. When submitting an order nonce can be filled 
/// with null, if a specific value is filled it must be the currently available nonce value, otherwise an exception is thrown. The advantage 
/// of providing a nonce value for a trade is that the txid can be calculated in advance from the nonce value.
///
/// ### PoolMode Trade
/// The trader is required to call the accountConfig() method to enable PoolMode. Funds for PoolMode orders are kept in PoolAccount and 
/// are recorded in the trader's TraderAccounts and are in the locked state. The funds are sent to the recipients when the order is matched 
/// or canceled.    
/// Notes:   
/// In PoolMode, it is compatible with TunnelMode's trading process, the difference is that the approving amount in Step2 should be 
/// added with an additional token_fee (approve: (value + token_fee * 2) or transfer: (value + token_fee)).   
/// The following is the trading process of TunnelMode:   
/// If the available balance in the trader's TraderAccount is sufficient, the operation starts from Step4. Otherwise the operation starts 
/// from Step1. 
/// - Step1
/// Call getDepositAccount() to get the DepositAccount. This is a query method, if called off-chain (e.g., web-side),  
/// You should generate the account address directly using the following rule: `{owner = pair_canister_id; subaccount = ?your_accountId }`.
/// - Step2  
/// Deposit funds to DepositAccount.
///     - DebitToken is DRC20/ICRC2 token: not needed to transfer funds to DepositAccount, but need to approve sufficient amount (value + 
///     token_fee * 2) PoolAccount could spend.
///     - DebitToken is ICRC1 token: need to call icrc1_transfer to transfer the required funds (value + token_fee) to DepositAccount.
/// - Step3  
/// Calling deposit() completes the deposit operation, the funds are deposited into PoolAccount, and TraderAccount increases the available 
/// balance.
/// - Step4  
/// Calls the trade(), trade_b(), tradeMKT(), or tradeMKT_b() methods to submit a trade order. When submitting an order nonce can be filled 
/// with null, if a specific value is filled it must be the currently available nonce value, otherwise an exception is thrown. The advantage 
/// of providing a nonce value for a trade is that the txid can be calculated in advance from the nonce value.  
/// - Step5  
/// If the trader has not enabled "Keeping balance in TraderAccount", the funds in TraderAccount will be automatically withdrawn to the 
/// trader's wallet. If he has enabled this option, he needs to call withdraw() method to complete the withdrawal operation. Withdrawal is 
/// sending funds from PoolAccount to Trader's Wallet while decreasing the available balance in his TraderAccount.
///
/// ### Strategy Order
///
/// The Strategy Order function is a strategy manager for pro-traders. Strategy Order includes pro-order and stop-loss-order.  
/// The strategy order lifecycle is divided into two segments: 
/// 1) Configure a strategy: Pro-trader selects a strategy type, configures the strategy parameters and starts a strategy.
/// 2) Trigger Order: When the latest price of the trading pair changes and meets the conditions of the strategy order, the Strategy Manager 
/// (Worktop) will automatically trigger the order.  
/// Notes:
/// - Ordinary orders may trigger a strategy to place an order when they are filled, while strategy orders will not trigger a strategy to 
/// place an order again.
/// - The triggers of the strategy do not guarantee that the order will be placed successfully or that it will be filled immediately, and 
/// there may be multiple uncertainties.
/// - When it is busy, the trigger price may have a deviation of about 0.5%, and the system will ignore multiple triggers within 10 seconds 
/// and trigger only once.
///
/// Strategy orders use the hook mechanism. When an order is submitted, it executes the strategy worktop function _hook_stoWorktop(). 
/// When an order is filled with matches, it executes _hook_fill(). When an order is fully filled, it executes _hook_close(). When an 
/// order is canceled, it executes _hook_cancel().
///
/// ### IDO
///
/// IDO (Initial DEX Offering), is a mechanism for tokens to be sold to traders or specific parties at the beginning of the token's 
/// listing on ICDex, which is authorized by owner (DAO) and configured by the Funder of the base token. Note that only trading pairs 
/// created through owner (DAO) can initiate IDO.
/// - Configure: 
///     - Open IDO: Owner (DAO) calls IDO_setFunder() method of the trading pair to open IDO, set the participation threshold, specify 
///     Funder, and set the opening time of the trading pair.
///     - Funder Configuration: Funder calls the IDO_config() method for configuration, and the configuration items include IDO time, 
///     whitelist, tiered supply rules, and participation limits.
/// - Tiered supply rules:
///     - Funder sets the total supply of tokens to be used for IDO and sets a tiered supply of one or more price levels, with the lowest 
///     priced supply being prioritized for purchase, and users getting first come, first served within the purchase limit.
/// - IDO Timeline: Funder configures IDO's IDOpeningTime and IDOClosingTime. IDOOpeningTime is also the time when the trading pair opens, 
/// and IDOClosingTime is also the time when the trading pair officially opens for trading.
///     - Funder can modify the IDO configuration up to 24 hours before the IDOOpeningTime and in case the trading pair does not have any orders;
///     - Prior to IDOOpeningTime, Funder can place orders (LMT type, Sell side, order price and quantity must be exactly a tiered price 
///     and supply) according to the IDO configured tiered supply data, and can set up whitelisting and participation limits;
///     - During IDOpeningTime ~ IDOClosingTime, the user (purchaser) can buy tokens (FOK type, Buy side, the order quantity must be 
///     within the participation limit);
///     - After IDOClosingTime, Funder's orders that are not fully filled will be canceled and the trading pair will be opened for normal trading.
/// - Participation Limits: 
///     - Whitelist mode: if Funder has enabled whitelist mode, only users in the whitelist are eligible to purchase the number of tokens 
///     within the whitelist quota.
///     - Non-whitelist mode: Funder does not enable whitelist, any eligible account can participate in IDO:
///         - Qualification for participation: 1) If ICDexRouter does not configure the participation threshold (threshold=0) when it enabled IDO, 
///         it means that all users are eligible to participate in IDO. 2) If ICDexRouter configures the participation threshold (threshold>0) 
///         when it enabled IDO, the user's volume of a specified pairs of trading converted to USD value exceeds the threshold, he is eligible 
///         to participate in IDO. If the value does not exceed threshold, Funder can directly set the whitelist quota for the user, then he 
///         is also eligible to participate in IDO.
///         - Participation limit: A user who is eligible to participate in IDO can purchase a number of tokens within the default limit (if 
///         the user has been assigned a whitelisted quota, then the whitelisted quota shall prevail).
/// - How users (purchasers) participate: 
///     - Step1: (Optional) Call IDO_updateQualification() to confirm qualification and quota. It must be called if the IDO is configured with 
///     a participation threshold (threshold>0). Qualification and quota can be queried via IDO_qualification().
///     - Step2: Call the trade() method of the trading pair as a FOK order to complete the purchase during IDO opening time.
///
/// ### Trading Ambassador (Referrer)
///
/// Each trading pair has a referrer system, where any user with a trading volume greater than 0 can become a referrer, also known as a 
/// Trading Ambassador. The referrer can get the referral link on ICDex UI and send it to the receiver, and the receiver will call ta_setReferrer() 
/// when he enters the trading pair for the first time through the link, and the trading pair will record the referral relationship and count 
/// the trading volume.
///
/// Referral rewards: The trading pair only counts the referral relationship and trading volume, there is no mechanism for direct rewards. 
/// Referral rewards need to be organized by DEX platform side or token project side, and the referral statistics of the trading pair can 
/// provide reference for them to distribute rewards.
///
/// ### ICTC
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
/// ### DRC205
///
/// ICDex uses DRC205 (https://github.com/iclighthouse/DRC_standards/tree/main/DRC205) for externally scalable storage of DEX transaction records 
/// so that it is possible to blockchain browser https://ic.house/swaps to to view transaction records. ICDex introduces the DRC205 module 
/// (https://github.com/iclighthouse/icl-vessel/blob/main/src/DRC205.mo) into the trading pair, which saves the transaction records to DRC205 
/// bucket while caching the recent records in the trading pair canister. The DRC205 is only responsible for record storage and does not affect 
/// the security of the assets of the trading pair.
///
/// ### Preventing DOS Attacks
///
/// The reverse-gas model of IC can easily invite DOS attacks, which are damaging to Defi applications. Our strategy is to maximize the 
/// cost of the attack, limit anomalous accesses, and make controls on several aspects such as access interval, TPS, number of asynchronous 
/// messages, total number of orders, global locks, and so on. If the number of ICTC exceptions is too large, or the trading pair PoolAccount 
/// balance is abnormal, the trading pair will be automatically suspended.
///
/// ## 4 Deployment
/// 
/// Initialize parameters
/// ```
/// type InitArgs = {
///     name: Text; // Name of the trading pair, e.g. "icdex:XYZ/ICP".
///     token0: Principal; // The base token canister-id.
///     token1: Principal; // The quote token canister-id.
///     unitSize: Nat64; // See section "UNIT_SIZE and Price".
///     owner: ?Principal; // Deprecated. Instead use Principal.isController()
/// }
/// ```
///
/// - Approach 1  
/// The Owner (DAO) calls the create() method of the ICDexRouter to create a trading pair, which is in a suspended state. You can configure 
/// the official opening time, whether to start IDO, etc.
///
/// - Approach 2  
/// The user calls the ICDexRouter's pubCreate() method to create a trading pair, and pays a specified number of ICL tokens as a fee, and 
/// the created pair is in a tradable state.
/// 
/// Notes:
/// - Trading pairs have a dependency on their own canister-id, so it is not possible to migrate the data to another canister. you may need 
/// to redeploy a trading pair and call the mergePair() method to migrate the data such as total volume and k-line charts, etc. 
/// - Trading pair transaction records are stored via DRC205 and cannot be deleted. To prevent duplication of account trading records, do not 
/// execute reinstall on pair canister.
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

import Array "mo:base/Array";
import Binary "mo:icl/Binary";
import Blob "mo:base/Blob";
import Cycles "mo:base/ExperimentalCycles";
// import DIP20 "mo:icl/DIP20";
import DRC20 "mo:icl/DRC20";
import DRC205 "mo:icl/DRC205";
import DRC207 "mo:icl/DRC207";
import Deque "mo:base/Deque";
import Error "mo:base/Error";
import Float "mo:base/Float";
import Hash "mo:base/Hash";
import Hex "mo:icl/Hex";
import ICRC1 "mo:icl/ICRC1";
import ICRC2 "mo:icl/ICRC1";
import Int "mo:base/Int";
import Int64 "mo:base/Int64";
// import Ledger "mo:icl/Ledger";
import List "mo:base/List";
import Nat "mo:base/Nat";
import Nat32 "mo:base/Nat32";
import Nat64 "mo:base/Nat64";
import Option "mo:base/Option";
import OrderBook "mo:icl/OrderBook";
import Principal "mo:base/Principal";
import Result "mo:base/Result";
import SagaTM "./ICTC/SagaTM";
import Text "mo:base/Text";
import Time "mo:base/Time";
import Tools "mo:icl/Tools";
import Trie "mo:base/Trie";
// import Trie "./lib/Elastic-Trie";
import Types "mo:icl/ICDexTypes";
import Iter "mo:base/Iter";
import Backup "./lib/ICDexBackupTypes";
import Timer "mo:base/Timer";
import STO "./lib/StrategyOrder";

// record { token0=principal ""; token1=principal "ryjl3-tyaaa-aaaaa-aaaba-cai"; owner=null; name="TTT/ICP"; unitSize=10_000_000:nat64;} 
shared(installMsg) actor class ICDexPair(initArgs: Types.InitArgs, isDebug: Bool) = this {
    // Types
    type AccountId = Types.AccountId;
    type Address = Types.Address;
    type Txid = Types.Txid;
    type TxAccount = Text;
    type Sa = Types.Sa;
    type Nonce = Types.Nonce;
    type Data = Types.Data;
    type Toid = Nat;
    type Ttid = Nat;
    type Amount = Types.Amount;
    type Timestamp = Types.Timestamp;
    type PeriodNs = Types.PeriodNs; 
    type IcpE8s = Types.IcpE8s;
    type AccountSetting = Types.AccountSetting;
    type KeepingBalance = Types.KeepingBalance;
    type BalanceChange = Types.BalanceChange;
    type TokenInfo = Types.TokenInfo;
    type DebitToken = Types.DebitToken;
    type OrderSide = Types.OrderSide;
    type OrderType = Types.OrderType;
    type OrderPrice = Types.OrderPrice;
    type PriceResponse = OrderBook.PriceResponse;
    type KBar = OrderBook.KBar;
    type KLines = OrderBook.KLines;
    type TradingStatus = Types.TradingStatus;
    type OrderFilled = Types.OrderFilled;
    type TradingOrder = Types.TradingOrder;
    //type TradingOrderResponse = Types.TradingOrderResponse;
    type PriceWeighted = Types.PriceWeighted;
    type Vol = Types.Vol;
    type OrderStatusResponse = Types.OrderStatusResponse;
    type TradingResult = Types.TradingResult;
    type DexSetting = Types.DexSetting;
    type DexConfig = Types.DexConfig;
    type TrieList<K, V> = Types.TrieList<K, V>;
    type ListPage = Types.ListPage;
    type ListSize = Types.ListSize;
    type SysMode = {#GeneralTrading; #ClosingOnly; #DisabledTrading; #ReadOnly};
    type ETHAddress = Text;

    // Variables
    private var icdex_debug : Bool = isDebug; /*config*/
    private let version_: Text = "0.12.19";
    private let ns_: Nat = 1_000_000_000;
    private let icdexRouter: Principal = installMsg.caller; // icdex_router
    private stable var ExpirationDuration : Int = 3 * 30 * 24 * 3600 * ns_;
    private stable var name_: Text = initArgs.name;
    private stable var pause: Bool = false;
    private stable var mode: SysMode = #GeneralTrading; // Currently only #GeneralTrading and #DisabledTrading are used.
    private stable var pairOpeningTime: Time.Time = 0;
    // private stable var owner: Principal = Option.get(initArgs.owner, installMsg.caller);
    private stable var token0_: Principal = initArgs.token0;
    private stable var token0Symbol: Text = "";
    private stable var token0Std: Types.TokenStd = #drc20;
    private stable var token0Gas: ?Nat = null;
    private stable var token1_: Principal = initArgs.token1;
    private stable var token1Symbol: Text = "";
    private stable var token1Std: Types.TokenStd = #icrc1;
    private stable var token1Gas: ?Nat = null;
    private stable var setting: DexSetting = {
            UNIT_SIZE = Nat64.toNat(initArgs.unitSize); // e.g. 1_000_000 token smallest units
            ICP_FEE = 10_000; // 10_000 E8s
            TRADING_FEE = 5_000; // value 5000 means 0.5%
            MAKER_BONUS_RATE = 0; // value 25 means 25%   BONUS = MAKER_BONUS_RATE * fee
            MAX_TPS = 6; 
            MAX_PENDINGS = 20;
            STORAGE_INTERVAL = 10; // seconds
            ICTC_RUN_INTERVAL = 10; // seconds
        };
    private stable var icdex_index: Nat = 0; // trade order Index Value
    private stable var icdex_totalFee: Types.FeeBalance = { value0=0; value1=0;};
    private stable var icdex_totalVol: Vol = { value0 = 0; value1 = 0;};
    private stable var icdex_orders : Trie.Trie<Txid, TradingOrder> = Trie.empty(); // Uncompleted orders. Completed orders will be removed from this variable.
    private stable var icdex_failedOrders: Trie.Trie<Txid, TradingOrder> = Trie.empty(); // Temporarily store failed orders, moved from icdex_orders.
    private stable var icdex_orderBook: OrderBook.OrderBook = OrderBook.create(); // Order book
    private stable var icdex_klines2: OrderBook.KLines = OrderBook.createK(); // Charts, K-line datasets
    private stable var icdex_lastPrice: OrderBook.OrderPrice = { quantity = #Sell(0); price = 0 }; // Latest filled price
    private stable var icdex_latestfilled = Deque.empty<(Timestamp, Txid, OrderFilled, OrderSide)>(); // Latest 50 filled price records
    private stable var icdex_priceWeighted: PriceWeighted = { token0TimeWeighted = 0; token1TimeWeighted = 0; updateTime = 0; }; // Current time-weighted price
    private stable var icdex_vols: Trie.Trie<AccountId, Vol> = Trie.empty(); // Cumulative volume of traders
    private stable var icdex_nonces: Trie.Trie<AccountId, Nonce> = Trie.empty(); // The traders' nonce values. A trader's nonce value increases by 1 for each order submitted.
    private stable var icdex_pendingOrders: Trie.Trie<AccountId, [Txid]> = Trie.empty(); // Trader's orders in pending status
    private stable var icdex_makers: Trie.Trie<AccountId, (rate: Nat/*50 means 50%*/, managedBy: Principal)> = Trie.empty(); // Vip-Makers
    private stable var icdex_dip20Balances: Trie.Trie<AccountId, (Principal, Nat)> = Trie.empty(); // deprecated
    private stable var icdex_lastVisits = Deque.empty<(AccountId, Nat)>(); // Statistics of visitors for protection against DOS attacks.
    private stable var icdex_RPCAccounts: Trie.Trie<ETHAddress, [ICRC1.Account]> = Trie.empty(); // *pre-occupancy
    private stable var icdex_accountSettings: Trie.Trie<AccountId, AccountSetting> = Trie.empty(); // Configuration items for traders, such as Exchange Mode, which is TunnelMode by default
    private stable var icdex_keepingBalances: Trie.Trie<AccountId, KeepingBalance> = Trie.empty(); // Traders keep balances in Pair Pool Account, to which they can make deposits and withdrawals.
    private stable var icdex_poolBalance: {token0: Amount; token1: Amount } = {token0 = 0; token1 = 0 }; // The balance of Pair Pool Account (PoolAccount).
    private stable var icdex_soid: STO.Soid = 1; // Strategy Order Index Value
    // Strategy orders, including stop-loss orders and pro orders. Strategies with #Deleted status will be removed after 24 hours
    private stable var icdex_stOrderRecords: STO.STOrderRecords = Trie.empty(); // Trie.Trie<Soid, STOrder> 
    private stable var icdex_userProOrderList: STO.UserProOrderList = Trie.empty(); // Trie.Trie<AccountId, List.List<Soid>> // Trader's Pro Order Index
    private stable var icdex_activeProOrderList: STO.ActiveProOrderList = List.nil<STO.Soid>(); // List of active pro orders
    private stable var icdex_userStopLossOrderList: STO.UserStopLossOrderList = Trie.empty(); // Trader's Stop-loss Order Index
    private stable var icdex_activeStopLossOrderList: STO.ActiveStopLossOrderList = { // List of active stop-loss orders
        buy = List.nil<(STO.Soid, STO.Price)>(); 
        sell = List.nil<(STO.Soid, STO.Price)>();
    }; 
    private stable var icdex_stOrderTxids: STO.STOrderTxids = Trie.empty(); // Trie.Trie<Txid, Soid> // Txid to Soid relationship index table
    private stable var clearingTxids = List.nil<(Txid)>(); // Completed orders waiting to be cleared
    private stable var lastExpiredTime : Time.Time = 0; // Last time expired orders were cleared
    private stable var timeSortedTxids = Deque.empty<(Txid, Time.Time)>(); // Time DESC sorted order index table
    private stable var countRejections: Nat = 0;
    private stable var lastExecutionDuration: Int = 0;
    private stable var maxExecutionDuration: Int = 0;
    private stable var lastSagaRunningTime : Time.Time = 0;
    private stable var lastStorageTime : Time.Time = 0;
    private var countAsyncMessage : Nat = 0;
    // The maximum number of orders the order book can accept, if this is exceeded, only quotes within +/-5% of the latest price will be accepted.
    private let maxTotalPendingNumber : Nat = 50_000; 
    // DRC205: External scalable storage of transaction records
    private var drc205 = DRC205.DRC205({EN_DEBUG = icdex_debug; MAX_CACHE_TIME = 6 * 30 * 24 * 3600 * ns_; MAX_CACHE_NUMBER_PER = 1000; MAX_STORAGE_TRIES = 2; }); 
    // Statistics on broker's volume and commissions
    private stable var stats_brokers: Trie.Trie<AccountId, {vol: Vol; commission: Vol; count: Nat; rate: Float}> = Trie.empty();
    // Statistics on vip-maker's volume and commissions
    private stable var stats_makers: Trie.Trie<AccountId, {vol: Vol; commission: Vol; orders: Nat; filledCount: Nat;}> = Trie.empty();
    private let sa_zero : [Nat8] = [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0]; // pool
    private let sa_one : [Nat8] = [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1]; // temp
    private stable var initialized: Bool = false;
    private stable var fallbacking_txids = List.nil<(Txid, Time.Time)>(); // Orders in fallbacking
    private stable var accountWithdrawToids = List.nil<(AccountId, Toid, Time.Time)>(); // ICTC transaction orders being withdrawn

    /* ===========================
      Local function section
    ============================== */
    /*
    * System pressure control functions
    */
    // ICTC status check. If more than 5 (if debug is 10) transactions are blocked, the trading pair will be suspended.
    private func _checkICTCError() : (){
        let count = _getSaga().getBlockingOrders().size();
        if (count >= (if (icdex_debug){ 10 }else{ 5 })){
            pause := true;
            mode := #DisabledTrading;
            pairOpeningTime := 0;
        };
    };
    // Check that all transactions in the ICTC have been executed.
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
    // Checks whether the execution of the transactions specified in the ICTC has completed.
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
    // Checks whether the execution of the transactions related to the orders of the specified trader in ICTC is complete.
    private func _accountIctcDone(_a: AccountId): Bool{
        for ((t, o) in Trie.iter(_accountPendingOrders(?_a))){
            var toids: [Toid] = o.toids;
            for ((a, toid, time) in List.toArray(List.filter(accountWithdrawToids, func (item: (AccountId, Toid, Time.Time)): Bool{ item.0 == _a })).vals()){
                toids := Tools.arrayAppend(toids, [toid]);
            };
            if (not(_ictcDone(toids))){
                return false;
            };
        };
        return true;
    };
    private func _visitLog(_a: AccountId): (){
        icdex_lastVisits := Deque.pushFront(icdex_lastVisits, (_a, _now()));
        var enLoop: Bool = true;
        while(enLoop){
            switch(Deque.popBack(icdex_lastVisits)){
                case(?(deque, (_account, _ts))){
                    if (_now() > _ts + 3600 or List.size(icdex_lastVisits.0) + List.size(icdex_lastVisits.1) > 5999){
                        icdex_lastVisits := deque;
                    }else{
                        enLoop := false;
                    };
                };
                case(_){ enLoop := false; };
            };
        };
    };
    private func _tps(_duration: Nat, _a: ?AccountId) : (total: Nat, tpsX10: Nat){
        if (icdex_debug) { return (0, 0); };  /*config*/
        var count: Nat = 0;
        var ts = _now();
        var temp_deque = icdex_lastVisits;
        while(ts > 0 and _now() < ts + _duration){
            switch(Deque.popFront(temp_deque)){
                case(?((_account, _ts), deque)){
                    temp_deque := deque;
                    ts := _ts;
                    switch(_a){
                        case(?(account)){
                            if(_now() < _ts + _duration and account == _account){ count += 1; };
                        };
                        case(_){
                            if(_now() < _ts + _duration){ count += 1; };
                        };
                    };
                };
                case(_){ ts := 0; return (0,0); };
            };
        };
        return (count, count * 10 / _duration);
    };
    // TPS within 5 seconds must be less than MAX_TPS and TPS within 15 seconds must be less than MAX_TPS * 80%.
    private func _checkTPSLimit() : Bool{
        return _tps(5, null).1 < setting.MAX_TPS*10 and _tps(15, null).1 < setting.MAX_TPS*8;
    };
    // Total number of asynchronous message queues
    private func _asyncMessageSize() : Nat{
        return countAsyncMessage + _getSaga().asyncMessageSize();
    };
    // Limit on the number of message queues waiting asynchronously
    private func _checkAsyncMessageLimit() : Bool{
        return _asyncMessageSize() < 390; /*config*/
    };
    // Checks access restrictions with `_checkAsyncMessageLimit()` and `_checkTPSLimit()` and logs current access. Used to prevent DOS attacks.
    private func _checkOverload(_caller: ?AccountId) : async* (){
        if (not(_checkAsyncMessageLimit()) or not(_checkTPSLimit())){
            countRejections += 1; 
            throw Error.reject("405: IC network is busy, please try again later."); 
        };
        _visitLog(Option.get(_caller, Tools.principalToAccountBlob(Principal.fromActor(this), null)));
    };
    // Check the maximum number of orders the trader is allowed to have in PENDING status.
    // 1. Trader: MAX_PENDINGS + 5 orders per pro-order
    // 2. Vip-maker: MAX_PENDINGS * 10 + 10 orders per pro-order
    private func _maxPendings(_trader: AccountId) : Nat{
        var proOrderCount : Nat = 0;
        switch(Trie.get(icdex_userProOrderList, keyb(_trader), Blob.equal)){
            case(?(userOrderList)){ proOrderCount := List.size(userOrderList); };
            case(_){};
        };
        switch(Trie.get(icdex_makers, keyb(_trader), Blob.equal)){
            case(?(v, p)){ return setting.MAX_PENDINGS * 10 + proOrderCount * 10; };
            case(_){ return setting.MAX_PENDINGS + proOrderCount * 5; };
        };
    };

    /*
    * Common Local Functions
    */
    private func _now() : Timestamp{
        return Int.abs(Time.now() / ns_);
    };
    private func _token0Canister() : Principal{ token0_ };
    private func _token1Canister() : Principal{ token1_ };
    // private let ledger: Ledger.Self = actor("ryjl3-tyaaa-aaaaa-aaaba-cai");
    private func keyb(t: Blob) : Trie.Key<Blob> { return { key = t; hash = Blob.hash(t) }; };
    private func keyn(t: Nat) : Trie.Key<Nat> { return { key = t; hash = Tools.natHash(t) }; };
    private func keyt(t: Text) : Trie.Key<Text> { return { key = t; hash = Text.hash(t) }; };
    private func trieItems<K, V>(_trie: Trie.Trie<K,V>, _page: ListPage, _size: ListSize) : TrieList<K, V> {
        return Tools.trieItems(_trie, _page, _size);
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
    private func _toOptSub(_sub: Blob) : ?Blob{
        if (_sub.size() == 0 or _sub == Blob.fromArray(sa_zero)){
            return null;
        }else{
            return ?_sub;
        };
    };
    private func _getGas(_update: Bool) : async* (){
        if (_update or Option.isNull(token0Gas)){
            if (token0Std == #drc20){
                let token: DRC20.Self = actor(Principal.toText(_token0Canister()));
                token0Gas := ?(await token.drc20_fee());
            } /*else if (token0Std == #dip20){
                let token: DIP20.Self = actor(Principal.toText(_token0Canister()));
                token0Gas := ?(await token.getTokenFee());
            }*/ else { // if (token0Std == #icrc1 or token0Std == #icp)
                let token: ICRC1.Self = actor(Principal.toText(_token0Canister()));
                token0Gas := ?(await token.icrc1_fee());
            } /*else if (token0Std == #ledger){
                let token: Ledger.Self = actor(Principal.toText(_token0Canister()));
                token0Gas := ?Nat64.toNat((await token.transfer_fee({})).transfer_fee.e8s);
            }*/;
        };
        if (_update or Option.isNull(token1Gas)){
            if (token1Std == #drc20){
                let token: DRC20.Self = actor(Principal.toText(_token1Canister()));
                token1Gas := ?(await token.drc20_fee());
            } /*else if (token1Std == #dip20){
                let token: DIP20.Self = actor(Principal.toText(_token1Canister()));
                token1Gas := ?(await token.getTokenFee());
            }*/ else { // if (token1Std == #icrc1 or token1Std == #icp)
                let token: ICRC1.Self = actor(Principal.toText(_token1Canister()));
                token1Gas := ?(await token.icrc1_fee());
            } /*else if (token1Std == #ledger){
                let token: Ledger.Self = actor(Principal.toText(_token1Canister()));
                token1Gas := ?Nat64.toNat((await token.transfer_fee({})).transfer_fee.e8s);
            }*/;
        };
    };
    private func _getFee0() : Nat{
        switch(token0Gas){
            case(?(gas)){ return gas; };
            case(_){ assert(false); return 0; };  
        };
    };
    private func _getFee1() : Nat{
        switch(token1Gas){
            case(?(gas)){ return gas; };
            case(_){ assert(false); return 0; };  
        };
    };
    private func _natToFloat(_n: Nat) : Float{
        return Tools.natToFloat(_n);
    };
    private func _floatToNat(_f: Float) : Nat{
        assert(_f >= 0);
        return Tools.floatToNat(_f);
    };

    private func _onlyOwner(_caller: Principal) : Bool { //ict
        return Principal.isController(_caller);
    }; 
    
    // Pair Opening: (Or)
    // 1. pause == false and Time.now() >= pairOpeningTime
    // 2. pause == false and Time.now() < pairOpeningTime and _inIDO() and _onlyIDOFunder(caller) // Allow IDO Funder to place orders prior to opening time
    private func _notPaused(_caller: ?Principal) : Bool { 
        let caller = Option.get(_caller, Principal.fromActor(this));
        if (pairOpeningTime > 0 and Time.now() >= pairOpeningTime){
            pause := false;
            mode := #GeneralTrading;
            pairOpeningTime := 0;
        };
        return not(pause) and (Time.now() >= pairOpeningTime or (_inIDO() and _onlyIDOFunder(caller)));
    };
    private func _onlyOrderOwner(_account: AccountId, _txid: Txid) : Bool{
        // switch(Trie.get(icdex_orders, keyb(_txid), Blob.equal)){
        //     case(?(order)){ return order.account == _account; };
        //     case(_){ return false; };
        // };
        let nonceBytes = Tools.slice(Blob.toArray(_txid), 0, ?3);
        let nonce = Nat32.toNat(Binary.BigEndian.toNat32(nonceBytes));
        let max: Nat = 2 ** 32;
        var i: Nat = 0;
        while (i < 64){
            if (_txid == drc205.generateTxid(Principal.fromActor(this), _account, i * max + nonce)){
                return true;
            };
            i += 1;
        };
        return false
    };
    private func _onlyVipMaker(_trader: AccountId) : Bool{
        switch(Trie.get(icdex_makers, keyb(_trader), Blob.equal)){
            case(?(v, p)){ return v > 0; };
            case(_){ return false; };
        };
    };

    private func _getNonce(_a: AccountId): Nat{
        switch(Trie.get(icdex_nonces, keyb(_a), Blob.equal)){
            case(?(v)){ return v; };
            case(_){ return 0; };
        };
    };
    private func _addNonce(_a: AccountId): (){
        let n = _getNonce(_a);
        icdex_nonces := Trie.put(icdex_nonces, keyb(_a), Blob.equal, n+1).0;
        icdex_index += 1;
    };
    private func _accountIdToHex(_a: AccountId) : Text{
        return Hex.encode(Blob.toArray(_a));
    };
    // private func _getSA(_sa: Blob) : Blob{
    //     var sa = Blob.toArray(_sa);
    //     while (sa.size() < 32){
    //         sa := Tools.arrayAppend([0:Nat8], sa);
    //     };
    //     return Blob.fromArray(sa);
    // };
    // private func _getMainAccount() : AccountId{
    //     let main = Principal.fromActor(this);
    //     return Blob.fromArray(Tools.principalToAccount(main, null));
    // };
    private func _getPairAccount(_sub: Blob) : AccountId{
        let main = Principal.fromActor(this);
        let sa = Blob.toArray(_sub);
        return Blob.fromArray(Tools.principalToAccount(main, ?sa));
    };
    /*private func _getDip20Principal(_a: AccountId) : Principal{
        switch(Trie.get(icdex_dip20Balances, keyb(_a), Blob.equal)){
            case(?(p, v)){ return p; };
            case(_){ assert(false); return Principal.fromText("aaaaa-aa"); };
        };
    };*/
    /*private func _getDip20Balance(_a: AccountId) : Nat{  // token0 / token1
        switch(Trie.get(icdex_dip20Balances, keyb(_a), Blob.equal)){
            case(?(p, v)){ return v; };
            case(_){ return 0; };
        };
    };*/

    private func _getPairBalance(_tokenId: Principal, _std: Types.TokenStd, _sub: Blob) : async* Nat{  
        let _a = _getPairAccount(_sub);
        var balance : Nat = 0;
        try{
            countAsyncMessage += 1;
            if (_std == #drc20){
                let token: DRC20.Self = actor(Principal.toText(_tokenId));
                let res = await token.drc20_balanceOf(_accountIdToHex(_a));
                balance := res;
            } /*else if (_std == #dip20) { // #dip20 
                balance := _getDip20Balance(_a);
            }*/ else { // if (_std == #icrc1 or _std == #icp) 
                let token : ICRC1.Self = actor(Principal.toText(_tokenId));
                let res = await token.icrc1_balance_of({owner = Principal.fromActor(this); subaccount = _toOptSub(_sub)});
                balance := res;
            }/* else if (_std == #icp){ // or _std == #ledger
                let token: Ledger.Self = actor(Principal.toText(_tokenId));
                let res = await token.account_balance({ account = _a; });
                balance := Nat64.toNat(res.e8s);
            }*/;
            countAsyncMessage -= Nat.min(1, countAsyncMessage);
            return balance;
        }catch(e){
            countAsyncMessage -= Nat.min(1, countAsyncMessage);
            throw Error.reject("query token balance error: "# Error.message(e)); 
        };
    };
    private func _getBaseBalance(_sub: Blob) : async* Nat{  // token0
        return await* _getPairBalance(_token0Canister(), token0Std, _sub);
    };
    private func _getQuoteBalance(_sub: Blob) : async* Nat{ // token1
        return await* _getPairBalance(_token1Canister(), token1Std, _sub);
    };
    private func _tokenTransfer(_token: Principal, _fromSa: Blob, _toIcrc1Account: ICRC1.Account, _value: Nat, _data: ?Blob) : async* (){  
        var _std : Types.TokenStd = #icrc1;
        if (_token == _token0Canister()){
            _std := token0Std;
        }else if (_token == _token1Canister()){
            _std := token1Std;
        };
        let _toAccount = Tools.principalToAccountBlob(_toIcrc1Account.owner, _toSaNat8(_toIcrc1Account.subaccount));
        if (_std == #drc20){
            let token: DRC20.Self = actor(Principal.toText(_token));
            try{
                countAsyncMessage += 1;
                let res = await token.drc20_transfer(_accountIdToHex(_toAccount), _value, null, ?Blob.toArray(_fromSa), _data);
                switch(res){
                    case(#ok(txid)){ 
                        countAsyncMessage -= Nat.min(1, countAsyncMessage);
                    };
                    case(#err(e)){ 
                        throw Error.reject("DRC20 token.drc20_transfer() error: "# e.message); 
                    };
                };
            }catch(e){
                countAsyncMessage -= Nat.min(1, countAsyncMessage);
                throw Error.reject("Error transferring token: "# Error.message(e)); 
            };
        }else{ // #icrc1
            let token: ICRC1.Self = actor(Principal.toText(_token));
            try{
                countAsyncMessage += 1;
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
                        countAsyncMessage -= Nat.min(1, countAsyncMessage);
                    };
                    case(#Err(e)){ 
                        throw Error.reject("ICRC1 token.icrc1_transfer() error."); 
                    };
                };
            }catch(e){
                countAsyncMessage -= Nat.min(1, countAsyncMessage);
                throw Error.reject("Error transferring token: "# Error.message(e)); 
            };
        };
    };
    private func _transferFrom(_token: Principal, _from: ICRC1.Account, _to: ICRC1.Account, _value: Nat, _data: ?Blob) : async* (){  
        var std : Types.TokenStd = #icrc1;
        if (_token == _token0Canister()){
            std := token0Std;
        }else if (_token == _token1Canister()){
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
            countAsyncMessage += 1;
            let res = await token.drc20_transferFrom(_accountIdToHex(_from), _accountIdToHex(_to), _value, null, null, _data);
            switch(res){
                case(#ok(txid)){ 
                    countAsyncMessage -= Nat.min(1, countAsyncMessage);
                    return txid;
                };
                case(#err(e)){ 
                    throw Error.reject("DRC20 token.drc20_transferFrom() error: "# e.message); 
                };
            };
        }catch(e){
            countAsyncMessage -= Nat.min(1, countAsyncMessage);
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
            countAsyncMessage += 1;
            let result = await token.icrc2_transfer_from(arg);
            switch(result){
                case(#Ok(blockNumber)){
                    countAsyncMessage -= Nat.min(1, countAsyncMessage);
                    return blockNumber;
                };
                case(#Err(e)){
                    throw Error.reject("ICRC1 token.icrc2_transfer_from() error: "# debug_show(e)); 
                };
            };
        }catch(e){
            countAsyncMessage -= Nat.min(1, countAsyncMessage);
            throw Error.reject("Error transferring token: "# Error.message(e)); 
        };
    };
    /*private func _dip20TransferFrom(_token: Principal, _a: AccountId, _from: Principal, _to: Principal, _value: Nat) : async Nat{  
        let token: DIP20.Self = actor(Principal.toText(_token));
        try{
            countAsyncMessage += 1;
            let res = await token.transferFrom(_from, _to, _value);
            switch(res){
                case(#Ok(txid)){ 
                    _dip20Increase(_a, _to, _value);
                    countAsyncMessage -= Nat.min(1, countAsyncMessage);
                    return txid; 
                };
                case(#Err(e)){ 
                    throw Error.reject("DIP20 token.transferFrom() error!"); 
                };
            };
        }catch(e){
            countAsyncMessage -= Nat.min(1, countAsyncMessage);
            throw Error.reject("query dip20 balance error: "# Error.message(e)); 
        };
    };*/
    /*private func _dip20Increase(_a: AccountId, _p: Principal, _value: Nat) : (){ 
        switch(Trie.get(icdex_dip20Balances, keyb(_a), Blob.equal)){
            case(?(p, v)){ 
                icdex_dip20Balances := Trie.put(icdex_dip20Balances, keyb(_a), Blob.equal, (p, v + _value)).0; 
            };
            case(_){
                icdex_dip20Balances := Trie.put(icdex_dip20Balances, keyb(_a), Blob.equal, (_p, _value)).0; 
            };
        };
    };
    private func _dip20Decrease(_a: AccountId, _value: Nat) : (){ 
        switch(Trie.get(icdex_dip20Balances, keyb(_a), Blob.equal)){
            case(?(p, v)){ 
                if (Nat.sub(v, _value) == 0){
                    icdex_dip20Balances := Trie.remove(icdex_dip20Balances, keyb(_a), Blob.equal).0;
                } else{
                    icdex_dip20Balances := Trie.put(icdex_dip20Balances, keyb(_a), Blob.equal, (p, Nat.sub(v, _value))).0; 
                };
            };
            case(_){ assert(false); };
        };
    };*/

    /*
    * ICTC local functions and local tasks
    */

    private var saga: ?SagaTM.SagaTM = null;

    // Create saga object
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

    // Local tasks
    /*private func _dip20Send(_from: AccountId, _value: Nat) : (){ 
        _dip20Decrease(_from, _value);
    };
    private func _dip20SendComp(_a: AccountId, _p: Principal, _value: Nat) : (){ 
        _dip20Increase(_a, _p, _value);
    };*/
    private func _localBatchTransfer(_args: [(_act: {#add; #sub}, _account: Blob, _token: {#token0; #token1}, _amount: {#locked: Nat; #available: Nat})]) : 
    ([KeepingBalance]){
        var res : [KeepingBalance] = [];
        for (arg in _args.vals()){
            switch(arg.0){
                case(#add){
                    res := Tools.arrayAppend(res, [_addAccountBalance(arg.1, arg.2, arg.3)]);
                };
                case(#sub){
                    res := Tools.arrayAppend(res, [_subAccountBalance(arg.1, arg.2, arg.3)]);
                };
            };
        };
        return res;
    };

    // Task builder
    private func _buildTask(_txid: ?Txid, _callee: Principal, _callType: SagaTM.CallType, _preTtid: [SagaTM.Ttid]) : SagaTM.PushTaskRequest{
        var cycles = 0;
        return {
            callee = _callee;
            callType = _callType;
            preTtid = _preTtid;
            attemptsMax = ?1;
            recallInterval = null; // nanoseconds
            cycles = cycles;
            data = _txid;
        };
    };

    // Local task entrance
    private func _local(_args: SagaTM.CallType, _receipt: ?SagaTM.Receipt) : async (SagaTM.TaskResult){
        switch(_args){
            case(#This(method)){
                switch(method){
                    // case(#dip20Send(_a, _value)){
                    //     /*var result = (); // Receipt
                    //     // do
                    //     result := _dip20Send(_a, _value);*/
                    //     // check & return
                    //     return (#Done, ?#This(#dip20Send), null);
                    // };
                    // case(#dip20SendComp(_a, _p, _value)){
                    //     /*var result = (); // Receipt
                    //     // do
                    //     result := _dip20SendComp(_a, _p, _value);*/
                    //     // check & return
                    //     return (#Done, ?#This(#dip20SendComp), null);
                    // }; 
                    case(#batchTransfer(_args: [(_act: {#add; #sub}, _account: Blob, _token: {#token0; #token1}, _amount: {#locked: Nat; #available: Nat})])){
                        let result = _localBatchTransfer(_args);
                        return (#Done, ?#This(#batchTransfer(result)), null);
                    };
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

    // Execute ICTC
    private func _ictcSagaRun(_toid: Nat, _sync: Bool): async* (){
        if (_sync or (_tps(15, null).1 < setting.MAX_TPS*7 and _checkAsyncMessageLimit()) ){ 
            lastSagaRunningTime := Time.now();
            let saga = _getSaga();
            if (_toid == 0){
                try{
                    countAsyncMessage += 1;
                    let sagaRes = await* saga.getActuator().run();
                    countAsyncMessage -= Nat.min(1, countAsyncMessage);
                }catch(e){
                    countAsyncMessage -= Nat.min(1, countAsyncMessage);
                    throw Error.reject("430: ICTC error: "# Error.message(e)); 
                };
            }else{
                try{
                    countAsyncMessage += 2;
                    if (_sync){
                        let sagaRes = await saga.runSync(_toid);
                    }else{
                        let sagaRes = await saga.run(_toid);
                    };
                    countAsyncMessage -= Nat.min(2, countAsyncMessage);
                }catch(e){
                    countAsyncMessage -= Nat.min(2, countAsyncMessage);
                    throw Error.reject("430: ICTC error: "# Error.message(e)); 
                };
            };
        };
    };

    /*
    * Core Local Functions for Trading
    */

    // Pre-create a new order (tunnel mode) for the trader, returning the TxAccount, Nonce and Txid.
    private func _preCreateTx(_a: AccountId) : (ICRC1.Account, Text, Nat, Txid){ // (address, id)
        let account = _a;
        let nonce = _getNonce(account);
        let txid = drc205.generateTxid(Principal.fromActor(this), account, nonce);
        let address = Hex.encode(Blob.toArray(_getPairAccount(txid)));
        //_addNonce(account);
        return ({owner = Principal.fromActor(this); subaccount = _toOptSub(txid) }, address, nonce, txid);
    };

    // Read TxAccount from an order (tunnel mode)
    private func _orderIcrc1Account(_txid: Txid) : ICRC1.Account{
        switch(Trie.get(icdex_orders, keyb(_txid), Blob.equal)){
            case(?(order)){ 
                switch(order.icrc1Account){
                    case(?(account)) { 
                        switch(account.subaccount){
                            case(?(sub)){
                                if (Blob.toArray(sub).size() == 0 or Blob.toArray(sub) == sa_zero){
                                    return { owner = account.owner; subaccount = null; };
                                };
                            };
                            case(_){};
                        };
                        return account; 
                    };
                    case(_){ 
                        if (icdex_debug) { assert(false);}; 
                        return { owner = Principal.fromActor(this); subaccount = ?Blob.fromArray(sa_one); }; // temp account
                    };
                };
            };
            case(_){  /*config*/
                if (icdex_debug) { assert(false);};
                return { owner = Principal.fromActor(this); subaccount = null; };
            };
        };
    };

    private func _putLatestFilled(_txid: Txid, _filled: [OrderFilled], _side: OrderSide) : (){
        let maxNumber : Nat = 50;
        for (t in _filled.vals()){
            icdex_latestfilled := Deque.pushFront(icdex_latestfilled, (_now(), _txid, t, _side));
        };
        var length = List.size(icdex_latestfilled.0) + List.size(icdex_latestfilled.1);
        while(length > maxNumber){
            switch(Deque.popBack(icdex_latestfilled)){
                case(?(dq, t)){ icdex_latestfilled := dq; };
                case(_){};
            };
            length -= 1;
        };
    };

    private func _getLatestFilled() : [(Timestamp, Txid, OrderFilled, OrderSide)]{
        return List.toArray(List.append(icdex_latestfilled.0, List.reverse(icdex_latestfilled.1)));
    };

    // Handling of counterparty order (maker order) in the order book when order is matched
    private func _makerFilled(_txid: Txid, _filled: OrderFilled, _toid: SagaTM.Toid) : (account: AccountId, nonce: Nonce){
        var account: Blob = Blob.fromArray([]);
        var nonce: Nonce = 0;
        //var cpFilled : [OrderFilled] = [];
        var token0Value : BalanceChange = #CreditRecord(0); // maker filled
        var token1Value : BalanceChange = #CreditRecord(0); // maker filled
        switch(Trie.get(icdex_orders, keyb(_filled.counterparty), Blob.equal)){
            case(?(order)){
                if (order.status == #Pending){
                    account := order.account;
                    nonce := order.nonce;
                    var remainingQuantity = OrderBook.quantity(order.remaining);
                    var remainingAmount = OrderBook.amount(order.remaining);
                    var tokenAmount: Nat = 0; // maker vol
                    var currencyAmount: Nat = 0; // maker vol
                    //var gas0: Nat = 0;
                    //var gas1: Nat = 0;
                    switch(_filled.token0Value){
                        case(#CreditRecord(value)){ // Maker Sell  (_txid Taker Buy)
                            tokenAmount += value;
                            remainingQuantity := Nat.max(remainingQuantity, value) - value;
                            token0Value := #DebitRecord(value);
                        };
                        case(#DebitRecord(value)){ // Maker Buy
                            tokenAmount += value;
                            remainingQuantity := Nat.max(remainingQuantity, value) - value;
                            token0Value := #CreditRecord(value);
                            //gas0 += _getFee0();
                        };
                        case(_){};
                    };
                    switch(_filled.token1Value){
                        case(#DebitRecord(value)){  // Maker Sell
                            currencyAmount += value;
                            token1Value := #CreditRecord(value);
                            //gas1 += _getFee1();
                        };
                        case(#CreditRecord(value)){  // Maker Buy
                            currencyAmount += value;
                            remainingAmount := Nat.max(remainingAmount, value) - value;
                            token1Value := #DebitRecord(value);
                        };
                        case(_){};
                    };
                    _updateTotalVol(tokenAmount, currencyAmount);
                    _updateVol(account, tokenAmount, currencyAmount);
                    //if (quantity < setting.UNIT_SIZE){ quantity := 0; };
                    let remaining: OrderPrice = OrderBook.setQuantity(order.remaining, remainingQuantity, ?remainingAmount);
                    var status: TradingStatus = order.status;
                    // if (Option.isNull(OrderBook.get(icdex_orderBook, order.txid, ?OrderBook.side(order.orderPrice)))){
                    //     status := #Closed;
                    // };
                    if (remainingQuantity < setting.UNIT_SIZE){
                        status := #Closed;
                    };
                    let filled : [OrderFilled] = [{counterparty = _txid; token0Value = token0Value; token1Value = token1Value; time = Time.now() }];
                    _update(order.txid, ?remaining, ?_toid, ?filled, null, null, ?status, null);
                    //ignore _refund(_toid, order.txid, []);
                };
            };
            case(_){ /*assert(false);*/ };
        };
        return (account, nonce);
    };

    // Sends a token of the specified values from the sub-account of the trading pair to the specified accounts via ICTC,
    // supports batch sending (_toIcrc1Account and _value are numeric values).
    // Parameters:
    // * _isAutoMode: Setting it to true when sending tokens for orders means that it automatically recognizes the PoolMode, and adjusts the sending strategy. If you send a token normally, you need to set it to false.
    // * _subaccount: Set to txid when sending tokens for orders. if sending normally, it needs to be set to the subaccount of the pair.
    private func _sendToken(_isAutoMode: Bool, _tokenSide: {#token0;#token1}, _toid: SagaTM.Toid, _subaccount: Blob, _preTtids: [SagaTM.Ttid], _toIcrc1Account: [ICRC1.Account], _value: [Nat], _transferData: ?Blob, _callback: ?SagaTM.Callback) : [SagaTM.Ttid]{
        assert(_toIcrc1Account.size() == _value.size());
        var ttids : [SagaTM.Ttid] = [];
        let saga = _getSaga();
        var std = token0Std;
        var tokenPrincipal = _token0Canister();
        var fee = _getFee0();
        if (_tokenSide == #token1){
            std := token1Std;
            tokenPrincipal := _token1Canister();
            fee := _getFee1();
        };
        var subaccount = _subaccount; // pair's subaccount or txid
        var totalAmount : Nat = 0;
        for (v in _value.vals()){
            totalAmount += v;
        };
        // At PoolMode of account, deducted from the account's balance locked in the pool
        var localTransferArgs_pre: [(_act: {#add; #sub}, _account: Blob, _token: {#token0; #token1}, _amount: {#locked: Nat; #available: Nat})] = [];
        if (_isAutoMode){
            switch(Trie.get(icdex_orders, keyb(_subaccount), Blob.equal)){ // _subaccount = txid
                case(?(order)){
                    let mode = _exchangeMode(order.account, ?order.nonce);
                    if (mode == #PoolMode){
                        subaccount := Blob.fromArray(sa_zero);
                        localTransferArgs_pre := Tools.arrayAppend(localTransferArgs_pre, [(#sub, order.account, _tokenSide, #locked(totalAmount))]);
                    };
                };
                case(_){};
            };
        };
        var sub = ?subaccount; // tunnel mode: txid; pool mode: sa_zero
        var sa = _toSaNat8(sub);
        if (subaccount.size() == 0){
            sub := null;
            sa := null;
        };
        let length = _toIcrc1Account.size();
        var toIcrc1Accounts: [ICRC1.Account] = _toIcrc1Account;
        var values: [Nat] = _value;
        // At PoolMode of account, Transfer valueTransferToPool tokens to pool
        var valueTransferToPool: Nat = 0;
        // At PoolMode of account, The received balance is kept in the pool
        var localTransferArgs_post: [(_act: {#add; #sub}, _account: Blob, _token: {#token0; #token1}, _amount: {#locked: Nat; #available: Nat})] = [];
        if (_isAutoMode and length > 0){
            toIcrc1Accounts := [];
            values := [];
            for (i in Iter.range(0, Nat.sub(length, 1))){
                let account = Tools.principalToAccountBlob(_toIcrc1Account[i].owner, _toSaNat8(_toIcrc1Account[i].subaccount));
                let isKeptFunds = _isKeepingBalanceInPair(account);
                if (isKeptFunds){
                    valueTransferToPool += _value[i];
                    localTransferArgs_post := Tools.arrayAppend(localTransferArgs_post, [(#add, account, _tokenSide, #available(_value[i]))]);
                }else{
                    toIcrc1Accounts := Tools.arrayAppend(toIcrc1Accounts, [_toIcrc1Account[i]]);
                    values := Tools.arrayAppend(values, [_value[i]]);
                };
            };
            if (valueTransferToPool > 0 and localTransferArgs_pre.size() == 0){ // to: Pool
                toIcrc1Accounts := Tools.arrayAppend(toIcrc1Accounts, [{owner = Principal.fromActor(this); subaccount = ?Blob.fromArray(sa_zero)}]);
                values := Tools.arrayAppend(values, [valueTransferToPool]);
            };
        };

        if (localTransferArgs_pre.size() > 0){
            let task_pre = _buildTask(sub, Principal.fromActor(this), #This(#batchTransfer(localTransferArgs_pre)), _preTtids);
            let ttid_pre = saga.push(_toid, task_pre, null, null);
            ttids := Tools.arrayAppend(ttids, [ttid_pre]);
        };
        if (std == #drc20 and toIcrc1Accounts.size() > 1){
            let accountArr = Array.map<ICRC1.Account, Address>(toIcrc1Accounts, func (t:ICRC1.Account): Address{
                _accountIdToHex(Tools.principalToAccountBlob(t.owner, _toSaNat8(t.subaccount)))
            });
            let valueArr = Array.map<Nat, Nat>(values, func (t:Nat): Nat{
                Nat.sub(t, fee);
            });
            let task = _buildTask(sub, tokenPrincipal, #DRC20(#transferBatch(accountArr, valueArr, null, sa, _transferData)), _preTtids);
            let ttid = saga.push(_toid, task, null, _callback);
            // if (Option.isSome(_callback)){ _putTTCallback(ttid) };
            ttids := Tools.arrayAppend(ttids, [ttid]);
        }else{
            var i : Nat = 0;
            for (_to in toIcrc1Accounts.vals()){
                let accountPrincipal = toIcrc1Accounts[i].owner;
                let account = Tools.principalToAccountBlob(toIcrc1Accounts[i].owner, _toSaNat8(toIcrc1Accounts[i].subaccount));
                let icrc1Account = toIcrc1Accounts[i];
                let value = Nat.sub(values[i], fee);
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
        if (localTransferArgs_post.size() > 0){
            let task_post = _buildTask(sub, Principal.fromActor(this), #This(#batchTransfer(localTransferArgs_post)), _preTtids);
            let ttid_post = saga.push(_toid, task_post, null, null);
            ttids := Tools.arrayAppend(ttids, [ttid_post]);
        };
        return ttids;
    };
    private func _sendToken0(_isAutoMode: Bool, _toid: SagaTM.Toid, _sub: Blob, _preTtids: [SagaTM.Ttid], _toIcrc1Account: [ICRC1.Account], _value: [Nat], _transferData: ?Blob, _callback: ?SagaTM.Callback) : [SagaTM.Ttid]{
        return _sendToken(_isAutoMode, #token0, _toid, _sub, _preTtids, _toIcrc1Account, _value, _transferData, _callback);
    };
    private func _sendToken1(_isAutoMode: Bool, _toid: SagaTM.Toid, _sub: Blob, _preTtids: [SagaTM.Ttid], _toIcrc1Account: [ICRC1.Account], _value: [Nat], _transferData: ?Blob, _callback: ?SagaTM.Callback) : [SagaTM.Ttid] {
        return _sendToken(_isAutoMode, #token1, _toid, _sub, _preTtids, _toIcrc1Account, _value, _transferData, _callback);
    };

    // Refund via ICTC
    private func _refund(_toid: SagaTM.Toid, _txid: Txid, _preTtids: [SagaTM.Ttid]) : [SagaTM.Ttid]{
        // Make sure the remaining is a real available balance before calling _refund()
        // Status: #Closed/#Cancelled
        var icrc1Account = _orderIcrc1Account(_txid);
        let account = Tools.principalToAccountBlob(icrc1Account.owner, _toSaNat8(icrc1Account.subaccount));
        // if (_inCompetition(account)){ /*Competitions*/
        //     icrc1Account := {owner = Principal.fromActor(this); subaccount = _toOptSub(_getCompAccountSa(account))};
        // };
        var ttids: [SagaTM.Ttid] = [];
        let saga = _getSaga();
        var toid: SagaTM.Toid = _toid;
        switch(Trie.get(icdex_orders, keyb(_txid), Blob.equal)){
            case(?(order)){
                var tokenAmount = OrderBook.quantity(order.remaining);
                var currencyAmount = OrderBook.amount(order.remaining);
                var fee0: Nat = 0;
                var fee1: Nat = 0;
                // charge cancelling fee: cancelling order without any fills within 1h 
                if (order.status == #Cancelled and Time.now() < order.time + 3600*ns_ and order.filled.size() == 0 and not(_isSTOrder(_txid))){
                    // _chargeCancelFee(_value: Amount, _isToken1: Bool) : (value: Amount, icdexFee: Amount)
                    if (OrderBook.side(order.orderPrice) == #Sell and order.orderType == #LMT){
                        let amountAndFee = _chargeCancelFee(tokenAmount, false);
                        tokenAmount := amountAndFee.0;
                        fee0 := amountAndFee.1;
                    }else if (OrderBook.side(order.orderPrice) == #Buy and order.orderType == #LMT){
                        let amountAndFee = _chargeCancelFee(currencyAmount, true);
                        currencyAmount := amountAndFee.0;
                        fee1 := amountAndFee.1;
                    };
                };
                if (OrderBook.side(order.orderPrice) == #Sell and (order.status == #Closed or order.status == #Cancelled)){
                    var gas0: Nat = 0;
                    if (tokenAmount > _getFee0()){
                        gas0 := _getFee0();
                        ttids := Tools.arrayAppend(ttids, _sendToken0(true, toid, _txid, _preTtids, [icrc1Account], [tokenAmount], ?_txid, null));
                    }else{ gas0 := tokenAmount; };
                    if (fee0 > _getFee0()){
                        ttids := Tools.arrayAppend(ttids, _sendToken0(true, toid, _txid, _preTtids, [{owner = icdexRouter; subaccount = null}], [fee0], ?_txid, null));
                    };
                    let remaining: OrderPrice = OrderBook.setQuantity(order.remaining, 0, null);
                    _update(_txid, ?remaining, ?toid, null, ?{gas0=gas0; gas1=0}, ?{fee0=fee0; fee1=0}, null, ?(tokenAmount, 0, toid));
                };
                if (OrderBook.side(order.orderPrice) == #Buy and (order.status == #Closed or order.status == #Cancelled)){
                    var gas1: Nat = 0;
                    if (currencyAmount > _getFee1()){
                        gas1 := _getFee1();
                        ttids := Tools.arrayAppend(ttids, _sendToken1(true, toid, _txid, _preTtids, [icrc1Account], [currencyAmount], ?_txid, null));
                    }else{ gas1 := currencyAmount; };
                    if (fee1 > _getFee1()){
                        ttids := Tools.arrayAppend(ttids, _sendToken1(true, toid, _txid, _preTtids, [{owner = icdexRouter; subaccount = null}], [fee1], ?_txid, null));
                    };
                    let remaining: OrderPrice = OrderBook.setQuantity(order.remaining, 0, ?0); 
                    _update(_txid, ?remaining, ?toid, null, ?{gas0=0; gas1=gas1}, ?{fee0=0; fee1=fee1}, null, ?(0, currencyAmount, toid));
                };
            };
            case(_){};
        };
        _dropSubAccount(toid, _txid);
        return ttids;
    };

    // Cancel via ICTC
    private func _cancel(_toid: SagaTM.Toid, _txid: Txid, _side: ?OrderBook.OrderSide): [SagaTM.Ttid]{
        // #Pending order
        var ttids: [SagaTM.Ttid] = [];
        switch(Trie.get(icdex_orders, keyb(_txid), Blob.equal)){
            case(?(order)){
                switch(_side){
                    case(?side){
                        if (OrderBook.side(order.orderPrice) != side){
                            return ttids;
                        };
                    };
                    case(_){};
                };
                if (order.status == #Pending){
                    icdex_orderBook := OrderBook.remove(icdex_orderBook, _txid, _side);
                    _update(_txid, null, ?_toid, null, null, null, ?#Cancelled, null);
                    ttids := _refund(_toid, _txid, []);
                    _saveOrderRecord(_txid, false, false);
                    _hook_cancel(_txid, order.orderPrice.price);
                };
            };
            case(_){};
        };
        return ttids;
    };

    // Fallbacking status management
    private func _putFallbacking(_txid: Txid) : (){
        fallbacking_txids := List.filter(fallbacking_txids, func (t: (Txid, Time.Time)): Bool{
            Time.now() < t.1 + 72 * 3600 * ns_  // 72h
        });
        fallbacking_txids := List.push((_txid, Time.now()), fallbacking_txids);
    };
    private func _removeFallbacking(_txid: Txid) : (){
        fallbacking_txids := List.filter(fallbacking_txids, func (t: (Txid, Time.Time)): Bool{
            t.0 != _txid
        });
    };
    private func _isFallbacking(_txid: Txid): Bool{
        return Option.isSome(List.find(fallbacking_txids, func (t: (Txid, Time.Time)): Bool{
            t.0 == _txid and Time.now() < t.1 + 72 * 3600 * ns_
        }));
    };

    // Fallback
    // There must be no active order with that txid in icdex_orders and no record that is fallbacking.
    private func _fallback(_icrc1Account: ICRC1.Account, _txid: Txid, _side: ?OrderSide) : async* Bool{
        _clear();
        let account = Tools.principalToAccountBlob(_icrc1Account.owner, _toSaNat8(_icrc1Account.subaccount));
        let txid = _txid;
        let txAccount = _getPairAccount(txid);
        var icrc1Account = _icrc1Account;
        // if (_inCompetition(account)){ /*Competitions*/
        //     icrc1Account := {owner = Principal.fromActor(this); subaccount = _toOptSub(_getCompAccountSa(account))};
        // };
        var side: Int = 0;
        switch(_side){
            case(?(#Buy)){ side := 1; };
            case(?(#Sell)){ side := -1; };
            case(_){ side := 0; };
        };
        // important!
        if (Option.isNull(Trie.get(icdex_orders, keyb(txid), Blob.equal)) and not(_isFallbacking(txid))){ //  or side != 0
            _putFallbacking(txid);
            var txTokenBalance : Nat = 0;
            var txCurrencyBalance : Nat = 0;
            try{
                txTokenBalance := await* _getBaseBalance(txid);
                txCurrencyBalance := await* _getQuoteBalance(txid);
            }catch(e){
                _removeFallbacking(txid);
                throw Error.reject("420: internal call error: "# Error.message(e)); 
            };
            if ((txTokenBalance > _getFee0() and (side == 0 or side == 1)) or (txCurrencyBalance > _getFee1() and (side == 0 or side == -1))){
                let saga = _getSaga();
                let toid = saga.create("fallback_1", #Backward, ?_txid, ?(func (_toName: Text, _toid: Toid, _status: SagaTM.OrderStatus, _data: ?Blob) : async (){
                    if (_status == #Done or _status == #Recovered){
                        switch(_data){
                            case(?txid){ _removeFallbacking(txid) };
                            case(_){};
                        };
                    };
                }));
                if ((txTokenBalance > _getFee0() and (side == 0 or side == 1))){
                    ignore _sendToken0(false, toid, _txid, [], [icrc1Account], [txTokenBalance], ?_txid, null);
                };
                if (txCurrencyBalance > _getFee1() and (side == 0 or side == -1)){
                    ignore _sendToken1(false, toid, _txid, [], [icrc1Account], [txCurrencyBalance], ?_txid, null);
                };
                saga.close(toid);
                await* _ictcSagaRun(toid, false);
            }else{
                _removeFallbacking(txid);
            };
            return true;
        }else { return false; };
    };

    // Update an order status in icdex_orders
    private func _update(_txid: Txid, _remaining: ?OrderPrice, _addOid: ?SagaTM.Toid, _addFilled: ?[OrderFilled], _addGas: ?{gas0:Nat; gas1:Nat}, _addFee: ?{fee0:Int; fee1:Int;}, 
    _status: ?TradingStatus, _refund: ?(Nat, Nat, Nat)) : (){
        switch(Trie.get(icdex_orders, keyb(_txid), Blob.equal)){
            case(?(tradingOrder)){
                var addGas = Option.get(_addGas, {gas0=0; gas1=0});
                var addFee = Option.get(_addFee, {fee0=0; fee1=0});
                var toids = tradingOrder.toids;
                if (Option.isNull(Array.find(toids, func (t: SagaTM.Toid): Bool{ t == Option.get(_addOid, 0) }))
                and  Option.isSome(_addOid)){
                    toids := Tools.arrayAppend(toids, [Option.get(_addOid, 0)]);
                };
                let status = Option.get(_status, tradingOrder.status);
                icdex_orders := Trie.put(icdex_orders, keyb(_txid), Blob.equal, {
                    account = tradingOrder.account;
                    icrc1Account = tradingOrder.icrc1Account;
                    txid = tradingOrder.txid;
                    orderType = tradingOrder.orderType;
                    orderPrice = tradingOrder.orderPrice;
                    time = tradingOrder.time;
                    expiration = tradingOrder.expiration;
                    remaining = Option.get(_remaining, tradingOrder.remaining);
                    toids = toids;
                    filled = Tools.arrayAppend(tradingOrder.filled, Option.get(_addFilled, []));
                    status = status;
                    refund = Option.get(_refund, tradingOrder.refund);
                    gas = {gas0 = tradingOrder.gas.gas0 + addGas.gas0; gas1 = tradingOrder.gas.gas1 + addGas.gas1;};
                    fee = {fee0 = tradingOrder.fee.fee0 + addFee.fee0; fee1 = tradingOrder.fee.fee1 + addFee.fee1;};
                    index = tradingOrder.index;
                    nonce = tradingOrder.nonce;
                    data = tradingOrder.data;
                }).0;
                if (status != tradingOrder.status and (status == #Closed or status == #Cancelled)) {
                    _pushToClearing(_txid);
                    // ignore _delPendingOrder(tradingOrder.account, _txid);
                };
                //trieLog := List.push((_txid, "put", Trie.isValid(icdex_orders, true)), trieLog);
            };
            case(_){};
        };
    };

    // Move orders with errors to the variable icdex_failedOrders and clear them periodically
    private func _moveToFailedOrder(_txid: Txid, _unlock0: Amount, _unlock1: Amount) : (){
        switch(Trie.get(icdex_orders, keyb(_txid), Blob.equal)){
            case(?(order)){ 
                _saveOrderRecord(_txid, false, true); // set fail
                icdex_failedOrders := Trie.put(icdex_failedOrders, keyb(_txid), Blob.equal, order).0;
                icdex_orders := Trie.remove(icdex_orders, keyb(_txid), Blob.equal).0;
                // fix locked bug
                if (_unlock0 > 0){
                    ignore _unlockAccountBalance(order.account, #token0, _unlock0);
                };
                if (_unlock1 > 0){
                    ignore _unlockAccountBalance(order.account, #token1, _unlock1);
                };
            };
            case(_){};
        };
        icdex_failedOrders := Trie.filter(icdex_failedOrders, func (k: Txid, v: TradingOrder):Bool{ 
            Time.now() < v.time + ExpirationDuration * 2
        });
    };

    // Push into queue to be cleared
    private func _pushToClearing(_txid: Txid) : (){
        clearingTxids := List.push(_txid, clearingTxids);
    };
    // clear
    private func _clear() : (){
        // icdex_orders := Trie.filter(icdex_orders, func (k: Txid, v: TradingOrder):Bool{ 
        //     var isCompleted : Bool = true;
        //     for (toid in v.toids.vals()){
        //         let saga = _getSaga();
        //         switch(saga.status(toid)){
        //             case(?(status)){ if (status != #Recovered and status != #Done){ isCompleted := false; } };
        //             case(_){};
        //         };
        //     };
        //     return v.status == #Pending or v.status == #Todo or not(isCompleted); 
        // });
        // Optimize to a sequence that is about to be cleaned
        var clearingTxidsTemp = List.nil<(Txid)>();
        for (txid in List.toArray(clearingTxids).vals()){
            switch(Trie.get(icdex_orders, keyb(txid), Blob.equal)){
                case(?(order)){
                    let isCompleted = _ictcDone(order.toids);
                    // var isCompleted : Bool = true;
                    // let saga = _getSaga();
                    // for (toid in order.toids.vals()){
                    //     switch(saga.status(toid)){
                    //         case(?(status)){ if (status != #Recovered and status != #Done){ isCompleted := false; } };
                    //         case(_){};
                    //     };
                    // };
                    if ((order.status == #Closed or order.status == #Cancelled) and isCompleted){
                        icdex_orders := Trie.remove(icdex_orders, keyb(txid), Blob.equal).0;
                        ignore _delPendingOrder(order.account, txid);
                    } else{
                        clearingTxidsTemp := List.push(txid, clearingTxidsTemp);
                    };
                };
                case(_){};
            };
        };
        clearingTxids := clearingTxidsTemp;
    };

    // Sort txid by time
    private func _pushSortedTxids(_txid: Txid, _time: Time.Time) : (){
        var temp : List.List<(Txid, Time.Time)> = null;
        func push(item: (Txid, Time.Time), deque: Deque.Deque<(Txid, Time.Time)>) : (Deque.Deque<(Txid, Time.Time)>){
            switch(Deque.popFront(deque)){
                case(?((txid, time), q)){
                    if (item.1 >= time){
                        return Deque.pushFront(deque, item);
                    }else{
                        temp := List.push((txid, time), temp);
                        return push(item, q);
                    };
                };
                case(_){
                    return Deque.pushFront(deque, item);
                };
            };
        };
        timeSortedTxids := push((_txid, _time), timeSortedTxids);
        for (item in List.toArray(temp).vals()){
            timeSortedTxids := Deque.pushFront(timeSortedTxids, item);
        };
    };

    // Cancel expired orders in the order book and refund them
    private func _expire() : (){
        // var n : Nat = 0;
        // let orders = Trie.filter(icdex_orders, func (k: Txid, v: TradingOrder):Bool{
        //         let defaultExpiration = v.time + ExpirationDuration;
        //         return Time.now() > v.expiration or Time.now() > defaultExpiration;
        // });
        // let saga = _getSaga();
        // for ((k,v) in Trie.iter(orders)){
        //     if (_asyncMessageSize() < 450 and n < 500){
        //         n += 1;
        //         let toid = saga.create("cancel", #Forward, ?k, null);
        //         let ttids = _cancel(toid, k, ?OrderBook.side(v.orderPrice));
        //         saga.close(toid);
        //         if (ttids.size() == 0){
        //             ignore saga.doneEmpty(toid);
        //         };
        //     };
        // };
        // Optimize to a time-sorted txid list
        func clearExpiredTxs(deque: Deque.Deque<(Txid, Time.Time)>) : Deque.Deque<(Txid, Time.Time)>{
            switch(Deque.popBack(deque)){
                case(?(q, (txid, time))){
                    if (Time.now() < time){
                        return deque;
                    }else{
                        switch(Trie.get(icdex_orders, keyb(txid), Blob.equal)){
                            case(?(order)){
                                let saga = _getSaga();
                                let toid = saga.create("cancel", #Forward, ?txid, null);
                                let ttids = _cancel(toid, txid, ?OrderBook.side(order.orderPrice));
                                saga.close(toid);
                                if (ttids.size() == 0){
                                    ignore saga.doneEmpty(toid);
                                };
                            };
                            case(_){};
                        };
                        return clearExpiredTxs(q);
                    };
                };
                case(_){
                    return deque;
                };
            };
        };
        timeSortedTxids := clearExpiredTxs(timeSortedTxids);
        // await* _ictcSagaRun(0);
        // drc205; 
        // if (_tps(15, null).1 < setting.MAX_TPS*7 or Time.now() > lastStorageTime + setting.STORAGE_INTERVAL*ns_) { 
        //     lastStorageTime := Time.now();
        //     ignore drc205.store(); 
        // }; 
        // ictc
    };

    private func _getPriceWeighted(_weighted: Types.PriceWeighted) : Types.PriceWeighted{
        var now = _now();
        if (now < _weighted.updateTime){ now := _weighted.updateTime; };
        var value0 : Nat = 0;
        var value1 : Nat = 0;
        switch(icdex_lastPrice.quantity){
            case(#Sell(value)){ value0 += value; };
            case(#Buy(value)){ value0 += value.0; };
        };
        value1 := value0 * icdex_lastPrice.price / setting.UNIT_SIZE;
        return {
            token0TimeWeighted = _weighted.token0TimeWeighted + value0 * Nat.sub(now, _weighted.updateTime);
            token1TimeWeighted = _weighted.token1TimeWeighted + value1 * Nat.sub(now, _weighted.updateTime);
            updateTime = now;
        };
    };

    private func _getPendingOrderLiquidity(_a: ?AccountId): (value0: Amount, value1: Amount){
        var balance0 : Amount = 0;
        var balance1 : Amount = 0;
        let pendingOrders = _accountPendingOrders(_a);
        for ((t, o) in Trie.iter(pendingOrders)){
            switch(o.remaining.quantity){
                case(#Buy(quantity, amount)){ balance1 += amount };
                case(#Sell(quantity)){ balance0 += quantity };
            };
        };
        return (balance0, balance1);
    };

    private func _getVol(_a: AccountId) : Vol{
        switch(Trie.get(icdex_vols, keyb(_a), Blob.equal)){
            case(?(vol)){
                return vol;
            };
            case(_){
                return { value0 = 0; value1 = 0;};
            };
        };
    };

    private func _updateTotalVol(_addVol0: Amount, _addVol1: Amount) : (){
        icdex_totalVol := {
            value0 = icdex_totalVol.value0 + _addVol0;
            value1 = icdex_totalVol.value1 + _addVol1;
        };
    };

    private func _updateVol(_a: AccountId, _addVol0: Amount, _addVol1: Amount) : (){
        switch(Trie.get(icdex_vols, keyb(_a), Blob.equal)){
            case(?(vol)){
                let newVol = {
                    value0 = vol.value0 + _addVol0;
                    value1 = vol.value1 + _addVol1;
                };
                icdex_vols := Trie.put(icdex_vols, keyb(_a), Blob.equal, newVol).0;
            };
            case(_){
                icdex_vols := Trie.put(icdex_vols, keyb(_a), Blob.equal, {
                    value0 = _addVol0;
                    value1 = _addVol1;
                }).0;
            };
        };
        _setPromotion(_a, { value0 = _addVol0; value1 = _addVol1; });
        // _compAddVol(activeRound, _a, { value0 = _addVol0; value1 = _addVol1; });/*Competitions*/
    };

    private func _updateBrokerData(_a: AccountId, _vol: Vol, _commission: Vol, _latestRate: Float) : (){
        switch(Trie.get(stats_brokers, keyb(_a), Blob.equal)){
            case(?(data)){
                stats_brokers := Trie.put(stats_brokers, keyb(_a), Blob.equal, {
                    vol = { value0 = data.vol.value0 + _vol.value0; value1 = data.vol.value1 + _vol.value1; }; 
                    commission = { value0 = data.commission.value0 + _commission.value0; value1 = data.commission.value1 + _commission.value1; }; 
                    count = data.count+1; 
                    rate = _latestRate
                }).0;
            };
            case(_){
                stats_brokers := Trie.put(stats_brokers, keyb(_a), Blob.equal, {vol = _vol; commission = _commission; count = 1; rate = _latestRate}).0;
            };
        };
    };

    private func _updateMakerData(_a: AccountId, _vol: Vol, _commission: Vol, _orderCount: Nat, _filledCount: Nat) : (){
        switch(Trie.get(stats_makers, keyb(_a), Blob.equal)){
            case(?(data)){
                stats_makers := Trie.put(stats_makers, keyb(_a), Blob.equal, {
                    vol = { value0 = data.vol.value0 + _vol.value0; value1 = data.vol.value1 + _vol.value1; }; 
                    commission = { value0 = data.commission.value0 + _commission.value0; value1 = data.commission.value1 + _commission.value1; }; 
                    orders = data.orders+_orderCount; 
                    filledCount = data.filledCount+_filledCount
                }).0;
            };
            case(_){
                stats_makers := Trie.put(stats_makers, keyb(_a), Blob.equal, {vol = _vol; commission = _commission; orders = _orderCount; filledCount = _filledCount}).0;
            };
        };
    };

    private func _getMakerRebateRate(_maker: AccountId) : Nat{
        var rate: Nat = setting.MAKER_BONUS_RATE;
        switch(Trie.get(icdex_makers, keyb(_maker), Blob.equal)){
            case(?(v, p)){ rate := v; };
            case(_){};
        };
        return rate;
    };

    private func _getTradingFee() : Nat{ // 1000000
        return setting.TRADING_FEE;
    };

    // Charge fees (see section 4 Fee model)
    private func _chargeFee(_maker: AccountId, _value: Amount, _isToken1: Bool, _brokerage: ?{broker: Principal; rate: Float}) : 
    (value: Amount, makerFee: Amount, icdexFee: Amount, brokerFee: Amount){
        var amount = _value;
        var makerFee: Nat = 0;
        var icdexFee: Nat = 0;
        var makerRate: Nat = _getMakerRebateRate(_maker);
        var gas = _getFee0();
        if (_isToken1) { gas := _getFee1(); };
        var tradingFee = _value * _getTradingFee() / 1_000_000; 
        // if (not(_isToken1)){
        //     tradingFee := _value * _getTradingFee() / 2 / 1_000_000; // Buyer
        // };
        if (tradingFee > gas*5){ //fee
            let fee = tradingFee;
            amount := _value - fee;
            icdexFee := fee;
            if (Nat.sub(fee, fee * makerRate / 100) >= gas*2){
                makerFee := fee * makerRate / 100;
                icdexFee := fee - makerFee;
            };
            if (_isToken1){
                icdex_totalFee := { value0 = icdex_totalFee.value0; value1 = icdex_totalFee.value1 + fee; };
            }else{
                icdex_totalFee := { value0 = icdex_totalFee.value0 + fee; value1 = icdex_totalFee.value1; };
            };
        };
        var brokerageFee : Nat = 0;
        switch(_brokerage){
            case(?(b)){
                let brokerageRate = Int.abs(Float.toInt(b.rate * 1_000_000));
                brokerageFee := _value * brokerageRate / 1_000_000;
                if (brokerageFee < gas * 2){ brokerageFee := 0 };
                amount -= brokerageFee;
            };
            case(_){};
        };
        return (amount, makerFee, icdexFee, brokerageFee);
    };
    private func _chargeCancelFee(_value: Amount, _isToken1: Bool) : (value: Amount, icdexFee: Amount){
        var amount = _value;
        var icdexFee: Nat = 0;
        var gas = _getFee0();
        if (_isToken1) { gas := _getFee1(); };
        var cancelFee = Nat.max(_value * _getTradingFee() / 5 / 1_000_000, gas*2); // charge TradingFee*20%
        if (cancelFee > amount){
            icdexFee := amount;
            amount := 0;
        }else{
            icdexFee := cancelFee;
            amount := Nat.sub(amount, icdexFee);
        };
        if (_isToken1){
            icdex_totalFee := { value0 = icdex_totalFee.value0; value1 = icdex_totalFee.value1 + icdexFee; };
        }else{
            icdex_totalFee := { value0 = icdex_totalFee.value0 + icdexFee; value1 = icdex_totalFee.value1; };
        };
        return (amount, icdexFee);
    };

    private func _accountPendingOrders(_account: ?AccountId): Trie.Trie<Txid, TradingOrder>{
        var orders : Trie.Trie<Txid, TradingOrder> = Trie.empty();
        switch(_account){
            case(?accountId){
                switch(Trie.get(icdex_pendingOrders, keyb(accountId), Blob.equal)){
                    case(?(txids)){
                        for (txid in txids.vals()){
                            switch(Trie.get(icdex_orders, keyb(txid), Blob.equal)){
                                case(?(t)){
                                    orders := Trie.put(orders, keyb(txid), Blob.equal, t).0;
                                };
                                case(_){};
                            };
                        };
                    };
                    case(_){};
                };
            };
            case(_){
                orders := icdex_orders;
                // for ((accountId, txids) in Trie.iter(icdex_pendingOrders)){
                //     for (txid in txids.vals()){
                //         switch(Trie.get(icdex_orders, keyb(txid), Blob.equal)){
                //             case(?(t)){
                //                 orders := Trie.put(orders, keyb(txid), Blob.equal, t).0;
                //             };
                //             case(_){};
                //         };
                //     };
                // };
            };
        };
        return orders;
    };

    // private func _toReponse(_order: TradingOrder) : TradingOrder{
    //     if (icdex_debug){ return _order; };
    //     return {
    //         account = _order.account;
    //         icrc1Account = null;
    //         txid = _order.txid;
    //         orderType = _order.orderType;
    //         orderPrice = _order.orderPrice;
    //         time = _order.time;
    //         expiration = _order.expiration;
    //         remaining = _order.remaining;
    //         toids = _order.toids;
    //         filled = _order.filled;  
    //         status = _order.status;
    //         refund = _order.refund;
    //         gas = _order.gas;
    //         fee = _order.fee;
    //         index = _order.index;
    //         nonce = _order.nonce;
    //         data = _order.data;
    //     }
    // };

    // Save order transaction records
    private func _saveOrderRecord(_txid: Txid, _allDetails: Bool, _isFailed: Bool) : (){
        switch(Trie.get(icdex_orders, keyb(_txid), Blob.equal)){
            case(?(order)){
                // if (order.filled.size() > 0 or order.status == #Cancelled or (_isFailed and order.status == #Todo)){
                if (order.status != #Todo or _isFailed){
                    var fills: [OrderFilled] = []; // order.filled;
                    if (_allDetails){
                        fills := order.filled;
                    }else if (order.status == #Cancelled){
                        fills := [];
                    }else if (order.filled.size() > 0){
                        fills := [order.filled[Nat.sub(order.filled.size(), 1)]];
                    };
                    var status: DRC205.Status = #Completed;
                    if (_isFailed and order.status == #Todo){ 
                        status := #Failed;
                    }else if (order.status == #Todo or order.status == #Pending){ 
                        status := #Pending;
                    }else if (order.status == #Cancelled and order.filled.size() > 0){
                        status := #PartiallyCompletedAndCancelled;
                    }else if (order.status == #Cancelled){
                        status := #Cancelled;
                    };
                    //if (order.status == #Cancelled and order.filled.size() == 0){ status := #Failed };
                    var orderValue0 = OrderBook.quantity(order.orderPrice);
                    var orderValue1 = OrderBook.amount(order.orderPrice);
                    var quantity: Nat = 0;
                    var amount: Nat = 0;
                    if (OrderBook.side(order.orderPrice) == #Buy){
                        if (order.orderPrice.price > 0 and orderValue0 > 0){ orderValue1 := orderValue0 * order.orderPrice.price / setting.UNIT_SIZE; };
                        for (item in order.filled.vals()){
                            switch(item.token0Value){
                                case(#CreditRecord(v)){ quantity += v; }; case(_){};
                            };
                            switch(item.token1Value){
                                case(#DebitRecord(v)){ amount += v; }; case(_){};
                            };
                        };
                    }else{
                        if (order.orderPrice.price > 0){ orderValue1 := orderValue0 * order.orderPrice.price / setting.UNIT_SIZE; };
                        for (item in order.filled.vals()){
                            switch(item.token0Value){
                                case(#DebitRecord(v)){ quantity += v; }; case(_){};
                            };
                            switch(item.token1Value){
                                case(#CreditRecord(v)){ amount += v; }; case(_){};
                            };
                        };
                    };
                    // record storage
                    if (orderValue0 > 0 or orderValue1 > 0){
                        var value0_ : ?BalanceChange = null;
                        var value1_ : ?BalanceChange = null;
                        var value0 : BalanceChange = #NoChange;
                        var value1 : BalanceChange = #NoChange;
                        if (OrderBook.side(order.orderPrice) == #Buy){
                            if (orderValue0 > 0){ value0_ := ?#CreditRecord(orderValue0); };
                            if (orderValue1 > 0){ value1_ := ?#DebitRecord(orderValue1); };
                            value0 := #CreditRecord(quantity);
                            value1 := #DebitRecord(amount);
                        }else{
                            if (orderValue0 > 0){ value0_ := ?#DebitRecord(orderValue0); };
                            if (orderValue1 > 0){ value1_ := ?#CreditRecord(orderValue1); };
                            value0 := #DebitRecord(quantity);
                            value1 := #CreditRecord(amount);
                        };
                        var storeIcrc1Account : ?ICRC1.Account = null; 
                        switch (token0Std, order.icrc1Account){
                            case(#icrc1, ?(ia)){
                                storeIcrc1Account := ?ia;
                            };
                            case(_, _){};
                        };
                        _drc205Store(_txid, storeIcrc1Account, order.account, {token0Value = value0_; token1Value = value1_;}, order.orderType, {token0Value = value0; token1Value = value1;}, 
                        order.gas.gas0+order.fee.fee0, order.gas.gas1+order.fee.fee1, order.index, order.nonce, fills, status, order.data);
                    };
                };
            };
            case(_){};
        };
    };

    // Clear temporary addresses for DRC20 tokens (e.g. TxAccount)
    private func _dropSubAccount(_toid: SagaTM.Toid, _txid: Txid) :  (){
        let saga = _getSaga();
        switch(Trie.get(icdex_orders, keyb(_txid), Blob.equal)){
            case(?(order)){
                let side = OrderBook.side(order.orderPrice);
                let tokenAmount = OrderBook.quantity(order.remaining);
                let currencyAmount = OrderBook.amount(order.remaining);
                if (side == #Sell and (order.status == #Closed or order.status == #Cancelled) and tokenAmount <= _getFee0() and token0Std == #drc20){
                    let task = _buildTask(?_txid, _token0Canister(), #DRC20(#dropAccount(_toSaNat8(?_txid))), []);
                    let ttid = saga.push(_toid, task, null, null);
                    let remaining: OrderPrice = OrderBook.setQuantity(order.remaining, 0, null);
                    _update(_txid, ?remaining, ?_toid, null, null, null, null, null);
                };
                if (side == #Buy and (order.status == #Closed or order.status == #Cancelled) and currencyAmount <= _getFee1() and token1Std == #drc20){
                    let task = _buildTask(?_txid, _token1Canister(), #DRC20(#dropAccount(_toSaNat8(?_txid))), []);
                    let ttid = saga.push(_toid, task, null, null);
                    let remaining: OrderPrice = OrderBook.setQuantity(order.remaining, 0, ?0); 
                    _update(_txid, ?remaining, ?_toid, null, null, null, null, null);
                };
            };
            case(_){};
        };
    };

    private func _pendingSize(_account: ?AccountId) : Nat{
        switch(_account){
            case(?(account)){
                switch(Trie.get(icdex_pendingOrders, keyb(account), Blob.equal)){
                    case(?(txids)){ return txids.size(); };
                    case(_){ return 0; };
                };
            };
            case(_){ return Trie.size(icdex_orders); };
        };
    };

    private func _addPendingOrder(_account: AccountId, _txid: Txid) : Nat{
        switch(Trie.get(icdex_pendingOrders, keyb(_account), Blob.equal)){
            case(?(txids)){
                if (Option.isNull(Array.find(txids, func (t: Txid): Bool{ t == _txid }))){
                    icdex_pendingOrders := Trie.put(icdex_pendingOrders, keyb(_account), Blob.equal, Tools.arrayAppend(txids, [_txid])).0;
                    return txids.size() + 1;
                }else{
                    return txids.size();
                };
            };
            case(_){
                icdex_pendingOrders := Trie.put(icdex_pendingOrders, keyb(_account), Blob.equal, [_txid]).0;
                return 1;
            };
        };
    };

    private func _delPendingOrder(_account: AccountId, _txid: Txid) : Nat{
        switch(Trie.get(icdex_pendingOrders, keyb(_account), Blob.equal)){
            case(?(txids)){
                let txidsNew = Array.filter(txids, func (t: Txid): Bool{ t != _txid });
                if (txidsNew.size() > 0){
                    icdex_pendingOrders := Trie.put(icdex_pendingOrders, keyb(_account), Blob.equal, txidsNew).0;
                    return txidsNew.size();
                }else{
                    icdex_pendingOrders := Trie.remove(icdex_pendingOrders, keyb(_account), Blob.equal).0;
                    return 0;
                };
            };
            case(_){ return 0; };
        };
    };

    private func _isPending(_txid: Txid): Bool{
        switch(Trie.get(icdex_orders, keyb(_txid), Blob.equal)){
            case(?(order)){
                return order.status == #Pending;
            };
            case(_){};
        };
        return false;
    };

    private func _isClosed(_txid: Txid): Bool{
        switch(Trie.get(icdex_orders, keyb(_txid), Blob.equal)){
            case(?(order)){
                return order.status == #Closed;
            };
            case(_){ return true };
        };
    };

    // private func _isCompleted(_txid: Txid): Bool{
    //     switch(Trie.get(icdex_orders, keyb(_txid), Blob.equal)){
    //         case(?(order)){
    //             return order.status == #Closed or order.status == #Cancelled;
    //         };
    //         case(_){ return true };
    //     };
    // };

    // init
    private func _init() : async* (){
        if (token0_ == Principal.fromText("ryjl3-tyaaa-aaaaa-aaaba-cai")){
            token0Std := #icrc1;
            token0Symbol := "ICP";
        } else {
            try {
                let token0: DRC20.Self = actor(Principal.toText(_token0Canister()));
                let strStd = await token0.standard();
                if (Text.contains(strStd, #text("drc20"):Text.Pattern)){
                    token0Symbol := await token0.drc20_symbol();
                    token0Std := #drc20;
                };
            } catch(e){
                try {
                    let token0: ICRC1.Self = actor(Principal.toText(_token0Canister()));
                    let stds = await token0.icrc1_supported_standards();
                    token0Symbol := await token0.icrc1_symbol();
                    token0Std := #icrc1;
                } catch(e){
                    /*try{
                        let token0: DIP20.Self = actor(Principal.toText(_token0Canister()));
                        token0Symbol := await token0.symbol();
                        token0Std := #dip20;
                    } catch(e){
                        let token0: Ledger.Self = actor(Principal.toText(_token0Canister()));
                        token0Symbol := (await token0.symbol()).symbol;
                        token0Std := #ledger;
                    };*/
                    assert(false);
                };
            };
        };
        if (token1_ == Principal.fromText("ryjl3-tyaaa-aaaaa-aaaba-cai")){
            token1Std := #icrc1;
            token1Symbol := "ICP";
        } else {
            try {
                let token1: DRC20.Self = actor(Principal.toText(_token1Canister()));
                let strStd = await token1.standard();
                if (Text.contains(strStd, #text("drc20"):Text.Pattern)){
                    token1Std := #drc20;
                    token1Symbol := await token1.drc20_symbol();
                };
            } catch(e){
                try {
                    let token1: ICRC1.Self = actor(Principal.toText(_token1Canister()));
                    let stds = await token1.icrc1_supported_standards();
                    token1Std := #icrc1;
                    token1Symbol := await token1.icrc1_symbol();
                } catch(e){
                    /*try {
                        let token1: DIP20.Self = actor(Principal.toText(_token1Canister()));
                        token1Std := #dip20;
                        token1Symbol := await token1.symbol();
                    } catch(e){
                        let token1: Ledger.Self = actor(Principal.toText(_token1Canister()));
                        token1Std := #ledger;
                        token1Symbol := (await token1.symbol()).symbol;
                    };*/
                    assert(false);
                };
            };
        };
        initialized := true;
    };

    // Escrow funds into the trading pair canister for new order.
    // Combined handle of tunnel and pool models
    private func _txPrepare(_side:{#token0; #token1}, _icrc1Account: ICRC1.Account, _txid: Txid, _orderAmount: Amount, _nonce: Nonce) : async* ([Toid], amountLockedInPool: Amount){
        var _fee : Nat = 0;
        var _canisterId : Principal = Principal.fromActor(this);
        var _std : Types.TokenStd = #drc20;
        if (_side == #token0){
            _fee := _getFee0();
            _canisterId := _token0Canister();
            _std := token0Std;
        }else if (_side == #token1){
            _fee := _getFee1();
            _canisterId := _token1Canister();
            _std := token1Std;
        };
        let _account = Tools.principalToAccountBlob(_icrc1Account.owner, _toSaNat8(_icrc1Account.subaccount));
        let _txAccount = _getPairAccount(_txid);
        var poolUserBalance: Nat = 0;
        var valueFromPoolUserBalance: Nat = 0; // 1: funds from pool
        var txBalance: Nat = 0;
        var valueFromTxBalance: Nat = 0; // 2.1: funds from txAccount
                                    // 2.2: funds from transferFrom()
        var toTxAccount = _txAccount;
        var toTxICRC1Account = {owner = Principal.fromActor(this); subaccount = ?_txid};
        let sa_pool = Blob.fromArray(sa_zero);
        let mode = _exchangeMode(_account, ?_nonce);
        let isKeptFunds = _isKeepingBalanceInPair(_account);
        if (mode == #PoolMode){
            toTxAccount := Tools.principalToAccountBlob(Principal.fromActor(this), ?sa_zero);
            toTxICRC1Account := {owner = Principal.fromActor(this); subaccount = ?sa_pool};
        };
        if (isKeptFunds){
            let accBalance = _getAccountBalance(_account);
            if (_side == #token0){
                poolUserBalance := accBalance.token0.available;
            }else{
                poolUserBalance := accBalance.token1.available;
            };
            valueFromPoolUserBalance := Nat.min(poolUserBalance, _orderAmount);
            if (mode == #TunnelMode and valueFromPoolUserBalance > _fee){
                poolUserBalance := Nat.min(Nat.sub(poolUserBalance, _fee), _orderAmount);
            }else if (mode == #TunnelMode and valueFromPoolUserBalance <= _fee){
                poolUserBalance := 0;
            };
        };
        if (valueFromPoolUserBalance < _orderAmount and (_std == #icrc1 or _std == #icp)){ // For compatibility with tokens without ICRC2
            if (_side == #token0){
                txBalance := await* _getBaseBalance(_txid);
            }else{
                txBalance := await* _getQuoteBalance(_txid);
            };
            valueFromTxBalance := Nat.min(txBalance, Nat.sub(_orderAmount, valueFromPoolUserBalance));
            if (mode == #PoolMode and valueFromTxBalance > _fee){ // will transfer tokens to PoolAccount
                valueFromTxBalance := Nat.min(Nat.sub(txBalance, _fee), Nat.sub(_orderAmount, valueFromPoolUserBalance));
            }else if (mode == #PoolMode and valueFromTxBalance <= _fee){
                valueFromTxBalance := 0;
            };
        };
        var tempLockedAmount : Nat = 0;
        // transferFrom
        if (valueFromPoolUserBalance + valueFromTxBalance < _orderAmount){ 
            let v = Nat.sub(_orderAmount, valueFromPoolUserBalance + valueFromTxBalance);
            try{
                await* _transferFrom(_canisterId, _icrc1Account, toTxICRC1Account, v, ?_txid);
                if (mode == #PoolMode){
                    ignore _addAccountBalance(_account, _side, #locked(v));
                    tempLockedAmount += v;
                };
            }catch(e){
                throw Error.reject("408: Insufficient token balance. " # Error.message(e));
            };
        };
        // from: pool -> to: pool / TxAccount
        if (valueFromPoolUserBalance > 0){
            let accBalance = _getAccountBalance(_account); // re-check balance
            if (_side == #token0){
                poolUserBalance := accBalance.token0.available;
            }else{
                poolUserBalance := accBalance.token1.available;
            };
            if ( (mode == #PoolMode and valueFromPoolUserBalance > poolUserBalance) or 
            (mode == #TunnelMode and valueFromPoolUserBalance + _fee > poolUserBalance) ){
                if (tempLockedAmount > 0){
                    ignore _unlockAccountBalance(_account, _side, tempLockedAmount);
                    tempLockedAmount := 0;
                };
                throw Error.reject("408: Insufficient token balance!");
            };
            if (mode == #PoolMode){
                ignore _lockAccountBalance(_account, _side, valueFromPoolUserBalance);
                tempLockedAmount += valueFromPoolUserBalance;
            }else if (mode == #TunnelMode){
                try{
                    ignore _subAccountBalance(_account, _side, #available(valueFromPoolUserBalance + _fee));
                    await* _tokenTransfer(_canisterId, sa_pool, toTxICRC1Account, valueFromPoolUserBalance, ?_txid);
                }catch(e){
                    ignore _addAccountBalance(_account, _side, #available(valueFromPoolUserBalance + _fee));
                    if (tempLockedAmount > 0){
                        ignore _unlockAccountBalance(_account, _side, tempLockedAmount);
                        tempLockedAmount := 0;
                    };
                    throw Error.reject("407: Token transfer error: " # Error.message(e));
                };
            };
        };
        // from: TxAccount -> to: pool
        if (valueFromTxBalance > 0){ // For compatibility with tokens without ICRC2
            if (mode == #PoolMode){
                try{
                    await* _tokenTransfer(_canisterId, _txid, toTxICRC1Account, valueFromTxBalance, ?_txid);
                    ignore _addAccountBalance(_account, _side, #locked(valueFromTxBalance));
                }catch(e){
                    if (tempLockedAmount > 0){
                        ignore _unlockAccountBalance(_account, _side, tempLockedAmount);
                        tempLockedAmount := 0;
                    };
                    throw Error.reject("407: Token transfer error: " # Error.message(e));
                };
            }else{
                // No transfer required
            };
        };
        // fallback
        if (valueFromTxBalance > 0 and mode == #PoolMode){
            valueFromTxBalance += _fee;
        };
        if (txBalance > valueFromTxBalance + _fee and not(_isFallbacking(_txid))){ // Fix fallback conflict
            _putFallbacking(_txid);
            let saga = _getSaga();
            let toid = saga.create("fallback_pretrade", #Backward, ?_txid, null);
            ignore _sendToken(false, _side, toid, _txid, [], [_icrc1Account], [Nat.sub(txBalance, valueFromTxBalance)], ?_txid, null);
            saga.close(toid);
            return ([toid], tempLockedAmount);
        }else{
            return ([], tempLockedAmount);
        };
    };

    // New order funding preparation function. Prevents too many failed transactions and does not use ICTC processing.
    // Note: Check prepared balances only after the order has been recorded. (Prevents asynchronous fallback)
    private func _prepareBalance(icrc1Account: ICRC1.Account, txid: Txid, order: OrderPrice, nonce: Nonce) : async* ([Toid], lockedAmount0: Amount, lockedAmount1: Amount){
        let account = Tools.principalToAccountBlob(icrc1Account.owner, _toSaNat8(icrc1Account.subaccount));
        var logToids : [Toid] = [];
        var lockedAmount0: Nat = 0;
        var lockedAmount1: Nat = 0;
        if (OrderBook.side(order) == #Buy){
            try{
                let (toids, lockedAmount) = await* _txPrepare(#token1, icrc1Account, txid, OrderBook.amount(order), nonce);
                logToids := Tools.arrayAppend(logToids, toids);
                lockedAmount1 := lockedAmount;
            }catch(e){
                throw Error.reject("420: internal call error: "# Error.message(e)); 
            };
        }else{ //#Sell
            try{
                let (toids, lockedAmount) = await* _txPrepare(#token0, icrc1Account, txid, OrderBook.quantity(order), nonce);
                logToids := Tools.arrayAppend(logToids, toids);
                lockedAmount0 := lockedAmount;
            }catch(e){
                throw Error.reject("420: internal call error: "# Error.message(e)); 
            };
        };
        return (logToids, lockedAmount0, lockedAmount1);
    };

    // Conditional filter function for new orders
    private func _traderFilter(account: AccountId, txid: Txid, order: OrderPrice, _orderType: OrderType, expirationDuration: Int, data: Blob) : ?TradingResult{
        if (data.size() > 2048){
            return ?#err({ code=#UndefinedError; message="410: The length of _data must be less than 2 KB"; });
        };
        if (_pendingSize(?account) >= _maxPendings(account) and _orderType == #LMT and not(icdex_debug)){
            return ?#err({code=#UndefinedError; message="411: The maximum number of pending status orders allowed per account is "# Nat.toText(_maxPendings(account));});
        };
        if (_pendingSize(null) >= maxTotalPendingNumber and _orderType == #LMT and 
        ((OrderBook.side(order) == #Sell and order.price > icdex_lastPrice.price*105/100) or (OrderBook.side(order) == #Buy and order.price < icdex_lastPrice.price*95/100))){
            return ?#err({code=#UndefinedError; message="412: The maximum total number of pending orders in the system is "# Nat.toText(maxTotalPendingNumber) #". Now only MKT order, or order quoted in the range of +/- 5% of the latest price is accepted.";});
        };
        if (OrderBook.quantity(order) > 0 and OrderBook.quantity(order) / setting.UNIT_SIZE * setting.UNIT_SIZE != OrderBook.quantity(order) ){
            return ?#err({code=#InvalidAmount; message="402: Invalid Amount";});
        };
        if (OrderBook.side(order) == #Buy and _orderType != #MKT and OrderBook.quantity(order) * order.price / setting.UNIT_SIZE != OrderBook.amount(order) ){
            return ?#err({code=#InvalidAmount; message="402: Invalid Amount";});
        };
        if (_orderType != #MKT and OrderBook.quantity(order) * order.price / setting.UNIT_SIZE <= _getFee1() ){
            return ?#err({code=#InvalidAmount; message="402: Invalid Amount";});
        };
        if (OrderBook.side(order) == #Buy and OrderBook.amount(order) <= _getFee1() ){
            return ?#err({code=#InvalidAmount; message="402: Invalid Amount";});
        };
        // if (_orderType == #MKT and order.price > 0){
        //     return ?#err({code=#UndefinedError; message="403: Unavailable Price";});
        // };
        if (Option.isSome(Trie.get(icdex_orders, keyb(txid), Blob.equal)) /*or  // The txid should not exist in order list
        OrderBook.inOrderBook(icdex_orderBook, txid)*/){ // The txid should not exist in the order book
            return ?#err({code=#UndefinedError; message="413: Order Duplicate";});
        }; 
        // if (_inCompSettlement(account)){ /*Competitions*/
        //     return ?#err({code=#UndefinedError; message="416: Trading competition participants are suspended from trading during the settlement period. Please wait until the settlement is completed.";});
        // };
        if (expirationDuration < 1800*ns_ or expirationDuration > ExpirationDuration){
            return ?#err({code=#UndefinedError; message="404: The parameter `_expiration` is invalid and needs to be between 1_800_000_000_000 and "# Int.toText(ExpirationDuration) #" nanoseconds.";});
        };
        return null;
    };

    // Handle order matching fills on ICTC
    private func _ictcForFilled(txid: Txid, toid: Toid, icrc1Account: ICRC1.Account, nonce: Nonce, filled: [OrderBook.OrderFilled], _brokerage: ?{broker: Principal; rate: Float}) : (){
        var preTtids : [SagaTM.Ttid] = [];
        var tokenAmount : Nat = 0;
        var currencyAmount : Nat = 0;
        let account = Tools.principalToAccountBlob(icrc1Account.owner, _toSaNat8(icrc1Account.subaccount));
        for (filled in filled.vals() ){ // Array.reverse {counterparty: Txid; token0Value: BalanceChange; token1Value: BalanceChange;}
            //let makerAccountPrincipal = _orderPrincipal(filled.counterparty);
            // ___txid1 := txid;
            // ___txid2 := filled.counterparty;
            var makerIcrc1Account = _orderIcrc1Account(filled.counterparty);
            // ___account := ?makerIcrc1Account;
            let (makerAccount, makerNonce) = _makerFilled(txid, filled, toid);
            // if (_inCompetition(makerAccount)){ /*Competitions*/
            //     makerIcrc1Account := {owner = Principal.fromActor(this); subaccount = _toOptSub(_getCompAccountSa(makerAccount))};
            // };
            //let makerTxAccount = _getPairAccount(filled.counterparty);
            let taker_mode = _exchangeMode(account, ?nonce);
            let taker_isKeptFunds = _isKeepingBalanceInPair(account);
            let maker_mode = _exchangeMode(makerAccount, ?makerNonce);
            let maker_isKeptFunds = _isKeepingBalanceInPair(makerAccount);
            switch(filled.token0Value){ //token
                case(#DebitRecord(value)){ // Sell  (send to maker)
                    tokenAmount += value;
                    if (value > _getFee0()){
                        let ttids = _sendToken0(true, toid, txid, [], [makerIcrc1Account], [value], ?txid, null);
                        preTtids := Tools.arrayAppend(preTtids, ttids);
                        var fee = _getFee0();
                        if (taker_mode == #PoolMode and maker_isKeptFunds){
                            fee := 0;
                        };
                        _update(filled.counterparty, null, null, null, ?{gas0=fee; gas1=0}, null, null, null);
                        _hook_fill(filled.counterparty, #Buy, Nat.sub(value, fee), 0);
                    };
                    _hook_fill(txid, #Sell, value, 0);
                };
                case(#CreditRecord(value)){ // Buy   (send to taker) 
                    tokenAmount += value;
                    if (value > _getFee0()){
                        let (amount, makerFee, icdexFee, brokerFee) = _chargeFee(makerAccount/*_counterpartyAccount(filled.counterparty)*/, value, false, _brokerage);
                        var transferBatch_to : [ICRC1.Account] = [icrc1Account];
                        var transferBatch_value : [Nat] = [amount];
                        // let ttids = _sendToken0(true, toid, filled.counterparty, [], [icrc1Account], [amount], ?filled.counterparty, null);
                        // preTtids := Tools.arrayAppend(preTtids, ttids);
                        if (makerFee > _getFee0()){ // makerTxAccount -> makerAccount
                            transferBatch_to := Tools.arrayAppend(transferBatch_to, [makerIcrc1Account]);
                            transferBatch_value := Tools.arrayAppend(transferBatch_value, [makerFee]);
                            // let ttids = _sendToken0(true, toid, filled.counterparty, [], [makerIcrc1Account], [makerFee], ?filled.counterparty, null);
                            // preTtids := Tools.arrayAppend(preTtids, ttids);
                            let makerAccountId = Tools.principalToAccountBlob(makerIcrc1Account.owner, _toSaNat8(makerIcrc1Account.subaccount));
                            if (_onlyVipMaker(makerAccountId)){
                                _updateMakerData(makerAccountId, {value0=value; value1=0;}, {value0=makerFee; value1=0;}, 0, 1);
                            };
                        };
                        if (icdexFee > _getFee0()){  // makerTxAccount -> router
                            transferBatch_to := Tools.arrayAppend(transferBatch_to, [{owner = icdexRouter; subaccount = null}]);
                            transferBatch_value := Tools.arrayAppend(transferBatch_value, [icdexFee]);
                            // let ttids = _sendToken0(true, toid, filled.counterparty, [], [{owner = icdexRouter; subaccount = null}], [icdexFee], ?filled.counterparty, null);
                            // preTtids := Tools.arrayAppend(preTtids, ttids);
                        };
                        if (brokerFee > _getFee0()){
                            switch(_brokerage){
                                case(?(b)){
                                    transferBatch_to := Tools.arrayAppend(transferBatch_to, [{owner = b.broker; subaccount = null}]);
                                    transferBatch_value := Tools.arrayAppend(transferBatch_value, [brokerFee]);
                                    _updateBrokerData(Tools.principalToAccountBlob(b.broker, null), {value0=value; value1=0;}, {value0=brokerFee; value1=0;}, b.rate);
                                };
                                case(_){};
                            };
                        };
                        let ttids = _sendToken0(true, toid, filled.counterparty, [], transferBatch_to, transferBatch_value, ?filled.counterparty, null);
                        preTtids := Tools.arrayAppend(preTtids, ttids);
                        var fee = _getFee0();
                        if (maker_mode == #PoolMode and taker_isKeptFunds){
                            fee := 0;
                        };
                        _update(txid, null, ?toid, null, ?{gas0=fee; gas1=0}, ?{fee0=Nat.sub(value, amount); fee1=0}, null, null);
                        _update(filled.counterparty, null, null, null, null, ?{fee0 = -makerFee; fee1=0}, null, null);
                        _hook_fill(txid, #Buy, Nat.sub(value, fee), 0);
                        _hook_fill(filled.counterparty, #Sell, value, 0);
                    };
                };
                case(_){};
            };
            switch(filled.token1Value){ //currency
                case(#DebitRecord(value)){ // Buy  
                    currencyAmount += value;
                    if (value > _getFee1()){
                        let ttids = _sendToken1(true, toid, txid, [], [makerIcrc1Account], [value], ?txid, null);
                        preTtids := Tools.arrayAppend(preTtids, ttids);
                        var fee = _getFee1();
                        if (taker_mode == #PoolMode and maker_isKeptFunds){
                            fee := 0;
                        };
                        _update(filled.counterparty, null, null, null, ?{gas0=0; gas1=fee}, null, null, null);
                        _hook_fill(filled.counterparty, #Sell, 0, Nat.sub(value, fee));
                    };
                    _hook_fill(txid, #Buy, 0, value);
                };
                case(#CreditRecord(value)){ //Sell  (send to taker) 
                    currencyAmount += value;
                    if (value > _getFee1()){
                        let (amount, makerFee, icdexFee, brokerFee) = _chargeFee(makerAccount/*_counterpartyAccount(filled.counterparty)*/, value, true, _brokerage);
                        var transferBatch_to : [ICRC1.Account] = [icrc1Account];
                        var transferBatch_value : [Nat] = [amount];
                        // let ttids = _sendToken1(true, toid, filled.counterparty, [], [icrc1Account], [amount], ?filled.counterparty, null);
                        // preTtids := Tools.arrayAppend(preTtids, ttids);
                        if (makerFee > _getFee1()){
                            transferBatch_to := Tools.arrayAppend(transferBatch_to, [makerIcrc1Account]);
                            transferBatch_value := Tools.arrayAppend(transferBatch_value, [makerFee]);
                            // let ttids = _sendToken1(true, toid, filled.counterparty, [], [makerIcrc1Account], [makerFee], ?filled.counterparty, null);
                            // preTtids := Tools.arrayAppend(preTtids, ttids);
                            let makerAccountId = Tools.principalToAccountBlob(makerIcrc1Account.owner, _toSaNat8(makerIcrc1Account.subaccount));
                            if (_onlyVipMaker(makerAccountId)){
                                _updateMakerData(makerAccountId, {value0=0; value1=value;}, {value0=0; value1=makerFee;}, 0, 1);
                            };
                        };
                        if (icdexFee > _getFee1()){
                            transferBatch_to := Tools.arrayAppend(transferBatch_to, [{owner = icdexRouter; subaccount = null}]);
                            transferBatch_value := Tools.arrayAppend(transferBatch_value, [icdexFee]);
                            // let ttids = _sendToken1(true, toid, filled.counterparty, [], [{owner = icdex_; subaccount = null}], [icdexFee], ?filled.counterparty, null);
                            // preTtids := Tools.arrayAppend(preTtids, ttids);
                        };
                        if (brokerFee > _getFee1()){
                            switch(_brokerage){
                                case(?(b)){
                                    transferBatch_to := Tools.arrayAppend(transferBatch_to, [{owner = b.broker; subaccount = null}]);
                                    transferBatch_value := Tools.arrayAppend(transferBatch_value, [brokerFee]);
                                    _updateBrokerData(Tools.principalToAccountBlob(b.broker, null), {value0=0; value1=value;}, {value0=0; value1=brokerFee;}, b.rate);
                                };
                                case(_){};
                            };
                        };
                        let ttids = _sendToken1(true, toid, filled.counterparty, [], transferBatch_to, transferBatch_value, ?filled.counterparty, null);
                        preTtids := Tools.arrayAppend(preTtids, ttids);
                        var fee = _getFee1();
                        if (maker_mode == #PoolMode and taker_isKeptFunds){
                            fee := 0;
                        };
                        _update(txid, null, ?toid, null, ?{gas0=0; gas1=fee}, ?{fee0=0; fee1=Nat.sub(value,amount)}, null, null);
                        _update(filled.counterparty, null, null, null, null, ?{fee0=0; fee1 = -makerFee}, null, null);
                        _hook_fill(txid, #Sell, 0, Nat.sub(value, fee));
                        _hook_fill(filled.counterparty, #Buy, 0, value);
                    };
                };
                case(_){};
            };
            ignore _refund(toid, filled.counterparty, []);
            _saveOrderRecord(filled.counterparty, false, false);
            if (_isClosed(filled.counterparty)){
                _hook_close(filled.counterparty);
            };
        };
        _updateTotalVol(tokenAmount, currencyAmount);
        _updateVol(account, tokenAmount, currencyAmount);
        // refund
        ignore _refund(toid, txid, preTtids); // push to ICTC
    };

    // Core function for trading
    private func _trade(_caller:Principal, _order: OrderPrice, _orderType: OrderType, _expiration: ?PeriodNs, _nonce: ?Nonce, _sa: ?Sa, _data: ?Data,
    _brokerage: ?{broker: Principal; rate: Float}, _quickly: Bool) : async* TradingResult{
        let __start = Time.now();
        assert(mode == #GeneralTrading);
        if (not(initialized)){ await* _init(); await* _getGas(true); };
        let prePrice = icdex_lastPrice.price;
        var order = _order;
        if (OrderBook.side(order) == #Buy and OrderBook.quantity(order) > 0 and OrderBook.amount(order) == 0){
            let token1Amount = OrderBook.quantity(order) * order.price / setting.UNIT_SIZE;
            order := {quantity = #Buy((OrderBook.quantity(order), token1Amount)); price = order.price };
        };
        var mktOrderPriceLimit: Nat = 0;
        if (_orderType == #MKT and order.price > 0){
            mktOrderPriceLimit := order.price;
            order := {quantity = order.quantity; price = 0 };
        };
        let icrc1Account = { owner = _caller; subaccount = _toSaBlob(_sa);};
        let account = Tools.principalToAccountBlob(_caller, _sa);
        let accountPrincipal = _caller; // _orderPrincipal(txid)
        var nonce: Nat = Option.get(_nonce, _getNonce(account));
        let index = icdex_index;
        let txid = drc205.generateTxid(Principal.fromActor(this), account, nonce);
        let txAccount = _getPairAccount(txid);
        let data = Option.get(_data, Blob.fromArray([]));
        let expirationDuration =  Option.get(_expiration, ExpirationDuration);
        // 1. prepare
        if (_inIDO() and not(_filterIDOConditions(account, OrderBook.side(order), _orderType, order.price, OrderBook.quantity(order)))){
            return #err({ code=#UndefinedError; message="415: You do not have permission to place orders in this way."; });
        };
        if(nonce != _getNonce(account)){ // check nonce
            return #err({code=#NonceError; message="401: Nonce Error. The nonce should be "#Nat.toText(_getNonce(account));});
        }; 
        switch(_traderFilter(account, txid, order, _orderType, expirationDuration, data)){
            case(?err){ return err; };
            case(_){};
        };
        if (_isFallbacking(txid)){ // fixed an atomicity issue.
            return #err({code=#NonceError; message="417: This txid is fallbacking.";});
        };
        // put order
        var logToids : [Nat] = [];
        var expiration = Time.now() + expirationDuration;
        if (_inIDO() and _isIDOFunderOrder(_caller)){
            expiration := IDOSetting_.IDOClosingTime;
        };
        var tradingOrder: TradingOrder = {
            account = account;
            icrc1Account = ?icrc1Account;
            txid = txid;
            orderType = _orderType;
            orderPrice = order;
            time = Time.now();
            expiration = expiration;
            remaining = order;
            toids = [];
            filled = [];  
            status = #Todo;
            refund = (0, 0, 0);
            gas = {gas0=0; gas1=0};
            fee = {fee0=0; fee1=0};
            index = index;
            nonce = nonce;
            data = _data;
        };
        icdex_orders := Trie.put(icdex_orders, keyb(txid), Blob.equal, tradingOrder).0;
        //trieLog := List.push((txid, "put", Trie.isValid(icdex_orders, true)), trieLog);
        _addNonce(account); // update nonce here
        if (Time.now() > lastExpiredTime + 5*ns_ and _pendingSize(null) < maxTotalPendingNumber){ 
            lastExpiredTime := Time.now();
            _clear();
            _expire();
        };
        // check balance
        var lockedAmount0: Nat = 0;
        var lockedAmount1: Nat = 0;
        try{
            let (toids, lockedTemp0, lockedTemp1) = await* _prepareBalance(icrc1Account, txid, order, nonce);
            logToids := Tools.arrayAppend(logToids, toids);
            lockedAmount0 := lockedTemp0;
            lockedAmount1 := lockedTemp1;
        }catch(e){
            _moveToFailedOrder(txid, lockedAmount0, lockedAmount1);
            try{
                let r = await* _fallback(icrc1Account, txid, null);
            }catch(e){};
            return #err({code=#InsufficientBalance; message=Error.message(e);});
        };
        // 2. orderbook
        let res = OrderBook.trade(icdex_orderBook, txid, order, _orderType, setting.UNIT_SIZE); // {ob; filled; remaining; isPending; fillPrice}
        let lastFillPrice = switch(res.fillPrice){ case(?fp){ fp.price }; case(_){ 0 } };
        if (_orderType == #MKT and mktOrderPriceLimit > 0 and lastFillPrice > 0 and (
            (OrderBook.side(order) == #Buy and lastFillPrice > mktOrderPriceLimit) or (OrderBook.side(order) == #Sell and lastFillPrice < mktOrderPriceLimit)
        )){
            _moveToFailedOrder(txid, lockedAmount0, lockedAmount1);
            try{
                let r = await* _fallback(icrc1Account, txid, null);
            }catch(e){};
            return #err({code=#UndefinedError; message="403: The order failed because the price did not meet the limit price you specified.";});
        }else if (_orderType == #MKT and (
            (OrderBook.side(order) == #Buy and OrderBook.amount(res.remaining) > Nat.max(lastFillPrice * setting.UNIT_SIZE, _getFee1())) or (OrderBook.side(order) == #Sell and OrderBook.quantity(res.remaining) >= Nat.max(setting.UNIT_SIZE, _getFee0()))
        )){
            _moveToFailedOrder(txid, lockedAmount0, lockedAmount1);
            try{
                let r = await* _fallback(icrc1Account, txid, null);
            }catch(e){};
            return #err({code=#UndefinedError; message="409: Insufficient liquidity and the order was canceled.";});
        }else{
            icdex_orderBook := res.ob; 
        };
        let countFilled = res.filled.size();
        var status : TradingStatus = #Pending;
        if (OrderBook.quantity(res.remaining) >= Nat.max(setting.UNIT_SIZE, _getFee0()) and _orderType == #FOK){
            status := #Cancelled;
        }else if (not(res.isPending)){
            status := #Closed;
        }else{ // #Pending
            _pushSortedTxids(txid, expiration);
            ignore _addPendingOrder(account, txid);
        };
        // 3. update data
        let saga = _getSaga();
        var toid : Nat = 0;
        if (status != #Pending or countFilled > 0){
            toid := saga.create("trade", #Forward, ?txid, null);
            logToids := Tools.arrayAppend(logToids, [toid]);
        };
        tradingOrder := {
            account = account;
            icrc1Account = ?icrc1Account;
            txid = txid;
            orderType = _orderType;
            orderPrice = order;
            time = Time.now();
            expiration = expiration;
            remaining = res.remaining;
            toids = logToids;
            filled = res.filled;
            status = status;
            refund = (0, 0, 0);
            gas = {gas0=0; gas1=0};
            fee = {fee0=0; fee1=0};
            index = index;
            nonce = nonce;
            data = _data;
        };
        icdex_orders := Trie.put(icdex_orders, keyb(txid), Blob.equal, tradingOrder).0;
        if (status == #Closed or status == #Cancelled){
            _pushToClearing(txid);
        };
        //trieLog := List.push((txid, "put", Trie.isValid(icdex_orders, true)), trieLog);
        icdex_priceWeighted := _getPriceWeighted(icdex_priceWeighted);
        icdex_lastPrice := Option.get(res.fillPrice, icdex_lastPrice);
        icdex_klines2 := OrderBook.putBatch(icdex_klines2, res.filled, setting.UNIT_SIZE);
        _putLatestFilled(txid, res.filled, OrderBook.side(order));
        if (_inIDO() and status == #Closed){
            _updateIDOData(account, OrderBook.quantity(order) - OrderBook.quantity(res.remaining));
        };
        // 4. ictc transaction
        if (toid > 0){
            _ictcForFilled(txid, toid, icrc1Account, nonce, res.filled, _brokerage);
            // finish
            saga.close(toid);
        };
        if (_onlyVipMaker(account)){
            _updateMakerData(account, {value0=0; value1=0}, {value0=0; value1=0}, 1, 0);
        };
        if (_isClosed(txid)){
            _hook_close(txid);
        };
        // record storage
        _saveOrderRecord(txid, true, false);
        //await drc205.store();
        if (not(_quickly)){
            await* _callDrc205Store(false, false); // 0 ~ 4
        };
        switch(_brokerage){
            case(?(b)){
                let b_toid = _autoWithdraw({owner = b.broker; subaccount = null}, null);
            };
            case(_){};
        };
        let p_toid = _autoWithdraw({owner = icdexRouter; subaccount = null}, null);
        if (not(_quickly)){
            if (countFilled > 0 and enableStrategyOrders){
                if (icdex_debug){
                    await _hook_stoWorktop(null, ?(if (icdex_lastPrice.price >= prePrice){ #Buy }else{ #Sell })); 
                }else{
                    let f = _hook_stoWorktop(null, ?(if (icdex_lastPrice.price >= prePrice){ #Buy }else{ #Sell }));
                };
            };
            await* _ictcSagaRun(toid, false); // >= 10
        };
        lastExecutionDuration := Time.now() - __start;
        if (lastExecutionDuration > maxExecutionDuration) { maxExecutionDuration := lastExecutionDuration };
        return #ok({ txid = txid; filled = res.filled; status = status; });
    };

    // Cancel all orders. 1. Owner (DAO) can cancel all orders; 2. A trader can cancel all his own orders.
    private func _cancelAll(_caller: Principal, _args: {#management: ?AccountId; #self_sa: ?Sa}, _side: ?OrderBook.OrderSide) : async* (){
        var orders : Trie.Trie<Txid, TradingOrder> = Trie.empty(); 
        switch(_args){
            case(#management(?(account))){
                assert(_onlyOwner(_caller));
                orders := _accountPendingOrders(?account);
            };
            case(#management(null)){
                assert(_onlyOwner(_caller));
                orders := icdex_orders;
            };
            case(#self_sa(_sa)){
                if (not(_notPaused(?_caller) and initialized)){
                    throw Error.reject("400: Trading pair has been suspended."); 
                };
                let account = Tools.principalToAccountBlob(_caller, _sa);
                orders := _accountPendingOrders(?account);
            };
        };
        switch(_side){
            case(?(side)){
                orders := Trie.filter(orders, func (k: Txid, v: TradingOrder): Bool{ OrderBook.side(v.orderPrice) == side });
            };
            case(_){};
        };
        let saga = _getSaga();
        let toid = saga.create("cancelAll", #Forward, null, null);
        var ttids : [Nat] = [];
        for ((txid, order) in Trie.iter(orders)){
            ttids := Tools.arrayAppend(ttids, _cancel(toid, txid, _side));
        };
        saga.close(toid);
        if (ttids.size() == 0){
            ignore saga.doneEmpty(toid);
        };
        // drc205; 
        await* _callDrc205Store(false, false);
        // ictc
        await* _ictcSagaRun(0, false);
    };

    // 24-hour statistics
    // The `price` in the return value indicates how much token1 (smallest_unit) is needed to purchase 1 token0 (smallest_unit).
    private func _24h() : {price: Float; change24h: Float; vol24h: Vol;}{
        let price = _natToFloat(icdex_lastPrice.price) / _natToFloat(setting.UNIT_SIZE);
        var prePrice = price;
        let kBars = OrderBook.getK(icdex_klines2, 300); // 5min Bars
        let kidFrom = Nat.sub(Int.abs(Time.now()) / ns_, 24 * 3600) / 300;
        var vol24h : Vol = {value0=0; value1=0;};
        label brk for (kBar in kBars.vals()){
            if (kBar.kid >= kidFrom){
                vol24h := {value0 = vol24h.value0 + kBar.vol.value0; value1 = vol24h.value1 + kBar.vol.value1;};
            }else{
                prePrice := _natToFloat(kBar.close) / _natToFloat(setting.UNIT_SIZE);
                break brk;
            };
        };
        let change24h = (price - prePrice) / prePrice;
        return {price = price; change24h = change24h; vol24h = vol24h;};
    };

    /* ===========================
      Ordinary trading section
    ============================== */
    
    /// Initialization function. If it is not called explicitly, _init() will be called on the first trade.
    public shared func init() : async (){ 
        if (not(initialized)){ 
            await* _init(); 
            await* _getGas(true);
        }; 
    };

    /// @deprecated: This method will be deprecated. The getTxAccount() method will replace it.
    public query func prepare(_account: Address) : async (TxAccount, Nonce){ 
        if (not(initialized)){
            throw Error.reject("400: Trading pair has been suspended."); 
        };
        let res = _preCreateTx(_getAccountId(_account));
        return (res.1, res.2);
    };

    /// In tunnel mode, the trader gets the next order's nonce value, TxAccount, Txid.  
    /// Warning: This is a query function and direct adoption of the results returned by the call may be a security risk. 
    ///     You need to use account and nonce to perform local calculations according to the generateTxid() method in DRC205 
    ///     and verify the TxAccount address.
    public query func getTxAccount(_account: Address) : async (ICRC1.Account, TxAccount, Nonce, Txid){ 
        if (not(initialized)){
            throw Error.reject("400: Trading pair has been suspended."); 
        };
        let res = _preCreateTx(_getAccountId(_account));
        return res;
    };
    
    /// Generic trade method that do not support broker
    ///
    /// Arguments:
    /// - orderPrice: OrderPrice. 
    ///     Type OrderPrice = { quantity: {#Buy: (Quantity, Amount); #Sell: Quantity; }; price: Price; }
    ///     - quantity: Orders are divided into #Buy and #Sell depending on the Side. the quantity must be an integer multiple of UNIT_SIZE.
    ///         - #Buy: Specify the number of token0 to be purchased and the amount of token1 to be used for the purchase. token1 is DebitToken.
    ///         - #Sell: Specify the number of tokens0 to be sold. token0 is DebitToken.
    ///     - price: How much token1 (smallest units) are needed to purchase UNIT_SIZE token0 (smallest units). Orders may be filled 
    ///     at a better price than this. If MKT order type, price can be filled in 0 or a limit price.   
    ///         - If the order side is Buy, the variant {Buy = (x, y)} must be filled in. x indicates the amount (smallest_units) of token0 
    ///     to be purchased and y indicates the amount (smallest_units) of token1 to be paid. y is required for MKT orders and is optional 
    ///     for other types of orders.  
    ///         - If the order side is Sell, the variant {Sell = x } must be filled in. x indicates the amount (smallest_units) 
    ///     of token0 to be sold.  
    ///     Note: If the price of an MKT order is filled with 0, it means that any price is accepted. If price is filled with a 
    ///     non-zero value, it means that the slippage is controlled, e.g. the price limit for buy order is less than or equal to price 
    ///     and the price limit for sell order is greater than or equal to price.
    /// - orderType: OrderType. Order type. Such as: LMT, MKT, FAK, FOK.
    /// - expiration: ?PeriodNs. The order expiration duration (nanoseconds), which is generally 90 days by default.
    /// - nonce: ?Nonce. Optionally specify nonce value.
    /// - sa: ?Sa. Optionally specify the subaccount of the caller
    /// - data: ?Data. Optional Remark data, like memo.
    /// e.g. '(record{ quantity=variant{Sell=5_000_000}; price=10_000_000;}, variant{LMT}, null, null, null, null)'
    ///
    /// Returns:
    /// - res: TradingResult. Returns order result. The execution is asynchronous, Record the txid and you can check the order 
    ///     status through drc205_events() or statusByTxid().
    ///
    /// See the `UNIT_SIZE and Price` section for a description of PRICE and human-readable PRICE.
    public shared(msg) func trade(_order: OrderPrice, _orderType: OrderType, _expiration: ?PeriodNs, _nonce: ?Nonce, _sa: ?Sa, _data: ?Data) : async TradingResult{
        _checkICTCError();
        if (not(_notPaused(?msg.caller) and initialized)){
            return #err({code=#UndefinedError; message="400: Trading pair has been suspended.";}); 
        };
        let account = Tools.principalToAccountBlob(msg.caller, _sa);
        await* _checkOverload(?account);
        if (_tps(6, ?account).0 > 3){ 
            countRejections += 1; 
            return #err({code=#UndefinedError; message="406: Tip: Only one order can be made within 3 seconds.";}); 
        };
        try{
            countAsyncMessage += 1;
            let res = await* _trade(msg.caller, _order, _orderType, _expiration, _nonce, _sa, _data, null, false);
            countAsyncMessage -= Nat.min(1, countAsyncMessage);
            return res;
        }catch(e){
            countAsyncMessage -= Nat.min(1, countAsyncMessage);
            throw Error.reject("420: internal call error: "# Error.message(e)); 
        };
    };

    /// Generic trade method that support broker
    ///
    /// Arguments: (See the trade() method arguments, the following are additional arguments)
    /// - brokerage: ?{ broker: Principal; rate: Float; }. Set the broker’s receiving account (principal) and brokerage rates.
    ///
    /// Returns:
    /// - res: TradingResult. Returns order result. The execution is asynchronous, Record the txid and you can check the order 
    ///     status through drc205_events() or statusByTxid().
    public shared(msg) func trade_b(_order: OrderPrice, _orderType: OrderType, _expiration: ?PeriodNs, _nonce: ?Nonce, _sa: ?Sa, _data: ?Data,
    _brokerage: ?{broker: Principal; rate: Float}) : async TradingResult{
        _checkICTCError();
        if (not(_notPaused(?msg.caller) and initialized)){
            return #err({code=#UndefinedError; message="400: Trading pair has been suspended.";}); 
        };
        let account = Tools.principalToAccountBlob(msg.caller, _sa);
        await* _checkOverload(?account);
        let brokerageRate: Float = switch(_brokerage){ 
            case(?(b)){ b.rate };
            case(_){ 0.0 };
        };
        if (brokerageRate > 0.005){
            return #err({code=#UndefinedError; message="414: Brokerage rate should not be higher than 0.005 (0.5%).";}); 
        };
        if (_tps(6, ?account).0 > 3){ 
            countRejections += 1; 
            return #err({code=#UndefinedError; message="406: Tip: Only one order can be made within 3 seconds.";}); 
        };
        try{
            countAsyncMessage += 1;
            let res = await* _trade(msg.caller, _order, _orderType, _expiration, _nonce, _sa, _data, _brokerage, false);
            countAsyncMessage -= Nat.min(1, countAsyncMessage);
            return res;
        }catch(e){
            countAsyncMessage -= Nat.min(1, countAsyncMessage);
            throw Error.reject("420: internal call error: "# Error.message(e)); 
        };
    };

    /// Fast MKT ordering method (not supported broker)
    /// The trader adds _value number of DebitToken and if the order match is successful, he will get some number of CreditToken.
    ///
    /// Arguments:
    /// - debitToken: Principal. DebitToken’s canister-id (DebitToken: The token that the trader needs to add to the trading pair).
    /// - value: Amount. The amount of DebitToken you want to add.
    /// - nonce: ?Nonce. Optionally specify nonce value.
    /// - sa: ?Sa. Optionally specify the subaccount of the caller
    /// - data: ?Data. Optional Remark data, like memo.
    ///
    /// Returns:
    /// - res: TradingResult. Returns order result. The execution is asynchronous, Record the txid and you can check the order 
    ///     status through drc205_events() or statusByTxid().
    /// 
    public shared(msg) func tradeMKT(_token: DebitToken, _value: Amount, _nonce: ?Nonce, _sa: ?Sa, _data: ?Data) : async TradingResult{
        _checkICTCError();
        if (not(_notPaused(?msg.caller) and initialized)){
            return #err({code=#UndefinedError; message="400: Trading pair has been suspended.";}); 
        };
        let account = Tools.principalToAccountBlob(msg.caller, _sa);
        await* _checkOverload(?account);
        if (_tps(6, ?account).0 > 3){ 
            countRejections += 1; 
            return #err({code=#UndefinedError; message="406: Tip: Only one order can be made within 3 seconds.";}); 
        };
        var _order: OrderPrice = {quantity=#Sell(0); price=0;};
        var _orderType: OrderType = #MKT;
        if (_token == _token0Canister()){
            _order := {quantity=#Sell(_value); price=0;};
        } else if (_token == _token1Canister()){
            _order := {quantity=#Buy((0, _value)); price=0;};
        };
        try{
            countAsyncMessage += 1;
            let res = await* _trade(msg.caller, _order, _orderType, null, _nonce, _sa, _data, null, true);
            countAsyncMessage -= Nat.min(1, countAsyncMessage);
            return res;
        }catch(e){
            countAsyncMessage -= Nat.min(1, countAsyncMessage);
            throw Error.reject("420: internal call error: "# Error.message(e)); 
        };
    };

    /// Fast MKT ordering method (supported broker)
    ///
    /// Arguments: (See the trade() method arguments, the following are additional arguments)
    /// - brokerage: ?{ broker: Principal; rate: Float; }. Set the broker’s receiving account (principal) and brokerage rates.
    ///
    /// Returns:
    /// - res: TradingResult. Returns order result. The execution is asynchronous, Record the txid and you can check the order 
    ///     status through drc205_events() or statusByTxid().
    public shared(msg) func tradeMKT_b(_token: DebitToken, _value: Amount, _limitPrice: ?Nat, _nonce: ?Nonce, _sa: ?Sa, _data: ?Data,
    _brokerage: ?{broker: Principal; rate: Float}) : async TradingResult{
        _checkICTCError();
        if (not(_notPaused(?msg.caller) and initialized)){
            return #err({code=#UndefinedError; message="400: Trading pair has been suspended.";}); 
        };
        let account = Tools.principalToAccountBlob(msg.caller, _sa);
        await* _checkOverload(?account);
        if (_tps(6, ?account).0 > 3){ 
            countRejections += 1; 
            return #err({code=#UndefinedError; message="406: Tip: Only one order can be made within 3 seconds.";}); 
        };
        let brokerageRate: Float = switch(_brokerage){ 
            case(?(b)){ b.rate };
            case(_){ 0.0 };
        };
        if (brokerageRate > 0.005){
            return #err({code=#UndefinedError; message="414: Brokerage rate should not be higher than 0.005 (0.5%).";}); 
        };
        let limitPrice = Option.get(_limitPrice, 0);
        var _order: OrderPrice = {quantity=#Sell(0); price=limitPrice;};
        var _orderType: OrderType = #MKT;
        if (_token == _token0Canister()){
            _order := {quantity=#Sell(_value); price = _order.price;};
        } else if (_token == _token1Canister()){
            _order := {quantity=#Buy((0, _value)); price = _order.price;};
        };
        try{
            countAsyncMessage += 1;
            let res = await* _trade(msg.caller, _order, _orderType, null, _nonce, _sa, _data, _brokerage, true);
            countAsyncMessage -= Nat.min(1, countAsyncMessage);
            return res;
        }catch(e){
            countAsyncMessage -= Nat.min(1, countAsyncMessage);
            throw Error.reject("420: internal call error: "# Error.message(e)); 
        };
    };
    
    /// The trader cancels an order
    ///
    /// Arguments:
    /// - nonce: Nat. Nonce of the order. If you don't know the nonce of order, you can call cancelByTxid().
    /// - sa: ?Sa. Optionally specify the subaccount of the caller
    public shared(msg) func cancel(_nonce: Nonce, _sa: ?Sa) : async (){
        if (not(_notPaused(?msg.caller) and initialized)){
            throw Error.reject("400: Trading pair has been suspended."); 
        };
        let account = Tools.principalToAccountBlob(msg.caller, _sa);
        await* _checkOverload(?account);
        _clear();
        let txid = drc205.generateTxid(Principal.fromActor(this), account, _nonce);
        let saga = _getSaga();
        let toid = saga.create("cancel", #Forward, ?txid, null);
        let ttids = _cancel(toid, txid, null);
        saga.close(toid);
        if (ttids.size() == 0){
            ignore saga.doneEmpty(toid);
        };
        // drc205; 
        await* _callDrc205Store(false, false);
        // ictc
        await* _ictcSagaRun(0, false);
    };

    /// The trader or Owner (DAO) cancels an order
    ///
    /// Arguments:
    /// - txid: Txid. Specify txid of the order.
    /// - sa: ?Sa. Optionally specify the subaccount of the caller
    public shared(msg) func cancelByTxid(_txid: Txid, _sa: ?Sa) : async (){
        let account = Tools.principalToAccountBlob(msg.caller, _sa);
        assert(_onlyOwner(msg.caller) or (_onlyOrderOwner(account, _txid) and _notPaused(?msg.caller)));
        await* _checkOverload(?account);
        _clear();
        //_cancel(_txid, null);
        let saga = _getSaga();
        let toid = saga.create("cancelByTxid", #Forward, ?_txid, null);
        let ttids = _cancel(toid, _txid, null);
        saga.close(toid);
        if (ttids.size() == 0){
            ignore saga.doneEmpty(toid);
        };
        // drc205; 
        await* _callDrc205Store(false, false);
        // ictc
        await* _ictcSagaRun(0, false);
    };

    /// Batch cancel orders. If `side` (#Buy or #Sell) is specified, only one side of the orders will be canceled.
    /// 1. Owner (DAO) caller: Cancel all orders or orders for a specific account.
    /// 2. Trader caller: Cancel all his own orders.
    ///
    /// Arguments:
    /// - args: {#management: ?AccountId; #self_sa: ?Sa}. Owner (DAO) specifies #management parameter, Trader specifies #self_sa parameter.
    /// - side: ?OrderBook.OrderSide. Optionally specify the side (#Buy or #Sell), only one side of the orders will be canceled.
    public shared(msg) func cancelAll(_args: {#management: ?AccountId; #self_sa: ?Sa}, _side: ?OrderBook.OrderSide) : async (){
        let msgAccount = Tools.principalToAccountBlob(msg.caller, null);
        await* _checkOverload(?msgAccount);
        _clear();
        await* _cancelAll(msg.caller, _args, _side);
    };

    /// While in tunnel mode, retrieve funds from TxAccount for an order that is inactive and is not in fallbacking lockout.
    /// When fallback() is called, the fallbacking state of the specified txid will be locked for up to 72 hours. 
    /// It is unlocked when the execution of the ICTC associated with the fallback completes, or it is automatically unlocked after 72 hours.
    ///
    /// Arguments:
    /// - nonce: Nat. Specify nonce of the order. If you don't know the nonce of order, you can call fallbackByTxid().
    /// - sa: ?Sa. Optionally specify the subaccount of the caller
    ///
    /// Results:
    /// - res: Bool
    public shared(msg) func fallback(_nonce: Nonce, _sa: ?Sa) : async Bool{
        if (not(_notPaused(?msg.caller) and initialized)){
            throw Error.reject("400: Trading pair has been suspended."); 
        };
        let account = Tools.principalToAccountBlob(msg.caller, _sa);
        await* _checkOverload(?account);
        let icrc1Account = { owner = msg.caller; subaccount = _toSaBlob(_sa);};
        let txid = drc205.generateTxid(Principal.fromActor(this), account, _nonce);
        try{
            countAsyncMessage += 1;
            let res = await* _fallback(icrc1Account, txid, null);
            countAsyncMessage -= Nat.min(1, countAsyncMessage);
            return res;
        }catch(e){
            countAsyncMessage -= Nat.min(1, countAsyncMessage);
            throw Error.reject("420: internal call error: "# Error.message(e)); 
        };
    };

    /// While in tunnel mode, retrieve funds from TxAccount for an order that is inactive and is not in fallbacking lockout.
    /// When fallbackByTxid() is called, the fallbacking state of the specified txid will be locked for up to 72 hours. 
    /// It is unlocked when the execution of the ICTC associated with the fallback completes, or it is automatically unlocked 
    /// after 72 hours.
    ///
    /// Note: If the Owner (DAO) calls this method, the funds of the TxAccount will be refunded to the ICDexRouter canister-id.
    ///
    /// Arguments:
    /// - txid: Txid. Specify txid of the order.
    /// - sa: ?Sa. Optionally specify the subaccount of the caller
    ///
    /// Results:
    /// - res: Bool
    public shared(msg) func fallbackByTxid(_txid: Txid, _sa: ?Sa) : async Bool{
        // Note: _onlyOwner - fallback to ICDex Router Canister
        let account = Tools.principalToAccountBlob(msg.caller, _sa);
        assert(_onlyOwner(msg.caller) or (_onlyOrderOwner(account, _txid) and _notPaused(?msg.caller)));
        await* _checkOverload(?account);
        let icrc1Account = { owner = msg.caller; subaccount = _toSaBlob(_sa);};
        try{
            countAsyncMessage += 1;
            let res = await* _fallback(icrc1Account, _txid, null);
            countAsyncMessage -= Nat.min(1, countAsyncMessage);
            return res;
        }catch(e){
            countAsyncMessage -= Nat.min(1, countAsyncMessage);
            throw Error.reject("420: internal call error: "# Error.message(e)); 
        };
    };

    /*public query func getDip20Balance(_account: Address) : async (Nat, Principal){
        let accountId = _getAccountId(_account);
        return (_getDip20Balance(accountId), _getDip20Principal(accountId));
    };
    public query func getTxDip20Balance(_txid: Text) : async ?(Nat, Principal){
        let a = Hex.decode(_txid);
        switch (a){
            case (#ok(txid:[Nat8])){
                let accountId = _getPairAccount(Blob.fromArray(txid));
                return ?(_getDip20Balance(accountId), _getDip20Principal(accountId));
            };
            case(#err(_)){
                return null;
            }
        };
    };*/

    /// Query all orders of a trader that are in pending status
    ///
    /// Arguments:
    /// - account: ?Address. Specify account of the trader, hex of account-id or principal.
    /// - page: ?ListPage. Page number.
    /// - size: ?ListSize. Number of records per page.
    ///
    /// Results:
    /// - res: TrieList<Txid, TradingOrder>. 
    public query func pending(_account: ?Address, _page: ?ListPage/*base 1*/, _size: ?ListSize) : async TrieList<Txid, TradingOrder>{
        var trie : Trie.Trie<Txid, TradingOrder> = Trie.empty();
        let page = Option.get(_page, 1);
        let size = Option.get(_size, 100);
        switch(_account){
            case(?(account)){
                let accountId = _getAccountId(account);
                trie := _accountPendingOrders(?accountId);
                // trie := Trie.mapFilter<Txid, TradingOrder, TradingOrder>(trie, func (k:Txid, v:TradingOrder): ?TradingOrder{ 
                //     if (v.account == accountId){
                //         return ?_toReponse(v);
                //     }else { return null; }; 
                // });
            };
            case(_){ assert(false); }; 
        };
        return trieItems<Txid, TradingOrder>(trie, page, size);
    };

    /// Query the total number of orders in pending status for the pair.
    public query func pendingCount() : async Nat{
        return Trie.size(icdex_orders);
    };

    /// Query all orders in pending status. Only the Owner (DAO) is allowed to query it.
    ///
    /// Arguments:
    /// - page: ?ListPage. Page number.
    /// - size: ?ListSize. Number of records per page.
    ///
    /// Results:
    /// - res: TrieList<Txid, TradingOrder>. 
    public query(msg) func pendingAll(_page: ?ListPage, _size: ?ListSize) : async TrieList<Txid, TradingOrder>{
        assert(_onlyOwner(msg.caller));
        var trie = icdex_orders;
        let page = Option.get(_page, 1);
        let size = Option.get(_size, 100);
        return trieItems<Txid, TradingOrder>(trie, page, size);
    };

    /// Query the status of an order by account and nonce.
    public query func status(_account: Address, _nonce: Nonce) : async OrderStatusResponse{
        let txid = drc205.generateTxid(Principal.fromActor(this), _getAccountId(_account), _nonce);
        switch(Trie.get(icdex_orders, keyb(txid), Blob.equal)){
            case(?(order)){ return #Pending(order); }; 
            case(_){
                switch(Trie.get(icdex_failedOrders, keyb(txid), Blob.equal)){
                    case(?(order)){ return #Failed(order); };
                    case(_){
                        switch(drc205.get(txid)){
                            case(?(txn)){ return #Completed(txn); }; 
                            case(_){ return #None; };
                        };
                    };
                };
            };
        };
    };

    /// Query the status of an order by txid.
    public query func statusByTxid(_txid: Txid) : async OrderStatusResponse{
        switch(Trie.get(icdex_orders, keyb(_txid), Blob.equal)){
            case(?(order)){ return #Pending(order); };
            case(_){
                switch(Trie.get(icdex_failedOrders, keyb(_txid), Blob.equal)){
                    case(?(order)){ return #Failed(order); };
                    case(_){
                        switch(drc205.get(_txid)){
                            case(?(txn)){ return #Completed(txn); }; 
                            case(_){ return #None; };
                        };
                    };
                };
            };
        };
    };

    /// Query the last 50 records of trades
    public query func latestFilled() : async [(Timestamp, Txid, OrderFilled, OrderSide)]{
        return _getLatestFilled();
    };

    /// Query the rebate rate of a maker. The return value `rebateRate = 0` means that it is an ordinary maker role with 
    /// no rebate; `rebateRate > 0` means that it is a vip-maker role with rebate.
    /// 
    /// Arguments:
    /// - maker: Address. Account address.
    ///
    /// Results:
    /// - res: (rebateRate: Float, feeRebate: Float).  rebateRate (res.0) indicates the rebate rate; 
    ///     feeRebate (res.1) indicates the percentage of commission that can be earned when an order for a maker is filled (trading_fee * rebateRate)
    public query func makerRebate(_maker: Address) : async (rebateRate: Float, feeRebate: Float){
        let maker = _getAccountId(_maker);
        (_natToFloat(_getMakerRebateRate(maker)) / 100, _natToFloat(_getTradingFee()) / 10000 * _natToFloat(_getMakerRebateRate(maker)) / 100);
    };

    /// Query 10 levels of quotes in the order book
    public query func level10() : async (unitSize: Nat, orderBook: {ask: [PriceResponse]; bid: [PriceResponse]}){
        return (setting.UNIT_SIZE, OrderBook.depth(icdex_orderBook, ?10));
    };

    /// Query 100 levels of quotes in the order book
    public query func level100() : async (unitSize: Nat, orderBook: {ask: [PriceResponse]; bid: [PriceResponse]}){
        return (setting.UNIT_SIZE, OrderBook.depth(icdex_orderBook, ?100));
    };

    /// Name of the trading pair
    public query func name() : async Text{
        return name_;
    };

    /// Version of the trading pair
    public query func version() : async Text{
        return version_;
    };

    /// Query the infomation of Base Token (token0)
    public query func token0() : async (DRC205.TokenType, ?Types.TokenStd){
        return (#Token(_token0Canister()), ?token0Std);
    };

    /// Query the infomation of Quote Token (token1)
    public query func token1() : async (DRC205.TokenType, ?Types.TokenStd){
        return (#Token(_token1Canister()), ?token1Std);
    };

    /// Query the number of orders for a trader (and also the value of nonce currently available for that trader), 
    /// or the number of orders for the trading pair if account is not specified.
    public query func count(_account: ?Address) : async Nat{
        switch (_account){
            case(?(account)){ return _getNonce(_getAccountId(account)); };
            case(_){ return icdex_index; };
        };
    };

    /// Counting the number of traders in the pair
    public query func userCount() : async Nat{
        return Trie.size(icdex_nonces);
    };

    /// Query the current trading fee (does not reflect vip-maker rebate and does not reflect broker commission). 
    /// broker commission will be charged additionally and paid additionally by the taker.
    public query func fee() : async {maker: { buy: Float; sell: Float }; taker: { buy: Float; sell: Float }}{
        let baseFee = _natToFloat(_getTradingFee()) / 1_000_000;
        return {
            maker = { buy = 0; sell = 0 }; 
            taker = { buy = baseFee; sell = baseFee }
        };
    };

    /// @deprecated: This method will be deprecated. 
    public query func feeStatus() : async Types.FeeStatus{
        return {
            feeRate = _natToFloat(_getTradingFee()) / 1_000_000;
            feeBalance = {value0=0; value1=0}; //icdex_feeBalance;
            totalFee = icdex_totalFee; //icdex_totalFee;
        };
    };

    // @deprecated: This method will be deprecated
    public query func liquidity(_account: ?Address) : async Types.Liquidity{
        var value0 : Nat = 0;
        var value1 : Nat = 0;
        switch(icdex_lastPrice.quantity){
            case(#Sell(value)){ value0 += value; };
            case(#Buy(value)){ value0 += value.0; };
        };
        value1 := value0 * icdex_lastPrice.price / setting.UNIT_SIZE;
        switch(_account) {
            case(null){
                return {
                value0 = value0; value1 = value1; // last price
                priceWeighted = icdex_priceWeighted; 
                vol = icdex_totalVol;
                swapCount = Nat64.fromNat(icdex_index);
                shares = 0; unitValue = (0, 0); shareWeighted = { shareTimeWeighted=0; updateTime=0 };
            };
            };
            case(?(_a)){
                let account = _getAccountId(_a);
                let vol = _getVol(account);
                return {
                value0 = value0; value1 = value1; // last price
                priceWeighted = icdex_priceWeighted; 
                vol = vol;
                swapCount = Nat64.fromNat(_getNonce(account));
                shares = 0; unitValue = (0, 0); shareWeighted = { shareTimeWeighted=0; updateTime=0 };
            };
            };
        };
    };

    /// Query the liquidity profile of the trading pair, or query the liquidity information of a specified trader.
    /// This is not a very accurate statistic due to performance considerations.
    /// 
    /// Arguments:
    /// - account: ?Address. Optionally specify a trader's account. If the value is not null it means to query the trader's 
    ///     liquidity information, if the value is null it means to query the pair liquidity information.
    ///
    /// Results:
    /// - res: Types.Liquidity2. 
    ///     - Trader Liquidity: 
    ///         ```
    ///         {
    ///             token0: Nat; // Smallest units. Liquidity of the trader (The balance locked in the PENDING status orders for the trader, plus the available balance for the trader kept in the pool of pair.)
    ///             token1: Nat; 
    ///             price: Nat; // Price: How much token1 (smallest units) are needed to purchase UNIT_SIZE token0 (smallest units).
    ///             unitSize: Nat; // UNIT_SIZE
    ///             priceWeighted: Nat; // Time-weighted price
    ///             vol: { value0: Nat; value1: Nat;}; // Smallest units. Cumulative volume of the trader.
    ///             orderCount: Nat64; // Total number of the trader's orders
    ///             userCount: Nat64; // Total number of users of trading pair
    ///             shares = 0; // This field has no meaning and is only for compatibility with the AMM Dex data structure
    ///             unitValue = (0, 0); // This field has no meaning and is only for compatibility with the AMM Dex data structure
    ///             shareWeighted = { shareTimeWeighted=0; updateTime=0 }; // This field has no meaning and is only for compatibility with the AMM Dex data structure
    ///         }
    ///         ```
    ///     - Pair Liquidity:
    ///         ```
    ///         {
    ///             token0: Nat; /* Smallest units. Liquidity in trading pair. Estimated in two ways: 1) when the total 
    ///               number of orders is less than 20,000, the value includes the balances locked in the pending order 
    ///               and the available balances kept in the pair; 2) when the total number of orders is greater than or 
    ///               equal to 20,000, the value includes the total balance kept in the pair (without the balances locked 
    ///               in tunnel mode's pending orders). */
    ///             token1: Nat; 
    ///             price: Nat; // Price: How much token1 (smallest units) are needed to purchase UNIT_SIZE token0 (smallest units).
    ///             unitSize: Nat; // UNIT_SIZE
    ///             priceWeighted: Nat; // Time-weighted price
    ///             vol: { value0: Nat; value1: Nat;}; // Smallest units. Total volume.
    ///             orderCount: Nat64; // Total number of orders of trading pair
    ///             userCount: Nat64; // Total number of users of trading pair
    ///             shares = 0; // This field has no meaning and is only for compatibility with the AMM Dex data structure
    ///             unitValue = (0, 0); // This field has no meaning and is only for compatibility with the AMM Dex data structure
    ///             shareWeighted = { shareTimeWeighted=0; updateTime=0 }; // This field has no meaning and is only for compatibility with the AMM Dex data structure
    ///         }
    ///         ```
    public query func liquidity2(_account: ?Address) : async Types.Liquidity2{
        switch(_account) {
            case(null){
                var value0 : Nat = 0;
                var value1 : Nat = 0;
                if (Trie.size(icdex_keepingBalances) < 20_000){ // Contains the balances locked in the pending order and the available balances kept in the pair.
                    let (lValue0, lValue1) = _getPendingOrderLiquidity(null);
                    value0 := lValue0;
                    value1 := lValue1;
                    for ((account, balances) in Trie.iter(icdex_keepingBalances)){
                        value0 += balances.token0.available;
                        value1 += balances.token1.available;
                    };
                }else{ // Contains the total balance kept in the pair (without the balances locked in tunnel mode's pending orders).
                    value0 := icdex_poolBalance.token0;
                    value1 := icdex_poolBalance.token1;
                };
                return {
                    token0 = value0; token1 = value1; 
                    price = icdex_lastPrice.price;
                    unitSize = setting.UNIT_SIZE;
                    priceWeighted = icdex_priceWeighted; 
                    vol = icdex_totalVol;
                    orderCount = Nat64.fromNat(icdex_index);
                    userCount = Nat64.fromNat(Trie.size(icdex_nonces));
                    shares = 0; unitValue = (0, 0); shareWeighted = { shareTimeWeighted=0; updateTime=0 };
                };
            };
            case(?(_a)){
                let account = _getAccountId(_a);
                let vol = _getVol(account);
                let balances = _getAccountBalance(account);
                let (lValue0, lValue1) = _getPendingOrderLiquidity(?account);
                return {
                    token0 = lValue0 + balances.token0.available; token1 = lValue1 + balances.token1.available; 
                    price = icdex_lastPrice.price;
                    unitSize = setting.UNIT_SIZE;
                    priceWeighted = icdex_priceWeighted; 
                    vol = vol;
                    orderCount = Nat64.fromNat(_getNonce(account));
                    userCount = Nat64.fromNat(Trie.size(icdex_nonces));
                    shares = 0; unitValue = (0, 0); shareWeighted = { shareTimeWeighted=0; updateTime=0 };
                };
            };
        };
    };

    /// Query the K chart of the market at the specified time interval (seconds).
    public query func getQuotes(_ki: OrderBook.KInterval) : async [OrderBook.KBar]{
        return OrderBook.getK(icdex_klines2, _ki);
    };

    /// Query default order expiration duration (nanoseconds)
    public query func orderExpirationDuration() : async Int{ // ns
        return ExpirationDuration;
    };

    /// Query the basic information of the trading pair
    public query func info() : async {
        name: Text;
        version: Text;
        decimals: Nat8;
        owner: Principal;
        paused: Bool;
        setting: DexSetting;
        token0: TokenInfo;
        token1: TokenInfo;
    }{
        return {
            name = name_;
            version = version_;
            decimals = 0;
            owner = icdexRouter;
            paused = not(_notPaused(null));
            setting = setting;
            token0 = (token0_, token0Symbol, token0Std);
            token1 = (token1_, token1Symbol, token1Std);
        }
    };

    /// Query current price，total volume and 24-hour statistics
    ///
    /// Results:
    /// - res: {  
    ///     price: Float; // Converted prices (float). How much token1 (smallest units) are needed to purchase 1 token0 (smallest units).  
    ///     totalVol: Vol; // Smallest units. Total volume.  
    ///     change24h: Float; // 24-hour rate of price change.  
    ///     vol24h: Vol; // Smallest units. 24-hour volume.  
    /// }
    public query func stats() : async {price:Float; change24h:Float; vol24h:Vol; totalVol:Vol}{
        let res = _24h();
        return {price = res.price; change24h = res.change24h; vol24h = res.vol24h; totalVol = icdex_totalVol};
    };

    /// TPS pressure statistics
    public query func tpsStats() : async (Nat, Float, Nat, Nat, Int, Int){ // asyncMessageSize, tps, visitors, rejections, lastExecutionDuration, maxExecutionDuration
        return (_asyncMessageSize(), _natToFloat(_tps(60, null).1) / 10.0, List.size(icdex_lastVisits.0)+List.size(icdex_lastVisits.1), countRejections, lastExecutionDuration, maxExecutionDuration);
    };

    /// System access mode, and time to be opened (0 means already opened)
    public query func sysMode() : async {mode: SysMode; openingTime: Time.Time;}{
        var mode_ = mode;
        if (_notPaused(null)){ 
            mode_ := #GeneralTrading;
        }else{
            mode_ := #DisabledTrading;
        };
        return {mode = mode_; openingTime = pairOpeningTime}; 
    };

    /// List of brokers
    public query func brokerList(_page: ?ListPage, _size: ?ListSize) : async TrieList<AccountId, {vol: Vol; commission: Vol; count: Nat; rate: Float}>{
        var trie = stats_brokers;
        let page = Option.get(_page, 1);
        let size = Option.get(_size, 100);
        return trieItems<AccountId, {vol: Vol; commission: Vol; count: Nat; rate: Float}>(trie, page, size);
    };

    /// List of vip-makers
    public query func makerList(_page: ?ListPage, _size: ?ListSize) : async TrieList<AccountId, {vol: Vol; commission: Vol; orders: Nat; filledCount: Nat;}>{
        var trie = stats_makers;
        let page = Option.get(_page, 1);
        let size = Option.get(_size, 100);
        return trieItems<AccountId, {vol: Vol; commission: Vol; orders: Nat; filledCount: Nat;}>(trie, page, size);
    };

    /// Query a trader's roles
    public query func getRole(_account: Address): async {
        broker: Bool;
        vipMaker: Bool;
        proTrader: Bool;
    }{
        let account = _getAccountId(_account);
        return {
            broker = Option.isSome(Trie.get(stats_brokers, keyb(account), Blob.equal));
            vipMaker = _getMakerRebateRate(account) > 0;
            proTrader = _isProTrader(account);
        }
    };

    /* ===========================
      PoolMode section
    ============================== */
    private func _accountConfig(_a: AccountId, _enPoolMode: ?Bool, _enKeepingBalance: ?Bool): (){
        let setting = _getAccountSetting(_a);
        let preEnPoolMode = setting.enPoolMode;
        let enPoolMode = Option.get(_enPoolMode, setting.enPoolMode);
        var enKeepingBalance = Option.get(_enKeepingBalance, setting.enKeepingBalance);
        var startNew: ?Nat = null;
        if (enPoolMode and preEnPoolMode){
            startNew := setting.start;
        }else if (enPoolMode){
            startNew := ?_getNonce(_a);
        };
        let history = setting.modeSwitchHistory;
        var historyNew : [(startNonce:Nonce, endNonce:Nonce)] = [];
        for ((start, end) in history.vals()){
            var completed: Bool = true;
            for (nonce in Iter.range(start, end)){
                let txid = drc205.generateTxid(Principal.fromActor(this), _a, nonce);
                if (Option.isSome(Trie.get(icdex_orders, keyb(txid), Blob.equal))){
                    completed := false;
                };
            };
            if (not(completed)){
                historyNew := Tools.arrayAppend(historyNew, [(start, end)]);
            };
        };
        if (preEnPoolMode and not(enPoolMode) and _getNonce(_a) > 0){
            let start = Option.get(setting.start, 0);
            let end = Nat.sub(_getNonce(_a), 1);
            if (end >= start){
                historyNew := Tools.arrayAppend(historyNew, [(start, end)]);
            };
        };
        if (not(enPoolMode) and not(enKeepingBalance) and historyNew.size() == 0){
            icdex_accountSettings := Trie.remove(icdex_accountSettings, keyb(_a), Blob.equal).0;
        }else{
            icdex_accountSettings := Trie.put(icdex_accountSettings, keyb(_a), Blob.equal, {
                enPoolMode = enPoolMode; 
                start = startNew; 
                modeSwitchHistory = historyNew; 
                enKeepingBalance = enKeepingBalance;
            }).0;
        };
    };
    private func _defaultConfig(_a: AccountId) : (){
        // Default: icdex-fee recipient, broker; vip-maker, pro-trader
        if (_a == Tools.principalToAccountBlob(icdexRouter, null)){
            _accountConfig(_a, null, ?true);
        };
        if (Option.isSome(Trie.get(stats_brokers, keyb(_a), Blob.equal))){
            _accountConfig(_a, null, ?true);
        };
        if (_getMakerRebateRate(_a) > 0){
            _accountConfig(_a, ?true, ?true);
        };
        if (_isProTrader(_a)){ 
            _accountConfig(_a, ?true, ?true);
        };
    };
    private func _exchangeMode(_a: AccountId, _nonce: ?Nonce) : {#PoolMode; #TunnelMode}{
        _defaultConfig(_a);
        let setting = _getAccountSetting(_a);
        switch(_nonce){
            case(?nonce){
                if (Option.isSome(Array.find(setting.modeSwitchHistory, func (t: (Nat,Nat)): Bool{ nonce >= t.0 and nonce <= t.1 }))){
                    return #PoolMode;
                }else if (nonce >= Option.get(setting.start, 0) and setting.enPoolMode){
                    return #PoolMode;
                }else{
                    return #TunnelMode;
                };
            };
            case(_){
                if (setting.enPoolMode){
                    return #PoolMode;
                }else{
                    return #TunnelMode;
                };
            };
        };
    };
    private func _isKeepingBalanceInPair(_a: AccountId) : Bool{
        _defaultConfig(_a);
        let setting = _getAccountSetting(_a);
        return setting.enKeepingBalance;
    };
    private func _getAccountSetting(_a: AccountId): AccountSetting{
        switch(Trie.get(icdex_accountSettings, keyb(_a), Blob.equal)){
            case(?setting){
                return setting;
            };
            case(_){
                return {enPoolMode = false; start = null; modeSwitchHistory = []; enKeepingBalance = false };
            };
        };
    };
    private func _lockAccountBalance(_a: AccountId, _token: {#token0; #token1}, _amount: Amount) : KeepingBalance{
        let balance = _getAccountBalance(_a);
        if (_amount == 0){
            return balance;
        };
        switch(_token){
            case(#token0){
                assert(balance.token0.available >= _amount);
                icdex_keepingBalances := Trie.put(icdex_keepingBalances, keyb(_a), Blob.equal, {
                    token0 = {locked = balance.token0.locked + _amount; available = Nat.sub(balance.token0.available, _amount) }; 
                    token1 = balance.token1;
                }).0;
            };
            case(#token1){
                assert(balance.token1.available >= _amount);
                icdex_keepingBalances := Trie.put(icdex_keepingBalances, keyb(_a), Blob.equal, {
                    token0 = balance.token0;
                    token1 = {locked = balance.token1.locked + _amount; available = Nat.sub(balance.token1.available, _amount) }; 
                }).0;
            };
        };
        return _getAccountBalance(_a);
    };
    private func _unlockAccountBalance(_a: AccountId, _token: {#token0; #token1}, _amount: Amount) : KeepingBalance{
        let balance = _getAccountBalance(_a);
        if (_amount == 0){
            return balance;
        };
        switch(_token){
            case(#token0){
                assert(balance.token0.locked >= _amount);
                icdex_keepingBalances := Trie.put(icdex_keepingBalances, keyb(_a), Blob.equal, {
                    token0 = {locked = Nat.sub(balance.token0.locked, _amount); available = balance.token0.available + _amount }; 
                    token1 = balance.token1;
                }).0;
            };
            case(#token1){
                assert(balance.token1.locked >= _amount);
                icdex_keepingBalances := Trie.put(icdex_keepingBalances, keyb(_a), Blob.equal, {
                    token0 = balance.token0;
                    token1 = {locked = Nat.sub(balance.token1.locked, _amount); available = balance.token1.available + _amount }; 
                }).0;
            };
        };
        return _getAccountBalance(_a);
    };
    private func _addAccountBalance(_a: AccountId, _token: {#token0; #token1}, _amount: {#locked: Amount; #available: Amount}) : KeepingBalance{
        let balance = _getAccountBalance(_a);
        switch(_token, _amount){
            case(#token0, #locked(amount)){
                if (amount == 0){ return balance; };
                icdex_poolBalance := {token0 = icdex_poolBalance.token0 + amount; token1 = icdex_poolBalance.token1 };
                icdex_keepingBalances := Trie.put(icdex_keepingBalances, keyb(_a), Blob.equal, {
                    token0 = {locked = balance.token0.locked + amount; available = balance.token0.available }; 
                    token1 = balance.token1;
                }).0;
            };
            case(#token0, #available(amount)){
                if (amount == 0){ return balance; };
                icdex_poolBalance := {token0 = icdex_poolBalance.token0 + amount; token1 = icdex_poolBalance.token1 };
                icdex_keepingBalances := Trie.put(icdex_keepingBalances, keyb(_a), Blob.equal, {
                    token0 = {locked = balance.token0.locked; available = balance.token0.available + amount }; 
                    token1 = balance.token1;
                }).0;
            };
            case(#token1, #locked(amount)){
                if (amount == 0){ return balance; };
                icdex_poolBalance := {token0 = icdex_poolBalance.token0; token1 = icdex_poolBalance.token1 + amount };
                icdex_keepingBalances := Trie.put(icdex_keepingBalances, keyb(_a), Blob.equal, {
                    token0 = balance.token0;
                    token1 = {locked = balance.token1.locked + amount; available = balance.token1.available }; 
                }).0;
            };
            case(#token1, #available(amount)){
                if (amount == 0){ return balance; };
                icdex_poolBalance := {token0 = icdex_poolBalance.token0; token1 = icdex_poolBalance.token1 + amount };
                icdex_keepingBalances := Trie.put(icdex_keepingBalances, keyb(_a), Blob.equal, {
                    token0 = balance.token0;
                    token1 = {locked = balance.token1.locked; available = balance.token1.available + amount }; 
                }).0;
            };
        };
        return _getAccountBalance(_a);
    };
    private func _subAccountBalance(_a: AccountId, _token: {#token0; #token1}, _amount: {#locked: Amount; #available: Amount}) : KeepingBalance{
        let balance = _getAccountBalance(_a);
        switch(_token, _amount){
            case(#token0, #locked(amount)){
                if (amount == 0){ return balance; };
                assert(icdex_poolBalance.token0 >= amount);
                assert(balance.token0.locked >= amount);
                icdex_poolBalance := {token0 = Nat.sub(icdex_poolBalance.token0, amount); token1 = icdex_poolBalance.token1 };
                icdex_keepingBalances := Trie.put(icdex_keepingBalances, keyb(_a), Blob.equal, {
                    token0 = {locked = Nat.sub(balance.token0.locked, amount); available = balance.token0.available }; 
                    token1 = balance.token1;
                }).0;
            };
            case(#token0, #available(amount)){
                if (amount == 0){ return balance; };
                assert(icdex_poolBalance.token0 >= amount);
                assert(balance.token0.available >= amount);
                icdex_poolBalance := {token0 = Nat.sub(icdex_poolBalance.token0, amount); token1 = icdex_poolBalance.token1 };
                icdex_keepingBalances := Trie.put(icdex_keepingBalances, keyb(_a), Blob.equal, {
                    token0 = {locked = balance.token0.locked; available = Nat.sub(balance.token0.available, amount) }; 
                    token1 = balance.token1;
                }).0;
            };
            case(#token1, #locked(amount)){
                if (amount == 0){ return balance; };
                assert(icdex_poolBalance.token1 >= amount);
                assert(balance.token1.locked >= amount);
                icdex_poolBalance := {token0 = icdex_poolBalance.token0; token1 = Nat.sub(icdex_poolBalance.token1, amount) };
                icdex_keepingBalances := Trie.put(icdex_keepingBalances, keyb(_a), Blob.equal, {
                    token0 = balance.token0;
                    token1 = {locked = Nat.sub(balance.token1.locked, amount); available = balance.token1.available }; 
                }).0;
            };
            case(#token1, #available(amount)){
                if (amount == 0){ return balance; };
                assert(icdex_poolBalance.token1 >= amount);
                assert(balance.token1.available >= amount);
                icdex_poolBalance := {token0 = icdex_poolBalance.token0; token1 = Nat.sub(icdex_poolBalance.token1, amount) };
                icdex_keepingBalances := Trie.put(icdex_keepingBalances, keyb(_a), Blob.equal, {
                    token0 = balance.token0;
                    token1 = {locked = balance.token1.locked; available = Nat.sub(balance.token1.available, amount) }; 
                }).0;
            };
        };
        let res = _getAccountBalance(_a);
        if (res.token0.locked == 0 and res.token0.available == 0 and res.token1.locked == 0 and res.token1.available == 0){
            icdex_keepingBalances := Trie.remove(icdex_keepingBalances, keyb(_a), Blob.equal).0;
        };
        return res;
    };
    private func _checkSumPoolBalance() : {result: Bool; total: { token0: Amount; token1: Amount }; pool: { token0: Amount; token1: Amount }}{
        var token0Total: Amount = 0;
        var token1Total: Amount = 0;
        for ((account, balances) in Trie.iter(icdex_keepingBalances)){
            token0Total += balances.token0.locked;
            token0Total += balances.token0.available;
            token1Total += balances.token1.locked;
            token1Total += balances.token1.available;
        };
        return {
            result = token0Total == icdex_poolBalance.token0 and token1Total == icdex_poolBalance.token1;
            total = { token0 = token0Total; token1 = token1Total }; 
            pool = icdex_poolBalance;
        };
    };
    private func _checkNativeBalance() : async* ?Bool{
        if (_ictcAllDone()){
            let sa_pool = Blob.fromArray(sa_zero);
            let balance0 = await* _getBaseBalance(sa_pool);
            let balance1 = await* _getQuoteBalance(sa_pool);
            return ?(balance0 >= icdex_poolBalance.token0 and balance1 >= icdex_poolBalance.token1);
        }else{
            return null;
        };
    };
    private func _getAccountBalance(_a: AccountId): KeepingBalance{
        switch(Trie.get(icdex_keepingBalances, keyb(_a), Blob.equal)){
            case(?res){ return res; };
            case(_){ return {token0 = {locked = 0; available = 0}; token1 = {locked = 0; available = 0}} };
        };
    };
    // private func _deposit2(_caller: Principal, _side:{#token0;#token1}, _a: AccountId, _value: Amount) : async* (){
    //     let sa_account = _a; // _getPairAccount( );
    //     let sa_pool = Blob.fromArray(sa_zero);
    //     let poolAccount = _getPairAccount(sa_pool);
    //     let saga = _getSaga();
    //     var fee: Nat = _getFee0();
    //     var std = token0Std;
    //     var tokenPrincipal = _token0Canister();
    //     if (_side == #token1){
    //         fee := _getFee1();
    //         std := token1Std;
    //         tokenPrincipal := _token1Canister();
    //     };
    //     if (_value <= fee){
    //         throw Error.reject("431: The specified `_value` should be greater than fee."); 
    //     };
    //     if (std == #icp or std == #icrc1 /*or std == #ledger*/){
    //         var balance : Nat = 0;
    //         try{
    //             if (_side == #token0){
    //                 balance := await* _getBaseBalance(sa_account);
    //             }else{
    //                 balance := await* _getQuoteBalance(sa_account);
    //             };
    //         }catch(e){
    //             throw Error.reject("420: internal call error: "# Error.message(e)); 
    //         };
    //         if (balance >= _value){
    //             let toid = saga.create("deposit", #Backward, null, null);
    //             let ttids = _sendToken(false, _side, toid, sa_account, [], [{owner=Principal.fromActor(this); subaccount = ?sa_pool}], [_value], ?sa_account, null);
    //             let task1 = _buildTask(?Principal.toBlob(_caller), Principal.fromActor(this), #This(#batchTransfer([(#add, _a, _side, #available(Nat.sub(_value, fee)))])), ttids);
    //             let ttid1 = saga.push(toid, task1, null, null);
    //             saga.close(toid);
    //             await* _ictcSagaRun(toid, false);
    //         }else{
    //             throw Error.reject("432: Insufficient balance."); 
    //         };
    //     }else if (std == #drc20){
    //         var balance : Nat = 0;
    //         try{
    //             let token: DRC20.Self = actor(Principal.toText(tokenPrincipal));
    //             balance := await token.drc20_balanceOf(_accountIdToHex(_a));
    //         }catch(e){
    //             throw Error.reject("420: internal call error: "# Error.message(e)); 
    //         };
    //         if (balance >= _value + fee){
    //             let toid = saga.create("deposit", #Backward, null, null);
    //             let task = _buildTask(?sa_account, tokenPrincipal, #DRC20(#transferFrom(_accountIdToHex(_a), _accountIdToHex(poolAccount), _value, null, null, null)), []);
    //             let ttid = saga.push(toid, task, null, null);
    //             let task1 = _buildTask(?Principal.toBlob(_caller), Principal.fromActor(this), #This(#batchTransfer([(#add, _a, _side, #available(_value))])), [ttid]);
    //             let ttid1 = saga.push(toid, task1, null, null);
    //             saga.close(toid);
    //             await* _ictcSagaRun(toid, false);
    //         }else{
    //             throw Error.reject("432: Insufficient balance."); 
    //         };
    //     };
    // };
    private func _deposit(_side:{#token0; #token1}, _icrc1Account: ICRC1.Account, _amount: Amount) : async* Amount{
        var _fee : Nat = 0;
        var _canisterId : Principal = Principal.fromActor(this);
        var _std : Types.TokenStd = #drc20;
        if (_side == #token0){
            _fee := _getFee0();
            _canisterId := _token0Canister();
            _std := token0Std;
        }else if (_side == #token1){
            _fee := _getFee1();
            _canisterId := _token1Canister();
            _std := token1Std;
        };
        let _account = Tools.principalToAccountBlob(_icrc1Account.owner, _toSaNat8(_icrc1Account.subaccount));
        let _depositAccount = _getPairAccount(_account);
        var _depositIcrc1Account = {owner = Principal.fromActor(this); subaccount = ?_account};
        let _poolAccount = _getPairAccount(Blob.fromArray(sa_zero));
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
                throw Error.reject("432: Insufficient token balance! " # Error.message(e));
            };
        };
        // depositAccount -> pool
        if (valueFromDepositBalance > 0){ 
            if (_isFallbacking(_account)){
                throw Error.reject("433: You are fallbacking. Try again later.");
            };
            try{
                await* _tokenTransfer(_canisterId, _account, _poolIcrc1Account, valueFromDepositBalance, ?_account);
                ignore _addAccountBalance(_account, _side, #available(valueFromDepositBalance));
            }catch(e){
                throw Error.reject("431: Token transfer error: " # Error.message(e));
            };
        };
        return valueFromDepositBalance;
    };
    private func _depositFallback(_owner: Principal, _sa: ?Sa) : async* (value0: Amount, value1: Amount){
        let sa_account = Tools.principalToAccountBlob(_owner, _sa);
        let icrc1Account = {owner = _owner; subaccount = _toSaBlob(_sa)};
        var value0: Nat = 0;
        var value1: Nat = 0;
        if (not(_isFallbacking(sa_account))){
            _putFallbacking(sa_account);
            try{
                value0 := await* _getBaseBalance(sa_account);
                value1 := await* _getQuoteBalance(sa_account);
            }catch(e){
                _removeFallbacking(sa_account);
                throw Error.reject("420: internal call error: "# Error.message(e)); 
            };
            let saga = _getSaga();
            if (value0 > _getFee0() or value1 > _getFee1()){
                let toid = saga.create("deposit_fallback_0", #Backward, ?sa_account, ?(func (_toName: Text, _toid: Toid, _status: SagaTM.OrderStatus, _data: ?Blob) : async (){
                    if (_status == #Done or _status == #Recovered){
                        switch(_data){
                            case(?sa_account){ _removeFallbacking(sa_account) };
                            case(_){};
                        };
                    };
                }));
                if (value0 > _getFee0()){
                    ignore _sendToken0(false, toid, sa_account, [], [icrc1Account], [value0], ?sa_account, null);
                };
                if (value1 > _getFee1()){
                    ignore _sendToken1(false, toid, sa_account, [], [icrc1Account], [value1], ?sa_account, null);
                };
                saga.close(toid);
                await* _ictcSagaRun(toid, false);
            }else{
                _removeFallbacking(sa_account);
            };
        };
        return (value0, value1);
    };
    private func _putWithdrawing(_account: AccountId, _toid: Toid) : (){
        accountWithdrawToids := List.push((_account, _toid, Time.now()), accountWithdrawToids);
    };
    private func _removeWithdrawing(_toid: Toid) : (){
        accountWithdrawToids := List.filter(accountWithdrawToids, func (t: (AccountId, Toid, Time.Time)): Bool{
            t.1 != _toid and Time.now() < t.2 + 30 * 24 * 3600 * ns_
        });
    };
    private func _withdraw(_owner: Principal, _value0: ?Amount, _value1: ?Amount, _sa: ?Sa) : (toid: Nat, value0: Amount, value1: Amount){
        let account = Tools.principalToAccountBlob(_owner, _sa);
        let sa_account = account; 
        let sa_pool = Blob.fromArray(sa_zero);
        let icrc1Account = {owner = _owner; subaccount = _toSaBlob(_sa)};
        let balances = _getAccountBalance(account);
        var value0: Nat = Option.get(_value0, balances.token0.available);
        var value1: Nat = Option.get(_value1, balances.token1.available);
        assert(value0 <= balances.token0.available and value1 <= balances.token1.available);
        let saga = _getSaga();
        var toid : Nat = 0;
        var resValue0: Nat = 0;
        var resValue1: Nat = 0;
        if (value0 > _getFee0() or value1 > _getFee1()){
            toid := saga.create("withdraw", #Forward, null, ?(func (_toName: Text, _toid: Toid, _status: SagaTM.OrderStatus, _data: ?Blob) : async (){
                if (_status == #Done or _status == #Recovered){
                    _removeWithdrawing(_toid);
                };
            }));
            if (value0 > _getFee0()){
                ignore _subAccountBalance(account, #token0, #available(value0));
                ignore _sendToken0(false, toid, sa_pool, [], [icrc1Account], [value0], ?sa_pool, null);
                resValue0 := Nat.sub(value0, _getFee0());
            };
            if (value1 > _getFee1()){
                ignore _subAccountBalance(account, #token1, #available(value1));
                ignore _sendToken1(false, toid, sa_pool, [], [icrc1Account], [value1], ?sa_pool, null);
                resValue1 := Nat.sub(value1, _getFee1());
            };
            saga.close(toid);
            _putWithdrawing(account, toid);
            // await* _ictcSagaRun(toid, false);
        };
        return (toid, resValue0, resValue1);
    };
    private func _autoWithdraw(_icrc1Account: ICRC1.Account, _threshold: ?Amount) : SagaTM.Toid{ // icdex_; brokers
        let token0_threshold = Option.get(_threshold, setting.UNIT_SIZE * 1000);
        let token1_threshold = token0_threshold * icdex_lastPrice.price / setting.UNIT_SIZE;
        let account = Tools.principalToAccountBlob(_icrc1Account.owner, _toSaNat8(_icrc1Account.subaccount));
        let balances = _getAccountBalance(account);
        if (balances.token0.available >= token0_threshold or balances.token1.available >= token1_threshold){
            let (toid, value0, value1) = _withdraw(_icrc1Account.owner, null, null, _toSaNat8(_icrc1Account.subaccount));
            return toid;
        };
        return 0;
    };

    /// Returns PoolAccount and FeeAccount
    public query func getPairAddress() : async {pool: (ICRC1.Account, Address); fees: (ICRC1.Account, Address)}{
        let pairCanisterId = Principal.fromActor(this);
        return {
            pool = ({owner = pairCanisterId; subaccount = ?Blob.fromArray(sa_zero) }, Hex.encode(Tools.principalToAccount(pairCanisterId, ?sa_zero)));
            fees = ({owner = icdexRouter; subaccount = null }, Hex.encode(Tools.principalToAccount(icdexRouter, null)));
        };
    };

    /// Returns the balance of PoolAccount
    public query func poolBalance(): async {token0: Amount; token1: Amount}{
        return icdex_poolBalance;
    };

    /// Returns the balance kept in PoolAccount by a trader. (The result of the query may not reflect the latest situation when the ICTC is being executed but has not yet been completed.)
    public query func accountBalance(_a: Address): async KeepingBalance{
        let account = _getAccountId(_a);
        return _getAccountBalance(account);
    };

    /// Returns the balance kept in PoolAccount by a trader in a safe way. (An exception will be thrown when the ICTC is executing and has not yet completed. You should try the query again after a while)
    public query func safeAccountBalance(_a: Address): async {balance: KeepingBalance; pendingOrders: (Amount, Amount); price: STO.Price; unitSize: Nat}{
        let account = _getAccountId(_a);
        assert(_accountIctcDone(account));
        return {balance = _getAccountBalance(account); pendingOrders = _getPendingOrderLiquidity(?account); price = icdex_lastPrice.price; unitSize = setting.UNIT_SIZE };
    };

    /// Returns a trader's account settings, including whether `PoolMode` is turned on, whether `KeepingBalanceInTraderAccount` is turned on, and so on.
    public query func accountSetting(_a: Address): async AccountSetting{
        let account = _getAccountId(_a);
        _defaultConfig(account);
        return _getAccountSetting(account);
    };

    /// In the PoolMode scenario, the trader wants to deposit the ICRC1 token into the TraderAccount, he needs to get the DepositAccount address first.
    /// This is a query method, if called off-chain (e.g., web-side), You should generate the account address directly using the 
    /// following rule: `{owner = pair_canister_id; subaccount = ?your_accountId }`.
    public query func getDepositAccount(_account: Address) : async (ICRC1.Account, Address){ 
        let sa_account = _getAccountId(_account);
        return ({owner = Principal.fromActor(this); subaccount = _toOptSub(sa_account) }, _accountIdToHex(_getPairAccount(sa_account)));
    };

    /// Trader configures `ExchangeMode` and `KeepingBalanceInTraderAccount`.  
    /// Some roles require specific configurations
    /// - Fee recipient: enKeepingBalance = true;
    /// - Broker: enKeepingBalance = true;
    /// - Vip-maker: exMode = #PoolMode, enKeepingBalance = true;
    /// - Pro-trader: exMode = #PoolMode, enKeepingBalance = true;
    ///
    /// Arguments:
    /// - exMode: {#PoolMode; #TunnelMode}. Set ExchangeMode to #PoolMode or #TunnelMode, default is #TunnelMode.
    /// - enKeepingBalance: Bool. Whether to turn on KeepingBalanceInTraderAccount.
    public shared(msg) func accountConfig(_exMode: {#PoolMode; #TunnelMode}, _enKeepingBalance: Bool, _sa: ?Sa) : async (){
        let account = Tools.principalToAccountBlob(msg.caller, _sa);
        // Default:
        if (account == Tools.principalToAccountBlob(icdexRouter, null)){ // Fee recipient
            assert(_enKeepingBalance == true);
        };
        if (Option.isSome(Trie.get(stats_brokers, keyb(account), Blob.equal))){ // broker
            assert(_enKeepingBalance == true);
        };
        if (_getMakerRebateRate(account) > 0){ //vip-maker
            assert(_exMode == #PoolMode and _enKeepingBalance == true);
        };
        if (_isProTrader(account)){ // pro-trader
            assert(_exMode == #PoolMode and _enKeepingBalance == true);
        };
        switch(_exMode){
            case(#PoolMode){
                _accountConfig(account, ?true, ?_enKeepingBalance);
            };
            case(#TunnelMode){
                _accountConfig(account, ?false, ?_enKeepingBalance);
            };
        };
    };

    /// Trader deposits funds into TraderAccount (tokens are kept in the PoolAccount of the trading pair).
    public shared(msg) func deposit(_token: {#token0;#token1}, _value: Amount, _sa: ?Sa) : async (){
        if (not(_notPaused(?msg.caller) and initialized)){
            throw Error.reject("400: Trading pair has been suspended."); 
        };
        ignore await* _deposit(_token, {owner = msg.caller; subaccount = _toSaBlob(_sa)}, _value);
        // let account = Tools.principalToAccountBlob(msg.caller, _sa);
        // await* _deposit(msg.caller, _token, account, _value);
    };

    /// This method can be called by the trader to return funds exceptionally left in the DepositAccount when there are 
    /// no deposits being processed.
    public shared(msg) func depositFallback(_sa: ?Sa) : async (value0: Amount, value1: Amount){
        if (not(_notPaused(?msg.caller) and initialized)){
            throw Error.reject("400: Trading pair has been suspended."); 
        };
        let account = Tools.principalToAccountBlob(msg.caller, _sa);
        await* _checkOverload(?account);
        return await* _depositFallback(msg.caller, _sa);
    };

    /// Trader retrieves funds from TraderAccount (tokens are sent from PoolAccount to trader wallet).
    public shared(msg) func withdraw(_value0: ?Amount, _value1: ?Amount, _sa: ?Sa) : async (value0: Amount, value1: Amount){
        if (not(_notPaused(?msg.caller) and initialized)){
            throw Error.reject("400: Trading pair has been suspended."); 
        };
        let account = Tools.principalToAccountBlob(msg.caller, _sa);
        await* _checkOverload(?account);
        let (toid, value0, value1) = _withdraw(msg.caller, _value0, _value1, _sa);
        if (toid > 0){
            await* _ictcSagaRun(toid, false); 
        };
        return (value0, value1);
    };

    /// Similar to withdraw(), try to call it as synchronous as possible when called by a pro-trader, but still asynchronous when ICTC is busy.
    public shared(msg) func withdraw2(_value0: ?Amount, _value1: ?Amount, _sa: ?Sa) : async (value0: Amount, value1: Amount, status: {#Completed; #Pending}){
        if (not(_notPaused(?msg.caller) and initialized)){
            throw Error.reject("400: Trading pair has been suspended."); 
        };
        let account = Tools.principalToAccountBlob(msg.caller, _sa);
        await* _checkOverload(?account);
        let (toid, value0, value1) = _withdraw(msg.caller, _value0, _value1, _sa);
        var status: {#Completed; #Pending} = #Completed;
        if (toid > 0){
            var count : Nat = 0;
            while (not(_getSaga().isCompleted(toid)) and count < 5){ // Up to 5 attempts
                count += 1;
                await* _ictcSagaRun(toid, _isProTrader(account));
            };
            // If the transaction status is #Doing, the result of its execution will become an asynchronous return.
            if (not(_getSaga().isCompleted(toid))){
                status := #Pending;
            };
        };
        return (value0, value1, status);
    };

    /// Checks for abnormal PoolAccount balances.
    public shared(msg) func checkPoolBalance() : async (?Bool, {result: Bool; total: { token0: Amount; token1: Amount }; pool: { token0: Amount; token1: Amount }}){
        assert(_onlyOwner(msg.caller));
        return (await* _checkNativeBalance(), _checkSumPoolBalance());
    };

    /* ===========================
    *  strategy order section
    ============================== */
    // Note: A `Strategy order` is a strategy rule configuration that does not place a trade order into the order book until it is triggered. 
    // A `trade order` is a real order in the order book and is what is normally referred to as a `Trade`.

    private var sto_lastWorkPrice: Nat = 0; 
    private var sto_lastWorkTime: Timestamp = 0; 
    private var sto_lastWorkTime2: Timestamp = 0; 
    private var sto_isWorking: Bool = false; 
    private var sto_lastGridOrders: [(STO.Soid, STO.ICRC1Account, OrderPrice)] = []; // for debug
    // Whether to enable strategic orders for trading pair
    private stable var enableStrategyOrders: Bool = true;
    // Policy order global configuration
    private stable var sto_setting: STO.Setting = {
        poFee1 = 2_000_000_000; // ICL (smallest_units). Fixed costs when configuring the pro-order strategy
        poFee2 = 0.0005; // When an order from pro-order is filled, token0/token1 will be charged proportionally as a fee.
        sloFee1 = 100_000_000; // ICL (smallest_units). Fixed costs when configuring the stop-loss-order strategy
        sloFee2 = 0.0005; // When an order from stop-loss-order is filled, token0/token1 will be charged proportionally as a fee.
        gridMaxPerSide = 3; // Maximum number of grids on one side of the grid order. This configuration for vip-maker is multiplied by 2.
        proCountMax = 5; // Maximum number of pro-orders allowed to be created per trader.
        stopLossCountMax = 10; // Maximum number of stop-loss-orders allowed to be created per trader.
    };
    private func _awaitFunc() : async (){};
    private func _isProTrader(_a: AccountId) : Bool{
        switch(Trie.get(icdex_userProOrderList, keyb(_a), Blob.equal)){
            case(?(list)){ return List.size(list) > 0 };
            case(_){
                switch(Trie.get(icdex_userStopLossOrderList, keyb(_a), Blob.equal)){
                    case(?(list)){ return List.size(list) > 0 };
                    case(_){ return false };
                };
            };
        };
    };
    private func _isSTOrder(_txid: Txid) : Bool{
        Option.isSome(STO.getSoidByTxid(icdex_stOrderTxids, _txid));
    };
    private func _onlyStratOrderOwner(_a: AccountId, _soid: STO.Soid) : Bool{
        switch(STO.get(icdex_stOrderRecords, _soid)){
            case(?po){ return _a == Tools.principalToAccountBlob(po.icrc1Account.owner, _toSaNat8(po.icrc1Account.subaccount))};
            case(_){ return false };
        };
    };
    private func _chargeSTOrderFee1(_account: ICRC1.Account, _stType: STO.STType, _act: {#Create; #Update}) : async* (){
        let icdex_account = Tools.principalToAccountBlob(icdexRouter, null);
        var value : Nat = 0;
        switch(_stType, _act){
            case(#StopLossOrder, #Create){
                value := sto_setting.sloFee1;
            };
            case(#StopLossOrder, #Update){
                value := sto_setting.sloFee1 * 5 / 100;
            };
            case(_, #Create){
                value := sto_setting.poFee1;
            };
            case(_, #Update){
                value := sto_setting.poFee1 * 5 / 100;
            };
        };
        let account = Tools.principalToAccountBlob(_account.owner, _toSaNat8(_account.subaccount));
        if (value > 0 and _getMakerRebateRate(account) == 0){ // Free for VIP-Maker
            let router: actor{
                sys_getConfig: shared query () -> async {
                    aggregator: Principal;
                    blackhole: Principal;
                    icDao: Principal;
                    nftPlanetCards: Principal;
                    sysToken: Principal;
                    sysTokenFee: Nat;
                    creatingPairFee: Nat;
                    creatingMakerFee: Nat;
                }
            } = actor(Principal.toText(icdexRouter));
            let sysToken = (await router.sys_getConfig()).sysToken;
            await* _transferFrom(sysToken, _account, {owner = icdexRouter; subaccount = null}, value, null);
        };
    };
    private func _chargeSTOrderFee2(_a: AccountId, _stType: STO.STType, _value0: Amount, _value1: Amount) : (token0: Amount, token1: Amount){
        let icdex_account = Tools.principalToAccountBlob(icdexRouter, null);
        switch(_stType){
            case(#StopLossOrder){
                let balances = _getAccountBalance(_a);
                let fee0 = _floatToNat(_natToFloat(_value0) * sto_setting.sloFee2);
                let fee1 = _floatToNat(_natToFloat(_value1) * sto_setting.sloFee2);
                if (fee0 > 0 and balances.token0.available >= fee0){
                    ignore _subAccountBalance(_a, #token0, #available(fee0));
                    ignore _addAccountBalance(icdex_account, #token0, #available(fee0));
                };
                if (fee1 > 0 and balances.token1.available >= fee1){
                    ignore _subAccountBalance(_a, #token1, #available(fee1));
                    ignore _addAccountBalance(icdex_account, #token1, #available(fee1));
                };
                return (fee0, fee1);
            };
            case(_){
                let balances = _getAccountBalance(_a);
                let fee0 = _floatToNat(_natToFloat(_value0) * sto_setting.poFee2);
                let fee1 = _floatToNat(_natToFloat(_value1) * sto_setting.poFee2);
                if (fee0 > 0 and balances.token0.available >= fee0){
                    ignore _subAccountBalance(_a, #token0, #available(fee0));
                    ignore _addAccountBalance(icdex_account, #token0, #available(fee0));
                };
                if (fee1 > 0 and balances.token1.available >= fee1){
                    ignore _subAccountBalance(_a, #token1, #available(fee1));
                    ignore _addAccountBalance(icdex_account, #token1, #available(fee1));
                };
                return (fee0, fee1);
            };
        };
    };

    // Attempt to place trade orders, trade order is abandoned if unsuccessful (will not be reordered)
    private func _openOrders(_args: [(STO.Soid, STO.ICRC1Account, OrderPrice)]): async* (){
        var count : Nat = 0;
        if (_args.size() > 0){
            await _awaitFunc();
        };
        for ((soid, icrc1Account, orderPrice) in _args.vals()){
            let account = Tools.principalToAccountBlob(icrc1Account.owner, _toSaNat8(icrc1Account.subaccount));
            let balances = _getAccountBalance(account); // balances.token0.available;  balances.token1.available
            let side = OrderBook.side(orderPrice);
            let quantity = OrderBook.quantity(orderPrice);
            let amount = OrderBook.amount(orderPrice);
            let (isExisting, optTxid) = STO.isPendingOrder(icdex_stOrderRecords, soid, side, orderPrice.price);
            if (isExisting and Option.isNull(optTxid) and ((side == #Sell and quantity <= balances.token0.available) or (side == #Buy and amount <= balances.token1.available))){
                count += 1;
                try{
                    if (count % 5 == 0){ // Execute _awaitFunc() every 5 trades, otherwise may face insufficient number of executable instructions.
                        try{
                            countAsyncMessage += 1;
                            await _awaitFunc();
                            countAsyncMessage -= Nat.min(1, countAsyncMessage);
                        }catch(e){
                            countAsyncMessage -= Nat.min(1, countAsyncMessage);
                        };
                    };
                    let res = await* _trade(icrc1Account.owner, orderPrice, #LMT, null, null, _toSaNat8(icrc1Account.subaccount), null, null, true);
                    switch(res){ 
                        case(#ok(r)){
                            let (isExisting, optTxid) = STO.isPendingOrder(icdex_stOrderRecords, soid, side, orderPrice.price);
                            if (isExisting and Option.isNull(optTxid)){
                                if (r.status == #Pending){ // maker
                                    icdex_stOrderRecords := STO.putPendingOrder(icdex_stOrderRecords, soid, side, (?r.txid, orderPrice.price, quantity));
                                    icdex_stOrderTxids := STO.putSTOTxids(icdex_stOrderTxids, r.txid, soid);
                                }else if (r.status == #Closed or r.status == #Cancelled){ // taker
                                    // filled & closed
                                    icdex_stOrderRecords := STO.removePendingOrderByPrice(icdex_stOrderRecords, soid, side, orderPrice.price);
                                };
                                switch(Trie.get(icdex_orders, keyb(r.txid), Blob.equal)){
                                    case(?(order)){
                                        let remainingQuantity = OrderBook.quantity(order.remaining);
                                        let remainingAmount = OrderBook.amount(order.remaining);
                                        let (stats_inAmount, stats_outAmount) = _orderFilledStats(side, Nat.sub(quantity, Nat.min(quantity, remainingQuantity)), Nat.sub(amount, Nat.min(amount, remainingAmount)));
                                        icdex_stOrderRecords := STO.updateStats(icdex_stOrderRecords, soid, {orderCount = 1; errorCount = 0; totalInAmount = stats_inAmount; totalOutAmount = stats_outAmount;});
                                        switch(STO.get(icdex_stOrderRecords, soid)){
                                            case(?sto){
                                                let (feeToken0, feeToken1) = _chargeSTOrderFee2(account, sto.stType, stats_inAmount.token0, stats_inAmount.token1);
                                                _update(r.txid, null, null, null, null, ?{fee0 = feeToken0; fee1 = feeToken1}, null, null);
                                            };
                                            case(_){};
                                        };
                                    };
                                    case(_){};
                                };
                                icdex_stOrderRecords := STO.updateIcebergOrder(icdex_stOrderRecords, soid, null, ?r.txid); // for IcebergOrder
                            }else{
                                ignore _cancelOrder(null, r.txid, null);
                            };
                        };
                        case(#err(e)){
                            icdex_stOrderRecords := STO.removePendingOrderByPrice(icdex_stOrderRecords, soid, side, orderPrice.price);
                            icdex_stOrderRecords := STO.updateStats(icdex_stOrderRecords, soid, {orderCount = 0; errorCount = 1; totalInAmount = {token0=0; token1=0}; totalOutAmount = {token0=0; token1=0};});
                        };
                    };
                }catch(e){
                    icdex_stOrderRecords := STO.removePendingOrderByPrice(icdex_stOrderRecords, soid, side, orderPrice.price);
                    icdex_stOrderRecords := STO.updateStats(icdex_stOrderRecords, soid, {orderCount = 0; errorCount = 1; totalInAmount = {token0=0; token1=0}; totalOutAmount = {token0=0; token1=0};});
                };
            };
        };
        await* _ictcSagaRun(0, false);  
    };

    // Canceling an order in an order book
    private func _cancelOrder(_soid: ?Nat, _txid: Txid, _side: ?OrderBook.OrderSide) : SagaTM.Toid{
        // update-231226: Fixed the issue that pending order records could not be deleted.
        if (_isPending(_txid)){
            let saga = _getSaga();
            let toid = saga.create("cancel_by_grid", #Forward, ?_txid, null);
            let ttids = _cancel(toid, _txid, _side);
            saga.close(toid);
            if (ttids.size() == 0){
                ignore saga.doneEmpty(toid);
            };
            return toid;
        }else{
            switch(STO.getSoidByTxid(icdex_stOrderTxids, _txid), _soid){
                case(?soid1, _){
                    icdex_stOrderRecords := STO.removePendingOrder(icdex_stOrderRecords, soid1, _txid); 
                    icdex_stOrderTxids := STO.removeSTOTxids(icdex_stOrderTxids, _txid);
                };
                case(_, ?soid2){
                    icdex_stOrderRecords := STO.removePendingOrder(icdex_stOrderRecords, soid2, _txid); 
                };
                case(_){};
            };
            return 0;
        };
    };

    // Remove strategies that have been disabled for more than 24 hours
    private func _autoDeleteSTO() : (){
        for ((soid, item) in Trie.iter(icdex_stOrderRecords)){
            if (item.status == #Deleted and _now() > item.triggerTime + 24 * 3600){
                let account = Tools.principalToAccountBlob(item.icrc1Account.owner, _toSaNat8(item.icrc1Account.subaccount));
                icdex_stOrderRecords := STO.remove(icdex_stOrderRecords, soid);
                if (item.stType == #StopLossOrder){
                    icdex_userStopLossOrderList := STO.removeUserSLOList(icdex_userStopLossOrderList, account, soid);
                }else{
                    icdex_userProOrderList := STO.removeUserPOList(icdex_userProOrderList, account, soid);
                };
            }else if (item.status == #Stopped and _now() > item.triggerTime + 24 * 3600){
                switch(item.strategy){
                    case(#StopLossOrder(slo)){
                        if (Option.isSome(slo.triggeredOrder)){
                            icdex_stOrderRecords := STO.updateStatus(icdex_stOrderRecords, soid, #Deleted);
                        };
                    };
                    case(_){};
                };
            };
        };
    };

    // // Strategy Trigger Portal
    // private func _stoTrigger(_soid: STO.Soid) : (STO.STStatus, [(STO.Soid, STO.ICRC1Account, OrderPrice)]){
    //     assert(icdex_lastPrice.price > 0);
    //     switch(STO.get(icdex_stOrderRecords, _soid)){
    //         case(?sto){
    //             if (sto.status == #Running){
    //                 switch(sto.strategy){
    //                     case(#StopLossOrder(v)){ return _sloTrigger(_soid, sto) };
    //                     case(#GridOrder(v)){ return _goTrigger(_soid, sto) };
    //                     case(#IcebergOrder(v)){ return _ioTrigger(_soid, sto) };
    //                     case(#VWAP(v)){ return _vwapTrigger(_soid, sto) };
    //                     case(#TWAP(v)){ return _twapTrigger(_soid, sto) };
    //                 };
    //             };
    //             return (sto.status, []);
    //         };
    //         case(_){ return (#Deleted, []) };
    //     };
    // };

    // Strategy Trigger Portal
    private func _stoTrigger(_soid: STO.Soid) : (STO.STStatus, [(STO.Soid, STO.ICRC1Account, OrderPrice)]){
        assert(icdex_lastPrice.price > 0);
        let price = icdex_lastPrice.price;
        let unitSize = setting.UNIT_SIZE;
        switch(STO.get(icdex_stOrderRecords, _soid)){
            case(?sto){
                if (sto.status == #Running){
                    let account = Tools.principalToAccountBlob(sto.icrc1Account.owner, _toSaNat8(sto.icrc1Account.subaccount));
                    let balances = _getAccountBalance(account);
                    switch(sto.strategy){
                        case(#StopLossOrder(v)){ 
                            let (data, status, ordersTriggered) = STO.sloTrigger(icdex_stOrderRecords, balances, price, unitSize, _soid, sto); 
                            icdex_stOrderRecords := data;
                            return (status, ordersTriggered);
                        };
                        case(#GridOrder(v)){ 
                            let (data, status, ordersTriggered, ordersToBeCancel) = STO.goTrigger(icdex_stOrderRecords, balances, price, unitSize, _soid, sto); 
                            icdex_stOrderRecords := data; // update-231226: Fix the issue of invalid deletion
                            for (item in ordersToBeCancel.vals()){
                                ignore _cancelOrder(?_soid, item.0, item.1);
                            };
                            return (status, ordersTriggered);
                        };
                        case(#IcebergOrder(v)){ 
                            var txnStatus: ?DRC205.Status = null;
                            switch(v.lastTxid){
                                case(?txid){
                                    switch(drc205.get(txid)){
                                        case(?txn){
                                            txnStatus := ?txn.status;
                                        };
                                        case(_){};
                                    };
                                };
                                case(_){};
                            };
                            let (data, status, ordersTriggered) = STO.ioTrigger(icdex_stOrderRecords, balances, price, unitSize, txnStatus, _soid, sto); 
                            icdex_stOrderRecords := data;
                            return (status, ordersTriggered);
                        };
                        case(#VWAP(v)){
                            let totalVol = icdex_totalVol;
                            let vol24h = _24h().vol24h;
                            let (data, status, ordersTriggered) = STO.vwapTrigger(icdex_stOrderRecords, balances, price, unitSize, totalVol, vol24h, _soid, sto);
                            icdex_stOrderRecords := data;
                            return (status, ordersTriggered);
                        };
                        case(#TWAP(v)){ 
                            let (data, status, ordersTriggered) = STO.twapTrigger(icdex_stOrderRecords, balances, price, unitSize, _soid, sto); 
                            icdex_stOrderRecords := data;
                            return (status, ordersTriggered);
                        };
                    };
                };
                return (sto.status, []);
            };
            case(_){ return (#Deleted, []) };
        };
    };

    // Check that the parameters of the grid order are in accordance with the specifications
    private func _checkGridSetting(_lowerLimit: ?STO.Price, _upperLimit: ?STO.Price, _spread: ?{#Arith: STO.Price; #Geom: STO.Ppm }, _amount: ?{#Token0: Nat; #Token1: Nat; #Percent: ?STO.Ppm }): Bool{
        var res: Bool = true;
        switch(_lowerLimit, _upperLimit){
            case(?lowerLimit, ?upperLimit){
                if (lowerLimit >= upperLimit or lowerLimit == 0){ res := false };
            };
            case(_, _){};
        };
        switch(_spread){
            case(?#Arith(v)){
                if (v < icdex_lastPrice.price / 1000){ res := false };
            };
            case(?#Geom(v)){
                if (v < 1000){ res := false }; // 1/1000
            };
            case(_){};
        };
        switch(_amount){
            case(?#Token0(v)){
                if (v < setting.UNIT_SIZE*10){ res := false };
            };
            case(?#Token1(v)){
                if (v < icdex_lastPrice.price*10 ){ res := false };
            };
            case(?#Percent(?v)){
                if (v < 100 ){ res := false }; // 1/10000
            };
            case(_){};
        };
        return res;
    };

    // Strategy volume statistics
    private func _orderFilledStats(_side: {#Buy; #Sell}, _quantity: Nat, _amount: Nat): (_in: {token0: Amount; token1: Amount}, _out: {token0: Amount; token1: Amount}){
        var stats_inAmount: {token0: Amount; token1: Amount} = {token0 = 0; token1 = 0};
        var stats_outAmount: {token0: Amount; token1: Amount} = {token0 = 0; token1 = 0};
        switch(_side){
            case(#Buy){ 
                stats_inAmount := {token0 = _quantity; token1 = 0}; 
                stats_outAmount := {token0 = 0; token1 = _amount};
            };
            case(#Sell){
                stats_inAmount := {token0 = 0; token1 = _amount}; 
                stats_outAmount := {token0 = _quantity; token1 = 0};
            };
        };
        return (stats_inAmount, stats_outAmount);
    };

    // Strategy worktop. It is triggered by the matching engine when a order is matched and all active strategy orders are executed in a loop.
    // Notes:
    // - Ordinary orders may trigger a strategy to place an order when they are filled, while strategy orders will not trigger a strategy to 
    // place an order again.
    // - The triggers of the strategy do not guarantee that the order will be placed successfully or that it will be filled immediately, and 
    // there may be multiple uncertainties.
    // - /// - When it is busy, the trigger price may have a deviation of about 0.5%, and the system will ignore multiple triggers within 10 seconds 
    // and trigger only once.
    private func _hook_stoWorktop(_soid: ?STO.Soid, _side: ?OrderBook.OrderSide) : async (){
        let price = icdex_lastPrice.price;
        var openingOrders: [(STO.Soid, STO.ICRC1Account, OrderPrice)] = [];
        if (Option.isSome(_soid) or not(sto_isWorking) or _now() >= sto_lastWorkTime + 10 or price <= sto_lastWorkPrice*995/1000 or price >= sto_lastWorkPrice*1005/1000){
            sto_lastWorkPrice := price;
            sto_lastWorkTime := _now();
            // StopLossOrder
            if (_side == ?#Buy){
                var completed: Bool = false;
                var orderList = icdex_activeStopLossOrderList.buy;
                while(not(completed)){
                    let (item, newList) = List.pop(orderList);
                    switch(item){
                        case(?(soid, triggerPrice)){
                            if (price >= triggerPrice){
                                let (status, preOpenOrders) = _stoTrigger(soid);
                                openingOrders := Tools.arrayAppend(openingOrders, preOpenOrders);
                                icdex_stOrderRecords := STO.updateStatus(icdex_stOrderRecords, soid, status);
                                orderList := newList;
                            }else{
                                completed := true;
                            };
                        };
                        case(_){
                            completed := true;
                        };
                    };
                    if (Option.isNull(orderList)){
                        completed := true;
                    }
                };
                icdex_activeStopLossOrderList := { buy = orderList; sell = icdex_activeStopLossOrderList.sell };
            };
            if (_side == ?#Sell){
                var completed: Bool = false;
                var orderList = icdex_activeStopLossOrderList.sell;
                while(not(completed)){
                    let (item, newList) = List.pop(orderList);
                    switch(item){
                        case(?(soid, triggerPrice)){
                            if (price <= triggerPrice){
                                let (status, preOpenOrders) = _stoTrigger(soid);
                                openingOrders := Tools.arrayAppend(openingOrders, preOpenOrders);
                                icdex_stOrderRecords := STO.updateStatus(icdex_stOrderRecords, soid, status);
                                orderList := newList;
                            }else{
                                completed := true;
                            };
                        };
                        case(_){
                            completed := true;
                        };
                    };
                    if (Option.isNull(orderList)){
                        completed := true;
                    }
                };
                icdex_activeStopLossOrderList := { buy = icdex_activeStopLossOrderList.buy; sell = orderList };
            };
            // ProOrder
            var pendingPOList = List.nil<STO.Soid>();
            var poCount : Nat = 0;
            // if (Option.isSome(_soid)){ // update-231226: De-prioritize
            //     let thisSoid = Option.get(_soid, 0);
            //     let (status, preOpenOrders) = _stoTrigger(thisSoid);
            //     openingOrders := Tools.arrayAppend(openingOrders, preOpenOrders);
            //     if (status != #Running){
            //         icdex_stOrderRecords := STO.updateStatus(icdex_stOrderRecords, thisSoid, status);
            //     };
            // }else 
            if (not(sto_isWorking) or _now() >= sto_lastWorkTime2 + 15 * 60){ // global lock
                sto_isWorking := true;
                sto_lastWorkTime2 := _now();
                for (soid in List.toArray(icdex_activeProOrderList).vals()){
                    poCount += 1;
                    let (status, preOpenOrders) = _stoTrigger(soid);
                    openingOrders := Tools.arrayAppend(openingOrders, preOpenOrders);
                    if (status == #Running){
                        pendingPOList := List.push(soid, pendingPOList);
                    }else{
                        icdex_stOrderRecords := STO.updateStatus(icdex_stOrderRecords, soid, status);
                    };
                    if (poCount == 10 or poCount % 50 == 0){
                        await _awaitFunc(); // Prevents insufficient number of available execution instructions
                    };
                    sto_lastWorkTime2 := _now();
                };
                sto_isWorking := false;
                icdex_activeProOrderList := pendingPOList;
            };
        };
        // place orders
        if (openingOrders.size() > 0){
            sto_lastGridOrders := openingOrders;
            try {
                countAsyncMessage += 4;
                await* _openOrders(openingOrders);
                countAsyncMessage -= Nat.min(4, countAsyncMessage);
            }catch(e){
                countAsyncMessage -= Nat.min(4, countAsyncMessage);
                if(icdex_debug){ throw Error.reject(Error.message(e));  };
            };
        };
    };

    // Hook on trade order closed
    private func _hook_close(_txid: Txid): (){
        switch(STO.getSoidByTxid(icdex_stOrderTxids, _txid)){
            case(?soid){
                icdex_stOrderRecords := STO.removePendingOrder(icdex_stOrderRecords, soid, _txid);
                icdex_stOrderTxids := STO.removeSTOTxids(icdex_stOrderTxids, _txid);
            };
            case(_){};
        };
    };

    // Hook on trade order filled
    private func _hook_fill(_txid: Txid, _side: OrderSide, _quantity: Amount, _amount: Amount) : (){
        switch(STO.getSoidByTxid(icdex_stOrderTxids, _txid)){ // Can only process orders for maker roles
            case(?soid){
                let (stats_inAmount, stats_outAmount) = _orderFilledStats(_side, _quantity, _amount);
                switch(STO.get(icdex_stOrderRecords, soid)){
                    case(?sto){ 
                        let account = Tools.principalToAccountBlob(sto.icrc1Account.owner, _toSaNat8(sto.icrc1Account.subaccount));
                        let (feeToken0, feeToken1) = _chargeSTOrderFee2(account, sto.stType, stats_inAmount.token0, stats_inAmount.token1);
                        _update(_txid, null, null, null, null, ?{fee0 = feeToken0; fee1 = feeToken1}, null, null);
                    };
                    case(_){};
                };
                icdex_stOrderRecords := STO.updateStats(icdex_stOrderRecords, soid, {orderCount = 0; errorCount = 0; totalInAmount = stats_inAmount; totalOutAmount = stats_outAmount;});
            };
            case(_){};
        };
    };

    // Hook on trade order cancelled
    private func _hook_cancel(_txid: Txid, _price: STO.Price) : (){
        switch(STO.getSoidByTxid(icdex_stOrderTxids, _txid)){
            case(?soid){
                icdex_stOrderRecords := STO.removePendingOrder(icdex_stOrderRecords, soid, _txid); 
                icdex_stOrderTxids := STO.removeSTOTxids(icdex_stOrderTxids, _txid);
            };
            case(_){};
        };
    };

    /// Cancel all orders in the order book for a strategy.
    public shared(msg) func sto_cancelPendingOrders(_soid: STO.Soid, _sa: ?Sa) : async (){
        let icrc1Account: STO.ICRC1Account = {owner = msg.caller; subaccount = _toSaBlob(_sa) };
        let account = Tools.principalToAccountBlob(msg.caller, _sa);
        assert(_onlyStratOrderOwner(account, _soid));
        switch(STO.get(icdex_stOrderRecords, _soid)){
            case(?(sto)){
                let saga = _getSaga();
                for ((optTxid, price, quantity) in sto.pendingOrders.buy.vals()){
                    switch(optTxid){
                        case(?txid){ ignore _cancelOrder(?_soid, txid, ?#Buy); };
                        case(_){
                            icdex_stOrderRecords := STO.removePendingOrderByPrice(icdex_stOrderRecords, _soid, #Buy, price);
                        };
                    };
                };
                for ((optTxid, price, quantity) in sto.pendingOrders.sell.vals()){
                    switch(optTxid){
                        case(?txid){ ignore _cancelOrder(?_soid, txid, ?#Sell); };
                        case(_){
                            icdex_stOrderRecords := STO.removePendingOrderByPrice(icdex_stOrderRecords, _soid, #Sell, price);
                        };
                    };
                };
                icdex_stOrderRecords := STO.removeGridPrices(icdex_stOrderRecords, _soid);
                await* _ictcSagaRun(0, false);
            };
            case(_){};
        };
    };

    /// Create a pro-order strategy, which includes GridOrder, IcebergOrder, VWAP, and TWAP.  
    ///
    /// Notes (applicable to all strategy order related methods):
    /// - Price: The price of strategy orders is Nat, indicating how much token1 (smallest units) are needed to purchase UNIT_SIZE token0 (smallest units).
    /// - Ppm: parts per million. "1 ppm" means "1 / 1000000".
    /// - Timestamp: Timestamp in seconds.
    /// - #Arith: Arithmetic.
    /// - #Geom: Geometric (ppm).
    /// - ppmFactor: Default grid order amount factor, initialized when the strategy is created. `ppmFactor = 1000000 * 1/n * (n ** (1/10))`, 
    ///     Where n is `(n1 + n2) / 2`, and n1, n2 is between 2 and 200. n1 is the number of grids between the latest price and the lowerLimit, 
    ///     and n2 is the number of grids between the latest price and the upperLimit.
    ///
    /// Arguments:
    /// - arg: {  
    ///    ```
    ///    #GridOrder: { // Grid strategy  
    ///        lowerLimit: Price; // Minimum Grid Price Limit  
    ///        upperLimit: Price; // Maximum Grid Price Limit  
    ///        spread: {#Arith: Price; #Geom: Ppm }; // Spread between two neighboring grids  
    ///        amount: {#Token0: Nat; #Token1: Nat; #Percent: ?Ppm }; // Amount of order placed per grid. `#Percent: ?n` Indicates n/1000000 of the funds in the TraderAccount for each grid order, and if n is not specified it defaults to the value `ppmFactor`.  
    ///    };  
    ///    #IcebergOrder: { // Iceberg strategy  
    ///        startingTime: Timestamp; // Strategy start time  
    ///        endTime: Timestamp; // Strategy end time  
    ///        order: {side: OB.OrderSide; price: Price; }; // When the strategy is triggered, place one #Buy/#Sell order at price `price` at a time.  
    ///        amountPerTrigger: {#Token0: Nat; #Token1: Nat}; // The amount of the order placed at each trigger. The minimum value is setting.UNIT_SIZE * 10 smallest_units token0 (or equivalently token0).  
    ///        totalLimit: {#Token0: Nat; #Token1: Nat}; // Maximum cumulative order amount.  
    ///    };  
    ///    #VWAP: { // VWAP strategy  
    ///        startingTime: Timestamp; // Strategy start time  
    ///        endTime: Timestamp; // Strategy end time  
    ///        order: {side: OB.OrderSide; priceSpread: Price; priceLimit: Price; }; // When the strategy is triggered, place one #Buy/#Sell order at the latest price plus slippage (+/- priceSpread) at a time.  
    ///        amountPerTrigger: {#Token0: Nat; #Token1: Nat}; // The amount of the order placed at each trigger. The minimum value is setting.UNIT_SIZE * 10 smallest_units token0 (or equivalently token0).  
    ///        totalLimit: {#Token0: Nat; #Token1: Nat}; // Maximum cumulative order amount.  
    ///        triggerVol: {#Arith: Nat; #Geom: Ppm }; // An order is triggered for each `vol` of change in volume. `vol` is the token1 volume of the trading pair, vol = n when triggerVol is #Arith(n), vol = 24hour_vol * ppm / 1000000 when triggerVol is #Geom(ppm).  
    ///    };  
    ///    #TWAP: { // TWAP strategy  
    ///        startingTime: Timestamp; // Strategy start time  
    ///        endTime: Timestamp; // Strategy end time  
    ///        order: {side: OB.OrderSide; priceSpread: Price; priceLimit: Price; }; // When the strategy is triggered, place one #Buy/#Sell order at the latest price plus slippage (+/- priceSpread) at a time.  
    ///        amountPerTrigger: {#Token0: Nat; #Token1: Nat}; // The amount of the order placed at each trigger. The minimum value is setting.UNIT_SIZE * 10 smallest_units token0 (or equivalently token0).  
    ///        totalLimit: {#Token0: Nat; #Token1: Nat}; // Maximum cumulative order amount.  
    ///        triggerInterval: Nat; // secondsInterval between order triggers.  
    ///    };  
    ///    ```
    /// }
    /// - sa: ?Sa. Optionally specify the subaccount of the caller
    ///
    /// Returns:
    /// - res: STO.Soid. Returns strategy order ID.
    /// 
    public shared(msg) func sto_createProOrder(_arg: {
        #GridOrder: STO.GridOrderSetting;
        #IcebergOrder: STO.IcebergOrderSetting;
        #VWAP: STO.VWAPSetting;
        #TWAP: STO.TWAPSetting;
    }, _sa: ?Sa) : async STO.Soid{
        if (not(enableStrategyOrders)){
            throw Error.reject("400: The Strategy Order module is disabled!"); 
        };
        if (icdex_lastPrice.price == 0){
            throw Error.reject("458: Requires the pair to have at least one trade."); 
        };
        if (List.size(icdex_activeProOrderList) >= 2000){
            throw Error.reject("460: The number of pro-order strategies that the system can host cannot exceed 2,000."); 
        };
        let icrc1Account: STO.ICRC1Account = {owner = msg.caller; subaccount = _toSaBlob(_sa) };
        let account = Tools.principalToAccountBlob(msg.caller, _sa);
        let isVipMaker = _getMakerRebateRate(account) > 0;
        let balance = _getAccountBalance(account);
        if (balance.token0.available < setting.UNIT_SIZE * 100 and balance.token1.available < icdex_lastPrice.price * 100){
            throw Error.reject("452: Insufficient token0 or token1 balance. You SHOULD make a deposit first (Minimum amount: value "# Nat.toText(setting.UNIT_SIZE * 100) #" smallest_units token0)."); 
        };
        switch(_arg){
            case(#GridOrder(arg)){
                if (not(_checkGridSetting(?arg.lowerLimit, ?arg.upperLimit, ?arg.spread, ?arg.amount))){
                    throw Error.reject("453: Arguments unavailable."); 
                };
            };
            case(#IcebergOrder(arg)){
                let amountPerTrigger = (switch(arg.amountPerTrigger){case(#Token0(v)){ v }; case(#Token1(v)){ v / icdex_lastPrice.price * setting.UNIT_SIZE }});
                if (not(arg.startingTime < arg.endTime and arg.endTime > _now() and arg.order.price > 0 and amountPerTrigger >= setting.UNIT_SIZE * 10)){
                    throw Error.reject("453: Arguments unavailable."); 
                };
            };
            case(#VWAP(arg)){
                let amountPerTrigger = (switch(arg.amountPerTrigger){case(#Token0(v)){ v }; case(#Token1(v)){ v / icdex_lastPrice.price * setting.UNIT_SIZE }});
                if (not(arg.startingTime < arg.endTime and arg.endTime > _now() and amountPerTrigger >= setting.UNIT_SIZE * 10)){
                    throw Error.reject("453: Arguments unavailable."); 
                };
            };
            case(#TWAP(arg)){
                let amountPerTrigger = (switch(arg.amountPerTrigger){case(#Token0(v)){ v }; case(#Token1(v)){ v / icdex_lastPrice.price * setting.UNIT_SIZE }});
                if (not(arg.startingTime < arg.endTime and arg.endTime > _now() and amountPerTrigger >= setting.UNIT_SIZE * 10)){
                    throw Error.reject("453: Arguments unavailable."); 
                };
            };
        };
        if (_exchangeMode(account, null) != #PoolMode or not(_isKeepingBalanceInPair(account))){
            throw Error.reject("450: Pro-trader SHOULD turn on the `PoolMode` mode and turn on `Keepping Tokens in Pair`."); 
        };
        if (STO.userPOSize(icdex_userProOrderList, account) >= sto_setting.proCountMax){
            throw Error.reject("451: You can only place a maximum of "# Nat.toText(sto_setting.proCountMax) #" pro-orders (excluding stop loss orders)"); 
        };
        var initPrice = icdex_lastPrice.price;

        // charge fee
        switch(_arg){
            case(#GridOrder(arg)){ await* _chargeSTOrderFee1(icrc1Account, #GridOrder, #Create); };
            case(#IcebergOrder(arg)){ await* _chargeSTOrderFee1(icrc1Account, #IcebergOrder, #Create); };
            case(#VWAP(arg)){ await* _chargeSTOrderFee1(icrc1Account, #VWAP, #Create); };
            case(#TWAP(arg)){ await* _chargeSTOrderFee1(icrc1Account, #TWAP, #Create); };
        };
        var soid : Nat = 0;
        switch(_arg){
            case(#GridOrder(arg)){
                if (initPrice > 10_000_000_000_000){
                    initPrice := initPrice / 1_000_000_000_000 * 1_000_000_000_000;
                }else if (initPrice > 1_000_000_000){
                    initPrice := initPrice / 100_000_000 * 100_000_000;
                }else if (initPrice > 100_000){
                    initPrice := initPrice / 10_000 * 10_000;
                }else if (initPrice > 1_000){
                    initPrice := initPrice / 100 * 100;
                };
                let ppmFactor = STO.getPpmFactor(initPrice, arg.spread, arg.lowerLimit, arg.upperLimit);
                icdex_stOrderRecords := STO.new(icdex_stOrderRecords, icrc1Account, icdex_soid, #GridOrder({
                    setting = {
                        initPrice = initPrice; //*
                        lowerLimit = arg.lowerLimit;
                        upperLimit = arg.upperLimit;
                        gridCountPerSide = sto_setting.gridMaxPerSide * (if (isVipMaker){ 2 }else{ 1 }); //*
                        spread = arg.spread;
                        amount = arg.amount;
                        ppmFactor = ?ppmFactor; //*
                    };
                    gridPrices = {midPrice = null; buy = []; sell = [] };
                }));
                soid := icdex_soid;
            };
            case(#IcebergOrder(arg)){
                icdex_stOrderRecords := STO.new(icdex_stOrderRecords, icrc1Account, icdex_soid, #IcebergOrder({
                    setting = arg;
                    lastTxid = null;
                }));
                soid := icdex_soid;
            };
            case(#VWAP(arg)){
                icdex_stOrderRecords := STO.new(icdex_stOrderRecords, icrc1Account, icdex_soid, #VWAP({
                    setting = arg;
                    lastVol = null;
                }));
                soid := icdex_soid;
            };
            case(#TWAP(arg)){
                icdex_stOrderRecords := STO.new(icdex_stOrderRecords, icrc1Account, icdex_soid, #TWAP({
                    setting = arg;
                    lastTime = null;
                }));
                soid := icdex_soid;
            };
        };
        if (soid > 0){
            icdex_soid += 1;
            icdex_userProOrderList := STO.putUserPOList(icdex_userProOrderList, account, soid);
            icdex_activeProOrderList := STO.putActivePOList(icdex_activeProOrderList, soid);
        };
        return soid;
    };

    /// Update a pro-order strategy, arguments similar to the above.
    public shared(msg) func sto_updateProOrder(_soid: STO.Soid, _arg: {
        #GridOrder: {
            lowerLimit: ?STO.Price;
            upperLimit: ?STO.Price;
            spread: ?{#Arith: STO.Price; #Geom: STO.Ppm };
            amount: ?{#Token0: Nat; #Token1: Nat; #Percent: ?STO.Ppm };
            status: ?STO.STStatus;
        };
        #IcebergOrder: {setting: ?STO.IcebergOrderSetting; status: ?STO.STStatus;};
        #VWAP: {setting: ?STO.VWAPSetting; status: ?STO.STStatus;};
        #TWAP: {setting: ?STO.TWAPSetting; status: ?STO.STStatus;};
    }, _sa: ?Sa) : async STO.Soid{
        let icrc1Account: STO.ICRC1Account = {owner = msg.caller; subaccount = _toSaBlob(_sa) };
        let account = Tools.principalToAccountBlob(msg.caller, _sa);
        assert(_onlyStratOrderOwner(account, _soid));
        let isVipMaker = _getMakerRebateRate(account) > 0;
        switch(_arg){
            case(#GridOrder(arg)){
                if (not(_checkGridSetting(arg.lowerLimit, arg.upperLimit, arg.spread, arg.amount))){
                    throw Error.reject("453: Arguments unavailable."); 
                };
            };
            case(#IcebergOrder({setting = ?arg; status = status})){
                let amountPerTrigger = (switch(arg.amountPerTrigger){case(#Token0(v)){ v }; case(#Token1(v)){ v / icdex_lastPrice.price * setting.UNIT_SIZE }});
                if (not(arg.startingTime < arg.endTime and arg.endTime > _now() and arg.order.price > 0 and amountPerTrigger >= setting.UNIT_SIZE * 10)){
                    throw Error.reject("453: Arguments unavailable."); 
                };
            };
            case(#VWAP({setting = ?arg; status = status})){
                let amountPerTrigger = (switch(arg.amountPerTrigger){case(#Token0(v)){ v }; case(#Token1(v)){ v / icdex_lastPrice.price * setting.UNIT_SIZE }});
                if (not(arg.startingTime < arg.endTime and arg.endTime > _now() and amountPerTrigger >= setting.UNIT_SIZE * 10)){
                    throw Error.reject("453: Arguments unavailable."); 
                };
            };
            case(#TWAP({setting = ?arg; status = status})){
                let amountPerTrigger = (switch(arg.amountPerTrigger){case(#Token0(v)){ v }; case(#Token1(v)){ v / icdex_lastPrice.price * setting.UNIT_SIZE }});
                if (not(arg.startingTime < arg.endTime and arg.endTime > _now() and amountPerTrigger >= setting.UNIT_SIZE * 10)){
                    throw Error.reject("453: Arguments unavailable."); 
                };
            };
            case(_){};
        };
        if (_exchangeMode(account, null) != #PoolMode or not(_isKeepingBalanceInPair(account))){
            throw Error.reject("450: Pro-trader SHOULD turn on the `PoolMode` mode and turn on `Keeping balance in TraderAccount`."); 
        };
        // charge fee
        switch(_arg){
            case(#GridOrder(arg)){ 
                if (arg.status != ?#Stopped and arg.status != ?#Deleted) await* _chargeSTOrderFee1(icrc1Account, #GridOrder, #Update); 
            };
            case(#IcebergOrder(arg)){ 
                if (arg.status != ?#Stopped and arg.status != ?#Deleted) await* _chargeSTOrderFee1(icrc1Account, #IcebergOrder, #Update); 
            };
            case(#VWAP(arg)){ 
                if (arg.status != ?#Stopped and arg.status != ?#Deleted) await* _chargeSTOrderFee1(icrc1Account, #VWAP, #Update); 
            };
            case(#TWAP(arg)){ 
                if (arg.status != ?#Stopped and arg.status != ?#Deleted) await* _chargeSTOrderFee1(icrc1Account, #TWAP, #Update); 
            };
        };
        switch(STO.get(icdex_stOrderRecords, _soid)){
            case(?(sto)){
                // cancel orders
                let saga = _getSaga();
                for ((optTxid, price, quantity) in sto.pendingOrders.buy.vals()){
                    switch(optTxid){
                        case(?txid){
                            ignore _cancelOrder(?_soid, txid, ?#Buy);
                        };
                        case(_){
                            icdex_stOrderRecords := STO.removePendingOrderByPrice(icdex_stOrderRecords, _soid, #Buy, price);
                        };
                    };
                };
                for ((optTxid, price, quantity) in sto.pendingOrders.sell.vals()){
                    switch(optTxid){
                        case(?txid){
                            ignore _cancelOrder(?_soid, txid, ?#Sell);
                        };
                        case(_){
                            icdex_stOrderRecords := STO.removePendingOrderByPrice(icdex_stOrderRecords, _soid, #Sell, price);
                        };
                    };
                };
                icdex_stOrderRecords := STO.removeGridPrices(icdex_stOrderRecords, _soid);
                // update
                var soid : Nat = 0;
                var status: STO.STStatus = #Running;
                switch(sto.strategy, _arg){
                    case(#GridOrder(grid), #GridOrder(arg)){
                        let lowerLimit = Option.get(arg.lowerLimit, grid.setting.lowerLimit);
                        let upperLimit = Option.get(arg.upperLimit, grid.setting.upperLimit);
                        let spread = Option.get(arg.spread, grid.setting.spread);
                        let amount = Option.get(arg.amount, grid.setting.amount);
                        status := Option.get(arg.status, sto.status);
                        let initPrice = grid.setting.initPrice;
                        let ppmFactor = STO.getPpmFactor(initPrice, spread, lowerLimit, upperLimit);
                        icdex_stOrderRecords := STO.updateStatus(icdex_stOrderRecords, _soid, status);
                        icdex_stOrderRecords := STO.updateGridOrder(icdex_stOrderRecords, _soid, ?{
                            initPrice = initPrice;
                            lowerLimit = lowerLimit;
                            upperLimit = upperLimit;
                            gridCountPerSide = sto_setting.gridMaxPerSide * (if (isVipMaker){ 2 }else{ 1 }); 
                            spread = spread;
                            amount = amount;
                            ppmFactor = ?ppmFactor;
                        },
                        null);
                        soid := _soid;
                    };
                    case(#IcebergOrder(io), #IcebergOrder(arg)){
                        status := Option.get(arg.status, sto.status);
                        // update
                        icdex_stOrderRecords := STO.updateStatus(icdex_stOrderRecords, _soid, status);
                        icdex_stOrderRecords := STO.updateIcebergOrder(icdex_stOrderRecords, _soid, ?Option.get(arg.setting, io.setting), null);
                        soid := _soid;
                    };
                    case(#VWAP(vo), #VWAP(arg)){
                        status := Option.get(arg.status, sto.status);
                        // update
                        icdex_stOrderRecords := STO.updateStatus(icdex_stOrderRecords, _soid, status);
                        icdex_stOrderRecords := STO.updateVWAP(icdex_stOrderRecords, _soid, ?Option.get(arg.setting, vo.setting), null);
                        soid := _soid;
                    };
                    case(#TWAP(to), #TWAP(arg)){
                        status := Option.get(arg.status, sto.status);
                        // update
                        icdex_stOrderRecords := STO.updateStatus(icdex_stOrderRecords, _soid, status);
                        icdex_stOrderRecords := STO.updateTWAP(icdex_stOrderRecords, _soid, ?Option.get(arg.setting, to.setting), null);
                        soid := _soid;
                    };
                    case(_, _){ return 0 };
                };
                if (soid > 0){
                    icdex_activeProOrderList := STO.removeActivePOList(icdex_activeProOrderList, _soid);
                    if (status == #Running){
                        icdex_activeProOrderList := STO.putActivePOList(icdex_activeProOrderList, _soid);
                    };
                    if (status == #Deleted){
                        icdex_stOrderRecords := STO.remove(icdex_stOrderRecords, _soid);
                        icdex_userProOrderList := STO.removeUserPOList(icdex_userProOrderList, account, _soid);
                    };
                    // if (status == #Running and enableStrategyOrders){
                    //     await _hook_stoWorktop(?_soid, null);
                    // };
                };
                await* _ictcSagaRun(0, false);
                return soid;
            };
            case(_){ return 0 };
        };
    };

    /// Create a stop-loss-order strategy.  
    ///
    /// Arguments:
    /// - arg: {  
    ///    triggerPrice: STO.Price; // Set the trigger price. The triggerPrice must be greater than the current price if a #Buy order is scheduled to be placed, or less than the current price if a #Sell order is scheduled to be placed.   
    ///    order: { side: OrderBook.OrderSide; quantity: Nat; price: STO.Price; }; // Parameters for placing an order when triggered. The minimum value of quantity is setting.UNIT_SIZE * 10.   
    /// }
    /// - sa: ?Sa. Optionally specify the subaccount of the caller
    ///
    /// Returns:
    /// - res: STO.Soid. Returns strategy order ID.
    /// 
    public shared(msg) func sto_createStopLossOrder(_arg: {
            triggerPrice: STO.Price;
            order: { side: OrderBook.OrderSide; quantity: Nat; price: STO.Price; };
        }, _sa: ?Sa) : async STO.Soid{
        if (not(enableStrategyOrders)){
            throw Error.reject("400: The Strategy Order module is disabled!"); 
        };
        if (List.size(icdex_activeStopLossOrderList.buy) + List.size(icdex_activeStopLossOrderList.sell) >= 50000){
            throw Error.reject("460: The number of stoploss-order strategies that the system can host cannot exceed 50,000."); 
        };
        if (icdex_lastPrice.price == 0){
            throw Error.reject("458: Requires the pair to have at least one trade."); 
        };
        if (_arg.triggerPrice == 0 or _arg.order.quantity < setting.UNIT_SIZE * 10 or _arg.order.price == 0){
            throw Error.reject("454: Arguments unavailable."); 
        };
        if (_arg.order.side == #Buy and icdex_lastPrice.price >= _arg.triggerPrice){
            throw Error.reject("455: The trigger price of a stop-loss order with a Buy side should be higher than the current price."); 
        };
        if (_arg.order.side == #Sell and icdex_lastPrice.price <= _arg.triggerPrice){
            throw Error.reject("455: The trigger price of a stop-loss order with a Sell side should be lower than the current price."); 
        };
        let icrc1Account: STO.ICRC1Account = {owner = msg.caller; subaccount = _toSaBlob(_sa) };
        let account = Tools.principalToAccountBlob(msg.caller, _sa);
        let isVipMaker = _getMakerRebateRate(account) > 0;
        let balance = _getAccountBalance(account);
        if (_exchangeMode(account, null) != #PoolMode or not(_isKeepingBalanceInPair(account))){
            throw Error.reject("450: Pro-trader SHOULD turn on the `PoolMode` mode and turn on `Keepping Tokens in Pair`."); 
        };
        if (STO.userSLOSize(icdex_userStopLossOrderList, account) >= sto_setting.stopLossCountMax){
            throw Error.reject("456: You can only place a maximum of "# Nat.toText(sto_setting.stopLossCountMax) #" stop-loss orders"); 
        };
        if (balance.token0.available < setting.UNIT_SIZE * 100 and balance.token1.available < icdex_lastPrice.price * 100){
            throw Error.reject("452: Insufficient token0 or token1 balance. You SHOULD make a deposit first (Minimum amount: value "# Nat.toText(setting.UNIT_SIZE * 100) #" smallest_units token0)."); 
        };
        // charge fee
        await* _chargeSTOrderFee1(icrc1Account, #StopLossOrder, #Create);
        // put
        icdex_stOrderRecords := STO.new(icdex_stOrderRecords, icrc1Account, icdex_soid, #StopLossOrder({
            condition = {
                triggerPrice = _arg.triggerPrice;
                order = _arg.order;
            };
            triggeredOrder = null;
        }));
        let soid = icdex_soid;
        icdex_soid += 1;
        icdex_userStopLossOrderList := STO.putUserSLOList(icdex_userStopLossOrderList, account, soid);
        icdex_activeStopLossOrderList := STO.putActiveSLOList(icdex_activeStopLossOrderList, _arg.order.side, (soid, _arg.triggerPrice));
        return soid;
    };

    /// Update a stop-loss-order strategy, arguments similar to the above.
    public shared(msg) func sto_updateStopLossOrder(_soid: STO.Soid, _arg: {
            triggerPrice: ?STO.Price;
            order: ?{ side: OrderBook.OrderSide; quantity: Nat; price: STO.Price; };
            status: ?STO.STStatus;
        }, _sa: ?Sa) : async STO.Soid{
        let icrc1Account: STO.ICRC1Account = {owner = msg.caller; subaccount = _toSaBlob(_sa) };
        let account = Tools.principalToAccountBlob(msg.caller, _sa);
        assert(_onlyStratOrderOwner(account, _soid));
        let isVipMaker = _getMakerRebateRate(account) > 0;
        if (_exchangeMode(account, null) != #PoolMode or not(_isKeepingBalanceInPair(account))){
            throw Error.reject("450: Pro-trader SHOULD turn on the `PoolMode` mode and turn on `Keeping balance in PairAccount`."); 
        };
        switch(STO.get(icdex_stOrderRecords, _soid)){
            case(?(sto)){
                if (sto.status == #Running){
                    let _status = Option.get(_arg.status, sto.status);
                    switch(sto.strategy){
                        case(#StopLossOrder(slo)){
                            let _triggerPrice = Option.get(_arg.triggerPrice, slo.condition.triggerPrice);
                            let _order = Option.get(_arg.order, slo.condition.order);
                            if (_triggerPrice == 0 or _order.quantity == 0 or _order.price == 0){
                                throw Error.reject("454: Arguments unavailable."); 
                            };
                            if (_status != #Deleted and _order.side == #Buy and icdex_lastPrice.price >= _triggerPrice){
                                throw Error.reject("455: The trigger price of a stop-loss order with a Buy side should be higher than the current price."); 
                            };
                            if (_status != #Deleted and _order.side == #Sell and icdex_lastPrice.price <= _triggerPrice){
                                throw Error.reject("455: The trigger price of a stop-loss order with a Sell side should be lower than the current price."); 
                            };
                            // charge fee (20% fee; #Stopped/#Deleted is free)
                            if (_status != #Stopped and _status != #Deleted){
                                await* _chargeSTOrderFee1(icrc1Account, #StopLossOrder, #Update); // 20% * fee
                            };
                            // update
                            icdex_stOrderRecords := STO.updateStatus(icdex_stOrderRecords, _soid, _status);
                            icdex_stOrderRecords := STO.updateStopLossOrder(icdex_stOrderRecords, _soid, ?{
                                triggerPrice = _triggerPrice;
                                order = _order;
                            }, null);
                            icdex_activeStopLossOrderList := STO.removeActiveSLOList(icdex_activeStopLossOrderList, _soid);
                            if (_status == #Running){
                                icdex_activeStopLossOrderList := STO.putActiveSLOList(icdex_activeStopLossOrderList, _order.side, (_soid, _triggerPrice));
                            };
                            if (_status == #Deleted){
                                icdex_stOrderRecords := STO.remove(icdex_stOrderRecords, _soid);
                                icdex_userStopLossOrderList := STO.removeUserSLOList(icdex_userStopLossOrderList, account, _soid);
                            };
                            if (_status == #Running and enableStrategyOrders){
                                await _hook_stoWorktop(?_soid, null);
                            };
                            await* _ictcSagaRun(0, false);
                        };
                        case(_){};
                    };
                    return _soid;
                }else{
                    return 0;
                };
            };
            case(_){ return 0 };
        };
    };

    /// Returns strategy order information and status
    public query func sto_getStratOrder(_soid: STO.Soid): async ?STO.STOrder{
        return STO.get(icdex_stOrderRecords, _soid);
    };

    /// Queries the strategy order based on the txid of the trade order, and returns null if the txid does not belong to 
    /// the trade triggered by the strategy.
    public query func sto_getStratOrderByTxid(_txid: Txid): async ?STO.STOrder{
        switch(STO.getSoidByTxid(icdex_stOrderTxids, _txid)){
            case(?soid){ return STO.get(icdex_stOrderRecords, soid) };
            case(_){ return null }
        };
    };

    /// Returns a trader's strategy pro-orders
    public query func sto_getAccountProOrders(_a: Address): async [STO.STOrder]{
        let account = _getAccountId(_a);
        switch(Trie.get(icdex_userProOrderList, keyb(account), Blob.equal)){
            case(?list){
                return Array.mapFilter(List.toArray(list), func (t: Nat): ?STO.STOrder{
                    STO.get(icdex_stOrderRecords, t);
                }); 
            };
            case(_){ return [] };
        };
    };

    /// Returns a trader's strategy stop-loss-orders
    public query func sto_getAccountStopLossOrders(_a: Address): async [STO.STOrder]{
        let account = _getAccountId(_a);
        switch(Trie.get(icdex_userStopLossOrderList, keyb(account), Blob.equal)){
            case(?list){
                return Array.mapFilter(List.toArray(list), func (t: Nat): ?STO.STOrder{
                    STO.get(icdex_stOrderRecords, t);
                }); 
            };
            case(_){ return [] };
        };
    };

    /// Returns the global configuration of the strategy platform for the trading pair.
    public query func sto_getConfig() : async STO.Setting{
        return sto_setting;
    };

    /// Returns all active pro-orders, dedicated to Owner (DAO) debugging.
    public shared(msg) func sto_getActiveProOrders(_page: ?ListPage, _size: ?ListSize): async TrieList<STO.Soid, STO.STOrder>{
        if (not(icdex_debug)) assert(_onlyOwner(msg.caller));
        var data: STO.STOrderRecords = Trie.empty();
        for (soid in List.toArray(icdex_activeProOrderList).vals()){
            switch(STO.get(icdex_stOrderRecords, soid)){
                case(?item){ data := STO.put(data, item); };
                case(_){};
            };
        };
        let page = Option.get(_page, 1);
        let size = Option.get(_size, 100);
        return trieItems<STO.Soid, STO.STOrder>(data, page, size);
    };

    /// Returns all active stop-loss-orders, dedicated to Owner (DAO) debugging.
    public shared(msg) func sto_getActiveStopLossOrders(_side: {#Buy; #Sell}, _page: ?ListPage, _size: ?ListSize): async TrieList<STO.Soid, STO.STOrder>{
        if (not(icdex_debug)) assert(_onlyOwner(msg.caller));
        var data: STO.STOrderRecords = Trie.empty();
        if (_side == #Buy){
            for ((soid, tPrice) in List.toArray(icdex_activeStopLossOrderList.buy).vals()){
                switch(STO.get(icdex_stOrderRecords, soid)){
                    case(?item){ data := STO.put(data, item); };
                    case(_){};
                };
            };
        }else if (_side == #Sell){
            for ((soid, tPrice) in List.toArray(icdex_activeStopLossOrderList.sell).vals()){
                switch(STO.get(icdex_stOrderRecords, soid)){
                    case(?item){ data := STO.put(data, item); };
                    case(_){};
                };
            };
        };
        let page = Option.get(_page, 1);
        let size = Option.get(_size, 100);
        return trieItems<STO.Soid, STO.STOrder>(data, page, size);
    };

    /// Returns all soid to txid relationships, dedicated to Owner (DAO) debugging.
    public shared(msg) func sto_getStratTxids(_page: ?ListPage, _size: ?ListSize) : async TrieList<Txid, STO.Soid>{
        if (not(icdex_debug)) assert(_onlyOwner(msg.caller));
        let page = Option.get(_page, 1);
        let size = Option.get(_size, 100);
        return trieItems<Txid, STO.Soid>(icdex_stOrderTxids, page, size);
    };
    /* ===========================
    *  End: Strategic order section
    ============================== */


    /* ===========================
      IDO section
    ============================== */
    type IDOSetting = {
        IDOEnabled: Bool; // Whether to enable IDO
        IDOWhitelistEnabled: Bool; // Whether to enable whitelisting
        IDOLimitPerAccount: Amount/* smallest units token0 */; // Participation limits per account.
        IDOOpeningTime: Time.Time; // nanoseconds. IDO opening time.
        IDOClosingTime: Time.Time; // nanoseconds. IDO closing time.
        IDOTotalSupply: {IDOSupply: Amount/* smallest units token0 */; percentageOfTotal: Float/* range (0, 1.0] */;}; // IDO supply and percentage. e.g. {IDOSupply = 1000000000000000; percentageOfTotal = 0.10; }
        IDOSupplies: [{price: Float/* how much smallest_units_token1 to buy 1 smallest_units_token0 */; supply: Amount/* smallest units */;}]; // Tiered supply rules e.g. [{price = 0.01; supply = 500000000000000;}]
    };
    type IDORequirement = { // For non-whitelisted mode
        pairs: [{pair: Principal; token1ToUsdRatio: Float}]; // 1 smallest_units = ? USD(main_units, NOT smallest_units)
        threshold: Float; // USD. Users who have reached this threshold of cumulative trading volume are eligible to participate in the IDO
    };
    type Participant = {
        historyVol: Float; // USD. cumulative trading volume of the user
        limit: Amount/* smallest units token0 */; // Participation limits
        used: Amount/* smallest units token0 */; // Amount already used
        updatedTime: Time.Time
    };
    private stable var IDOFunder: ?Principal = null;
    private stable var IDORequirement_: ?IDORequirement = null;
    private stable var IDOSetting_ : IDOSetting = {
        IDOEnabled: Bool = false;
        IDOWhitelistEnabled: Bool = false;
        IDOLimitPerAccount: Amount = 0;
        IDOOpeningTime: Time.Time = 0;
        IDOClosingTime: Time.Time = 0;
        IDOTotalSupply = {IDOSupply = 0; percentageOfTotal = 0;};
        IDOSupplies = [];
    };
    private stable var IDOParticipants: Trie.Trie<AccountId, Participant> = Trie.empty(); // IDO Participant information and status

    private func _onlyIDOFunder(_caller: Principal) : Bool { //ict
        let ?idoFunder = IDOFunder else { return false; };
        return _caller == idoFunder;
    }; 
    private func _inIDO() : Bool{
        return IDOSetting_.IDOEnabled and Time.now() < IDOSetting_.IDOClosingTime;
    };
    private func _isIDOFunderOrder(_caller: Principal): Bool{
        return _onlyIDOFunder(_caller) and Time.now() < pairOpeningTime;
    };

    // For IDO scenarios, a trade order is filtered and will return true if it meets the conditions. it returns true if IDO is not turned on or if IDO has ended.
    private func _filterIDOConditions(_a: AccountId, _side: OrderBook.OrderSide, _type: OrderBook.OrderType, _price: Nat, _quantity: Amount): Bool{
        let ?idoFunder = IDOFunder else { return true; };
        if (not(IDOSetting_.IDOEnabled)){ // no IDO
            return true;
        };
        if (Time.now() > IDOSetting_.IDOClosingTime){ // IDO closed
            return true;
        };
        if (_a == Tools.principalToAccountBlob(idoFunder, null) and _side == #Sell and _type == #LMT and Time.now() < pairOpeningTime){ // funder #LMT
            return Option.isSome(Array.find(IDOSetting_.IDOSupplies, func (t: {price: Float; supply: Amount;}): Bool{
                let price = _floatToNat(t.price * _natToFloat(setting.UNIT_SIZE));
                let pendingOrders = _accountPendingOrders(?_a);
                for ((txid, order) in Trie.iter(pendingOrders)){
                    if (order.orderPrice.price == _price){
                        return false;
                    };
                };
                return _price == price and _quantity == t.supply; // _price >= Nat.sub(price, 1) and _price <= price + 1
            }));
        };
        if (IDOSetting_.IDOEnabled and _side == #Buy and _type == #FOK and Time.now() >= pairOpeningTime){ // buy(limit) #FOK
            var amountLimit: Amount = 0;
            let threshold: Float = switch(IDORequirement_){ case(?(r)){ r.threshold }; case(_){ 0 } };
            if (IDOSetting_.IDOWhitelistEnabled){ // Whitelist mode
                switch(Trie.get(IDOParticipants, keyb(_a), Blob.equal)){
                    case(?(participant)){
                        amountLimit := participant.limit - Nat.min(participant.limit, participant.used);
                    };
                    case(_){};
                };
            }else{ // Non-Whitelist mode (but whitelist data can override default values)
                if (threshold == 0){
                    amountLimit := IDOSetting_.IDOLimitPerAccount; 
                };
                switch(Trie.get(IDOParticipants, keyb(_a), Blob.equal)){
                    case(?(p)){
                        var participant = p;
                        // if (participant.limit == 0 and threshold > 0){
                        //     participant := await* _fetchVolForIDO(_a);
                        // };
                        amountLimit := participant.limit - Nat.min(participant.limit, participant.used);
                    };
                    case(_){
                        // if (threshold > 0){
                        //     let participant = await* _fetchVolForIDO(_a);
                        //     amountLimit := participant.limit - Nat.min(participant.limit, participant.used);
                        // };
                    };
                };
            };
            
            if (amountLimit >= _quantity){
                return true;
            };
        };
        return false;
    };

    // Updates IDO Participant Information
    private func _updateIDOData(_a: AccountId, _quantity: Amount) : (){
        switch(Trie.get(IDOParticipants, keyb(_a), Blob.equal)){
            case(?(participant)){
                IDOParticipants := Trie.put(IDOParticipants, keyb(_a), Blob.equal, {
                    historyVol = participant.historyVol; 
                    limit = participant.limit; 
                    used = participant.used + _quantity; 
                    updatedTime = Time.now()
                }).0;
            };
            case(_){
                let p : Participant = {
                    historyVol = 0; 
                    limit = IDOSetting_.IDOLimitPerAccount; 
                    used = _quantity; 
                    updatedTime = Time.now()
                };
                IDOParticipants := Trie.put(IDOParticipants, keyb(_a), Blob.equal, p).0;
            };
        };
    };

    // Get the cumulative volume of a trader from the specified pairs of the configuration.
    private func _fetchVolForIDO(_a: AccountId) : async* Participant{
        let threshold: Float = switch(IDORequirement_){ case(?(r)){ r.threshold }; case(_){ 0 } };
        var limit : Amount = 0;
        var updatedTime: Time.Time = 0;
        switch(Trie.get(IDOParticipants, keyb(_a), Blob.equal)){
            case(?(participant)){
                limit := participant.limit;
                updatedTime := participant.updatedTime;
            };
            case(_){};
        };
        if (not(IDOSetting_.IDOWhitelistEnabled) and limit == 0 and threshold > 0 and Time.now() > updatedTime + 600*ns_){
            switch(IDORequirement_){
                case(?(requirement)){
                    let address = Hex.encode(Blob.toArray(_a));
                    var volUsd : Float = 0;
                    label IDOFetchVol for (item in requirement.pairs.vals()){
                        let pair: Types.Self = actor(Principal.toText(item.pair));
                        try{
                            countAsyncMessage += 1;
                            let res = await pair.liquidity(?address);
                            volUsd += _natToFloat(res.vol.value1) * item.token1ToUsdRatio;
                            countAsyncMessage -= Nat.min(1, countAsyncMessage);
                        }catch(e){
                            countAsyncMessage -= Nat.min(1, countAsyncMessage);
                        };
                        if (volUsd > threshold){
                            break IDOFetchVol;
                        };
                    };
                    if (volUsd > threshold){
                        limit := IDOSetting_.IDOLimitPerAccount; 
                    };
                    var p: Participant = {
                        historyVol = volUsd; 
                        limit = limit; 
                        used = 0; 
                        updatedTime = Time.now()
                    };
                    switch(Trie.get(IDOParticipants, keyb(_a), Blob.equal)){
                        case(?(participant)){
                            p := {
                                historyVol = p.historyVol; 
                                limit = Nat.max(p.limit, participant.limit); 
                                used = participant.used; 
                                updatedTime = p.updatedTime;
                            };
                        };
                        case(_){};
                    };
                    IDOParticipants := Trie.put(IDOParticipants, keyb(_a), Blob.equal, p).0;
                };
                case(_){};
            };
        };
        switch(Trie.get(IDOParticipants, keyb(_a), Blob.equal)){
            case(?(participant)){
                return participant;
            };
            case(_){
                if (not(IDOSetting_.IDOWhitelistEnabled) and threshold == 0){
                    limit := IDOSetting_.IDOLimitPerAccount; 
                };
                return {
                    historyVol = 0;
                    limit = limit;
                    used = 0; 
                    updatedTime = 0;
                };
            };
        };
    };

    /// Funder configures IDO
    public shared(msg) func IDO_config(_setting: IDOSetting) : async (){
        assert(_onlyIDOFunder(msg.caller));
        assert(icdex_totalVol.value1 == 0);
        assert(Trie.size(icdex_orders) == 0);
        assert(Time.now() + 24*3600*ns_ < pairOpeningTime or pairOpeningTime == 0);
        var supply: Nat = 0;
        for (s in _setting.IDOSupplies.vals()){
            supply += s.supply;
        };
        assert(supply == _setting.IDOTotalSupply.IDOSupply);
        IDOSetting_ := _setting;
        pairOpeningTime := _setting.IDOOpeningTime; 
        IDOParticipants := Trie.empty(); 
    };

    /// Returns IDO configuration
    public query func IDO_getConfig() : async (funder: ?Principal, setting: IDOSetting, requirement: ?IDORequirement){
        return (IDOFunder, IDOSetting_, IDORequirement_);
    };

    /// Funder sets up whitelisting
    public shared(msg) func IDO_setWhitelist(limits: [(Address, Amount)]) : async (){
        assert(_onlyIDOFunder(msg.caller));
        assert(Time.now() < pairOpeningTime);
        for ((address, limit) in limits.vals()){
            let p : Participant = {
                historyVol = 0;
                limit = if (limit == 0) { IDOSetting_.IDOLimitPerAccount } else { limit };
                used = 0; 
                updatedTime = Time.now();
            };
            IDOParticipants := Trie.put(IDOParticipants, keyb(_getAccountId(address)), Blob.equal, p).0;
        };
    };

    /// Funder removes whitelisted members
    public shared(msg) func IDO_removeWhitelist(users: [Address]) : async (){
        assert(_onlyIDOFunder(msg.caller));
        assert(Time.now() < pairOpeningTime);
        for (address in users.vals()){
            IDOParticipants := Trie.remove(IDOParticipants, keyb(_getAccountId(address)), Blob.equal).0;
        };
    };

    /// Participant update his qualification status ( fetch cumulative volume from specified trading pairs).
    public shared(msg) func IDO_updateQualification(_sa: ?Sa): async ?Participant{
        assert(Time.now() <= IDOSetting_.IDOClosingTime);
        let account = Tools.principalToAccountBlob(msg.caller, _sa);
        if (IDOSetting_.IDOWhitelistEnabled){
            return null;
        };
        return ?(await* _fetchVolForIDO(account));
    };

    /// Returns an account's participation qualification status. If account `_a` is not specified, all qualified accounts are returned.
    public query func IDO_qualification(_a: ?Address) : async [(Address, Participant)]{
        switch(_a){
            case(?(address)){
                let threshold: Float = switch(IDORequirement_){ case(?(r)){ r.threshold }; case(_){ 0 } };
                let account = _getAccountId(address);
                switch(Trie.get(IDOParticipants, keyb(account), Blob.equal)){
                    case(?(p)){
                        return [(Hex.encode(Blob.toArray(account)), p)];
                    };
                    case(_){
                        if (not(IDOSetting_.IDOWhitelistEnabled) and threshold == 0){
                            return [(Hex.encode(Blob.toArray(account)), {
                                historyVol = 0;
                                limit = IDOSetting_.IDOLimitPerAccount;
                                used = 0; 
                                updatedTime = Time.now();
                            })];
                        };
                    };
                };
                return [];
            };
            case(_){
                return Trie.toArray<AccountId, Participant, (Address, Participant)>(IDOParticipants, func (k:AccountId, v:Participant): (Address, Participant){
                    (Hex.encode(Blob.toArray(k)), v)
                });
            };
        };
    };
    /* ===========================
      End: IDO section
    ============================== */

    /* ===========================
      Management section
    ============================== */
    // public query func getOwner() : async Principal{  
    //     return owner;
    // };
    // public shared(msg) func changeOwner(_newOwner: Principal) : async Bool{ 
    //     assert(_onlyOwner(msg.caller));
    //     owner := _newOwner;
    //     return true;
    // };

    /// Synchronizing token0 and token1 transfer fees
    public shared(msg) func sync() : async (){
        assert(_onlyOwner(msg.caller));
        await* _getGas(true);
    };

    /// Returns the basic configuration of the pair.
    public query func getConfig() : async DexSetting{
        return setting;
    };

    /// Set basic configuration of trading pair.
    public shared(msg) func config(_config: DexConfig) : async Bool{
        assert(_onlyOwner(msg.caller));
        assert(_asyncMessageSize() < 300);
        if (Option.isSome(_config.UNIT_SIZE) and Option.get(_config.UNIT_SIZE, 0) != setting.UNIT_SIZE){
            icdex_lastPrice := { quantity = #Sell(0); price = 0 };
            let saga = _getSaga();
            for ((k,v) in Trie.iter(icdex_orders)){
                //_cancel(k, ?OrderBook.side(v.orderPrice));
                let toid = saga.create("cancel", #Forward, ?k, null);
                let ttids = _cancel(toid, k, ?OrderBook.side(v.orderPrice));
                saga.close(toid);
                if (ttids.size() == 0){
                    ignore saga.doneEmpty(toid);
                };
            };
            // drc205; 
            await* _callDrc205Store(false, true);
            // ictc
            await* _ictcSagaRun(0, true);
        };
        setting := {
            UNIT_SIZE: Nat = Option.get(_config.UNIT_SIZE, setting.UNIT_SIZE);
            ICP_FEE: Nat = Option.get(_config.ICP_FEE, setting.ICP_FEE);
            TRADING_FEE: Nat = Option.get(_config.TRADING_FEE, setting.TRADING_FEE);
            MAKER_BONUS_RATE: Nat = Option.get(_config.MAKER_BONUS_RATE, setting.MAKER_BONUS_RATE);
            MAX_TPS: Nat = Option.get(_config.MAX_TPS, setting.MAX_TPS);
            MAX_PENDINGS: Nat = Option.get(_config.MAX_PENDINGS, setting.MAX_PENDINGS);
            STORAGE_INTERVAL: Nat = Option.get(_config.STORAGE_INTERVAL, setting.STORAGE_INTERVAL);
            ICTC_RUN_INTERVAL: Nat = Option.get(_config.ICTC_RUN_INTERVAL, setting.ICTC_RUN_INTERVAL);
        };
        ExpirationDuration := Option.get(_config.ORDER_EXPIRATION_DURATION, ExpirationDuration / ns_) * ns_;
        return true;
    };

    /// Suspend (true) or open (false) trading pair. If `_openingTime` is specified, it means that the pair will be opened automatically after that time.
    public shared(msg) func setPause(_pause: Bool, _openingTime: ?Time.Time) : async Bool{ 
        assert(_onlyOwner(msg.caller));
        pause := _pause;
        if (_pause){
            mode := #DisabledTrading;
        }else{
            mode := #GeneralTrading;
        };
        switch(_openingTime){
            case(?(t)){ 
                pairOpeningTime := t; 
                IDOSetting_ := {
                    IDOEnabled = IDOSetting_.IDOEnabled;
                    IDOWhitelistEnabled = IDOSetting_.IDOWhitelistEnabled;
                    IDOLimitPerAccount = IDOSetting_.IDOLimitPerAccount;
                    IDOOpeningTime = t;
                    IDOClosingTime = IDOSetting_.IDOClosingTime;
                    IDOTotalSupply = IDOSetting_.IDOTotalSupply;
                    IDOSupplies = IDOSetting_.IDOSupplies;
                };
            };
            case(_){ pairOpeningTime := 0; };
        };
        return true;
    };

    /// Set up vip-maker qualification and configure rebate rate.
    public shared(msg) func setVipMaker(_account: Address, _rate: Nat) : async (){
        assert(_onlyOwner(msg.caller));
        assert(_rate <= 100);
        // if (_onlyToken(msg.caller)){
        //     assert(_rate <= 70);
        // };
        switch(Trie.get(icdex_makers, keyb(_getAccountId(_account)), Blob.equal)){
            case(?(rate, managedBy)){
                if (_onlyOwner(msg.caller) or managedBy == msg.caller){
                    icdex_makers := Trie.put(icdex_makers, keyb(_getAccountId(_account)), Blob.equal, (_rate, msg.caller)).0;
                };
            };
            case(_){ icdex_makers := Trie.put(icdex_makers, keyb(_getAccountId(_account)), Blob.equal, (_rate, msg.caller)).0; };
        };
    };

    /// Removes vip-maker qualification
    public shared(msg) func removeVipMaker(_account: Address) : async (){
        assert(_onlyOwner(msg.caller));
        icdex_makers := Trie.remove(icdex_makers, keyb(_getAccountId(_account)), Blob.equal).0;
    };

    /// Sets an order with #Todo status as an error order
    public shared(msg) func setOrderFail(_txid: Text, _unlock0: Amount, _unlock1: Amount) : async Bool{
        // #Todo order
        assert(_onlyOwner(msg.caller));
        switch(Hex.decode(_txid)){
            case(#ok(txid_)){
                let txid = Blob.fromArray(txid_);
                switch(Trie.get(icdex_orders, keyb(txid), Blob.equal)){
                    case(?(order)){
                        if (order.status == #Todo and order.filled.size() == 0 and order.toids.size() == 0){
                            let icrc1Account = _orderIcrc1Account(txid);
                            _moveToFailedOrder(txid, _unlock0, _unlock1);
                            try{
                                let r = await* _fallback(icrc1Account, txid, null);
                            }catch(e){
                                return false;
                            };
                        };
                    };
                    case(_){};
                };
                return true;
            };
            case(_){ return false; };
        };
    };

    private stable var hasMerged : Bool = false;

    /// Migrate total volume and K-chart data from old trading pair. It can only be migrated once.
    public shared(msg) func mergePair(_pair: Principal) : async Bool{
        assert(_onlyOwner(msg.caller));
        assert(not(hasMerged));
        type Pair = actor{
            stats : shared query() -> async {price:Float; change24h:Float; vol24h:Vol; totalVol:Vol};
            getQuotes : shared query (_ki: Nat) -> async [KBar];
        };
        let pair: Pair = actor(Principal.toText(_pair));
        let vol = (await pair.stats()).totalVol;
        icdex_totalVol := { value0 = icdex_totalVol.value0 + vol.value0; value1 = icdex_totalVol.value1 + vol.value1 };
        let kis : [Nat] = [60, 60*5, 3600, 3600*24, 3600*24*7, 3600*24*30];
        for (ki in kis.vals()){
            var kbars = await pair.getQuotes(ki);
            switch(Trie.get(icdex_klines2, keyn(ki), Nat.equal)){
                case(?(dq)){
                    switch(Deque.popBack(dq)){
                        case(?(dq_, kbar)){
                            let startTime = kbar.updatedTs; //Nat seconds
                            var dqNew = dq;
                            for (k in kbars.vals()){
                                if (k.updatedTs < startTime){
                                    dqNew := Deque.pushBack(dqNew, k);
                                };
                            };
                            icdex_klines2 := Trie.put(icdex_klines2, keyn(ki), Nat.equal, dqNew).0;
                        };
                        case(_){};
                    };
                };
                case(_){};
            };
        };
        hasMerged := true;
        return true;
    };

    /// Configuring strategy order parameters.
    public shared(msg) func sto_config(_config: {
        poFee1: ?Nat; // ICL
        poFee2: ?Float; // Fee rate of filled token0 or token1
        sloFee1: ?Nat; // ICL
        sloFee2: ?Float; // Fee rate of filled token0 or token1
        gridMaxPerSide: ?Nat; 
        proCountMax: ?Nat;
        stopLossCountMax: ?Nat;
    }) : async (){
        assert(_onlyOwner(msg.caller));
        sto_setting := {
            poFee1 = Option.get(_config.poFee1, sto_setting.poFee1);
            poFee2 = Option.get(_config.poFee2, sto_setting.poFee2);
            sloFee1 = Option.get(_config.sloFee1, sto_setting.sloFee1);
            sloFee2 = Option.get(_config.sloFee2, sto_setting.sloFee2);
            gridMaxPerSide = Option.get(_config.gridMaxPerSide, sto_setting.gridMaxPerSide);
            proCountMax = Option.get(_config.proCountMax, sto_setting.proCountMax);
            stopLossCountMax = Option.get(_config.stopLossCountMax, sto_setting.stopLossCountMax);
        };
    };

    /// Open IDO and configure parameters
    public shared(msg) func IDO_setFunder(_funder: ?Principal, _requirement: ?IDORequirement) : async (){
        assert(_onlyOwner(msg.caller));
        IDOFunder := _funder;
        IDORequirement_ := _requirement;
    };

    /// Submit a text description of the Trading Ambassadors (referral) system
    public shared(msg) func ta_setDescription(_desc: Text) : async (){
        assert(_onlyOwner(msg.caller));
        taDescription := _desc;
    };

    /// Enable strategy orders
    public shared(msg) func sto_enableStratOrder(_arg: {#Enable; #Disable}): async (){
        assert(_onlyOwner(msg.caller));
        enableStrategyOrders := _arg == #Enable;
    };

    /// Clear the relationship table between strategy order soid and trade order txid.
    public shared(msg) func sto_clearTxidLog(): async (){
        assert(_onlyOwner(msg.caller));
        icdex_stOrderTxids := Trie.filter(icdex_stOrderTxids, func (k: Txid, v: STO.Soid): Bool{
            Option.isSome(STO.get(icdex_stOrderRecords, v));
        });
    };

    /// Clear account settings with no activity.
    public shared(msg) func clearAccountSetting() : async (){
        assert(_onlyOwner(msg.caller));
        icdex_accountSettings := Trie.filter(icdex_accountSettings, func (k: AccountId, v: AccountSetting): Bool{
            if (k == Tools.principalToAccountBlob(icdexRouter, null)){
                return true;
            };
            if (Option.isSome(Trie.get(stats_brokers, keyb(k), Blob.equal))){
                return true;
            };
            if (_getMakerRebateRate(k) > 0){
                return true;
            };
            if (_isProTrader(k)){ 
                return true;
            };
            let balances = _getAccountBalance(k);
            if (balances.token0.locked > 0 or balances.token0.available > 0 or balances.token1.locked > 0 or balances.token1.available > 0){
                return true;
            };
            let countPendingOrder = _pendingSize(?k);
            if (countPendingOrder > 0){
                return true;
            };
            return false;
        });
    };

    /// Clear non-core data (volume statistics and referral statistics).
    public shared(msg) func clearNonCoreData() : async (){
        assert(_onlyOwner(msg.caller));
        icdex_vols := Trie.empty();
        traderReferrerTemps := Trie.empty();
        ambassadors := Trie.empty();
        traderReferrers := Trie.empty();
    };

    /// debug: Returns the current grid-orders
    public shared(msg) func debug_gridOrders() : async [(STO.Soid, STO.ICRC1Account, OrderPrice)]{
        assert(_onlyOwner(msg.caller));
        return sto_lastGridOrders;
    };

    /* ===========================
      Trading Ambassadors section
    ============================== */
    // A trader can submit a referrer only if he/she has a record of a filled order.

    // entity: An organization's name or a theme; referred: Cumulative number of referrals; vol: Total volume of traders referred by the ambassador
    type AmbassadorData = (entity: Text, referred: Nat, vol: Vol); 
    private stable var taDescription: Text = "";
    private stable var ambassadors: Trie.Trie<AccountId, AmbassadorData> = Trie.empty(); // Ambassador list
    private stable var traderReferrerTemps: Trie.Trie<AccountId, (AccountId, Text, Time.Time)> = Trie.empty(); // Unvalidated trader and referrer relationships
    private stable var traderReferrers: Trie.Trie<AccountId, AccountId> = Trie.empty(); // Validated trader and referrer relationships
    
    private func _isAmbassador(_a: AccountId) : Bool{
        let vol = _getVol(_a);
        return Option.isSome(Trie.get(ambassadors, keyb(_a), Blob.equal)) or vol.value0 > 0 or vol.value1 > 0;
    };

    // Set an ambassador
    private func _setAmbassador(_ambassador: AccountId, _newReferred: Bool, _addVol: ?Vol, _entity: ?Text) : (){
        if (_newReferred or Option.isSome(_addVol)){
            var referred: Nat = 0;
            if (_newReferred) { referred := 1; };
            var addVol = Option.get(_addVol, {value0 = 0; value1 = 0;});
            if (_isAmbassador(_ambassador)){
                switch(Trie.get(ambassadors, keyb(_ambassador), Blob.equal)){
                    case(?(amb)){
                        let entity = if (amb.0 == "") { Option.get(_entity, "") } else { amb.0 };
                        ambassadors := Trie.put(ambassadors, keyb(_ambassador), Blob.equal, (entity, amb.1 + referred, {value0 = amb.2.value0 + addVol.value0; value1 = amb.2.value1 + addVol.value1;})).0;
                    };
                    case(_){
                        let entity = Option.get(_entity, "");
                        ambassadors := Trie.put(ambassadors, keyb(_ambassador), Blob.equal, (entity, referred, {value0 = addVol.value0; value1 = addVol.value1;})).0;
                    };
                };
            };
        };
    };

    // Update referral data
    private func _setPromotion(_a: AccountId, _addVol: Vol) : (){
        if ((_addVol.value0 > 0 or _addVol.value1 > 0) and Option.isSome(Trie.get(traderReferrerTemps, keyb(_a), Blob.equal))){
            switch(Trie.get(traderReferrerTemps, keyb(_a), Blob.equal)){
                case(?(ambassador, entity, setTime)){
                    ignore _setReferrer(_a, ambassador, ?entity);
                    _setAmbassador(ambassador, true, ?_addVol, ?entity);
                };
                case(_){};
            };
        }else{
            switch(Trie.get(traderReferrers, keyb(_a), Blob.equal)){
                case(?(ambassador)){
                    _setAmbassador(ambassador, false, ?_addVol, null);
                };
                case(_){};
            };
        };
    };

    // Sets up an unvalidated referral relationship
    private func _setReferrerTemp(_owner: AccountId, _ambassador: AccountId, _entity: ?Text) : Bool{
        if (_isAmbassador(_ambassador) and Option.isNull(Trie.get(traderReferrerTemps, keyb(_owner), Blob.equal))
         and Option.isNull(Trie.get(traderReferrers, keyb(_owner), Blob.equal))){
            traderReferrerTemps := Trie.put(traderReferrerTemps, keyb(_owner), Blob.equal, (_ambassador, Option.get(_entity, ""), Time.now())).0;
            traderReferrerTemps := Trie.filter(traderReferrerTemps, func (k: AccountId, v: (AccountId, Text, Time.Time)): Bool{
                Time.now() < v.2 + 2_592_000_000_000_000; // 30days
            });
            return true;
        }else{
            return false;
        };
    };

    // Sets up a validated referral relationship
    private func _setReferrer(_owner: AccountId, _ambassador: AccountId, _entity: ?Text) : Bool{
        if (_isAmbassador(_ambassador) and Option.isNull(Trie.get(traderReferrers, keyb(_owner), Blob.equal))){
            traderReferrers := Trie.put(traderReferrers, keyb(_owner), Blob.equal, _ambassador).0;
            traderReferrerTemps := Trie.remove(traderReferrerTemps, keyb(_owner), Blob.equal).0;
            return true;
        }else{
            return false;
        };
    };

    /// A trader sets up his referrer, which can only be validly set up once.
    public shared(msg) func ta_setReferrer(_ambassador: Address, _entity: ?Text, _sa: ?Sa) : async Bool{
        assert(Tools.principalToAccountBlob(msg.caller, _sa) != _getAccountId(_ambassador));
        return _setReferrerTemp(Tools.principalToAccountBlob(msg.caller, _sa), _getAccountId(_ambassador), _entity);
    };

    /// Returns a trader's referrer
    public query func ta_getReferrer(_account: Address) : async ?(Address, Bool){
        switch(Trie.get(traderReferrers, keyb(_getAccountId(_account)), Blob.equal), Trie.get(traderReferrerTemps, keyb(_getAccountId(_account)), Blob.equal)){
            case(?(ambassador), _){
                return ?(_accountIdToHex(ambassador), true);
            };
            case(_, ?(ambassador, entity, seTime)){
                return ?(_accountIdToHex(ambassador), false);
            };
            case(_, _){ return null; };
        };
    };

    /// Returns data of an ambassador.
    public query func ta_ambassador(_ambassador: Address) : async (quality: Bool, entity: Text, referred: Nat, vol: Vol){
        var quality: Bool = false;
        var entity: Text = "";
        var referred: Nat = 0;
        var vol = {value0: Nat = 0; value1: Nat = 0; };
        switch(Trie.get(ambassadors, keyb(_getAccountId(_ambassador)), Blob.equal)){
            case(?(amb)){
                quality := true;
                entity := amb.0;
                referred := amb.1;
                vol := amb.2;
            };
            case(_){};
        };
        return (quality, entity, referred, vol);
    };

    /// Returns summary data of referral based on entity.
    public query func ta_stats(_entity: ?Text) : async (ambassadors: Nat, referred: Nat, vol: Vol){
        var trie = ambassadors;
        if (Option.isSome(_entity)){
            trie := Trie.filter(trie, func (k: AccountId, v: AmbassadorData): Bool{ v.0 == Option.get(_entity,"")});
        };
        var count: Nat = 0;
        var referred : Nat = 0;
        var vol = {value0: Nat = 0; value1: Nat = 0;};
        for ((k,v) in Trie.iter(trie)){
            count += 1;
            referred += v.1;
            vol := {value0 = vol.value0 + v.2.value0; value1 = vol.value1 + v.2.value1;};
        };
        return (count, referred, vol);
    };

    /// Returns trading ambassadors description
    public query func ta_description() : async Text{
        return taDescription;
    };
    // End: Trading Ambassadors


    // /* ===========================
    //   Competitions section
    //   @deprecated: Removed the competition feature. 
    // ============================== */
    // // T1 -- start -- T2 -- end -- T3 -- settled -- T4
    // type CompCapital = {value0: Nat; value1: Nat; total: Float;}; // @deprecated
    // type RoundItem = { // @deprecated
    //     name: Text;
    //     content: Text; // H5
    //     start: Time.Time;
    //     end: Time.Time;
    //     quoteToken: {#token0; #token1};
    //     closedPrice: ?Float; // 1 smallest token = ? quote smallest token, Set only after the end time
    //     isSettled: Bool;
    //     minCapital: Nat;
    // };
    // type CompResult = { // @deprecated
    //     icrc1Account: ICRC1.Account;
    //     status: {#Active; #Dropout;};
    //     vol: Vol;
    //     capital: CompCapital;
    //     assetValue: ?CompCapital; // Note: Only set after settlement
    // };
    // private stable var activeRound : Nat = 0; // @deprecated
    // private stable var rounds: Trie.Trie<Nat, RoundItem> = Trie.empty(); // @deprecated
    // private stable var competitors: Trie.Trie2D<Nat, AccountId, CompResult> = Trie.empty(); // @deprecated
    // private stable var ictcTaskCallbackEvents: Trie.Trie<SagaTM.Ttid, Time.Time> = Trie.empty(); // @deprecated
    // private func _putTTCallback(_ttid: SagaTM.Ttid) : (){ 
    //     ictcTaskCallbackEvents := Trie.put(ictcTaskCallbackEvents, keyn(_ttid), Nat.equal, Time.now()).0;
    // };
    // private func _removeTTCallback(_ttid: SagaTM.Ttid) : (){ 
    //     ictcTaskCallbackEvents := Trie.remove(ictcTaskCallbackEvents, keyn(_ttid), Nat.equal).0;
    // };
    // private func _clearTTCallback() : (){ 
    //     ictcTaskCallbackEvents := Trie.filter(ictcTaskCallbackEvents, func (k: SagaTM.Ttid, v: Time.Time): Bool{
    //         Time.now() < v + ExpirationDuration;
    //     });
    // };
    // private func _checkTTCallback(_ttid: SagaTM.Ttid, _task: SagaTM.Task) : Bool{ 
    //     if (Time.now() > _task.time + ExpirationDuration){
    //         return false;
    //     };
    //     return Option.isSome(Trie.get(ictcTaskCallbackEvents, keyn(_ttid), Nat.equal));
    // };
    // End: Competitions


    /* ===========================
      ICTC section
    ============================== */
    /*
    * ICTC Transaction Explorer Interface
    * (Optional) Implement the following interface, which allows you to browse transaction records and execute compensation transactions through a UI interface.
    * https://cmqwp-uiaaa-aaaaj-aihzq-cai.raw.ic0.app/
    */
    private stable var ictc_admins: [Principal] = []; // ICTC admins
    private func _onlyIctcAdmin(_caller: Principal) : Bool { 
        return Option.isSome(Array.find(ictc_admins, func (t: Principal): Bool{ t == _caller }));
    }; 
    private func _onlyBlocking(_toid: Nat) : Bool{
        /// Saga
        switch(_getSaga().status(_toid)){
            case(?(status)){ return status == #Blocking }; // or status == #Compensating
            case(_){ return false; };
        };
        /// 2PC
        // switch(_getTPC().status(_toid)){
        //     case(?(status)){ return status == #Blocking };
        //     case(_){ return false; };
        // };
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
    public shared(msg) func ictc_clearLog(_expiration: ?Int, _delForced: Bool) : async (){ 
        assert(_onlyOwner(msg.caller));
        _getSaga().clear(_expiration, _delForced);
    };

    /// Clear the pool of running transaction tasks.  
    /// Warning: Execute this method with caution
    public shared(msg) func ictc_clearTTPool() : async (){
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
        assert(_onlyOwner(msg.caller) or _onlyIctcAdmin(msg.caller));
        let saga = _getSaga();
        let ttid = saga.redo(_toid, _ttid);
        await* _ictcSagaRun(_toid, true);
        return ttid;
    };

    /// Set status of a pending task  
    /// Warning: proceed with caution!
    public shared(msg) func ictc_doneTT(_toid: SagaTM.Toid, _ttid: SagaTM.Ttid, _toCallback: Bool) : async ?SagaTM.Ttid{
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
        assert(_onlyOwner(msg.caller) or _onlyIctcAdmin(msg.caller) or _notPaused(?msg.caller));
        let account = Tools.principalToAccountBlob(msg.caller, null);
        await* _checkOverload(?account);
        if (_onlyOwner(msg.caller)){
            await* _ictcSagaRun(0, true);
        } else if (Time.now() > lastSagaRunningTime + setting.ICTC_RUN_INTERVAL*ns_){ 
            await* _ictcSagaRun(0, false);
        };
        return true;
    };
    /*
    * End: ICTC Transaction Explorer Interface
    */

    /* ===========================
      DRC205 section
    ============================== */
    private func _token0Type() : DRC205.TokenType{
        if (token0Std == #icp){
            return #Icp;
        }else {
            return #Token(_token0Canister());
        };
    };
    private func _token1Type() : DRC205.TokenType{
        if (token1Std == #icp){
            return #Icp;
        }else {
            return #Token(_token1Canister());
        };
    };

    // DRC205: Cache records to local canister
    private func _drc205Store(_txid: Txid, _ia: ?ICRC1.Account, _account: AccountId, _order: {token0Value: ?BalanceChange; token1Value: ?BalanceChange;}, _orderType: OrderType, _filled: {token0Value: BalanceChange; token1Value: BalanceChange;}, 
    _fee0: Int, _fee1: Int, _index: Nat, _nonce: Nonce, _details: [OrderFilled], _status: DRC205.Status, _data: ?Blob) : (){
        var msgCaller: ?Principal = null;
        var caller: Blob = _account;
        switch(_ia){
            case(?(ia)){
                msgCaller := ?ia.owner;
                caller := Option.get(ia.subaccount, Blob.fromArray([])); // Tools.icrc1Encode(ia); // Option.get(ia.subaccount, Blob.fromArray([]));
            };
            case(_){};
        };
        var time = Time.now();
        // switch(drc205.get(_txid)){
        //     case(?(txn)){ time := txn.time };
        //     case(_){};
        // };
        var txn: DRC205.TxnRecord = {
            txid = _txid;
            msgCaller = msgCaller;  
            caller = caller; // ICRC1 pair: subaccount
            operation = #Swap;
            account = _account;
            cyclesWallet = null;
            token0 = _token0Type();
            token1 = _token1Type();
            fee = {token0Fee = _fee0; token1Fee = _fee1; };
            shares = #NoChange;
            time = time;
            index = _index;
            nonce = _nonce;
            order = _order;
            orderMode = #OrderBook;
            orderType = ?_orderType;
            filled = _filled;
            details = _details;
            status = _status; 
            data = _data;
        };
        drc205.put(txn, true);
    };

    // DRC205: Save records to external canister (synchronized)
    private func _callDrc205Store(_sync: Bool, _now: Bool) : async* (){
        if (_tps(15, null).1 < setting.MAX_TPS*7 and (_now or Time.now() > lastStorageTime + setting.STORAGE_INTERVAL*ns_)) { 
            lastStorageTime := Time.now();
            if (_sync){
                await drc205.store(); 
            }else{
                let f = drc205.store(); 
            };
        };
    };

    /// Returns the configuration of DRC205
    public query func drc205_getConfig() : async DRC205.Setting{
        return drc205.getConfig();
    };

    /// Returns the canister-id of the DRC205
    public query func drc205_canisterId() : async Principal{
        return drc205.drc205CanisterId();
    };

    /// Returns trading pair information
    public query func drc205_dexInfo() : async DRC205.DexInfo{
        return {
            canisterId = Principal.fromActor(this);
            mmType = #OrderBook;
            dexName = "icdex";
            pairName = name_;
            token0 = (_token0Type(), token0Std);
            token1 = (_token1Type(), token1Std);
            feeRate = _natToFloat(_getTradingFee()) / 1_000_000;
        };
    };

    /// Configure DRC205.
    public shared(msg) func drc205_config(config: DRC205.Config) : async Bool{ 
        assert(_onlyOwner(msg.caller));
        return drc205.config(config);
    };

    /// returns latest events
    public query func drc205_events(_account: ?DRC205.Address) : async [DRC205.TxnRecord]{
        switch(_account){
            case(?(account)){ return drc205.getEvents(?_getAccountId(account), null, null).0; };
            case(_){return drc205.getEvents(null, null, null).0;}
        };
    };

    /// returns events filtered by time
    public query func drc205_events_filter(_account: ?DRC205.Address, _startTime: ?Time.Time, _endTime: ?Time.Time) : async (data: [DRC205.TxnRecord], mayHaveArchived: Bool){
        switch(_account){
            case(?(account)){ return drc205.getEvents(?_getAccountId(account), _startTime, _endTime); };
            case(_){return drc205.getEvents(null, _startTime, _endTime);}
        };
    };

    /// Returns a txn record. This is a query method that looks for record from this canister cache.
    public query func drc205_txn(_txid: DRC205.Txid) : async (txn: ?DRC205.TxnRecord){
        return drc205.get(_txid);
    };

    /// Returns a txn record. It's an update method that will try to find txn record in the DRC205 canister if it does not exist in this canister.
    public shared(msg) func drc205_txn2(_txid: DRC205.Txid) : async (txn: ?DRC205.TxnRecord){
        let account = Tools.principalToAccountBlob(msg.caller, null);
        await* _checkOverload(?account);
        switch(drc205.get(_txid)){
            case(?(txn)){ return ?txn; };
            case(_){
                try{
                    countAsyncMessage += 3;
                    let res = await* drc205.get2(Principal.fromActor(this), _txid);
                    countAsyncMessage -= Nat.min(3, countAsyncMessage);
                    return res;
                }catch(e){
                    countAsyncMessage -= Nat.min(3, countAsyncMessage);
                    throw Error.reject("420: internal call error: "# Error.message(e)); 
                };
            };
        };
    };

    /// Check the data to be stored by DRC205.
    public query func drc205_pool() : async [(Txid, DRC205.TxnRecord, Nat)]{
        return drc205.getPool();
    };


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

    // /// canister_status
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
        let wallet : Wallet = actor(Principal.toText(icdexRouter));
        let amount = Cycles.balance();
        assert(_amount + 20_000_000_000 < amount);
        Cycles.add(_amount);
        await wallet.wallet_receive();
    };

    // /// timer tick
    // public shared(msg) func timer_tick(): async (){
    //     //
    // };


    /* ===========================
      Upgrade section
    ============================== */
    // Note: Redundant variables are used for compatibility with previous versions
    // private stable var __sagaData: [SagaTM.Data] = [];
    private stable var __sagaDataNew: ?SagaTM.Data = null;
    // private stable var __drc205Data: [DRC205.DataTemp] = [];
    // private stable var __drc205DataV2: [DRC205.DataTempV2] = [];
    private stable var __drc205DataNew: ?DRC205.DataTempV2 = null;
    private var __upgradeMode : {#Base; #All} = #All;

    /// When the data is too large to be backed up, you can set the UpgradeMode to #Base
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
        if (__upgradeMode == #All){
            __drc205DataNew := ?drc205.getData();
        }else{
            __drc205DataNew := ?drc205.getDataBase();
        };
        Timer.cancelTimer(timerId);
    };

    system func postupgrade() {
        // if (__sagaData.size() > 0){
        //     _getSaga().setData(__sagaData[0]);
        //     __sagaData := [];
        // };
        switch(__sagaDataNew){
            case(?(data)){
                _getSaga().setData(data);
                // __sagaData := [];
                __sagaDataNew := null;
            };
            case(_){
                // if (__sagaData.size() > 0){
                //     _getSaga().setData(__sagaData[0]);
                //     __sagaData := [];
                // };
            };
        };
        // if (__drc205DataV2.size() > 0){
        //     drc205.setData(__drc205DataV2[0]);
        //     __drc205DataV2 := [];
        //     __drc205Data := [];
        // };
        switch(__drc205DataNew){
            case(?(data)){
                drc205.setData(data);
                // __drc205Data := [];
                // __drc205DataV2 := [];
                __drc205DataNew := null;
            };
            case(_){
                // if (__drc205DataV2.size() > 0){
                //     drc205.setData(__drc205DataV2[0]);
                //     __drc205DataV2 := [];
                //     __drc205Data := [];
                // };
            };
        };
        timerId := Timer.recurringTimer(#seconds(900), timerLoop);
        // Will be removed in version 0.10
        // for ((txid, tx) in Trie.iter(icdex_orders)){
        //     ignore _addPendingOrder(tx.account, txid);
        // };
    };

    /* ===========================
      Timer section
    ============================== */
    private func timerLoop() : async (){
        _clear();
        _expire();
        await* _ictcSagaRun(0, false);
        await* _callDrc205Store(true, false);
        // try{ /*Competitions*/
        //     await* _compSettle(activeRound);
        //     compInSettlement := false;
        // }catch(e){
        //     compInSettlement := false;
        // };
        if (Cycles.balance() < 300_000_000_000){ // 0.3T
            Timer.cancelTimer(timerId);
        };
        // _clearTTCallback();
        _autoDeleteSTO();
    };
    private var timerId: Nat = 0;

    /// Start the Timer, it will be started automatically when upgrading the canister.
    public shared(msg) func timerStart(_intervalSeconds: Nat): async (){
        assert(_onlyOwner(msg.caller));
        Timer.cancelTimer(timerId);
        timerId := Timer.recurringTimer(#seconds(_intervalSeconds), timerLoop);
    };

    /// Stop the Timer
    public shared(msg) func timerStop(): async (){
        assert(_onlyOwner(msg.caller));
        Timer.cancelTimer(timerId);
    };

    /* ===========================
      Backup / Recovery section
    ============================== */

    // type Toid = SagaTM.Toid;
    // type Ttid = SagaTM.Ttid;
    type Order = SagaTM.Order;
    type Task = SagaTM.Task;
    type SagaData = Backup.SagaData;
    type TxnRecord = DRC205.TxnRecord;
    type DRC205Data = Backup.DRC205Data;
    type BackupRequest = Backup.BackupRequest;
    type BackupResponse = Backup.BackupResponse;

    /// Backs up data of the specified `BackupRequest` classification, and the result is wrapped using the `BackupResponse` type.
    public shared(msg) func backup(_request: BackupRequest) : async BackupResponse{
        assert(_onlyOwner(msg.caller));
        switch(_request){
            case(#otherData){
                return #otherData({
                    icdex_index = icdex_index;
                    icdex_totalFee = icdex_totalFee;
                    icdex_totalVol = icdex_totalVol;
                    icdex_priceWeighted = icdex_priceWeighted;
                    icdex_lastPrice = icdex_lastPrice;
                    taDescription = taDescription;
                    // activeRound = activeRound;
                });
            };
            case(#icdex_orders){
                return #icdex_orders(Trie.toArray<Txid, TradingOrder, (Txid, TradingOrder)>(icdex_orders, 
                    func (k: Txid, v: TradingOrder): (Txid, TradingOrder){
                        return (k, v);
                    }));
            };
            case(#icdex_failedOrders){
                return #icdex_failedOrders(Trie.toArray<Txid, TradingOrder, (Txid, TradingOrder)>(icdex_failedOrders, 
                    func (k: Txid, v: TradingOrder): (Txid, TradingOrder){
                        return (k, v);
                    }));
            };
            case(#icdex_orderBook){
                return #icdex_orderBook({ ask = List.toArray(icdex_orderBook.ask);  bid = List.toArray(icdex_orderBook.bid);});
            };
            case(#icdex_klines2){
                return #icdex_klines2(Trie.toArray<OrderBook.KInterval, Deque.Deque<KBar>, (OrderBook.KInterval, ([KBar], [KBar]))>(icdex_klines2, 
                    func (k: OrderBook.KInterval, v: Deque.Deque<KBar>): (OrderBook.KInterval, ([KBar], [KBar])){
                        return (k, (List.toArray(v.0), List.toArray(v.1)));
                    }));
            };
            case(#icdex_vols){
                return #icdex_vols(Trie.toArray<AccountId, Vol, (AccountId, Vol)>(icdex_vols, 
                    func (k: AccountId, v: Vol): (AccountId, Vol){
                        return (k, v);
                    }));
            };
            case(#icdex_nonces){
                return #icdex_nonces(Trie.toArray<AccountId, Nonce, (AccountId, Nonce)>(icdex_nonces, 
                    func (k: AccountId, v: Nonce): (AccountId, Nonce){
                        return (k, v);
                    }));
            };
            case(#icdex_pendingOrders){
                return #icdex_pendingOrders(Trie.toArray<AccountId, [Txid], (AccountId, [Txid])>(icdex_pendingOrders, 
                    func (k: AccountId, v: [Txid]): (AccountId, [Txid]){
                        return (k, v);
                    }));
            };
            case(#icdex_makers){
                return #icdex_makers(Trie.toArray<AccountId, (Nat, Principal), (AccountId, (Nat, Principal))>(icdex_makers, 
                    func (k: AccountId, v: (Nat, Principal)): (AccountId, (Nat, Principal)){
                        return (k, v);
                    }));
            };
            case(#icdex_dip20Balances){
                return #icdex_dip20Balances(Trie.toArray<AccountId, (Principal, Nat), (AccountId, (Principal, Nat))>(icdex_dip20Balances, 
                    func (k: AccountId, v: (Principal, Nat)): (AccountId, (Principal, Nat)){
                        return (k, v);
                    }));
            };
            case(#clearingTxids){
                return #clearingTxids(List.toArray(clearingTxids));
            };
            case(#timeSortedTxids){ 
                let deque = (
                    List.filter(timeSortedTxids.0, func (t: (Txid,Int)): Bool{ Option.isSome(Trie.get(icdex_orders, keyb(t.0), Blob.equal)) }), 
                    List.filter(timeSortedTxids.1, func (t: (Txid,Int)): Bool{ Option.isSome(Trie.get(icdex_orders, keyb(t.0), Blob.equal)) })
                );
                return #timeSortedTxids((List.toArray(deque.0), List.toArray(deque.1)));
            };
            case(#ambassadors){
                return #ambassadors(Trie.toArray<AccountId, AmbassadorData, (AccountId, AmbassadorData)>(ambassadors, 
                    func (k: AccountId, v: AmbassadorData): (AccountId, AmbassadorData){
                        return (k, v);
                    }));
            };
            case(#traderReferrers){
                return #traderReferrers(Trie.toArray<AccountId, AccountId, (AccountId, AccountId)>(traderReferrers, 
                    func (k: AccountId, v: AccountId): (AccountId, AccountId){
                        return (k, v);
                    }));
            };
            // case(#rounds){
            //     return #rounds(Trie.toArray<Nat, RoundItem, (Nat, RoundItem)>(rounds, 
            //         func (k: Nat, v: RoundItem): (Nat, RoundItem){
            //             return (k, v);
            //         }));
            // };
            // case(#competitors){
            //     return #competitors(Trie.toArray<Nat, Trie.Trie<AccountId, CompResult>, (Nat, [(AccountId, CompResult)])>(competitors, 
            //         func (k: Nat, v: Trie.Trie<AccountId, CompResult>): (Nat, [(AccountId, CompResult)]){
            //             return (k, Trie.toArray<AccountId, CompResult, (AccountId, CompResult)>(v, 
            //                 func (k1: AccountId, v1: CompResult): (AccountId, CompResult){
            //                     return (k1, v1);
            //                 }));
            //         }));
            // };
            case(#sagaData(mode)){
                var data = _getSaga().getDataBase();
                if (mode == #All){
                    data := _getSaga().getData();
                };
                return #sagaData({
                    autoClearTimeout = data.autoClearTimeout; 
                    index = data.index; 
                    firstIndex = data.firstIndex; 
                    orders = data.orders; 
                    aliveOrders = List.toArray(data.aliveOrders); 
                    taskEvents = data.taskEvents; 
                    actuator = {
                        tasks = (List.toArray(data.actuator.tasks.0), List.toArray(data.actuator.tasks.1)); 
                        taskLogs = data.actuator.taskLogs; 
                        errorLogs = data.actuator.errorLogs; 
                        callees = data.actuator.callees; 
                        index = data.actuator.index; 
                        firstIndex = data.actuator.firstIndex; 
                        errIndex = data.actuator.errIndex; 
                        firstErrIndex = data.actuator.firstErrIndex; 
                    }; 
                });
            };
            case(#drc205Data(mode)){
                var data = drc205.getDataBase();
                if (mode == #All){
                    data := drc205.getData();
                };
                return #drc205Data({
                    setting = data.setting;
                    txnRecords = Trie.toArray<Txid, TxnRecord, (Txid, TxnRecord)>(data.txnRecords, 
                        func (k: Txid, v: TxnRecord): (Txid, TxnRecord){
                            return (k, v);
                        });
                    globalTxns = (List.toArray(data.globalTxns.0), List.toArray(data.globalTxns.1));
                    globalLastTxns = (List.toArray(data.globalLastTxns.0), List.toArray(data.globalLastTxns.1));
                    accountLastTxns = Trie.toArray<AccountId, Deque.Deque<Txid>, (AccountId, ([Txid], [Txid]))>(data.accountLastTxns, 
                        func (k: AccountId, v: Deque.Deque<Txid>): (AccountId, ([Txid], [Txid])){
                            return (k, (List.toArray(v.0), List.toArray(v.1)));
                        });
                    storagePool = List.toArray(data.storagePool);
                });
            };
            case(#traderReferrerTemps){
                return #traderReferrerTemps(Trie.toArray<AccountId, (AccountId, Text, Time.Time), (AccountId, (AccountId, Text, Time.Time))>(traderReferrerTemps, 
                    func (k: AccountId, v: (AccountId, Text, Time.Time)): (AccountId, (AccountId, Text, Time.Time)){
                        return (k, v);
                    }));
            };
            // case(#ictcTaskCallbackEvents){
            //     return #ictcTaskCallbackEvents(Trie.toArray<Ttid, Time.Time, (Ttid, Time.Time)>(ictcTaskCallbackEvents, 
            //         func (k: Ttid, v: Time.Time): (Ttid, Time.Time){
            //             return (k, v);
            //         }));
            // };
            case(#ictc_admins){
                return #ictc_admins(ictc_admins);
            };
            case(#icdex_RPCAccounts){
                return #icdex_RPCAccounts(Trie.toArray<ETHAddress, [ICRC1.Account], (ETHAddress, [ICRC1.Account])>(icdex_RPCAccounts, 
                    func (k: ETHAddress, v: [ICRC1.Account]): (ETHAddress, [ICRC1.Account]){
                        return (k, v);
                    }));
            };
            case(#icdex_accountSettings){
                return #icdex_accountSettings(Trie.toArray<AccountId, AccountSetting, (AccountId, AccountSetting)>(icdex_accountSettings, 
                    func (k: AccountId, v: AccountSetting): (AccountId, AccountSetting){
                        return (k, v);
                    }));
            };
            case(#icdex_keepingBalances){
                return #icdex_keepingBalances(Trie.toArray<AccountId, KeepingBalance, (AccountId, KeepingBalance)>(icdex_keepingBalances, 
                    func (k: AccountId, v: KeepingBalance): (AccountId, KeepingBalance){
                        return (k, v);
                    }));
            };
            case(#icdex_poolBalance){
                return #icdex_poolBalance(icdex_poolBalance);
            };
            case(#icdex_sto){
                return #icdex_sto({
                    icdex_soid = icdex_soid;
                    icdex_activeProOrderList = List.toArray(icdex_activeProOrderList);
                    icdex_activeStopLossOrderList = {buy=List.toArray(icdex_activeStopLossOrderList.buy); sell=List.toArray(icdex_activeStopLossOrderList.sell)};
                });
            };
            case(#icdex_stOrderRecords){
                return #icdex_stOrderRecords(Trie.toArray<STO.Soid, STO.STOrder, (STO.Soid, STO.STOrder)>(icdex_stOrderRecords, 
                    func (k: STO.Soid, v: STO.STOrder): (STO.Soid, STO.STOrder){
                        return (k, v);
                    }));
            };
            case(#icdex_userProOrderList){
                return #icdex_userProOrderList(Trie.toArray<AccountId, List.List<STO.Soid>, (AccountId, [STO.Soid])>(icdex_userProOrderList, 
                    func (k: AccountId, v: List.List<STO.Soid>): (AccountId, [STO.Soid]){
                        return (k, List.toArray(v));
                    }));
            };
            case(#icdex_userStopLossOrderList){
                return #icdex_userStopLossOrderList(Trie.toArray<AccountId, List.List<STO.Soid>, (AccountId, [STO.Soid])>(icdex_userStopLossOrderList, 
                    func (k: AccountId, v: List.List<STO.Soid>): (AccountId, [STO.Soid]){
                        return (k, List.toArray(v));
                    }));
            };
            case(#icdex_stOrderTxids){
                return #icdex_stOrderTxids(Trie.toArray<Txid, STO.Soid, (Txid, STO.Soid)>(icdex_stOrderTxids, 
                    func (k: Txid, v: STO.Soid): (Txid, STO.Soid){
                        return (k, v);
                    }));
            };
        };
    };
    
    /// Restore `BackupResponse` data to the canister's global variable.
    public shared(msg) func recovery(_request: BackupResponse) : async Bool{
        assert(_onlyOwner(msg.caller));
        switch(_request){
            case(#otherData(data)){
                icdex_index := data.icdex_index;
                icdex_totalFee := data.icdex_totalFee;
                icdex_totalVol := data.icdex_totalVol;
                icdex_priceWeighted := data.icdex_priceWeighted;
                icdex_lastPrice := data.icdex_lastPrice;
                taDescription := data.taDescription;
                // activeRound := data.activeRound;
            };
            case(#icdex_orders(data)){
                for ((k, v) in data.vals()){
                    icdex_orders := Trie.put(icdex_orders, keyb(k), Blob.equal, v).0;
                };
            };
            case(#icdex_failedOrders(data)){
                for ((k, v) in data.vals()){
                    icdex_failedOrders := Trie.put(icdex_failedOrders, keyb(k), Blob.equal, v).0;
                };
            };
            case(#icdex_orderBook(data)){
                icdex_orderBook := { ask = List.fromArray(data.ask);  bid = List.fromArray(data.bid);};
            };
            case(#icdex_klines2(data)){ //*
                for ((k, v) in data.vals()){
                    icdex_klines2 := Trie.put(icdex_klines2, keyn(k), Nat.equal, (List.fromArray(v.0), List.fromArray(v.1))).0;
                };
            };
            case(#icdex_vols(data)){
                for ((k, v) in data.vals()){
                    icdex_vols := Trie.put(icdex_vols, keyb(k), Blob.equal, v).0;
                };
            };
            case(#icdex_nonces(data)){
                for ((k, v) in data.vals()){
                    icdex_nonces := Trie.put(icdex_nonces, keyb(k), Blob.equal, v).0;
                };
            };
            case(#icdex_pendingOrders(data)){
                for ((k, v) in data.vals()){
                    icdex_pendingOrders := Trie.put(icdex_pendingOrders, keyb(k), Blob.equal, v).0;
                };
            };
            case(#icdex_makers(data)){
                for ((k, v) in data.vals()){
                    icdex_makers := Trie.put(icdex_makers, keyb(k), Blob.equal, v).0;
                };
            };
            case(#icdex_dip20Balances(data)){
                for ((k, v) in data.vals()){
                    icdex_dip20Balances := Trie.put(icdex_dip20Balances, keyb(k), Blob.equal, v).0;
                };
            };
            case(#clearingTxids(data)){
                clearingTxids := List.fromArray(data);
            };
            case(#timeSortedTxids(data)){ //*
                timeSortedTxids := (List.fromArray(data.0), List.fromArray(data.1));
            };
            case(#ambassadors(data)){
                for ((k, v) in data.vals()){
                    ambassadors := Trie.put(ambassadors, keyb(k), Blob.equal, v).0;
                };
            };
            case(#traderReferrers(data)){
                for ((k, v) in data.vals()){
                    traderReferrers := Trie.put(traderReferrers, keyb(k), Blob.equal, v).0;
                };
            };
            // case(#rounds(data)){
            //     for ((k, v) in data.vals()){
            //         rounds := Trie.put(rounds, keyn(k), Nat.equal, v).0;
            //     };
            // };
            // case(#competitors(data)){
            //     for ((k, v) in data.vals()){
            //         var trie: Trie.Trie<AccountId, CompResult> = Trie.empty();
            //         for ((k1, v1) in v.vals()){
            //             trie := Trie.put(trie, keyb(k1), Blob.equal, v1).0;
            //         };
            //         competitors := Trie.put(competitors, keyn(k), Nat.equal, trie).0;
            //     };
            // };
            case(#sagaData(data)){
                _getSaga().setData({
                    autoClearTimeout = data.autoClearTimeout; 
                    index = data.index; 
                    firstIndex = data.firstIndex; 
                    orders = data.orders; 
                    aliveOrders = List.fromArray(data.aliveOrders); 
                    taskEvents = data.taskEvents; 
                    actuator = {
                        tasks = (List.fromArray(data.actuator.tasks.0), List.fromArray(data.actuator.tasks.1)); 
                        taskLogs = data.actuator.taskLogs; 
                        errorLogs = data.actuator.errorLogs; 
                        callees = data.actuator.callees; 
                        index = data.actuator.index; 
                        firstIndex = data.actuator.firstIndex; 
                        errIndex = data.actuator.errIndex; 
                        firstErrIndex = data.actuator.firstErrIndex; 
                    }; 
                });
            };
            case(#drc205Data(data)){
                var txnRecords: Trie.Trie<Txid, TxnRecord> = Trie.empty();
                for ((k, v) in data.txnRecords.vals()){
                    txnRecords := Trie.put(txnRecords, keyb(k), Blob.equal, v).0;
                };
                var accountLastTxns: Trie.Trie<AccountId, Deque.Deque<Txid>> = Trie.empty();
                for ((k, v) in data.accountLastTxns.vals()){
                    accountLastTxns := Trie.put(accountLastTxns, keyb(k), Blob.equal, (List.fromArray(v.0), List.fromArray(v.1))).0;
                };
                drc205.setData({
                    setting = data.setting;
                    txnRecords = txnRecords;
                    globalTxns = (List.fromArray(data.globalTxns.0), List.fromArray(data.globalTxns.1));
                    globalLastTxns = (List.fromArray(data.globalLastTxns.0), List.fromArray(data.globalLastTxns.1));
                    accountLastTxns = accountLastTxns;
                    storagePool = List.fromArray(data.storagePool);
                });
            };
            case(#traderReferrerTemps(data)){
                for ((k, v) in data.vals()){
                    traderReferrerTemps := Trie.put(traderReferrerTemps, keyb(k), Blob.equal, v).0;
                };
            };
            // case(#ictcTaskCallbackEvents(data)){
            //     for ((k, v) in data.vals()){
            //         ictcTaskCallbackEvents := Trie.put(ictcTaskCallbackEvents, keyn(k), Nat.equal, v).0;
            //     };
            // };
            case(#ictc_admins(data)){
                ictc_admins := data;
            };
            case(#icdex_RPCAccounts(data)){
                for ((k, v) in data.vals()){
                    icdex_RPCAccounts := Trie.put(icdex_RPCAccounts, keyt(k), Text.equal, v).0;
                };
            };
            case(#icdex_accountSettings(data)){
                for ((k, v) in data.vals()){
                    icdex_accountSettings := Trie.put(icdex_accountSettings, keyb(k), Blob.equal, v).0;
                };
            };
            case(#icdex_keepingBalances(data)){
                for ((k, v) in data.vals()){
                    icdex_keepingBalances := Trie.put(icdex_keepingBalances, keyb(k), Blob.equal, v).0;
                };
            };
            case(#icdex_poolBalance(data)){
                icdex_poolBalance := data;
            };
            case(#icdex_sto(data)){
                icdex_soid := data.icdex_soid;
                icdex_activeProOrderList := List.fromArray(data.icdex_activeProOrderList);
                icdex_activeStopLossOrderList := {buy = List.fromArray(data.icdex_activeStopLossOrderList.buy); sell = List.fromArray(data.icdex_activeStopLossOrderList.sell)};
            };
            case(#icdex_stOrderRecords(data)){
                for ((k, v) in data.vals()){
                    icdex_stOrderRecords := Trie.put(icdex_stOrderRecords, keyn(k), Nat.equal, v).0;
                };
            };
            case(#icdex_userProOrderList(data)){
                for ((k, v) in data.vals()){
                    icdex_userProOrderList := Trie.put(icdex_userProOrderList, keyb(k), Blob.equal, List.fromArray(v)).0;
                };
            };
            case(#icdex_userStopLossOrderList(data)){
                for ((k, v) in data.vals()){
                    icdex_userStopLossOrderList := Trie.put(icdex_userStopLossOrderList, keyb(k), Blob.equal, List.fromArray(v)).0;
                };
            };
            case(#icdex_stOrderTxids(data)){
                for ((k, v) in data.vals()){
                    icdex_stOrderTxids := Trie.put(icdex_stOrderTxids, keyb(k), Blob.equal, v).0;
                };
            };
        };
        return true;
    };

};
