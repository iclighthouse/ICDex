/**
 * Module     : OrderBook.mo
 * Author     : ICLighthouse Team
 * Stability  : Experimental
 * Description: OrderBook Manager.
 * Refers     : https://github.com/iclighthouse/
 */
import Nat "mo:base/Nat";
import Nat64 "mo:base/Nat64";
import Int64 "mo:base/Int64";
import Int "mo:base/Int";
import Float "mo:base/Float";
import Option "mo:base/Option";
import Array "mo:base/Array";
import Time "mo:base/Time";
import Hash "mo:base/Hash";
import List "mo:base/List";
import Trie "mo:base/Trie";
import Deque "mo:base/Deque";
import Buffer "mo:base/Buffer";
import Blob "mo:base/Blob";
import Binary "lib/Binary";

module {
    public type Txid = Blob;
    public type Amount = Nat;
    public type Timestamp = Nat; // seconds
    public type BalanceChange = {
        #DebitRecord: Nat; // account "-"   contract "+"
        #CreditRecord: Nat; // account "+"   contract "-"
        #NoChange;
    };
    public type OrderSide = { #Sell; #Buy; };
    public type OrderType = { #LMT; #FOK; #FAK; #MKT; }; // #MKT; 
    public type OrderPrice = { quantity: {#Buy: (quantity: Nat, amount: Nat); #Sell: Nat; }; price: Nat; };
    public type PriceResponse = { quantity: Nat; price: Nat; };
    public type Tick = { bestAsk: PriceResponse; bestBid: PriceResponse };
    public type OrderFilled = {counterparty: Txid; token0Value: BalanceChange; token1Value: BalanceChange; time: Time.Time };
    public type OrderBook = { ask: List.List<(Txid, OrderPrice)>;  bid: List.List<(Txid, OrderPrice)>};
    //public type OrderBookResponse = { ask: List.List<(Txid, PriceResponse)>;  bid: List.List<(Txid, PriceResponse)>};
    public let NumberCachedBars: Nat = 1440;
    public type KInterval = Nat; // seconds
    // price = token1_amount * _UNIT_SIZE / token0_amount;  vol += token0_amount;
    public type KBar = {kid: Nat; open: Nat; high: Nat; low: Nat; close: Nat; vol: Nat; updatedTs: Timestamp}; // kid = ts_seconds / KInterval
    public type KLines = Trie.Trie<KInterval, Deque.Deque<KBar>>;

    private func _now() : Timestamp{
        return Int.abs(Time.now() / 1000000000);
    };
    // replace Hash.hash (Warning: Incompatible)
    public func natHash(n : Nat) : Hash.Hash{
        return Blob.hash(Blob.fromArray(Binary.BigEndian.fromNat64(Nat64.fromIntWrap(n))));
    };
    private func keyn(t: Nat) : Trie.Key<Nat> { return { key = t; hash = natHash(t) }; };

    public func arrayAppend<T>(a: [T], b: [T]) : [T]{
        let buffer = Buffer.Buffer<T>(1);
        for (t in a.vals()){
            buffer.add(t);
        };
        for (t in b.vals()){
            buffer.add(t);
        };
        return buffer.toArray();
    };
    public func natToFloat(_n: Nat) : Float{
        return Float.fromInt64(Int64.fromNat64(Nat64.fromNat(_n)));
    };
    public func adjust(_amount: Nat, _UNIT_SIZE: Nat) : Nat{
        return (_amount + _UNIT_SIZE/2) / _UNIT_SIZE * _UNIT_SIZE;
    };
    public func adjustCeiling(_amount: Nat, _UNIT_SIZE: Nat) : Nat{
        return (_amount + _UNIT_SIZE - Nat.min(_UNIT_SIZE, 1)) / _UNIT_SIZE * _UNIT_SIZE;
    };
    public func adjustFlooring(_amount: Nat, _UNIT_SIZE: Nat) : Nat{
        return _amount / _UNIT_SIZE * _UNIT_SIZE;
    };
    public func side(_orderPrice: OrderPrice) : OrderSide{
        switch(_orderPrice.quantity){
            case(#Buy(value)){ return #Buy; };
            case(#Sell(value)){ return #Sell; };
        };
    };
    public func quantity(_orderPrice: OrderPrice) : Nat{
        switch(_orderPrice.quantity){
            case(#Buy(value)){ return value.0; };
            case(#Sell(value)){ return value; };
        };
    };
    public func amount(_orderPrice: OrderPrice) : Nat{
        switch(_orderPrice.quantity){
            case(#Buy(value)){ return value.1; };
            case(#Sell(value)){ return 0; };
        };
    };
    public func valueAmount(_orderPrice: OrderPrice, _UNIT_SIZE: Nat) : ?Nat{
        switch(_orderPrice.quantity){
            case(#Buy(value)){ 
                if (_orderPrice.price == 0){return ?value.1; }
                else{ return ?(value.0 * _orderPrice.price / _UNIT_SIZE); };
            };
            case(#Sell(value)){
                if (_orderPrice.price == 0){return null; }
                else{ return ?(value * _orderPrice.price / _UNIT_SIZE); };
            };
        };
    };
    public func setQuantity(_orderPrice: OrderPrice, _quantity: Nat, _amount: ?Nat) : OrderPrice{
        var quantity = _orderPrice.quantity;
        switch(_orderPrice.quantity){
            case(#Buy(value)){ quantity := #Buy((_quantity, Option.get(_amount, value.1))); };
            case(#Sell(value)){ quantity := #Sell(_quantity); };
        };
        return { quantity = quantity; price = _orderPrice.price; };
    };
    
    private func _priceResponse(_p: OrderPrice) : PriceResponse{
        var quantity: Nat = 0;
        switch(_p.quantity){
            case(#Buy(v)){ quantity := v.0; };
            case(#Sell(v)){ quantity := v; };
        };
        return { quantity = quantity; price = _p.price;};
    };
    public func priceResponse(_p: OrderPrice) : PriceResponse{
        return _priceResponse(_p);
    };
    private func _priceResponseArr(_p: [OrderPrice]) : [PriceResponse]{
        return Array.map(_p, func (t: OrderPrice): PriceResponse{
            return _priceResponse(t);
        });
    };
    private func _fill(_ob: OrderBook, _orderPrice: OrderPrice, _filled: [OrderFilled], _UNIT_SIZE: Nat, _lastPrice: ?OrderPrice) : (ob: OrderBook, filled: [OrderFilled], remaining: OrderPrice, fillPrice: ?OrderPrice){
        if (side(_orderPrice) == #Sell and quantity(_orderPrice) == 0) {  
            return (_ob, _filled, _orderPrice, null); 
        }else if (side(_orderPrice) == #Buy and amount(_orderPrice) == 0) {  
            return (_ob, _filled, _orderPrice, null); 
        };
        var filled: [OrderFilled] = _filled;
        var remaining: OrderPrice = _orderPrice;
        var fillPrice: ?OrderPrice = _lastPrice;
        switch(side(remaining)){
            case(#Buy){
                var ask = _ob.ask;
                var item = List.pop(ask);
                switch(item.0){
                    case(?(txid, orderPrice)){
                        if (remaining.price >= orderPrice.price){
                            if (quantity(remaining) > quantity(orderPrice)){
                                let _quantity = quantity(orderPrice);
                                let _amount = quantity(orderPrice) * orderPrice.price / _UNIT_SIZE;
                                fillPrice := ?{ quantity = #Buy((_quantity, _amount)); price = orderPrice.price; };
                                remaining := setQuantity(remaining, quantity(remaining) - _quantity, ?(amount(remaining) - _amount)); 
                                filled := arrayAppend(filled, [{
                                    counterparty = txid; 
                                    token0Value = #CreditRecord(_quantity); 
                                    token1Value = #DebitRecord(_amount); 
                                    time = Time.now()}]);
                                ask := item.1;
                                return _fill({ask=ask; bid=_ob.bid}, remaining, filled, _UNIT_SIZE, fillPrice);
                            } else if (quantity(remaining) <= quantity(orderPrice) and quantity(remaining) >= _UNIT_SIZE){
                                let _quantity = quantity(remaining);
                                let _amount = quantity(remaining) * orderPrice.price / _UNIT_SIZE;
                                fillPrice := ?{ quantity = #Buy((_quantity, _amount)); price = orderPrice.price; };
                                remaining := setQuantity(remaining, 0, ?(amount(remaining) - _amount)); 
                                filled := arrayAppend(filled, [{
                                    counterparty = txid; 
                                    token0Value = #CreditRecord(_quantity); 
                                    token1Value = #DebitRecord(_amount); 
                                    time = Time.now()}]);
                                let orderPriceNew = setQuantity(orderPrice, quantity(orderPrice) - _quantity, null); 
                                ask := item.1;
                                if (quantity(orderPriceNew) >= _UNIT_SIZE){ // Otherwise, dropped.
                                    ask := List.push((txid, orderPriceNew), ask);
                                };
                                return ({ask = ask; bid = _ob.bid}, filled, remaining, fillPrice);
                            }else {
                                return (_ob, filled, remaining, fillPrice);
                            };
                        } else if (remaining.price == 0){ // #MKT
                            let bookAskAmount = quantity(orderPrice) * orderPrice.price / _UNIT_SIZE;
                            if (amount(remaining) >= bookAskAmount){
                                let _quantity = quantity(orderPrice);
                                let _amount = bookAskAmount;
                                fillPrice := ?{ quantity = #Buy((_quantity, _amount)); price = orderPrice.price; };
                                remaining := setQuantity(remaining, 0, ?(amount(remaining) - _amount)); 
                                filled := arrayAppend(filled, [{
                                    counterparty = txid; 
                                    token0Value = #CreditRecord(_quantity); 
                                    token1Value = #DebitRecord(_amount); 
                                    time = Time.now()}]);
                                ask := item.1;
                                return _fill({ask=ask; bid=_ob.bid}, remaining, filled, _UNIT_SIZE, fillPrice);
                            } else if (amount(remaining) <= bookAskAmount and amount(remaining) * _UNIT_SIZE / orderPrice.price >= _UNIT_SIZE){
                                let _quantity = adjustFlooring(amount(remaining) * _UNIT_SIZE / orderPrice.price, _UNIT_SIZE);
                                let _amount = _quantity * orderPrice.price / _UNIT_SIZE;
                                fillPrice := ?{ quantity = #Buy((_quantity, _amount)); price = orderPrice.price; };
                                remaining := setQuantity(remaining, 0, ?(amount(remaining) - _amount)); 
                                filled := arrayAppend(filled, [{
                                    counterparty = txid; 
                                    token0Value = #CreditRecord(_quantity); 
                                    token1Value = #DebitRecord(_amount); 
                                    time = Time.now()}]);
                                let orderPriceNew = setQuantity(orderPrice, quantity(orderPrice) - _quantity, null); 
                                ask := item.1;
                                if (quantity(orderPriceNew) >= _UNIT_SIZE){ // Otherwise, dropped.
                                    ask := List.push((txid, orderPriceNew), ask);
                                };
                                return ({ask = ask; bid = _ob.bid}, filled, remaining, fillPrice);
                            }else {
                                return (_ob, filled, remaining, fillPrice);
                            };
                        }else{
                            return (_ob, filled, remaining, fillPrice);
                        };
                    };
                    case(_){ return (_ob, filled, remaining, fillPrice); };
                };
            };
            case(#Sell){
                var bid = _ob.bid;
                var item = List.pop(bid);
                switch(item.0){
                    case(?(txid, orderPrice)){
                        if (remaining.price <= orderPrice.price or remaining.price == 0){
                            if (quantity(remaining) > quantity(orderPrice)){
                                let _quantity = quantity(orderPrice);
                                let _amount = quantity(orderPrice) * orderPrice.price / _UNIT_SIZE;
                                fillPrice := ?{ quantity = #Sell(_quantity); price = orderPrice.price; };
                                remaining := setQuantity(remaining, quantity(remaining) - _quantity, null); 
                                filled := arrayAppend(filled, [{
                                    counterparty = txid; 
                                    token0Value = #DebitRecord(_quantity); 
                                    token1Value = #CreditRecord(_amount); 
                                    time = Time.now()}]);
                                bid := item.1;
                                return _fill({ask=_ob.ask; bid=bid}, remaining, filled, _UNIT_SIZE, fillPrice);
                            } else if (quantity(remaining) <= quantity(orderPrice) and quantity(remaining) >= _UNIT_SIZE){
                                let _quantity = quantity(remaining);
                                let _amount = quantity(remaining) * orderPrice.price / _UNIT_SIZE;
                                fillPrice := ?{ quantity = #Sell(_quantity); price = orderPrice.price; };
                                remaining := setQuantity(remaining, 0, null);  
                                filled := arrayAppend(filled, [{
                                    counterparty = txid; 
                                    token0Value = #DebitRecord(_quantity); 
                                    token1Value = #CreditRecord(_amount); 
                                    time = Time.now()}]);
                                let orderPriceNew = setQuantity(orderPrice, quantity(orderPrice) - _quantity, ?(amount(orderPrice) - _amount)); 
                                bid := item.1;
                                if (quantity(orderPriceNew) >= _UNIT_SIZE){
                                    bid := List.push((txid, orderPriceNew), bid);
                                };
                                return ({ask = _ob.ask; bid = bid}, filled, remaining, fillPrice);
                            }else {
                                return (_ob, filled, remaining, fillPrice);
                            };
                        }else {
                            return (_ob, filled, remaining, fillPrice);
                        };
                    };
                    case(_){ return (_ob, filled, remaining, fillPrice); };
                };
            };
        };
    };
    private func _popOrderPrice(_list: List.List<(Txid, OrderPrice)>, _temp: List.List<(Txid, OrderPrice)>, _condition: {#ge: Nat; #le: Nat; }) : 
    (list: List.List<(Txid, OrderPrice)>, temp: List.List<(Txid, OrderPrice)>) {
        var list = _list;
        var temp = _temp;
        var item = List.pop(list);
        switch(item.0){
            case(?(txid, orderPrice)){
                switch(_condition){
                    case(#ge(value)){
                        if (orderPrice.price >= value){
                            list := item.1;
                            temp := List.push((txid, orderPrice), temp);
                            return _popOrderPrice(list, temp, _condition);
                        }else {
                            return (list, temp);
                        };
                    };
                    case(#le(value)){
                        if (orderPrice.price <= value){
                            list := item.1;
                            temp := List.push((txid, orderPrice), temp);
                            return _popOrderPrice(list, temp, _condition);
                        }else {
                            return (list, temp);
                        };
                    };
                    // case(#txidEq(_txid)){
                    //     if (_txid == txid){
                    //         list := item.1;
                    //         return (list, temp);
                    //     }else{
                    //         list := item.1;
                    //         temp := List.push((txid, orderPrice), temp);
                    //         return _popOrderPrice(list, temp, _condition);
                    //     };
                    // };
                };
            };
            case(_){ return (list, temp) };
        };
    };
    private func _pushOrderPrice(_list: List.List<(Txid, OrderPrice)>, _temp: List.List<(Txid, OrderPrice)>) : List.List<(Txid, OrderPrice)>{
        var list = _list;
        var temp = _temp;
        var tempItem = List.pop(temp);
        switch(tempItem.0){
            case(?(txid, orderPrice)){
                temp := tempItem.1;
                list := List.push((txid, orderPrice), list);
                return _pushOrderPrice(list, temp);
            };
            case(_){ return list };
        };
    };

    private func _put(_ob: OrderBook, _txid: Txid, _orderPrice: OrderPrice, _UNIT_SIZE: Nat) : OrderBook{
        if (quantity(_orderPrice) < _UNIT_SIZE) {  return _ob; }; // drop
        switch(side(_orderPrice)){
            case(#Buy){
                var bid = _ob.bid;
                var temp: List.List<(Txid, OrderPrice)> = List.nil();
                let res = _popOrderPrice(bid, temp, #ge(_orderPrice.price));
                bid := res.0;
                temp := res.1;
                bid := List.push((_txid, _orderPrice), bid);
                bid := _pushOrderPrice(bid, temp);
                return { ask = _ob.ask; bid = bid };
            };
            case(#Sell){
                var ask = _ob.ask;
                var temp: List.List<(Txid, OrderPrice)> = List.nil();
                let res = _popOrderPrice(ask, temp, #le(_orderPrice.price));
                ask := res.0;
                temp := res.1;
                ask := List.push((_txid, _orderPrice), ask);
                ask := _pushOrderPrice(ask, temp);
                return { ask = ask; bid = _ob.bid };
            };
        };
    };

    public func create() : OrderBook{
        return { 
            ask = List.nil<(Txid, OrderPrice)>(); 
            bid = List.nil<(Txid, OrderPrice)>(); 
        };
    };

    public func level1(_ob: OrderBook) : Tick{
        var ask1: OrderPrice = {quantity = #Sell(0); price = 0; };
        switch(List.pop(_ob.ask).0){
            case(?(txid, orderPrice)){ ask1 := orderPrice; };
            case(_){};
        };
        var bid1: OrderPrice = {quantity = #Buy(0,0); price = 0; };
        switch(List.pop(_ob.bid).0){
            case(?(txid, orderPrice)){ bid1 := orderPrice; };
            case(_){};
        };
        return { bestAsk = _priceResponse(ask1); bestBid = _priceResponse(bid1); };
    };
    public func depth(_ob: OrderBook, _depth: ?Nat) : {ask: [PriceResponse]; bid: [PriceResponse]}{
        var ask = _ob.ask;
        var bid = _ob.bid;
        var depth_ = Option.get(_depth, 10);
        var askRes: [OrderPrice] = [];
        var bidRes: [OrderPrice] = [];
        var i: Nat = 0;
        var item = List.pop(ask);
        while(Option.isSome(item.0) and i < depth_){
            ask := item.1;
            i += 1;
            switch(item.0){
                case(?(txid, orderPrice)){ 
                    askRes := arrayAppend(askRes, [orderPrice]); 
                    item := List.pop(ask);
                };
                case(_){};
            };
        };
        i := 0;
        item := List.pop(bid);
        while(Option.isSome(item.0) and i < depth_){
            bid := item.1;
            i += 1;
            switch(item.0){
                case(?(txid, orderPrice)){ 
                    bidRes := arrayAppend(bidRes, [orderPrice]); 
                    item := List.pop(bid);
                };
                case(_){};
            };
        };
        return {ask = _priceResponseArr(askRes); bid = _priceResponseArr(bidRes)};
    };

    public func trade(_ob: OrderBook, _txid: Txid, _orderPrice: OrderPrice, _orderType: OrderType, _UNIT_SIZE: Nat) : {ob: OrderBook; filled: [OrderFilled]; remaining: OrderPrice; isPending: Bool; fillPrice: ?OrderPrice}{
        //assert(quantity(_orderPrice) > 0 and _orderPrice.price > 0);
        if (_orderPrice.price > 0){
            assert(quantity(_orderPrice) > 0);
        };
        // fill
        var _filled: [OrderFilled] = [];
        let (ob_, filled_, remaining_, fillPrice_) = _fill(_ob, _orderPrice, _filled, _UNIT_SIZE, null);
        // put
        var ob = ob_;
        var filled = filled_;
        var remaining = remaining_;
        var isPending: Bool = false;
        var fillPrice : ?OrderPrice = fillPrice_;
        if (_orderType == #LMT and quantity(remaining) >= _UNIT_SIZE ){
            ob := _put(ob, _txid, remaining, _UNIT_SIZE);
            isPending := true;
        } else if (_orderType == #FOK and quantity(remaining) >= _UNIT_SIZE ){
            ob := _ob;
            filled := [];
            remaining := _orderPrice;
            isPending := false;
            fillPrice := null;
        } else if (_orderType == #FAK and quantity(remaining) >= _UNIT_SIZE ){
            isPending := false;
        } else if (_orderType == #MKT ){
            isPending := false;
        };
        return {ob = ob; filled = filled; remaining = remaining; isPending = isPending; fillPrice = fillPrice;};
    };

    public func get(_ob: OrderBook, _txid: Txid) : ?OrderPrice{
        switch(List.find(_ob.ask, func (item:(Txid, OrderPrice)):Bool{ item.0 == _txid })){
            case(?(txid, orderPrice)){ return ?orderPrice; };
            case(_){
                switch(List.find(_ob.bid, func (item:(Txid, OrderPrice)):Bool{ item.0 == _txid })){
                    case(?(txid, orderPrice)){ return ?orderPrice; };
                    case(_){ return null; };
                };
            };
        };
    };

    public func inOrderBook(_ob: OrderBook, _txid: Txid) : Bool{
        var ask = _ob.ask;
        var bid = _ob.bid;
        return Option.isSome(List.find(bid, func (item:(Txid, OrderPrice)):Bool{ item.0 == _txid }))
            or Option.isSome(List.find(ask, func (item:(Txid, OrderPrice)):Bool{ item.0 == _txid }));
    };
    
    public func remove(_ob: OrderBook, _txid: Txid, _direction: ?OrderSide) : OrderBook{
        var ask = _ob.ask;
        var bid = _ob.bid;
        switch(_direction){
            case(?(#Buy)){
                bid := List.filter(bid, func (item:(Txid, OrderPrice)):Bool{ item.0 != _txid });
            };
            case(?(#Sell)){
                ask := List.filter(ask, func (item:(Txid, OrderPrice)):Bool{ item.0 != _txid });
            };
            case(_){
                bid := List.filter(bid, func (item:(Txid, OrderPrice)):Bool{ item.0 != _txid });
                ask := List.filter(ask, func (item:(Txid, OrderPrice)):Bool{ item.0 != _txid });
            };
        };
        return { ask = ask; bid = bid; };
    };

    /// Warning: Do not call clear() lightly. Calling this method may result in inconsistent order status data.
    public func clear(_ob: OrderBook) : OrderBook{
        return { 
            ask = List.nil<(Txid, OrderPrice)>(); 
            bid = List.nil<(Txid, OrderPrice)>(); 
        };
    };

    /// KLine: create
    public func createK() : KLines{
        return Trie.empty(); 
    };
    public func putK(_kl: KLines, _ki: KInterval, _price: Nat, _vol: Nat): KLines{
        let kid = _now() / _ki;
        var kl = _kl;
        switch(Trie.get(kl, keyn(_ki), Nat.equal)){
            case(?(kline)){
                var klineData = kline;
                switch(Deque.popFront(klineData)){
                    case(?(kbar, klineTemp)){
                        if (kid > kbar.kid){ // new kbar
                            klineData := Deque.pushFront(klineData, {kid = kid; open = _price; high = _price; low = _price; close = _price; vol = _vol; updatedTs = _now()});
                        }else if (kid == kbar.kid){ // update
                            klineData := Deque.pushFront(klineTemp, {kid = kid; open = kbar.open; high = Nat.max(kbar.high, _price); low = Nat.min(kbar.low, _price); close = _price; vol = kbar.vol + _vol; updatedTs = _now()});
                        }else{
                            // History bar cannot be modified.
                        };
                    };
                    case(_){ // new kbar
                        klineData := Deque.pushFront(klineData, {kid = kid; open = _price; high = _price; low = _price; close = _price; vol = _vol; updatedTs = _now()});
                    };
                };
                if (List.size(klineData.0) + List.size(klineData.1) > NumberCachedBars){
                    switch(Deque.popBack(klineData)){
                        case(?(klineNew, item)){ klineData := klineNew; };
                        case(_){};
                    };
                };
                kl := Trie.put(kl, keyn(_ki), Nat.equal, klineData).0;
            };
            case(_){ // new kbar
                var klineData: Deque.Deque<KBar> = Deque.empty();
                klineData := Deque.pushFront(klineData, {kid = kid; open = _price; high = _price; low = _price; close = _price; vol = _vol; updatedTs = _now()});
                kl := Trie.put(kl, keyn(_ki), Nat.equal, klineData).0;
            };
        };
        return kl;
    };
    /// KLine: putBatch
    public func putBatch(_kl: KLines, _filled: [OrderFilled], _UNIT_SIZE: Nat) : KLines {
        var kl = _kl;
        for (item in _filled.vals()){
            var quantity : Nat = 0;
            var amount : Nat = 0;
            switch(item.token0Value){
                case(#DebitRecord(v)){ quantity := v; };
                case(#CreditRecord(v)){ quantity := v; };
                case(_){};
            };
            switch(item.token1Value){
                case(#DebitRecord(v)){ amount := v; };
                case(#CreditRecord(v)){ amount := v; };
                case(_){};
            };
            if (quantity > 0){
                let price = amount * _UNIT_SIZE / quantity;
                kl := putK(kl, 60, price, quantity); // 1min
                kl := putK(kl, 60*5, price, quantity); // 5mins
                kl := putK(kl, 3600, price, quantity); // 1h
                kl := putK(kl, 3600*24, price, quantity); // 1d
                kl := putK(kl, 3600*24*7, price, quantity); // 1w
                kl := putK(kl, 3600*24*30, price, quantity); // 1m
            };
        };
        return kl;
    };
    /// KLine: get
    public func getK(_kl: KLines, _ki: KInterval) : [KBar]{
        switch(Trie.get(_kl, keyn(_ki), Nat.equal)){
            case(?(kline)){
                return arrayAppend(List.toArray(kline.0), List.toArray(List.reverse(kline.1)));
            };
            case(_){ return []; };
        };
    };

};
