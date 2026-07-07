# rust-lang/rust

This is a fork of the Rust compiler and standard library with some changes to
the x86_64-fortanix-unknown-sgx target.

The main goal of this fork is to build a minimal nix derivation for building
and packaging the rust standard library (library/) for
x86_64-fortanix-unknown-sgx.

## `just` commands:

- default: runs clean-std, tools, configure, build, then install in sequence.
- clean: removes the entire build directory.
- clean-std: removes SGX stdlib artifacts from stage1 and stage1-std.
- tools: builds tooling via nix into build/tools-dir and installs a cargo config into .cargo/
  config.toml.
- configure: wipes bootstrap.toml/inst, recreates inst, then runs ./configure for SGX target with custom
  options and args.
- build: fakes submodules, sources tool envs, symlinks existing rustc/libstd into stage dirs, then
  builds library for SGX via x.py.
- install: sources tool envs and installs library/std into ./inst via x.py.
- vendor: clears vendor and runs cargo vendor for library and bootstrap Cargo.toml into ./vendor.

## `default.nix`

Provides reproducible tooling and toolchains for cross-compiling.
