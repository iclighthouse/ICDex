/**
 * Module     : StrategyOrder.mo
 * Author     : ICLighthouse Team
 * Stability  : Experimental
 * Description: Strategy for trading: Professional orders and Stop loss orders.
 * Refers     : https://github.com/iclighthouse/ICDex/
 */
///
/// StrategyOrder is a strategy executor that is hooked into the _trade() function of a trading pair. Strategy Order is divided 
/// into stop-loss-orders and pro-orders, and pro-orders include Grid, Iceberg, VWAP, and TWAP orders. The StrategyOrder module 
/// is a library of functions that provide basic functionality of Strategy Order.

import Nat "mo:base/Nat";
import Nat64 "mo:base/Nat64";
import Int "mo:base/Int";
import Option "mo:base/Option";
import Array "mo:base/Array";
import Time "mo:base/Time";
import Hash "mo:base/Hash";
import List "mo:base/List";
import Trie "mo:base/Trie";
import Blob "mo:base/Blob";
import Binary "mo:icl/Binary";
import OB "mo:icl/OrderBook";
import STO "mo:icl/STOTypes";
import Pair "mo:icl/ICDexTypes";
import Tools "mo:icl/Tools";

module {
    public type Txid = STO.Txid; // Blob
    public type AccountId = STO.AccountId; // Blob
    public type ICRC1Account = STO.ICRC1Account;
    public type Nonce = STO.Nonce; // Nat
    public type Amount = STO.Amount; // Nat
    public type Timestamp = STO.Timestamp; // seconds
    public type Price = STO.Price; // How much token1 (smallest units) are needed to purchase UNIT_SIZE token0 (smallest units).
    public type OrderSide = OB.OrderSide; // {#Buy; #Sell}
    public type Soid = STO.Soid; // Nat
    public type Ppm = STO.Ppm; //  ppm. 1/1000000.
    public type STOrderRecords = STO.STOrderRecords; // Strategies
    public type UserProOrderList = STO.UserProOrderList; // Index relationship table between users and pro-orders. 
    public type ActiveProOrderList = STO.ActiveProOrderList; // Currently active pro-orders. 
    public type UserStopLossOrderList = STO.UserStopLossOrderList; // Index relationship table between users and stop-loss-orders.
    public type ActiveStopLossOrderList = STO.ActiveStopLossOrderList; // Currently active stop-loss-orders. 
    public type STOrderTxids = STO.STOrderTxids; // Index relationship table between trade orders (txid) and strategies (soid).

    public type Setting = STO.Setting;
    // type STOrder = { // Data structure of a strategy order
    //     soid: Soid; // index
    //     icrc1Account: ICRC1Account; // owner
    //     stType: STType; // {#StopLossOrder; #GridOrder; #IcebergOrder; #VWAP; #TWAP }; 
    //     strategy: STStrategy; // Strategy configuration and intermediate states.
    //     stats: STStats; // Strategy statistics.
    //     status: STStatus; // Strategy status.
    //     initTime: Timestamp; // Timestamp at initialization.
    //     triggerTime: Timestamp; // Timestamp of latest trigger.
    //     pendingOrders: { buy: [(?Txid, Price, quantity: Nat)]; sell: [(?Txid, Price, quantity: Nat)] }; // Trade orders that are in the process of being placed or have already been placed.
    // };
    public type STOrder = STO.STOrder; // Data structure of a strategy order
    public type STType = STO.STType; // {#StopLossOrder; #GridOrder; #IcebergOrder; #VWAP; #TWAP }; 
    public type STStrategy = STO.STStrategy;
    public type STStats = STO.STStats;
    public type STStatus = STO.STStatus;
    // StopLossOrder
    public type StopLossOrder = STO.StopLossOrder; // stop-loss-order
    public type Condition = STO.Condition;
    public type TriggeredOrder = STO.TriggeredOrder;
    // GridOrder
    public type GridOrderSetting = STO.GridOrderSetting;
    public type GridSetting = STO.GridSetting;
    public type GridPrices = STO.GridPrices;
    public type GridOrder = STO.GridOrder;
    // IcebergOrder
    public type IcebergOrderSetting = STO.IcebergOrderSetting;
    public type IcebergOrder = STO.IcebergOrder;
    // VWAP
    public type VWAPSetting = STO.VWAPSetting;
    public type VWAP = STO.VWAP;
    // TWAP
    public type TWAPSetting = STO.TWAPSetting;
    public type TWAP = STO.TWAP;

    private func _now() : Timestamp{
        return Int.abs(Time.now() / 1000000000);
    };
    private func _toSaNat8(_sa: ?Blob) : ?[Nat8]{
        let sa_zero : [Nat8] = [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0];
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

    // Pushes a new item into the `(Soid, Price)` list  according to the `Price` sorting rule.
    private func _pushSortedSTOList(_list: List.List<(Soid, Price)>, _order: {#Asc; #Desc}, _item: (Soid, Price)) : List.List<(Soid, Price)>{
        var list = _list;
        var temp : List.List<(Soid, Price)> = null;
        func push(list: List.List<(Soid, Price)>) : List.List<(Soid, Price)>{
            switch(List.pop(list), _order){
                case((?(soid, price), l), #Desc){
                    if (_item.1 > price){
                        return List.push(_item, list);
                    }else{
                        temp := List.push((soid, price), temp);
                        return push(l);
                    };
                };
                case((?(soid, price), l), #Asc){
                    if (_item.1 < price){
                        return List.push(_item, list);
                    }else{
                        temp := List.push((soid, price), temp);
                        return push(l);
                    };
                };
                case(_, _){
                    return List.push(_item, list);
                };
            };
        };
        list := push(list);
        for(item in List.toArray(temp).vals()){
            list := List.push(item, list);
        };
        return list;
    };

    // Calculate the hash value of Nat.
    private func natHash(n : Nat) : Hash.Hash{
        return Blob.hash(Blob.fromArray(Binary.BigEndian.fromNat64(Nat64.fromIntWrap(n))));
    };
    private func keyn(t: Nat) : Trie.Key<Nat> { return { key = t; hash = natHash(t) }; };
    private func keyb(t: Blob) : Trie.Key<Blob> { return { key = t; hash = Blob.hash(t) }; };

    /// Returns the type of a strategy. 
    public func getSTType(_strategy: STStrategy) : STType{ // {#StopLossOrder; #GridOrder; #IcebergOrder; #VWAP; #TWAP }; 
        switch(_strategy){
            case(#GridOrder(v)){ return #GridOrder };
            case(#StopLossOrder(v)){ return #StopLossOrder };
            case(#IcebergOrder(v)){ return #IcebergOrder };
            case(#VWAP(v)){ return #VWAP };
            case(#TWAP(v)){ return #TWAP };
        };
    };

    /// GridOrder: Calculate grid spread based on spread configuration `_spread`.  
    /// #Arith: arithmetic; #Geom: geometric (1 ppm means 1/1_000_000).
    public func getSpread(_side: {#upward; #downward}, _spread: {#Arith: Price; #Geom: Ppm }, _gridPrice: Price) : Price{
        switch(_side){
            case(#upward){
                return switch(_spread){ case(#Arith(v)){ v }; case(#Geom(ppm)){ _gridPrice * ppm / 1000000 } };
            };
            case(#downward){
                return switch(_spread){ case(#Arith(v)){ v }; case(#Geom(ppm)){ (_gridPrice - (_gridPrice * 1000000 / (1000000 + ppm))) } };
            };
        };
    };

    /// GridOrder: Default grid order amount factor, initialized when the strategy is created. `ppmFactor = 1000000 * 1/n * (n ** (1/10))`, 
    /// Where n is `(n1 + n2) / 2`, and n1, n2 is between 2 and 200. n1 is the number of grids between the latest price and the lowerLimit, 
    /// and n2 is the number of grids between the latest price and the upperLimit.
    public func getPpmFactor(_initPrice: Price, _spread: {#Arith: Price; #Geom: Ppm }, _lowerPrice: Price, _upperPrice: Price) : Ppm{
        var price : Price = 0;
        var spread: Price = 0;
        var gridCount_buy: Nat = 0;
        var gridCount_sell: Nat = 0;
        price := _initPrice;
        spread := getSpread(#upward, _spread, price);
        while(price + spread <= _upperPrice and gridCount_sell < 200){
            gridCount_sell += 1;
            price := price + spread;
            spread := getSpread(#upward, _spread, price);
        };
        if (gridCount_sell < 2) { gridCount_sell := 2; };
        price := _initPrice;
        spread := getSpread(#downward, _spread, price);
        while(price > spread and Nat.sub(price, spread) >= _lowerPrice and gridCount_buy < 200){
            gridCount_buy += 1;
            price := Nat.sub(price, spread);
            spread := getSpread(#downward, _spread, price);
        };
        if (gridCount_buy < 2) { gridCount_buy := 2; };
        let n = (gridCount_sell + gridCount_buy) / 2;
        return OB.floatToNat(OB.natToFloat(n) ** (1.0 / 10.0) * 1000000.0) / n; 
    };

    /// Add a strategy.
    public func put(_data: STOrderRecords, _sto: STOrder) : STOrderRecords{
        return Trie.put(_data, keyn(_sto.soid), Nat.equal, _sto).0;
    };

    /// Returns a strategy order information and status.
    public func get(_data: STOrderRecords, _soid: Soid) : ?STOrder{
        return Trie.get(_data, keyn(_soid), Nat.equal);
    };

    /// Create a new strategy.
    public func new(_data: STOrderRecords, _icrc1Account: ICRC1Account, _soid: Soid, _strategy: STStrategy) : STOrderRecords{
        let sto: STOrder = {
            soid = _soid;
            icrc1Account = _icrc1Account;
            stType = getSTType(_strategy);
            strategy = _strategy;
            stats = {
                orderCount = 0;
                errorCount = 0;
                totalInAmount = {token0 = 0; token1 = 0};
                totalOutAmount = {token0 = 0; token1 = 0};
            };
            status = #Running;
            initTime = _now();
            triggerTime = _now();
            pendingOrders = {buy = []; sell = []};
        };
        return Trie.put(_data, keyn(_soid), Nat.equal, sto).0;
    };

    /// Remove a strategy.
    public func remove(_data: STOrderRecords, _soid: Soid) : STOrderRecords{
        return Trie.remove(_data, keyn(_soid), Nat.equal).0;
    };

    /// Updates the status of a strategy.
    public func updateStatus(_data: STOrderRecords, _soid: Soid, _status: STStatus) : STOrderRecords{
        var data = _data;
        switch(get(data, _soid)){
            case(?(po)){
                let _po: STOrder = {
                    soid = po.soid;
                    icrc1Account = po.icrc1Account;
                    stType = po.stType;
                    strategy = po.strategy;
                    stats = po.stats;
                    status = _status;
                    initTime = po.initTime;
                    triggerTime = po.triggerTime;
                    pendingOrders = po.pendingOrders;
                };
                data := Trie.put(data, keyn(_soid), Nat.equal, _po).0;
            };
            case(_){};
        };
        return data;
    };

    /// Updates the latest trigger time for a strategy.
    public func updateTriggerTime(_data: STOrderRecords, _soid: Soid) : STOrderRecords{
        var data = _data;
        switch(get(data, _soid)){
            case(?(po)){
                let _po: STOrder = {
                    soid = po.soid;
                    icrc1Account = po.icrc1Account;
                    stType = po.stType;
                    strategy = po.strategy;
                    stats = po.stats;
                    status = po.status;
                    initTime = po.initTime;
                    triggerTime = _now();
                    pendingOrders = po.pendingOrders;
                };
                data := Trie.put(data, keyn(_soid), Nat.equal, _po).0;
            };
            case(_){};
        };
        return data;
    };

    /// Updates the statistics for a strategy.
    public func updateStats(_data: STOrderRecords, _soid: Soid, _add: STStats) : STOrderRecords{
        var data = _data;
        switch(get(data, _soid)){
            case(?(po)){
                let _po: STOrder = {
                    soid = po.soid;
                    icrc1Account = po.icrc1Account;
                    stType = po.stType;
                    strategy = po.strategy;
                    stats = {
                        orderCount = po.stats.orderCount + _add.orderCount;
                        errorCount = po.stats.errorCount + _add.errorCount;
                        totalInAmount = {token0 = po.stats.totalInAmount.token0 + _add.totalInAmount.token0; token1 = po.stats.totalInAmount.token1 + _add.totalInAmount.token1};
                        totalOutAmount = {token0 = po.stats.totalOutAmount.token0 + _add.totalOutAmount.token0; token1 = po.stats.totalOutAmount.token1 + _add.totalOutAmount.token1};
                    };
                    status = po.status;
                    initTime = po.initTime;
                    triggerTime = po.triggerTime;
                    pendingOrders = po.pendingOrders;
                };
                data := Trie.put(data, keyn(_soid), Nat.equal, _po).0;
            };
            case(_){};
        };
        return data;
    };

    /// When a strategy is triggered and trade orders are placed, update the pending status of the trade order to the strategy order.
    public func putPendingOrder(_data: STOrderRecords, _soid: Soid, _side: {#Buy; #Sell}, _item: (?Txid, Price, quantity: Nat)) : STOrderRecords{
        var data = _data;
        switch(get(data, _soid)){
            case(?(po)){
                var buyPendingOrders = po.pendingOrders.buy;
                var sellPendingOrders = po.pendingOrders.sell;
                switch(_side){
                    case(#Buy){
                        buyPendingOrders := Array.filter(buyPendingOrders, func (t: (?Txid, Price, Nat)): Bool{ 
                            t.1 != _item.1
                        });
                        buyPendingOrders := OB.arrayAppend(buyPendingOrders, [_item]);
                    };
                    case(#Sell){
                        sellPendingOrders := Array.filter(sellPendingOrders, func (t: (?Txid, Price, Nat)): Bool{ 
                            t.1 != _item.1
                        });
                        sellPendingOrders := OB.arrayAppend(sellPendingOrders, [_item]);
                    };
                };
                let _po: STOrder = {
                    soid = po.soid;
                    icrc1Account = po.icrc1Account;
                    stType = po.stType;
                    strategy = po.strategy;
                    stats = po.stats;
                    status = po.status;
                    initTime = po.initTime;
                    triggerTime = po.triggerTime;
                    pendingOrders = {buy = buyPendingOrders; sell = sellPendingOrders};
                };
                data := Trie.put(data, keyn(_soid), Nat.equal, _po).0;
            };
            case(_){};
        };
        return data;
    };

    /// Removes a record of trade order from a strategy order.
    public func removePendingOrder(_data: STOrderRecords, _soid: Soid, _txid: Txid) : STOrderRecords{
        var data = _data;
        switch(get(data, _soid)){
            case(?(po)){
                let buyPendingOrders = Array.filter(po.pendingOrders.buy, func (t: (?Txid, Price, Nat)): Bool{ t.0 != ?_txid });
                let sellPendingOrders = Array.filter(po.pendingOrders.sell, func (t: (?Txid, Price, Nat)): Bool{ t.0 != ?_txid });
                let _po: STOrder = {
                    soid = po.soid;
                    icrc1Account = po.icrc1Account;
                    stType = po.stType;
                    strategy = po.strategy;
                    stats = po.stats;
                    status = po.status;
                    initTime = po.initTime;
                    triggerTime = po.triggerTime;
                    pendingOrders = {buy = buyPendingOrders; sell = sellPendingOrders};
                };
                data := Trie.put(data, keyn(_soid), Nat.equal, _po).0;
            };
            case(_){};
        };
        return data;
    };

    /// Removes a record of trade order from a strategy order.
    public func removePendingOrderByPrice(_data: STOrderRecords, _soid: Soid, _side: {#Buy; #Sell}, _price: Price) : STOrderRecords{
        var data = _data;
        switch(get(data, _soid)){
            case(?(po)){
                // var hSpread: Nat = 1;
                // switch(po.strategy){
                //     case(#GridOrder(grid)){
                //         hSpread := getSpread(#upward, grid.setting.spread, _price) / 2;
                //     };
                // };
                var buyPendingOrders = po.pendingOrders.buy;
                if (_side == #Buy){
                    buyPendingOrders := Array.filter(po.pendingOrders.buy, func (t: (?Txid, Price, Nat)): Bool{ 
                        t.1 != _price
                    });
                };
                var sellPendingOrders = po.pendingOrders.sell;
                if (_side == #Sell){
                    sellPendingOrders := Array.filter(po.pendingOrders.sell, func (t: (?Txid, Price, Nat)): Bool{ 
                        t.1 != _price
                    });
                };
                let _po: STOrder = {
                    soid = po.soid;
                    icrc1Account = po.icrc1Account;
                    stType = po.stType;
                    strategy = po.strategy;
                    stats = po.stats;
                    status = po.status;
                    initTime = po.initTime;
                    triggerTime = po.triggerTime;
                    pendingOrders = {buy = buyPendingOrders; sell = sellPendingOrders};
                };
                data := Trie.put(data, keyn(_soid), Nat.equal, _po).0;
            };
            case(_){};
        };
        return data;
    };

    /// Returns whether a trade order triggered by a strategy order already exists (whether the same trade order has already 
    /// been triggered and has been placed or is in the process of being placed).
    public func isPendingOrder(_data: STOrderRecords, _soid: Soid, _side: {#Buy; #Sell}, _price: Price) : (Bool, ?Txid){
        switch(get(_data, _soid)){
            case(?(sto)){
                // var hSpread: Nat = 1;
                // switch(sto.strategy){
                //     case(#GridOrder(grid)){
                //         hSpread := getSpread(#upward, grid.setting.spread, _price) / 2;
                //     };
                // };
                if (_side == #Buy){
                    for((optTxid, price, quantity) in sto.pendingOrders.buy.vals()){
                        // let valueMin = Nat.sub(Nat.max(price,hSpread), hSpread);
                        // let valueMax = price + hSpread;
                        // if (_price >= valueMin and _price <= valueMax){
                        //     return (true, optTxid);
                        // };
                        if (price == _price){
                            return (true, optTxid);
                        };
                    };
                };
                if (_side == #Sell){
                    for((optTxid, price, quantity) in sto.pendingOrders.sell.vals()){
                        // let valueMin = Nat.sub(Nat.max(price,hSpread), hSpread);
                        // let valueMax = price + hSpread;
                        // if (_price >= valueMin and _price <= valueMax){
                        //     return (true, optTxid);
                        // };
                        if (price == _price){
                            return (true, optTxid);
                        };
                    };
                };
            };
            case(_){};
        };
        return (false, null);
    };

    /// GridOrder: Returns trade orders with a PENDING status outside the specified grid price range as invalid orders.
    public func getInvalidOrders(_orders: [(?Txid, Price, Nat)], _side: {#Buy; #Sell}, _thresholdFirst: Price, _thresholdLast: Price) : [(?Txid, Price, Nat)]{
        var res: [(?Txid, Price, Nat)] = [];
        switch(_side){
            case(#Buy){
                let valueMin = Nat.sub(Nat.max(_thresholdLast,1), 1);
                // let valueMax = _thresholdFirst + 1;
                for((optTxid, price, quantity) in _orders.vals()){
                    if (price < valueMin/* or price > valueMax*/){
                        res := OB.arrayAppend(res, [(optTxid, price, quantity)]);
                    };
                };
            };
            case(#Sell){
                // let valueMin = Nat.sub(Nat.max(_thresholdFirst,1), 1);
                let valueMax = _thresholdLast + 1;
                for((optTxid, price, quantity) in _orders.vals()){
                    if (/*price < valueMin or */price > valueMax){
                        res := OB.arrayAppend(res, [(optTxid, price, quantity)]);
                    };
                };
            };
        };
        return res;
    };

    /// GridOrder: Determines whether a grid price exists within the current active grid price range.
    public func isExistingPrice(_prices: [Price], _price: Price, _spreadSetting: {#Arith: Price; #Geom: Ppm }) : Bool{
        let hSpread = getSpread(#upward, _spreadSetting, _price) / 2;
        for(price in _prices.vals()){
            let valueMin = Nat.sub(Nat.max(price,hSpread), hSpread);
            let valueMax = price + hSpread;
            if (_price >= valueMin and _price <= valueMax){
                return true;
            };
        };
        return false;
    };
    
    /// Returns the number of pro-orders for a trader.
    public func userPOSize(_data: UserProOrderList, _a: AccountId): Nat{
        switch(Trie.get(_data, keyb(_a), Blob.equal)){
            case(?(list)){
                return List.size(list);
            };
            case(_){
                return 0;
            };
        };
    };

    /// Returns the number of stop-loss-orders for a trader.
    public func userSLOSize(_data: UserStopLossOrderList, _a: AccountId): Nat{
        switch(Trie.get(_data, keyb(_a), Blob.equal)){
            case(?(list)){
                return List.size(list);
            };
            case(_){
                return 0;
            };
        };
    };

    /// Adds a record to the traders and pro-orders index table.
    public func putUserPOList(_data: UserProOrderList, _a: AccountId, _soid: Soid): UserProOrderList{
        switch(Trie.get(_data, keyb(_a), Blob.equal)){
            case(?(list)){
                return Trie.put(_data, keyb(_a), Blob.equal, List.push(_soid, list)).0;
            };
            case(_){
                return Trie.put(_data, keyb(_a), Blob.equal, List.push(_soid, null)).0;
            };
        };
    };

    /// Removes a record from the traders and pro-orders index table.
    public func removeUserPOList(_data: UserProOrderList, _a: AccountId, _soid: Soid): UserProOrderList{
        switch(Trie.get(_data, keyb(_a), Blob.equal)){
            case(?(list)){
                let newList = List.filter(list, func (t: Soid): Bool{ t != _soid });
                if (List.size(newList) == 0){
                    return Trie.remove(_data, keyb(_a), Blob.equal).0;
                }else{
                    return Trie.put(_data, keyb(_a), Blob.equal, newList).0;
                };
            };
            case(_){ return _data };
        };
    };

    /// Adds a record to the traders and stop-loss-orders index table.
    public func putUserSLOList(_data: UserStopLossOrderList, _a: AccountId, _soid: Soid): UserStopLossOrderList{
        switch(Trie.get(_data, keyb(_a), Blob.equal)){
            case(?(list)){
                return Trie.put(_data, keyb(_a), Blob.equal, List.push(_soid, list)).0;
            };
            case(_){
                return Trie.put(_data, keyb(_a), Blob.equal, List.push(_soid, null)).0;
            };
        };
    };

    /// Removes a record from the traders and stop-loss-orders index table.
    public func removeUserSLOList(_data: UserStopLossOrderList, _a: AccountId, _soid: Soid): UserStopLossOrderList{
        switch(Trie.get(_data, keyb(_a), Blob.equal)){
            case(?(list)){
                let newList = List.filter(list, func (t: Soid): Bool{ t != _soid });
                if (List.size(newList) == 0){
                    return Trie.remove(_data, keyb(_a), Blob.equal).0;
                }else{
                    return Trie.put(_data, keyb(_a), Blob.equal, newList).0;
                };
            };
            case(_){ return _data };
        };
    };

    /// Adds a record to the currently active pro-orders queue.
    public func putActivePOList(_data: ActiveProOrderList, _soid: Soid): ActiveProOrderList{
        return List.reverse(List.push(_soid, List.reverse(_data)));
    };

    /// Removes a record from the currently active pro-orders queue.
    public func removeActivePOList(_data: ActiveProOrderList, _soid: Soid): ActiveProOrderList{
        return List.filter(_data, func (t: Soid): Bool{ t != _soid });
    };

    /// Adds a record to the currently active stop-loss-orders queue.
    public func putActiveSLOList(_data: ActiveStopLossOrderList, _side: {#Buy; #Sell}, _item: (Soid, Price)): ActiveStopLossOrderList{
        switch(_side){
            case(#Buy){
                return {buy = _pushSortedSTOList(_data.buy, #Asc, _item); sell = _data.sell };
            };
            case(#Sell){
                return {buy = _data.buy; sell = _pushSortedSTOList(_data.sell, #Desc, _item) };
            };
        };
    };

    /// Removes a record from the currently active stop-loss-orders queue.
    public func removeActiveSLOList(_data: ActiveStopLossOrderList, _soid: Soid): ActiveStopLossOrderList{
        let buyOrders = List.filter(_data.buy, func (t: (Soid, Price)): Bool{ t.0 != _soid });
        let sellOrders = List.filter(_data.sell, func (t: (Soid, Price)): Bool{ t.0 != _soid });
        return {buy = buyOrders; sell = sellOrders };
    };

    /// Adds a record to the trade orders and strategy orders index table.
    public func putSTOTxids(_data: STOrderTxids, _txid: Txid, _soid: Soid): STOrderTxids{
        return Trie.put(_data, keyb(_txid), Blob.equal, _soid).0;
    };

    /// Removes a record from the trade orders and strategy orders index table.
    public func removeSTOTxids(_data: STOrderTxids, _txid: Txid): STOrderTxids{
        return Trie.remove(_data, keyb(_txid), Blob.equal).0;
    };

    /// Returns the soid of the strategy order based on the specified txid.
    public func getSoidByTxid(_data: STOrderTxids, _txid: Txid): ?Soid{
        return Trie.get(_data, keyb(_txid), Blob.equal);
    };

    /// StopLossOrder: Updates a stop-loss-order strategy.
    public func updateStopLossOrder(_data: STOrderRecords, _soid: Soid, _condition: ?Condition, _triggeredOrder: ?TriggeredOrder) : STOrderRecords{
        var data = _data;
        switch(get(data, _soid)){
            case(?(sto)){
                var strategy = sto.strategy;
                switch(strategy){
                    case(#StopLossOrder(slo)){
                        strategy := #StopLossOrder({
                            condition = Option.get(_condition, slo.condition);
                            triggeredOrder = switch(_triggeredOrder){ case(?tOrder){ _triggeredOrder }; case(_){ slo.triggeredOrder } };
                        });
                    };
                    case(_){};
                };
                let _slo: STOrder = {
                    soid = sto.soid;
                    icrc1Account = sto.icrc1Account;
                    stType = sto.stType;
                    strategy = strategy;
                    stats = sto.stats;
                    status = sto.status;
                    initTime = sto.initTime;
                    triggerTime = sto.triggerTime;
                    pendingOrders = sto.pendingOrders;
                };
                data := Trie.put(data, keyn(_soid), Nat.equal, _slo).0;
            };
            case(_){};
        };
        return data;
    };

    /// GridOrder: Updates a pro-order (GridOrder) strategy.
    public func updateGridOrder(_data: STOrderRecords, _soid: Soid, _setting: ?GridSetting, _gridPrices: ?GridPrices) : STOrderRecords{
        var data = _data;
        switch(get(data, _soid)){
            case(?(po)){
                var strategy = po.strategy;
                switch(strategy){
                    case(#GridOrder(go)){
                        strategy := #GridOrder({
                            setting = Option.get(_setting, go.setting);
                            gridPrices = Option.get(_gridPrices, go.gridPrices);
                        });
                    };
                    case(_){};
                };
                let _po: STOrder = {
                    soid = po.soid;
                    icrc1Account = po.icrc1Account;
                    stType = po.stType;
                    strategy = strategy;
                    stats = po.stats;
                    status = po.status;
                    initTime = po.initTime;
                    triggerTime = po.triggerTime;
                    pendingOrders = po.pendingOrders;
                };
                data := Trie.put(data, keyn(_soid), Nat.equal, _po).0;
            };
            case(_){};
        };
        return data;
    };

    /// GridOrder: Removes a grid price from the currently active grid prices of a grid order strategy.
    public func removeGridPrice(_data: STOrderRecords, _soid: Soid, _price: Price) : STOrderRecords{
        var data = _data;
        switch(get(data, _soid)){
            case(?(sto)){
                var strategy = sto.strategy;
                switch(strategy){
                    case(#GridOrder(grid)){
                        let hSpread = getSpread(#upward, grid.setting.spread, _price) / 2;
                        let gridPrices_buy = Array.filter(grid.gridPrices.buy, func (t: Price): Bool{ 
                            t <= Nat.sub(Nat.max(_price,hSpread), hSpread) or t >= _price + hSpread
                        });
                        let gridPrices_sell = Array.filter(grid.gridPrices.sell, func (t: Price): Bool{ 
                            t <= Nat.sub(Nat.max(_price,hSpread), hSpread) or t >= _price + hSpread
                        });
                        strategy := #GridOrder({
                            setting = grid.setting;
                            gridPrices = {midPrice = grid.gridPrices.midPrice; buy = gridPrices_buy; sell = gridPrices_sell };
                        });
                    };
                    case(_){};
                };
                let _sto: STOrder = {
                    soid = sto.soid;
                    icrc1Account = sto.icrc1Account;
                    stType = sto.stType;
                    strategy = strategy;
                    stats = sto.stats;
                    status = sto.status;
                    initTime = sto.initTime;
                    triggerTime = sto.triggerTime;
                    pendingOrders = sto.pendingOrders;
                };
                data := Trie.put(data, keyn(_soid), Nat.equal, _sto).0;
            };
            case(_){};
        };
        return data;
    };

    /// GridOrder: Returns the currently active grid prices for a grid order strategy.
    public func getGridPrices(_setting: GridSetting, _price: Price, _midPrice: ?Price, _lowerLimit: ?Price, _upperLimit: ?Price) : {midPrice: ?Price; sell: [Price]; buy: [Price]}{
        let initPrice = _setting.initPrice;
        let sideSize = _setting.gridCountPerSide;
        let lowerLimit = Option.get(_lowerLimit, _setting.lowerLimit);
        let upperLimit = Option.get(_upperLimit, _setting.upperLimit);
        var midPrice : Price = Option.get(_midPrice, initPrice);
        var price : Price = 0;
        var spread: Price = 0;
        var gridPrice_buy: [Price] = [];
        var gridPrice_sell: [Price] = [];
        if (_price >= midPrice){
            price := midPrice;
            spread := getSpread(#upward, _setting.spread, price);
            while(gridPrice_sell.size() < sideSize and price + spread <= upperLimit){
                if (price + spread >= _price + spread){
                    gridPrice_sell := OB.arrayAppend(gridPrice_sell, [price + spread]);
                };
                if (gridPrice_sell.size() == 1){
                    midPrice := price;
                };
                price := price + spread;
                spread := getSpread(#upward, _setting.spread, price);
            };
            if (gridPrice_sell.size() == 0){
                midPrice := price;
                gridPrice_sell := OB.arrayAppend(gridPrice_sell, [upperLimit]);
            };
            price := midPrice;
            spread := getSpread(#downward, _setting.spread, price);
            while(gridPrice_buy.size() < sideSize and price > spread and Nat.sub(price, spread) >= lowerLimit){
                if (Nat.sub(price, spread) <= Nat.sub(_price, spread)){
                    gridPrice_buy := OB.arrayAppend(gridPrice_buy, [Nat.sub(price, spread)]);
                };
                price := Nat.sub(price, spread);
                spread := getSpread(#downward, _setting.spread, price);
            };
            if (gridPrice_buy.size() == 0){
                gridPrice_buy := OB.arrayAppend(gridPrice_buy, [lowerLimit]);
            };
        }else{
            price := midPrice;
            spread := getSpread(#downward, _setting.spread, price);
            while(gridPrice_buy.size() < sideSize and price > spread and Nat.sub(price, spread) >= lowerLimit){
                if (Nat.sub(price, spread) <= Nat.sub(_price, spread)){
                    gridPrice_buy := OB.arrayAppend(gridPrice_buy, [Nat.sub(price, spread)]);
                };
                if (gridPrice_buy.size() == 1){
                    midPrice := price;
                };
                price := Nat.sub(price, spread);
                spread := getSpread(#downward, _setting.spread, price);
            };
            if (gridPrice_buy.size() == 0){
                midPrice := price;
                gridPrice_buy := OB.arrayAppend(gridPrice_buy, [lowerLimit]);
            };
            price := midPrice;
            spread := getSpread(#upward, _setting.spread, price);
            while(gridPrice_sell.size() < sideSize and price + spread <= upperLimit){
                if (price + spread >= _price + spread){
                    gridPrice_sell := OB.arrayAppend(gridPrice_sell, [price + spread]);
                };
                price := price + spread;
                spread := getSpread(#upward, _setting.spread, price);
            };
            if (gridPrice_sell.size() == 0){
                gridPrice_sell := OB.arrayAppend(gridPrice_sell, [upperLimit]);
            };
        };
        return {midPrice = ?midPrice; sell = gridPrice_sell; buy = gridPrice_buy};
    };

    /// GridOrder: Similar to getGridPrices().
    public func getGridPrices2(_data: STOrderRecords, _soid: Soid, _price: Price, _midPrice: ?Price, _lowerLimit: ?Price, _upperLimit: ?Price) : {midPrice: ?Price; sell: [Price]; buy: [Price]}{
         switch(get(_data, _soid)){
            case(?(po)){
                switch(po.strategy){
                    case(#GridOrder(grid)){
                        return getGridPrices(grid.setting, _price, _midPrice, _lowerLimit, _upperLimit);
                    };
                    case(_){};
                };
            };
            case(_){};
        };
        return {midPrice = null; sell = []; buy = []};
    };

    /// GridOrder: Calculates the quantity of trade order triggered by GridOrder.
    public func getQuantityPerOrder(_setting: GridSetting, _price: Price, _unitSize: Nat, _token0Balance: Amount, _token1Balance: Amount, _side: {#Buy; #Sell}, _minValue: Amount) : 
    {#Buy: (quantity: Nat, amount: Nat); #Sell: Nat; }{
        switch(_setting.amount, _side){
            case(#Token0(v), #Buy){
                let quantity = OB.adjustFlooring(Nat.max(v, _minValue), _unitSize);
                let amount = quantity * _price / _unitSize;
                if (amount <= _token1Balance){
                    return #Buy(quantity, amount);
                };
            };
            case(#Token0(v), #Sell){
                let quantity = OB.adjustFlooring(Nat.max(v, _minValue), _unitSize);
                if (quantity <= _token0Balance){
                    return #Sell(quantity);
                };
            };
            case(#Token1(v), #Buy){
                let quantity = OB.adjustFlooring(Nat.max(_unitSize * v / _price, _minValue), _unitSize);
                let amount = quantity * _price / _unitSize;
                if (amount <= _token1Balance){
                    return #Buy(quantity, amount);
                };
            };
            case(#Token1(v), #Sell){
                let quantity = OB.adjustFlooring(Nat.max(_unitSize * v / _price, _minValue), _unitSize);
                if (quantity <= _token0Balance){
                    return #Sell(quantity);
                };
            };
            // case(#Percent(optPpm), #Buy){
            //     let ppmFactor = Option.get(_setting.ppmFactor, getPpmFactor(_setting.initPrice, _setting.spread, _setting.lowerLimit, _setting.upperLimit));
            //     let ppm = Option.get(optPpm, ppmFactor);
            //     let quantity = OB.adjustFlooring(Nat.max(_unitSize * _token1Balance * ppm / _price / 1000000, _minValue), _unitSize);
            //     let amount = quantity * _price / _unitSize;
            //     if (amount <= _token1Balance){
            //         return #Buy(quantity, amount);
            //     };
            // };
            // case(#Percent(optPpm), #Sell){
            //     let ppmFactor = Option.get(_setting.ppmFactor, getPpmFactor(_setting.initPrice, _setting.spread, _setting.lowerLimit, _setting.upperLimit));
            //     let ppm = Option.get(optPpm, ppmFactor);
            //     let quantity = OB.adjustFlooring(Nat.max(_token0Balance * ppm / 1000000, _minValue), _unitSize);
            //     if (quantity <= _token0Balance){
            //         return #Sell(quantity);
            //     };
            // };
            case(#Percent(optPpm), _){
                let ppmFactor = Option.get(_setting.ppmFactor, 10000);
                let ppm = Option.get(optPpm, ppmFactor);
                let totalBalance = _token0Balance + _unitSize * _token1Balance / _price;
                let quantity = OB.adjustFlooring(Nat.max(totalBalance * ppm / 1000000, _minValue), _unitSize);
                let amount = quantity * _price / _unitSize;
                if (_side == #Buy and amount <= _token1Balance){
                    return #Buy(quantity, amount);
                }else if (_side == #Sell and quantity <= _token0Balance){
                    return #Sell(quantity);
                };
            };
        };
        // else
        if (_side == #Buy) {
            return #Buy(0, 0);
        }else{
            return #Sell(0);
        };
    };

    /// IcebergOrder / VWAP / TWAP: Calculates the quantity of trade order triggered by the IcebergOrder, VWAP or TWAP.
    public func getQuantityForPO(_amount: {#Token0: Nat; #Token1: Nat}, _side: OB.OrderSide, _price: Price, _unitSize: Nat) : 
    {#Buy: (quantity: Nat, amount: Nat); #Sell: Nat; }{
        let _minValue = _unitSize * 10;
        switch(_amount, _side){
            case(#Token0(v), #Buy){
                let quantity = OB.adjustFlooring(Nat.max(v, _minValue), _unitSize);
                let amount = quantity * _price / _unitSize;
                return #Buy(quantity, amount);
            };
            case(#Token0(v), #Sell){
                let quantity = OB.adjustFlooring(Nat.max(v, _minValue), _unitSize);
                return #Sell(quantity);
            };
            case(#Token1(v), #Buy){
                let quantity = OB.adjustFlooring(Nat.max(_unitSize * v / _price, _minValue), _unitSize);
                let amount = quantity * _price / _unitSize;
                return #Buy(quantity, amount);
            };
            case(#Token1(v), #Sell){
                let quantity = OB.adjustFlooring(Nat.max(_unitSize * v / _price, _minValue), _unitSize);
                return #Sell(quantity);
            };
        };
    };

    /// IcebergOrder / VWAP / TWAP: Returns whether the market price has reached the limit range of the strategy.
    public func isReachedLimit(_totalLimit: {#Token0: Nat; #Token1: Nat}, _totalAmount: {#Token0: Nat; #Token1: Nat}, _price: Price, _unitSize: Nat) : Bool{
        var res: Bool = false;
        switch(_totalLimit, _totalAmount){
            case(#Token0(limit), #Token0(amount)){ return amount >= limit };
            case(#Token1(limit), #Token1(amount)){ return amount >= limit };
            case(#Token0(limit), #Token1(amount)){ return _unitSize * amount / _price >= limit };
            case(#Token1(limit), #Token0(amount)){ return amount * _price / _unitSize >= limit };
        };
        return res;
    };

    /// Returns the price of a trade order that increases or decreases by a slippage (spread).
    public func getPrice(_side: OB.OrderSide, _price: Price, _spread: Price) : Price{
        switch(_side){
            case(#Buy){
                return _price + _spread;
            };
            case(#Sell){
                return Nat.max(_price, _spread + 1) - _spread;
            };
        };
    };

    /// IcebergOrder: Updates a pro-order (IcebergOrder) strategy.
    public func updateIcebergOrder(_data: STOrderRecords, _soid: Soid, _setting: ?IcebergOrderSetting, _lastTxid: ?Blob) : STOrderRecords{
        var data = _data;
        switch(get(data, _soid)){
            case(?(po)){
                var strategy = po.strategy;
                switch(strategy){
                    case(#IcebergOrder(io)){
                        strategy := #IcebergOrder({
                            setting = Option.get(_setting, io.setting);
                            lastTxid = switch(_lastTxid){ case(?txid){ _lastTxid }; case(_){ io.lastTxid } };
                        });
                    };
                    case(_){};
                };
                let _po: STOrder = {
                    soid = po.soid;
                    icrc1Account = po.icrc1Account;
                    stType = po.stType;
                    strategy = strategy;
                    stats = po.stats;
                    status = po.status;
                    initTime = po.initTime;
                    triggerTime = po.triggerTime;
                    pendingOrders = po.pendingOrders;
                };
                data := Trie.put(data, keyn(_soid), Nat.equal, _po).0;
            };
            case(_){};
        };
        return data;
    };

    /// VWAP: Updates a pro-order (VWAP) strategy.
    public func updateVWAP(_data: STOrderRecords, _soid: Soid, _setting: ?VWAPSetting, _lastVol: ?Nat) : STOrderRecords{
        var data = _data;
        switch(get(data, _soid)){
            case(?(po)){
                var strategy = po.strategy;
                switch(strategy){
                    case(#VWAP(vo)){
                        strategy := #VWAP({
                            setting = Option.get(_setting, vo.setting);
                            lastVol = switch(_lastVol){ case(?v){ _lastVol }; case(_){ vo.lastVol } };
                        });
                    };
                    case(_){};
                };
                let _po: STOrder = {
                    soid = po.soid;
                    icrc1Account = po.icrc1Account;
                    stType = po.stType;
                    strategy = strategy;
                    stats = po.stats;
                    status = po.status;
                    initTime = po.initTime;
                    triggerTime = po.triggerTime;
                    pendingOrders = po.pendingOrders;
                };
                data := Trie.put(data, keyn(_soid), Nat.equal, _po).0;
            };
            case(_){};
        };
        return data;
    };

    /// TWAP: Updates a pro-order (TWAP) strategy.
    public func updateTWAP(_data: STOrderRecords, _soid: Soid, _setting: ?TWAPSetting, _lastTime: ?Timestamp) : STOrderRecords{
        var data = _data;
        switch(get(data, _soid)){
            case(?(po)){
                var strategy = po.strategy;
                switch(strategy){
                    case(#TWAP(to)){
                        strategy := #TWAP({
                            setting = Option.get(_setting, to.setting);
                            lastTime = switch(_lastTime){ case(?v){ _lastTime }; case(_){ to.lastTime } };
                        });
                    };
                    case(_){};
                };
                let _po: STOrder = {
                    soid = po.soid;
                    icrc1Account = po.icrc1Account;
                    stType = po.stType;
                    strategy = strategy;
                    stats = po.stats;
                    status = po.status;
                    initTime = po.initTime;
                    triggerTime = po.triggerTime;
                    pendingOrders = po.pendingOrders;
                };
                data := Trie.put(data, keyn(_soid), Nat.equal, _po).0;
            };
            case(_){};
        };
        return data;
    };

    /* trigger */
    type OrderPrice = OB.OrderPrice;
    type TxnStatus = {#Failed; #Pending; #Completed; #PartiallyCompletedAndCancelled; #Cancelled;};

    /// Stop-loss-order trigger
    public func sloTrigger(_data: STOrderRecords, _balances: Pair.KeepingBalance, _price: Price, _unitSize: Nat, _soid: STO.Soid, sto: STO.STOrder): 
    (STOrderRecords, STO.STStatus, [(STO.Soid, STO.ICRC1Account, OrderPrice)]){
        var data = _data;
        let price = _price; // icdex_lastPrice.price;
        var res: [(STO.Soid, STO.ICRC1Account, OrderPrice)] = [];
        let account = Tools.principalToAccountBlob(sto.icrc1Account.owner, _toSaNat8(sto.icrc1Account.subaccount));
        let balances = _balances; // _getAccountBalance(account);
        let balance0 = balances.token0.available;
        let balance1 = balances.token1.available;
        switch(sto.strategy){
            case(#StopLossOrder(slo)){
                var status : STO.STStatus = sto.status;
                var orderQuantity : {#Buy: (quantity: Nat, amount: Nat); #Sell: Nat; } = #Sell(0);
                var orderPrice : OrderPrice = { quantity = orderQuantity; price = slo.condition.order.price; };
                var quantity: Nat = 0;
                var amount: Nat = 0;
                switch(slo.condition.order.side){
                    case(#Buy){
                        if (price >= slo.condition.triggerPrice){
                            quantity := OB.adjustFlooring(slo.condition.order.quantity, _unitSize);
                            amount := quantity * slo.condition.order.price / _unitSize;
                            orderQuantity := #Buy(quantity, amount);
                            orderPrice := { quantity = orderQuantity; price = slo.condition.order.price; };
                            status := #Stopped;
                        };
                    };
                    case(#Sell){
                        if (price <= slo.condition.triggerPrice){
                            quantity := OB.adjustFlooring(slo.condition.order.quantity, _unitSize);
                            orderQuantity := #Sell(quantity);
                            orderPrice := { quantity = orderQuantity; price = slo.condition.order.price; };
                            status := #Stopped;
                        };
                    };
                };
                // pre-order
                if (quantity >= _unitSize*2){
                    res := Tools.arrayAppend(res, [(_soid, sto.icrc1Account, orderPrice)]);
                    data := putPendingOrder(data, _soid, slo.condition.order.side, (null, slo.condition.order.price, quantity));
                };
                // update data
                if (res.size() > 0 and Option.isNull(slo.triggeredOrder)){
                    data := updateTriggerTime(data, _soid);
                    data := updateStopLossOrder(data, _soid, null, ?{
                        triggerPrice = price;
                        order = { side = slo.condition.order.side; quantity = quantity; price = slo.condition.order.price; };
                    });
                };
                // return
                return (data, status, res);
            };
            case(_){};
        };
        return (data, sto.status, res);
    };

    /// Grid-order trigger
    public func goTrigger(_data: STOrderRecords, _balances: Pair.KeepingBalance, _price: Price, _unitSize: Nat, _soid: STO.Soid, sto: STO.STOrder): 
    (STOrderRecords, STO.STStatus, ordersTriggered: [(STO.Soid, STO.ICRC1Account, OrderPrice)], ordersToBeCancel: [(Txid, ?OrderSide)]){
        var data = _data;
        let price = _price; // icdex_lastPrice.price;
        var res: [(STO.Soid, STO.ICRC1Account, OrderPrice)] = [];
        var ordersToBeCancel: [(Txid, ?OrderSide)] = [];
        let account = Tools.principalToAccountBlob(sto.icrc1Account.owner, _toSaNat8(sto.icrc1Account.subaccount));
        let balances = _balances; // _getAccountBalance(account);
        let balance0 = balances.token0.available;
        let balance1 = balances.token1.available;
        switch(sto.strategy){
            case(#GridOrder(grid)){
                // prices : {midPrice: ?Price; sell: [Price]; buy: [Price]}
                let prices = getGridPrices(grid.setting, price, grid.gridPrices.midPrice, null, null);
                var insufficientBalance : Bool = false;
                // cancel
                if (prices.buy.size() > 0){
                    let invalidOrders = getInvalidOrders(sto.pendingOrders.buy, #Buy, prices.buy[0], prices.buy[Nat.sub(prices.buy.size(),1)]);
                    for ((optTxid, price, quantity) in invalidOrders.vals()){
                        switch(optTxid){
                            case(?txid){
                                // ignore _cancelOrder(txid, ?#Buy);
                                ordersToBeCancel := Tools.arrayAppend(ordersToBeCancel, [(txid, ?#Buy)]);
                            };
                            case(_){
                                data := removePendingOrderByPrice(data, _soid, #Buy, price);
                                // data := STO.removeGridPrice(data, _soid, price);
                            };
                        };
                    };
                };
                if (prices.sell.size() > 0){
                    let invalidOrders = getInvalidOrders(sto.pendingOrders.sell, #Sell, prices.sell[0], prices.sell[Nat.sub(prices.sell.size(),1)]);
                    for ((optTxid, price, quantity) in invalidOrders.vals()){
                        switch(optTxid){
                            case(?txid){
                                // ignore _cancelOrder(txid, ?#Sell);
                                ordersToBeCancel := Tools.arrayAppend(ordersToBeCancel, [(txid, ?#Sell)]);
                            };
                            case(_){
                                data := removePendingOrderByPrice(data, _soid, #Sell, price);
                                // data := STO.removeGridPrice(data, _soid, price);
                            };
                        };
                    };
                };
                // pre-order
                var toBeLockedValue0: Nat = 0;
                var toBeLockedValue1: Nat = 0;
                for(gridPrice in prices.sell.vals()){
                    let orderQuantity = getQuantityPerOrder(grid.setting, gridPrice, _unitSize, balance0, balance1, #Sell, _unitSize*10);
                    let orderPrice : OrderPrice = { quantity = orderQuantity; price = gridPrice; };
                    let quantity = OB.quantity(orderPrice);
                    if (toBeLockedValue0 + quantity > balances.token0.available){
                        insufficientBalance := true;
                    };
                    if (quantity >= _unitSize*10 and toBeLockedValue0 + quantity <= balances.token0.available and 
                    not(isExistingPrice(grid.gridPrices.sell, gridPrice, grid.setting.spread))){
                        res := Tools.arrayAppend(res, [(_soid, sto.icrc1Account, orderPrice)]);
                        data := putPendingOrder(data, _soid, #Sell, (null, gridPrice, quantity));
                        toBeLockedValue0 += quantity;
                    };
                    // if (pendingValue0 + quantity <= balance0){
                    //     pendingValue0 += quantity;
                    // };
                };
                for(gridPrice in prices.buy.vals()){
                    let orderQuantity = getQuantityPerOrder(grid.setting, gridPrice, _unitSize, balance0, balance1, #Buy, _unitSize*10);
                    let orderPrice : OrderPrice = { quantity = orderQuantity; price = gridPrice; };
                    let quantity = OB.quantity(orderPrice);
                    let amount = OB.amount(orderPrice);
                    if (toBeLockedValue1 + amount > balances.token1.available){
                        insufficientBalance := true;
                    };
                    if (quantity >= _unitSize*10 and amount > 0 and toBeLockedValue1 + amount <= balances.token1.available and 
                    not(isExistingPrice(grid.gridPrices.buy, gridPrice, grid.setting.spread))){
                        res := Tools.arrayAppend(res, [(_soid, sto.icrc1Account, orderPrice)]);
                        data := putPendingOrder(data, _soid, #Buy, (null, gridPrice, quantity));
                        toBeLockedValue1 += amount;
                    };
                    // if (pendingValue1 + amount <= balance1){
                    //     pendingValue1 += amount;
                    // };
                };
                // update data
                if (res.size() > 0){
                    data := updateTriggerTime(data, _soid);
                    data := updateGridOrder(data, _soid, null, ?prices);
                }else if (insufficientBalance and _now() > sto.triggerTime + 24 * 3600){
                    return (data, #Stopped, res, ordersToBeCancel);
                };
            };
            case(_){};
        };
        return (data, sto.status, res, ordersToBeCancel);
    };

    /// Iceberg-order trigger
    public func ioTrigger(_data: STOrderRecords, _balances: Pair.KeepingBalance, _price: Price, _unitSize: Nat, _txnStatus: ?TxnStatus, _soid: STO.Soid, sto: STO.STOrder): 
    (STOrderRecords, STO.STStatus, ordersTriggered: [(STO.Soid, STO.ICRC1Account, OrderPrice)]){
        var data = _data;
        let price = _price; // icdex_lastPrice.price;
        var res: [(STO.Soid, STO.ICRC1Account, OrderPrice)] = [];
        let account = Tools.principalToAccountBlob(sto.icrc1Account.owner, _toSaNat8(sto.icrc1Account.subaccount));
        let balances = _balances; // _getAccountBalance(account);
        let balance0 = balances.token0.available;
        let balance1 = balances.token1.available;
        switch(sto.strategy){
            case(#IcebergOrder(io)){
                var status : STO.STStatus = sto.status;
                var orderQuantity : {#Buy: (quantity: Nat, amount: Nat); #Sell: Nat; } = #Sell(0);
                var orderPrice : OrderPrice = { quantity = orderQuantity; price = io.setting.order.price; };
                var quantity: Nat = 0;
                var amount: Nat = 0;
                var insufficientBalance : Bool = false;
                // trigger
                var trigger: Bool = true;
                switch(_txnStatus){
                    case(?txnStatus){
                        if (txnStatus == #Pending) { trigger := false };
                    };
                    case(_){};
                };
                
                if (_now() > io.setting.endTime){
                    status := #Stopped;
                };
                if (trigger and status == #Running and _now() >= io.setting.startingTime){
                    orderQuantity := getQuantityForPO(io.setting.amountPerTrigger, io.setting.order.side, io.setting.order.price, _unitSize);
                    orderPrice := { quantity = orderQuantity; price = io.setting.order.price; };
                    quantity := OB.quantity(orderPrice);
                    amount := OB.amount(orderPrice);
                    if (OB.side(orderPrice) == #Buy and amount > balances.token1.available){
                        insufficientBalance := true;
                    }else if (OB.side(orderPrice) == #Sell and quantity > balances.token0.available){
                        insufficientBalance := true;
                    };
                    var totalAmount: {#Token0: Nat; #Token1: Nat} = #Token0(0);
                    switch(io.setting.totalLimit){
                        case(#Token0(v)){ totalAmount := #Token0(quantity + Nat.max(sto.stats.totalInAmount.token0, sto.stats.totalOutAmount.token0)); };
                        case(#Token1(v)){ totalAmount := #Token1(amount + Nat.max(sto.stats.totalInAmount.token1, sto.stats.totalOutAmount.token1)); };
                    };
                    if (isReachedLimit(io.setting.totalLimit, totalAmount, io.setting.order.price, _unitSize)){
                        status := #Stopped;
                    };
                };
                // pre-order
                if (trigger and quantity >= _unitSize*10 and not(insufficientBalance)){
                    res := Tools.arrayAppend(res, [(_soid, sto.icrc1Account, orderPrice)]);
                    data := putPendingOrder(data, _soid, io.setting.order.side, (null, io.setting.order.price, quantity));
                };
                // update data
                if (res.size() > 0){
                    data := updateTriggerTime(data, _soid);
                }else if (insufficientBalance and _now() > sto.triggerTime + 24 * 3600){
                    return (data, #Stopped, res);
                };
                // return
                return (data, status, res);
            };
            case(_){};
        };
        return (data, sto.status, res);
    };

    /// VWAP Trigger
    public func vwapTrigger(_data: STOrderRecords, _balances: Pair.KeepingBalance, _price: Price, _unitSize: Nat, _totalVol: Pair.Vol, _vol24h: Pair.Vol,
    _soid: STO.Soid, sto: STO.STOrder): (STOrderRecords, STO.STStatus, ordersTriggered: [(STO.Soid, STO.ICRC1Account, OrderPrice)]){
        var data = _data;
        let price = _price; // icdex_lastPrice.price;
        var res: [(STO.Soid, STO.ICRC1Account, OrderPrice)] = [];
        let account = Tools.principalToAccountBlob(sto.icrc1Account.owner, _toSaNat8(sto.icrc1Account.subaccount));
        let balances = _balances; // _getAccountBalance(account);
        let balance0 = balances.token0.available;
        let balance1 = balances.token1.available;
        switch(sto.strategy){
            case(#VWAP(vwap)){
                var status : STO.STStatus = sto.status;
                let thisPrice = getPrice(vwap.setting.order.side, price, vwap.setting.order.priceSpread);
                var orderQuantity : {#Buy: (quantity: Nat, amount: Nat); #Sell: Nat; } = #Sell(0);
                var orderPrice : OrderPrice = { quantity = orderQuantity; price = thisPrice; };
                var quantity: Nat = 0;
                var amount: Nat = 0;
                var insufficientBalance : Bool = false;
                // trigger
                var trigger: Bool = true;
                if (vwap.setting.order.side == #Buy and thisPrice > vwap.setting.order.priceLimit){
                    trigger := false;
                }else if (vwap.setting.order.side == #Sell and thisPrice < vwap.setting.order.priceLimit){
                    trigger := false;
                }else{
                    switch(vwap.setting.triggerVol, vwap.lastVol){ // token1
                        case(#Arith(t), ?lastVol){
                            if (Nat.sub(_totalVol.value1, lastVol) < t){ trigger := false; };
                        };
                        case(#Geom(ppm), ?lastVol){
                            let t = _vol24h.value1 * ppm / 1_000_000;
                            if (Nat.sub(_totalVol.value1, lastVol) < t){ trigger := false; };
                        };
                        case(_){};
                    };
                };
                
                if (_now() > vwap.setting.endTime){
                    status := #Stopped;
                };
                if (trigger and status == #Running and _now() >= vwap.setting.startingTime){
                    orderQuantity := getQuantityForPO(vwap.setting.amountPerTrigger, vwap.setting.order.side, thisPrice, _unitSize);
                    orderPrice := { quantity = orderQuantity; price = thisPrice; };
                    quantity := OB.quantity(orderPrice);
                    amount := OB.amount(orderPrice);
                    if (OB.side(orderPrice) == #Buy and amount > balances.token1.available){
                        insufficientBalance := true;
                    }else if (OB.side(orderPrice) == #Sell and quantity > balances.token0.available){
                        insufficientBalance := true;
                    };
                    var totalAmount: {#Token0: Nat; #Token1: Nat} = #Token0(0);
                    switch(vwap.setting.totalLimit){
                        case(#Token0(v)){ totalAmount := #Token0(quantity + Nat.max(sto.stats.totalInAmount.token0, sto.stats.totalOutAmount.token0)); };
                        case(#Token1(v)){ totalAmount := #Token1(amount + Nat.max(sto.stats.totalInAmount.token1, sto.stats.totalOutAmount.token1)); };
                    };
                    if (isReachedLimit(vwap.setting.totalLimit, totalAmount, thisPrice, _unitSize)){
                        status := #Stopped;
                    };
                };
                // pre-order
                if (trigger and quantity >= _unitSize*10 and not(insufficientBalance)){
                    res := Tools.arrayAppend(res, [(_soid, sto.icrc1Account, orderPrice)]);
                    data := putPendingOrder(data, _soid, vwap.setting.order.side, (null, thisPrice, quantity));
                };
                // update data
                if (res.size() > 0){
                    data := updateTriggerTime(data, _soid);
                    data := updateVWAP(data, _soid, null, ?_totalVol.value1);
                }else if (insufficientBalance and _now() > sto.triggerTime + 24 * 3600){
                    return (data, #Stopped, res);
                };
                // return
                return (data, status, res);
            };
            case(_){};
        };
        return (data, sto.status, res);
    };

    /// TWAP Trigger
    public func twapTrigger(_data: STOrderRecords, _balances: Pair.KeepingBalance, _price: Price, _unitSize: Nat, _soid: STO.Soid, sto: STO.STOrder): 
    (STOrderRecords, STO.STStatus, ordersTriggered: [(STO.Soid, STO.ICRC1Account, OrderPrice)]){
        var data = _data;
        let price = _price;
        var res: [(STO.Soid, STO.ICRC1Account, OrderPrice)] = [];
        let account = Tools.principalToAccountBlob(sto.icrc1Account.owner, _toSaNat8(sto.icrc1Account.subaccount));
        let balances = _balances; // _getAccountBalance(account);
        let balance0 = balances.token0.available;
        let balance1 = balances.token1.available;
        switch(sto.strategy){
            case(#TWAP(twap)){
                var status : STO.STStatus = sto.status;
                let thisPrice = getPrice(twap.setting.order.side, price, twap.setting.order.priceSpread);
                var orderQuantity : {#Buy: (quantity: Nat, amount: Nat); #Sell: Nat; } = #Sell(0);
                var orderPrice : OrderPrice = { quantity = orderQuantity; price = thisPrice; };
                var quantity: Nat = 0;
                var amount: Nat = 0;
                var insufficientBalance : Bool = false;
                // trigger
                var trigger: Bool = true;
                if (twap.setting.order.side == #Buy and thisPrice > twap.setting.order.priceLimit){
                    trigger := false;
                }else if (twap.setting.order.side == #Sell and thisPrice < twap.setting.order.priceLimit){
                    trigger := false;
                }else{
                    switch(twap.lastTime){ // seconds
                        case(?lastTime){
                            if (Nat.sub(_now(), lastTime) < twap.setting.triggerInterval){ trigger := false; };
                        };
                        case(_){};
                    };
                };
                
                if (_now() > twap.setting.endTime){
                    status := #Stopped;
                };
                if (trigger and status == #Running and _now() >= twap.setting.startingTime){
                    orderQuantity := getQuantityForPO(twap.setting.amountPerTrigger, twap.setting.order.side, thisPrice, _unitSize);
                    orderPrice := { quantity = orderQuantity; price = thisPrice; };
                    quantity := OB.quantity(orderPrice);
                    amount := OB.amount(orderPrice);
                    if (OB.side(orderPrice) == #Buy and amount > balances.token1.available){
                        insufficientBalance := true;
                    }else if (OB.side(orderPrice) == #Sell and quantity > balances.token0.available){
                        insufficientBalance := true;
                    };
                    var totalAmount: {#Token0: Nat; #Token1: Nat} = #Token0(0);
                    switch(twap.setting.totalLimit){
                        case(#Token0(v)){ totalAmount := #Token0(quantity + Nat.max(sto.stats.totalInAmount.token0, sto.stats.totalOutAmount.token0)); };
                        case(#Token1(v)){ totalAmount := #Token1(amount + Nat.max(sto.stats.totalInAmount.token1, sto.stats.totalOutAmount.token1)); };
                    };
                    if (isReachedLimit(twap.setting.totalLimit, totalAmount, thisPrice, _unitSize)){
                        status := #Stopped;
                    };
                };
                // pre-order
                if (trigger and quantity >= _unitSize*10 and not(insufficientBalance)){
                    res := Tools.arrayAppend(res, [(_soid, sto.icrc1Account, orderPrice)]);
                    data := putPendingOrder(data, _soid, twap.setting.order.side, (null, thisPrice, quantity));
                };
                // update data
                if (res.size() > 0){
                    data := updateTriggerTime(data, _soid);
                    data := updateTWAP(data, _soid, null, ?_now());
                }else if (insufficientBalance and _now() > sto.triggerTime + 24 * 3600){
                    return (data, #Stopped, res);
                };
                // return
                return (data, status, res);
            };
            case(_){};
        };
        return (data, sto.status, res);
    };
};