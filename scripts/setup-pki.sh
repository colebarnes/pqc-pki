#!/usr/bin/env bash
#
# Quantum-Safe PKI Setup Script
# Creates 1 Root CA (ML-DSA-87) + 3 Intermediate CAs (ML-DSA-65)
# and example end-entity certificates.
#
# Requirements: OpenSSL 3.5+ with native ML-DSA / ML-KEM support
#
# Usage:
#   export OPENSSL=/path/to/openssl-3.5/bin/openssl
#   export LD_LIBRARY_PATH=/path/to/openssl-3.5/lib64   # if needed
#   ./scripts/setup-pki.sh
#
set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration – edit these as needed
# ---------------------------------------------------------------------------
ROOT_ALG="ML-DSA-87"
INTER_ALG="ML-DSA-65"
ENC_EE_ALG="ML-KEM-768"
SIG_EE_ALG="ML-DSA-65"
TLS_EE_ALG="ML-DSA-65"

ROOT_DAYS=7300          # ~20 years
INTER_DAYS=3650         # ~10 years
EE_DAYS=825             # ~2.25 years

ORG="Example Organization"
COUNTRY="US"
STATE="California"
LOCALITY="San Francisco"
EMAIL="pki-admin@example.org"

# ---------------------------------------------------------------------------
# Locate OpenSSL
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKI_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${PKI_ROOT}"

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

# Ensure a usable default config exists (avoids missing openssl.cnf errors)
if [[ -z "${OPENSSL_CONF:-}" ]]; then
  if [[ -f "${PKI_ROOT}/../openssl-3.5/ssl/openssl.cnf" ]]; then
    export OPENSSL_CONF="${PKI_ROOT}/../openssl-3.5/ssl/openssl.cnf"
  elif [[ -f /home/workdir/artifacts/openssl-3.5/ssl/openssl.cnf ]]; then
    export OPENSSL_CONF=/home/workdir/artifacts/openssl-3.5/ssl/openssl.cnf
  fi
fi

echo "=== Using OpenSSL: $($OPENSSL version) ==="
echo "PKI root: ${PKI_ROOT}"

# Sanity check for PQC algorithms
if ! $OPENSSL list -signature-algorithms 2>/dev/null | grep -qi "ML-DSA-65"; then
  echo "ERROR: This OpenSSL does not support ML-DSA. Need OpenSSL 3.5+." >&2
  exit 1
fi
if ! $OPENSSL list -kem-algorithms 2>/dev/null | grep -qi "ML-KEM-768\|MLKEM768"; then
  echo "ERROR: This OpenSSL does not support ML-KEM. Need OpenSSL 3.5+." >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Helper
# ---------------------------------------------------------------------------
ensure_dirs() {
  local base="$1"
  mkdir -p "${base}"/{private,certs,crl,newcerts,csr}
  chmod 700 "${base}/private"
  touch "${base}/index.txt"
  [[ -f "${base}/serial" ]] || echo 1000 > "${base}/serial"
  [[ -f "${base}/crlnumber" ]] || echo 1000 > "${base}/crlnumber"
}

# ---------------------------------------------------------------------------
# 1. Root CA
# ---------------------------------------------------------------------------
echo ""
echo ">>> 1. Creating Root CA (${ROOT_ALG})"
ensure_dirs root-ca

if [[ ! -f root-ca/private/root-ca.key ]]; then
  $OPENSSL genpkey -algorithm "${ROOT_ALG}" -out root-ca/private/root-ca.key
  chmod 400 root-ca/private/root-ca.key
  echo "    Generated root-ca/private/root-ca.key"
else
  echo "    Root key already exists – skipping generation"
fi

if [[ ! -f root-ca/certs/root-ca.crt ]]; then
  $OPENSSL req -new -x509 -days ${ROOT_DAYS} \
    -config root-ca/openssl.cnf \
    -key root-ca/private/root-ca.key \
    -out root-ca/certs/root-ca.crt \
    -extensions v3_ca
  echo "    Generated root-ca/certs/root-ca.crt"
else
  echo "    Root certificate already exists – skipping"
fi

