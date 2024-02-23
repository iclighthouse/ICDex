/**
 * Module     : CallType.mo
 * Author     : ICLighthouse Team
 * Stability  : Experimental
 * Description: Wrapping the methods used by the transaction. Modify this file to suit your needs.
                Notes: Upgrading canister after modifying CallType and Receipt types will cause the transaction log to be lost.
 * Refers     : https://github.com/iclighthouse/ICTC
 */

import Blob "mo:base/Blob";
import CF "mo:icl/CF";
import Cycles "mo:base/ExperimentalCycles";
import CyclesWallet "mo:icl/CyclesWallet";
import DRC20 "mo:icl/DRC20";
import DIP20 "mo:icl/DIP20";
import ICRC1 "./lib/ICRC1_old"; //*
import ICRC1New "mo:icl/ICRC1"; //*
import ICRC2 "./lib/ICRC1_old"; //*
import ICRC2New "mo:icl/ICRC1"; //*
import ICTokens "mo:icl/ICTokens";
import ICSwap "mo:icl/ICSwap";
import ICDex "mo:icl/ICDexTypes";
import Error "mo:base/Error";
import IC "mo:icl/IC";
import Ledger "mo:icl/Ledger";
import Option "mo:base/Option";
import Principal "mo:base/Principal";
import STO "mo:icl/STOTypes";

