# Vercel Demo Prover Design

> Historical note: this plan described an earlier `/api/prove` architecture. The current deployed demo uses browser-only Rust+WASM proving and does not use `frontend/pages/api/prove.ts`.

**Goal:** Deploy a real web demo on Vercel where proof generation runs server-side in the app backend, with a clean switch to an external native prover later.

## Design

Use a provider abstraction in `frontend/pages/api/prove.ts`:

- `local-snarkjs`: API route signs inputs and runs `snarkjs.groth16.fullProve`.
- `remote-prover`: API route forwards signed inputs to an external prover URL and returns proof outputs.

The frontend keeps one `/api/prove` integration point and does not need to know which provider is active.

## Data flow

1. Browser collects state and creates unsigned input.
2. Browser posts `{ input, circuitId }` to `/api/prove`.
3. API route signs inputs and executes selected provider.
4. API route verifies proof with the matching verification key.
5. Browser receives `{ proof, publicSignals, isValid, timing }`.

## Scope decisions

- Demo-first, no production hardening.
- Single default circuit variant (`gh_20_fp_400`) with allowlisted variants.
- Keep browser proving as fallback for local debugging only.
