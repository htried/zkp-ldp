#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_DIR="${TMPDIR:-/tmp}/circom-cvm-build"
OUT_DIR="${ROOT_DIR}/prove_verify/cvm_artifacts"

# Compile the circuit with circom_cvm, then precompile bytecode (.wcd) for calc-witness.
# Usage:
#   ./prove_verify/build_cvm_artifacts.sh /absolute/or/relative/path/to/circuit.circom "MainComponent(5)"
CIRCUIT_PATH="${1:-${ROOT_DIR}/zk_cred_logic/state.circom}"
MAIN_COMPONENT="${2:-AttemptStateUpdate(5)}"

if [[ ! -f "${CIRCUIT_PATH}" ]]; then
  echo "Circuit not found: ${CIRCUIT_PATH}" >&2
  exit 1
fi

ABS_CIRCUIT_PATH="$(cd "$(dirname "${CIRCUIT_PATH}")" && pwd)/$(basename "${CIRCUIT_PATH}")"
if [[ "${ABS_CIRCUIT_PATH}" == "${ROOT_DIR}"/* ]]; then
  CONTAINER_CIRCUIT_PATH="/repo/${ABS_CIRCUIT_PATH#${ROOT_DIR}/}"
else
  echo "Circuit path must be inside repo for Docker mount: ${ABS_CIRCUIT_PATH}" >&2
  exit 1
fi

mkdir -p "${WORK_DIR}" "${OUT_DIR}"

cat > "${WORK_DIR}/main.circom" <<EOF
pragma circom 2.2.0;
include "${CONTAINER_CIRCUIT_PATH}";
component main = ${MAIN_COMPONENT};
EOF

echo "Building circom_cvm and compiling circuit..."
docker run --rm \
  -v "${ROOT_DIR}:/repo" \
  -v "${WORK_DIR}:/work" \
  -w /work \
  rust:1.86-bookworm \
  bash -lc '
    export PATH=/usr/local/cargo/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
    apt-get update >/dev/null
    DEBIAN_FRONTEND=noninteractive apt-get install -y git pkg-config libssl-dev protobuf-compiler clang-16 >/dev/null
    if [ ! -d /work/circom_cvm ]; then
      git clone --depth 1 https://github.com/costa-group/circom_cvm.git /work/circom_cvm
    fi
    mkdir -p /work/out
    /work/circom_cvm/target/release/circom --version >/dev/null 2>&1 || \
      (cd /work/circom_cvm && cargo build --release >/dev/null)
    /work/circom_cvm/target/release/circom --r1cs --wasm --cvm --cvm_multi_assign /work/main.circom -o /work/out
  '

echo "Compiling .cvm to .wcd with witnesscalc..."
docker run --rm \
  -v "${ROOT_DIR}:/repo" \
  -v "${WORK_DIR}:/work" \
  -w /work \
  ubuntu:22.04 \
  bash -lc '
    chmod +x /repo/prove_verify/cvm_compile_linux_x64
    /repo/prove_verify/cvm_compile_linux_x64 /work/out/main_cvm/main.cvm -o /work/out/main.wcd
  '

cp -f "${WORK_DIR}/out/main.r1cs" "${OUT_DIR}/state.r1cs"
cp -f "${WORK_DIR}/out/main_js/main.wasm" "${OUT_DIR}/state.wasm"
cp -f "${WORK_DIR}/out/main_cvm/main.cvm" "${OUT_DIR}/state.cvm"
cp -f "${WORK_DIR}/out/main.wcd" "${OUT_DIR}/state.wcd"

echo "Done. Wrote:"
echo "  ${OUT_DIR}/state.r1cs"
echo "  ${OUT_DIR}/state.wasm"
echo "  ${OUT_DIR}/state.cvm"
echo "  ${OUT_DIR}/state.wcd"
