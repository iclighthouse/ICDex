import Time "mo:base/Time";
import DRC205 "mo:icl/DRC205";
import SagaTM "../ICTC/SagaTM";
import Types "mo:icl/ICDexTypes";
import OrderBook "mo:icl/OrderBook";
import STO "mo:icl/STOTypes";

module {
    public type Txid = Blob;
    public type AccountId = Blob;
    public type Address = Text;
    public type Amount = Nat;
    public type Sa = [Nat8];
    public type Nonce = Nat;
    public type Toid = SagaTM.Toid;
    public type Ttid = SagaTM.Ttid;
    public type Order = SagaTM.Order;
    public type Task = SagaTM.Task;
    public type SagaData = {
        autoClearTimeout: Int; 
        index: Nat; 
        firstIndex: Nat; 
        orders: [(Toid, Order)]; 
        aliveOrders: [(Toid, Time.Time)]; 
        taskEvents: [(Toid, [Ttid])];
        actuator: {
            tasks: ([(Ttid, Task)], [(Ttid, Task)]); 
            taskLogs: [(Ttid, SagaTM.TaskEvent)]; 
            errorLogs: [(Nat, SagaTM.ErrorLog)]; 
            callees: [(SagaTM.Callee, SagaTM.CalleeStatus)]; 
            index: Nat; 
            firstIndex: Nat; 
            errIndex: Nat; 
            firstErrIndex: Nat; 
        }; 
    };
    public type TxnRecord = DRC205.TxnRecord;
    public type DRC205Data = {
        setting: DRC205.Setting;
        txnRecords: [(Txid, TxnRecord)];
        globalTxns: ([(Txid, Time.Time)], [(Txid, Time.Time)]);
        globalLastTxns: ([Txid], [Txid]);
        accountLastTxns: [(AccountId, ([Txid], [Txid]))]; 
        storagePool: [(Txid, TxnRecord, Nat)];
    };
    public type AmbassadorData = (entity: Text, referred: Nat, vol: Types.Vol);
    public type CompCapital = {value0: Nat; value1: Nat; total: Float;};
    public type RoundItem = {
        name: Text;
        content: Text; // H5
        start: Time.Time;
        end: Time.Time;
        quoteToken: {#token0; #token1};
        closedPrice: ?Float; // 1 base token = ? quote token
        isSettled: Bool;
        minCapital: Nat;
    };
    public type CompResult = {
        icrc1Account: { owner : Principal; subaccount : ?Blob; };
        status: {#Active; #Dropout;};
        vol: Types.Vol;
        capital: CompCapital;
        assetValue: ?CompCapital; // balanceAccount
    };
    public type BackupRequest = {
        #otherData;
        #icdex_orders;
        #icdex_failedOrders;
        #icdex_orderBook;
        #icdex_klines2;  //Trie.Trie<KInterval, Deque.Deque<KBar>>;
        #icdex_vols;
        #icdex_nonces;
        #icdex_pendingOrders;
        #icdex_makers;
        #icdex_dip20Balances;
        #clearingTxids;
        #timeSortedTxids;
        #ambassadors;
        #traderReferrerTemps;
        #traderReferrers;
        #rounds;
        #competitors;
        #sagaData: {#All; #Base};
        #drc205Data: {#All; #Base};
        #ictcTaskCallbackEvents;
        #ictc_admins;
        #icdex_RPCAccounts;
        #icdex_accountSettings;
        #icdex_keepingBalances;
        #icdex_poolBalance;
        #icdex_sto;
        #icdex_stOrderRecords;
        #icdex_userProOrderList;
        #icdex_userStopLossOrderList;
        #icdex_stOrderTxids;
    };

    public type BackupResponse = {
        #otherData: {
            icdex_index: Nat;
            icdex_totalFee: Types.FeeBalance;
            icdex_totalVol: Types.Vol;
            icdex_priceWeighted: Types.PriceWeighted;
            icdex_lastPrice: Types.OrderPrice;
            taDescription: Text;
            activeRound: Nat;
        };
        #icdex_orders: [(Txid, Types.TradingOrder)];
        #icdex_failedOrders: [(Txid, Types.TradingOrder)];
        #icdex_orderBook: { ask: [(Txid, Types.OrderPrice)];  bid: [(Txid, Types.OrderPrice)]};
        #icdex_klines2: [(OrderBook.KInterval, ([OrderBook.KBar], [OrderBook.KBar]))];
        #icdex_vols: [(AccountId, Types.Vol)];
        #icdex_nonces: [(AccountId, Nonce)];
        #icdex_pendingOrders: [(AccountId, [Txid])];
        #icdex_makers: [(AccountId, (Nat, Principal))];
        #icdex_dip20Balances: [(AccountId, (Principal, Nat))];
        #clearingTxids: [Txid];
        #timeSortedTxids: ([(Txid, Time.Time)], [(Txid, Time.Time)]);
        #ambassadors: [(AccountId, AmbassadorData)];
        #traderReferrerTemps: [(AccountId, (AccountId, Text, Time.Time))];
        #traderReferrers: [(AccountId, AccountId)];
        #rounds: [(Nat, RoundItem)];
        #competitors: [(Nat, [(AccountId, CompResult)])];
        #sagaData: SagaData;
        #drc205Data: DRC205Data;
        #ictcTaskCallbackEvents: [(Ttid, Time.Time)];
        #ictc_admins: [Principal];
        #icdex_RPCAccounts: [(Text, [{ owner : Principal; subaccount : ?Blob; }])];
        #icdex_accountSettings: [(AccountId, Types.AccountSetting)];
        #icdex_keepingBalances: [(AccountId, Types.KeepingBalance)];
        #icdex_poolBalance: {token0: Amount; token1: Amount };
        #icdex_sto: {
            icdex_soid: Nat;
            icdex_activeProOrderList: [STO.Soid];
            icdex_activeStopLossOrderList: {buy:[(STO.Soid, STO.Price)]; sell:[(STO.Soid, STO.Price)]};
        };
        #icdex_stOrderRecords: [(STO.Soid, STO.STOrder)];
        #icdex_userProOrderList: [(AccountId, [STO.Soid])];
        #icdex_userStopLossOrderList: [(AccountId, [STO.Soid])];
        #icdex_stOrderTxids: [(STO.Txid, STO.Soid)];
    };
};