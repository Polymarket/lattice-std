# lattice-std

The structs and encoders a governance plan or deploy script uses in a contract repository's forge scripts. It's one file, `src/Lattice.sol`, with no dependencies.

What a script returns is matched on ABI shape, never on a type's name or import path. So nothing here is required: a script may declare the structs itself. The library exists so plans and deploy scripts share one definition with fixed, tested encodings.

## Install

```shell
forge install Polymarket/lattice-std
```

Add the remapping (in `foundry.toml` or `remappings.txt`):

```
lattice-std/=lib/lattice-std/src/
```

Give forge read access to the environment written before every run:

```toml
fs_permissions = [{ access = "read", path = "./.lattice" }]
```

## What it provides

| | |
|---|---|
| `Call` | `{to, value, data}`: the unit of a governance plan. A plan's `build()` returns `Call[]`. |
| `Deployment` | `{name, addr}`: what a deploy script's entry point returns, naming each address for the address book. |
| `EnvVar` | `{key, value}`: one scalar param, for a step that updates params. |
| `Env` | Reads `.lattice/env.json`: `addr(name)`, `implementation(name)`, `staged(name)` (an implementation deployed but not yet live, which is what an upgrade plan proposes), `has(name)` and `hasStaged(name)`; `str`, `addr_`, `bool_`, `uint256_`, `int256_`, `bytes32_`, `bytes_` and the range-checked `uint8_` … `uint128_` for params; `chainId()`; and the governing account, `authority()`, with the owner set and threshold the book expects of a Safe, `authorityOwners()` and `authorityThreshold()` (empty and zero when none is recorded). What a release's pre- and post-checks read. |
| `Erc7821`, `Timelock`, `MultiSend` | The encoders for Solady Timelock batches and Safe `MultiSendCallOnly`. |
| `LatticeTest` (`src/LatticeTest.sol`) | A base for a release's pre- and post-checks and for safe-sim-style simulations: `materialized()` / `skipUnlessMaterialized()`, `liveImplementation(name)` and the ERC-1967 slots, `timelock()`, `governedAsDeclared(target)`, `operationId(calls, predecessor, salt)`, and `callAs` / `proposeAs` / `executeAs` / `applyAsAuthority` to apply a plan under `prank`. Readers and helpers only — assertions are the test's — so it still depends on nothing. |

```solidity
import { Call, Env } from "lattice-std/Lattice.sol";

contract UpgradeExchange is Script {
    function build() external view returns (Call[] memory calls) {
        calls = new Call[](1);
        calls[0] = Call(Env.addr("exchange"), 0, abi.encodeCall(IUUPS.upgradeToAndCall, (Env.staged("exchange"), "")));
    }
}
```

An empty plan is refused.

## Development

```shell
forge fmt --check && forge test   # format and tests
./bash/check-coverage.sh          # 100% lines, statements, branches and functions on src/
```

`script/Differential.s.sol` runs every encoder over one input document, so another implementation can compare its encodings byte for byte. Its output is part of the library's interface.
