import DRC205 "mo:icl/DRC205";
import SagaTM "../ICTC/SagaTM";
import ICDexTypes "mo:icl/ICDexTypes";
import Backup "ICDexBackupTypes";

module {
    public type AccountId = Blob;
    public type Address = Text;
    public type Txid = Blob;
    public type Toid = Nat;
    public type Amount = Nat;
    public type Sa = [Nat8];
    public type Nonce = Nat;
    public type Data = Blob;
    public type DexSetting_ = {
        UNIT_SIZE: Nat; // 1000000 token smallest units
        ICP_FEE: Nat; // 10000 E8s
        TRADING_FEE: Nat; // /1000000   value 5000 means 0.5%
        MAKER_BONUS_RATE: Nat; // /100  value 50  means 50%
    };
    public type DexSetting = ICDexTypes.DexSetting;
    public type DexConfig = ICDexTypes.DexConfig;
    public type IDORequirement = { // For non-whitelisted users
        pairs: [{pair: Principal; token1ToUsdRatio: Float}]; // 1 smallest_units = ? USD
        threshold: Float; //USD
    };
    public type Self = actor {
        fee : shared query () -> async {maker: { buy: Float; sell: Float }; taker: { buy: Float; sell: Float }};
        feeStatus : shared query () -> async ICDexTypes.FeeStatus;
        init: shared () -> async ();
        cancelByTxid : shared (_txid: Txid, _sa: ?Sa) -> async ();
        fallbackByTxid : shared (_txid: Txid, _sa: ?Sa) -> async Bool;
        setVipMaker : shared (_account: Address, _rate: Nat) -> async ();
        removeVipMaker : shared (_account: Address) -> async ();
        // changeOwner : shared (_newOwner: Principal) -> async Bool;
        setOrderFail : shared (_txid: Text, _unlock0: Amount, _unlock1: Amount) -> async Bool;
        sto_enableStratOrder : shared (_arg: {#Enable; #Disable}) -> async ();
        sto_config: shared (_config: {
            poFee1: ?Nat; 
            poFee2: ?Float; 
            sloFee1: ?Nat; 
            sloFee2: ?Float; 
            gridMaxPerSide: ?Nat; 
            proCountMax: ?Nat;
            stopLossCountMax: ?Nat;
        }) -> async ();
        pendingAll : shared query(_page: ?Nat, _size: ?Nat) -> async ICDexTypes.TrieList<Txid, ICDexTypes.TradingOrder>;
        sync : shared () -> async ();
        getConfig : shared query() -> async DexSetting;
        config : shared (_config: DexConfig) -> async Bool;
        setPause : shared (_pause: Bool, _openingTime: ?Int) -> async Bool;
        info : shared query () -> async {
            name: Text;
            version: Text;
            decimals: Nat8;
            owner: Principal;
            paused: Bool;
            setting: DexSetting;
            token0: ICDexTypes.TokenInfo;
            token1: ICDexTypes.TokenInfo;
        };
        // disableTrading : shared (_set: Bool) -> async Bool;
        drc205_config : shared (config: DRC205.Config) -> async Bool;
        ictc_addAdmin : shared (_admin: Principal) -> async ();
        ictc_removeAdmin : shared (_admin: Principal) -> async ();
        ictc_clearLog : shared (_expiration: ?Int, _delForced: Bool) -> async ();
        ictc_clearTTPool : shared () -> async ();
        ictc_manageOrder1 : shared (_txid: Txid, _orderStatus: ICDexTypes.TradingStatus, _token0Fallback: Amount, _token1Fallback: Amount, _token0FromPair: Amount, _token1FromPair: Amount) -> async Bool;
        ictc_redoTT : shared (SagaTM.Toid, SagaTM.Ttid) -> async (?SagaTM.Ttid);
        ictc_doneTT : shared (SagaTM.Toid, SagaTM.Ttid, Bool) -> async (?SagaTM.Ttid);
        ictc_doneTO : shared (SagaTM.Toid, SagaTM.OrderStatus, Bool) -> async Bool;
        ictc_runTO : shared (SagaTM.Toid) -> async ?SagaTM.OrderStatus;
        ictc_blockTO : shared (SagaTM.Toid) -> async ?SagaTM.Toid;
        ta_setDescription : shared (_desc: Text) -> async ();
        // comp_newRound : shared (_name: Text, _content: Text, _start: Int, _end: Int, _quoteToken:{#token0; #token1}, _minCapital: Nat, _forced: Bool) -> async Nat;
        setUpgradeMode : shared (_mode: {#Base; #All}) -> async ();
        backup : shared (_request: Backup.BackupRequest) -> async Backup.BackupResponse;
        recovery : shared (_request: Backup.BackupResponse) -> async Bool;
        timerStart : shared (_intervalSeconds: Nat) -> async ();
        timerStop : shared () -> async ();
        IDO_setFunder : shared (_funder: ?Principal, _requirement: ?IDORequirement) -> async ();
        withdraw_cycles : shared(_amount: Nat) -> async ();
    };
    public type V0_9_0 = actor {
        getConfig : shared query() -> async DexSetting_;
        setMaxTPS : shared (Nat, Nat, Nat) -> async Bool;
    };
};