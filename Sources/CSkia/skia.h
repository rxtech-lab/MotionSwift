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

bool msk_image_rgba(MSKSurface s, const uint8_t* bytes, size_t len, int32_t iw, int32_t ih, float w, float h, int32_t fit);

typedef void* MSKFonts;
typedef void* MSKParagraph;
typedef void* MSKParagraphBuilder;
MSKFonts msk_fonts_create(void);
void msk_fonts_destroy(MSKFonts fonts);
bool msk_fonts_register(MSKFonts fonts, const uint8_t* bytes, size_t len, const char* family);
MSKParagraphBuilder msk_paragraph_builder(MSKFonts fonts, int32_t align);
void msk_paragraph_add(MSKParagraphBuilder builder, const char* text, const char* families, float size, int32_t weight, bool italic, uint32_t color, float height, float spacing);
MSKParagraph msk_paragraph_build(MSKParagraphBuilder builder);
void msk_paragraph_destroy(MSKParagraph paragraph);
void msk_paragraph_layout(MSKParagraph paragraph, float width);
float msk_paragraph_height(MSKParagraph paragraph);
float msk_paragraph_width(MSKParagraph paragraph);
float msk_paragraph_baseline(MSKParagraph paragraph);
void msk_paragraph_paint(MSKSurface surface, MSKParagraph paragraph, float x, float y);

// CSS compositing. Filter entry: kind + 20 floats (0 blur sigma, 1 4x5 color matrix).
void msk_effect_layer(MSKSurface s, float alpha, int32_t blend, const float* entries, size_t count);
void msk_backdrop(MSKSurface s, float w, float h, float radius, float sigma);
void msk_concat(MSKSurface s, const float* matrix9);
bool msk_clip_path(MSKSurface s, const char* svg);
bool msk_gradient(MSKSurface s, float w, float h, float radius, int32_t kind, const float* geometry4, const uint32_t* colors, const float* stops, size_t count, int32_t mode);
void msk_shadow(MSKSurface s, float w, float h, float radius, float dx, float dy, float sigma, float spread, uint32_t color, bool inset);

void msk_save_state(MSKSurface s);
