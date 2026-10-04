// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Call, Deployment, EnvVar, Erc7821, Timelock, MultiSend, Env} from "../src/Lattice.sol";
import {TestBaseHarness, FakeTimelock, FakeTarget, FakeGoverned} from "./LatticeTest.t.sol";

/// The two cheatcodes these tests need beyond the library's own, declared inline: lattice-std
/// has no dependencies, and its tests keep it that way.
interface Vm {
    function createDir(string calldata path, bool recursive) external;
    function writeFile(string calldata path, string calldata data) external;
    function expectRevert(bytes calldata revertData) external;
    function store(address target, bytes32 slot, bytes32 value) external;
    function etch(address target, bytes calldata code) external;
}

/// Exposes the libraries' internal functions on an external surface, so a revert can be
/// expected on them.
contract Harness {
    function encode(Call[] memory calls) external pure returns (bytes memory) {
        return Erc7821.encode(calls);
    }

    function encode(Call[] memory calls, bytes32 predecessor, bytes32 salt) external pure returns (bytes memory) {
        return Erc7821.encode(calls, predecessor, salt);
    }

    function pack(Call[] memory calls) external pure returns (bytes memory) {
        return MultiSend.pack(calls);
    }

    function uint8_(string memory key) external view returns (uint8) {
        return Env.uint8_(key);
    }

    function uint16_(string memory key) external view returns (uint16) {
        return Env.uint16_(key);
    }

    function uint32_(string memory key) external view returns (uint32) {
        return Env.uint32_(key);
    }

    function uint64_(string memory key) external view returns (uint64) {
        return Env.uint64_(key);
    }

    function uint128_(string memory key) external view returns (uint128) {
        return Env.uint128_(key);
    }
}

