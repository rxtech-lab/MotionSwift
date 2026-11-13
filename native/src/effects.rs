//! Compositing primitives shared by raster and Metal. Parsing/contract validation is in Swift.
use super::*;
use skia_safe::{BlendMode, TileMode, Matrix, Path, RRect, ClipOp, image_filters};

fn blend(value: i32) -> BlendMode {
    match value {
        1 => BlendMode::Multiply, 2 => BlendMode::Screen, 3 => BlendMode::Overlay,
        4 => BlendMode::Darken, 5 => BlendMode::Lighten, 6 => BlendMode::ColorDodge,
        7 => BlendMode::ColorBurn, 8 => BlendMode::HardLight, 9 => BlendMode::SoftLight,
        10 => BlendMode::Difference, 11 => BlendMode::Exclusion, 12 => BlendMode::Hue,
        13 => BlendMode::Saturation, 14 => BlendMode::Color, 15 => BlendMode::Luminosity,
        _ => BlendMode::SrcOver,
    }
}

/// Filter entries are 21 floats: kind (0 blur, 1 color matrix), then 20 matrix values.
#[no_mangle]
pub unsafe extern "C" fn msk_effect_layer(s: *mut Target, alpha: f32, mode: i32, entries: *const f32, count: usize) {
    let mut filter = None;
    for index in 0..count {
        let v = std::slice::from_raw_parts(entries.add(index * 21), 21);
        filter = if v[0] == 0. {
            image_filters::blur((v[1], v[1]), TileMode::Decal, filter, None)
        } else if v[0] == 2. {
            image_filters::drop_shadow((v[1],v[2]),(v[3],v[3]),skia_safe::Color4f::new(v[4],v[5],v[6],v[7]),None,filter,None)
        } else {
            let matrix: &[f32; 20] = v[1..].try_into().unwrap();
            image_filters::color_filter(color_filters::matrix_row_major(matrix, None), filter, None)
        };
    }
    let mut paint = Paint::default();
    paint.set_blend_mode(blend(mode)).set_color_filter(alpha_filter(alpha)).set_image_filter(filter);
    (*s).surface.canvas().save_layer(&SaveLayerRec::default().paint(&paint).flags(SaveLayerFlags::F16_COLOR_TYPE));
}

#[no_mangle]
pub unsafe extern "C" fn msk_backdrop(s: *mut Target, w: f32, h: f32, radius: f32, sigma: f32) {
    let canvas = (*s).surface.canvas();
    if let Some(filter) = image_filters::blur((sigma,sigma), TileMode::Clamp, None, None) {
        // Sample the entire backdrop before restricting the output to the box.
        // Clipping before saveLayer clamps the blur at the element's edge.
        canvas.save_layer(&SaveLayerRec::default().backdrop(&filter));
        canvas.save();
        canvas.clip_rrect(RRect::new_rect_xy(Rect::from_wh(w,h), radius, radius), ClipOp::Difference, true);
        let mut clear = Paint::default();
        clear.set_blend_mode(BlendMode::Clear);
        canvas.draw_paint(&clear);
        canvas.restore();
        canvas.restore();
    }
}

#[no_mangle]
pub unsafe extern "C" fn msk_concat(s: *mut Target, values: *const f32) {
    let v = std::slice::from_raw_parts(values, 9);
    (*s).surface.canvas().concat(&Matrix::new_all(v[0],v[1],v[2],v[3],v[4],v[5],v[6],v[7],v[8]));
}

#[no_mangle]
pub unsafe extern "C" fn msk_clip_path(s: *mut Target, svg: *const c_char) -> bool {
    let Ok(svg) = CStr::from_ptr(svg).to_str() else { return false; };
    let Some(path) = Path::from_svg(svg) else { return false; };
    (*s).surface.canvas().clip_path(&path, None, true);
    true
}

