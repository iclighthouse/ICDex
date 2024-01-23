#!/usr/local/bin/ic-repl
identity default "~/.config/dfx/identity/${IdentityName:-default}/identity.pem";
import icdexRouter = "${ICDexRouterCanisterId}" as "Router.did";
call icdexRouter.setICDexPairWasm(file("ICDexPair.wasm"),"${ICDexPairVersion}", null);