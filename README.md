# Quantum-Safe PKI (OpenSSL + ML-DSA / ML-KEM)

Complete, ready-to-use post-quantum PKI hierarchy built with OpenSSL 3.5+ native support for NIST FIPS 203 (ML-KEM) and FIPS 204 (ML-DSA).

Initial script generated with much help from Grok!

## Hierarchy

```
Root CA (ML-DSA-87)
├── Signature Intermediate CA (ML-DSA-65)
│   └── End-entity certs (ML-DSA-65)
│       Purpose: digitalSignature, nonRepudiation, clientAuth,
│                codeSigning, emailProtection, document signing
├── TLS Intermediate CA (ML-DSA-65)
│   └── End-entity certs (ML-DSA-65)
│       Purpose: serverAuth, digitalSignature (+ SAN)
└── Encryption Intermediate CA (ML-DSA-65)
    └── End-entity certs (ML-KEM-768)
        Purpose: keyEncipherment
```

## Requirements

- OpenSSL **3.5 or later** (native ML-DSA / ML-KEM support).
- The setup script auto-detects a build under `artifacts/openssl-3.5` if present.

## Quick Start

```bash
# If you have OpenSSL 3.5 elsewhere:
export OPENSSL=/path/to/openssl-3.5/bin/openssl
export LD_LIBRARY_PATH=/path/to/openssl-3.5/lib64   # if needed

cd quantum-safe-pki
chmod +x scripts/*.sh
./scripts/setup-pki.sh
```

The script is idempotent: existing keys/certificates are left untouched.

## Directory Layout

```
quantum-safe-pki/
├── root-ca/
│   ├── openssl.cnf
│   ├── private/root-ca.key
│   ├── certs/root-ca.crt
│   ├── index.txt, serial, crlnumber
│   └── …
├── intermediate-sig/     # Signature & Authentication CA
├── intermediate-tls/     # TLS Server CA
├── intermediate-enc/     # Encryption (ML-KEM) CA
├── end-entity/           # Example leaf certificates + keys
└── scripts/setup-pki.sh
```

Each intermediate directory also contains a `certs/chain.pem` (intermediate + root).

## Customization

Edit the variables at the top of `scripts/setup-pki.sh`:

- Algorithm parameter sets (`ROOT_ALG`, `INTER_ALG`, `ENC_EE_ALG`, …)
- Validity periods
- Organization / subject fields

Or edit the `openssl.cnf` files directly for more advanced policy / extension control.

## Issuing Additional Certificates

**Signature / Auth example:**

```bash
openssl genpkey -algorithm ML-DSA-65 -out end-entity/user.key
openssl req -new -key end-entity/user.key -out end-entity/user.csr \
  -subj "/C=US/O=Example Organization/CN=User Name/emailAddress=user@example.org"
openssl ca -config intermediate-sig/openssl.cnf \
  -extensions signature_cert -days 825 -notext -batch \
  -in end-entity/user.csr -out end-entity/user.crt
```

**TLS server example** (remember SAN):

```bash
openssl req -new -key server.key -out server.csr \
  -subj "/C=US/O=Example Organization/CN=app.example.org" \
  -addext "subjectAltName=DNS:app.example.org,DNS:*.app.example.org"
openssl ca -config intermediate-tls/openssl.cnf \
  -extensions server_cert -days 825 -notext -batch \
  -in server.csr -out server.crt
```

**Encryption (ML-KEM) example:**

```bash
openssl genpkey -algorithm ML-KEM-768 -out enc.key
openssl req -new -key enc.key -out enc.csr \
  -subj "/C=US/O=Example Organization/CN=enc-user@example.org"
openssl ca -config intermediate-enc/openssl.cnf \
  -extensions encryption_cert -days 825 -notext -batch \
  -in enc.csr -out enc.crt
```

## Verification

```bash
openssl verify -CAfile intermediate-sig/certs/chain.pem end-entity/alice-sig.crt
openssl x509 -in end-entity/bob-enc.crt -text -noout   # inspect ML-KEM key
```

## Notes

- All CA private keys are mode 400.
- ML-KEM certificates carry a KEM public key; the signature on the certificate itself is still produced by the intermediate’s ML-DSA key.
- For production, protect CA keys with HSMs or strong passphrases, enable CRLs/OCSP, and tighten the `policy_*` sections.
- Parameter sets can be changed to ML-DSA-44 / ML-KEM-512 (smaller) or ML-DSA-87 / ML-KEM-1024 (higher security / CNSA 2.0 style).

## CRL Support

Each CA maintains a Certificate Revocation List.

### Generate / refresh all CRLs

```bash
./scripts/gencrl.sh
# or individual:
./scripts/gencrl.sh root
./scripts/gencrl.sh intermediate-sig
```

CRLs are written to:

- `root-ca/crl/root-ca.crl.pem`
- `intermediate-sig/crl/intermediate-sig.crl.pem`
- `intermediate-tls/crl/intermediate-tls.crl.pem`
- `intermediate-enc/crl/intermediate-enc.crl.pem`

### Revoke a certificate

```bash
./scripts/revoke.sh intermediate-sig end-entity/alice-sig.crt
./scripts/revoke.sh intermediate-tls end-entity/server.example.org.crt keyCompromise
```

Supported reasons: `unspecified`, `keyCompromise`, `CACompromise`, `affiliationChanged`,
`superseded`, `cessationOfOperation`, `certificateHold`, `removeFromCRL`.

After revocation the corresponding CRL is automatically regenerated.

### Inspect a CRL

```bash
openssl crl -in intermediate-sig/crl/intermediate-sig.crl.pem -text -noout
```

### CDP in certificates

End-entity certificates include a `crlDistributionPoints` extension pointing to:

```
http://pki.example.org/crl/<ca-name>.crl
```

Change the URI in the `[signature_cert]`, `[server_cert]` and `[encryption_cert]`
sections of the intermediate `openssl.cnf` files to match your real distribution point.
