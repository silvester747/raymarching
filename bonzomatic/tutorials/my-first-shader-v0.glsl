#version 410 core

uniform float fGlobalTime; // in seconds
uniform vec2 v2Resolution; // viewport resolution (in pixels)
uniform float fFrameTime; // duration of the last frame, in seconds

uniform sampler1D texFFT; // towards 0.0 is bass / lower freq, towards 1.0 is higher / treble freq
uniform sampler1D texFFTSmoothed; // this one has longer falloff and less harsh transients
uniform sampler1D texFFTIntegrated; // this is continually increasing
uniform sampler2D texPreviousFrame; // screenshot of the previous frame
uniform sampler2D texChecker;
uniform sampler2D texNoise;
uniform sampler2D texTex1;
uniform sampler2D texTex2;
uniform sampler2D texTex3;
uniform sampler2D texTex4;

in vec2 out_texcoord;
layout(location = 0) out vec4 out_color; // out_color must be written in order to see anything

#define MAX_STEPS 100
#define MAX_DIST 100.
#define SURF_DIST .01

float Sphere(vec4 s, vec3 p, float offset, float speed) {
    s.y += 1. + sin(fGlobalTime * speed + offset);
    s.w *= texture(texFFT, 0.1).x;
    float d = length(p-s.xyz)-s.w;
    return d;
}

float GetDist(vec3 p) {
    float sd1 = Sphere(vec4(0, 1, 6. - (cos(fGlobalTime) * 2.5), 3), p, 0., 1.);
    float sd2 = Sphere(vec4(-2, 1, 6, 2), p, 1., 1.5);
    float sd3 = Sphere(vec4(3, 1, 6. + (sin(fGlobalTime) * 3.), 4), p, 2., 3.);
    float sd4 = Sphere(vec4(sin(fGlobalTime/2.) * 5., 1, 6. + cos(fGlobalTime/2.) * 2., 1), p, 1., 1.);
    float sd = min(min(min(sd1, sd2), sd3), sd4);
    
    float audio = texture(texFFT, 0.1).x;
    float planeDist = p.y + texture(texFFT, p.y).x * sin(p.x + fGlobalTime);
    
    float d = min(sd, planeDist);
    return d;
}


float RayMarch(vec3 ro, vec3 rd) {
    float dO=0.;
    
    for(int i=0; i<MAX_STEPS; i++) {
        vec3 p = ro + rd * dO;
        float dS = GetDist(p);
        dO += dS;
        if(dO>MAX_DIST || dS<SURF_DIST) break;
    }
    
    return dO;
}

vec3 GetNormal(vec3 p) {
    float d = GetDist(p);
    vec2 e = vec2(.01, 0);
    
    // Swizzle
    // e.xyy -> vec3(e.x, e.y, e.y)
    vec3 n = d - vec3(
        GetDist(p-e.xyy),
        GetDist(p-e.yxy),
        GetDist(p-e.yyx));
        
    return normalize(n);
}

float GetLight(vec3 p) {
    vec3 lightPos = vec3(0, 7, 3);
    lightPos.xz += vec2(sin(fGlobalTime*2.), cos(fGlobalTime)) * 1.25;
    vec3 l = normalize(lightPos - p);
    vec3 n = GetNormal(p);
    //float intensity = clamp(1. - texture(texFFT, 0.5).x, 0.5, 1.);
    float intensity = 1.0;

    float dif = clamp(dot(n, l), 0., 1.) * intensity;
    float d = RayMarch(p+n*SURF_DIST*2., l);
    if (d<length(lightPos - p)) dif *= .1;
    return dif;
}

void main(void)
{
	vec2 uv = (gl_FragCoord.xy - 0.5 * v2Resolution.xy) / v2Resolution.y;
    
  vec3 col = vec3(0);
    
    vec3 ro = vec3(0, 3, -4);
    vec3 rd = normalize(vec3(uv.x, uv.y, 1)); 
    
    float d = RayMarch(ro, rd);
    
    vec3 p = ro + rd * d;
    float dif = GetLight(p);
    col = vec3((sin(fGlobalTime) + 1.)/2. + p.x*sin(fGlobalTime), 0.5, 1) * dif;

    out_color = vec4(col, 1.0);
  

}