# ZK Proof Generator
# Usage: docker run --rm -v $(pwd):/work zkproof generate /work/bundle.json /work/output

FROM ubuntu:24.04

# Install dependencies
RUN apt-get update && apt-get install -y \
    curl ca-certificates nodejs npm xxd \
    && rm -rf /var/lib/apt/lists/*

# Install nargo
ARG NARGO_VERSION=1.0.0-beta.17
RUN curl -L https://raw.githubusercontent.com/noir-lang/noirup/main/install | bash \
    && /root/.nargo/bin/noirup -v ${NARGO_VERSION}
ENV PATH="/root/.nargo/bin:${PATH}"

# Install bb (barretenberg)
ARG BB_VERSION=v3.0.3
RUN curl -L -o /tmp/bb.tar.gz \
    "https://github.com/AztecProtocol/aztec-packages/releases/download/${BB_VERSION}/barretenberg-amd64-linux.tar.gz" \
    && tar -xzf /tmp/bb.tar.gz -C /usr/local/bin \
    && rm /tmp/bb.tar.gz \
    && chmod +x /usr/local/bin/bb

# Copy circuit and witness generator
WORKDIR /prover
COPY circuits/ ./circuits/
COPY js/ ./js/

# Install JS dependencies and build
RUN cd js && npm install && npx tsc
RUN cd circuits && nargo compile

# Pre-generate verification key (saves time on each proof)
RUN cd circuits && bb write_vk -b target/zk_github_attestation.json -o target/vk -t evm

# Entrypoint script
COPY <<'EOF' /usr/local/bin/zkproof
#!/bin/bash
set -e

case "$1" in
  generate)
    BUNDLE="$2"
    OUTPUT="${3:-/work/proof}"

    if [ -z "$BUNDLE" ]; then
      echo "Usage: zkproof generate <bundle.json> [output_dir]"
      exit 1
    fi

    echo "==> Generating witness from attestation bundle..."
    cd /prover/js
    node dist/index.js witness "$BUNDLE"

    echo "==> Executing circuit..."
    cd /prover/circuits
    nargo execute

    echo "==> Generating proof..."
    bb prove \
      -b target/zk_github_attestation.json \
      -w target/zk_github_attestation.gz \
      -k target/vk/vk \
      -o target/proof \
      -t evm

    echo "==> Verifying proof locally..."
    bb verify \
      -k target/vk/vk \
      -p target/proof/proof \
      -i target/proof/public_inputs \
      -t evm

    echo "==> Formatting output..."
    mkdir -p "$OUTPUT"
    cp target/proof/proof "$OUTPUT/proof.bin"
    cp target/proof/public_inputs "$OUTPUT/inputs.bin"

    # Create hex versions for easy contract calls
    xxd -p -c 99999 target/proof/proof > "$OUTPUT/proof.hex"

    # Format public inputs as bytes32 array + claim JSON
    RECIPIENT="${RECIPIENT:-}"
    node -e "
      const fs = require('fs');
      const raw = fs.readFileSync('target/proof/public_inputs');
      const proof = '0x' + fs.readFileSync('$OUTPUT/proof.hex', 'utf8').trim();
      const inputs = [];
      for (let i = 0; i < raw.length; i += 32) {
        inputs.push('0x' + raw.slice(i, i + 32).toString('hex'));
      }
      fs.writeFileSync('$OUTPUT/inputs.json', JSON.stringify(inputs, null, 2));

      // Generate claim JSON ready for GitHub issue
      const claim = {
        proof,
        inputs,
        recipient: process.env.RECIPIENT || '0x_YOUR_ADDRESS_HERE'
      };
      fs.writeFileSync('$OUTPUT/claim.json', JSON.stringify(claim, null, 2));
      console.log('Public inputs:', inputs.length, 'elements');
    "

    echo ""
    echo "==> Proof generated successfully!"
    echo "    $OUTPUT/proof.bin    - Raw proof ($(stat -c%s "$OUTPUT/proof.bin") bytes)"
    echo "    $OUTPUT/inputs.bin   - Raw public inputs"
    echo "    $OUTPUT/proof.hex    - Hex-encoded proof"
    echo "    $OUTPUT/inputs.json  - Public inputs array"
    echo "    $OUTPUT/claim.json   - Ready for GitHub issue submission"
    echo ""
    echo "To claim, open an issue at the repo with title '[CLAIM] Faucet request'"
    echo "and paste the contents of claim.json in a \`\`\`json code block."
    ;;

  verify)
    PROOF="${2:-/work/proof}"
    echo "==> Verifying proof..."
    cd /prover/circuits
    bb verify \
      -k target/vk/vk \
      -p "$PROOF/proof.bin" \
      -i "$PROOF/inputs.bin" \
      -t evm
    echo "==> Proof valid!"
    ;;

  *)
    echo "ZK Sigstore Proof Generator"
    echo ""
    echo "Usage:"
    echo "  zkproof generate <bundle.json> [output_dir]  Generate proof from attestation"
    echo "  zkproof verify [proof_dir]                   Verify a proof locally"
    echo ""
    echo "Example:"
    echo "  docker run --rm -v \$(pwd):/work zkproof generate /work/bundle.json /work/proof"
    ;;
esac
EOF

RUN chmod +x /usr/local/bin/zkproof

ENTRYPOINT ["zkproof"]
CMD ["--help"]
