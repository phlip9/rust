alias b := build
alias c := configure
alias i := install
alias t := tools

default:
    just clean-std
    just tools
    just configure
    just build
    just install

clean:
    rm -rf build

clean-std:
    rm -rf \
        build/host/stage1/lib/rustlib/x86_64-fortanix-unknown-sgx \
        build/host/stage1-std/x86_64-fortanix-unknown-sgx

tools:
    mkdir -p build .cargo
    nix build -f . tools-dir --out-link build/tools-dir

    rm -f .cargo/config.toml
    cp --dereference --no-preserve=all build/tools-dir/cargo-config-toml .cargo/config.toml

configure:
    #!/usr/bin/env bash
    set -euxo pipefail

    # see: ./configure --help
    rm -rf ./bootstrap.toml ./inst
    mkdir inst

    # configure bootstrap to build for x86_64-fortanix-unknown-sgx
    # - give it an existing LLVM so we don't have to waste a few hours rebuilding
    ./configure \
        --build=x86_64-unknown-linux-gnu \
        --host=x86_64-unknown-linux-gnu \
        --target=x86_64-fortanix-unknown-sgx \
        --disable-llvm-bitcode-linker \
        --enable-llvm-link-shared \
        --enable-local-rebuild \
        --enable-local-rust \
        --enable-manage-submodules \
        --enable-option-checking \
        --prefix="$(readlink -f inst)" \
        --set=change-id=ignore \
        --sysconfdir=etc \
        --tools= \
        $(< ./build/tools-dir/configure-args)

build:
    #!/usr/bin/env bash
    set -euo pipefail

    rustc="$(rustup which rustc)"
    toolchain="$(dirname "$(dirname "$rustc")")"

    # fake some submodules
    mkdir -p \
      src/gcc \
      src/tools/cargo \
      src/tools/rustc-perf \
      src/tools/enzyme/enzyme

    source ./build/tools-dir/build-envs

    # coerce bootstrap into using our existing compiler
    mkdir -p build/x86_64-unknown-linux-gnu/stage{0,1}-{std,rustc}/x86_64-unknown-linux-gnu/release/
    ln -sf "$toolchain"/lib/rustlib/x86_64-unknown-linux-gnu/libstd-*.so build/x86_64-unknown-linux-gnu/stage0-std/x86_64-unknown-linux-gnu/release/libstd.so
    ln -sf "$toolchain"/lib/rustlib/x86_64-unknown-linux-gnu/librustc_driver-*.so build/x86_64-unknown-linux-gnu/stage0-rustc/x86_64-unknown-linux-gnu/release/librustc.so
    ln -sf "$rustc" build/x86_64-unknown-linux-gnu/stage0-rustc/x86_64-unknown-linux-gnu/release/rustc-main
    ln -sf "$rustc" build/x86_64-unknown-linux-gnu/stage1-rustc/x86_64-unknown-linux-gnu/release/rustc-main
    touch build/x86_64-unknown-linux-gnu/stage0-std/x86_64-unknown-linux-gnu/release/.libstd-stamp
    touch build/x86_64-unknown-linux-gnu/stage{0,1}-rustc/x86_64-unknown-linux-gnu/release/.librustc-stamp

    # build rust-std for x86_64-fortanix-unknown-sgx
    python ./x.py --keep-stage=0 --stage=1 build library # --verbose

install:
    #!/usr/bin/env bash
    set -euo pipefail

    source ./build/tools-dir/build-envs

    # install into ./inst/
    python ./x.py --keep-stage=0 --stage=1 install library/std # --verbose

# build cargo vendor directory
vendor:
    rm -rf vendor

    # RUSTC=...
    RUSTC_BOOTSTRAP=1 \
    cargo vendor --locked --versioned-dirs \
        --sync library/Cargo.toml \
        --sync src/bootstrap/Cargo.toml \
        ./vendor
