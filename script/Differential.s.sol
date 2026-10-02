// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Call, Deployment, Erc7821, Timelock, MultiSend} from "../src/Lattice.sol";

/// The cheatcodes this script needs, declared inline like everything else here.
interface Vm {
    function readFile(string calldata path) external view returns (string memory);
    function parseJsonUint(string calldata json, string calldata key) external pure returns (uint256);
    function parseJsonBytes32(string calldata json, string calldata key) external pure returns (bytes32);
    function parseJsonAddress(string calldata json, string calldata key) external pure returns (address);
    function parseJsonBytes(string calldata json, string calldata key) external pure returns (bytes memory);
    function parseJsonString(string calldata json, string calldata key) external pure returns (string memory);
    function toString(uint256 value) external pure returns (string memory);
}

/// Runs every encoder lattice-std has over one input document, so an independent
/// implementation can compare its encodings byte for byte. The input is
/// .lattice/input.json: {"n", "predecessor", "salt", "delay", "calls": [{"name","to","value","data"}]}.
/// The result is abi.encode(head, tail): head = (plain, withOpData, opId, opIdWithOpData), tail =
/// (propose, execute, cancel, packed, deployments) — two halves, because the legacy code
/// generator runs out of stack on one nine-field return.
contract Differential {
    Vm constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function run() external view returns (bytes memory) {
        (Call[] memory calls, Deployment[] memory named, bytes32 predecessor, bytes32 salt, uint256 delay) = parse();
        return abi.encode(head(calls, predecessor, salt), tail(calls, named, predecessor, salt, delay));
    }

    /// executionData without and with opData, and the operation id of each.
    function head(Call[] memory calls, bytes32 predecessor, bytes32 salt) internal pure returns (bytes memory) {
        bytes memory plain = Erc7821.encode(calls);
        bytes memory withOpData = Erc7821.encode(calls, predecessor, salt);
        return
            abi.encode(
                plain, withOpData, Erc7821.opId(Erc7821.MODE, plain), Erc7821.opId(Erc7821.MODE_OPDATA, withOpData)
            );
    }

    /// The timelock calldata, the MultiSend packing and the Deployment[] shape.
    function tail(Call[] memory calls, Deployment[] memory named, bytes32 predecessor, bytes32 salt, uint256 delay)
        internal
        pure
        returns (bytes memory)
    {
        bytes memory d = Erc7821.encode(calls, predecessor, salt);
        bytes32 id = Erc7821.opId(Erc7821.MODE_OPDATA, d);
        return abi.encode(
            Timelock.propose(Erc7821.MODE_OPDATA, d, delay),
            Timelock.execute(Erc7821.MODE_OPDATA, d),
            Timelock.cancel(id),
            MultiSend.pack(calls),
            abi.encode(named)
        );
    }

    function parse()
        internal
        view
        returns (Call[] memory calls, Deployment[] memory named, bytes32 predecessor, bytes32 salt, uint256 delay)
    {
        string memory doc = vm.readFile(".lattice/input.json");
        uint256 n = vm.parseJsonUint(doc, ".n");
        calls = new Call[](n);
        named = new Deployment[](n);
        for (uint256 i = 0; i < n; i++) {
            string memory at = string.concat(".calls[", vm.toString(i), "]");
            calls[i] = Call({
                to: vm.parseJsonAddress(doc, string.concat(at, ".to")),
                value: vm.parseJsonUint(doc, string.concat(at, ".value")),
                data: vm.parseJsonBytes(doc, string.concat(at, ".data"))
            });
            named[i] = Deployment({name: vm.parseJsonString(doc, string.concat(at, ".name")), addr: calls[i].to});
        }
        predecessor = vm.parseJsonBytes32(doc, ".predecessor");
        salt = vm.parseJsonBytes32(doc, ".salt");
        delay = vm.parseJsonUint(doc, ".delay");
    }
}
