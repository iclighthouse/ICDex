/**
 * Module     : StrategyOrder.mo
 * Author     : ICLighthouse Team
 * Stability  : Experimental
 * Description: Strategic orders: Professional orders and Stop loss orders.
 * Refers     : https://github.com/iclighthouse/
 */
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

/// Fee model
/// 1. Fixed fee at time of order
/// 2. Pro-rated fee when triggered (regardless of whether or not it is filled)

module {
    public type Txid = STO.Txid;
    public type AccountId = STO.AccountId;
    public type ICRC1Account = STO.ICRC1Account;
    public type Nonce = STO.Nonce;
    public type Amount = STO.Amount;
    public type Timestamp = STO.Timestamp; // seconds
    public type Price = STO.Price;
    public type OrderSide = OB.OrderSide;
    // pro-orders
    public type Soid = STO.Soid;
    public type Ppm = STO.Ppm; //  1 / 1000000
    public type STOrderRecords = STO.STOrderRecords; 
    public type UserProOrderList = STO.UserProOrderList; // Excluding Stop Loss Orders; UserOrderCount <= 5; 
    public type ActiveProOrderList = STO.ActiveProOrderList; // Excluding Stop Loss Orders
    public type UserStopLossOrderList = STO.UserStopLossOrderList; // Stop Loss Orders; UserOrderCount <= 10; 
    public type ActiveStopLossOrderList = STO.ActiveStopLossOrderList; // Stop Loss Orders
    public type STOrderTxids = STO.STOrderTxids; 

    public type Setting = STO.Setting;
    public type STType = STO.STType; // {#StopLossOrder; #GridOrder; #IcebergOrder; #VWAP; #TWAP }; 
    public type STStrategy = STO.STStrategy;
    public type STStats = STO.STStats;
    public type STStatus = STO.STStatus;
    public type STOrder = STO.STOrder;
    // GridOrder
    public type GridSetting = STO.GridSetting;
    // public type GridProgress = {
    //     ppmFactor: ?{buy: Nat; sell: Nat}; //  1000000 * 1/n * (n ** (1/10))
    //     gridPrices: { buy: [Price]; sell: [Price] };  // ordered
    // };
    public type GridPrices = STO.GridPrices;
    public type GridOrder = STO.GridOrder;

    private func _now() : Timestamp{
        return Int.abs(Time.now() / 1000000000);
    };
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
    // replace Hash.hash (Warning: Incompatible)
    public func natHash(n : Nat) : Hash.Hash{
        return Blob.hash(Blob.fromArray(Binary.BigEndian.fromNat64(Nat64.fromIntWrap(n))));
    };
    private func keyn(t: Nat) : Trie.Key<Nat> { return { key = t; hash = natHash(t) }; };
    private func keyb(t: Blob) : Trie.Key<Blob> { return { key = t; hash = Blob.hash(t) }; };

    public func getSTType(_strategy: STStrategy) : STType{
        switch(_strategy){
            case(#GridOrder(v)){ return #GridOrder };
        };
    };
    public func getSpread(_side: {#upward; #downward}, _spread: {#Arith: Price; #Geom: Ppm }, _gridPrice: Price) : Nat{
        switch(_side){
            case(#upward){
                return switch(_spread){ case(#Arith(v)){ v }; case(#Geom(ppm)){ _gridPrice * ppm / 1000000 } };
            };
            case(#downward){
                return switch(_spread){ case(#Arith(v)){ v }; case(#Geom(ppm)){ (_gridPrice - (_gridPrice * 1000000 / (1000000 + ppm))) } };
            };
        };
    };
    public func getPpmFactor(_initPrice: Price, _spread: {#Arith: Price; #Geom: Ppm }, _lowerPrice: Price, _upperPrice: Price) : Nat{
        // 1000000 * 1/n * (n ** (1/10))
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
        if (gridCount_sell == 0) { gridCount_sell := 1; };
        price := _initPrice;
        spread := getSpread(#downward, _spread, price);
        while(price > spread and Nat.sub(price, spread) >= _lowerPrice and gridCount_buy < 200){
            gridCount_buy += 1;
            price := Nat.sub(price, spread);
            spread := getSpread(#downward, _spread, price);
        };
        if (gridCount_buy == 0) { gridCount_buy := 1; };
        let n = Nat.min(gridCount_sell, gridCount_buy);
        return OB.floatToNat(OB.natToFloat(n) ** (1.0 / 10.0) * 1000000.0) / n; 
    };
    public func put(_data: STOrderRecords, _sto: STOrder) : STOrderRecords{
        return Trie.put(_data, keyn(_sto.soid), Nat.equal, _sto).0;
    };
    public func get(_data: STOrderRecords, _soid: Soid) : ?STOrder{
        return Trie.get(_data, keyn(_soid), Nat.equal);
    };
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
    public func remove(_data: STOrderRecords, _soid: Soid) : STOrderRecords{
        return Trie.remove(_data, keyn(_soid), Nat.equal).0;
    };
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
    public func removePendingOrderByPrice(_data: STOrderRecords, _soid: Soid, _price: Price) : STOrderRecords{
        var data = _data;
        switch(get(data, _soid)){
            case(?(po)){
                // var hSpread: Nat = 1;
                // switch(po.strategy){
                //     case(#GridOrder(grid)){
                //         hSpread := getSpread(#upward, grid.setting.spread, _price) / 2;
                //     };
                // };
                let buyPendingOrders = Array.filter(po.pendingOrders.buy, func (t: (?Txid, Price, Nat)): Bool{ 
                    t.1 != _price
                });
                let sellPendingOrders = Array.filter(po.pendingOrders.sell, func (t: (?Txid, Price, Nat)): Bool{ 
                    t.1 != _price
                });
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
    public func putActivePOList(_data: ActiveProOrderList, _soid: Soid): ActiveProOrderList{
        return List.reverse(List.push(_soid, List.reverse(_data)));
    };
    public func removeActivePOList(_data: ActiveProOrderList, _soid: Soid): ActiveProOrderList{
        return List.filter(_data, func (t: Soid): Bool{ t != _soid });
    };
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
    public func removeActiveSLOList(_data: ActiveStopLossOrderList, _soid: Soid): ActiveStopLossOrderList{
        let buyOrders = List.filter(_data.buy, func (t: (Soid, Price)): Bool{ t.0 != _soid });
        let sellOrders = List.filter(_data.sell, func (t: (Soid, Price)): Bool{ t.0 != _soid });
        return {buy = buyOrders; sell = sellOrders };
    };
    public func putPOTxids(_data: STOrderTxids, _txid: Txid, _soid: Soid): STOrderTxids{
        return Trie.put(_data, keyb(_txid), Blob.equal, _soid).0;
    };
    public func removePOTxids(_data: STOrderTxids, _txid: Txid): STOrderTxids{
        return Trie.remove(_data, keyb(_txid), Blob.equal).0;
    };
    public func getSoidByTxid(_data: STOrderTxids, _txid: Txid): ?Soid{
        return Trie.get(_data, keyb(_txid), Blob.equal);
    };
    // GridOrder
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
                    // case(_){};
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
                    // case(_){};
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
    public func getGridPrices2(_data: STOrderRecords, _soid: Soid, _price: Price, _midPrice: ?Price, _lowerLimit: ?Price, _upperLimit: ?Price) : {midPrice: ?Price; sell: [Price]; buy: [Price]}{
         switch(get(_data, _soid)){
            case(?(po)){
                switch(po.strategy){
                    case(#GridOrder(grid)){
                        return getGridPrices(grid.setting, _price, _midPrice, _lowerLimit, _upperLimit);
                    };
                    // case(_){};
                };
            };
            case(_){};
        };
        return {midPrice = null; sell = []; buy = []};
    };
    public func getQuantityPerOrder(_setting: GridSetting, _price: Price, _unitSize: Nat, _token0Balance: Amount, _token1Balance: Amount, _side: {#Buy; #Sell}, _minValue: Amount) : 
    {#Buy: (quantity: Nat, amount: Nat); #Sell: Nat; }{
        switch(_setting.amount, _side){
            case(#Token0(v), #Buy){
                let quantity = OB.adjust(Nat.max(v, _minValue), _unitSize);
                let amount = quantity * _price / _unitSize;
                if (amount <= _token1Balance){
                    return #Buy(quantity, amount);
                };
            };
            case(#Token0(v), #Sell){
                let quantity = OB.adjust(Nat.max(v, _minValue), _unitSize);
                if (quantity <= _token0Balance){
                    return #Sell(quantity);
                };
            };
            case(#Token1(v), #Buy){
                let quantity = OB.adjust(Nat.max(_unitSize * v / _price, _minValue), _unitSize);
                let amount = quantity * _price / _unitSize;
                if (amount <= _token1Balance){
                    return #Buy(quantity, amount);
                };
            };
            case(#Token1(v), #Sell){
                let quantity = OB.adjust(Nat.max(_unitSize * v / _price, _minValue), _unitSize);
                if (quantity <= _token0Balance){
                    return #Sell(quantity);
                };
            };
            case(#Percent(optPpm), #Buy){
                let ppmFactor = Option.get(_setting.ppmFactor, getPpmFactor(_setting.initPrice, _setting.spread, _setting.lowerLimit, _setting.upperLimit));
                let ppm = Option.get(optPpm, ppmFactor);
                let quantity = OB.adjust(Nat.max(_unitSize * _token1Balance * ppm / _price / 1000000, _minValue), _unitSize);
                let amount = quantity * _price / _unitSize;
                if (amount <= _token1Balance){
                    return #Buy(quantity, amount);
                };
            };
            case(#Percent(optPpm), #Sell){
                let ppmFactor = Option.get(_setting.ppmFactor, getPpmFactor(_setting.initPrice, _setting.spread, _setting.lowerLimit, _setting.upperLimit));
                let ppm = Option.get(optPpm, ppmFactor);
                let quantity = OB.adjust(Nat.max(_token0Balance * ppm / 1000000, _minValue), _unitSize);
                if (quantity <= _token0Balance){
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

};