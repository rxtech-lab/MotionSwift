#include "include/utils/SkPaintFilterCanvas.h"
#include "include/core/SkPaint.h"
#include "include/core/SkRRect.h"
#include "include/core/SkData.h"
#include "include/core/SkSurface.h"
#include "include/effects/SkRuntimeEffect.h"
#include "src/shaders/SkShaderBase.h"
#include <string>
#include <vector>
#include "include/core/SkPathUtils.h"
#include "include/core/SkPath.h"
#include "include/core/SkPathBuilder.h"
#include "src/gpu/tessellate/WangsFormula.h"
#include "include/core/SkBitmap.h"
#include "include/core/SkImage.h"
#include "include/utils/SkParsePath.h"
static sk_sp<SkShader> pathMask(const SkPath& filled,const SkMatrix& matrix,SkIRect& bounds,const SkIRect* clip=nullptr) {
        auto device=filled.makeTransform(matrix);
        SkPathBuilder polygon;polygon.setFillType(device.getFillType());SkPath::Iter iter(device,true);SkPoint pts[4];
        for(auto verb=iter.next(pts);verb!=SkPath::kDone_Verb;verb=iter.next(pts)) {
            if(verb==SkPath::kMove_Verb)polygon.moveTo(pts[0]);
            else if(verb==SkPath::kLine_Verb)polygon.lineTo(pts[1]);
            else if(verb==SkPath::kClose_Verb)polygon.close();
            else {
                int log=verb==SkPath::kCubic_Verb?skgpu::wangs_formula::cubic_log2(4,pts):verb==SkPath::kQuad_Verb?skgpu::wangs_formula::quadratic_log2(4,pts):skgpu::wangs_formula::conic_log2(4,pts,iter.conicWeight());
                int count=1<<std::min(log,12);
                for(int i=1;i<=count;i++){float t=float(i)/count,u=1-t;SkPoint p;
                    if(verb==SkPath::kCubic_Verb)p=pts[0]*(u*u*u)+pts[1]*(3*u*u*t)+pts[2]*(3*u*t*t)+pts[3]*(t*t*t);
                    else if(verb==SkPath::kQuad_Verb)p=pts[0]*(u*u)+pts[1]*(2*u*t)+pts[2]*(t*t);
                    else {float w=iter.conicWeight();p=(pts[0]*(u*u)+pts[1]*(2*w*u*t)+pts[2]*(t*t))*(1/(u*u+2*w*u*t+t*t));}
                    polygon.lineTo(p);
                }
            }
        }device=polygon.detach();
        bounds=device.getBounds().makeOutset(1,1).roundOut();
        if(clip && !bounds.intersect(*clip))return nullptr;
        if(bounds.width()<=0 || bounds.height()<=0) return nullptr;
        SkBitmap mask;if(!mask.tryAllocPixels(SkImageInfo::Make(bounds.width(),bounds.height(),kRGBA_F32_SkColorType,kPremul_SkAlphaType)))return nullptr;mask.eraseColor(SK_ColorTRANSPARENT);
        // Rasterize four point samples with scan conversion, avoiding a path.contains()
        // search for every pixel and every sample of an animated vector path.
        const SkPoint samples[]={{.375,.125},{.875,.375},{.125,.625},{.625,.875}};
        SkBitmap sampleMask;if(!sampleMask.tryAllocPixels(SkImageInfo::MakeA8(bounds.width(),bounds.height())))return nullptr;
        SkPaint samplePaint;samplePaint.setColor(SK_ColorWHITE);
        for(auto sample:samples) {
            sampleMask.eraseColor(SK_ColorTRANSPARENT);SkCanvas canvas(sampleMask);
            canvas.translate(.5f-sample.x()-bounds.left(),.5f-sample.y()-bounds.top());
            canvas.drawPath(device,samplePaint);
            for(int y=0;y<bounds.height();y++)for(int x=0;x<bounds.width();x++)if(*sampleMask.getAddr8(x,y)) {
                auto pixel=(float*)mask.getAddr(x,y);for(int c=0;c<4;c++)pixel[c]+=.25f;
            }
        }
        auto image=SkImages::RasterFromBitmap(mask);
        return image->makeShader(SkTileMode::kDecal,SkTileMode::kDecal,SkSamplingOptions(),SkMatrix::Translate(bounds.left(),bounds.top()));
}
class SVGPaintCanvas final : public SkPaintFilterCanvas {
    SkCanvas* target;
public:
    explicit SVGPaintCanvas(SkCanvas* canvas):SkPaintFilterCanvas(canvas),target(canvas){}
protected:
    void rounded(const SkRect& rect,float radius,const SkPaint& original) {
        SkPaint paint=original;onFilter(paint);
        const char* source="uniform shader content;uniform shader backdrop; uniform float4 rect; uniform float radius;uniform float4 inverseJ; half4 main(float2 p) {float2 q=abs(p-(rect.xy+rect.zw)*0.5)-(rect.zw-rect.xy)*0.5+radius;q=max(q,float2(0));float d=(q.x>0.0 && q.y>0.0) ? (dot(q,q)-radius*radius)/max(2.0*length(q),0.00001) : length(q)-radius;float2 normal=normalize(max(q,float2(0.0000001)))*sign(p-(rect.xy+rect.zw)*0.5);float2 grad=float2(dot(normal,inverseJ.xy),dot(normal,inverseJ.zw));d/=max(length(grad),0.0000001);float coverage=clamp(0.5-d,0.0,1.0);float4 src=(floor(float4(content.eval(p))*255.0+0.5)/255.0)*coverage;float4 dst=floor(float4(backdrop.eval(p))*255.0+0.5)/255.0;return half4(floor((src+dst*(1.0-src.a))*255.0+0.5)/255.0);}";
        auto [effect,error]=SkRuntimeEffect::MakeForShader(SkString(source));
        if(!effect)return;
        SkRuntimeShaderBuilder builder(effect);
        builder.uniform("rect")=SkV4{rect.left(),rect.top(),rect.right(),rect.bottom()};
        builder.uniform("radius")=radius;
        SkMatrix pixelInverse;if(!target->getTotalMatrix().invert(&pixelInverse))return;
        builder.uniform("inverseJ")=SkV4{pixelInverse[0],pixelInverse[3],pixelInverse[1],pixelInverse[4]};
        builder.child("content")=paint.refShader()?paint.refShader():SkShaders::Color(paint.getColor4f(),nullptr);
        auto inverse=target->getTotalMatrix();if(!inverse.invert(&inverse))return;
        SkImageInfo layerInfo;size_t layerRowBytes;SkIPoint layerOrigin;sk_sp<SkImage> backdrop;
        if(auto pixels=target->accessTopLayerPixels(&layerInfo,&layerRowBytes,&layerOrigin)) {
            backdrop=SkImages::RasterFromPixmapCopy(SkPixmap(layerInfo,pixels,layerRowBytes));
            inverse=SkMatrix::Concat(inverse,SkMatrix::Translate(layerOrigin.x(),layerOrigin.y()));
        }else {auto surface=target->getSurface();if(!surface)return;backdrop=surface->makeImageSnapshot();}
        builder.child("backdrop")=backdrop->makeShader(SkTileMode::kClamp,SkTileMode::kClamp,SkSamplingOptions(),inverse);
        paint.setBlendMode(SkBlendMode::kSrc);
        paint.setColor(SK_ColorWHITE);paint.setShader(builder.makeShader());paint.setAntiAlias(false);paint.setDither(false);
        target->drawRect(rect.makeOutset(1,1),paint);
    }
    void onDrawPoints(PointMode mode,size_t count,const SkPoint points[],const SkPaint& paint) override {
        if(paint.getStyle()==SkPaint::kFill_Style) return;
        if(count==2 && paint.getStrokeWidth()>0 && paint.getStrokeWidth()<=1 && target->getTotalMatrix().isScaleTranslate()) {
            auto matrix=target->getTotalMatrix();auto a=matrix.mapPoint(points[0]);auto b=matrix.mapPoint(points[1]);
            if(a.y()==b.y() && !paint.getShader()) {
                float width=paint.getStrokeWidth()*fabs(matrix.getScaleY());float top=a.y()-width*.5f,bottom=a.y()+width*.5f;
                target->save();target->resetMatrix();
                for(int y=floor(top);y<ceil(bottom);y++) {
                    float coverage=floor(std::max(0.f,std::min(bottom,float(y+1))-std::max(top,float(y)))*255.f)/255.f;
                    SkPaint line=paint;line.setStyle(SkPaint::kFill_Style);line.setAntiAlias(false);line.setAlphaf(paint.getAlphaf()*coverage);
                    target->drawRect(SkRect::MakeLTRB(std::min(a.x(),b.x()),y,std::max(a.x(),b.x()),y+1),line);
                }target->restore();return;
            }
        }
        SkPaintFilterCanvas::onDrawPoints(mode,count,points,paint);
    }
    void onDrawPath(const SkPath& path,const SkPaint& paint) override {
        if(target->recordingContext()) {SkPaintFilterCanvas::onDrawPath(path,paint);return;}
        SkPaint filtered=paint;onFilter(filtered);auto cc=paint.getColor4f();
        auto filled=skpathutils::FillPathWithPaint(path,paint);
        auto matrix=target->getTotalMatrix();
        SkIRect bounds;auto clip=target->getDeviceClipBounds();auto alpha=pathMask(filled,matrix,bounds,&clip);if(!alpha)return;
        auto shader=filtered.refShader();if(!shader)shader=SkShaders::Color(filtered.getColor4f(),nullptr);
        else {auto inv=matrix; if(matrix.invert(&inv))shader=shader->makeWithLocalMatrix(matrix);}
        SkBitmap backdrop;backdrop.allocPixels(SkImageInfo::Make(bounds.width(),bounds.height(),kRGBA_F32_SkColorType,kPremul_SkAlphaType));backdrop.eraseColor(SK_ColorTRANSPARENT);
        SkImageInfo layerInfo;size_t layerRowBytes;SkIPoint layerOrigin;
        if(auto pixels=target->accessTopLayerPixels(&layerInfo,&layerRowBytes,&layerOrigin)) {
            SkPixmap(layerInfo,pixels,layerRowBytes).readPixels(backdrop.pixmap(),bounds.left()-layerOrigin.x(),bounds.top()-layerOrigin.y());
        } else {target->readPixels(backdrop.pixmap(),bounds.left(),bounds.top());}

        auto dst=SkImages::RasterFromBitmap(backdrop)->makeShader(SkTileMode::kDecal,SkTileMode::kDecal,SkSamplingOptions(),SkMatrix::Translate(bounds.left(),bounds.top()));
        auto [effect,error]=SkRuntimeEffect::MakeForShader(SkString("uniform float4 color;uniform float solid;uniform shader content;uniform shader mask;uniform shader backdrop;half4 main(float2 p){float4 dst=floor(float4(backdrop.eval(p))*255.0+0.5)/255.0;float4 src=(solid>0.5?color:float4(content.eval(p)))*float(mask.eval(p).a);return half4(floor((src+dst*(1.0-src.a))*255.0+0.5)/255.0);}"));
        if(!effect)return;
        SkRuntimeShaderBuilder builder(effect);builder.uniform("color")=SkV4{cc.fR*cc.fA,cc.fG*cc.fA,cc.fB*cc.fA,cc.fA};builder.uniform("solid")=paint.getShader()?0.f:1.f;builder.child("content")=shader;builder.child("mask")=alpha;builder.child("backdrop")=dst;
        filtered.setColor(SK_ColorWHITE);filtered.setShader(builder.makeShader());filtered.setBlendMode(SkBlendMode::kSrc);filtered.setStyle(SkPaint::kFill_Style);filtered.setAntiAlias(false);
        target->save();target->resetMatrix();target->drawRect(SkRect::Make(bounds),filtered);target->restore();
    }
    void onDrawOval(const SkRect& rect,const SkPaint& paint) override {
        if(rect.width()==rect.height() && paint.getStyle()==SkPaint::kFill_Style) rounded(rect,rect.width()/2,paint);
        else SkPaintFilterCanvas::onDrawOval(rect,paint);
    }
    void onDrawRRect(const SkRRect& rect,const SkPaint& paint) override {
        if(rect.isSimple() && rect.getSimpleRadii().fX==rect.getSimpleRadii().fY && paint.getStyle()==SkPaint::kFill_Style) rounded(rect.rect(),rect.getSimpleRadii().fX,paint);
        else SkPaintFilterCanvas::onDrawRRect(rect,paint);
    }
    bool onFilter(SkPaint& paint) const override {
        paint.setDither(true);
        if (auto shader=paint.getShader()) {
            SkShaderBase::GradientInfo info;
            SkMatrix local;
            auto kind=as_SB(shader)->asGradient(&info,&local);
            if(kind==SkShaderBase::GradientType::kLinear) {
                std::vector<SkColor4f> colors(info.fColorCount);
                std::vector<float> stops(info.fColorCount);
                info.fColors=colors.data();info.fColorOffsets=stops.data();
                as_SB(shader)->asGradient(&info,&local);
                int count=info.fColorCount;
                std::string n=std::to_string(count);
                std::string source="uniform float3x3 device; uniform float4 geometry; uniform float4 colors["+n+"]; uniform float stops["+n+"]; half4 main(float2 p) { float2 delta=geometry.zw-geometry.xy; float t=dot(p-geometry.xy,delta)/dot(delta,delta)+0.00001; float4 c=colors[0]; for(int i=1;i<"+n+";++i) {float u=clamp((t-stops[i-1])/max(0.0000001,stops[i]-stops[i-1]),0.0,1.0);c=c+(colors[i]-c)*u;} float3 q=device*float3(p,1); float2 xy=floor(q.xy/q.z); float x=xy.x;float y=xy.y;float m=mod(y,2.0)*32.0+mod(x,2.0)*16.0+mod(floor(y/2.0),2.0)*8.0+mod(floor(x/2.0),2.0)*4.0+mod(floor(y/4.0),2.0)*2.0+mod(floor(x/4.0),2.0);float d=(floor((m/64.0-63.0/128.0+0.5)*255.0+0.5)/255.0-0.5)/255.0; c.rgb=floor(clamp(c.rgb+d,0.0,c.a)*255.0+0.5)/255.0;return half4(c);}";
                auto [effect,error]=SkRuntimeEffect::MakeForShader(SkString(source));
                if(effect) {
                    SkMatrix device=SkMatrix::Concat(this->getTotalMatrix(),local);
                    std::vector<float> values={device[0],device[3],device[6],device[1],device[4],device[7],device[2],device[5],device[8],info.fPoint[0].fX,info.fPoint[0].fY,info.fPoint[1].fX,info.fPoint[1].fY};
                    for(auto c:colors) {values.push_back(c.fR);values.push_back(c.fG);values.push_back(c.fB);values.push_back(c.fA);}
                    values.insert(values.end(),stops.begin(),stops.end());
                    paint.setDither(false);paint.setShader(effect->makeShader(SkData::MakeWithCopy(values.data(),values.size()*sizeof(float)),{},&local));
                }
            }
        }
        return true;
    }
};
extern "C" void* msk_svg_paint_canvas(const void* canvas) {return new SVGPaintCanvas((SkCanvas*)canvas);}
extern "C" void msk_svg_paint_canvas_destroy(void* canvas) {delete (SVGPaintCanvas*)canvas;}

