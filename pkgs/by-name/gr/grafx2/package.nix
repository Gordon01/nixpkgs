{
  lib,
  stdenv,
  fetchurl,
  SDL2,
  SDL2_image,
  SDL2_ttf,
  installShellFiles,
  fontconfig,
  libpng,
  libtiff,
  libx11,
  lua5_2_compat,
  pkg-config,
  desktopToDarwinBundle,
  which,
  zlib,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "grafx2";
  version = "2.8.3091";

  outputs = [
    "out"
    "man"
  ];

  src = fetchurl {
    name = "grafx2-${finalAttrs.version}.tar.gz";
    url = "https://pulkomandy.tk/projects/GrafX2/downloads/65";
    hash = "sha256-KdY7GUhQp/Q7t/ktLPGxI66ZHy2gDAffn2yB5pmcJCM=";
  };

  patches = lib.optionals stdenv.hostPlatform.isDarwin [
    ./darwin-data-dir.patch
  ];

  postPatch = ''
    substituteInPlace misc/unix/grafx2.desktop \
      --replace-fail "Exec=grafx2" "Exec=grafx2-sdl2"
  '';

  nativeBuildInputs = [
    installShellFiles
    pkg-config
    which
    SDL2 # for sdl-config
  ]
  ++ lib.optionals stdenv.hostPlatform.isDarwin [
    desktopToDarwinBundle
  ];

  buildInputs = [
    SDL2
    SDL2_image
    SDL2_ttf
    fontconfig
    libpng
    libtiff
    libx11
    lua5_2_compat
    zlib
  ];

  strictDeps = true;
  __structuredAttrs = true;

  makeFlags = [
    "--directory=src"
    "API=sdl2"
  ]
  ++ lib.optionals stdenv.hostPlatform.isDarwin [ "OSX_STATIC=0" ];
  buildFlags = lib.optionals stdenv.hostPlatform.isDarwin [ "../bin/grafx2-sdl2" ];
  installFlags = [ "PREFIX=$(out)" ];

  postInstall = ''
    installManPage misc/unix/grafx2.1
  '';

  meta = {
    homepage = "http://grafx2.eu/";
    description = "Ultimate 256-color painting program";
    longDescription = ''
      GrafX2 is a bitmap paint program inspired by the Amiga programs ​Deluxe
      Paint and Brilliance. Specialized in 256-color drawing, it includes a very
      large number of tools and effects that make it particularly suitable for
      pixel art, game graphics, and generally any detailed graphics painted with
      a mouse.

      The program is mostly developed on Haiku, Linux and Windows, but is also
      portable on many other platforms.
    '';
    license = lib.licenses.gpl2Plus;
    mainProgram = "grafx2-sdl2";
    maintainers = [ ];
    platforms = lib.platforms.unix;
  };
})
