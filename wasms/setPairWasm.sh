#!/usr/local/bin/ic-repl -r ic
identity default "~/.config/dfx/identity/${IdentityName:-default}/identity.pem";
import icdexRouter = "${ICDexRouterCanisterId}" as "Router.did";
call icdexRouter.setICDexPairWasm(file("ICDexPair.wasm.gz"),"${ICDexPairVersion}", null);