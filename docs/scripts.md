# Release scripts

A release is a folder in the contract repository — `script/releases/<name>/` — holding a
`release.json` manifest and one forge script per step that touches the chain. Lattice runs the
scripts; this page is about what they return.

## Entry points and their shapes

| Step kind | Function Lattice calls | Returns | Use it for |
|---|---|---|---|
| `deploy` | `deploy()` | `Deployment[]` | Creating contracts. Each `Deployment{name, addr}` names an address for the book: `name` is the book's contract name (`"chainlinkReporterModuleImpl"` with a `bindings` entry in the manifest saying it is `chainlinkReporterModule`'s implementation) and `addr` what the broadcast created. Deploy inside `vm.startBroadcast()` / `vm.stopBroadcast()`; Lattice signs as `--deployer`. |
| `propose`, `execute` | `build()` | `Call[]` | A governance plan: the calls the authority's route will carry — through the timelock for `owner`-routed targets, directly for `admin` / `direct` ones. Return the inner calls only (`Call{to, value, data}` per target); Lattice routes and encodes them, computes the operation id and the Safe transaction, and preflights the result. An empty plan is refused. |
| `script` with `envUpdates` | `envUpdates()` | `EnvVar[]` | Scalar params the release changes in the book: `EnvVar{key, value}` with the value as a decimal, hex, bool or address string. |

```solidity
import { Call, Deployment, Env } from "lattice-std/Lattice.sol";

contract DeployReporterImplementation {
    function deploy() external returns (Deployment[] memory out) {
        address dataStore = Env.addr_("chainlinkDataStore");
        vm.startBroadcast();
        ChainlinkReporterModule impl = new ChainlinkReporterModule{ salt: 0 }(dataStore);
        vm.stopBroadcast();
        out = new Deployment[](1);
        out[0] = Deployment({ name: "chainlinkReporterModuleImpl", addr: address(impl) });
    }
}

contract UpgradeReporter {
    function build() external view returns (Call[] memory calls) {
        calls = new Call[](1);
        calls[0] = Call({
            to: Env.addr("chainlinkReporterModule"),
            value: 0,
            data: abi.encodeCall(IUUPS.upgradeToAndCall, (Env.staged("chainlinkReporterModule"), ""))
        });
    }
}
```

## Rules worth knowing

- **Read the book, never a literal.** `Env.addr`, `Env.implementation`, `Env.staged` and the param readers ([env.md](./env.md)) make one script run on every environment, and let Lattice's materialized overlay show a later step what an earlier one produced: an upgrade's `build()` reads `Env.staged(name)`, the implementation the deploy step just landed.
- **A plan is the inner calls.** Do not wrap them in `Timelock.propose(...)` or `Safe.execTransaction(...)`: the route is the book's and the encoding is Lattice's, so the same `build()` serves `propose` and `execute`, and the second reviewer's `verify plan` can re-derive it.
- **Deterministic where it matters.** CREATE2 / CREATE3 deployments land at the same address on a fork and on the chain; a plain CREATE moves with the deployer's nonce, which Lattice records by position in the creation sequence.
- **No secrets, no RPC URLs.** Scripts read `.lattice/env.json` and the chain; signing is Lattice's (`--deployer`, `--sender`).
