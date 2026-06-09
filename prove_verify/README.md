# Prover/Verifier Investigation Notes

This note compares practical proving/witness options for this repository and outlines a deployment approach using the existing `frontend` and `go_credential_server` skeletons.

## Current baseline in this repo

- `frontend/lib/zk_utils.ts` performs browser-side proving with `snarkjs.groth16.fullProve(...)`.
- `frontend/public/gh_*` already contains per-parameter circuit artifacts (`state.wasm`, `state_0001.zkey`, `verification_key.json`).
- `go_credential_server/main.go` already verifies Groth16 proofs via `go-rapidsnark` and handles nullifier persistence/signing.

## Option A: wasmsnark in browser

## Pros

- Browser-native proving path.
- Historically optimized for Groth16 in WebAssembly.

## Cons

- Old project and legacy flow.
- Requires binary witness (`witness.bin`) and proving key conversion (`proving_key.bin`) pipeline.
- Higher integration risk with modern Circom 2 pipelines.
- Not a clear upgrade over current `snarkjs` for maintainability.

## Verdict

- Not recommended as the primary direction for this repo unless there is a specific benchmark win on your exact circuits.

## Option B: circom-witnesscalc for witness generation

## Pros

- Faster witness generation than standard WASM witness generation in many circuits.
- Avoids JS/WASM witness runtime dependency in server environments.
- Designed as a drop-in witness generation alternative.

## Cons

- Adds Rust toolchain/build complexity to infra.
- May require compatibility testing for all circuit features in this repo.

## Verdict

- Strong candidate for server-side witness generation acceleration.

## Option C: Hosted binary prover/verifier stack

Use Rapidsnark binaries (or go-rapidsnark wrappers) on a real server and keep browser as an input/signing UX.

## Pros

- Best path for larger circuits and predictable production performance.
- Keeps heavy proving work off client devices.
- Matches existing server code direction in this repo.

## Cons

- Requires secure API boundary and operational setup.
- Need artifact/version management for multiple circuit variants (`gh_*`).

## Verdict

- Recommended primary direction.

## Suggested architecture (using current skeleton)

1. `frontend` collects state and locally signs inputs (already present).
2. Frontend sends signed JSON input + circuit id (for example `gh_20_fp_400`) to a prover API.
3. Prover service:
   - loads circuit artifacts for that id,
   - generates witness (`circom-witnesscalc` preferred, or existing witness generator fallback),
   - runs Rapidsnark proof generation,
   - returns `{ proof, publicSignals }`.
4. `go_credential_server` verifies proof and enforces nullifier uniqueness, then signs credential output.

## Minimal API split

- `POST /prove`: heavy compute endpoint (stateless worker preferred).
- `POST /verify`: existing verification/signing endpoint (`go_credential_server`).

## Deployment notes

- Put proving worker behind queue/concurrency control to prevent CPU exhaustion.
- Keep circuit artifacts immutable and versioned by hash.
- Restrict accepted circuit ids to an allowlist.
- Add request auth/rate limits before public exposure.
- Persist timing and failure metrics for each stage (witness, prove, verify).

## Recommended next implementation steps

1. Add a dedicated prover worker service (Node+rapidsnark CLI or Rust wrapper), initially for one circuit variant.
2. Update `frontend/pages/api/prove.ts` to call that worker instead of local file-path proving.
3. Route proof output into `go_credential_server` for final verification/signing.
4. Benchmark:
   - browser `snarkjs` baseline,
   - server witnesscalc + Rapidsnark,
   - end-to-end latency and throughput under load.

## CVM compile pipeline (upgraded attempt)

The repo now includes `prove_verify/build_cvm_artifacts.sh` to compile circuits with the `circom_cvm` fork and generate:

- `state.cvm` (CVM assembly)
- `state.wcd` (witnesscalc bytecode)
- plus `state.wasm` / `state.r1cs` for parity checks

Run:

```bash
./prove_verify/build_cvm_artifacts.sh /path/to/state.circom "AttemptStateUpdate(5)"
```

Output is written to `prove_verify/cvm_artifacts/`.

Current status:

- `circom_cvm` compilation works.
- `cvm-compile` to `.wcd` works.
- `calc-witness` currently fails fast with assertion errors on old input payloads, which indicates input/circuit-shape mismatch (the upgraded circuit expects fields/signing flow that differ from the deployed `gh_20_fp_400` artifact set).
