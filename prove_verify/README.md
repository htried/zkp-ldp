# Prover/Verifier Notes

This repository currently uses a single successful demo toolchain:

1. Browser signs circuit inputs in `frontend/lib/zk_utils.ts`.
2. Browser runs proof generation and verification using the Rust+WASM module in `frontend/rust_wasm_prover_poc/`.
3. Browser loads rust proving assets from `frontend/public/gh_20_fp_400/rust/`:
   - `state.ark-pkey`
   - `state.graph`
   - `state.r1cs`
   - `state.ark-vk.json`

## Current scope

- Active circuit profile: `gh_20_fp_400`.
- Active frontend flow: browser-only proving and verification.
- No `/api/prove` route is used in this toolchain.

## Legacy investigation note

Earlier experiments in this folder evaluated additional proving paths (server-hosted proving, CVM pipelines, and other alternatives). The current demo intentionally keeps only the Rust+WASM browser path above.