# ---------------------------------------------------------------------------
# 2. Intermediate CAs
# ---------------------------------------------------------------------------
create_intermediate() {
  local name="$1"          # e.g. intermediate-sig
  local cn="$2"
  local ou="$3"

  echo ""
  echo ">>> Creating ${name} (${INTER_ALG})"
  ensure_dirs "${name}"

  if [[ ! -f "${name}/private/${name}.key" ]]; then
    $OPENSSL genpkey -algorithm "${INTER_ALG}" -out "${name}/private/${name}.key"
    chmod 400 "${name}/private/${name}.key"
    echo "    Generated ${name}/private/${name}.key"
  else
    echo "    Key already exists – skipping generation"
  fi

  if [[ ! -f "${name}/csr/${name}.csr" ]]; then
    # Temporary subject override via environment is not reliable;
    # we use -subj and a minimal req
    $OPENSSL req -new \
      -key "${name}/private/${name}.key" \
      -out "${name}/csr/${name}.csr" \
      -subj "/C=${COUNTRY}/ST=${STATE}/L=${LOCALITY}/O=${ORG}/OU=${ou}/CN=${cn}/emailAddress=${EMAIL}"
    echo "    Generated ${name}/csr/${name}.csr"
  fi

  if [[ ! -f "${name}/certs/${name}.crt" ]]; then
    # Sign with Root using the intermediate extension.
    # openssl ca resolves relative paths in the config relative to its cwd,
    # so we must run it from the root-ca directory.
    (
      cd root-ca
      $OPENSSL ca -config openssl.cnf \
        -extensions v3_intermediate_ca \
        -days ${INTER_DAYS} -notext -batch \
        -in "../${name}/csr/${name}.csr" \
        -out "../${name}/certs/${name}.crt"
    )
    echo "    Generated ${name}/certs/${name}.crt"
  else
    echo "    Certificate already exists – skipping"
  fi

  # Chain
  cat "${name}/certs/${name}.crt" root-ca/certs/root-ca.crt > "${name}/certs/chain.pem"
  echo "    Created ${name}/certs/chain.pem"
}

create_intermediate "intermediate-sig" \
  "Example Signature Intermediate CA (ML-DSA-65)" \
  "Quantum Safe PKI - Signature CA"

create_intermediate "intermediate-tls" \
  "Example TLS Intermediate CA (ML-DSA-65)" \
  "Quantum Safe PKI - TLS CA"

create_intermediate "intermediate-enc" \
  "Example Encryption Intermediate CA (ML-DSA-65)" \
  "Quantum Safe PKI - Encryption CA"

# ---------------------------------------------------------------------------
# 3. Example End-Entity Certificates
# ---------------------------------------------------------------------------
echo ""
echo ">>> 3. Creating example end-entity certificates"

mkdir -p end-entity
chmod 700 end-entity 2>/dev/null || true

# --- Signature / Authentication EE ---
if [[ ! -f end-entity/alice-sig.key ]]; then
  $OPENSSL genpkey -algorithm "${SIG_EE_ALG}" -out end-entity/alice-sig.key
  chmod 400 end-entity/alice-sig.key
fi

if [[ ! -f end-entity/alice-sig.crt ]]; then
  $OPENSSL req -new \
    -key end-entity/alice-sig.key \
    -out end-entity/alice-sig.csr \
    -subj "/C=${COUNTRY}/ST=${STATE}/O=${ORG}/OU=Users/CN=Alice Example/emailAddress=alice@example.org"

  (
    cd intermediate-sig
    $OPENSSL ca -config openssl.cnf \
      -extensions signature_cert \
      -days ${EE_DAYS} -notext -batch \
      -in ../end-entity/alice-sig.csr \
      -out ../end-entity/alice-sig.crt
  )
  echo "    Created end-entity/alice-sig.{key,crt}  (ML-DSA signature/auth)"
fi

# --- TLS Server EE ---
if [[ ! -f end-entity/server.example.org.key ]]; then
  $OPENSSL genpkey -algorithm "${TLS_EE_ALG}" -out end-entity/server.example.org.key
  chmod 400 end-entity/server.example.org.key
fi

if [[ ! -f end-entity/server.example.org.crt ]]; then
  $OPENSSL req -new \
    -key end-entity/server.example.org.key \
    -out end-entity/server.example.org.csr \
    -subj "/C=${COUNTRY}/ST=${STATE}/O=${ORG}/OU=Web Services/CN=server.example.org" \
    -addext "subjectAltName=DNS:server.example.org,DNS:www.example.org,IP:127.0.0.1"

  (
    cd intermediate-tls
    $OPENSSL ca -config openssl.cnf \
      -extensions server_cert \
      -days ${EE_DAYS} -notext -batch \
      -in ../end-entity/server.example.org.csr \
      -out ../end-entity/server.example.org.crt
  )
  echo "    Created end-entity/server.example.org.{key,crt}  (TLS server)"
fi

# --- Encryption EE (ML-KEM) ---
# Pure KEM keys cannot sign a CSR. We create a temporary ML-DSA key to
# produce a valid CSR, then force the ML-KEM public key into the issued cert.
if [[ ! -f end-entity/bob-enc.key ]]; then
  $OPENSSL genpkey -algorithm "${ENC_EE_ALG}" -out end-entity/bob-enc.key
  chmod 400 end-entity/bob-enc.key
