#ifndef SHOTD_CODECS_H
#define SHOTD_CODECS_H

#include <stddef.h>
#include <stdint.h>

int shotd_webp_encode_rgba(const uint8_t *rgba, int width, int height, int stride, int lossless, float quality, uint8_t **output, size_t *output_size);
int shotd_webp_decode_rgba(const uint8_t *data, size_t data_size, uint8_t **rgba, int *width, int *height);

int shotd_avif_encode_rgba(const uint8_t *rgba, int width, int height, int stride, int lossless, int quality, uint8_t **output, size_t *output_size);
int shotd_avif_decode_rgba(const uint8_t *data, size_t data_size, uint8_t **rgba, int *width, int *height);

void shotd_codec_free(void *data);

#endif
