ARG RUST_VERSION=1.75.0

FROM rust:$RUST_VERSION-slim
ENV RUSTFLAGS='-C link-arg=-fuse-ld=lld'
RUN \
  # Misc system utilities
  apt-get update && \
  apt-get install --no-install-recommends -y jq valgrind wget pkg-config libssl-dev git && \
  rm -rf /var/lib/apt/lists/* && \
  # Add clippy and llvm utilities
  rustup component add clippy llvm-tools-preview && \
  ln -s $(rustc --print target-libdir)/../bin/llvm-profdata /usr/local/bin/llvm-profdata && \
  ln -s $(rustc --print target-libdir)/../bin/llvm-cov /usr/local/bin/llvm-cov && \
  # Download custom cargo subcommands
  mkdir -p /usr/local/cargo/bin && \
  target=$(rustc -vV | grep -oP '(?<=host: ).*') && \
  wget https://github.com/cargo-bins/cargo-binstall/releases/download/v1.4.6/cargo-binstall-$target.tgz -O - | \
  tar -xzvf - -C /usr/local/cargo/bin && \
  cargo binstall -y cargo-nextest@0.9.70 cargo-llvm-cov@0.6.9 cargo-deny@0.14.3 cargo-about@0.6.1 cargo-vet@0.9.1 && \
  # cargo binstall -y mdbook@0.4.35 && \
  # Install mold linker for dramatically faster build times
  wget https://github.com/rui314/mold/releases/download/v2.31.0/mold-2.31.0-x86_64-linux.tar.gz -O - | \
  tar -xzvf - -C /usr/local/ --strip-components 1 && \
  ln -s /usr/local/bin/mold /usr/bin/ld.lld
