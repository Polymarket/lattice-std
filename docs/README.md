# lattice-std documentation

lattice-std is what a contract repository imports to work with [Lattice](https://github.com/Polymarket/lattice),
Polymarket's staged deployer and governance execution tool. Two Solidity files, no dependencies:

| File | Holds | Read |
|---|---|---|
| `src/Lattice.sol` | The structs a release script returns (`Call`, `Deployment`, `EnvVar`), the encoders for Solady Timelock batches and Safe `MultiSendCallOnly` (`Erc7821`, `Timelock`, `MultiSend`), and `Env`, the reader of the address book Lattice materializes. | [scripts.md](./scripts.md), [encoders.md](./encoders.md), [env.md](./env.md) |
| `src/LatticeTest.sol` | `LatticeTest`, the base for a release's pre- and post-checks and for safe-sim-style simulations. | [testing.md](./testing.md) |

The short version of when to reach for what:

- **Writing a release** (a folder under `script/releases/<name>/` with a `release.json` and one script per step): the scripts return the structs in [scripts.md](./scripts.md) and read addresses through `Env` ([env.md](./env.md)). They do not encode Safe or timelock calldata — Lattice does that from the plan they return.
- **Writing the release's checks** (forge tests the `verify` steps run before and after each state change): inherit `LatticeTest` ([testing.md](./testing.md)) and forge-std's `Test`, read everything through `Env`, assert with forge-std.
- **Simulating a governance operation without Lattice** (what safe-sim does): `LatticeTest` again, with `applyAsAuthority` and the encoders ([encoders.md](./encoders.md)) to apply the plan yourself under `prank`.

A consumer matches on ABI shape, never on a type's name or import path, so nothing here is required — a plan may declare the structs itself. The libraries are conveniences with fixed, tested encodings, and `test/differential` in the Lattice repository holds them byte for byte to Lattice's own Go encoders.
