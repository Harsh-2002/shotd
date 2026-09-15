# Bundled Codec Sources

- libwebp: `c410d1d733a678e4a3288e97567b80644deefac6`
- libavif: `b994fe4601c62d6f98dbff295bd5c251940789b0`
- libaom: fetched by libavif's pinned CMake dependency during codec builds.

The project ships only static still-image codec libraries. Animation tools, CLI tools, muxers, and unrelated image conversion dependencies are disabled.
