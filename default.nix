# provide toolchains needed to compile rust-std for x86_64-fortanix-unknown-sgx
# {
#   nixpkgs ? ../nixpkgs,
#   pkgs ? import nixpkgs {
#     localSystem = "x86_64-unknown-linux-gnu";
#   },
# }:
rec {
  dotfiles = import ../dotfiles { };

  pkgs = dotfiles.pkgs;
  inherit (pkgs) lib stdenv callPackage;

  # package containing `llvm-config` so we can avoid rebuilding all of LLVM
  llvmSharedFor =
    pkgSet:
    pkgSet.llvmPackages.libllvm.override (
      {
        enableSharedLibraries = true;
      }
      // lib.optionalAttrs (stdenv.targetPlatform.useLLVM or false) {
        # Force LLVM to compile using clang + LLVM libs when targeting pkgsLLVM
        stdenv = pkgSet.stdenv.override {
          allowedRequisites = null;
          cc = pkgSet.pkgsBuildHost.llvmPackages.clangUseLLVM;
        };
      }
    );
  pkgsBuildHost = pkgs.pkgsBuildHost;
  llvmSharedForHost = llvmSharedFor pkgsBuildHost;

  # Use plain, unwrapped (not nixpkgs wrapped) compilers and binutils.
  llvmPackages = pkgs.llvmPackages;
  bintools-unwrapped = llvmPackages.bintools-unwrapped;
  clang-unwrapped = llvmPackages.clang-unwrapped;
  libcxx = llvmPackages.libcxx.dev;

  # snmalloc needs c++ std headers to compile. We have to configure them a bit
  # to manually enable/disable some features that aren't available in SGX or
  # aren't detected automatically.
  libcxx-dev = pkgs.stdenvNoCC.mkDerivation {
    pname = "${libcxx.pname}-cfg-sgx";
    version = libcxx.version;
    src = libcxx.dev;

    phases = [ "installPhase" ];
    installPhase = ''
      mkdir -p $out/include
      shopt -s extglob
      cp -R $src/include/c++/v1/!(__config_site) $out/include
      shopt -u extglob
    ''
    + lib.optionalString (lib.versionAtLeast libcxx.version "20") ''
      substitute $src/include/c++/v1/__config_site $out/include/__config_site \
        --replace-fail '#define _LIBCPP_HAS_FILESYSTEM 1' '#define _LIBCPP_HAS_FILESYSTEM 0' \
        --replace-fail '#define _LIBCPP_HAS_LOCALIZATION 1' '#define _LIBCPP_HAS_LOCALIZATION 0' \
        --replace-fail '#define _LIBCPP_HAS_TERMINAL 1' '#define _LIBCPP_HAS_TERMINAL 0' \
        --replace-fail '#define _LIBCPP_HAS_THREAD_API_PTHREAD 0' '#define _LIBCPP_HAS_THREAD_API_PTHREAD 1'
    ''
    + lib.optionalString (lib.versionOlder libcxx.version "20") ''
      substitute $src/include/c++/v1/__config_site $out/include/__config_site \
        --replace-fail '/* #undef _LIBCPP_HAS_NO_FILESYSTEM */' '#define _LIBCPP_HAS_NO_FILESYSTEM 1' \
        --replace-fail '/* #undef _LIBCPP_HAS_NO_LOCALIZATION */' '#define _LIBCPP_HAS_NO_LOCALIZATION 1' \
        --replace-fail '/* #undef _LIBCPP_HAS_THREAD_API_PTHREAD */' '#define _LIBCPP_HAS_THREAD_API_PTHREAD 1'
    '';
  };

  # collect tools needed for each platform
  tools = {
    x86_64-unknown-linux-gnu = rec {
      ar = "${stdenv.cc}/bin/ar";
      cc = "${stdenv.cc}/bin/cc";
      cxx = "${stdenv.cc}/bin/c++";
      linker = cc;
      llvm-config = "${llvmSharedForHost.dev}/bin/llvm-config";
      ranlib = "${stdenv.cc}/bin/ranlib";
    };

    x86_64-fortanix-unknown-sgx = rec {
      ar = "${bintools-unwrapped}/bin/ar";
      cc = "${clang-unwrapped}/bin/clang";
      cxx = "${clang-unwrapped}/bin/clang++";
      cflags = builtins.concatStringsSep " " [
        "-D__ELF__"
        "-DCMAKE_SYSTEM_NAME=Generic-ELF"

        "-march=x86-64-v3"

        # silence snmalloc warning
        "-Wno-missing-template-arg-list-after-template-kw"

        # "-mlvi-hardening"
        # "-mllvm=-x86-experimental-lvi-inline-asm-hardening"
        # TODO: <src/llvm-project/llvm/include/llvm/TargetParser/X86TargetParser.def>
        "-mno-lvi-cfi"
        "-mno-lvi-hardening"
        "-mretpoline"

        "-resource-dir ${clang-unwrapped.lib}/lib/clang/${lib.versions.major clang-unwrapped.version}"
        "-idirafter${pkgs.glibc.dev}/include"
      ];
      cxxflags = builtins.concatStringsSep " " [
        "-cxx-isystem${libcxx-dev}/include"

        # CFLAGS _must_ go after C++ includes
        cflags
      ];
      linker = cc;
      llvm-config = "${llvmSharedForHost.dev}/bin/llvm-config";
      ranlib = "${bintools-unwrapped}/bin/ranlib";
    };
  };

  # args to pass to rust's ./configure script
  configure-args = pkgs.writeText "configure-args" ''
    --set=target."x86_64-unknown-linux-gnu".ar=${tools.x86_64-unknown-linux-gnu.ar}
    --set=target."x86_64-unknown-linux-gnu".cc=${tools.x86_64-unknown-linux-gnu.cc}
    --set=target."x86_64-unknown-linux-gnu".cxx=${tools.x86_64-unknown-linux-gnu.cxx}
    --set=target."x86_64-unknown-linux-gnu".linker=${tools.x86_64-unknown-linux-gnu.linker}
    --set=target."x86_64-unknown-linux-gnu".llvm-config=${tools.x86_64-unknown-linux-gnu.llvm-config}
    --set=target."x86_64-unknown-linux-gnu".ranlib=${tools.x86_64-unknown-linux-gnu.ranlib}
    --set=target."x86_64-fortanix-unknown-sgx".ar=${tools.x86_64-fortanix-unknown-sgx.ar}
    --set=target."x86_64-fortanix-unknown-sgx".cc=${tools.x86_64-fortanix-unknown-sgx.cc}
    --set=target."x86_64-fortanix-unknown-sgx".cxx=${tools.x86_64-fortanix-unknown-sgx.cxx}
    --set=target."x86_64-fortanix-unknown-sgx".linker=${tools.x86_64-fortanix-unknown-sgx.linker}
    --set=target."x86_64-fortanix-unknown-sgx".llvm-config=${tools.x86_64-fortanix-unknown-sgx.llvm-config}
    --set=target."x86_64-fortanix-unknown-sgx".ranlib=${tools.x86_64-fortanix-unknown-sgx.ranlib}
  '';

  # .cargo/config.toml
  cargo-config-toml = pkgs.writeText "cargo-config.toml" ''
    # Use vendored crates
    [source.crates-io]
    replace-with = "vendored-sources"
    [source.vendored-sources]
    directory = "vendor"
  '';

  # we'll set these envs before build/install steps
  build-envs = pkgs.writeShellScript "build-envs" ''
    export CMAKE="${lib.getExe' pkgs.cmake "cmake"}"
    export CMAKE_GENERATOR="Ninja"
    export PATH="${lib.makeBinPath [ pkgs.ninja ]}:$PATH"
    export CFLAGS_x86_64_fortanix_unknown_sgx="${tools.x86_64-fortanix-unknown-sgx.cflags}"
    export CXXFLAGS_x86_64_fortanix_unknown_sgx="${tools.x86_64-fortanix-unknown-sgx.cxxflags}"

    # We run on min. Ice Lake (60_6AH) which mitigates LVI in hardware. Disable
    # lvi-cfi and lvi-load-hardening since these have a HUGE performance cost
    # (5-20x). Still need retpolines to mitigate Spectre_v2, just at a much
    # lower cost (2-50%).
    export CARGO_TARGET_X86_64_FORTANIX_UNKNOWN_SGX_RUSTFLAGS="-Zretpoline=yes -Ctarget-feature=-lvi-cfi,-lvi-load-hardening,+adx,+aes,+pclmulqdq,+sha,+vaes -Ctarget-cpu=x86-64-v3"
  '';

  # collect all our nix-provided tools in ./build/tools-dir/
  tools-dir = pkgs.linkFarm "tools-dir" {
    inherit build-envs cargo-config-toml configure-args;
  };
}