module {
    public let Version: Text = "2.0";
    public let ICCanister: Text = "aaaaa-aa";
    public let LedgerCanister: Text = "ryjl3-tyaaa-aaaaa-aaaba-cai";
    public let CFCanister: Text = "6nmrm-laaaa-aaaak-aacfq-cai";
    public type Status = {#Todo; #Doing; #Done; #Error; #Unknown; };
    public type Err = {code: Error.ErrorCode; message: Text; };
    public type TaskResult = (Status, ?Receipt, ?Err);
    public type LocalCall = (CallType, ?Receipt) -> async (TaskResult);
    public type BlobFill = {#AutoFill; #ManualFill: Blob; };
    public type NatFill = {#AutoFill; #ManualFill: Nat; };
    /// type ErrorCode = {
    ///   // Fatal error.
    ///   #system_fatal;
    ///   // Transient error.
    ///   #system_transient;
    ///   // Destination invalid.
    ///   #destination_invalid;
    ///   // Explicit reject by canister code.
    ///   #canister_reject;
    ///   // Canister trapped.
    ///   #canister_error;
    ///   // Error issuing inter-canister call (0.8.0)
    ///   #call_error : { err_code :  Nat32 }
    ///   // Future error code (with unrecognized numeric code)
    ///   #future : Nat32;
    ///     9901    No such actor.
    ///     9902    No such method.
    ///     9903    Return #err by canister code.
    ///     9904    Blocked by code.
    /// };

    // Re-wrapping of the canister's methods, parameters and return values.
    /// Wrap method names and parameters.
    public type CallType = { 
        #__skip;
        #__block;
        #DRC20: {
            #approve : (DRC20.Spender, DRC20.Amount, ?DRC20.Nonce, ?DRC20.Sa, ?DRC20.Data);
            #balanceOf : DRC20.Address;
            #executeTransfer : (BlobFill, DRC20.ExecuteType, ?DRC20.To, ?DRC20.Nonce, ?DRC20.Sa, ?DRC20.Data);
            #lockTransfer : (DRC20.To, DRC20.Amount, DRC20.Timeout, ?DRC20.Decider, ?DRC20.Nonce, ?DRC20.Sa, ?DRC20.Data);
            #lockTransferFrom : (DRC20.From, DRC20.To, DRC20.Amount, DRC20.Timeout, ?DRC20.Decider, ?DRC20.Nonce, ?DRC20.Sa, ?DRC20.Data );
            #transfer : (DRC20.To, DRC20.Amount, ?DRC20.Nonce, ?DRC20.Sa, ?DRC20.Data);
            #transferBatch : ([DRC20.To], [DRC20.Amount], ?DRC20.Nonce, ?DRC20.Sa, ?DRC20.Data);
            #transferFrom : (DRC20.From, DRC20.To, DRC20.Amount, ?DRC20.Nonce, ?DRC20.Sa, ?DRC20.Data);
            #txnRecord : BlobFill;
            #dropAccount: ?DRC20.Sa;
        }; 
        #ICRC1: { // ICRC1 -> ICRC1New result  (Old version ICRC1)
            #icrc1_transfer : (ICRC1.TransferArgs);
            #icrc1_balance_of : (ICRC1.Account);
        };
        #ICRC1New: { // ICRC1New -> ICRC1New result
            #icrc1_transfer : (ICRC1New.TransferArgs);
            #icrc1_balance_of : (ICRC1New.Account);
        };
        // #ICRC2: {  // ICRC2 -> Unavailable   (Old version ICRC2)
        //     #icrc2_approve : (ICRC2.ApproveArgs); //*
        //     #icrc2_transfer_from : (ICRC2.TransferFromArgs); //*
        // };
        // #ICRC2New: { // ICRC2New -> ICRC2New result
        //     #icrc2_approve : (ICRC2New.ApproveArgs);
        //     #icrc2_transfer_from : (ICRC2New.TransferFromArgs);
        // };
        #ICDex: {
            #deposit : (_token: {#token0; #token1}, _value: Nat, _sa: ?ICDex.Sa);
            #depositFallback : (_sa: ?ICDex.Sa);
            #withdraw : (_value0: ?ICDex.Amount, _value1: ?ICDex.Amount, _sa: ?ICDex.Sa);
        };
        #StratOrder: {
            #sto_cancelPendingOrders : (_soid: STO.Soid, _sa: ?STO.Sa);
            #sto_createProOrder : (_arg: {
                #GridOrder: {
                    lowerLimit: STO.Price;
                    upperLimit: STO.Price;
                    spread: {#Arith: STO.Price; #Geom: STO.Ppm };
                    amount: {#Token0: Nat; #Token1: Nat; #Percent: ?STO.Ppm };
                };
            }, _sa: ?STO.Sa);
            #sto_updateProOrder : (_soid: STO.Soid, _arg: {
                #GridOrder: {
                    lowerLimit: ?STO.Price;
                    upperLimit: ?STO.Price;
                    spread: ?{#Arith: STO.Price; #Geom: STO.Ppm };
                    amount: ?{#Token0: Nat; #Token1: Nat; #Percent: ?STO.Ppm };
                    status: ?STO.STStatus;
                };
            }, _sa: ?STO.Sa);
        };
        #This: {
            // #dip20Send : (_a: Blob, _value: Nat);
            // #dip20SendComp : (_a: Blob, _p: Principal, _value: Nat);
            // for ICDexPair
            #batchTransfer: ([(_act: {#add; #sub}, _account: Blob, _token: {#token0; #token1}, _amount: {#locked: Nat; #available: Nat})]);
            // for ICDexMaker
            #dexDepositFallback: (_pair: Principal, _sa: ?[Nat8]);
            #updatePoolLocalBalance: (_token0: ?{#add: Nat; #sub: Nat; #set: Nat}, _token1: ?{#add: Nat; #sub: Nat; #set: Nat});
        };
    };

    /// Wrap return values of methods.
    public type Receipt = { 
        #__skip;
        #__block;
        #DRC20: {
            #approve : DRC20.TxnResult;
            #balanceOf : DRC20.Amount;
            #executeTransfer : DRC20.TxnResult;
            #lockTransfer : DRC20.TxnResult;
            #lockTransferFrom : DRC20.TxnResult;
            #transfer : DRC20.TxnResult;
            #transferBatch : [DRC20.TxnResult];
            #transferFrom : DRC20.TxnResult;
            #txnRecord : ?DRC20.TxnRecord;
            #dropAccount;
        }; 
        #ICRC1: {
            #icrc1_transfer : { #Ok: Nat; #Err: ICRC1.TransferError; }; //*
            #icrc1_balance_of : Nat;
        };
        #ICRC1New: {
            #icrc1_transfer : { #Ok: Nat; #Err: ICRC1New.TransferError; };
            #icrc1_balance_of : Nat;
        };
        // #ICRC2: {
        //     #icrc2_approve : ({ #Ok : Nat; #Err : ICRC2.ApproveError });
        //     #icrc2_transfer_from : ({ #Ok : Nat; #Err : ICRC2.TransferFromError });
        // };
        // #ICRC2New: {
        //     #icrc2_approve : ({ #Ok : Nat; #Err : ICRC2New.ApproveError });
        //     #icrc2_transfer_from : ({ #Ok : Nat; #Err : ICRC2New.TransferFromError });
        // };
        #ICDex: {
            #deposit : ();
            #depositFallback : (value0: Nat, value1: Nat);
            #withdraw : (value0: Nat, value1: Nat);
        };
        #StratOrder: {
            #sto_cancelPendingOrders : ();
            #sto_createProOrder : STO.Soid;
            #sto_updateProOrder : STO.Soid;
        };
        #This: {
            // #dip20Send : ();
            // #dip20SendComp : ();
            #batchTransfer: ([{token0:{locked: Nat; available: Nat}; token1:{locked: Nat; available: Nat}}]);
            #dexDepositFallback: (value0: Nat, value1: Nat);
            #updatePoolLocalBalance: ({ balance0: Nat; balance1: Nat; ts: Nat; });
        };
    };

    public type Domain = {
        #Local : LocalCall;
        #Canister : (Principal, Nat); // (Canister-id, AddCycles)
    };
    private func _getTxid(txid: BlobFill, receipt: ?Receipt) : Blob{
        var txid_ = Blob.fromArray([]);
        switch(txid){
            case(#AutoFill){
                switch(receipt){
                    case(?(#DRC20(#lockTransfer(#ok(v))))){ txid_ := v };
                    case(?(#DRC20(#lockTransferFrom(#ok(v))))){ txid_ := v };
                    case(?(#DRC20(#transfer(#ok(v))))){ txid_ := v };
                    case(?(#DRC20(#transferFrom(#ok(v))))){ txid_ := v };
                    case(?(#DRC20(#executeTransfer(#ok(v))))){ txid_ := v };
                    case(?(#DRC20(#approve(#ok(v))))){ txid_ := v };
                    // case(?(#ICDex(#trade(#ok(v))))){ txid_ := v.txid };
                    // case(?(#ICDex(#tradeMKT(#ok(v))))){ txid_ := v.txid };
                    case(_){};
                };
            };
            case(#ManualFill(v)){ txid_ := v };
        };
        return txid_;
    };
    private func _rebuildICRC1TransferArgs(_callType: CallType): CallType{
        switch(_callType){
            case(#ICRC1(#icrc1_transfer(args))){
                var from_subaccount = args.from_subaccount;
                var to_subaccount = args.to.subaccount;
                switch(to_subaccount){
                    case(?(_sub)){
                        if (Blob.toArray(_sub).size() == 0) {
                            to_subaccount := null;
                        };
                    };
                    case(_){};
                };
                switch(from_subaccount){
                    case(?(_sub)){
                        if (Blob.toArray(_sub).size() == 0) {
                            from_subaccount := null;
                        };
                    };
                    case(_){};
                };
                return #ICRC1(#icrc1_transfer({
                    from_subaccount = from_subaccount;
                    to = {owner = args.to.owner; subaccount = to_subaccount };
                    amount = args.amount;
                    fee = args.fee;
                    memo = args.memo;
                    created_at_time = args.created_at_time;
                }: ICRC1.TransferArgs));
            };
            case(_){
                return _callType;
            };
        };
    };

    /// Wrap the calling function
    public func call(_args: CallType, _domain: Domain, _receipt: ?Receipt) : async* TaskResult{
        switch(_domain){
            // Local Task Call
            case(#Local(localCall)){
                switch(_args){
                    case(#__skip){ return (#Done, ?#__skip, null); };
                    case(#__block){ return (#Error, ?#__block, ?{code=#future(9904); message="Blocked by code."; }); };
                    case(#This(method)){
                        try{
                            return await localCall(_args, _receipt);
                        } catch (e){
                            return (#Error, null, ?{code=Error.code(e); message=Error.message(e); });
                        };
                    };
                    case(_){ return (#Error, null, ?{code=#future(9901); message="No such actor."; }); };
                };
            };
            // Cross-Canister Task Call
            case(#Canister((callee, cycles))){
                var calleeId = Principal.toText(callee);
                let args = _rebuildICRC1TransferArgs(_args);
                switch(args){
                    case(#__skip){ return (#Done, ?#__skip, null); };
                    case(#__block){ return (#Error, ?#__block, ?{code=#future(9904); message="Blocked by code."; }); };
                    case(#DRC20(method)){
                        let token: DRC20.Self = actor(calleeId);
                        if (cycles > 0){ Cycles.add(cycles); };
                        switch(method){
                            case(#balanceOf(user)){
                                var result: Nat = 0; // Receipt
                                try{
                                    // do
                                    result := await token.drc20_balanceOf(user);
                                    // check & return
                                    return (#Done, ?#DRC20(#balanceOf(result)), null);
                                } catch (e){
                                    return (#Error, null, ?{code=Error.code(e); message=Error.message(e); });
                                };
                            };
                            case(#approve(spender, amount, nonce, sa, data)){
                                var result: DRC20.TxnResult = #err({code=#UndefinedError; message="No call."}); // Receipt
                                try{
                                    // do
                                    result := await token.drc20_approve(spender, amount, nonce, sa, data);
                                    // check & return
                                    switch(result){
                                        case(#ok(txid)){ return (#Done, ?#DRC20(#approve(result)), null); };
                                        case(#err(e)){ return (#Error, ?#DRC20(#approve(result)), ?{code=#future(9903); message=e.message; }); };
                                    };
                                } catch (e){
                                    return (#Error, null, ?{code=Error.code(e); message=Error.message(e); });
                                };
                            };
                            case(#transfer(to, amount, nonce, sa, data)){
                                var result: DRC20.TxnResult = #err({code=#UndefinedError; message="No call."}); // Receipt
                                try{
                                    // do
                                    result := await token.drc20_transfer(to, amount, nonce, sa, data);
                                    // check & return
                                    switch(result){
                                        case(#ok(txid)){ return (#Done, ?#DRC20(#transfer(result)), null); };
                                        case(#err(e)){ return (#Error, ?#DRC20(#transfer(result)), ?{code=#future(9903); message=e.message; }); };
                                    };
                                } catch (e){
                                    return (#Error, null, ?{code=Error.code(e); message=Error.message(e); });
                                };
                            };
                            case(#transferBatch(to, amount, nonce, sa, data)){
                                var results: [DRC20.TxnResult] = []; // Receipt
                                try{
                                    // do
                                    results := await token.drc20_transferBatch(to, amount, nonce, sa, data);
                                    // check & return
                                    var isSuccess : Bool = true;
                                    for (result in results.vals()){
                                        switch(result){
                                            case(#ok(txid)){};
                                            case(#err(e)){ isSuccess := false; };
                                        };
                                    };
                                    if (isSuccess){
                                        return (#Done, ?#DRC20(#transferBatch(results)), null);
                                    }else{
                                        return (#Error, ?#DRC20(#transferBatch(results)), ?{code=#future(9903); message="Batch transaction error."; });
                                    };
                                } catch (e){
                                    return (#Error, null, ?{code=Error.code(e); message=Error.message(e); });
                                };
                            };
                            case(#transferFrom(from, to, amount, nonce, sa, data)){
                                var result: DRC20.TxnResult = #err({code=#UndefinedError; message="No call."}); // Receipt
                                try{
                                    // do
                                    result := await token.drc20_transferFrom(from, to, amount, nonce, sa, data);
                                    // check & return
                                    switch(result){
                                        case(#ok(txid)){ return (#Done, ?#DRC20(#transferFrom(result)), null); };
                                        case(#err(e)){ return (#Error, ?#DRC20(#transferFrom(result)), ?{code=#future(9903); message=e.message; }); };
                                    };
                                } catch (e){
                                    return (#Error, null, ?{code=Error.code(e); message=Error.message(e); });
                                };
                            };
                            case(#lockTransfer(to, amount, timeout, decider, nonce, sa, data)){
                                var result: DRC20.TxnResult = #err({code=#UndefinedError; message="No call."}); // Receipt
                                try{
                                    // do
                                    result := await token.drc20_lockTransfer(to, amount, timeout, decider, nonce, sa, data);
                                    // check & return
                                    switch(result){
                                        case(#ok(txid)){ return (#Done, ?#DRC20(#lockTransfer(result)), null); };
                                        case(#err(e)){ return (#Error, ?#DRC20(#lockTransfer(result)), ?{code=#future(9903); message=e.message; }); };
                                    };
                                } catch (e){
                                    return (#Error, null, ?{code=Error.code(e); message=Error.message(e); });
                                };
                            };
                            case(#lockTransferFrom(from, to, amount, timeout, decider, nonce, sa, data)){
                                var result: DRC20.TxnResult = #err({code=#UndefinedError; message="No call."}); // Receipt
                                try{
                                    // do
                                    result := await token.drc20_lockTransferFrom(from, to, amount, timeout, decider, nonce, sa, data);
                                    // check & return
                                    switch(result){
                                        case(#ok(txid)){ return (#Done, ?#DRC20(#lockTransferFrom(result)), null); };
                                        case(#err(e)){ return (#Error, ?#DRC20(#lockTransferFrom(result)), ?{code=#future(9903); message=e.message; }); };
                                    };
                                } catch (e){
                                    return (#Error, null, ?{code=Error.code(e); message=Error.message(e); });
                                };
                            };
                            case(#executeTransfer(txid, executeType, to, nonce, sa, data)){
                                let txid_ = _getTxid(txid, _receipt);
                                var result: DRC20.TxnResult = #err({code=#UndefinedError; message="No call."}); // Receipt
                                try{
                                    // do
                                    result := await token.drc20_executeTransfer(txid_, executeType, to, nonce, sa, data);
                                    // check & return
                                    switch(result){
                                        case(#ok(txid)){ return (#Done, ?#DRC20(#executeTransfer(result)), null); };
                                        case(#err(e)){ return (#Error, ?#DRC20(#executeTransfer(result)), ?{code=#future(9903); message=e.message; }); };
                                    };
                                } catch (e){
                                    return (#Error, null, ?{code=Error.code(e); message=Error.message(e); });
                                };
                            };
                            case(#txnRecord(txid)){
                                let txid_ = _getTxid(txid, _receipt);
                                var result: ?DRC20.TxnRecord = null; // Receipt
                                try{
                                    // do
                                    result := await token.drc20_txnRecord(txid_);
                                    // check & return
                                    return (#Done, ?#DRC20(#txnRecord(result)), null);
                                } catch (e){
                                    return (#Error, null, ?{code=Error.code(e); message=Error.message(e); });
                                };
                            };
                            case(#dropAccount(_sa)){
                                try{
                                    // do
                                    let f = token.drc20_dropAccount(_sa);
                                    // check & return
                                    return (#Done, ?#DRC20(#dropAccount), null);
                                } catch (e){
                                    return (#Error, null, ?{code=Error.code(e); message=Error.message(e); });
                                };
                            };
                            //case(_){ return (#Error, null, ?{code=#future(9902); message="No such method."; });};
                        };
                    };
                    case(#ICRC1(method)){ // For forward compatibility
                        let token: ICRC1New.Self = actor(calleeId);
                        if (cycles > 0){ Cycles.add(cycles); };
                        switch(method){
                            case(#icrc1_balance_of(user)){
                                var result: Nat = 0; // Receipt
                                try{
                                    // do
                                    result := await token.icrc1_balance_of(user);
                                    // check & return
                                    return (#Done, ?#ICRC1New(#icrc1_balance_of(result)), null);
                                } catch (e){
                                    return (#Error, null, ?{code=Error.code(e); message=Error.message(e); });
                                };
                            };
                            case(#icrc1_transfer(args)){
                                var result: { #Ok: Nat; #Err: ICRC1New.TransferError; } = #Err(#TemporarilyUnavailable); // Receipt
                                try{
                                    // do
                                    result := await token.icrc1_transfer(args);
                                    // check & return
                                    switch(result){
                                        case(#Ok(id)){ return (#Done, ?#ICRC1New(#icrc1_transfer(result)), null); };
                                        case(#Err(e)){ return (#Error, ?#ICRC1New(#icrc1_transfer(result)), ?{code=#future(9903); message="ICRC1 token Err."; }); };
                                    };
                                } catch (e){
                                    return (#Error, null, ?{code=Error.code(e); message=Error.message(e); });
                                };
                            };
                            //case(_){ return (#Error, null, ?{code=#future(9902); message="No such method."; });};
                        };
                    };
                    case(#ICRC1New(method)){ 
                        let token: ICRC1New.Self = actor(calleeId);
                        if (cycles > 0){ Cycles.add(cycles); };
                        switch(method){
                            case(#icrc1_balance_of(user)){
                                var result: Nat = 0; // Receipt
                                try{
                                    // do
                                    result := await token.icrc1_balance_of(user);
                                    // check & return
                                    return (#Done, ?#ICRC1New(#icrc1_balance_of(result)), null);
                                } catch (e){
                                    return (#Error, null, ?{code=Error.code(e); message=Error.message(e); });
                                };
                            };
                            case(#icrc1_transfer(args)){
                                var result: { #Ok: Nat; #Err: ICRC1New.TransferError; } = #Err(#TemporarilyUnavailable); // Receipt
                                try{
                                    // do
                                    result := await token.icrc1_transfer(args);
                                    // check & return
                                    switch(result){
                                        case(#Ok(id)){ return (#Done, ?#ICRC1New(#icrc1_transfer(result)), null); };
                                        case(#Err(e)){ return (#Error, ?#ICRC1New(#icrc1_transfer(result)), ?{code=#future(9903); message="ICRC1 token Err."; }); };
                                    };
                                } catch (e){
                                    return (#Error, null, ?{code=Error.code(e); message=Error.message(e); });
                                };
                            };
                            //case(_){ return (#Error, null, ?{code=#future(9902); message="No such method."; });};
                        };
                    };
                    // case(#ICRC2New(method)){
                    //     let token: ICRC2New.Self = actor(calleeId);
                    //     if (cycles > 0){ Cycles.add(cycles); };
                    //     switch(method){
                    //         case(#icrc2_approve(args)){
                    //             var result: { #Ok: Nat; #Err: ICRC2New.ApproveError; } = #Err(#TemporarilyUnavailable); // Receipt
                    //             try{
                    //                 // do
                    //                 result := await token.icrc2_approve(args);
                    //                 // check & return
                    //                 switch(result){
                    //                     case(#Ok(id)){ return (#Done, ?#ICRC2New(#icrc2_approve(result)), null); };
                    //                     case(#Err(e)){ return (#Error, ?#ICRC2New(#icrc2_approve(result)), ?{code=#future(9903); message="ICRC2 token Err."; }); };
                    //                 };
                    //             } catch (e){
                    //                 return (#Error, null, ?{code=Error.code(e); message=Error.message(e); });
                    //             };
                    //         };
                    //         case(#icrc2_transfer_from(args)){
                    //             var result: { #Ok: Nat; #Err: ICRC2New.TransferFromError; } = #Err(#TemporarilyUnavailable); // Receipt
                    //             try{
                    //                 // do
                    //                 result := await token.icrc2_transfer_from(args);
                    //                 // check & return
                    //                 switch(result){
                    //                     case(#Ok(id)){ return (#Done, ?#ICRC2New(#icrc2_transfer_from(result)), null); };
                    //                     case(#Err(e)){ return (#Error, ?#ICRC2New(#icrc2_transfer_from(result)), ?{code=#future(9903); message="ICRC2 token Err."; }); };
                    //                 };
                    //             } catch (e){
                    //                 return (#Error, null, ?{code=Error.code(e); message=Error.message(e); });
                    //             };
                    //         };
                    //     };
                    // };
                    case(#ICDex(method)){
                        let dex: ICDex.Self = actor(calleeId);
                        if (cycles > 0){ Cycles.add(cycles); };
                        switch(method){
                            case(#deposit(_token, _value, _sa)){
                                try{
                                    // do
                                    let result = await dex.deposit(_token, _value, _sa);
                                    // check & return
                                    return (#Done, ?#ICDex(#deposit(result)), null);
                                } catch (e){
                                    return (#Error, null, ?{code=Error.code(e); message=Error.message(e); });
                                };
                            };
                            case(#depositFallback(_sa)){
                                var result: (Nat, Nat) = (0, 0); // Receipt
                                try{
                                    // do
                                    result := await dex.depositFallback(_sa);
                                    // check & return
                                    return (#Done, ?#ICDex(#depositFallback(result)), null);
                                } catch (e){
                                    return (#Error, null, ?{code=Error.code(e); message=Error.message(e); });
                                };
                            };
                            case(#withdraw(_value0, _value1, _sa)){
                                var result: (Nat, Nat) = (0, 0); // Receipt
                                try{
                                    // do
                                    result := await dex.withdraw(_value0, _value1, _sa);
                                    // check & return
                                    return (#Done, ?#ICDex(#withdraw(result)), null);
                                } catch (e){
                                    return (#Error, null, ?{code=Error.code(e); message=Error.message(e); });
                                };
                            };
                        };
                    };
                    case(#StratOrder(method)){
                        let sto: STO.Self = actor(calleeId);
                        if (cycles > 0){ Cycles.add(cycles); };
                        switch(method){
                            case(#sto_cancelPendingOrders(_soid, _sa)){
                                try{
                                    // do
                                    let result = await sto.sto_cancelPendingOrders(_soid, _sa);
                                    // check & return
                                    return (#Done, ?#StratOrder(#sto_cancelPendingOrders(result)), null);
                                } catch (e){
                                    return (#Error, null, ?{code=Error.code(e); message=Error.message(e); });
                                };
                            };
                            case(#sto_createProOrder(_arg, _sa)){
                                try{
                                    var result: STO.Soid = 0;
                                    // do
                                    result := await sto.sto_createProOrder(_arg, _sa);
                                    // check & return
                                    return (#Done, ?#StratOrder(#sto_createProOrder(result)), null);
                                } catch (e){
                                    return (#Error, null, ?{code=Error.code(e); message=Error.message(e); });
                                };
                            };
                            case(#sto_updateProOrder(_soid, _arg, _sa)){
                                try{
                                    var result: STO.Soid = 0;
                                    // do
                                    result := await sto.sto_updateProOrder(_soid, _arg, _sa);
                                    // check & return
                                    return (#Done, ?#StratOrder(#sto_updateProOrder(result)), null);
                                } catch (e){
                                    return (#Error, null, ?{code=Error.code(e); message=Error.message(e); });
                                };
                            };
                        };
                    };
                    case(_){ return (#Error, null, ?{code=#future(9901); message="No such actor."; });};
                };
            };
        };
        
    };

};