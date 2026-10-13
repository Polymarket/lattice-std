// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import {LatticeTest} from "../src/LatticeTest.sol";

interface GovernedVm {
    function createDir(string calldata path, bool recursive) external;
    function writeFile(string calldata path, string calldata data) external;
    function toString(uint256 value) external pure returns (string memory);
    function toString(address value) external pure returns (string memory);
}

/// A target with an owner and one admin, the shape Solady's OwnableRoles presents.
contract GovernedTarget {
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

/// Exposes the base's name-based governance check over a book of its own. Forge runs tests in
/// parallel, so every test below writes a file nothing else writes. (The address form reads the
/// timelock off Env's fixed path and is exercised with the default book elsewhere.)
abstract contract GovernedHarness is LatticeTest {
    function byName(string memory name) external view returns (bool) {
        return governedAsDeclared(name);
    }
}

contract GovernedHarnessA is GovernedHarness {
    function bookPath() internal pure override returns (string memory) {
        return ".lattice/governed-a.json";
    }
}

contract GovernedHarnessB is GovernedHarness {
    function bookPath() internal pure override returns (string memory) {
        return ".lattice/governed-b.json";
    }
}

/// `governedAsDeclared(name)` reads the book: owned by the timelock always, the admin role only
/// where the book declares it.
contract GovernedAsDeclaredTest {
    GovernedVm constant vm = GovernedVm(address(uint160(uint256(keccak256("hevm cheat code")))));
    address constant AUTHORITY = 0x00447A08bf275b7FB3D5d832387a54Be1090d281;
    address constant TIMELOCK = 0x47EbFAC3353314C788B96CDCbf41daadfE03629C;

    function setUp() public {
        vm.createDir(".lattice", true);
    }

    /// Writes a book at path: the timelock, and one contract `x` at target with the admin role
    /// declared as given ("" writes no adminRole field at all).
    function writeBook(string memory path, address target, string memory adminRole) internal {
        string memory x = string.concat('"x":{"address":"', vm.toString(target), '"');
        if (bytes(adminRole).length != 0) x = string.concat(x, ',"adminRole":', adminRole);
        x = string.concat(x, "}");
        vm.writeFile(
            path,
            string.concat(
                '{"id":"t","chainId":',
                vm.toString(block.chainid),
                ',"authority":{"kind":"safe","address":"',
                vm.toString(AUTHORITY),
                '"},"contracts":{"timelock":{"address":"',
                vm.toString(TIMELOCK),
                '"},',
                x,
                '},"params":{}}'
            )
        );
    }

    function test_ownerGovernedOnlyPassesOnItsOwner() public {
        GovernedHarnessA h = new GovernedHarnessA();
        // The Router's shape: the timelock owns it, nobody holds its roles.
        GovernedTarget t = new GovernedTarget(TIMELOCK, address(0));
        writeBook(".lattice/governed-a.json", address(t), "");
        require(h.byName("x"), "owner-governed only, as declared");
        writeBook(".lattice/governed-a.json", address(t), "false");
        require(h.byName("x"), "adminRole false is owner-governed only");
        writeBook(".lattice/governed-a.json", address(t), "true");
        require(!h.byName("x"), "the book declares a role the authority does not hold");
    }

    function test_adminGovernedNeedsTheRoleAndTheOwner() public {
        GovernedHarnessB h = new GovernedHarnessB();
        GovernedTarget t = new GovernedTarget(TIMELOCK, AUTHORITY);
        writeBook(".lattice/governed-b.json", address(t), "true");
        require(h.byName("x"), "owner and role, as declared");
        GovernedTarget stray = new GovernedTarget(address(0xBEEF), AUTHORITY);
        writeBook(".lattice/governed-b.json", address(stray), "true");
        require(!h.byName("x"), "owned by somebody else");
        writeBook(".lattice/governed-b.json", address(stray), "");
        require(!h.byName("x"), "owned by somebody else, role or not");
    }
}
