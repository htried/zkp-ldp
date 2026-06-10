# zkp-ldp

This repository contains the code for "[zk-Cookies: Continuous Anonymous Authentication for the Web](https://eprint.iacr.org/2025/1938)".

Experiments and prototypes for privacy-preserving state credentials using Circom-based zero-knowledge proofs, with supporting demo frontend and server verification components.

This top-level README is intentionally brief and points to the right subproject docs.

## Where to start

- Main credential update circuit and experiments: `zk_cred_logic/README.md`
- Cold start (initial credential state) circuit: `zk_cred_cold_start_logic/README.md`
- Streaming-state experiment variant: `zk_cred_streaming_logic/README.md`
- Attribution circuits:
  - Single-step attribution: `zk_cred_attribution_single_logic/README.md`
  - Chained attribution: `zk_cred_attribution_chain_logic/README.md`
- Browser fingerprint service: `fingerprint_logic/README.md`
- Go credential verification server (SNARK verification + nullifier DB): `go_credential_server/README.md`

## Frontend demo

- Demo app code is in `frontend/`.
- The demo uses Rust+WASM proving directly in the browser.
- Circuit artifacts for the active demo circuit are served from `frontend/public/gh_20_fp_400/rust/`.
- Rust prover source lives in `frontend/rust_wasm_prover_poc/`.
- Toolchain notes are in `prove_verify/README.md`.

## Deploying demo on Vercel

1. Set the project root to `frontend/`.
2. Deploy with default build/start commands (`next build`, `next start`).
3. No prover backend environment variables are required for the current browser proving flow.
4. Redeploy.

## Additional directories

- `graphics/` contains figures and generated assets.
- `results/`, `results_attribution_single/`, and `results_attribution_chain/` contain experiment outputs.
- `self/` is a separate upstream project with its own documentation in `self/README.md`.

## License

See `LICENSE`.

## ⚠️WARNING⚠️
This code is released for the purposes of open science, and has not been reviewed for security. Do not use it for production applications.
