# `Env`: reading the address book

Before every forge run — a deploy script, a plan's `build()`, a test — Lattice materializes the
environment's book at `.lattice/env.json` in the checkout: the contracts by name, their
implementations (and any the current release has deployed but not yet made live), the scalar
params, the authority. `Env` reads it. Every function takes a name or key as written in the book.

| Function | Reads | Use it when |
|---|---|---|
| `addr(name)` | `contracts.<name>.address` | You need the anchor — the proxy, beacon or singleton — a call targets. |
| `implementation(name)` | `contracts.<name>.implementation.address` | You need what the proxy runs as the book records it: a pre-upgrade check, or a plan that compares old and new. |
| `staged(name)` | `contracts.<name>.implementation.staged.address` | An upgrade plan: the implementation this release deployed and has not yet pointed the proxy at. Reverts when nothing is staged — see `hasStaged`. |
| `has(name)` | whether `contracts.<name>` exists | A check that must not revert on a missing entry. |
| `hasStaged(name)` | whether `contracts.<name>.implementation.staged` exists | A pre-deploy check asserting nothing is staged yet; a plan deciding between a staged and a recorded implementation. |
| `authority()` | `authority.address` | The Protocol Safe (or the EOA on a testnet): the account that holds admin roles, the sender of direct calls. |
| `authorityOwners()`, `authorityThreshold()` | `authority.owners`, `authority.threshold` | Safe-administration releases and their checks. Empty and zero when the book records none. |
| `chainId()` | `chainId` | Guards in a script that must not run on the wrong chain. |
| `str(key)` | `params.<key>` as recorded | Any param; everything else below parses this string. |
| `addr_(key)` | an address param | Most params are addresses: `Env.addr_("chainlinkDataStore")`. |
| `bool_(key)`, `uint256_(key)`, `int256_(key)`, `bytes32_(key)`, `bytes_(key)` | scalar params | Typed reads. |
| `uint8_` … `uint128_(key)` | narrow unsigned params | A struct field like `uint16 resultLength` or `uint32 livenessWindow`: range-checked, so a value that does not fit reverts with `lattice-std: param <key> does not fit its type` instead of truncating as a cast would. |

Params are always strings in the book; Lattice writes them that way and a release's `envUpdates()`
returns them that way ([scripts.md](./scripts.md)).

## When the book is not there

`Env` reverts when `.lattice/env.json` is missing — a script run outside Lattice, or a plain
`forge test` over the repository. Scripts should not run outside Lattice at all. Tests inherit
`LatticeTest` and call `skipUnlessMaterialized()` first ([testing.md](./testing.md)), so a
repository's own `forge test` skips them rather than failing.

The repository's `foundry.toml` needs `fs_permissions = [{ access = "read", path = ".lattice/" }]`
for any of this to work.
