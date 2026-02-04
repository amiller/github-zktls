FROM ubuntu:24.04
RUN apt-get update && apt-get install -y curl ca-certificates && rm -rf /var/lib/apt/lists/*
ARG BB_VERSION=v3.0.3
RUN curl -L -o /tmp/bb.tar.gz "https://github.com/AztecProtocol/aztec-packages/releases/download/${BB_VERSION}/barretenberg-amd64-linux.tar.gz" \
    && tar -xzf /tmp/bb.tar.gz -C /usr/local/bin && rm /tmp/bb.tar.gz && chmod +x /usr/local/bin/bb
WORKDIR /circuit
ENTRYPOINT ["bb"]
