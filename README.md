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
| `Env` | Reads `.lattice/env.json`: `addr(name)`, `implementation(name)`, `staged(name)` (an implementation deployed but not yet live, which is what an upgrade plan proposes), and `str` / `uint256_` / `bool_` for params. |
| `Erc7821`, `Timelock`, `MultiSend` | The encoders for Solady Timelock batches and Safe `MultiSendCallOnly`. |

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
