# ICDex

## Instruction

ICDex is an order book DEX built on the IC network and supports the token standards ICRC1 and DRC20.  
ICDex can be deployed on the IC main network or on a local test network. Due to ICDex's dependency on the DRC205 instance (canister-id: lw5dr-uiaaa-aaaak-ae2za-cai) and the ICLighthouse NFT (canister-id: goncb-kqaaa-aaaap-aakpa-cai) on the IC main network, locally deployed instances will not synchronize transaction records to the DRC205 instance (they will be cached locally) and will not be able to use features that require ICLighthouse NFTs as qualification (you can deploy a collection of NFTs locally). These features are non-core and have a low impact on testing.

OrderBook: https://github.com/iclighthouse/ICDex/blob/main/OrderBook.md

## Deployment

### 1. Deploy ICDexRouter
- args:
    - initDAO: Principal.  // Owner (DAO) principal

### 2. (optional) Config ICDexRouter
- call sys_config()
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
- call setWasm()
- args:
    - wasm: Blob // wasm file. Tools: https://ic.house/tools
    - version: Text // version.  e.g. "v0.1.0"
    - append: Bool // Default is false, if the wasm file is more than 2M, and needs to be uploaded in more than one block, except for the first block, the rest of the blocks should be filled with true.
    - backup: Bool // Whether to back up the previous version.

If the wasm file exceeds 2M, you can use the ic-wasm tool to compress it.

### 4. Create trading pair
- call create()
- args:
    - token0: Principal // base token canister-id
    - token1: Principal // quote token canister-id
    - unitSize: ?Nat64 // (optional) UNIT_SIZE: It is the base number of quotes in the trading pair and the minimum quantity to be used when placing an order. The quantity of the order placed must be an integer multiple of UNIT_SIZE. E.g., 1000000
    - initCycles: ?Nat // (optional) The amount of cycles added for the newly created trading pair.
- returns:
    - res: Principal // Trading pair cansiter-id

### 5. (optional) Enable IDO
- call pair_IDOSetFunder()
- args:
    - app: Principal // Trading pair cansiter-id
    - funder: ?Principal // Add IDO's Funder
    - requirement: ?ICDexPrivate.IDORequirement // Default configuration, can be filled with null. Refer to the IDO section of the ICDexPair documentation.

### 6. Open trading pair (could specify the opening time)
- call pair_pause()
- args:
    - app: Principal // Trading pair cansiter-id
    - pause: Bool // 'false' means opening (if openingTime is specified, it will be opened at openingTime), and true means pausing.
    - openingTime: ?Time.Time // (optional) If IDO is turned on, openingTime needs to be specified as the IDO end time.

### 7. (optional) Set ICDexMaker wasm
- call maker_setWasm()
- args:
    - wasm: Blob // wasm file. Tools: https://ic.house/tools
    - version: Text // version.  e.g. "v0.1.0"
    - append: Bool // Default is false, if the wasm file is more than 2M, and needs to be uploaded in more than one block, except for the first block, the rest of the blocks should be filled with true.
    - backup: Bool // Whether to back up the previous version.

### 8. (optional) Create ICDexMaker for trading pair
#### Step 1. call maker_create() // Requires the trading pair to complete at least one trade.
- args: 
```
{
    pair: Principal; // Trading pair cansiter-id
    allow: {#Public; #Private}; // Public or Private
    name: Text; // name, e.g. "AAA_BBB DeMM-1"
    lowerLimit: Nat; // Price (How much token1 (smallest units) are needed to purchase UNIT_SIZE token0 (smallest units).)
    upperLimit: Nat; // Price
    spreadRate: Nat; // ppm. e.g. 10_000 means 0.01
    threshold: Nat; // e.g. 1_000_000_000_000 token1, After the total liquidity exceeds this threshold, the LP adds liquidity up to a limit of volFactor times his trading volume.
    volFactor: Nat; // e.g. 2
}
```
#### Step 2. Preparing requirements for creating a grid order (with at least one requirement)
- Make ICDexMaker get the vip-maker role via NFT bindings to create/update a grid order for free. 
- Deposit enough ICLs to ICDexMaker as fees for creating/updating a grid order.

#### Step 3. The creator activates ICDexMaker by adding the first liquidity
The creator activates ICDexMaker by adding the first liquidity.
The first liquidity must be added by the creator, requiring the amount of token0 to be greater than token0_fee * 100000, and the amount of token1 to be greater than token1_fee * 100000.


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
    - Module hash: 12276010bf5b7bcee72ed5fcf22446555bfb1af679d96cf54a3c5a2bc6be50c7
    - Version: 0.12.21
    - DFX version: 0.15.0 (moc 0.9.7)
    - Build: {
        "args": "--compacting-gc"
    }

## Disclaimer

The project may have undiscovered defects, and you may face technical risks, counterparty risks, legal risks, hacker attacks and many other risks in using it, you need to fully understand the project before using it, and bear all the risks of using it by yourself.

ICLighthouse is a community-driven decentralised project, which is considered a community collaboration dedicated to developing infrastructure on IC. ICLighthouse is provided “as is”, and utilized at your own risk and responsibility without any guarantee. ICLighthouse token ICL is only used for governance and utility, and no team or individual guarantees its value. Therefore, before utilizing this service you should review its documentation and codes carefully to fully understand its functioning and the risks that could entail the usage of a service built on open protocols on an autonomous blockchain network (the Internet Computer). No individual, entity, developer (internal to the founding team, or from the ICLighthouse community), or ICLighthouse itself will be considered liable for any damages or claims related to the usage, interaction, or lack of functioning associated with the ICLighthouse, its interfaces, or websites. This includes loss of profits, assets of any value, or indirect, incidental, direct, special, exemplary, punitive or consequential damages. The same applies to the usage of ICLighthouse through third-party interfaces or applications that integrate/surface it. It is your responsibility to manage the risk of your activities and usage on said platforms/protocols. Utilizing this project/protocol may not comply with the requirements of certain regional laws. You are requested to comply with local laws and to assume all legal consequences arising from its use.
