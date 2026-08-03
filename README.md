# Quantum-Safe PKI (OpenSSL + ML-DSA / ML-KEM)

A ready-to-use **post-quantum certificate hierarchy** built with OpenSSL 3.5+ and the NIST standards:

- **ML-DSA** (FIPS 204) for signatures
- **ML-KEM** (FIPS 203) for key encapsulation

> **⚠️ Important – Testing & Development Only**  
> This project is intended for **learning, experimentation, interoperability testing, and development** of post-quantum cryptography.  
> It is **not** a production-grade PKI.  
> Do **not** use the generated keys or certificates to protect real systems, production traffic, code signing of released software, or any environment where security failures have real consequences.  
> Private keys are stored on disk in plaintext (mode 400), there is no HSM support, no strong access control, no audited procedures, and the default policies are intentionally permissive for ease of use.

Initial scripts were generated with assistance from Grok.

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

- **OpenSSL 3.5 or later** (native ML-DSA / ML-KEM support — no oqs-provider required)
- A Unix-like environment (Linux, macOS, WSL, etc.)

Verify support:

```bash
openssl list -signature-algorithms | grep -i ml-dsa
openssl list -kem-algorithms      | grep -i ml-kem
```

## Quick Start

```bash
# Optional: point to a specific OpenSSL 3.5+ binary
export OPENSSL=/path/to/openssl-3.5/bin/openssl
export LD_LIBRARY_PATH=/path/to/openssl-3.5/lib64   # if needed

chmod +x scripts/*.sh
./scripts/setup-pki.sh
```

The script is **idempotent** — existing keys and certificates are left untouched.  
It creates the full hierarchy, example end-entity certificates, and initial (empty) CRLs.

## Directory Layout

```
pqc-pki/
├── root-ca/                 # Root CA (ML-DSA-87)
├── intermediate-sig/        # Signature & Authentication CA
├── intermediate-tls/        # TLS Server CA
├── intermediate-enc/        # Encryption (ML-KEM) CA
├── end-entity/              # Example leaf certificates & keys
└── scripts/
    ├── setup-pki.sh         # Bootstrap the entire hierarchy
    ├── gencrl.sh            # Generate / refresh CRLs
    └── revoke.sh            # Revoke a certificate + update CRL
```

Each intermediate also produces a `certs/chain.pem` (intermediate + root).

## Customization

Edit the variables at the top of `scripts/setup-pki.sh`:

- Algorithm parameter sets (`ROOT_ALG`, `INTER_ALG`, `ENC_EE_ALG`, …)
- Validity periods
- Organization / subject fields

Or edit the `openssl.cnf` files directly for more advanced policy and extension control.

You can switch to smaller parameter sets (ML-DSA-44 / ML-KEM-512) or higher-security ones (ML-DSA-87 / ML-KEM-1024, closer to CNSA 2.0 guidance).

## Issuing Additional Certificates

**Signature / Authentication**

```bash
openssl genpkey -algorithm ML-DSA-65 -out end-entity/user.key
openssl req -new -key end-entity/user.key -out end-entity/user.csr \
  -subj "/C=US/O=Example Organization/CN=User Name/emailAddress=user@example.org"

# Run from the intermediate directory or adjust paths
cd intermediate-sig
openssl ca -config openssl.cnf -extensions signature_cert \
  -days 825 -notext -batch \
  -in ../end-entity/user.csr -out ../end-entity/user.crt
```

**TLS Server** (include SANs)

```bash
openssl req -new -key server.key -out server.csr \
  -subj "/C=US/O=Example Organization/CN=app.example.org" \
  -addext "subjectAltName=DNS:app.example.org,DNS:*.app.example.org"

cd intermediate-tls
openssl ca -config openssl.cnf -extensions server_cert \
  -days 825 -notext -batch \
  -in ../server.csr -out ../server.crt
```

**Encryption (ML-KEM)**  
Pure KEM keys cannot sign a CSR. The setup script uses a temporary ML-DSA key for the CSR and then forces the ML-KEM public key into the certificate with `openssl x509 -req -force_pubkey`. See the script for the exact pattern.

## CRL Support

Each CA maintains a Certificate Revocation List.

```bash
# Generate / refresh all CRLs
./scripts/gencrl.sh

# Or individually
./scripts/gencrl.sh root
./scripts/gencrl.sh intermediate-sig
```

**Revoke a certificate**

```bash
./scripts/revoke.sh intermediate-sig end-entity/alice-sig.crt
./scripts/revoke.sh intermediate-tls end-entity/server.example.org.crt keyCompromise
```

Supported reasons: `unspecified`, `keyCompromise`, `CACompromise`, `affiliationChanged`,
`superseded`, `cessationOfOperation`, `certificateHold`, `removeFromCRL`.

Inspect a CRL:

```bash
openssl crl -in intermediate-sig/crl/intermediate-sig.crl.pem -text -noout
```

End-entity certificates include a `crlDistributionPoints` extension with a placeholder URI (`http://pki.example.org/crl/...`). Update the intermediate `openssl.cnf` files if you serve the CRLs from a real location.

## Verification

```bash
openssl verify -CAfile intermediate-sig/certs/chain.pem end-entity/alice-sig.crt
openssl x509 -in end-entity/bob-enc.crt -text -noout   # inspect ML-KEM key
```

## Security Notes (Please Read)

- This is a **lab / development tool**, not a production CA.
- Private keys are written to disk with mode 400 and are **not** encrypted with a passphrase by default.
- There is no HSM, PKCS#11, multi-person control, or audited operational procedure.
- Default certificate policies are intentionally loose so the scripts are easy to run.
- For any real-world use you must implement proper key protection, access control, logging, CRL/OCSP distribution, certificate policies, and operational security that this project deliberately does not provide.

## License

See [LICENSE](LICENSE).
