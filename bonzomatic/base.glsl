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

layout(location = 0) out vec4 out_color; // out_color must be written in order to see anything

const int MAX_STEPS = 100;
const int MAX_DIST = 100;
const float SURF_DIST = 0.01;

const float M_FFT_SCALE = 10.;
const float M_PI = 3.1415926535897932384626433832795;
const float M_2PI = (2 * M_PI);

//
// Shape functions
//
float sdSphere( vec3 p, float s )
{
  return length(p)-s;
}

float sdBox( vec3 p, vec3 b )
{
  vec3 q = abs(p) - b;
  return length(max(q,0.0)) + min(max(q.x,max(q.y,q.z)),0.0);
}

//
// Transformation functions
//

mat3 rotateX(in float a) {
  return mat3(
    1., 0., 0.,
    0., cos(a), -sin(a),
    0., sin(a), cos(a)
  );
}

mat3 rotateY(in float a) {
  return mat3(
    cos(a), 0., sin(a),
    0., 1., 0.,
    -sin(a), 0., cos(a)
  );
}

mat3 rotateZ(in float a) {
  return mat3(
    cos(a), -sin(a), 0.,
    sin(a), cos(a), 0.,
    0., 0., 1.
  );
}

//
// Audio functions
//
float fft(in float freq)
{
  return M_FFT_SCALE * texture(texFFTSmoothed, freq).x;
}

//
// Scene
//
vec4 background(void) {
  return vec4(0.1, 0.1, 0.3, 1.0);
}

float map(in vec3 p, out vec4 info) {
  float d = MAX_DIST;
  info.w = 0.;

  d = sdBox(p, vec3(1, 1, 1));

  return d;
}

vec3 normal(vec3 p) {
  vec4 info = vec4(0.);
	float d = map(p, info);
  vec2 e = vec2(.01, 0);
    
  vec3 n = d - vec3(
      map(p-e.xyy, info),
      map(p-e.yxy, info),
      map(p-e.yyx, info));
    
  return normalize(n);
}

vec3 lighting(vec3 p, vec4 info) {
  vec3 light_pos = vec3(5. , 5., -5.);
  vec3 l = normalize(light_pos - p);
  vec3 n = normal(p);
  float dif = clamp(dot(l, n), 0., 1.);

  vec3 col = vec3(1, 1, 0);
  col = col * dif;
  col = pow(col, vec3(.4545));	// gamma correction

  return col;
}

vec3 camera(vec2 uv, vec3 p, vec3 l, float z) {
    vec3 f = normalize(l-p);
    vec3 r = normalize(cross(vec3(0,1,0), f));
    vec3 u = cross(f,r);
    vec3 c = p+f*z;
    vec3 i = c + uv.x*r + uv.y*u;
    return normalize(i-p);
}

void main(void)
{
  vec2 uv = (gl_FragCoord.xy-.5*v2Resolution.xy)/v2Resolution.y;
  vec3 ro = vec3(5. * sin(fGlobalTime) , 2. + sin(fGlobalTime / 4.), 5. * cos(fGlobalTime));
  vec3 lookat = vec3(0., 0., 0.);
  float zoom = 1.;
  vec3 rd = camera(uv, ro, lookat, zoom);

	float d=0.;
  vec4 info = vec4(0.);
  for(int i=0; i<MAX_STEPS; i++) {
  	vec3 p = ro + rd*d;
    float dS = map(p, info);
    d += dS;
    if(d>MAX_DIST || dS<SURF_DIST) break;
  }
    
  if (d < MAX_DIST) {
    vec3 p = ro + rd * d;
    vec3 col = lighting(p, info);
    out_color = vec4(col, 1.0);
  } else {
    out_color = background();
  }
}
