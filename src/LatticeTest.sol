// SPDX-License-Identifier: MIT
pragma solidity >=0.8.12 <0.9.0;

import {Call, Env, Erc7821, Timelock} from "./Lattice.sol";

/// The forge cheatcodes the test base uses, declared here so nothing has to be installed beside
/// it. A test that also inherits forge-std's `Test` sees no clash: the handle is `cheats`, never
/// `vm`.
interface LatticeTestVm {
    function load(address target, bytes32 slot) external view returns (bytes32);
    function exists(string calldata path) external view returns (bool);
    function readFile(string calldata path) external view returns (string memory);
    function parseJsonUint(string calldata json, string calldata key) external pure returns (uint256);
    function parseJsonAddress(string calldata json, string calldata key) external pure returns (address);
    function parseJsonBool(string calldata json, string calldata key) external pure returns (bool);
    function keyExistsJson(string calldata json, string calldata key) external view returns (bool);
    function toString(uint256 value) external pure returns (string memory);
    function skip(bool skipTest, string calldata reason) external;
    function prank(address msgSender) external;
    function warp(uint256 newTimestamp) external;
}

/// A Solady Timelock, as far as a test reads it.
interface ITimelockView {
    function minDelay() external view returns (uint256);
    function operationState(bytes32 id) external view returns (uint8);
}

/// A Solady OwnableRoles target, as far as its governance is checked.
interface IOwnableRolesView {
    function owner() external view returns (address);
    function hasAllRoles(address user, uint256 roles) external view returns (bool);
    function rolesOf(address user) external view returns (uint256);
}

/// A UUPS implementation, as far as its sanity is checked.
interface IUUPSView {
    function proxiableUUID() external view returns (bytes32);
}

