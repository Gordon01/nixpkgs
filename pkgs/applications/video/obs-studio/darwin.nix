{
  lib,
  config,
  callPackage,
  stdenv,
  stdenvNoCC,
  fetchurl,
  browserSupport ? true,
  scriptingSupport ? true,
  withFdk ? true,
  cudaSupport ? config.cudaSupport,
  decklinkSupport ? false,
  apple-sdk_26,
  asio,
  cjson,
  cmake,
  curl,
  fdk_aac,
  ffmpeg,
  file,
  fontconfig,
  freetype,
  jansson,
  libdatachannel,
  libjack2,
  librist,
  llvmPackages,
  luajit,
  mbedtls,
  ninja,
  nlohmann_json,
  pkg-config,
  python311,
  qrcodegencpp,
  qt6,
  rnnoise,
  speex,
  srt,
  swift,
  swig,
  testers,
  uthash,
  websocketpp,
  x264,
}:

let
  package = callPackage ./default.nix {
    inherit
      browserSupport
      scriptingSupport
      withFdk
      cudaSupport
      decklinkSupport
      ;
  };

  # The default Swift toolchain propagates a newer SDK than OBS requires.
  swiftForOBS =
    (swift.override {
      swift-corelibs-libdispatch = null;
      swift-foundation = null;
      swift-testing = null;
      enableRepl = false;
      enableSourceKitLSP = false;
    }).overrideAttrs
      (old: {
        depsTargetTargetPropagated = map (
          dep: if lib.getName dep == "apple-sdk" then apple-sdk_26 else dep
        ) old.depsTargetTargetPropagated;
      });

  cef = stdenvNoCC.mkDerivation {
    pname = "obs-studio-cef";
    version = "6533-5";
    src = fetchurl {
      url = "https://cdn-fastly.obsproject.com/downloads/cef_binary_6533_macos_arm64_v5.tar.xz";
      hash = "sha256-QptQ509sF03P4vFNggS1St1Jfqr+EX97ac5rsjVNJiY=";
    };
    sourceRoot = ".";
    dontBuild = true;
    installPhase = ''
      runHook preInstall
      mkdir -p "$out"
      cp -R . "$out/"
      runHook postInstall
    '';
  };
