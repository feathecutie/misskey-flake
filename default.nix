{ stdenv
, lib
, fetchFromGitHub
, nodejs
, pnpm
, makeWrapper
, python3
, bash
, jemalloc
, ffmpeg-headless
, ...
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "misskey";

  version = "2024.5.0";

  src = fetchFromGitHub {
    owner = "misskey-dev";
    repo = finalAttrs.pname;
    rev = finalAttrs.version;
    hash = "sha256-nKf+SfuF6MQtNO53E6vN9CMDvQzKMv3PrD6gs9Qa86w=";
    fetchSubmodules = true;
  };

  nativeBuildInputs = [
    nodejs
    pnpm.configHook
    makeWrapper
    python3
  ];

  patches = [
    ./pnpm_version.patch
  ];

  # https://nixos.org/manual/nixpkgs/unstable/#javascript-pnpm
  pnpmDeps = pnpm.fetchDeps {
    inherit (finalAttrs) pname version src patches;
    hash = "sha256-A1JBLa6lIw5tXFuD2L3vvkH6pHS5rlwt8vU2+UUQYdg=";
  };

  buildPhase = ''
    runHook preBuild

    # https://github.com/NixOS/nixpkgs/pull/296697/files#r1617546739
    (
      cd node_modules/.pnpm/node_modules/v-code-diff
      pnpm run postinstall
    )

    # https://github.com/NixOS/nixpkgs/pull/296697/files#r1617595593
    # TODO: Check if this is needed
    export npm_config_nodedir=${nodejs}
    (
      cd node_modules/.pnpm/node_modules/re2
      pnpm run rebuild
    )
    (
      cd node_modules/.pnpm/node_modules/sharp
      pnpm run install
    )

    # Equivalent to pnpm build, but with each package being built seperately
    pnpm build-pre
    pnpm --filter misskey-bubble-game build
    pnpm --filter misskey-js build
    pnpm --filter misskey-reversi build
    pnpm --filter sw build
    pnpm --filter backend build
    pnpm --filter frontend build
    pnpm build-assets

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/data
    cp -r . $out/data
    cp .config/example.yml $out/data/.config/default.yml


    makeWrapper ${pnpm}/bin/pnpm $out/bin/misskey \
      --chdir $out/data \
      --set-default NODE_ENV production \
      --prefix PATH : ${lib.makeBinPath [
        nodejs
        pnpm
        bash
      ]} \
      --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath [
        # TODO: Check if this is needed
        jemalloc
        ffmpeg-headless
        # TODO: Check if this is needed
        stdenv.cc.cc.lib
      ]}

    runHook postInstall
  '';

  passthru = {
    inherit (finalAttrs) pnpmDeps;
  };

  meta = {
    description = "🌎 An interplanetary microblogging platform 🚀";
    homepage = "https://misskey-hub.net/";
    license = lib.licenses.agpl3Only;
    maintainers = [ lib.maintainers.feathecutie ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "misskey";
  };
})
