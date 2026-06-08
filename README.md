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
- The frontend now uses hosted proving via `frontend/pages/api/prove.ts` by default.
- Circuit artifacts (for geohash/fingerprint threshold variants) are served from `frontend/public/gh_*`.
- Prover/verifier implementation notes and demo plan are in `prove_verify/`.

## Deploying demo on Vercel

1. Set the project root to `frontend/`.
2. Deploy with default build/start commands (`next build`, `next start`).
3. Add environment variables:
   - `PROVER_MODE=local-snarkjs` (default hosted proving inside the Next.js API route)
   - Optional: `NEXT_PUBLIC_ENABLE_BROWSER_PROVE_FALLBACK=false`
4. Redeploy.

### Optional external optimized prover

If you have a native prover service (for example Rapidsnark-based), switch to:

- `PROVER_MODE=remote-prover`
- `EXTERNAL_PROVER_URL=https://<your-prover-endpoint>`

The app still calls `/api/prove`; the API route forwards requests to the external prover when this mode is enabled.

## Additional directories

- `graphics/` contains figures and generated assets.
- `results/`, `results_attribution_single/`, and `results_attribution_chain/` contain experiment outputs.
- `self/` is a separate upstream project with its own documentation in `self/README.md`.

## License

See `LICENSE`.

## ⚠️WARNING⚠️
This code is released for the purposes of open science, and has not been reviewed for security. Do not use it for production applications.
