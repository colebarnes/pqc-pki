#!/usr/bin/env bash
#
# Generate (or refresh) CRLs for Root and Intermediate CAs
#
# Usage:
#   ./scripts/gencrl.sh                  # generate all
#   ./scripts/gencrl.sh root             # only root
#   ./scripts/gencrl.sh intermediate-sig # only one intermediate
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKI_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${PKI_ROOT}"

# Locate OpenSSL
if [[ -n "${OPENSSL:-}" ]]; then
  :
elif [[ -x /home/workdir/artifacts/openssl-3.5/bin/openssl ]]; then
  OPENSSL=/home/workdir/artifacts/openssl-3.5/bin/openssl
  export LD_LIBRARY_PATH=/home/workdir/artifacts/openssl-3.5/lib64${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
elif command -v openssl >/dev/null 2>&1; then
  OPENSSL=$(command -v openssl)
else
  echo "ERROR: OpenSSL not found. Set OPENSSL environment variable." >&2
  exit 1
fi

if [[ -z "${OPENSSL_CONF:-}" ]]; then
  if [[ -f /home/workdir/artifacts/openssl-3.5/ssl/openssl.cnf ]]; then
    export OPENSSL_CONF=/home/workdir/artifacts/openssl-3.5/ssl/openssl.cnf
  fi
fi

gencrl_one() {
  local name="$1"   # root-ca | intermediate-sig | ...
  local outname="${2:-$name}"

  echo ">>> Generating CRL for ${name}"
  (
    cd "${name}"
    $OPENSSL ca -config openssl.cnf -gencrl -out "crl/${outname}.crl.pem"
  )
  echo "    Wrote ${name}/crl/${outname}.crl.pem"
  $OPENSSL crl -in "${name}/crl/${outname}.crl.pem" -noout -text | head -12
  echo ""
}

TARGET="${1:-all}"

case "${TARGET}" in
  all)
    gencrl_one root-ca root-ca
    gencrl_one intermediate-sig intermediate-sig
    gencrl_one intermediate-tls intermediate-tls
    gencrl_one intermediate-enc intermediate-enc
    ;;
  root|root-ca)
    gencrl_one root-ca root-ca
    ;;
  intermediate-sig|sig)
    gencrl_one intermediate-sig intermediate-sig
    ;;
  intermediate-tls|tls)
    gencrl_one intermediate-tls intermediate-tls
    ;;
  intermediate-enc|enc)
    gencrl_one intermediate-enc intermediate-enc
    ;;
  *)
    echo "Usage: $0 [all|root|intermediate-sig|intermediate-tls|intermediate-enc]"
    exit 1
    ;;
esac

echo "=== CRL generation complete ==="
