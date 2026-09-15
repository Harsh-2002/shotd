#!/bin/zsh
set -euo pipefail

root="${0:A:h:h}"
deployment_target="${1:-14.0}"

if ! command -v cmake >/dev/null; then
  print -u2 "cmake is required to build shotd's bundled codecs."
  exit 1
fi

cmake -S "$root/CodecKit/WebP" -B "$root/CodecKit/build-webp" \
  -DCMAKE_OSX_DEPLOYMENT_TARGET="$deployment_target" \
  -DBUILD_SHARED_LIBS=OFF \
  -DWEBP_BUILD_ANIM_UTILS=OFF \
  -DWEBP_BUILD_CWEBP=OFF \
  -DWEBP_BUILD_DWEBP=OFF \
  -DWEBP_BUILD_GIF2WEBP=OFF \
  -DWEBP_BUILD_IMG2WEBP=OFF \
  -DWEBP_BUILD_VWEBP=OFF \
  -DWEBP_BUILD_WEBPINFO=OFF \
  -DWEBP_BUILD_LIBWEBPMUX=OFF \
  -DWEBP_BUILD_WEBPMUX=OFF \
  -DWEBP_BUILD_EXTRAS=OFF \
  -DWEBP_BUILD_WEBP_JS=OFF \
  -DWEBP_BUILD_FUZZTEST=OFF \
  -DCMAKE_BUILD_TYPE=Release
cmake --build "$root/CodecKit/build-webp" --parallel

cmake -S "$root/CodecKit/AVIF" -B "$root/CodecKit/build-avif" \
  -DCMAKE_OSX_DEPLOYMENT_TARGET="$deployment_target" \
  -DBUILD_SHARED_LIBS=OFF \
  -DAVIF_CODEC_AOM=LOCAL \
  -DAVIF_CODEC_DAV1D=OFF \
  -DAVIF_CODEC_LIBGAV1=OFF \
  -DAVIF_CODEC_RAV1E=OFF \
  -DAVIF_CODEC_SVT=OFF \
  -DAVIF_LIBYUV=OFF \
  -DAVIF_ZLIBPNG=OFF \
  -DAVIF_JPEG=OFF \
  -DAVIF_BUILD_APPS=OFF \
  -DAVIF_BUILD_TESTS=OFF \
  -DAVIF_BUILD_EXAMPLES=OFF \
  -DCMAKE_BUILD_TYPE=Release
cmake --build "$root/CodecKit/build-avif" --parallel