extern "C" bool msk_path_coverage(const char* svg,const float* values,unsigned char* output,int width,int height) {
    auto path=SkParsePath::FromSVGString(svg);if(!path || width<=0 || height<=0)return false;
    SkMatrix matrix;matrix.set9(values);SkIRect bounds;auto clip=SkIRect::MakeWH(width,height);auto shader=pathMask(*path,matrix,bounds,&clip);
    SkRect oval=path->getBounds();int conics=0;bool ellipse=oval.width()>0 && oval.height()>0;SkPath::Iter iter(*path,true);SkPoint pts[4];
    auto normalize=[&](SkPoint p){return SkPoint::Make((p.x()-oval.centerX())/(oval.width()*.5f),(p.y()-oval.centerY())/(oval.height()*.5f));};
    auto cardinal=[](SkPoint p){return (fabs(fabs(p.x())-1)<.0001f && fabs(p.y())<.0001f)||(fabs(fabs(p.y())-1)<.0001f && fabs(p.x())<.0001f);};
    for(auto verb=iter.next(pts);verb!=SkPath::kDone_Verb;verb=iter.next(pts)) {
        if(verb==SkPath::kConic_Verb) {
            conics++;auto start=normalize(pts[0]),control=normalize(pts[1]),end=normalize(pts[2]);
            if(fabs(iter.conicWeight()-.70710678f)>.0001f || !cardinal(start) || !cardinal(end) || fabs(start.dot(end))>.0001f || (control-start-end).length()>.0001f)ellipse=false;
        }else if(verb!=SkPath::kMove_Verb && verb!=SkPath::kClose_Verb)ellipse=false;
    }
    if(ellipse && conics==4 && matrix.isScaleTranslate()) {
        auto box=matrix.mapRect(oval);auto [effect,error]=SkRuntimeEffect::MakeForShader(SkString("uniform float4 rect;half4 main(float2 p){float2 radius=(rect.zw-rect.xy)*0.5;float2 q=(p-(rect.xy+rect.zw)*0.5)/radius;float d=(dot(q,q)-1.0)/max(length(2.0*q/radius),0.0000001);return half4(clamp(0.5-d,0.0,1.0));}"));
        // A failed SkSL compilation has no effect. The builder dereferences it even
        // in Release, so propagate failure to Swift instead of crashing the preview.
        if(!effect)return false;
        SkRuntimeShaderBuilder builder(effect);builder.uniform("rect")=SkV4{box.left(),box.top(),box.right(),box.bottom()};shader=builder.makeShader();
    }
    if(!shader)return false;
    SkBitmap bitmap;if(!bitmap.tryAllocPixels(SkImageInfo::Make(width,height,kRGBA_F32_SkColorType,kPremul_SkAlphaType)))return false;bitmap.eraseColor(SK_ColorTRANSPARENT);
    SkCanvas canvas(bitmap);SkPaint paint;
    paint.setShader(shader);canvas.drawPaint(paint);
    for(int y=0;y<height;y++)for(int x=0;x<width;x++){float a=std::clamp(((float*)bitmap.getAddr(x,y))[3],0.f,1.f)*255.f;int hi=floor(a),lo=round((a-hi)*255.f);auto p=output+(y*width+x)*4;p[0]=hi;p[1]=lo;p[2]=(ellipse&&conics==4)?0:255;p[3]=255;}
    return true;
}
extern "C" void msk_rrect_mask(void* ptr,float left,float top,float right,float bottom,float radius) {
    auto canvas=(SkCanvas*)ptr;
    auto [effect,error]=SkRuntimeEffect::MakeForShader(SkString("uniform float4 rect;uniform float radius;uniform float4 inverseJ;half4 main(float2 p){float2 q=max(abs(p-(rect.xy+rect.zw)*0.5)-(rect.zw-rect.xy)*0.5+radius,float2(0));float d=(q.x>0.0 && q.y>0.0)?(dot(q,q)-radius*radius)/max(2.0*length(q),0.00001):length(q)-radius;float2 normal=normalize(max(q,float2(0.0000001)))*sign(p-(rect.xy+rect.zw)*0.5);d/=max(length(float2(dot(normal,inverseJ.xy),dot(normal,inverseJ.zw))),0.0000001);return half4(clamp(0.5-d,0.0,1.0));}"));
    if(!effect)return;
    SkRuntimeShaderBuilder builder(effect);builder.uniform("rect")=SkV4{left,top,right,bottom};builder.uniform("radius")=radius;SkMatrix inverse;if(!canvas->getTotalMatrix().invert(&inverse))return;builder.uniform("inverseJ")=SkV4{inverse[0],inverse[3],inverse[1],inverse[4]};
    SkPaint paint;paint.setShader(builder.makeShader());canvas->drawRect(SkRect::MakeLTRB(left-1,top-1,right+1,bottom+1),paint);
}

// Skia 0.99 assumes every macOS Metal device supports border samplers, including
// virtual devices that reject them. Disable that capability before recording draws;
// Ganesh then implements decal edges in its texture shaders on the same GPU.
#include "src/gpu/ganesh/GrRecordingContextPriv.h"
#include "src/gpu/ganesh/GrCaps.h"
void disableBorderSamplers(GrCaps&);
// Explicit template instantiation permits access to the pinned protected capability
// (C++20 [temp.explicit]). This avoids layout casts or modifying Skia's binary ABI.
template<auto setter> struct BorderCapabilityAccess {
    friend void disableBorderSamplers(GrCaps& caps) { setter(caps); }
};
template struct BorderCapabilityAccess<[](GrCaps& caps) { caps.fClampToBorderSupport=false; }>;
extern "C" void msk_shader_borders(const void* raw) {
    auto canvas=static_cast<const SkCanvas*>(raw);
    if(auto context=canvas->recordingContext()) {
        disableBorderSamplers(*const_cast<GrCaps*>(context->priv().caps()));
    }
}
