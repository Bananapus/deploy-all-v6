# Deploy All Operations

## Operator Checklist

- Verify sibling package addresses and expected artifacts before blaming this repo.
- Use [`script/Resume.s.sol`](../script/Resume.s.sol) when the rollout is partially complete instead of hand-editing deployment assumptions.
- Use [`script/Verify.s.sol`](../script/Verify.s.sol) after deployment to confirm on-chain state and published artifacts still align.

## Common Failure Modes

- A subsystem deployment changed shape, but this repo still assumes the old artifact or address.
- Operators debug runtime behavior here before confirming deployment shape is even correct.
- Recovery steps are skipped and the rollout is restarted in a way that breaks deterministic assumptions.