/// Selectors measured with `cast sig`, so a typo in a signature string cannot agree with itself.
contract LatticeStdTest {
    Vm constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
    Harness harness = new Harness();

    bytes4 constant PROPOSE = 0xb109e950;
    bytes4 constant EXECUTE = 0xe9ae5c53;
    bytes4 constant CANCEL = 0xc4d252f5;

    // The combinatorial module upgrade governance executed at Safe nonce 147 on Polygon
    // (testdata/fixtures/route.json): one upgradeToAndCall, proposed with a zero predecessor and
    // salt in the opData mode. Its operation id is on chain, so the encoding is pinned to what
    // executed rather than to itself.
    address constant MODULE = 0xDCa4af75705dbB50f62437045afF9921947917d2;
    bytes constant UPGRADE =
        hex"4f1ef286000000000000000000000000f92018eecaf1585de6b6d4989f51482c3e90cce500000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000000000";
    bytes32 constant OP_ID_147 = 0xffea0e8b3366b790c136a5e0b12fc590de6dd86dcfd6fd7c73d502803005be2a;

    address constant A = 0x1000000000000000000000000000000000000001;
    address constant B = 0x2000000000000000000000000000000000000002;

    function nonce147() internal pure returns (Call[] memory calls) {
        calls = new Call[](1);
        calls[0] = Call({to: MODULE, value: 0, data: UPGRADE});
    }

    function two() internal pure returns (Call[] memory calls) {
        calls = new Call[](2);
        calls[0] = Call({to: A, value: 1 ether, data: ""});
        calls[1] = Call({to: B, value: 0, data: hex"deadbeef01"});
    }

    function same(bytes memory a, bytes memory b, string memory what) internal pure {
        require(keccak256(a) == keccak256(b), what);
    }

    function test_modes() public pure {
        require(Erc7821.MODE == bytes32(uint256(1) << 248), "MODE is 0x01 then zeros");
        require(
            Erc7821.MODE_OPDATA == 0x0100000000007821000100000000000000000000000000000000000000000000,
            "MODE_OPDATA is the production mode"
        );
    }

    function test_executionDataIsTheAbiEncoding() public pure {
        Call[] memory calls = two();
        same(Erc7821.encode(calls), abi.encode(calls), "plain");
        same(
            Erc7821.encode(calls, bytes32(uint256(1)), bytes32(uint256(2))),
            abi.encode(calls, abi.encode(bytes32(uint256(1)), bytes32(uint256(2)))),
            "with opData"
        );
        bytes memory d = Erc7821.encode(calls);
        require(Erc7821.opId(Erc7821.MODE, d) == keccak256(abi.encode(Erc7821.MODE, keccak256(d))), "opId");
    }

    function test_reproducesTheOperationGovernanceExecutedAtNonce147() public pure {
        bytes memory d = Erc7821.encode(nonce147(), bytes32(0), bytes32(0));
        require(Erc7821.opId(Erc7821.MODE_OPDATA, d) == OP_ID_147, "opId of nonce 147");
        bytes memory x = Timelock.execute(Erc7821.MODE_OPDATA, d);
        same(x, abi.encodeWithSelector(EXECUTE, Erc7821.MODE_OPDATA, d), "execute calldata");
    }

    function test_timelockCalldata() public pure {
        bytes memory d = Erc7821.encode(two(), bytes32(0), bytes32(uint256(7)));
        same(
            Timelock.propose(Erc7821.MODE_OPDATA, d, 43200),
            abi.encodeWithSelector(PROPOSE, Erc7821.MODE_OPDATA, d, uint256(43200)),
            "propose"
        );
        same(
            Timelock.execute(Erc7821.MODE_OPDATA, d), abi.encodeWithSelector(EXECUTE, Erc7821.MODE_OPDATA, d), "execute"
        );
        same(Timelock.cancel(OP_ID_147), abi.encodeWithSelector(CANCEL, OP_ID_147), "cancel");
        require(Timelock.cancel(OP_ID_147).length == 36, "cancel is a selector and one word");
    }

    function test_packIsTheMultiSendLayout() public pure {
        Call[] memory calls = two();
        bytes memory packed = MultiSend.pack(calls);
        // uint8 operation (0), address, uint256 value, uint256 length, then the data: 85 bytes plus the data per call.
        require(packed.length == 85 * 2 + 5, "length");
        same(
            packed,
            abi.encodePacked(
                uint8(0), A, uint256(1 ether), uint256(0), uint8(0), B, uint256(0), uint256(5), hex"deadbeef01"
            ),
            "layout"
        );
        require(uint8(packed[0]) == 0 && uint8(packed[85]) == 0, "every operation is a CALL");
    }

    function test_refusesAnEmptyPlan() public {
        Call[] memory none = new Call[](0);
        vm.expectRevert(bytes("lattice-std: empty plan"));
        harness.encode(none);
        vm.expectRevert(bytes("lattice-std: empty plan"));
        harness.encode(none, bytes32(0), bytes32(0));
        vm.expectRevert(bytes("lattice-std: empty plan"));
        harness.pack(none);
    }

    function test_envReadsTheMaterializedBook() public {
        vm.createDir(".lattice", true);
        vm.writeFile(
            ".lattice/env.json",
            '{"id":"polygon-mainnet","chainId":137,"authority":{"kind":"safe","address":"0x3dcE0a29139A851Da1dFCa56Af8e8a6440b4D952","threshold":3,"owners":["0x00447A08bf275b7FB3D5d832387a54Be1090d281","0x3B0dfCe5C3A1e2D5bB1c2D8E5f6A7B8C9d0E1f2A"]},"contracts":{"timelock":{"address":"0x47EbFAC3353314C788B96CDCbf41daadfE03629C","kind":"singleton","route":"none"},"exchange":{"address":"0xe3333700cA9d93003F00f0F71f8515005F6c00Aa","kind":"proxy","route":"owner","implementation":{"address":"0x641b40ec414a076b9e79E703Fc7BF4EBEC248Bb7","staged":{"address":"0x7345C6842b244926125ed4054905cAc49620B5dc"}}}},"params":{"feeRecipient":"0x115F48DC2A731aA16251c6d6e1BEfC42f92Accc9","minDelay":"43200","paused":"false","skew":"-5","salt":"0x0000000000000000000000000000000000000000000000000000000000000007","blob":"0x1234","u8":"255","u8x":"256","u16":"65535","u16x":"65536","u32":"4294967295","u32x":"4294967296","u64":"18446744073709551615","u64x":"18446744073709551616","u128":"340282366920938463463374607431768211455","u128x":"340282366920938463463374607431768211456"}}'
        );
        require(Env.addr("exchange") == 0xe3333700cA9d93003F00f0F71f8515005F6c00Aa, "anchor");
        require(Env.implementation("exchange") == 0x641b40ec414a076b9e79E703Fc7BF4EBEC248Bb7, "implementation");
        require(Env.staged("exchange") == 0x7345C6842b244926125ed4054905cAc49620B5dc, "staged");
        require(
            keccak256(bytes(Env.str("feeRecipient"))) == keccak256("0x115F48DC2A731aA16251c6d6e1BEfC42f92Accc9"), "str"
        );
        require(Env.uint256_("minDelay") == 43200, "uint256");
        require(!Env.bool_("paused"), "bool");
        require(Env.addr_("feeRecipient") == 0x115F48DC2A731aA16251c6d6e1BEfC42f92Accc9, "addr_");
        require(Env.int256_("skew") == -5, "int256_");
        require(Env.bytes32_("salt") == bytes32(uint256(7)), "bytes32_");
        require(keccak256(Env.bytes_("blob")) == keccak256(hex"1234"), "bytes_");
        require(Env.uint8_("u8") == 255 && Env.uint16_("u16") == 65535 && Env.uint32_("u32") == 4294967295, "narrow");
        require(Env.uint64_("u64") == type(uint64).max && Env.uint128_("u128") == type(uint128).max, "wide");
        vm.expectRevert(bytes("lattice-std: param u8x does not fit its type"));
        harness.uint8_("u8x");
        vm.expectRevert(bytes("lattice-std: param u16x does not fit its type"));
        harness.uint16_("u16x");
        vm.expectRevert(bytes("lattice-std: param u32x does not fit its type"));
        harness.uint32_("u32x");
        vm.expectRevert(bytes("lattice-std: param u64x does not fit its type"));
        harness.uint64_("u64x");
        vm.expectRevert(bytes("lattice-std: param u128x does not fit its type"));
        harness.uint128_("u128x");
        require(Env.chainId() == 137, "chainId");
        require(Env.authority() == 0x3dcE0a29139A851Da1dFCa56Af8e8a6440b4D952, "authority");
        require(Env.authorityThreshold() == 3, "threshold");
        address[] memory owners = Env.authorityOwners();
        require(owners.length == 2 && owners[0] == 0x00447A08bf275b7FB3D5d832387a54Be1090d281, "owners");
        require(Env.has("exchange") && !Env.has("router"), "has");
        require(Env.hasStaged("exchange"), "hasStaged");

        // The test base over the same book.
        TestBaseHarness base = new TestBaseHarness();
        require(base.isMaterialized(), "materialized");
        base.skipUnless(); // a no-op with a book in place
        require(base.theTimelock() == 0x47EbFAC3353314C788B96CDCbf41daadfE03629C, "timelock");
        vm.store(
            0xe3333700cA9d93003F00f0F71f8515005F6c00Aa,
            0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc,
            bytes32(uint256(uint160(0x641b40ec414a076b9e79E703Fc7BF4EBEC248Bb7)))
        );
        require(base.live("exchange") == 0x641b40ec414a076b9e79E703Fc7BF4EBEC248Bb7, "liveImplementation");
        FakeGoverned asDeclared =
            new FakeGoverned(0x47EbFAC3353314C788B96CDCbf41daadfE03629C, 0x3dcE0a29139A851Da1dFCa56Af8e8a6440b4D952);
        FakeGoverned otherOwner =
            new FakeGoverned(0x00447A08bf275b7FB3D5d832387a54Be1090d281, 0x3dcE0a29139A851Da1dFCa56Af8e8a6440b4D952);
        FakeGoverned otherAdmin =
            new FakeGoverned(0x47EbFAC3353314C788B96CDCbf41daadfE03629C, 0x00447A08bf275b7FB3D5d832387a54Be1090d281);
        require(base.governed(address(asDeclared)), "governed as declared");
        require(!base.governed(address(otherOwner)) && !base.governed(address(otherAdmin)), "not governed as declared");
        FakeTarget target = new FakeTarget();
        base.callAuthority(address(target), abi.encodeWithSignature("poke()"));
        require(target.lastSender() == 0x3dcE0a29139A851Da1dFCa56Af8e8a6440b4D952, "callAsAuthority sender");
        // applyAsAuthority goes to the book's timelock: put a recording one there and watch the clock.
        FakeTimelock tl = new FakeTimelock();
        vm.etch(0x47EbFAC3353314C788B96CDCbf41daadfE03629C, address(tl).code);
        Call[] memory calls = new Call[](1);
        calls[0] = Call(0xe3333700cA9d93003F00f0F71f8515005F6c00Aa, 0, hex"1234");
        uint256 before = block.timestamp;
        bytes32 id = base.apply_(calls, bytes32(0), bytes32(uint256(7)));
        require(id == base.id(calls, bytes32(0), bytes32(uint256(7))), "apply id");
        require(block.timestamp == before + 60, "the clock did not move past the delay");
        require(
            keccak256(FakeTimelock(payable(0x47EbFAC3353314C788B96CDCbf41daadfE03629C)).lastData())
                == keccak256(
                    Timelock.execute(Erc7821.MODE_OPDATA, Erc7821.encode(calls, bytes32(0), bytes32(uint256(7))))
                ),
            "apply executed last"
        );
        require(
            FakeTimelock(payable(0x47EbFAC3353314C788B96CDCbf41daadfE03629C)).lastSender()
                == 0x3dcE0a29139A851Da1dFCa56Af8e8a6440b4D952,
            "apply sender"
        );
        require(base.state(bytes32(0)) == 1, "operationState reads the book's timelock");

        // A testnet's book, written over the first (forge runs test functions in parallel, and
        // Env reads one fixed path, so the two books share one test): an EOA authority with no
        // owner set recorded, and a proxy with nothing staged behind it — what a test placed
        // before a deploy step sees.
        vm.writeFile(
            ".lattice/env.json",
            '{"id":"polygon-amoy","chainId":80002,"authority":{"kind":"eoa","address":"0x00447A08bf275b7FB3D5d832387a54Be1090d281"},"contracts":{"exchange":{"address":"0xe3333700cA9d93003F00f0F71f8515005F6c00Aa","kind":"proxy","route":"owner","implementation":{"address":"0x641b40ec414a076b9e79E703Fc7BF4EBEC248Bb7"}}},"params":{}}'
        );
        require(Env.authority() == 0x00447A08bf275b7FB3D5d832387a54Be1090d281, "authority");
        require(Env.authorityOwners().length == 0, "owners");
        require(Env.authorityThreshold() == 0, "threshold");
        require(Env.has("exchange") && !Env.hasStaged("exchange"), "staged");
        require(Env.chainId() == 80002, "chainId");
    }

    function test_structsHaveTheirShape() public pure {
        Deployment[] memory ds = new Deployment[](1);
        ds[0] = Deployment({name: "counter", addr: A});
        EnvVar[] memory vars = new EnvVar[](1);
        vars[0] = EnvVar({key: "minDelay", value: "43200"});
        // One (string,address): the array's offset and length, the element's offset, the tuple's two
        // words, then the string's length and one word of data — seven words. One (string,string) has
        // a second string: nine.
        require(abi.encode(ds).length == 32 * 7, "Deployment[]");
        require(abi.encode(vars).length == 32 * 9, "EnvVar[]");
    }
}
