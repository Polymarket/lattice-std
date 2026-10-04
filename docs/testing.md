# `LatticeTest`: a release's checks, before and after

A release's tests are forge tests in its folder — `script/releases/<name>/test/*.t.sol` — run by
the manifest's `verify` steps in `test` mode. Lattice runs them when the machine reaches the step:
on a disposable fork under `lattice test`, on the chain itself under `lattice run`, each time with
the book materialized at `.lattice/env.json` so the test sees what the release has produced so far.
A suite placed before the deploy step checks the state the release starts from; one after the
deploy sees the staged implementation; one after the execute sees the proxy moved. The same files
run in both commands, unchanged.

`LatticeTest` is the shared ground: readers and helpers, no assertions. Inherit it beside forge-std's
`Test` (or any assertion library — its cheatcodes are reached through `cheats`, never `vm`, so there
is no clash) and read every address through `Env`, never a literal.

```solidity
import { Test } from "@forge-std/src/Test.sol";
import { Env } from "lattice-std/Lattice.sol";
import { LatticeTest } from "lattice-std/LatticeTest.sol";

abstract contract ReporterTestBase is Test, LatticeTest {
    address internal proxy;

    function setUp() public virtual {
        skipUnlessMaterialized();           // a plain `forge test` has no book: skip, do not fail
        if (!materialized()) return;
        proxy = Env.addr("chainlinkReporterModule");
    }
}
```

## The checklist, and the helper for each line

What a governance simulation at Polymarket checks (safe-sim's convention), mapped to `LatticeTest`:

| Check | Before | After | Helper |
|---|---|---|---|
| The proxy runs what the book records | ✓ | | `liveImplementation(name) == Env.implementation(name)` |
| Nothing is staged yet | ✓ | | `!Env.hasStaged(name)` |
| The operation is not already in the timelock | ✓ | | `operationState(operationId(calls, predecessor, salt)) == OPERATION_UNSET` |
| Governance is as the book declares: owner is the timelock, the authority holds the admin role | ✓ | ✓ | `governedAsDeclared(target)`; `IOwnableRolesView(target).hasAllRoles(who, soladyRole(n))` for other roles; `holdsNoRoles(target, timelock())` |
| The new implementation has code, is UUPS, and nobody can initialize it | ✓ | | `implementationSane(impl) == ""` (or the pieces: `isUUPS`, `initializersDisabled`, `soladyInitializersDisabled`, `ozInitializersDisabled`) |
| Its constructor immutables and constants match the live ones | ✓ | | `sameAnswers(proxy, impl, getters) == getters.length`, one `abi.encodeWithSignature` per getter; assert the one that is meant to differ separately |
| Storage the upgrade must not touch | snapshot | compare | `snapshot(target, firstSlots(n))`, `firstChangedSlot(target, slots, before) == slots.length` — in one test when the test applies the plan itself; across runs, assert the values the book implies |
| The proxy's initialized version is unchanged | ✓ | ✓ | `soladyInitializedVersion(proxy)` / `ozInitializedVersion(proxy)` |
| The proxy moved | | ✓ | `liveImplementation(name) == Env.staged(name)` |
| The proxy cannot be re-initialized | | ✓ | `reverts(proxy, abi.encodeWithSignature("initialize(...)", ...))` |
| Selectors only the new build has resolve now, and did not before | ✓ | ✓ | `answer(proxy, data)` → `(ok, ret)` |
| A beacon or its proxies | | ✓ | `liveBeaconOf(proxy)` |

Deploy checks use the same readers against the book's expectations: `Env.staged(name)` has code,
`implementationSane(Env.staged(name)) == ""`, each constructor argument read back equals the param
or address it was built from (`Env.addr_(...)`, `Env.addr(...)`).

## Applying a plan yourself

Under `lattice test` the machine applies the plan for real and the tests only assert. A test that
wants to apply a plan itself — a safe-sim-style simulation, or a pre-check asking "what will this
do" — has the helpers safe-sim's base had. They `prank` the authority, so the Safe's code does not
run: they say what the operation does, not whether the Safe would send it; that half is Lattice's.

| Helper | Does |
|---|---|
| `callAs(sender, to, data)` / `callAsAuthority(to, data)` | One call under `prank`; a revert is bubbled with its reason. |
| `tryCallAs(sender, to, data)` | The same, answered as `(ok, returndata)` — for an execute before the delay, which must fail and leave the operation `OPERATION_WAITING`. |
| `proposeAs(sender, timelock, calls, predecessor, salt, delay)` | `Timelock.propose` with opData; returns the operation id. |
| `executeAs(sender, timelock, calls, predecessor, salt)` | `Timelock.execute`; returns the id. |
| `applyAsAuthority(calls, predecessor, salt)` | Propose on the book's timelock as the authority, warp past its live `minDelay()`, execute. |
| `operationId(calls, predecessor, salt)` | The id, for `operationState`. |

```solidity
bytes32 id = operationId(calls, bytes32(0), salt);
assertEq(operationState(id), OPERATION_UNSET, "operation already exists");
bytes32[] memory slots = firstSlots(8);
bytes32[] memory before = snapshot(proxy, slots);

applyAsAuthority(calls, bytes32(0), salt);

assertEq(operationState(id), OPERATION_DONE);
assertEq(liveImplementation("exchange"), Env.staged("exchange"));
assertEq(firstChangedSlot(proxy, slots, before), slots.length, "raw storage changed");
assertTrue(governedAsDeclared(proxy));
assertTrue(reverts(proxy, abi.encodeWithSignature("initialize(address,address)", address(1), address(2))));
```

## Constants

`ERC1967_IMPLEMENTATION_SLOT`, `ERC1967_BEACON_SLOT`; `SOLADY_INITIALIZABLE_SLOT` (bit 0
initializing, bits 1..64 the version; disabled is `uint64.max << 1`) and `OZ_INITIALIZABLE_SLOT`
(`uint64 _initialized` low, `_initializing` at bit 64; disabled is `uint64.max`); `SOLADY_ROLE_0`
(the admin role of Polymarket's modules) with `soladyRole(n)` for the others; the timelock's
`OPERATION_UNSET` … `OPERATION_DONE`.

## What stays with the test

Which getters are immutables, which selectors are new, which storage slots carry what, which
`initialize` signature a contract has, and what a release is *for*: those are the release's to
state. `LatticeTest` reads and probes; the test asserts and explains.