fi

if [[ ! -f end-entity/bob-enc.crt ]]; then
  # Temporary signature key solely for the CSR signature
  $OPENSSL genpkey -algorithm ML-DSA-65 -out end-entity/.tmp-csr-sig.key
  $OPENSSL req -new \
    -key end-entity/.tmp-csr-sig.key \
    -out end-entity/bob-enc.csr \
    -subj "/C=${COUNTRY}/ST=${STATE}/O=${ORG}/OU=Users/CN=Bob Example/emailAddress=bob@example.org"
  $OPENSSL pkey -in end-entity/bob-enc.key -pubout -out end-entity/bob-enc.pub

  $OPENSSL x509 -req \
    -in end-entity/bob-enc.csr \
    -CA intermediate-enc/certs/intermediate-enc.crt \
    -CAkey intermediate-enc/private/intermediate-enc.key \
    -CAcreateserial \
    -force_pubkey end-entity/bob-enc.pub \
    -days ${EE_DAYS} \
    -extfile intermediate-enc/openssl.cnf \
    -extensions encryption_cert \
    -out end-entity/bob-enc.crt
  rm -f end-entity/.tmp-csr-sig.key end-entity/bob-enc.pub 2>/dev/null || true
  echo "    Created end-entity/bob-enc.{key,crt}  (ML-KEM encryption)"
fi

# ---------------------------------------------------------------------------
# 4. Generate initial (empty) CRLs
# ---------------------------------------------------------------------------
echo ""
echo ">>> 4. Generating initial CRLs"

gencrl_one() {
  local name="$1"
  (
    cd "${name}"
    $OPENSSL ca -config openssl.cnf -gencrl -out "crl/${name}.crl.pem"
  )
  echo "    ${name}/crl/${name}.crl.pem"
}

gencrl_one root-ca
gencrl_one intermediate-sig
gencrl_one intermediate-tls
gencrl_one intermediate-enc

# ---------------------------------------------------------------------------
# 5. Verification
# ---------------------------------------------------------------------------
echo ""
echo ">>> 5. Verifying certificate chains"

verify_one() {
  local name="$1"
  local cert="$2"
  local chain="$3"
  if $OPENSSL verify -CAfile "${chain}" "${cert}" >/dev/null 2>&1; then
    echo "    OK  ${name}"
  else
    echo "    FAIL ${name}"
    $OPENSSL verify -CAfile "${chain}" "${cert}" || true
  fi
}

verify_one "Root self-check" root-ca/certs/root-ca.crt root-ca/certs/root-ca.crt
verify_one "Signature Intermediate" intermediate-sig/certs/intermediate-sig.crt root-ca/certs/root-ca.crt
verify_one "TLS Intermediate" intermediate-tls/certs/intermediate-tls.crt root-ca/certs/root-ca.crt
verify_one "Encryption Intermediate" intermediate-enc/certs/intermediate-enc.crt root-ca/certs/root-ca.crt
verify_one "Alice (sig)" end-entity/alice-sig.crt intermediate-sig/certs/chain.pem
verify_one "Server (TLS)" end-entity/server.example.org.crt intermediate-tls/certs/chain.pem
verify_one "Bob (enc)" end-entity/bob-enc.crt intermediate-enc/certs/chain.pem

echo ""
echo "=== Quantum-Safe PKI setup complete ==="
echo ""
echo "Root CA:          root-ca/certs/root-ca.crt"
echo "Signature Inter:  intermediate-sig/certs/intermediate-sig.crt + chain.pem"
echo "TLS Inter:        intermediate-tls/certs/intermediate-tls.crt + chain.pem"
echo "Encryption Inter: intermediate-enc/certs/intermediate-enc.crt + chain.pem"
echo ""
echo "Example EE certs in end-entity/"
echo "  alice-sig.*          – ML-DSA document/email/code/client auth"
echo "  server.example.org.* – ML-DSA TLS server"
echo "  bob-enc.*            – ML-KEM keyEncipherment"
echo ""
echo "CRLs:  */crl/*.crl.pem"
echo "  Generate / refresh:  ./scripts/gencrl.sh"
echo "  Revoke a cert:       ./scripts/revoke.sh <ca-name> <cert-file> [reason]"
echo ""
echo "To inspect a certificate:"
echo "  $OPENSSL x509 -in <cert> -text -noout"
echo "To inspect a CRL:"
echo "  $OPENSSL crl -in <crl.pem> -text -noout"
