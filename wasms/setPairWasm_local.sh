#!/usr/local/bin/ic-repl
identity default "~/.config/dfx/identity/${IdentityName:-default}/identity.pem";
import icdexRouter = "${ICDexRouterCanisterId}" as "Router.did";
call icdexRouter.setWasm(file("ICDexPair.wasm"),"${ICDexPairVersion}", false, true);