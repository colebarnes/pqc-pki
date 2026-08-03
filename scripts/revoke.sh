#!/usr/bin/env bash
#
# Revoke a certificate and regenerate the corresponding CRL
#
# Usage:
#   ./scripts/revoke.sh <intermediate-name> <cert-file> [reason]
#
# Examples:
#   ./scripts/revoke.sh intermediate-sig end-entity/alice-sig.crt
#   ./scripts/revoke.sh intermediate-tls end-entity/server.example.org.crt keyCompromise
#
# Reasons (optional): unspecified, keyCompromise, CACompromise, affiliationChanged,
#                     superseded, cessationOfOperation, certificateHold, removeFromCRL
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKI_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${PKI_ROOT}"

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <intermediate-name> <cert-file> [reason]"
  echo "  intermediate-name: intermediate-sig | intermediate-tls | intermediate-enc | root-ca"
  exit 1
fi

CA_NAME="$1"
CERT_FILE="$2"
REASON="${3:-unspecified}"

# Locate OpenSSL
if [[ -n "${OPENSSL:-}" ]]; then
  :
elif [[ -x /home/workdir/artifacts/openssl-3.5/bin/openssl ]]; then
  OPENSSL=/home/workdir/artifacts/openssl-3.5/bin/openssl
  export LD_LIBRARY_PATH=/home/workdir/artifacts/openssl-3.5/lib64${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
elif command -v openssl >/dev/null 2>&1; then
  OPENSSL=$(command -v openssl)
else
  echo "ERROR: OpenSSL not found." >&2
  exit 1
fi

if [[ -z "${OPENSSL_CONF:-}" ]]; then
  if [[ -f /home/workdir/artifacts/openssl-3.5/ssl/openssl.cnf ]]; then
    export OPENSSL_CONF=/home/workdir/artifacts/openssl-3.5/ssl/openssl.cnf
  fi
fi

if [[ ! -d "${CA_NAME}" ]]; then
  echo "ERROR: CA directory ${CA_NAME} not found" >&2
  exit 1
fi
if [[ ! -f "${CERT_FILE}" ]]; then
  echo "ERROR: Certificate file ${CERT_FILE} not found" >&2
  exit 1
fi

echo ">>> Revoking ${CERT_FILE} under ${CA_NAME} (reason=${REASON})"
(
  cd "${CA_NAME}"
  $OPENSSL ca -config openssl.cnf \
    -revoke "../${CERT_FILE}" \
    -crl_reason "${REASON}"
)

echo ">>> Regenerating CRL"
(
  cd "${CA_NAME}"
  $OPENSSL ca -config openssl.cnf -gencrl -out "crl/${CA_NAME}.crl.pem"
)

echo "    Updated ${CA_NAME}/crl/${CA_NAME}.crl.pem"
$OPENSSL crl -in "${CA_NAME}/crl/${CA_NAME}.crl.pem" -noout -text | head -20
echo ""
echo "=== Revocation complete ==="
