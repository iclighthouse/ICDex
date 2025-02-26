# ICDex

## Instruction

ICDex is an order book DEX built on the IC network and supports the token standards ICRC1 and DRC20.  
ICDex can be deployed on the IC main network or on a local test network. Due to ICDex's dependency on the DRC205 instance (canister-id: lw5dr-uiaaa-aaaak-ae2za-cai) and the ICLighthouse NFT (canister-id: goncb-kqaaa-aaaap-aakpa-cai) on the IC main network, locally deployed instances will not synchronize transaction records to the DRC205 instance (they will be cached locally) and will not be able to use features that require ICLighthouse NFTs as qualification (you can deploy a collection of NFTs locally). These features are non-core and have a low impact on testing.

OrderBook: https://github.com/iclighthouse/ICDex/blob/main/OrderBook.md

ICDex Infrastructure:

![Matching engine](img/icdex.png)


## Dependent toolkits

### dfx
- https://github.com/dfinity/sdk/
- version: 0.21.0 (https://github.com/dfinity/sdk/releases/tag/0.21.0)
- moc version: 0.11.1

### vessel
- https://github.com/dfinity/vessel
- version: 0.7.0 (https://github.com/dfinity/vessel/releases/tag/v0.7.0)

### ic-wasm
- https://github.com/dfinity/ic-wasm
- version: 0.7.0 (https://github.com/dfinity/ic-wasm/releases/tag/0.7.0)

### ic-repl
- https://github.com/dfinity/ic-repl/
- version: 0.6.2 (https://github.com/dfinity/ic-repl/releases/tag/0.6.2)
- Install to the directory `/usr/local/bin/ic-repl`

## Tokens for testing

### 1. ICLtest
```
dfx canister --network ic create ICLtest --controller __your principal__
dfx build --network ic ICLtest
dfx canister --network ic install ICLtest --argument '(record { totalSupply=100000000000000000; decimals=8; fee=1000000; name=opt "ICLtest"; symbol=opt "ICLtest"; metadata=null; founder=null;}, true)'
```

### 2. Token0
```
dfx canister --network ic create Token0 --controller __your principal__
dfx build --network ic Token0
dfx canister --network ic install Token0 --argument '(record { totalSupply=100000000000000000; decimals=8; fee=10000; name=opt "Token0"; symbol=opt "Token0"; metadata=null; founder=null;}, true)'
```

### 3. Token1
```
dfx canister --network ic create Token1 --controller __your principal__
dfx build --network ic Token1
dfx canister --network ic install Token1 --argument '(record { totalSupply=100000000000000000; decimals=8; fee=10000; name=opt "Token1"; symbol=opt "Token1"; metadata=null; founder=null;}, true)'
```

## Compiles

### 1. ICDexRouter
```
dfx canister --network ic create ICDexRouter --controller __your principal__
dfx build --network ic ICDexRouter
cp -f .dfx/ic/canisters/ICDexRouter/ICDexRouter.wasm.gz wasms/
```
- Code: "src/ICDexRouter.mo"
- Module hash: f06196d7079f691ea2dc7773088158c54c210fa219c044e0b44ae2c31d26d118
- Version: 0.12.40
- Build: {
    "args": "--compacting-gc",
    "gzip": true
}

### 2. ICDexPair
```
dfx canister --network ic create ICDexPair --controller __your principal__
dfx build --network ic ICDexPair
cp -f .dfx/ic/canisters/ICDexPair/ICDexPair.wasm.gz wasms/
```
- Code: "src/ICDexPair.mo"
- Module hash: ea736e503a580116acccecba7f84557dfb6123f08a45c14efc266ebce8b92e02
- Version: 0.12.68
- Build: {
    "args": "--incremental-gc",
    "gzip": true
}

### 3. ICDexMaker
```
dfx canister --network ic create ICDexMaker --controller __your principal__
dfx build --network ic ICDexMaker
cp -f .dfx/ic/canisters/ICDexMaker/ICDexMaker.wasm.gz wasms/
```
- Code: "src/ICDexMaker.mo"
- Module hash: 76933ea4ec09ad0e2c7863003b75ba5de863fbe62dbcbd5db3f6d694f59b85cd
- Version: 0.5.16
- Build: {
    "args": "--compacting-gc",
    "gzip": true
}

## Deployment of ICDex

### 1. Deploy ICDexRouter
```
dfx canister --network ic install ICDexRouter --argument '(principal "__dao-canister-id or your-principal__", true)'
```
- args:
    - initDAO: Principal.  // Owner (DAO) principal. You can fill in your own Principal when testing.
    - isDebug: Bool

### 2. (optional) Config ICDexRouter
- call ICDexRouter.sys_config()
```
dfx canister --network ic call ICDexRouter sys_config '(record{ sysToken = opt principal "__ICLtest-canistter-id__"; sysTokenFee = opt 1000000 })'
```
- args: 
```
{
    aggregator: ?Principal; // External trading pair aggregator. If not configured, it will not affect use.
    blackhole: ?Principal; // Black hole canister, which can be used as a controller for canisters to monitor their cycles and memory.
    icDao: ?Principal; // The canister that governs ICDex is assigned the value initDAO at installation. a private principal can be filled in at test time.
    nftPlanetCards: ?Principal; // ICLighthouse NFT.
    sysToken: ?Principal; // ICDex governance token canister-id.
    sysTokenFee: ?Nat; // smallest units. Transfer fee for ICDex governance token.
    creatingPairFee: ?Nat; // smallest units. The fee to be paid for creating a trading pair by pubCreate().
    creatingMakerFee: ?Nat; // smallest units. The fee to be paid for creating an automated market maker pool canister.
}
```

### 3. Set ICDexPair wasm
- call ICDexRouter.setICDexPairWasm()
```
dfx canister --network ic call ICDexRouter setICDexPairWasm '(__ICDexPair.wasm bytes([nat8])__, "__ICDexPair version__", null)'
```
Or use ic-repl (/usr/local/bin/ic-repl)  
Note: Local network using setPairWasm_local.sh
```
export IdentityName=default
export ICDexRouterCanisterId=__ICDexRouter-canister-id__
export ICDexPairVersion=__ICDexPair-version__
chmod +x  wasms/setPairWasm.sh
wasms/setPairWasm.sh
```

### 4. Create trading pair
- call ICDexRouter.create()
```
dfx canister --network ic call ICDexRouter create '(principal "__Token0-canister-id__", principal "__Token1-canister-id__", __opning-time-nanoseconds__, null, null)'
```
- args:
    - token0: Principal // base token canister-id
    - token1: Principal // quote token canister-id
    - openingTimeNS: Time.Time // Set the time in nanoseconds when the pair is open for trading. If an IDO needs to be started, it is recommended that at least 4 days be set aside.
    - unitSize: ?Nat64 // (optional) UNIT_SIZE: It is the base number of quotes in the trading pair and the minimum quantity to be used when placing an order. The quantity of the order placed must be an integer multiple of UNIT_SIZE. E.g., 1000000
    - initCycles: ?Nat // (optional) The amount of cycles added for the newly created trading pair.
- returns:
    - res: Principal // Trading pair cansiter-id

### 5. trade
- call ICDexPair.trade()
```
dfx canister --network ic call Token0 icrc2_approve '(record{ spender = record{owner = principal "__ICDexPair-canister-id__"; subaccount = null }; amount = 10_000_000_000 })'
dfx canister --network ic call Token1 icrc2_approve '(record{ spender = record{owner = principal "__ICDexPair-canister-id__"; subaccount = null }; amount = 10_000_000_000 })'
dfx canister --network ic call __ICDexPair-canister-id__ trade '(record{ quantity = variant{Buy = record{500_000_000: nat; 500_000_000: nat} }; price = 10_000_000: nat }, variant{ LMT }, null, null, null, null)'
dfx canister --network ic call __ICDexPair-canister-id__ trade '(record{ quantity = variant{Sell = 100_000_000: nat }; price = 10_000_000: nat }, variant{ LMT }, null, null, null, null)'
```
args: see `docs/ICDexPair.md` documentation.

### 6. (optional) Set ICDexMaker wasm
- call ICDexRouter.setICDexMakerWasm()
```
dfx canister --network ic call ICDexRouter setICDexMakerWasm '(__ICDexMaker.wasm bytes([nat8])__, "__ICDexMaker version__", null)'
```
Or use ic-repl (/usr/local/bin/ic-repl)  
Note: Local network using setMakerWasm_local.sh
```
export IdentityName=default
export ICDexRouterCanisterId=__ICDexRouter-canister-id__
export ICDexMakerVersion=__ICDexMaker-version__
chmod +x  wasms/setMakerWasm.sh
wasms/setMakerWasm.sh
```

### 7. (optional) Create ICDexMaker (OAMM) for trading pair

#### Step 1. call maker_create() 
Note: Requires the trading pair to complete at least one trade.
- call ICDexRouter.maker_create()
```
dfx canister --network ic call ICDexRouter maker_create '(record{ pair = principal "__ICDexPair-canister-id__"; allow = variant{Public}; name = "MakerTest1"; lowerLimit = 1; upperLimit = 10_000_000_000_000; spreadRate = 10_000; threshold = 1_000_000_000_000; volFactor = 2; creator = null })'
```
- args: 
```
{
    pair: Principal; // Trading pair caniser-id.
    allow: {#Public; #Private}; // Visibility. #Public / #Private.
    name: Text; // Name. e.g. "AAA_BBB AMM-1"
    lowerLimit: Nat; // Lower price limit. How much token1 (smallest units) are needed to purchase UNIT_SIZE token0 (smallest units).
    upperLimit: Nat; // Upper price limit. How much token1 (smallest units) are needed to purchase UNIT_SIZE token0 (smallest units).
    spreadRate: Nat; // ppm. Inter-grid spread ratio for grid orders. e.g. 10_000, it means 1%. It will create 2 grid strategies, the second strategy has a spreadRate that is 5 times this value.
    threshold: Nat; // token1 (smallest units). e.g. 1_000_000_000_000. After the total liquidity exceeds this threshold, the LP adds liquidity up to a limit of volFactor times his trading volume.
    volFactor: Nat; // LP liquidity limit = LP's trading volume * volFactor.  e.g. 2
    creator: ?AccountId; // Specify the creator.
}
```
- returns:
    - res: Principal // ICDexMaker cansiter-id

#### Step 2. Make ICDexMaker get the vip-maker role to create/update a grid order for free. 
- call ICDexRouter.pair_setVipMaker()
```
dfx canister --network ic call ICDexRouter pair_setVipMaker '(principal "__ICDexPair-canister-id__", "__ICDexMaker-canister-id__", 90)'
```

#### Step 3. The creator activates ICDexMaker by adding the first liquidity
The creator activates ICDexMaker by adding the first liquidity.
The first liquidity must be added by the creator, requiring the amount of token0 to be greater than token0_fee * 100000, and the amount of token1 to be greater than token1_fee * 100000.

- call ICDexMaker.add()
```
dfx canister --network ic call __ICDexMaker-canister-id__ add '(10_000_000_000: nat, 10_000_000_000: nat, null)'
```

## Security items that need to be configured through proposals after launching on SNS

### System configurations

- ICDexRouter.sys_config().  
Where icDAO is to be configured as SNS governance canister-id and sysToken is to be configured as ICL ledger canister-id issued.

### Controllers (Owners) of canisters

(Note: Impact on security of funds.)

ICDexRouter is controlled by SNS governance canister, the list of ICDexPair and ICDexMaker can be queried by getPairs(), maker_getPublicMakers(), maker_getPrivateMakers() of ICDexRouter.

- Controllers of ICDexPair
Trading pairs (ICDexPair) listed before the launch of SNS may have controllers that contain the developer's principal and need to be rechecked and reset.
    - ICDexRouter.setControllers().

- Controllers of ICDexMaker
OAMMs (ICDexMaker) created before the launch of SNS may have controllers that contain the developer's principal and need to be rechecked and reset.
    - ICDexRouter.maker_setControllers().

### ICTC Admins

(Note: Impact on security of funds.)

By default, ICTC Admins are not added. ictc Admins are authorized to provide fast manual compensation for failed ICTC transaction orders, and it is generally not recommended to authorize them in this way. The ICTC related methods are invoked directly through DAO governance under normal circumstances.

- Query ICTC Admins
    - ICDexPair.ictc_getAdmins()
    - ICDexMaker.ictc_getAdmins()
- Add/remove ICTC Admins (through DAO proposal)
    - ICDexPair.ictc_addAdmin()
    - ICDexMaker.ictc_addAdmin()
    - ICDexPair.ictc_removeAdmin()
    - ICDexMaker.ictc_removeAdmin()

### Creators of ICDexPair and ICDexMaker

Creator has no special permissions, except the following.
- Creator of public ICDexMaker: He needs to add the first liquidity to ICDexMaker to activate it.
- Creator of private ICDexMaker: He has access to his private ICDexMaker for upgrades and such.

### Funder of IDO

For IDO-enabled trading pairs, set up a project-side Funder account via the DAO proposal, who can configure IDO parameters and place orders during the validity period. This permission will be invalidated once the trading pair has officially started trading.
- Query: ICDexPair.IDO_getConfig()
- Set (through DAO proposal): ICDexRouter.pair_IDOSetFunder()

### Funder of AuctionMode

When a trading pair is set up in Auction mode via the DAO proposal, a Funder is specified and only he can place sell orders, other users can only place buy orders.
- Query: ICDexPair.getAuctionMode()
- Set (through DAO proposal): ICDexRouter.pair_setAuctionMode()


## Docs

https://github.com/iclighthouse/ICDex/tree/main/docs

## Implementation

### ICDex UI
- ICLight: https://iclight.io
- For security reasons, it is recommended to deploy your own front-end or access it via APIs.

### DEX Explorer
- ICHouse: https://ic.house/swaps

### Canisters

- ICDexRouter (Testnet)
    - Canister-id: pymhy-xyaaa-aaaak-act7a-cai

## Disclaimer

The project may have undiscovered defects, and you may face technical risks, counterparty risks, legal risks, hacker attacks and many other risks in using it, you need to fully understand the project before using it, and bear all the risks of using it by yourself.

ICLighthouse is a community-driven decentralised project, which is considered a community collaboration dedicated to developing infrastructure on IC. ICLighthouse is provided “as is”, and utilized at your own risk and responsibility without any guarantee. ICLighthouse token ICL is only used for governance and utility, and no team or individual guarantees its value. Therefore, before utilizing this service you should review its documentation and codes carefully to fully understand its functioning and the risks that could entail the usage of a service built on open protocols on an autonomous blockchain network (the Internet Computer). No individual, entity, developer (internal to the founding team, or from the ICLighthouse community), or ICLighthouse itself will be considered liable for any damages or claims related to the usage, interaction, or lack of functioning associated with the ICLighthouse, its interfaces, or websites. This includes loss of profits, assets of any value, or indirect, incidental, direct, special, exemplary, punitive or consequential damages. The same applies to the usage of ICLighthouse through third-party interfaces or applications that integrate/surface it. It is your responsibility to manage the risk of your activities and usage on said platforms/protocols. Utilizing this project/protocol may not comply with the requirements of certain regional laws. You are requested to comply with local laws and to assume all legal consequences arising from its use.
