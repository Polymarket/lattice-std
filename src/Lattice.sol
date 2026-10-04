// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

/// lattice-std: the structs and encoders a governance plan or deploy script returns and builds.
///
/// A consumer matches on ABI shape, never on a type's name or import path, so nothing in this
/// file is required — a plan may declare the structs itself. The libraries are conveniences
/// with fixed, tested encodings.

/// The unit of a plan: structurally identical to Safe's MetaTransaction and ERC-7821's Call.
struct Call {
    address to;
    uint256 value;
    bytes data;
}

/// What a deploy step returns: the address book's name for an address the broadcast created.
struct Deployment {
    string name;
    address addr;
}

/// What an envUpdates() step returns: one scalar param, as a decimal, hex, bool or address string.
struct EnvVar {
    string key;
    string value;
}

/// The forge cheatcodes this file uses, declared here so nothing has to be installed beside it.
interface LatticeVm {
    function readFile(string calldata path) external view returns (string memory);
    function parseJsonAddress(string calldata json, string calldata key) external pure returns (address);
    function parseJsonAddressArray(string calldata json, string calldata key) external pure returns (address[] memory);
    function parseJsonUint(string calldata json, string calldata key) external pure returns (uint256);
    function parseJsonString(string calldata json, string calldata key) external pure returns (string memory);
    function keyExistsJson(string calldata json, string calldata key) external view returns (bool);
    function parseAddress(string calldata value) external pure returns (address);
    function parseUint(string calldata value) external pure returns (uint256);
    function parseBool(string calldata value) external pure returns (bool);
}

/// ERC-7821 batch execution, as the Solady Timelock consumes it.
library Erc7821 {
    /// `Call[]` alone.
    bytes32 internal constant MODE = 0x0100000000000000000000000000000000000000000000000000000000000000;
    /// `Call[]` carrying opData — the (predecessor, salt) pair the timelock reads. What production uses.
    bytes32 internal constant MODE_OPDATA = 0x0100000000007821000100000000000000000000000000000000000000000000;

    /// executionData without opData: abi.encode(calls). An empty plan is refused.
    function encode(Call[] memory calls) internal pure returns (bytes memory) {
        require(calls.length != 0, "lattice-std: empty plan");
        return abi.encode(calls);
    }

    /// executionData with opData: abi.encode(calls, abi.encode(predecessor, salt)).
    function encode(Call[] memory calls, bytes32 predecessor, bytes32 salt) internal pure returns (bytes memory) {
        require(calls.length != 0, "lattice-std: empty plan");
        return abi.encode(calls, abi.encode(predecessor, salt));
    }

    /// The timelock's operation id: keccak256(abi.encode(mode, keccak256(executionData))).
    function opId(bytes32 mode, bytes memory executionData) internal pure returns (bytes32) {
        return keccak256(abi.encode(mode, keccak256(executionData)));
    }
}

/// Calldata for the Solady Timelock's governance entry points.
library Timelock {
    function propose(bytes32 mode, bytes memory d, uint256 delay) internal pure returns (bytes memory) {
        return abi.encodeWithSignature("propose(bytes32,bytes,uint256)", mode, d, delay);
    }

    function execute(bytes32 mode, bytes memory d) internal pure returns (bytes memory) {
        return abi.encodeWithSignature("execute(bytes32,bytes)", mode, d);
    }

    function cancel(bytes32 id) internal pure returns (bytes memory) {
        return abi.encodeWithSignature("cancel(bytes32)", id);
    }
}

/// Packing for MultiSendCallOnly. The result is the argument of multiSend(bytes), which the Safe
/// must send with operation = DelegateCall, or every inner call runs with MultiSend's authority.
library MultiSend {
    /// Per call, tightly packed: uint8 operation (always 0), address to, uint256 value,
    /// uint256 data.length, bytes data.
    function pack(Call[] memory calls) internal pure returns (bytes memory packed) {
        require(calls.length != 0, "lattice-std: empty plan");
        for (uint256 i = 0; i < calls.length; i++) {
            packed =
                abi.encodePacked(packed, uint8(0), calls[i].to, calls[i].value, calls[i].data.length, calls[i].data);
        }
    }
}

/// The environment materialized before every forge run at .lattice/env.json: the address
/// book's contracts by name, and its scalar params by key.
library Env {
    LatticeVm internal constant vm = LatticeVm(address(uint160(uint256(keccak256("hevm cheat code")))));
    string internal constant PATH = ".lattice/env.json";

    /// The anchor of a contract: `contracts.<name>.address`.
    function addr(string memory name) internal view returns (address) {
        return vm.parseJsonAddress(vm.readFile(PATH), string.concat(".contracts.", name, ".address"));
    }

    /// The implementation behind a proxy or beacon: `contracts.<name>.implementation.address`.
    function implementation(string memory name) internal view returns (address) {
        return vm.parseJsonAddress(vm.readFile(PATH), string.concat(".contracts.", name, ".implementation.address"));
    }

    /// An implementation deployed for a proxy or beacon that is not live behind it yet:
    /// `contracts.<name>.implementation.staged.address`. What an upgrade plan proposes.
    function staged(string memory name) internal view returns (address) {
        return
            vm.parseJsonAddress(vm.readFile(PATH), string.concat(".contracts.", name, ".implementation.staged.address"));
    }

    /// A param as recorded: `params.<key>`, always a string in the book.
    function str(string memory key) internal view returns (string memory) {
        return vm.parseJsonString(vm.readFile(PATH), string.concat(".params.", key));
    }

    function uint256_(string memory key) internal view returns (uint256) {
        return vm.parseUint(str(key));
    }

    function bool_(string memory key) internal view returns (bool) {
        return vm.parseBool(str(key));
    }

    /// A param that holds an address.
    function addr_(string memory key) internal view returns (address) {
        return vm.parseAddress(str(key));
    }

    /// The chain the book describes: `chainId`.
    function chainId() internal view returns (uint256) {
        return vm.parseJsonUint(vm.readFile(PATH), ".chainId");
    }

    /// The account that governs the environment: `authority.address` — the Protocol Safe, or the
    /// EOA on a testnet.
    function authority() internal view returns (address) {
        return vm.parseJsonAddress(vm.readFile(PATH), ".authority.address");
    }

    /// The owner set the book expects of a Safe authority: `authority.owners`. Empty when the book
    /// records none — an EOA, or a Safe nobody has recorded yet.
    function authorityOwners() internal view returns (address[] memory) {
        string memory book = vm.readFile(PATH);
        if (!vm.keyExistsJson(book, ".authority.owners")) return new address[](0);
        return vm.parseJsonAddressArray(book, ".authority.owners");
    }

    /// The threshold the book expects of a Safe authority: `authority.threshold`, zero when none
    /// is recorded.
    function authorityThreshold() internal view returns (uint256) {
        string memory book = vm.readFile(PATH);
        if (!vm.keyExistsJson(book, ".authority.threshold")) return 0;
        return vm.parseJsonUint(book, ".authority.threshold");
    }

    /// Whether the book names a contract.
    function has(string memory name) internal view returns (bool) {
        return vm.keyExistsJson(vm.readFile(PATH), string.concat(".contracts.", name));
    }

    /// Whether an implementation is staged behind a proxy or beacon — deployed by a release and
    /// not yet live. A test placed before the deploy step expects none.
    function hasStaged(string memory name) internal view returns (bool) {
        return vm.keyExistsJson(vm.readFile(PATH), string.concat(".contracts.", name, ".implementation.staged"));
    }
}
