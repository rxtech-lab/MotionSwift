use skia_safe::{surfaces, Color, EncodedImageFormat, Font, FontMgr, FontStyle, Paint, Rect, Surface, canvas::{SaveLayerRec, SaveLayerFlags}};
use std::ffi::{c_char, CStr};

// Handles are owned by Swift's Canvas, confined to one render worker.
#[no_mangle]
pub extern "C" fn msk_create(width: i32, height: i32) -> *mut Surface {
    if width <= 0 || height <= 0 || width > 16384 || height > 16384 { return std::ptr::null_mut(); }
    surfaces::raster_n32_premul((width, height))
        .map(|mut s| { s.canvas().clear(Color::TRANSPARENT); Box::into_raw(Box::new(s)) })
        .unwrap_or(std::ptr::null_mut())
}
#[no_mangle]
pub unsafe extern "C" fn msk_clear(s: *mut Surface) { (*s).canvas().clear(Color::TRANSPARENT); }
#[no_mangle]
pub unsafe extern "C" fn msk_destroy(s: *mut Surface) { if !s.is_null() { drop(Box::from_raw(s)); } }
#[no_mangle]
pub unsafe extern "C" fn msk_save(s: *mut Surface, alpha: f32) {
    let mut paint = Paint::default();
    paint.set_alpha_f(alpha);
    let layer = SaveLayerRec::default().paint(&paint).flags(SaveLayerFlags::F16_COLOR_TYPE);
    (*s).canvas().save_layer(&layer);
}
#[no_mangle]
pub unsafe extern "C" fn msk_restore(s: *mut Surface) { (*s).canvas().restore(); }
#[no_mangle]
pub unsafe extern "C" fn msk_translate(s: *mut Surface, x: f32, y: f32) { (*s).canvas().translate((x,y)); }
#[no_mangle]
pub unsafe extern "C" fn msk_rotate(s: *mut Surface, degrees: f32) { (*s).canvas().rotate(degrees, None); }
#[no_mangle]
pub unsafe extern "C" fn msk_scale(s: *mut Surface, x: f32, y: f32) { (*s).canvas().scale((x,y)); }
#[no_mangle]
pub unsafe extern "C" fn msk_clip(s: *mut Surface, w: f32, h: f32) {
    (*s).canvas().clip_rect(Rect::from_xywh(0.,0.,w,h), None, true);
}
// Use device-space coverage for axis-aligned quads, retaining its 256-step
// precision through floating-point layers. Converting coverage to an alpha byte
// prematurely shifts scaled edges by one channel value against GPU references.
fn axis_bands(start: f32, end: f32) -> Vec<(f32, f32, f32)> {
    if end <= start { return vec![]; }
    if start.floor() == end.floor() { return vec![(start.floor(), end.ceil(), end-start)]; }
    let mut bands = vec![];
    if start.fract() != 0. { bands.push((start.floor(), start.ceil(), start.ceil()-start)); }
    if end.floor() > start.ceil() { bands.push((start.ceil(), end.floor(), 1.)); }
    if end.fract() != 0. { bands.push((end.floor(), end.ceil(), end-end.floor())); }
    bands
}
fn draw_quad(canvas: &skia_safe::Canvas, rect: Rect, color: u32) -> bool {
    let matrix = canvas.local_to_device_as_3x3();
    if !matrix.is_scale_translate() { return false; }
    let (device, _) = matrix.map_rect(rect);
    let horizontal = axis_bands(device.left, device.right);
    let vertical = axis_bands(device.top, device.bottom);
    canvas.save();
    canvas.reset_matrix();
    for &(left, right, x_coverage) in &horizontal {
        for &(top, bottom, y_coverage) in &vertical {
            // Convex-quad AA uses the closest edge, including at corners.
            let coverage = (x_coverage.min(y_coverage) * 256.).round() / 256.;
            let mut paint = Paint::default();
            paint.set_color(Color::new(color));
            // Keep fractional coverage through the floating-point layer. Converting
            // the mask to an alpha byte here would divide by 255 instead of 256.
            paint.set_alpha_f(((color >> 24) as f32 / 255.) * coverage);
            canvas.draw_rect(Rect::new(left, top, right, bottom), &paint);
        }
    }
    canvas.restore();
    true
}
#[no_mangle]
pub unsafe extern "C" fn msk_rect(s: *mut Surface, x: f32, y: f32, w: f32, h: f32, radius: f32, color: u32) {
    if radius == 0. && draw_quad((*s).canvas(), Rect::from_xywh(x,y,w,h), color) { return; }
    let mut paint = Paint::default();
    paint.set_color(Color::new(color)).set_anti_alias(true);
    (*s).canvas().draw_round_rect(Rect::from_xywh(x,y,w,h), radius, radius, &paint);
}
#[no_mangle]
pub unsafe extern "C" fn msk_text(s: *mut Surface, text: *const c_char, family: *const c_char, size: f32, color: u32, x: f32, y: f32) -> bool {
    let Ok(text) = CStr::from_ptr(text).to_str() else { return false; };
    let Ok(family) = CStr::from_ptr(family).to_str() else { return false; };
    let Some(face) = FontMgr::new().match_family_style(family, FontStyle::normal()) else { return false; };
    let font = Font::new(face, size);
    let mut paint = Paint::default();
    paint.set_color(Color::new(color)).set_anti_alias(true);
    (*s).canvas().draw_str(text, (x,y), &font, &paint);
    true
}
#[no_mangle]
pub unsafe extern "C" fn msk_png(s: *mut Surface, path: *const c_char) -> bool {
    let Ok(path) = CStr::from_ptr(path).to_str() else { return false; };
    let image = (*s).image_snapshot();
    let Some(data) = image.encode(None, EncodedImageFormat::PNG, None) else { return false; };
    std::fs::write(path, data.as_bytes()).is_ok()
}
