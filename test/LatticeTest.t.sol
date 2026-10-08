// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import {Call, Erc7821, Timelock} from "../src/Lattice.sol";
import {LatticeTest} from "../src/LatticeTest.sol";

/// The cheatcodes these tests need beyond the base's own, declared inline: lattice-std has no
/// dependencies, and its tests keep it that way.
interface TestVm {
    function store(address target, bytes32 slot, bytes32 value) external;
    function expectRevert(bytes calldata revertData) external;
    function createDir(string calldata path, bool recursive) external;
    function writeFile(string calldata path, string calldata data) external;
    function toString(uint256 value) external pure returns (string memory);
}

/// A minimal book for one chain, written where a harness looks for it. Each harness has a file of
/// its own, because forge runs test contracts in parallel.
function writeBook(TestVm vm, string memory path, uint256 chainId) {
    vm.createDir(".lattice", true);
    vm.writeFile(
        path,
        string.concat(
            '{"id":"t","chainId":',
            vm.toString(chainId),
            ',"authority":{"kind":"eoa","address":"0x00447A08bf275b7FB3D5d832387a54Be1090d281"},"contracts":{},"params":{}}'
        )
    );
}

/// Exposes the base's internal helpers over the default book path.
contract TestBaseHarness is LatticeTest {
    function isMaterialized() external view returns (bool) {
        return materialized();
    }

    function skipUnless() external {
        skipUnlessMaterialized();
    }

    function bookChain() external view returns (uint256) {
        return bookChainId();
    }

    function why() external view returns (string memory) {
        return notMaterializedBecause();
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

    function tryCall(address sender, address to, bytes memory data) external returns (bool, bytes memory) {
        return tryCallAs(sender, to, data);
    }

    function state(bytes32 opId) external view returns (uint8) {
        return operationState(opId);
    }

    function role(uint8 n) external pure returns (uint256) {
        return soladyRole(n);
    }

    function noRoles(address target, address who) external view returns (bool) {
        return holdsNoRoles(target, who);
    }

    function soladyVersion(address t) external view returns (uint64) {
        return soladyInitializedVersion(t);
    }

    function soladyInit(address t) external view returns (bool) {
        return soladyInitializing(t);
    }

    function soladyDisabled(address t) external view returns (bool) {
        return soladyInitializersDisabled(t);
    }

    function ozVersion(address t) external view returns (uint64) {
        return ozInitializedVersion(t);
    }

    function ozInit(address t) external view returns (bool) {
        return ozInitializing(t);
    }

    function ozDisabled(address t) external view returns (bool) {
        return ozInitializersDisabled(t);
    }

    function disabled(address t) external view returns (bool) {
        return initializersDisabled(t);
    }

    function uups(address t) external view returns (bool) {
        return isUUPS(t);
    }

    function sane(address t) external view returns (string memory) {
        return implementationSane(t);
    }

    function answerOf(address to, bytes memory data) external view returns (bool, bytes memory) {
        return answer(to, data);
    }

    function revertsOn(address to, bytes memory data) external returns (bool) {
        return reverts(to, data);
    }

    function same(address a, address b, bytes[] memory calls) external view returns (uint256) {
        return sameAnswers(a, b, calls);
    }

    function slots(uint256 n) external pure returns (bytes32[] memory) {
        return firstSlots(n);
    }

    function snap(address t, bytes32[] memory which) external view returns (bytes32[] memory) {
        return snapshot(t, which);
    }

    function changed(address t, bytes32[] memory which, bytes32[] memory before) external view returns (uint256) {
        return firstChangedSlot(t, which, before);
    }
}

/// An implementation that answers proxiableUUID with the right slot — and one with the wrong one.
contract FakeUUPS {
    function proxiableUUID() external pure returns (bytes32) {
        return 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
    }
}

contract FakeNotUUPS {
    function proxiableUUID() external pure returns (bytes32) {
        return bytes32(uint256(1));
    }
}

/// Two constructor-set values with getters, for parity checks.
contract FakeConstants {
    uint256 public immutable A;
    bytes32 public immutable B;

    constructor(uint256 a, bytes32 b) {
        A = a;
        B = b;
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

    function rolesOf(address user) external view returns (uint256) {
        return user == admin ? 1 : 0;
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

    function test_readsInitializerStateUnderBothFrameworks() public {
        address t = address(0xbeef);
        bytes32 solady = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffbf601132;
        bytes32 oz = 0xf0c57e16840df040f15088dc2f81fe391c3923bec73e23a9662efc9c229c6a00;
        require(
            !harness.disabled(t) && harness.soladyVersion(t) == 0 && harness.ozVersion(t) == 0, "a blank is nothing"
        );

        vm.store(t, solady, bytes32(uint256(1) << 1));
        require(harness.soladyVersion(t) == 1 && !harness.soladyInit(t) && !harness.soladyDisabled(t), "solady v1");
        vm.store(t, solady, bytes32((uint256(1) << 1) | 1));
        require(harness.soladyInit(t), "solady initializing");
        vm.store(t, solady, bytes32(uint256(type(uint64).max) << 1));
        require(harness.soladyDisabled(t) && harness.disabled(t), "solady disabled");

        vm.store(t, solady, bytes32(0));
        vm.store(t, oz, bytes32(uint256(1)));
        require(
            harness.ozVersion(t) == 1 && !harness.ozInit(t) && !harness.ozDisabled(t) && !harness.disabled(t), "oz v1"
        );
        vm.store(t, oz, bytes32(uint256(1) | (uint256(1) << 64)));
        require(harness.ozInit(t), "oz initializing");
        vm.store(t, oz, bytes32(uint256(type(uint64).max)));
        require(harness.ozDisabled(t) && harness.disabled(t), "oz disabled");
    }

    function test_judgesAnImplementationsSanity() public {
        require(harness.uups(address(new FakeUUPS())), "uups");
        require(!harness.uups(address(new FakeNotUUPS())), "wrong uuid");
        require(!harness.uups(address(new FakeTarget())), "no proxiableUUID");

        require(keccak256(bytes(harness.sane(address(0xdead)))) == keccak256("no code"), "no code");
        require(
            keccak256(bytes(harness.sane(address(new FakeTarget()))))
                == keccak256("not UUPS: proxiableUUID is not the ERC-1967 implementation slot"),
            "not uups"
        );
        FakeUUPS live = new FakeUUPS();
        require(keccak256(bytes(harness.sane(address(live)))) == keccak256("initializers enabled"), "enabled");
        vm.store(
            address(live),
            0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffbf601132,
            bytes32(uint256(type(uint64).max) << 1)
        );
        require(bytes(harness.sane(address(live))).length == 0, "sane");
    }

    function test_probesAndComparesAnswers() public {
        FakeTarget target = new FakeTarget();
        (bool ok, bytes memory ret) = harness.answerOf(address(target), abi.encodeWithSignature("lastSender()"));
        require(ok && abi.decode(ret, (address)) == address(0), "answer");
        (ok,) = harness.answerOf(address(target), abi.encodeWithSignature("nothing()"));
        require(!ok, "an unknown selector does not answer");
        require(harness.revertsOn(address(target), abi.encodeWithSignature("boom()")), "boom reverts");
        require(!harness.revertsOn(address(target), abi.encodeWithSignature("poke()")), "poke does not");

        FakeConstants x = new FakeConstants(7, bytes32(uint256(9)));
        FakeConstants y = new FakeConstants(7, bytes32(uint256(9)));
        FakeConstants z = new FakeConstants(7, bytes32(uint256(8)));
        bytes[] memory calls = new bytes[](2);
        calls[0] = abi.encodeWithSignature("A()");
        calls[1] = abi.encodeWithSignature("B()");
        require(harness.same(address(x), address(y), calls) == 2, "all agree");
        require(harness.same(address(x), address(z), calls) == 1, "B differs");
        require(harness.same(address(x), address(target), calls) == 0, "a getter one side lacks differs");

        (ok, ret) = harness.tryCall(SENDER, address(target), abi.encodeWithSignature("boom()"));
        require(!ok && ret.length > 0, "tryCall answers the revert");
        (ok,) = harness.tryCall(SENDER, address(target), abi.encodeWithSignature("poke()"));
        require(ok && target.lastSender() == SENDER, "tryCall pranks");
    }

    function test_snapshotsRawStorage() public {
        address t = address(0xcafe);
        bytes32[] memory which = harness.slots(3);
        require(which.length == 3 && which[0] == bytes32(0) && which[2] == bytes32(uint256(2)), "first slots");
        vm.store(t, bytes32(uint256(1)), bytes32(uint256(11)));
        bytes32[] memory before = harness.snap(t, which);
        require(before[1] == bytes32(uint256(11)) && before[0] == bytes32(0), "snapshot");
        require(harness.changed(t, which, before) == 3, "unchanged");
        vm.store(t, bytes32(uint256(2)), bytes32(uint256(5)));
        require(harness.changed(t, which, before) == 2, "slot 2 changed");
    }

    function test_rolesHelpers() public {
        require(harness.role(0) == 1 && harness.role(4) == 16, "role bits");
        FakeGoverned g = new FakeGoverned(address(1), SENDER);
        require(!harness.noRoles(address(g), SENDER) && harness.noRoles(address(g), address(1)), "holdsNoRoles");
    }

    function test_aMissingBookIsNotMaterialized() public {
        NoBookHarness none = new NoBookHarness();
        require(!none.isMaterialized(), "a missing book reads as materialized");
    }

    function test_aBookIsMaterializedOnlyForItsChain() public {
        writeBook(vm, ".lattice/this-chain.json", block.chainid);
        writeBook(vm, ".lattice/other-chain.json", block.chainid + 1);
        ThisChainHarness here = new ThisChainHarness();
        require(here.isMaterialized(), "a book for this chain reads as not materialized");
        require(bytes(here.why()).length == 0, "a book for this chain has a reason not to run");
        OtherChainHarness other = new OtherChainHarness();
        require(!other.isMaterialized(), "a book for another chain reads as materialized");
        require(other.bookChain() == block.chainid + 1, "the book's chain id");
        require(
            same(
                other.why(),
                string.concat(
                    "the book at .lattice/other-chain.json is for chain ",
                    vm.toString(block.chainid + 1),
                    " and this run is on chain ",
                    vm.toString(block.chainid),
                    ": run through lattice test or lattice run"
                )
            ),
            "the reason for another chain's book"
        );
        require(
            same(
                new NoBookHarness().why(), "no book at .lattice/nowhere.json: run through lattice test or lattice run"
            ),
            "the reason for a missing book"
        );
    }

    function same(string memory a, string memory b) internal pure returns (bool) {
        return keccak256(bytes(a)) == keccak256(bytes(b));
    }
}

/// Harnesses over a book written for this chain and for another one.
contract ThisChainHarness is TestBaseHarness {
    function bookPath() internal pure override returns (string memory) {
        return ".lattice/this-chain.json";
    }
}

contract OtherChainHarness is TestBaseHarness {
    function bookPath() internal pure override returns (string memory) {
        return ".lattice/other-chain.json";
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

/// The base over the book an earlier lattice run left behind, with no fork under it: the chain id
/// is forge's own, not the book's, and the hook is skipped rather than run against nothing.
contract LatticeTestSkipsOnAnotherChain is LatticeTest {
    TestVm constant vm = TestVm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function bookPath() internal pure override returns (string memory) {
        return ".lattice/skip-other-chain.json";
    }

    function setUp() public {
        writeBook(vm, bookPath(), block.chainid + 1);
    }

    function test_skipsWhenTheBookIsForAnotherChain() public {
        skipUnlessMaterialized();
        revert("reached past the skip");
    }
}

/// The base over a book for the chain the test runs on: the hook runs.
contract LatticeTestRunsOnTheBooksChain is LatticeTest {
    TestVm constant vm = TestVm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function bookPath() internal pure override returns (string memory) {
        return ".lattice/run-this-chain.json";
    }

    function setUp() public {
        writeBook(vm, bookPath(), block.chainid);
    }

    function test_runsWhenTheBookIsForThisChain() public view {
        require(materialized(), "a book for this chain reads as not materialized");
    }

    function test_doesNotSkipWhenTheBookIsForThisChain() public {
        skipUnlessMaterialized();
        require(bookChainId() == block.chainid, "reached, and the book is this chain's");
    }
}
