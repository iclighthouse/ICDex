import Time "mo:base/Time";
import DRC205 "mo:icl/DRC205";
import SagaTM "../ICTC/SagaTM";
import Types "mo:icl/ICDexTypes";
import OrderBook "mo:icl/OrderBook";
import Maker "mo:icl/ICDexMaker";

module {
    public type Txid = Blob;
    public type AccountId = Blob;
    public type Address = Text;
    public type Amount = Nat;
    public type Timestamp = Nat;
    public type Time = Int;
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
    public type BackupRequest = {
        #otherData;
        #unitNetValues: {#All; #Base};
        #accountShares: {#All; #Base};
        #accountVolUsed: {#All; #Base};
        #blockEvents;
        #accountEvents;
        #fallbacking_accounts;
    };

    public type BackupResponse = {
        #otherData: {
            shareDecimals: Nat8;
            shareUnitSize: Nat;
            creator: AccountId;
            visibility: {#Public; #Private};
            poolLocalBalance: Maker.PoolBalance;
            poolBalance: Maker.PoolBalance;
            poolShares: Nat;
            poolShareWeighted: Maker.ShareWeighted;
            gridSoid : ?Nat;
            gridOrderDeleted : Bool;
            gridSoid2 : ?Nat;
            gridOrderDeleted2 : Bool;
            blockIndex : Nat;
            firstBlockIndex : Nat;
            ictc_admins: [Principal];
        };
        #unitNetValues: [Maker.UnitNetValue];
        #accountShares: [(AccountId, (Nat, Maker.ShareWeighted))];
        #accountVolUsed: [(AccountId, Nat)];
        #blockEvents: [(Nat, (Maker.Event, Timestamp))];
        #accountEvents: [(AccountId, [Nat])];
        #fallbacking_accounts: [(AccountId, Time)];
    };
};