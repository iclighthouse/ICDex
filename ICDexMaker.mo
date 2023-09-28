/**
 * Module     : ICDexMaker (Order Book Decentralized Market Maker)
 * Author     : ICLighthouse Team
 * Stability  : Experimental
 * Github     : https://github.com/iclighthouse/
 */

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

// record{name="Test-1";creator=blob " "; allow=variant{Public}; pair=principal "fpwot-xyaaa-aaaak-adp2a-cai"; unitSize=10000000;token0 = principal "fpwot-xyaaa-aaaak-adp2a-cai"; token0Std = variant{icrc1}; token1 = principal "fpwot-xyaaa-aaaak-adp2a-cai"; token1Std = variant{icrc1};lowerLimit = 0; upperLimit = 0; spreadRate = 0; threshold=0; volFactor=0} 
shared(installMsg) actor class ICDexMaker(initArgs: T.InitArgs) = this {
    type Timestamp = T.Timestamp;  //seconds
    type Address = T.Address;
    type AccountId = T.AccountId;  //Blob
    type Amount = T.Amount;
    type Sa = T.Sa;
    type Shares = T.Shares;
    type Nonce = T.Nonce;
    type Price = T.Price;
    type Data = T.Data;
    type Txid = T.Txid;
    type PoolBalance = T.PoolBalance;
    type UnitNetValue = T.UnitNetValue;
    type ShareWeighted = T.ShareWeighted;
    type TrieList<K, V> = T.TrieList<K, V>;

    private let version_: Text = "0.1";
    private let ns_: Nat = 1000000000;
    private let sa_zero : [Nat8] = [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0];
    private var name_: Text = initArgs.name;
    private stable var shareDecimals: Nat8 = 0; 
    private stable var shareUnitSize : Nat = 1;
    private stable var paused: Bool = false;
    private stable var owner: Principal = installMsg.caller;
    private stable var icdex_: Principal = installMsg.caller;
    private stable var creator: AccountId = initArgs.creator;
    private stable var visibility: {#Public; #Private} = initArgs.allow;
    private stable var initialized: Bool = false;
    private stable var sysTransactionLock: Bool = false;
    private stable var withdrawalFee: Nat = 100; // ppm x/1000000  (Fee: 10 * tokenFee + withdrawalFee * Value / 1000000)
    private stable var pairPrincipal: Principal = initArgs.pair;
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
    private stable var pairUnitSize: Nat = initArgs.unitSize;
    private stable var poolThreshold: Amount = initArgs.threshold; // token1
    private stable var volFactor: Nat = initArgs.volFactor;
    private stable var poolLocalBalance: PoolBalance = { balance0 = 0; balance1 = 0; ts = 0; };
    private stable var poolBalance: PoolBalance = { balance0 = 0; balance1 = 0; ts = 0; };
    private stable var poolShares: Nat = 0;
    private stable var poolShareWeighted: ShareWeighted = { shareTimeWeighted = 0; updateTime = 0; };
    private stable var unitNetValues: List.List<UnitNetValue> = List.nil<UnitNetValue>(); // per shareUnitSize shares
    private stable var accountShares: Trie.Trie<AccountId, (Nat, ShareWeighted)> = Trie.empty();
    private stable var accountVolUsed: Trie.Trie<AccountId, Nat> = Trie.empty();
    private stable var gridLowerLimit: Price = Nat.max(initArgs.lowerLimit, 1);
    private stable var gridUpperLimit: Price = initArgs.upperLimit;
    private stable var gridSpread: Nat = Nat.max(initArgs.spreadRate, 100); // ppm x/1000000
    private stable var gridSoid : ?Nat = null;
    private stable var gridOrderDeleted : Bool = false;
    // Events
    private stable var blockIndex : ICEvents.BlockHeight = 0;
    private stable var firstBlockIndex : ICEvents.BlockHeight = 0;
    private stable var blockEvents : ICEvents.ICEvents<T.Event> = Trie.empty(); 
    private stable var accountEvents : ICEvents.AccountEvents = Trie.empty(); 

    private func keyb(t: Blob) : Trie.Key<Blob> { return { key = t; hash = Blob.hash(t) }; };
    private func keyn(t: Nat) : Trie.Key<Nat> { return { key = t; hash = Tools.natHash(t) }; };
    private func keyt(t: Text) : Trie.Key<Text> { return { key = t; hash = Text.hash(t) }; };
    private func trieItems<K, V>(_trie: Trie.Trie<K,V>, _page: Nat, _size: Nat) : TrieList<K, V> {
        let length = Trie.size(_trie);
        if (_page < 1 or _size < 1){
            return {data = []; totalPage = 0; total = length; };
        };
        let offset = Nat.sub(_page, 1) * _size;
        var totalPage: Nat = length / _size;
        if (totalPage * _size < length) { totalPage += 1; };
        if (offset >= length){
            return {data = []; totalPage = totalPage; total = length; };
        };
        let end: Nat = offset + Nat.sub(_size, 1);
        var i: Nat = 0;
        var res: [(K, V)] = [];
        for ((k,v) in Trie.iter<K, V>(_trie)){
            if (i >= offset and i <= end){
                res := Tools.arrayAppend(res, [(k,v)]);
            };
            i += 1;
        };
        return {data = res; totalPage = totalPage; total = length; };
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
        let n: Int = _n;
        return Float.fromInt(n);
    };
    private func _floatToNat(_f: Float) : Nat{
        let i = Float.toInt(_f);
        assert(i >= 0);
        return Int.abs(i);
    };

    private func _onlyOwner(_caller: Principal) : Bool { //ict
        return _caller == owner or Principal.isController(_caller);
    }; 
    private func _onlyCreator(_a: AccountId) : Bool { //ict
        return _a == creator;
    }; 

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
                let sagaRes = await saga.run(_toid);
            }catch(e){
                throw Error.reject("430: ICTC error: "# Error.message(e)); 
            };
        };
    };
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
    private func _buildTask(_data: ?Data, _callee: Principal, _callType: SagaTM.CallType, _preTtid: [SagaTM.Ttid]) : SagaTM.PushTaskRequest{
        var cycles = 0;
        return {
            callee = _callee;
            callType = _callType;
            preTtid = _preTtid;
            attemptsMax = ?3;
            recallInterval = ?5000000000; // nanoseconds  5 seconds
            cycles = cycles;
            data = _data;
        };
    };
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
    // private stable var countICTCBlockings: Nat = 0;
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


    private func _getUnitNetValue(_ts: ?Timestamp, _tsAdjust: Bool): UnitNetValue{
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
    private func _putUnitNetValue(_token0: Nat, _token1: Nat, _price: Price, _shares: Nat) : (){
        unitNetValues := List.push({
            ts = _now(); 
            token0 = _token0; 
            token1 = _token1; 
            price = _price;
            shares = _shares;
        }, unitNetValues);
    };
    private func _updateUnitNetValue(_price: ?Price) : (){
        let unitValue0 = shareUnitSize * poolBalance.balance0 / poolShares;
        let unitValue1 = shareUnitSize * poolBalance.balance1 / poolShares;
        let price = Option.get(_price, _getUnitNetValue(null, false).price);
        _putUnitNetValue(unitValue0, unitValue1, price, poolShares);
    };
    private func _amountToShares(_value: Amount, _tokenSide: {#token0; #token1}) : Nat{
        switch(_tokenSide){
            case(#token0){
                return shareUnitSize * _value / _getUnitNetValue(null, false).token0;
            };
            case(#token1){
                return shareUnitSize * _value / _getUnitNetValue(null, false).token1;
            };
        };
    };
    private func _sharesToAmount(_shares: Shares) : {value0: Amount; value1: Amount}{
        return {
            value0 = _shares * _getUnitNetValue(null, false).token0 / shareUnitSize; 
            value1 = _shares * _getUnitNetValue(null, false).token1 / shareUnitSize;
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
    private func _calcuShareWeighted(_shareWeighted: ShareWeighted, _sheres: Shares) : ShareWeighted{
        var now = _now();
        if (now < _shareWeighted.updateTime){ now := _shareWeighted.updateTime; };
        return {
            shareTimeWeighted = _shareWeighted.shareTimeWeighted + _sheres * Nat.sub(now, _shareWeighted.updateTime);
            updateTime = now;
        };
    };
    private func _ictcCreateGridOrder(_toid: Nat): (ttid: Nat){
        let saga = _getSaga();
        let task = _buildTask(null, pairPrincipal, #StratOrder(#sto_createProOrder(#GridOrder({
                lowerLimit = gridLowerLimit;
                upperLimit = gridUpperLimit;
                spread = #Geom(gridSpread);
                amount = #Percent(null);
            }), null)), []);
        return saga.push(_toid, task, null, ?(func(_toName: Text, _ttid: SagaTM.Ttid, _task: SagaTM.Task, _result: SagaTM.TaskResult) : async (){
            switch(_result.0, _result.1, _result.2){
                case(#Done, ?(#StratOrder(#sto_createProOrder(soid))), _){ gridSoid := ?soid };
                case(_, _, _){};
            };
        }));
    };
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

    // Fetch data
    private func _fetchAccountVol(_accountId: AccountId) : async* ICDex.Vol{
        let pair: ICDex.Self = actor(Principal.toText(pairPrincipal));
        let userLiquidity = await pair.liquidity2(?_accountIdToHex(_accountId));
        return userLiquidity.vol;
    };
    private func _fetchPoolBalance() : async* (available0: Amount, available1: Amount){
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
            available0 := dexBalance.balance.token0.available;
            let balance1 = localBalance1 + dexBalance.balance.token1.locked + dexBalance.balance.token1.available;
            available1 := dexBalance.balance.token1.available;
            _updatePoolBalance(?#set(balance0), ?#set(balance1));
            if (not(initialized) and  balance0 > 0 and balance1 > 0){
                let unitValue0 = pairUnitSize;
                let shares = shareUnitSize * balance0 / unitValue0;
                let unitValue1 = shareUnitSize * balance1 / shares;
                // _updatePoolShares(#add(shares));
                _putUnitNetValue(unitValue0, unitValue1, price, shares);
                // let accountId = Option.get(_initAccountId, Tools.principalToAccountBlob(owner, null));
                // _updateAccountShares(accountId, #add(shares));
                initialized := true;
            }else if (poolShares > 0){
                // _updatePoolShares(#add(0));
                _updateUnitNetValue(?price);
            };
            ignore _putEvent(#updateUnitNetValue({ 
                pairBalance = ?dexBalance.balance;
                localBalance = poolLocalBalance;
                poolBalance = poolBalance;
                poolShares = poolShares;
                unitNetValue = _getUnitNetValue(null, false);
            }), null);
        }catch(e){
            sysTransactionLock := false;
            throw Error.reject("402: There was a conflict or error fetching the data, please try again later.");
        };
        return (available0, available1);
    };

    // core
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
        var valueFromDepositBalance: Nat = 0; // 1: funds from txAccount
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
        if (valueFromDepositBalance < _amount and _std == #drc20){
            let value = Nat.sub(_amount, valueFromDepositBalance) + _fee;
            ignore await* _drc20TransferFrom(_canisterId, _account, _depositAccount, value, null);
            depositBalance += value;
            if (depositBalance >= _fee){
                valueFromDepositBalance := Nat.min(Nat.sub(depositBalance, _fee), _amount);
            } else {
                valueFromDepositBalance := 0;
            };
        }else if (valueFromDepositBalance < _amount){
            throw Error.reject("405: Insufficient token balance!");
        };
        // depositAccount -> pool
        if (valueFromDepositBalance > 0){ 
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
            Time.now() < t.1 + 300 * ns_  // 5mins
        });
        fallbacking_accounts := List.push((_account, Time.now()), fallbacking_accounts);
    };
    private func _inFallbacking(_account: AccountId): Bool{
        return Option.isSome(List.find(fallbacking_accounts, func (t: (AccountId, Time.Time)): Bool{
            t.0 == _account and Time.now() < t.1 + 300 * ns_
        }));
    };
    private func _fallback(_icrc1Account: ICRC1.Account, instantly: Bool) : async* (value0: Amount, value1: Amount, toids: [Nat]){
        let sa_account = Tools.principalToAccountBlob(_icrc1Account.owner, _toSaNat8(_icrc1Account.subaccount));
        let icrc1Account = _icrc1Account;
        var value0: Nat = 0;
        var value1: Nat = 0;
        var toids: [Nat] = [];
        if (instantly or not(_inFallbacking(sa_account))){
            _putFallbacking(sa_account);
            try{
                value0 := await* _getBaseBalance(sa_account);
            }catch(e){
                throw Error.reject("420: internal call error: "# Error.message(e)); 
            };
            let saga = _getSaga();
            if (value0 > token0Fee){
                let toid = saga.create("fallback_1", #Backward, null, null);
                toids := Tools.arrayAppend(toids, [toid]);
                ignore _sendToken0(toid, sa_account, [], [icrc1Account], [value0], ?sa_account, null);
                saga.close(toid);
                await* _ictcSagaRun(toid, false);
            };
            
            try{
                value1 := await* _getQuoteBalance(sa_account);
            }catch(e){
                throw Error.reject("420: internal call error: "# Error.message(e)); 
            };
            if (value1 > token1Fee){
                let toid = saga.create("fallback_1", #Backward, null, null);
                toids := Tools.arrayAppend(toids, [toid]);
                ignore _sendToken1(toid, sa_account, [], [icrc1Account], [value1], ?sa_account, null);
                saga.close(toid);
                await* _ictcSagaRun(toid, false);
            };
        };
        return (value0, value1, toids);
    };
    private func _updateGridOrder(_accountId: AccountId, _token0: Amount, _token1: Amount, _updateMode: {#auto; #instantly}) : SagaTM.Toid{
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
            if (token0Std == #drc20){ // #approve : (DRC20.Spender, DRC20.Amount, ?DRC20.Nonce, ?DRC20.Sa, ?DRC20.Data);
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

    // SYS
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

    // public functions 
    public query func getDepositAccount(_account: Address) : async (ICRC1.Account, Address){ 
        let sa_account = _getAccountId(_account);
        return ({owner = Principal.fromActor(this); subaccount = ?sa_account }, _accountIdToHex(_getThisAccount(sa_account)));
    };
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
        let isInitAdd: Bool = not(initialized);
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
        if (_token0 <= token0Fee * 100 or _token1 <= token1Fee * 100){
            throw Error.reject("411: Unavailable amount.");
        };
        // deposit
        var depositedToken0: Amount = 0;
        var depositedToken1: Amount = 0;
        try{
            depositedToken0 := await* _deposit(#token0, _icrc1Account, _token0);
            ignore _putEvent(#deposit({account=_icrc1Account; token0=_token0; token1=0}), ?_account);
            depositedToken1 := await* _deposit(#token1, _icrc1Account, _token1);
            ignore _putEvent(#deposit({account=_icrc1Account; token0=0; token1=_token1}), ?_account);
        }catch(e){
            isException := true;
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
                _updatePoolLocalBalance(?#add(depositedToken0), null);
                _updatePoolLocalBalance(null, ?#add(depositedToken1));
            };
            try{
                ignore await* _fetchPoolBalance();
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
                let unitNetValue = _getUnitNetValue(null, false);
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
        // order
        if (addLiquidityToken0 > 0 and addLiquidityToken1 > 0){
            if (not(isInitAdd)){
                _updatePoolLocalBalance(?#add(addLiquidityToken0), null);
                _updatePoolLocalBalance(null, ?#add(addLiquidityToken1));
            };
            if (poolLocalBalance.balance0 > poolBalance.balance0 * 10 / 100 or poolLocalBalance.balance1 > poolBalance.balance1 * 10 / 100){ 
                let value0 = Nat.sub(poolLocalBalance.balance0, poolBalance.balance0 * 5 / 100);
                let value1 = Nat.sub(poolLocalBalance.balance1, poolBalance.balance1 * 5 / 100);
                let toid = _updateGridOrder(_account, value0, value1, #auto);
                toids := Tools.arrayAppend(toids, [toid]);
            };
        };
        // exception
        if (isException){
            await* _ictcSagaRun(0, false);
            ignore _putEvent(#add(#err({account = _icrc1Account; depositToken0 = depositedToken0; depositToken1 = depositedToken1; toids=toids})), ?_account);
            throw Error.reject(exceptMessage);
        };
        // fallback
        try{
            let r = await* _fallback(_icrc1Account, true);
            ignore _putEvent(#fallback({account = _icrc1Account; token0 = r.0; token1 = r.1; toids=r.2}), ?_account);
        }catch(e){};
        // run ictc
        await* _ictcSagaRun(0, false);
        // return 
        ignore _putEvent(#add(#ok({account = _icrc1Account; shares = sharesTest; token0 = addLiquidityToken0; token1 = addLiquidityToken1; toids=toids})), ?_account);
        return sharesTest;
    };
    public shared(msg) func remove(_shares: Amount, _sa: ?Sa) : async (value0: Amount, value1: Amount){
        if (paused or not(initialized)){
            throw Error.reject("400: The canister has been suspended."); 
        };
        if (sysTransactionLock){
            throw Error.reject("400: The system transaction is locked, please try again later."); 
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
        let saga = _getSaga();
        // get unit net value
        var available0InDex: Amount = 0;
        var available1InDex: Amount = 0;
        try{
            let (v0, v1) = await* _fetchPoolBalance();
            available0InDex := v0;
            available1InDex := v1;
        }catch(e){
            sysTransactionLock := false;
            throw Error.reject("413: Exception on fetching pool balance. ("# Error.message(e) #")"); 
        };
        if (sysTransactionLock){
            throw Error.reject("400: The system transaction is locked, please try again later."); 
        };
        // shares to amounts (Fee: 10 * tokenFee + 0.01% * Value)
        let values = _sharesToAmount(_shares);
        if (values.value0 > 10 * token0Fee + values.value0 * withdrawalFee / 1000000){
            resValue0 := Nat.sub(values.value0, 10 * token0Fee + values.value0 * withdrawalFee / 1000000);
        };
        if (values.value1 > 10 * token1Fee + values.value1 * withdrawalFee / 1000000){
            resValue1 := Nat.sub(values.value1, 10 * token1Fee + values.value1 * withdrawalFee / 1000000);
        };
        if ((resValue0 == 0 and resValue1 == 0) or values.value0 >= available0InDex or values.value1 >= available1InDex){
            throw Error.reject("414: The number of shares entered is not available."); 
        };
        // withdraw from Dex
        if (resValue0 + token0Fee > poolLocalBalance.balance0 or resValue1 + token1Fee > poolLocalBalance.balance1){
            sysTransactionLock := true;
            let pair: ICDex.Self = actor(Principal.toText(pairPrincipal));
            try{
                let value0 = if (resValue0 > 0){ ?Nat.max(resValue0 + token0Fee*2, poolBalance.balance0 * 5 / 100) }else{ null };
                let value1 = if (resValue1 > 0){ ?Nat.max(resValue1 + token1Fee*2, poolBalance.balance1 * 5 / 100) }else{ null };
                let (v0, v1) = await pair.withdraw(value0, value1, null);
                sysTransactionLock := false;
                _updatePoolLocalBalance(?#add(v0), ?#add(v1));
                ignore _putEvent(#dexWithdraw({token0 = v0; token1 = v1: Nat; toid=null}), null);
                if (v0 < resValue0 or v1 < resValue1){
                    throw Error.reject("Failed withdrawal");
                };
            }catch(e){
                sysTransactionLock := false;
                throw Error.reject(Error.message(e));
            };
        };
        sharesAvailable := _getAccountShares(_account).0;
        if ((resValue0 > 0 or resValue1 > 0) and _shares <= sharesAvailable){
            // burn account's shares
            _updateAccountShares(_account, #sub(_shares));
            _updatePoolShares(#sub(_shares));
            // ictc: transfer
            _updatePoolLocalBalance(?#sub(resValue0), ?#sub(resValue1));
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
            await* _ictcSagaRun(toid, false);
        }else if (resValue0 > 0 or resValue1 > 0){
            ignore _putEvent(#remove(#err({account = _icrc1Account; addPoolToken0 = resValue0; addPoolToken1 = resValue1; toid=null})), ?_account);
            resValue0 := 0;
            resValue1 := 0;
        };
        return (resValue0, resValue1);
    };

    public query func getAccountShares(_account: Address) : async (Shares, ShareWeighted){
        let accountId = _getAccountId(_account);
        return _getAccountShares(accountId);
    };
    public query func getAccountVolUsed(_account: Address): async Nat{ // token1
        let accountId = _getAccountId(_account);
        return switch(Trie.get(accountVolUsed, keyb(accountId), Blob.equal)){case(?(v)){ v }; case(_){ 0 }};
    };
    public query func getUnitNetValues() : async {shareUnitSize: Nat; data: [UnitNetValue]}{
        return {
            shareUnitSize = shareUnitSize; 
            data = Tools.slice(List.toArray(unitNetValues), 0, ?2000);
        };
    };
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
            latestUnitNetValue = _getUnitNetValue(null, false);
        };
    };
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
        let unitNetValue0 = shareUnitSize * balance0 / poolShares;
        let unitNetValue1 = shareUnitSize * balance1 / poolShares;
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
    public query func getOwner() : async Principal{  
        return owner;
    };
    public shared(msg) func changeOwner(_newOwner: Principal) : async Bool{ 
        assert(_onlyOwner(msg.caller));
        owner := _newOwner;
        ignore _putEvent(#changeOwner({newOwner = _newOwner}), ?Tools.principalToAccountBlob(msg.caller, null));
        return true;
    };
    public shared(msg) func config(_config: T.Config) : async Bool{
        assert(_onlyOwner(msg.caller));
        assert(not(sysTransactionLock));
        gridLowerLimit := Nat.max(Option.get(_config.lowerLimit, gridLowerLimit), 1);
        gridUpperLimit := Option.get(_config.upperLimit, gridUpperLimit);
        assert(gridUpperLimit > gridLowerLimit);
        gridSpread := Nat.max(Option.get(_config.spreadRatePpm, gridSpread), 100);
        poolThreshold := Option.get(_config.threshold, poolThreshold);
        volFactor := Option.get(_config.volFactor, volFactor);
        withdrawalFee := Option.get(_config.withdrawalFeePpm, withdrawalFee);
        ignore _putEvent(#config({setting = _config}), ?Tools.principalToAccountBlob(msg.caller, null));
        let toid = _updateGridOrder(Tools.principalToAccountBlob(msg.caller, null), 0, 0, #instantly);
        ignore _putEvent(#updateGridOrder({soid=gridSoid; toid=?toid}), ?Tools.principalToAccountBlob(msg.caller, null));
        await* _ictcSagaRun(toid, false);
        return true;
    };
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
    public shared(msg) func resetLocalBalance() : async PoolBalance{
        assert(_onlyOwner(msg.caller) and paused);
        let makerSubaccount = Blob.fromArray(sa_zero);
        let localBalance0 = await* _getBaseBalance(makerSubaccount);
        let localBalance1 = await* _getQuoteBalance(makerSubaccount);
        _updatePoolLocalBalance(?#set(localBalance0), ?#set(localBalance1));
        return poolLocalBalance;
    };
    public shared(msg) func dexWithdraw(_token0: Amount, _token1: Amount) : async (token0: Amount, token1: Amount){ 
        assert(_onlyOwner(msg.caller) and paused);
        let pair: ICDex.Self = actor(Principal.toText(pairPrincipal));
        let (v0, v1) = await pair.withdraw((if (_token0 > 0){ ?(_token0 + token0Fee) }else{ null }), (if (_token1 > 0){ ?(_token1 + token1Fee) }else{ null }), null);
        _updatePoolLocalBalance(?#add(v0), ?#add(v1));
        ignore _putEvent(#dexWithdraw({token0 = v0; token1 = v1: Nat; toid=null}), null);
        return (v0, v1);
    };
    public shared(msg) func dexDeposit(_token0: Amount, _token1: Amount) : async (token0: Amount, token1: Amount){ 
        assert(_onlyOwner(msg.caller) and paused);
        var token0: Amount = 0;
        var token1: Amount = 0;
        let makerAccount = Tools.principalToAccountBlob(Principal.fromActor(this), null);
        let dexDepositIcrc1Account = {owner = pairPrincipal; subaccount = ?makerAccount };
        let dexDepositAccount = Tools.principalToAccountBlob(pairPrincipal, ?Blob.toArray(makerAccount));
        let dexAccount = Tools.principalToAccountBlob(pairPrincipal, null);
        let saga = _getSaga();
        let toid = saga.create("dex_deposit", #Forward, null, null); 
        var ttidSize: Nat = 0;
        if (_token0 > token0Fee){
            _updatePoolLocalBalance(?#sub(_token0), null);
            if (token0Std == #drc20){ 
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
        await* _ictcSagaRun(toid, false);
        return (token0, token1);
    };
    public shared(msg) func deleteGridOrder() : async (){
        assert(_onlyOwner(msg.caller) and paused);
        if (not(gridOrderDeleted)){
            let saga = _getSaga();
            let toid = saga.create("delete_gridOrder", #Forward, null, null); 
            let ttid1 = _ictcUpdateGridOrder(toid, #Deleted);
            saga.close(toid);
            ignore _putEvent(#deleteGridOrder({soid=gridSoid; toid=?toid}), null);
            await* _ictcSagaRun(toid, false);
            gridOrderDeleted := true;
        };
    };
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
        await* _ictcSagaRun(toid, false);
        gridOrderDeleted := false;
    };
    public shared(msg) func cancelAllOrders() : async (){
        assert(_onlyOwner(msg.caller) and paused);
        let pair: ICDex.Self = actor(Principal.toText(pairPrincipal));
        await pair.cancelAll(#self_sa(null), null);
    };
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
    public query func get_event(_blockIndex: ICEvents.BlockHeight) : async ?(T.Event, ICEvents.Timestamp){
        return ICEvents.getEvent(blockEvents, _blockIndex);
    };
    public query func get_event_first_index() : async ICEvents.BlockHeight{
        return firstBlockIndex;
    };
    public query func get_events(_page: ?ICEvents.ListPage, _size: ?ICEvents.ListSize) : async ICEvents.TrieList<ICEvents.BlockHeight, (T.Event, ICEvents.Timestamp)>{
        let page = Option.get(_page, 1);
        let size = Option.get(_size, 100);
        return ICEvents.trieItems2<(T.Event, ICEvents.Timestamp)>(blockEvents, firstBlockIndex, blockIndex, page, size);
    };
    public query func get_account_events(_accountId: ICEvents.AccountId) : async [(T.Event, ICEvents.Timestamp)]{ //latest 1000 records
        return ICEvents.getAccountEvents<T.Event>(blockEvents, accountEvents, _accountId);
    };
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
    private stable var ictc_admins: [Principal] = [owner];
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
    public query func ictc_getAdmins() : async [Principal]{
        return ictc_admins;
    };
    public shared(msg) func ictc_addAdmin(_admin: Principal) : async (){
        assert(_onlyOwner(msg.caller) or _onlyIctcAdmin(msg.caller));
        if (Option.isNull(Array.find(ictc_admins, func (t: Principal): Bool{ t == _admin }))){
            ictc_admins := Tools.arrayAppend(ictc_admins, [_admin]);
        };
    };
    public shared(msg) func ictc_removeAdmin(_admin: Principal) : async (){
        assert(_onlyOwner(msg.caller) or _onlyIctcAdmin(msg.caller));
        ictc_admins := Array.filter(ictc_admins, func (t: Principal): Bool{ t != _admin });
    };

    // SagaTM Scan
    public query func ictc_TM() : async Text{
        return "Saga";
    };
    /// Saga
    public query func ictc_getTOCount() : async Nat{
        return _getSaga().count();
    };
    public query func ictc_getTO(_toid: SagaTM.Toid) : async ?SagaTM.Order{
        return _getSaga().getOrder(_toid);
    };
    public query func ictc_getTOs(_page: Nat, _size: Nat) : async {data: [(SagaTM.Toid, SagaTM.Order)]; totalPage: Nat; total: Nat}{
        return _getSaga().getOrders(_page, _size);
    };
    public query func ictc_getPool() : async {toPool: {total: Nat; items: [(SagaTM.Toid, ?SagaTM.Order)]}; ttPool: {total: Nat; items: [(SagaTM.Ttid, SagaTM.Task)]}}{
        let tos = _getSaga().getAliveOrders();
        let tts = _getSaga().getActuator().getTaskPool();
        return {
            toPool = { total = tos.size(); items = Tools.slice(tos, 0, ?255)};
            ttPool = { total = tts.size(); items = Tools.slice(tts, 0, ?255)};
        };
    };
    public query func ictc_getTOPool() : async [(SagaTM.Toid, ?SagaTM.Order)]{
        return _getSaga().getAliveOrders();
    };
    public query func ictc_getTT(_ttid: SagaTM.Ttid) : async ?SagaTM.TaskEvent{
        return _getSaga().getActuator().getTaskEvent(_ttid);
    };
    public query func ictc_getTTByTO(_toid: SagaTM.Toid) : async [SagaTM.TaskEvent]{
        return _getSaga().getTaskEvents(_toid);
    };
    public query func ictc_getTTs(_page: Nat, _size: Nat) : async {data: [(SagaTM.Ttid, SagaTM.TaskEvent)]; totalPage: Nat; total: Nat}{
        return _getSaga().getActuator().getTaskEvents(_page, _size);
    };
    public query func ictc_getTTPool() : async [(SagaTM.Ttid, SagaTM.Task)]{
        return _getSaga().getActuator().getTaskPool();
    };
    public query func ictc_getTTErrors(_page: Nat, _size: Nat) : async {data: [(Nat, SagaTM.ErrorLog)]; totalPage: Nat; total: Nat}{
        return _getSaga().getActuator().getErrorLogs(_page, _size);
    };
    public query func ictc_getCalleeStatus(_callee: Principal) : async ?SagaTM.CalleeStatus{
        return _getSaga().getActuator().calleeStatus(_callee);
    };

    // Transaction Governance
    public shared(msg) func ictc_clearLog(_expiration: ?Int, _delForced: Bool) : async (){ // Warning: Execute this method with caution
        assert(_onlyOwner(msg.caller));
        _getSaga().clear(_expiration, _delForced);
    };
    public shared(msg) func ictc_clearTTPool() : async (){ // Warning: Execute this method with caution
        assert(_onlyOwner(msg.caller));
        _getSaga().getActuator().clearTasks();
    };
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
    /// Try the task again
    public shared(msg) func ictc_redoTT(_toid: SagaTM.Toid, _ttid: SagaTM.Ttid) : async ?SagaTM.Ttid{
        // Warning: proceed with caution!
        assert(_onlyOwner(msg.caller) or _onlyIctcAdmin(msg.caller));
        let saga = _getSaga();
        let ttid = saga.redo(_toid, _ttid);
        await* _ictcSagaRun(_toid, true);
        return ttid;
    };
    /// set status of pending task
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
    /// set status of pending order
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
    /// Complete blocking order
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
    public query func drc207() : async DRC207.DRC207Support{
        return {
            monitorable_by_self = false;
            monitorable_by_blackhole = { allowed = true; canister_id = ?Principal.fromText("7hdtw-jqaaa-aaaak-aaccq-cai"); };
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
    // receive cycles
    public func wallet_receive(): async (){
        let amout = Cycles.available();
        let accepted = Cycles.accept(amout);
    };
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
    public shared(msg) func timerStart(_intervalSeconds: Nat): async (){
        assert(_onlyOwner(msg.caller));
        Timer.cancelTimer(timerId);
        timerId := Timer.recurringTimer(#seconds(_intervalSeconds), timerLoop);
    };
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
        timerId := Timer.recurringTimer(#seconds(60), timerLoop);
    };
    

};
