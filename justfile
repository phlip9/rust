alias b := build
alias c := configure
alias i := install

default:
    just configure
    just build
    just install

configure:
    #!/usr/bin/env bash
    set -euxo pipefail

    mkdir -p .cargo
    cat > .cargo/config.toml <<\EOF
    [source.crates-io]
    replace-with = "vendored-sources"
    [source.vendored-sources]
    directory = "vendor"
    EOF

    # see: ./configure --help
    rm -rf ./bootstrap.toml ./inst
    mkdir inst

    # configure bootstrap to build for x86_64-fortanix-unknown-sgx
    # - give it an existing LLVM so we don't have to waste a few hours rebuilding
    ./configure \
        --set=change-id=ignore \
        --prefix="$(readlink -f inst)" \
        --sysconfdir=etc \
        --tools= \
        --enable-local-rust \
        --enable-local-rebuild \
        --enable-manage-submodules \
        --enable-option-checking \
        --build=x86_64-unknown-linux-gnu \
        --host=x86_64-unknown-linux-gnu \
        --target=x86_64-fortanix-unknown-sgx \
        --disable-llvm-bitcode-linker \
        --enable-llvm-link-shared \
        --set=target."x86_64-unknown-linux-gnu".llvm-config=/nix/store/fcw7fmd5w49nr7f55vl6axnpxrlx971q-llvm-19.1.7-dev/bin/llvm-config \
        --set=target."x86_64-unknown-linux-gnu".llvm-config=/nix/store/fcw7fmd5w49nr7f55vl6axnpxrlx971q-llvm-19.1.7-dev/bin/llvm-config \
        --set=target."x86_64-fortanix-unknown-sgx".llvm-config=/nix/store/fcw7fmd5w49nr7f55vl6axnpxrlx971q-llvm-19.1.7-dev/bin/llvm-config

build:
    #!/usr/bin/env bash
    set -euxo pipefail

    rustc="$(rustup which rustc)"
    toolchain="$(dirname "$(dirname "$rustc")")"

    # coerce bootstrap into using our existing compiler
    mkdir -p build/x86_64-unknown-linux-gnu/stage{0,1}-{std,rustc}/x86_64-unknown-linux-gnu/release/
    ln -sf "$toolchain"/lib/rustlib/x86_64-unknown-linux-gnu/libstd-*.so build/x86_64-unknown-linux-gnu/stage0-std/x86_64-unknown-linux-gnu/release/libstd.so
    ln -sf "$toolchain"/lib/rustlib/x86_64-unknown-linux-gnu/librustc_driver-*.so build/x86_64-unknown-linux-gnu/stage0-rustc/x86_64-unknown-linux-gnu/release/librustc.so
    ln -sf "$rustc" build/x86_64-unknown-linux-gnu/stage0-rustc/x86_64-unknown-linux-gnu/release/rustc-main
    ln -sf "$rustc" build/x86_64-unknown-linux-gnu/stage1-rustc/x86_64-unknown-linux-gnu/release/rustc-main
    touch build/x86_64-unknown-linux-gnu/stage0-std/x86_64-unknown-linux-gnu/release/.libstd-stamp
    touch build/x86_64-unknown-linux-gnu/stage{0,1}-rustc/x86_64-unknown-linux-gnu/release/.librustc-stamp

    # build rust-std for x86_64-fortanix-unknown-sgx
    python ./x.py --keep-stage=0 --stage=1 build library

install:
    # install into ./inst/
    python ./x.py --keep-stage=0 --stage=1 install library/std

vendor:
    rm -rf vendor

    # RUSTC=...
    RUSTC_BOOTSTRAP=1 \
    cargo vendor --locked --versioned-dirs \
        --sync library/Cargo.toml \
        --sync src/bootstrap/Cargo.toml \
        ./vendor
