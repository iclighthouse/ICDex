import Router "mo:icl/ICDexRouter";
import Pair "mo:icl/ICDexTypes";
import Maker "mo:icl/ICDexMaker";
import ICDexPrivate "ICDexPrivate";
import DRC205 "mo:icl/DRC205";
import ERC721 "mo:icl/ERC721";
import ICRC1 "mo:icl/ICRC1";
import SagaTM "../ICTC/SagaTM";

module {
    public type Txid = Blob;
    public type Sa = [Nat8];
    public type AccountId = Blob;
    public type ICRC1Account = {owner: Principal; subaccount: ?Blob; };
    public type Address = Text;
    public type Nonce = Nat;
    public type Amount = Nat;
    public type BlockHeight = Nat;
    public type Timestamp = Nat; // seconds
    public type Event = { 
        #initOrUpgrade : {version: Text};
        #changeOwner: {newOwner: Principal};
        #sysConfig: {
            aggregator: ?Principal;
            blackhole: ?Principal;
            icDao: ?Principal;
            nftPlanetCards: ?Principal;
            sysToken: ?Principal;
            sysTokenFee: ?Nat;
            creatingPairFee: ?Nat;
            creatingMakerFee: ?Nat;
        };
        #sysWithdraw: { token: Principal; to: Principal; value: Nat; txid: {#txid: Txid; #index: Nat} };
        #sysTrade: { pair: Principal; tokenTxid : {#txid: Txid; #index: Nat}; order: Pair.OrderPrice; orderType: Pair.OrderType; result: Pair.TradingResult };
        #sysCancelOrder: { pair: Principal; txid: ?Txid };
        #timerStart: { intervalSeconds: Nat };
        #timerStop;
        #createPairByUser: { token0: Principal; token1: Principal; pairCanisterId: Principal };
        #setICDexPairWasm: { version: Text; append: Bool; backupPreVersion: Bool };
        #createPair: { token0: Principal; token1: Principal; unitSize: ?Nat64; initCycles: ?Nat; pairCanisterId: Principal };
        #upgradePairWasm: { pair: Principal; version: Text; success: Bool };
        #rollbackPairWasm: { pair: Principal; success: Bool };
        #reinstallPairWasm: { pair: Principal; version: Text; success: Bool };
        #setPairControllers: { pair: Principal; controllers: [Principal] };
        #removePairDataSnapshot: { pair: Principal; timeBefore: Timestamp; };
        #backupPairData: { pair: Principal; timestamp: Timestamp; };
        #recoveryPairData: { pair: Principal; timestamp: Timestamp; };
        #addPairToList: { pair: Principal;};
        #removePairFromList: { pair: Principal;};
        #pairEnableIDOAndSetFunder: { pair: Principal; funder: ?Principal; _requirement: ?ICDexPrivate.IDORequirement};
        #pairStart: { pair: Principal; message: ?Text };
        #pairSuspend: { pair: Principal; message: ?Text };
        #pairChangeOwner: { pair: Principal; newOwner: Principal};
        #pairConfig: { pair: Principal; setting: ?Pair.DexConfig; drc205config: ?DRC205.Config };
        #pairSetAuctionMode: { pair: Principal; result: (Bool, AccountId) };
        #pairSetUpgradeMode: { pair: Principal; mode: {#Base; #All} };
        #pairSetOrderFail: { pair: Principal; txidHex: Text; refundToken0: Amount; refundToken1: Amount };
        #pairEnableStratOrder: { pair: Principal; arg: {#Enable; #Disable} };
        #pairSTOConfig: {pair: Principal; config: {
            poFee1: ?Nat; 
            poFee2: ?Float; 
            sloFee1: ?Nat; 
            sloFee2: ?Float; 
            gridMaxPerSide: ?Nat; 
            proCountMax: ?Nat;
            stopLossCountMax: ?Nat;
        }};
        #pairICTCSetAdmin: { app: Principal; admin: Principal; act: { #Add; #Remove } };
        #pairICTCClearLog: { app: Principal; expiration: ?Int; forced: Bool };
        #pairICTCRedoTT: { app: Principal; toid: Nat; ttid: Nat; completed: Bool };
        #pairICTCCompleteTO: { app: Principal; toid: Nat; status: SagaTM.OrderStatus; completed: Bool };
        #pairICTCDoneTT: { app: Principal; toid: Nat; ttid: Nat; callbacked: Bool; completed: Bool};
        #pairICTCDoneTO: { app: Principal; toid: Nat; status: SagaTM.OrderStatus; callbacked: Bool; completed: Bool};
        #pairICTCRunTO: { app: Principal; toid: Nat; result: ?SagaTM.OrderStatus };
        #pairICTCBlockTO: { app: Principal; toid: Nat; completed: Bool };
        #pairSync: { pair: Principal; };
        #pairSetVipMaker: { pair: Principal; account: Address; rebateRate: Nat };
        #pairRemoveVipMaker: { pair: Principal; account: Address };
        #pairFallbackByTxid: { pair: Principal; txid: Txid; result: Bool};
        #pairCancelByTxid: { pair: Principal; txid: Txid };
        #pairTASetDescription: { pair: Principal; desc: Text };
        #dexAddCompetition: { id: ?Nat; name: Text; start: Int; end: Int; addPairs: [{dex: Text; canisterId: Principal; quoteToken:{#token0; #token1}; minCapital: Nat}] };
        #nftTransferFrom: { collId: Principal; nftId: ERC721.TokenIdentifier; args: ERC721.TransferRequest; result: ERC721.TransferResponse };
        #nftWithdraw: { collId: Principal; nftId: ERC721.TokenIdentifier; args: ERC721.TransferRequest; result: ERC721.TransferResponse };
        #nftSetVipMaker: { pair: Principal; nftId: ERC721.TokenIdentifier; vipMaker: Text; rebateRate: Nat };
        #nftRemoveVipMaker: { pair: Principal; vipMaker: Text };
        #setMakerWasm: { version: Text; append: Bool; backupPreVersion: Bool };
        #createMaker: { version: Text; makerCanisterId: Principal; arg: {
            pair: Principal;
            allow: {#Public; #Private};
            name: Text; // "AAA_BBB DeMM-1"
            lowerLimit: Nat; //Price
            upperLimit: Nat; //Price
            spreadRate: Nat; // e.g. 10000, ppm  x/1000000
            threshold: Nat; // e.g. 1000000000000 token1, After the total liquidity exceeds this threshold, the LP adds liquidity up to a limit of volFactor times his trading volume.
            volFactor: Nat; // e.g. 2
        } };
        #upgradeMaker: { version: Text; pair: Principal; maker: Principal; name: ?Text; completed: Bool };
        #reinstallMaker: { version: Text; pair: Principal; maker: Principal; completed: Bool };
        #rollbackMaker: { pair: Principal; maker: Principal; completed: Bool };
        #removeMaker: { pair: Principal; maker: Principal; };
        #makerSetControllers: { pair: Principal; maker: Principal; controllers: [Principal] };
        #makerConfig: { maker: Principal; config: Maker.Config };
        #makerTransactionLock: { maker: Principal; act: {#lock; #unlock} };
        #makerStart: { maker: Principal};
        #makerSuspend: { maker: Principal};
        #makerResetLocalBalance: { maker: Principal; balance: Maker.PoolBalance };
        #makerDexDeposit: { maker: Principal; token0: Amount; token1: Amount; result: (Amount, Amount) };
        #makerDexWithdraw: { maker: Principal; token0: Amount; token1: Amount; result: (Amount, Amount) };
        #makerDeleteGridOrder: { maker: Principal; };
        #makerCreateGridOrder: { maker: Principal; };
        #makerCancelAllOrders: { maker: Principal; };
        #chargeFee: { token: Principal; arg: ICRC1.TransferFromArgs; result: { #Ok : Nat; #Err : ICRC1.TransferFromError }; };
        #refundFee: { token: Principal; arg: ICRC1.TransferArgs; result: { #Ok : Nat; #Err : ICRC1.TransferError }; };
    };
}