/// Ground for a release's pre- and post-checks — the `verify` steps in `test` mode, which
/// `lattice test` runs on a fork and `lattice run` runs on the chain — and for a safe-sim-style
/// simulation that applies a plan itself. Readers and helpers only: the assertions are the test's,
/// from forge-std or anything else, so this file keeps lattice-std's rule of depending on nothing.
/// Every address comes from the book lattice materializes, never from a literal, so one test runs
/// on every environment.
abstract contract LatticeTest {
    LatticeTestVm internal constant cheats = LatticeTestVm(address(uint160(uint256(keccak256("hevm cheat code")))));

    /// ERC-1967's implementation and beacon slots.
    bytes32 internal constant ERC1967_IMPLEMENTATION_SLOT =
        0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
    bytes32 internal constant ERC1967_BEACON_SLOT = 0xa3f0ad74e5423aebfd80d3ef4346578335a9a72aeaee59ff6cb3582b35133d50;
    /// Solady OwnableRoles' `_ROLE_0`: the admin role of Polymarket's modules.
    uint256 internal constant SOLADY_ROLE_0 = 1;
    /// Solady Timelock's operation states.
    uint8 internal constant OPERATION_UNSET = 0;
    uint8 internal constant OPERATION_WAITING = 1;
    uint8 internal constant OPERATION_READY = 2;
    uint8 internal constant OPERATION_DONE = 3;
    /// Solady Initializable's slot, `~uint256(uint32(bytes4(keccak256("_INITIALIZABLE_SLOT"))))`:
    /// bit 0 is `initializing`, bits 1..64 the initialized version. `_disableInitializers()`
    /// stores `uint64.max << 1`.
    bytes32 internal constant SOLADY_INITIALIZABLE_SLOT =
        0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffbf601132;
    /// OpenZeppelin v5 Initializable's namespaced slot: `uint64 _initialized` in the low 64 bits,
    /// `bool _initializing` at bit 64. `_disableInitializers()` stores `uint64.max`.
    bytes32 internal constant OZ_INITIALIZABLE_SLOT =
        0xf0c57e16840df040f15088dc2f81fe391c3923bec73e23a9662efc9c229c6a00;

    /// Where the book is. Overridable so a test of this contract can point at a missing one.
    function bookPath() internal pure virtual returns (string memory) {
        return Env.PATH;
    }

    /// Whether lattice materialized a book for this run: the file is there and it is for the chain
    /// the test runs on. A plain `forge test` over a repository has no book — or has the book an
    /// earlier lattice run left behind, with no fork under it, and then the chain id is forge's own
    /// rather than the book's and the hooks would run against nothing.
    function materialized() internal view returns (bool) {
        return bytes(notMaterializedBecause()).length == 0;
    }

    /// Why the hooks should not run here — no book at the path, or a book for another chain — or
    /// the empty string when a book is materialized for this chain.
    function notMaterializedBecause() internal view returns (string memory) {
        if (!cheats.exists(bookPath())) {
            return string.concat("no book at ", bookPath(), ": run through lattice test or lattice run");
        }
        uint256 want = bookChainId();
        if (want != block.chainid) {
            return string.concat(
                "the book at ",
                bookPath(),
                " is for chain ",
                cheats.toString(want),
                " and this run is on chain ",
                cheats.toString(block.chainid),
                ": run through lattice test or lattice run"
            );
        }
        return "";
    }

    /// The chain the materialized book is for.
    function bookChainId() internal view returns (uint256) {
        return cheats.parseJsonUint(cheats.readFile(bookPath()), ".chainId");
    }

    /// Skips the test unless a book is materialized for this chain: these are step hooks, not unit
    /// tests. The reason names which half is missing.
    function skipUnlessMaterialized() internal {
        string memory why = notMaterializedBecause();
        cheats.skip(bytes(why).length != 0, why);
    }

    /// The timelock the book's governance goes through: its `timelock` entry.
    function timelock() internal view returns (address) {
        return Env.addr("timelock");
    }

    /// What a proxy runs right now, off its ERC-1967 implementation slot.
    function liveImplementation(string memory name) internal view returns (address) {
        return liveImplementationOf(Env.addr(name));
    }

    function liveImplementationOf(address proxy) internal view returns (address) {
        return address(uint160(uint256(cheats.load(proxy, ERC1967_IMPLEMENTATION_SLOT))));
    }

    /// The beacon a beacon proxy points at, off its ERC-1967 beacon slot.
    function liveBeaconOf(address proxy) internal view returns (address) {
        return address(uint160(uint256(cheats.load(proxy, ERC1967_BEACON_SLOT))));
    }

    /// Whether a target is governed as the book declares: owned by the timelock, with the
    /// authority holding the admin role. An upgrade touches neither, so a release checks it
    /// before and after.
    function governedAsDeclared(address target) internal view returns (bool) {
        return IOwnableRolesView(target).owner() == timelock()
            && IOwnableRolesView(target).hasAllRoles(Env.authority(), SOLADY_ROLE_0);
    }

    /// Whether a contract the book names is governed as the book declares: owned by the
    /// timelock and, where the book declares the authority holds its admin role
    /// (`contracts.<name>.adminRole`), holding `_ROLE_0` there. A contract the book declares
    /// owner-governed only — the Router grants no roles — passes on its owner alone, where the
    /// address form above demands a role it was never meant to hold. Read off bookPath(), the
    /// book this base checks, so a harness with a book of its own is judged by it.
    function governedAsDeclared(string memory name) internal view returns (bool) {
        string memory book = cheats.readFile(bookPath());
        address target = cheats.parseJsonAddress(book, string.concat(".contracts.", name, ".address"));
        if (IOwnableRolesView(target).owner() != cheats.parseJsonAddress(book, ".contracts.timelock.address")) {
            return false;
        }
        string memory key = string.concat(".contracts.", name, ".adminRole");
        if (!cheats.keyExistsJson(book, key) || !cheats.parseJsonBool(book, key)) return true;
        return IOwnableRolesView(target).hasAllRoles(cheats.parseJsonAddress(book, ".authority.address"), SOLADY_ROLE_0);
    }

    /// Solady OwnableRoles' bit for `_ROLE_n`.
    function soladyRole(uint8 n) internal pure returns (uint256) {
        return 1 << n;
    }

    /// Whether an account holds no role at all on a target — the timelock, for one, owns a
    /// module without holding its roles, and an upgrade must not change that.
    function holdsNoRoles(address target, address who) internal view returns (bool) {
        return IOwnableRolesView(target).rolesOf(who) == 0;
    }

    /// The id the timelock gives an operation proposed with opData.
    function operationId(Call[] memory calls, bytes32 predecessor, bytes32 salt) internal pure returns (bytes32) {
        return Erc7821.opId(Erc7821.MODE_OPDATA, Erc7821.encode(calls, predecessor, salt));
    }

    /// What the book's timelock says about an operation: OPERATION_UNSET before it is proposed,
    /// which a pre-check asserts, through OPERATION_DONE.
    function operationState(bytes32 id) internal view returns (uint8) {
        return ITimelockView(timelock()).operationState(id);
    }

    // Initializers. A bare implementation must be inert — `_disableInitializers()` in its
    // constructor — and a proxy keeps its initialized version across an upgrade.

    function soladyInitializedVersion(address target) internal view returns (uint64) {
        return uint64((uint256(cheats.load(target, SOLADY_INITIALIZABLE_SLOT)) >> 1) & type(uint64).max);
    }

    function soladyInitializing(address target) internal view returns (bool) {
        return uint256(cheats.load(target, SOLADY_INITIALIZABLE_SLOT)) & 1 == 1;
    }

    function soladyInitializersDisabled(address target) internal view returns (bool) {
        return soladyInitializedVersion(target) == type(uint64).max;
    }

    function ozInitializedVersion(address target) internal view returns (uint64) {
        return uint64(uint256(cheats.load(target, OZ_INITIALIZABLE_SLOT)));
    }

    function ozInitializing(address target) internal view returns (bool) {
        return (uint256(cheats.load(target, OZ_INITIALIZABLE_SLOT)) >> 64) & 1 == 1;
    }

    function ozInitializersDisabled(address target) internal view returns (bool) {
        return ozInitializedVersion(target) == type(uint64).max;
    }

    /// Whether the initializers are disabled under either framework. Both slots are namespaced,
    /// so a contract using neither reads zero in both and is not disabled.
    function initializersDisabled(address target) internal view returns (bool) {
        return soladyInitializersDisabled(target) || ozInitializersDisabled(target);
    }

    /// Whether a contract answers `proxiableUUID()` with the ERC-1967 implementation slot: what
    /// `upgradeToAndCall` checks before it points a proxy at it.
    function isUUPS(address implementation) internal view returns (bool) {
        (bool ok, bytes memory ret) =
            implementation.staticcall(abi.encodeWithSelector(IUUPSView.proxiableUUID.selector));
        return ok && ret.length == 32 && abi.decode(ret, (bytes32)) == ERC1967_IMPLEMENTATION_SLOT;
    }

    /// The sanity of an implementation about to be put behind a proxy, as one answer: empty when
    /// it has code, is UUPS and cannot be initialized by anyone; otherwise the first failing
    /// reason. A pre-check asserts it is empty.
    function implementationSane(address implementation) internal view returns (string memory) {
        if (implementation.code.length == 0) return "no code";
        if (!isUUPS(implementation)) return "not UUPS: proxiableUUID is not the ERC-1967 implementation slot";
        if (!initializersDisabled(implementation)) return "initializers enabled";
        return "";
    }

    // Reading and probing targets.

    /// A static call's answer, without reverting on failure.
    function answer(address to, bytes memory data) internal view returns (bool ok, bytes memory ret) {
        return to.staticcall(data);
    }

    /// Whether a call reverts. For a mutator — `initialize(...)` through an upgraded proxy, which
    /// must. A call that does not revert has run, so a test asserting the revert fails anyway.
    function reverts(address to, bytes memory data) internal returns (bool) {
        (bool ok,) = to.call(data);
        return !ok;
    }

    /// Whether two contracts answer the same calls identically: an implementation's constructor
    /// immutables and constants against the proxy's (or the live implementation's), one getter
    /// per entry. Returns the index of the first call that differs or fails on either side, or
    /// `calls.length` when all agree.
    function sameAnswers(address a, address b, bytes[] memory calls) internal view returns (uint256) {
        for (uint256 i = 0; i < calls.length; i++) {
            (bool okA, bytes memory retA) = a.staticcall(calls[i]);
            (bool okB, bytes memory retB) = b.staticcall(calls[i]);
            if (!okA || !okB || keccak256(retA) != keccak256(retB)) return i;
        }
        return calls.length;
    }

    /// The first n storage slots, for a raw snapshot.
    function firstSlots(uint256 n) internal pure returns (bytes32[] memory slots) {
        slots = new bytes32[](n);
        for (uint256 i = 0; i < n; i++) {
            slots[i] = bytes32(i);
        }
    }

    /// Raw storage, slot by slot: what an upgrade must leave byte-equal, proving the layout
    /// is compatible.
    function snapshot(address target, bytes32[] memory slots) internal view returns (bytes32[] memory words) {
        words = new bytes32[](slots.length);
        for (uint256 i = 0; i < slots.length; i++) {
            words[i] = cheats.load(target, slots[i]);
        }
    }

    /// The index of the first slot whose word differs from the snapshot, or `slots.length`.
    function firstChangedSlot(address target, bytes32[] memory slots, bytes32[] memory before)
        internal
        view
        returns (uint256)
    {
        for (uint256 i = 0; i < slots.length; i++) {
            if (cheats.load(target, slots[i]) != before[i]) return i;
        }
        return slots.length;
    }

    // Applying a plan the way the chain will, without lattice: safe-sim's path. A prank, so the
    // Safe's code does not run — these say what an operation does, not whether the Safe would
    // send it; that half is `lattice test`'s. A revert is bubbled with its reason.

    /// A call as sender, answered rather than bubbled: for an execute before the delay, which
    /// must fail and leave the operation Waiting.
    function tryCallAs(address sender, address to, bytes memory data) internal returns (bool ok, bytes memory ret) {
        cheats.prank(sender);
        return to.call(data);
    }

    function callAs(address sender, address to, bytes memory data) internal returns (bytes memory) {
        (bool ok, bytes memory ret) = tryCallAs(sender, to, data);
        if (!ok) {
            assembly {
                revert(add(ret, 32), mload(ret))
            }
        }
        return ret;
    }

    function callAsAuthority(address to, bytes memory data) internal returns (bytes memory) {
        return callAs(Env.authority(), to, data);
    }

    function proposeAs(
        address sender,
        address tl,
        Call[] memory calls,
        bytes32 predecessor,
        bytes32 salt,
        uint256 delay
    ) internal returns (bytes32 id) {
        callAs(sender, tl, Timelock.propose(Erc7821.MODE_OPDATA, Erc7821.encode(calls, predecessor, salt), delay));
        return operationId(calls, predecessor, salt);
    }

    function executeAs(address sender, address tl, Call[] memory calls, bytes32 predecessor, bytes32 salt)
        internal
        returns (bytes32 id)
    {
        callAs(sender, tl, Timelock.execute(Erc7821.MODE_OPDATA, Erc7821.encode(calls, predecessor, salt)));
        return operationId(calls, predecessor, salt);
    }

    /// Propose, wait the timelock's own delay, execute — as the authority, on the book's timelock.
    function applyAsAuthority(Call[] memory calls, bytes32 predecessor, bytes32 salt) internal returns (bytes32 id) {
        address tl = timelock();
        uint256 delay = ITimelockView(tl).minDelay();
        id = proposeAs(Env.authority(), tl, calls, predecessor, salt, delay);
        cheats.warp(block.timestamp + delay);
        executeAs(Env.authority(), tl, calls, predecessor, salt);
    }
}
