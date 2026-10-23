FROM debian:bookworm-slim

RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      build-essential clang flex bison g++ gawk gcc-multilib g++-multilib gettext git \
      libncurses-dev libssl-dev python3 python3-setuptools python3-dev rsync swig unzip \
      zlib1g-dev file wget curl ca-certificates xz-utils zstd bzip2 patch perl \
      device-tree-compiler time \
    && rm -rf /var/lib/apt/lists/*
