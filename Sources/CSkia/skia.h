#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
typedef void* MSKSurface;
MSKSurface msk_create(int32_t width, int32_t height);
/// Metal-backed surface. device/queue are borrowed id<MTLDevice>/id<MTLCommandQueue>.
MSKSurface msk_create_gpu(int32_t width, int32_t height, const void* device, const void* queue);
void msk_clear(MSKSurface s);
void msk_destroy(MSKSurface s);
void msk_save(MSKSurface s, float alpha);
void msk_restore(MSKSurface s);
void msk_translate(MSKSurface s, float x, float y);
void msk_rotate(MSKSurface s, float degrees);
void msk_scale(MSKSurface s, float x, float y);
void msk_clip(MSKSurface s, float w, float h);
void msk_rect(MSKSurface s, float x, float y, float w, float h, float radius, uint32_t color);
bool msk_text(MSKSurface s, const char* text, const char* family, float size, uint32_t color, float x, float y);
bool msk_svg(MSKSurface s, const uint8_t* bytes, size_t len, float w, float h);
/// Unpremultiplied RGBA8888, tightly packed; len must equal width * height * 4.
bool msk_read_rgba(MSKSurface s, uint8_t* dst, size_t len);
/// GPU resolve to a borrowed id<MTLTexture> (BGRA8, same dimensions), synchronized on return.
bool msk_copy_to_metal_texture(MSKSurface s, const void* texture);
bool msk_png(MSKSurface s, const char* path);
