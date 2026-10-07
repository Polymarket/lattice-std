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
| | `encode(calls)` | `executionData` without opData: `abi.encode(calls)`. Refuses an empty plan and a call to the zero address. |
| | `encode(calls, predecessor, salt)` | `executionData` with opData: `abi.encode(calls, abi.encode(predecessor, salt))`. Pair it with `MODE_OPDATA`. Refuses an empty plan and a call to the zero address. |
| | `opId(mode, executionData)` | The Solady Timelock's operation id, `keccak256(abi.encode(mode, keccak256(executionData)))`. Refuses opData under `MODE`. |
| `Timelock` | `propose(mode, executionData, delay)` | Calldata for `propose(bytes32,bytes,uint256)`: what the Safe sends the timelock. Refuses opData under `MODE`. |
| | `execute(mode, executionData)` | Calldata for `execute(bytes32,bytes)`, after the delay. Refuses opData under `MODE`. |
| | `cancel(id)` | Calldata for `cancel(bytes32)`. |
| `MultiSend` | `pack(calls)` | The argument of `MultiSendCallOnly.multiSend(bytes)`: per call `uint8 operation` (always 0), `address to`, `uint256 value`, `uint256 data.length`, `bytes data`, tightly packed. The Safe must send it with `operation = DelegateCall`, or every inner call runs with MultiSend's authority. Refuses an empty plan and a call to the zero address. |

```solidity
bytes memory d = Erc7821.encode(calls, bytes32(0), salt);
bytes32 id = Erc7821.opId(Erc7821.MODE_OPDATA, d);
bytes memory proposeCalldata = Timelock.propose(Erc7821.MODE_OPDATA, d, 12 hours);
```

Both `encode` forms and `pack` refuse an empty plan: 32 zero bytes is valid ABI for an empty
`Call[]`, and proposing it would burn an authority nonce to do nothing. Lattice's Go side refuses
the same way; do not remove either `require`.

Both `encode` forms and `pack` also refuse a call to the zero address. ERC-7821 rewrites a zero
target to `address(this)`, and so does Safe 1.4's MultiSendCallOnly, so an address that was never
set — an explicit zero in the book, or a slot of `new Call[](n)` left unfilled — would send the call
to the timelock or the Safe itself: governance calling governance.

`opId`, `Timelock.propose` and `Timelock.execute` refuse `MODE` with `executionData` that carries
opData. ERC-7821 reads opData only under `MODE_OPDATA`. Under `MODE` the timelock accepts the
proposal, the id hashes the predecessor and looks right, and at execution the predecessor check is
skipped: the ordering the plan asked for is silently gone. A zero predecessor is ignored on chain,
so `MODE_OPDATA` with `encode(calls, bytes32(0), salt)` covers every plain case.
