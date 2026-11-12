#include <stdint.h>
#include <stdbool.h>
typedef void* MSKSurface;
MSKSurface msk_create(int32_t width, int32_t height);
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
bool msk_png(MSKSurface s, const char* path);
