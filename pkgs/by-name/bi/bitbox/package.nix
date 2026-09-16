{
  lib,
  stdenv,
  fetchFromGitHub,
  runCommand,
  buildNpmPackage,
  clang,
  dejavu_fonts,
  go_1_26,
  nodejs_24,
  patchelf,
  qt5,
  qt6,
  udevCheckHook,
}:

let
  # Qt 6 doesn’t provide the rcc binary so we create an ad hoc package pulling
  # it from Qt 5.
  rcc = runCommand "rcc" { } ''
    mkdir -p $out/bin
    cp ${lib.getExe' qt5.qtbase.dev "rcc"} $out/bin
  '';

  # prevent runtime errors on fonts
  bitboxFontsConf = runCommand "bitbox-fontconfig" { } ''
    mkdir -p $out

    cat > $out/fonts.conf <<EOF
    <?xml version="1.0"?>
    <!DOCTYPE fontconfig SYSTEM "fonts.dtd">
    <fontconfig>
      <dir>${dejavu_fonts}/share/fonts/truetype</dir>
    </fontconfig>
    EOF
  '';
in
stdenv.mkDerivation rec {
  pname = "bitbox";
  version = "4.52.0";

  src = fetchFromGitHub {
    owner = "BitBoxSwiss";
    repo = "bitbox-wallet-app";
    tag = "v${version}";
    fetchSubmodules = true;
    hash = "sha256-urQjnrBcqTwP+xpcM0L8IpE/Vc+CQiN/2hE5jlBnzdU=";
  };

  postPatch = ''
    substituteInPlace frontends/qt/resources/linux/usr/share/applications/bitbox.desktop \
      --replace-fail 'Exec=BitBox %u' 'Exec=bitbox %u'
  '';

  dontConfigure = true;

  passthru.web = buildNpmPackage {
    pname = "bitbox-web";
    inherit version src;
    sourceRoot = "${src.name}/frontends/web";
    # BitBoxApp v4.52.0 requires Node >=24 <25.
    nodejs = nodejs_24;
    npmDepsHash = "sha256-G8ZhBG9zdiFvkMVgjLFJcbFFpbqh6+q1xezv9fwwaAg=";
    installPhase = "cp -r build $out";
  };

  buildPhase = ''
    runHook preBuild

    ln -s ${passthru.web} frontends/web/build
    export GOCACHE=$TMPDIR/go-cache
    cd frontends/qt
    make -C server linux
    ./genassets.sh
    qmake -o build/Makefile
    cd build
    make
    cd ../../..

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out
    cp -r frontends/qt/resources/linux/usr/share $out
    mkdir -p $out/bin
    mkdir -p $out/lib
    cp frontends/qt/build/BitBox $out/bin/bitbox
    cp frontends/qt/build/assets.rcc $out/bin
    cp frontends/qt/server/libserver.so $out/lib
    cp \
      vendor/github.com/breez/breez-sdk-spark-go/breez_sdk_spark/lib/linux-amd64/libbreez_sdk_spark_bindings.so \
      $out/lib/

    install -m 644 \
      -Dt $out/lib/udev/rules.d \
      ${./rules.d}/*
    patchelf --set-rpath '$ORIGIN' \
      $out/lib/libserver.so

    runHook postInstall
  '';

  buildInputs = [
    qt6.qtwebengine
  ];

  nativeBuildInputs = [
    clang
    go_1_26
    patchelf
    qt6.wrapQtAppsHook
    rcc
    udevCheckHook
  ];

  qtWrapperArgs = [
    "--set"
    "FONTCONFIG_FILE"
    "${bitboxFontsConf}/fonts.conf"
  ];

  doInstallCheck = true;

  meta = {
    description = "Companion app for the BitBox02 hardware wallet";
    homepage = "https://bitbox.swiss/app/";
    downloadPage = "https://github.com/BitBoxSwiss/bitbox-wallet-app";
    changelog = "https://github.com/BitBoxSwiss/bitbox-wallet-app/blob/master/CHANGELOG.md#${
      builtins.replaceStrings [ "." ] [ "" ] version
    }";
    license = lib.licenses.asl20;
    maintainers = [ lib.maintainers.tensor5 ];
    mainProgram = "bitbox";
    sourceProvenance = [ lib.sourceTypes.fromSource ];
    platforms = [ "x86_64-linux" ];
  };
}