in
assert lib.assertMsg (
  !cudaSupport && !decklinkSupport
) "obs-studio: CUDA and DeckLink are not supported on Darwin";
package.overrideAttrs (
  final: old: {
    separateDebugInfo = false;
    patches = [ ];
    nativeBuildInputs = [
      cmake
      file
      llvmPackages.llvm
      ninja
      pkg-config
      qt6.wrapQtAppsHook
      swiftForOBS
    ]
    ++ lib.optional scriptingSupport swig;
    buildInputs = [
      apple-sdk_26
      asio
      cjson
      curl
      ffmpeg
      fontconfig
      freetype
      jansson
      libdatachannel
      libjack2
      librist
      mbedtls
      nlohmann_json
      qrcodegencpp
      qt6.qtbase
      qt6.qtsvg
      rnnoise
      speex
      srt
      uthash
      websocketpp
      x264
    ]
    ++ lib.optionals scriptingSupport [
      luajit
      python311
    ]
    ++ lib.optional withFdk fdk_aac;

    postUnpack = lib.optionalString browserSupport ''
      ln -s ${cef} cef
    '';
    postPatch = ''
      cp ${./CMakeUserPresets.json} CMakeUserPresets.json
      substituteInPlace CMakeUserPresets.json \
        --replace-fail '"inherits": ["macos"],' '"inherits": ["macos"], "generator": "Ninja",'
      substituteInPlace cmake/macos/defaults.cmake --replace-fail 'include(buildspec)' ""
      substituteInPlace cmake/macos/compilerconfig.cmake \
        --replace-fail 'if(NOT XCODE)' 'if(FALSE)' \
        --replace-fail 'check_sdk_requirements()' ""
      substituteInPlace CMakeLists.txt \
        --replace-fail 'project(obs-studio VERSION ''${OBS_VERSION_CANONICAL})' \
          'project(obs-studio VERSION ''${OBS_VERSION_CANONICAL} LANGUAGES C CXX OBJC OBJCXX Swift)'
      substituteInPlace cmake/macos/helpers.cmake \
        --replace-fail '        COMMAND /bin/ln -fs obs-frontend-api.dylib libobs-frontend-api.1.dylib' '        COMMAND "''${CMAKE_COMMAND}" -E true' \
        --replace-fail '        WORKING_DIRECTORY "$<TARGET_BUNDLE_CONTENT_DIR:''${target}>/Frameworks"' "" \
        --replace-fail '        COMMENT "Create symlink for legacy obs-frontend-api"' '        COMMENT "Skip legacy obs-frontend-api symlink"'
      substituteInPlace libobs-metal/CMakeLists.txt \
        --replace-fail 'target_link_libraries(libobs-metal PRIVATE OBS::libobs)' \
        'target_link_libraries(libobs-metal PRIVATE OBS::libobs)
      target_compile_options(libobs-metal PRIVATE "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-import-objc-header ''${CMAKE_CURRENT_SOURCE_DIR}/libobs-metal-Bridging-Header.h>" "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-Xcc -fmodules>" "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-Xcc -fcxx-modules>")
      set_target_properties(libobs-metal PROPERTIES Swift_LANGUAGE_VERSION 5 Swift_MODULE_NAME libobs_metal)'
      substituteInPlace plugins/mac-avcapture/CMakeLists.txt \
        --replace-fail 'target_link_libraries(mac-avcapture PRIVATE OBS::libobs)' \
        'target_link_libraries(mac-avcapture PRIVATE OBS::libobs)
      target_compile_options(mac-avcapture PRIVATE -fobjc-arc -fmodules)
      target_compile_options(mac-avcapture-legacy PRIVATE -fobjc-arc)'
      substituteInPlace frontend/CMakeLists.txt \
        --replace-fail 'DL_''${graphics_library_U}="$<$<IF:$<PLATFORM_ID:Windows>,TARGET_FILE_NAME,TARGET_SONAME_FILE_NAME>:OBS::libobs-''${graphics_library}>"' \
        'DL_''${graphics_library_U}="$<$<PLATFORM_ID:Darwin>:@executable_path/../Frameworks/$<TARGET_SONAME_FILE_NAME:OBS::libobs-''${graphics_library}>>$<$<PLATFORM_ID:Windows>:$<TARGET_FILE_NAME:OBS::libobs-''${graphics_library}>>$<$<AND:$<NOT:$<PLATFORM_ID:Windows>>,$<NOT:$<PLATFORM_ID:Darwin>>>:$<TARGET_SONAME_FILE_NAME:OBS::libobs-''${graphics_library}>>"'
    ''
    + lib.optionalString scriptingSupport ''
      substituteInPlace shared/obs-scripting/obs-scripting-python-import.h \
        --replace-fail '#if defined(_WIN32) || defined(__APPLE__)' '#if defined(_WIN32)'
      substituteInPlace shared/obs-scripting/obs-scripting.c \
        --replace-fail '#if !defined(_WIN32) && !defined(__APPLE__) /* Win32 and macOS need user-provided Python library paths */' '#if !defined(_WIN32)'
      substituteInPlace shared/obs-scripting/obs-scripting-python.c \
        --replace-fail '	Py_Initialize();' '	Py_SetPythonHome(L"${python311}"); Py_Initialize();'
      substituteInPlace shared/obs-scripting/obspython/CMakeLists.txt \
        --replace-fail '$<$<PLATFORM_ID:Windows,Darwin>:-py3-stable-abi>' '$<$<PLATFORM_ID:Windows>:-py3-stable-abi>'
      substituteInPlace shared/obs-scripting/cmake/python.cmake \
        --replace-fail '$<$<PLATFORM_ID:Windows,Darwin>:-py3-stable-abi>' '$<$<PLATFORM_ID:Windows>:-py3-stable-abi>' \
        --replace-fail '$<$<PLATFORM_ID:Windows,Darwin>:obs-scripting-python-import.c>' '$<$<PLATFORM_ID:Windows>:obs-scripting-python-import.c>' \
        --replace-fail 'target_link_libraries(obs-scripting PRIVATE $<$<PLATFORM_ID:Linux,FreeBSD,OpenBSD>:Python::Python>)' 'target_link_libraries(obs-scripting PRIVATE $<$<PLATFORM_ID:Linux,FreeBSD,OpenBSD,Darwin>:Python::Python>)' \
        --replace-fail 'target_link_options(obs-scripting PRIVATE $<$<PLATFORM_ID:Darwin>:LINKER:-undefined,dynamic_lookup>)' ""
    '';
    cmakeFlags = [
      "--preset"
      "nixpkgs-darwin"
      "-DOBS_VERSION_OVERRIDE=${final.version}"
      "-DCMAKE_COMPILE_WARNING_AS_ERROR=OFF"
      "-DCMAKE_C_COMPILER=${stdenv.cc}/bin/cc"
      "-DCMAKE_CXX_COMPILER=${stdenv.cc}/bin/c++"
      "-DCMAKE_OBJC_COMPILER=${stdenv.cc}/bin/cc"
      "-DCMAKE_OBJCXX_COMPILER=${stdenv.cc}/bin/c++"
      "-DCMAKE_Swift_COMPILER=${swiftForOBS}/bin/swiftc"
      "-DCMAKE_OSX_DEPLOYMENT_TARGET=${stdenv.hostPlatform.darwinMinVersion}"
      "-DCMAKE_Swift_COMPILER_TARGET=${stdenv.hostPlatform.darwinArch}-apple-macosx${stdenv.hostPlatform.darwinMinVersion}"
      "-DCMAKE_EXE_LINKER_FLAGS=-Wl,-headerpad_max_install_names"
      "-DCMAKE_MODULE_LINKER_FLAGS=-Wl,-headerpad_max_install_names"
      "-DSPARKLE_APPCAST_URL="
      "-DSPARKLE_PUBLIC_KEY="
      "-DENABLE_AJA=OFF"
      "-DENABLE_DECKLINK=OFF"
      "-DENABLE_SYPHON=OFF"
      "-DENABLE_VIRTUALCAM=OFF"
      "-DENABLE_VLC=OFF"
      (lib.cmakeBool "ENABLE_LIBFDK" withFdk)
      (lib.cmakeBool "ENABLE_BROWSER" browserSupport)
      (lib.cmakeBool "ENABLE_SCRIPTING" scriptingSupport)
    ]
    ++ lib.optional browserSupport "-DCEF_ROOT_DIR=../../cef"
    ++ lib.optionals scriptingSupport [
      "-DPython_ROOT_DIR=${python311}"
      "-DPython_EXECUTABLE=${python311.interpreter}"
    ];

    env.NIX_CFLAGS_COMPILE = "-Wno-error=deprecated-declarations -DCURL_DISABLE_TYPECHECK";
    dontWrapQtApps = true;
    preFixup = "";
    postInstall = ''
      app="$out/Applications/OBS.app"
      mkdir -p "$out/Applications" "$out/bin"
      mv "$out/OBS.app" "$app"
      frameworks="$app/Contents/Frameworks"
      plugins="$app/Contents/PlugIns"
      mkdir -p "$frameworks" "$plugins"
      cp -R libobs/libobs.framework frontend/api/obs-frontend-api.dylib \
        libobs-opengl/libobs-opengl.dylib libobs-metal/libobs-metal.dylib "$frameworks/"
      ${lib.optionalString scriptingSupport ''
        cp shared/obs-scripting/obs-scripting.dylib "$frameworks/"
        cp shared/obs-scripting/obslua/obslua.so "$plugins/"
        cp shared/obs-scripting/obspython/_obspython.so "$app/Contents/Resources/"
      ''}
      ${lib.optionalString browserSupport ''
        cp -R "${cef}/Release/Chromium Embedded Framework.framework" "$frameworks/"
        for helper in "OBS Helper.app" "OBS Helper (GPU).app" "OBS Helper (Plugin).app" "OBS Helper (Renderer).app"; do
          cp -R "plugins/obs-browser/$helper" "$frameworks/"
        done
      ''}
      while IFS= read -r -d "" plugin; do
        cp -R "$plugin" "$plugins/"
      done < <(find plugins frontend -name '*.plugin' -type d -print0)
      test -d "$plugins/mac-capture.plugin"
      ${lib.optionalString browserSupport ''test -d "$plugins/obs-browser.plugin"''}

      while IFS= read -r -d "" binary; do
        if file "$binary" | grep -q 'Mach-O'; then
          while IFS= read -r dependency; do
            case "$dependency" in
              libobs/libobs.framework/Versions/A/libobs)
                install_name_tool -change "$dependency" "$frameworks/libobs.framework/Versions/A/libobs" "$binary" ;;
              frontend/api/obs-frontend-api.dylib)
                install_name_tool -change "$dependency" "$frameworks/obs-frontend-api.dylib" "$binary" ;;
              shared/obs-scripting/obs-scripting.dylib)
                install_name_tool -change "$dependency" "$frameworks/obs-scripting.dylib" "$binary" ;;
            esac
          done < <(llvm-otool -L "$binary" | tail -n +2 | awk '{print $1}')
        fi
      done < <(find "$app/Contents" -type f -print0)
      ln -s "$app/Contents/MacOS/OBS" "$out/bin/obs"
      cp ../cmake/macos/resources/AppIcon.icns "$app/Contents/Resources/"
      substitute ${./Info.plist} "$app/Contents/Info.plist" --replace-fail @version@ ${final.version}
    '';
    postFixup = ''
      wrapQtApp "$out/Applications/OBS.app/Contents/MacOS/OBS"
    '';
    passthru = old.passthru // {
      tests.version = testers.testVersion { package = final.finalPackage; };
    };
    meta = old.meta // {
      platforms = [ "aarch64-darwin" ];
    };
  }
)
