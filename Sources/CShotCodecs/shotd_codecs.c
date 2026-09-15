#include "shotd_codecs.h"

#include <avif/avif.h>
#include <stdlib.h>
#include <string.h>
#include <webp/decode.h>
#include <webp/encode.h>

static int copy_output(const uint8_t *source, size_t source_size, uint8_t **output, size_t *output_size) {
    uint8_t *copy = malloc(source_size);
    if (copy == NULL) {
        return 0;
    }
    memcpy(copy, source, source_size);
    *output = copy;
    *output_size = source_size;
    return 1;
}

void shotd_codec_free(void *data) {
    free(data);
}

int shotd_webp_encode_rgba(const uint8_t *rgba, int width, int height, int stride, int lossless, float quality, uint8_t **output, size_t *output_size) {
    WebPConfig config;
    WebPPicture picture;
    WebPMemoryWriter writer;
    int result = 0;

    *output = NULL;
    *output_size = 0;
    if (!WebPConfigInit(&config) || !WebPPictureInit(&picture)) {
        return 0;
    }
    if (lossless) {
        // Screenshot capture favors immediate availability over a smaller lossless file.
        if (!WebPConfigLosslessPreset(&config, 0)) {
            return 0;
        }
    } else {
        config.quality = quality;
    }
    config.thread_level = 1;
    picture.width = width;
    picture.height = height;
    if (!WebPPictureImportRGBA(&picture, rgba, stride)) {
        WebPPictureFree(&picture);
        return 0;
    }
    WebPMemoryWriterInit(&writer);
    picture.writer = WebPMemoryWrite;
    picture.custom_ptr = &writer;
    if (WebPEncode(&config, &picture)) {
        result = copy_output(writer.mem, writer.size, output, output_size);
    }
    WebPMemoryWriterClear(&writer);
    WebPPictureFree(&picture);
    return result;
}

int shotd_webp_decode_rgba(const uint8_t *data, size_t data_size, uint8_t **rgba, int *width, int *height) {
    uint8_t *decoded = WebPDecodeRGBA(data, data_size, width, height);
    size_t size;
    int result;
    if (decoded == NULL || *width <= 0 || *height <= 0) {
        return 0;
    }
    size = (size_t)(*width) * (size_t)(*height) * 4;
    result = copy_output(decoded, size, rgba, &size);
    WebPFree(decoded);
    return result;
}

int shotd_avif_encode_rgba(const uint8_t *rgba, int width, int height, int stride, int lossless, int quality, uint8_t **output, size_t *output_size) {
    avifImage *image = NULL;
    avifEncoder *encoder = NULL;
    avifRGBImage rgb;
    avifRWData encoded = AVIF_DATA_EMPTY;
    int result = 0;

    *output = NULL;
    *output_size = 0;
    image = avifImageCreate(width, height, 8, AVIF_PIXEL_FORMAT_YUV444);
    if (image == NULL) {
        return 0;
    }
    image->yuvRange = AVIF_RANGE_FULL;
    image->matrixCoefficients = AVIF_MATRIX_COEFFICIENTS_IDENTITY;
    avifRGBImageSetDefaults(&rgb, image);
    rgb.format = AVIF_RGB_FORMAT_RGBA;
    rgb.pixels = (uint8_t *)rgba;
    rgb.rowBytes = (uint32_t)stride;
    if (avifImageRGBToYUV(image, &rgb) != AVIF_RESULT_OK) {
        avifImageDestroy(image);
        return 0;
    }
    encoder = avifEncoderCreate();
    if (encoder == NULL) {
        avifImageDestroy(image);
        return 0;
    }
    encoder->codecChoice = AVIF_CODEC_CHOICE_AOM;
    // Screenshots favor bounded latency; losslessness is controlled by quantizers, not speed.
    encoder->speed = AVIF_SPEED_FASTEST;
    if (lossless) {
        encoder->minQuantizer = 0;
        encoder->maxQuantizer = 0;
        encoder->minQuantizerAlpha = 0;
        encoder->maxQuantizerAlpha = 0;
    } else {
        int quantizer = 63 - ((quality * 63) / 100);
        encoder->minQuantizer = quantizer;
        encoder->maxQuantizer = quantizer;
        encoder->minQuantizerAlpha = quantizer;
        encoder->maxQuantizerAlpha = quantizer;
    }
    if (avifEncoderWrite(encoder, image, &encoded) == AVIF_RESULT_OK) {
        result = copy_output(encoded.data, encoded.size, output, output_size);
    }
    avifRWDataFree(&encoded);
    avifEncoderDestroy(encoder);
    avifImageDestroy(image);
    return result;
}

int shotd_avif_decode_rgba(const uint8_t *data, size_t data_size, uint8_t **rgba, int *width, int *height) {
    avifDecoder *decoder = avifDecoderCreate();
    avifImage *image = avifImageCreateEmpty();
    avifRGBImage rgb;
    size_t size;
    int result = 0;
    if (decoder == NULL || image == NULL || avifDecoderReadMemory(decoder, image, data, data_size) != AVIF_RESULT_OK) {
        avifDecoderDestroy(decoder);
        avifImageDestroy(image);
        return 0;
    }
    *width = (int)image->width;
    *height = (int)image->height;
    size = (size_t)(*width) * (size_t)(*height) * 4;
    *rgba = malloc(size);
    if (*rgba != NULL) {
        avifRGBImageSetDefaults(&rgb, image);
        rgb.format = AVIF_RGB_FORMAT_RGBA;
        rgb.pixels = *rgba;
        rgb.rowBytes = (uint32_t)(*width * 4);
        result = avifImageYUVToRGB(image, &rgb) == AVIF_RESULT_OK;
        if (!result) {
            free(*rgba);
            *rgba = NULL;
        }
    }
    avifDecoderDestroy(decoder);
    avifImageDestroy(image);
    return result;
}