/// mode 0 background, 1 alpha mask (DstIn on an isolated layer).
#[no_mangle]
pub unsafe extern "C" fn msk_gradient(s: *mut Target, w: f32, h: f32, radius: f32, kind: i32, geometry: *const f32, colors: *const u32, stops: *const f32, count: usize, mode: i32) -> bool {
    if count < 2 || count > 256 { return false; }
    let colors: Vec<Color> = std::slice::from_raw_parts(colors,count).iter().map(|c| Color::new(*c)).collect();
    // Rasterize the CSS gradient in full float precision before the 8-bit
    // ordered dither used by Chrome. A half-valued child shader loses that precision.
    let matrix = (*s).surface.canvas().local_to_device_as_3x3();
    let coordinate = if kind == 0 {
        "float2 delta=geometry.zw-geometry.xy; float t=dot(p-geometry.xy,delta)/dot(delta,delta);"
    } else { "float t=length((p-geometry.xy)/geometry.zw);" };
    let source = format!("uniform float3x3 device; uniform float4 geometry; uniform float4 colors[{count}]; uniform float stops[{count}]; half4 main(float2 p) {{ {coordinate} float4 c=colors[0]; for(int i=1;i<{count};++i) {{ float u=clamp((t-stops[i-1])/max(0.0000001,stops[i]-stops[i-1]),0.0,1.0); c=mix(c,colors[i],u); }} float3 q=device*float3(p,1); float2 xy=floor(q.xy/q.z); float x=xy.x; float y=xy.y; float m=mod(y,2.0)*32.0+mod(x,2.0)*16.0+mod(floor(y/2.0),2.0)*8.0+mod(floor(x/2.0),2.0)*4.0+mod(floor(y/4.0),2.0)*2.0+mod(floor(x/4.0),2.0); float d=(m/64.0-63.0/128.0)/255.0; c.rgb=floor(clamp(c.rgb+d,0.0,c.a)*255.0+0.5)/255.0; return half4(c); }}");
    let Ok(effect) = RuntimeEffect::make_for_shader(&source,None) else { return false; };
    let mut values = vec![matrix.scale_x(),matrix.skew_y(),matrix.persp_x(), matrix.skew_x(),matrix.scale_y(),matrix.persp_y(),matrix.translate_x(),matrix.translate_y(),matrix[8]];
    values.extend_from_slice(std::slice::from_raw_parts(geometry,4));
    for color in &colors {
        let alpha = color.a() as f32 / 255.;
        values.extend_from_slice(&[color.r() as f32 / 255. * alpha,color.g() as f32 / 255. * alpha,color.b() as f32 / 255. * alpha,alpha]);
    }
    values.extend_from_slice(std::slice::from_raw_parts(stops,count));
    let bytes: Vec<u8> = values.iter().flat_map(|v| v.to_ne_bytes()).collect();
    let Some(shader) = effect.make_shader(Data::new_copy(&bytes),&[],None) else { return false; };
    let mut paint = Paint::default();
    paint.set_shader(shader).set_anti_alias(true).set_dither(true);
    if mode == 1 { paint.set_blend_mode(BlendMode::DstIn); }
    (*s).surface.canvas().draw_round_rect(Rect::from_wh(w,h),radius,radius,&paint);
    true
}

#[no_mangle]
pub unsafe extern "C" fn msk_shadow(s: *mut Target, w: f32, h: f32, radius: f32, dx: f32, dy: f32, sigma: f32, spread: f32, color: u32, inset: bool) {
    let canvas = (*s).surface.canvas();
    let box_shape = RRect::new_rect_xy(Rect::from_wh(w,h),radius,radius);
    canvas.save();
    let mut paint = Paint::default();
    paint.set_color(Color::new(color)).set_anti_alias(true);
    if sigma > 0. { paint.set_mask_filter(skia_safe::MaskFilter::blur(skia_safe::BlurStyle::Normal,sigma,true)); }
    if inset {
        canvas.clip_rrect(box_shape,None,true);
        let hole = RRect::new_rect_xy(Rect::from_xywh(dx+spread,dy+spread,w-2.*spread,h-2.*spread),(radius-spread).max(0.),(radius-spread).max(0.));
        let mut path = skia_safe::PathBuilder::new();
        let extent = w.max(h) + sigma*10. + dx.abs() + dy.abs() + spread.abs();
        path.add_rect(Rect::from_xywh(-extent,-extent,w+2.*extent,h+2.*extent),None,None);
        path.add_rrect(hole,None,None);
        path.set_fill_type(skia_safe::PathFillType::EvenOdd);
        canvas.draw_path(&path.detach(),&paint);
    } else {
        canvas.clip_rrect(box_shape,ClipOp::Difference,true);
        canvas.draw_round_rect(Rect::from_xywh(dx-spread,dy-spread,w+2.*spread,h+2.*spread),(radius+spread).max(0.),(radius+spread).max(0.),&paint);
    }
    canvas.restore();
}

#[no_mangle]
pub unsafe extern "C" fn msk_save_state(s: *mut Target) { (*s).surface.canvas().save(); }
