// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Call, Erc7821, Timelock} from "../src/Lattice.sol";
import {LatticeTest} from "../src/LatticeTest.sol";

/// The cheatcodes these tests need beyond the base's own, declared inline: lattice-std has no
/// dependencies, and its tests keep it that way.
interface TestVm {
    function store(address target, bytes32 slot, bytes32 value) external;
    function expectRevert(bytes calldata revertData) external;
}

/// Exposes the base's internal helpers over the default book path.
contract TestBaseHarness is LatticeTest {
    function isMaterialized() external view returns (bool) {
        return materialized();
    }

    function skipUnless() external {
        skipUnlessMaterialized();
    }

    function live(string memory name) external view returns (address) {
        return liveImplementation(name);
    }

    function liveOf(address proxy) external view returns (address) {
        return liveImplementationOf(proxy);
    }

    function beaconOf(address proxy) external view returns (address) {
        return liveBeaconOf(proxy);
    }

    function theTimelock() external view returns (address) {
        return timelock();
    }

    function governed(address target) external view returns (bool) {
        return governedAsDeclared(target);
    }

    function id(Call[] memory calls, bytes32 predecessor, bytes32 salt) external pure returns (bytes32) {
        return operationId(calls, predecessor, salt);
    }

    function call(address sender, address to, bytes memory data) external returns (bytes memory) {
        return callAs(sender, to, data);
    }

    function callAuthority(address to, bytes memory data) external returns (bytes memory) {
        return callAsAuthority(to, data);
    }

    function propose(address sender, address tl, Call[] memory calls, bytes32 predecessor, bytes32 salt, uint256 delay)
        external
        returns (bytes32)
    {
        return proposeAs(sender, tl, calls, predecessor, salt, delay);
    }

    function execute(address sender, address tl, Call[] memory calls, bytes32 predecessor, bytes32 salt)
        external
        returns (bytes32)
    {
        return executeAs(sender, tl, calls, predecessor, salt);
    }

    function apply_(Call[] memory calls, bytes32 predecessor, bytes32 salt) external returns (bytes32) {
        return applyAsAuthority(calls, predecessor, salt);
    }
}

/// A harness whose book is somewhere nothing was written.
contract NoBookHarness is TestBaseHarness {
    function bookPath() internal pure override returns (string memory) {
        return ".lattice/nowhere.json";
    }
}

/// A timelock that records what it was asked and answers a fixed delay.
contract FakeTimelock {
    address public lastSender;
    bytes public lastData;

    /// A constant, not storage: the book test etches this code at the book's timelock address,
    /// and etch carries code, never storage.
    function minDelay() external pure returns (uint256) {
        return 60;
    }

    function operationState(bytes32) external pure returns (uint8) {
        return 1;
    }

    fallback() external {
        lastSender = msg.sender;
        lastData = msg.data;
    }
}

/// A target that records its caller and can be made to revert.
contract FakeTarget {
    address public lastSender;

    function poke() external returns (uint256) {
        lastSender = msg.sender;
        return 7;
    }

    function boom() external pure {
        revert("boom: no");
    }
}

/// A Solady-shaped governed contract with a settable owner and role holder.
contract FakeGoverned {
    address public owner;
    address public admin;

    constructor(address owner_, address admin_) {
        owner = owner_;
        admin = admin_;
    }

    function hasAllRoles(address user, uint256 roles) external view returns (bool) {
        return user == admin && roles == 1;
    }
}

contract LatticeTestBaseTest {
    TestVm constant vm = TestVm(address(uint160(uint256(keccak256("hevm cheat code")))));
    TestBaseHarness harness = new TestBaseHarness();

    address constant PROXY = 0xe3333700cA9d93003F00f0F71f8515005F6c00Aa;
    address constant IMPL = 0x641b40ec414a076b9e79E703Fc7BF4EBEC248Bb7;
    address constant BEACON = 0x7A18EDfe055488A3128f01F563e5B479D92ffc3a;
    address constant SENDER = 0x3dcE0a29139A851Da1dFCa56Af8e8a6440b4D952;

    function test_readsTheErc1967Slots() public {
        vm.store(
            PROXY, 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc, bytes32(uint256(uint160(IMPL)))
        );
        vm.store(
            PROXY, 0xa3f0ad74e5423aebfd80d3ef4346578335a9a72aeaee59ff6cb3582b35133d50, bytes32(uint256(uint160(BEACON)))
        );
        require(harness.liveOf(PROXY) == IMPL, "implementation slot");
        require(harness.beaconOf(PROXY) == BEACON, "beacon slot");
        require(harness.liveOf(address(0xdead)) == address(0), "an empty slot is the zero address");
    }

    function test_callAsPranksTheSenderAndBubblesAReason() public {
        FakeTarget target = new FakeTarget();
        bytes memory ret = harness.call(SENDER, address(target), abi.encodeWithSignature("poke()"));
        require(target.lastSender() == SENDER, "the sender was not pranked");
        require(abi.decode(ret, (uint256)) == 7, "the return data was lost");
        vm.expectRevert(bytes("boom: no"));
        harness.call(SENDER, address(target), abi.encodeWithSignature("boom()"));
    }

    function test_proposeAndExecuteEncodeTheOperationAndNameItsId() public {
        FakeTimelock tl = new FakeTimelock();
        Call[] memory calls = new Call[](1);
        calls[0] = Call(PROXY, 0, abi.encodeWithSignature("upgradeToAndCall(address,bytes)", IMPL, ""));
        bytes32 salt = bytes32(uint256(42));
        bytes memory d = Erc7821.encode(calls, bytes32(0), salt);
        bytes32 want = Erc7821.opId(Erc7821.MODE_OPDATA, d);

        bytes32 id = harness.propose(SENDER, address(tl), calls, bytes32(0), salt, 43200);
        require(id == want && id == harness.id(calls, bytes32(0), salt), "propose id");
        require(tl.lastSender() == SENDER, "propose sender");
        require(keccak256(tl.lastData()) == keccak256(Timelock.propose(Erc7821.MODE_OPDATA, d, 43200)), "propose data");

        id = harness.execute(SENDER, address(tl), calls, bytes32(0), salt);
        require(id == want, "execute id");
        require(keccak256(tl.lastData()) == keccak256(Timelock.execute(Erc7821.MODE_OPDATA, d)), "execute data");
    }

    function test_aMissingBookIsNotMaterialized() public {
        NoBookHarness none = new NoBookHarness();
        require(!none.isMaterialized(), "a missing book reads as materialized");
    }
}

/// A test that is itself the base, over a missing book: forge allows `skip` only from the test's
/// own frame, which is how a release's checks call it. Skipping is the whole point — with no book
/// the hook does not run, and forge reports the test as skipped rather than failed.
contract LatticeTestSkipsWithoutABook is LatticeTest {
    function bookPath() internal pure override returns (string memory) {
        return ".lattice/nowhere.json";
    }

    function test_skipsWithoutABook() public {
        skipUnlessMaterialized();
        revert("reached past the skip");
    }
}
