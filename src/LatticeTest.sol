// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {Call, Env, Erc7821, Timelock} from "./Lattice.sol";

/// The forge cheatcodes the test base uses, declared here so nothing has to be installed beside
/// it. A test that also inherits forge-std's `Test` sees no clash: the handle is `cheats`, never
/// `vm`.
interface LatticeTestVm {
    function load(address target, bytes32 slot) external view returns (bytes32);
    function exists(string calldata path) external view returns (bool);
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

    /// Where the book is. Overridable so a test of this contract can point at a missing one.
    function bookPath() internal pure virtual returns (string memory) {
        return Env.PATH;
    }

    /// Whether lattice materialized a book for this run. A plain `forge test` over a repository
    /// has none.
    function materialized() internal view returns (bool) {
        return cheats.exists(bookPath());
    }

    /// Skips the test unless a book is materialized: these are step hooks, not unit tests.
    function skipUnlessMaterialized() internal {
        cheats.skip(!materialized(), "no .lattice/env.json: run through lattice test or lattice run");
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

    /// The id the timelock gives an operation proposed with opData.
    function operationId(Call[] memory calls, bytes32 predecessor, bytes32 salt) internal pure returns (bytes32) {
        return Erc7821.opId(Erc7821.MODE_OPDATA, Erc7821.encode(calls, predecessor, salt));
    }

    // Applying a plan the way the chain will, without lattice: safe-sim's path. A prank, so the
    // Safe's code does not run — these say what an operation does, not whether the Safe would
    // send it; that half is `lattice test`'s. A revert is bubbled with its reason.

    function callAs(address sender, address to, bytes memory data) internal returns (bytes memory) {
        cheats.prank(sender);
        (bool ok, bytes memory ret) = to.call(data);
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
