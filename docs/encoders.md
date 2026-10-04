# Encoders: `Erc7821`, `Timelock`, `MultiSend`

Lattice encodes a plan's governance transactions itself, in Go, and these libraries produce the
same bytes in Solidity — proven byte for byte by the Lattice repository's `test/differential`
against the operation governance executed at Safe nonce 147. A release script does **not** need
them: `build()` returns inner calls and Lattice does the rest ([scripts.md](./scripts.md)). They
exist for the two cases where Solidity has to speak the chain's language itself:

- a **simulation** that applies a plan under `prank` without Lattice (safe-sim's path; `LatticeTest`'s `proposeAs` / `executeAs` / `applyAsAuthority` use them, [testing.md](./testing.md)),
- a **check** that recomputes an operation id or a MultiSend payload to compare with what landed.

| Library | Function | Produces |
|---|---|---|
| `Erc7821` | `MODE` | The ERC-7821 batch mode with no opData: `0x01000000…`. |
| | `MODE_OPDATA` | The batch mode with opData — `(predecessor, salt)` inside `executionData` — which is what production proposals use: `0x0100000000007821000100…`. |
| | `encode(calls)` | `executionData` without opData: `abi.encode(calls)`. Refuses an empty plan. |
| | `encode(calls, predecessor, salt)` | `executionData` with opData: `abi.encode(calls, abi.encode(predecessor, salt))`. Refuses an empty plan. |
| | `opId(mode, executionData)` | The Solady Timelock's operation id, `keccak256(abi.encode(mode, keccak256(executionData)))`. |
| `Timelock` | `propose(mode, executionData, delay)` | Calldata for `propose(bytes32,bytes,uint256)`: what the Safe sends the timelock. |
| | `execute(mode, executionData)` | Calldata for `execute(bytes32,bytes)`, after the delay. |
| | `cancel(id)` | Calldata for `cancel(bytes32)`. |
| `MultiSend` | `pack(calls)` | The argument of `MultiSendCallOnly.multiSend(bytes)`: per call `uint8 operation` (always 0), `address to`, `uint256 value`, `uint256 data.length`, `bytes data`, tightly packed. The Safe must send it with `operation = DelegateCall`, or every inner call runs with MultiSend's authority. Refuses an empty plan. |

```solidity
bytes memory d = Erc7821.encode(calls, bytes32(0), salt);
bytes32 id = Erc7821.opId(Erc7821.MODE_OPDATA, d);
bytes memory proposeCalldata = Timelock.propose(Erc7821.MODE_OPDATA, d, 12 hours);
```

Both `encode` forms and `pack` refuse an empty plan: 32 zero bytes is valid ABI for an empty
`Call[]`, and proposing it would burn an authority nonce to do nothing. Lattice's Go side refuses
the same way; do not remove either `require`.
