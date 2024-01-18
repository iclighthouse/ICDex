#!/usr/local/bin/ic-repl
identity default "~/.config/dfx/identity/${IdentityName:-default}/identity.pem";
import icdexRouter = "${ICDexRouterCanisterId}" as "Router.did";
call icdexRouter.maker_setWasm(file("ICDexMaker.wasm"),"${ICDexMakerVersion}", false, true);