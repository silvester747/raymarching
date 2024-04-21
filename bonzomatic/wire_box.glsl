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

const int NO_MAT = 0;
const int MAT_BALL = 1;
const int MAT_FRAME = 2;
const int MAT_WIRES = 3;
const int MAT_ELECTRON_RED = 4;
const int MAT_ELECTRON_GREEN = 5;
const int MAT_ELECTRON_BLUE = 6;

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

float sdBoxFrame( vec3 p, vec3 b, float e )
{
  p = abs(p)-b;
  vec3 q = abs(p+e)-e;
  return min(min(
      length(max(vec3(p.x,q.y,q.z),0.0))+min(max(p.x,max(q.y,q.z)),0.0),
      length(max(vec3(q.x,p.y,q.z),0.0))+min(max(q.x,max(p.y,q.z)),0.0)),
      length(max(vec3(q.x,q.y,p.z),0.0))+min(max(q.x,max(q.y,p.z)),0.0));
}

// Capsule or line
float sdCapsule( vec3 p, vec3 a, vec3 b, float r )
{
  vec3 pa = p - a, ba = b - a;
  float h = clamp( dot(pa,ba)/dot(ba,ba), 0.0, 1.0 );
  return length( pa - ba*h ) - r;
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
vec3 background(void) {
  vec2 uv = gl_FragCoord.xy/v2Resolution.xy;
  return vec3(uv.xy, uv.y);
}

float map(in vec3 p, out int obj_mat, out vec3 obj_p) {
  float d = MAX_DIST;
  obj_mat = NO_MAT;

  // Frame width 0. causes only a thin line
  // Subtracting .05 makes lines round with a radius
  float box = sdBoxFrame(p, vec3(1, 1, 1), 0.) - .03;

  float sphere = sdSphere(p, .3);

  float electron_red = sdSphere(p - vec3(.8 * sin(fGlobalTime * 3.), .8 * sin(fGlobalTime * 3.), .8 * cos(fGlobalTime * 3.)), .15);
  float electron_green = sdSphere(p - vec3(.8 * sin(fGlobalTime * 3. + M_PI - .2), .8 * sin(fGlobalTime * 3. + .5 * M_PI), .8 * cos(fGlobalTime * 3. + M_PI - .2)), .15);
  float electron_blue = sdSphere(p - vec3(.8 * sin(fGlobalTime * 3. + .6), .8 * -sin(fGlobalTime * 3.), .8 * cos(fGlobalTime * 3. + .6)), .15);

  // Mirror the following SDF around all axes
  p.xyz = abs(p.xyz);

  float lines = sdCapsule(p, vec3(-1.), vec3(1.), .0001);

  if (box < d) {
    d = box;
    obj_mat = MAT_FRAME;
  } 
  if (sphere < d) {
    d = sphere;
    obj_mat = MAT_BALL;
  } 
  if (lines < d) {
    d = lines;
    obj_mat = MAT_WIRES;
  }
  if (electron_red < d) {
    d = electron_red;
    obj_mat = MAT_ELECTRON_RED;
  }
  if (electron_green < d) {
    d = electron_green;
    obj_mat = MAT_ELECTRON_GREEN;
  }
  if (electron_blue < d) {
    d = electron_blue;
    obj_mat = MAT_ELECTRON_BLUE;
  }
  return d;
}

vec3 normal(vec3 p) {
  int obj_mat = NO_MAT;
  vec3 obj_p = vec3(0.);
	float d = map(p, obj_mat, obj_p);
  vec2 e = vec2(.01, 0);
    
  vec3 n = d - vec3(
      map(p-e.xyy, obj_mat, obj_p),
      map(p-e.yxy, obj_mat, obj_p),
      map(p-e.yyx, obj_mat, obj_p));
    
  return normalize(n);
}

vec3 lighting(inout vec3 ro, inout vec3 rd, float d, int obj_mat, vec3 obj_p, out float ref) {
  vec3 p = ro + rd * d;

  vec3 light_pos = vec3(5. , 5., -5.);
  vec3 l = normalize(light_pos - p);
  vec3 n = normal(p);
  vec3 r = reflect(rd, n);
  float dif = clamp(dot(l, n), 0., 1.);

  vec3 col = vec3(0);
  if (obj_mat == MAT_BALL) {
    col = vec3(0.3);
    ref = .2 + .7 * abs(sin(fGlobalTime / 10));
  } else if (obj_mat == MAT_FRAME) {
    col = vec3(.9, .9, .9);
    ref = .1;
  } else if (obj_mat == MAT_WIRES) {
    ref = .9;
    col = vec3(0.1);
  } else if (obj_mat == MAT_ELECTRON_RED) {
    ref = .01;
    col = vec3(1, 0, 0);
  } else if (obj_mat == MAT_ELECTRON_GREEN) {
    ref = .01;
    col = vec3(0, 1, 0);
  } else if (obj_mat == MAT_ELECTRON_BLUE) {
    ref = .01;
    col = vec3(0, 0, 1);
  }
  col = col * dif;

  ro = p + n * SURF_DIST * 3.;
  rd = r;

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

float raymarch(vec3 ro, vec3 rd, out int obj_mat, out vec3 obj_p) {
	float d=0.;
  for(int i=0; i<MAX_STEPS; i++) {
  	vec3 p = ro + rd*d;
    float dS = map(p, obj_mat, obj_p);
    d += dS;
    if(d>MAX_DIST || dS<SURF_DIST) break;
  }
  return d;
}

vec3 render(inout vec3 ro, inout vec3 rd, inout float ref, out bool no_obj) {
  int obj_mat = NO_MAT;
  vec3 obj_p = vec3(0.);
	float d = raymarch(ro, rd, obj_mat, obj_p);
    
  if (d < MAX_DIST) {
    no_obj = false;
    return lighting(ro, rd, d, obj_mat, obj_p, ref);
  } else {
    no_obj = true;
    return background();
  }
}

vec3 render(vec2 pix_coord) {
  vec2 uv = (gl_FragCoord.xy-.5*v2Resolution.xy)/v2Resolution.y;
  vec3 ro = vec3(5. * sin(fGlobalTime) , 2. + sin(fGlobalTime / 4.), 5. * cos(fGlobalTime));
  vec3 lookat = vec3(0., 0., 0.);
  float zoom = 1.;
  vec3 rd = camera(uv, ro, lookat, zoom);

  vec3 col = vec3(0.);
  float ref = 0.;
  float fil = 1.;
  const int NUM_BOUNCES = 2;
  for (int i = 0; i < NUM_BOUNCES; i++) {
    bool no_obj;
    vec3 pass = render(ro, rd, ref, no_obj);
    if (no_obj && i > 0) break;
    col += pass * fil;
    fil *= ref;

  }
  return col;
}

void main(void)
{
  vec3 col = render(gl_FragCoord.xy);
  col = pow(col, vec3(.4545));	// gamma correction
  out_color = vec4(col, 1.);
}
