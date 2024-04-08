#!/usr/local/bin/ic-repl -r ic
identity default "~/.config/dfx/identity/${IdentityName:-default}/identity.pem";
import icdexRouter = "${ICDexRouterCanisterId}" as "Router.did";
let payload = encode icdexRouter.setICDexMakerWasm(file("ICDexMaker.wasm.gz"),"${ICDexMakerVersion}", null);
export "proposalMakerPayload";