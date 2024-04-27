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
const int MAX_DIST = 400;
const float SURF_DIST = 0.01;

const float M_FFT_SCALE = 10.;
const float M_PI = 3.1415926535897932384626433832795;
const float M_2PI = (2 * M_PI);

const int NO_MAT = 0;
const int MAT_ORBEE_TOP = 1;
const int MAT_ORBEE_BOTTOM = 2;
const int MAT_ROAD = 3;
const int MAT_ROAD_LINE = 4;
const int MAT_LANDSCAPE = 5;
const int MAT_TREE = 6;

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

float sdRoundedCylinder( vec3 p, float ra, float rb, float h )
{
  vec2 d = vec2( length(p.xz)-2.0*ra+rb, abs(p.y) - h );
  return min(max(d.x,d.y),0.0) + length(max(d,0.0)) - rb;
}

// Capsule or line
float sdCapsule( vec3 p, vec3 a, vec3 b, float r )
{
  vec3 pa = p - a, ba = b - a;
  float h = clamp( dot(pa,ba)/dot(ba,ba), 0.0, 1.0 );
  return length( pa - ba*h ) - r;
}

// specialization for a vertical vesica segment at the origin
float sdVerticalVesicaSegment( in vec3 p, in float h, in float w )
{
    // shape constants
    h *= 0.5;
    w *= 0.5;
    float d = 0.5*(h*h-w*w)/w;
    
    // project to 2D
    vec2  q = vec2(length(p.xz), abs(p.y-h));
    
    // feature selection (vertex or body)
    vec3  t = (h*q.x < d*(q.y-h)) ? vec3(0.0,h,0.0) : vec3(-d,0.0,d+w);
    
    // distance
    return length(q-t.xy) - t.z;
}

//
// 2D shapes
//

float sdEquilateralTriangle( in vec2 p, in float r )
{
    const float k = sqrt(3.0);
    p.x = abs(p.x) - r;
    p.y = p.y + r/k;
    if( p.x+k*p.y>0.0 ) p = vec2(p.x-k*p.y,-k*p.x-p.y)/2.0;
    p.x -= clamp( p.x, -2.0*r, 0.0 );
    return -length(p)*sign(p.y);
}

//
// Operations
//

float opSmoothUnion( float d1, float d2, float k )
{
    float h = clamp( 0.5 + 0.5*(d2-d1)/k, 0.0, 1.0 );
    return mix( d2, d1, h ) - k*h*(1.0-h);
}

float opSmoothSubtraction( float d1, float d2, float k )
{
    float h = clamp( 0.5 - 0.5*(d2+d1)/k, 0.0, 1.0 );
    return mix( d2, -d1, h ) + k*h*(1.0-h);
}

float opSmoothIntersection( float d1, float d2, float k )
{
    float h = clamp( 0.5 - 0.5*(d2-d1)/k, 0.0, 1.0 );
    return mix( d2, d1, h ) + k*h*(1.0-h);
}

float opExtrusion( in vec3 p, in float d, in float h )
{
    vec2 w = vec2( d, abs(p.z) - h );
    return min(max(w.x,w.y),0.0) + length(max(w,0.0));
}

float opRound( in float d, float rad )
{
    return d - rad;
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
  return vec3(0.1, 0.1, 0.3);
}

float orbee(in vec3 p, out int obj_mat) {
  float d = MAX_DIST;

  vec3 p_top = p;
  p_top.y -= 1.2;
  p_top *= rotateX(M_PI/2);
  float top = sdRoundedCylinder(p_top, .3, .02, .1);
  float top_hole = sdRoundedCylinder(p_top, .15, .1, .3);
  top = opSmoothSubtraction(top_hole, top, .05);

  vec3 p_bottom = p;
  p_bottom.y -= .3;
  p_bottom *= rotateZ(M_PI);
  float bottom = sdEquilateralTriangle(p_bottom.xy, .2);
  bottom = opExtrusion(p_bottom, bottom, .1);
  bottom = opRound(bottom, .02);

  if (top < d) {
    d = top;
    obj_mat = MAT_ORBEE_TOP;
  }
  if (bottom < d) {
    d = bottom;
    obj_mat = MAT_ORBEE_BOTTOM;
  }
  
  return d;
}

float terrain_height(in vec3 p) {
  return 1.5 * sin((abs(p.x) - .21) / 3) + min(.2*abs(p.x), 10.);
}

float terrain(in vec3 p, out int obj_mat) {
  vec3 p_trees = p;
  p_trees.x = -abs(p_trees.x);
  p_trees.y = p.y - terrain_height(p);
  p_trees.z += 2*fGlobalTime;
  p_trees.z += .5*p_trees.x;

  vec2 id_trees = round(p_trees.xz/.8);
  vec2 o_trees = sign(p_trees.xz - .8 * id_trees);
  float trees_d = MAX_DIST;
  for (int j=0; j<2; j++) {
    for (int i=0; i<2; i++) {
      vec2 rid = id_trees + vec2(i, j) * o_trees;
      if (abs(rid.x) < 1) {
        rid.x += o_trees.x;
      }
      vec2 r = p_trees.xz - .8 * rid;
      vec4 tree_diff = texture(texNoise, rid/10.);
      trees_d = min(trees_d, sdVerticalVesicaSegment(vec3(r.x + 2*tree_diff.x, p_trees.y, r.y - 3*tree_diff.z), .7 + 2*tree_diff.y, .5));
    }
  }

  float terrain_d = p.y;
  float road_d = p.y + terrain_height(vec3(.21, 0, 0));

  if (abs(p.x) < .01) {
    if (mod(p.z + 2*fGlobalTime, .3) <= 0.1) {
      obj_mat = MAT_ROAD_LINE;
      terrain_d = road_d;
    } else {
      obj_mat = MAT_ROAD;
      terrain_d = road_d;
    }
  } else if (abs(p.x) < .2) {
    obj_mat = MAT_ROAD;
    terrain_d = road_d;
  } else if (abs(p.x) < .21) {
    obj_mat = MAT_ROAD_LINE;
    terrain_d = road_d;
  } else {
    obj_mat = MAT_LANDSCAPE;
    if (p.x < 3 * M_PI + .21) {
      terrain_d = p.y - terrain_height(p);
    }
  }

  if (trees_d < terrain_d) {
    obj_mat = MAT_TREE;
  }
  float d = min(trees_d, terrain_d);
  return d;
}

float road_deform(in vec3 p) {
  const float d_straight = 20.;
  const float d_curve = 80.;
  const float a_curve = 2. * M_PI;
  const float w_curve = 4.;

  float progress = mod(p.z + 2*fGlobalTime, d_straight + d_curve);
  if (progress < d_straight) {
    return 0.;
  } else {
    return (cos(((progress - d_straight) / d_curve) * a_curve) - 1.) * w_curve;
  }

  return .01 * (smoothstep(.2, .7, sin(fGlobalTime / 10)) - smoothstep(-.2, -.7, sin(fGlobalTime / 10))) * pow(p.z, 2);
}

float map(in vec3 p, out int obj_mat, out vec3 obj_p) {
  float d = MAX_DIST;
  obj_mat = NO_MAT;

  // Create objects here
  p.x += road_deform(p);

  int orbee_mat;
  vec3 p_orbee = p;
  p_orbee *= rotateZ(.1*cos(fGlobalTime));
  p_orbee.y += .01 * (1.04 + sin(fGlobalTime*30));
  p_orbee.x -= .10;
  p_orbee.z -= 8.*round(p_orbee.z/8);
  p_orbee *= rotateY(3*M_PI * smoothstep(9, 10, mod(2*fGlobalTime, 20)));
  p_orbee *= rotateY(-3*M_PI * smoothstep(19, 20, mod(2*fGlobalTime, 20)));
  float orbee_d = orbee(p_orbee, orbee_mat);

  int road_mat;
  float road_d = terrain(p, road_mat);

  if (orbee_d < d) {
    d = orbee_d;
    obj_mat = orbee_mat;
  }
  if (road_d < d) {
    d = road_d;
    obj_mat = road_mat;
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

vec3 lighting(inout vec3 ro, inout vec3 rd, float d, int obj_mat, vec3 obj_p, out vec3 ref) {
  vec3 p = ro + rd * d;

  vec3 light_pos = vec3(5. , 5., -5.);

  vec3 l = normalize(light_pos - p);
  vec3 n = normal(p);
  vec3 r = reflect(rd, n);
  float dif = clamp(dot(l, n), 0., 1.);
  float fresnel = pow(clamp(1.+dot(rd, n), 0., 1.), 5.);

  // Determine object lighting here
  vec3 col = vec3(0);

  if (obj_mat == MAT_ORBEE_TOP) {
    col = vec3(1, 0, 0);
    ref = vec3(mix(.01, .6, fresnel));
  }
  if (obj_mat == MAT_ORBEE_BOTTOM) {
    col = vec3(1, 0, 0);
    ref = vec3(mix(.01, .1, fresnel));
  }
  if (obj_mat == MAT_ROAD) {
    col = vec3(0, 0, 0);
    ref = vec3(0);
  }
  if (obj_mat == MAT_ROAD_LINE) {
    col = vec3(1, 1, 1);
    ref = vec3(mix(.01, .7, fresnel));
  }
  if (obj_mat == MAT_LANDSCAPE) {
    vec2 noise_p = p.xz;
    noise_p.x += road_deform(p);
    noise_p.y += 2*fGlobalTime;
    vec4 noise = texture(texNoise, noise_p);
    col = vec3(0, 1-noise.y, 0);
    ref = vec3(0);
  }
  if (obj_mat == MAT_TREE) {
    vec2 noise_p = p.xz;
    noise_p.x += road_deform(p);
    noise_p.y += 2*fGlobalTime;
    vec4 noise = texture(texNoise, noise_p);
    col = vec3(.1, .3, 0) - .5*noise.zxz;
    ref = vec3(mix(.01, .3, fresnel));
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

vec3 render(inout vec3 ro, inout vec3 rd, inout vec3 ref, out bool no_obj) {
  int obj_mat = NO_MAT;
  vec3 obj_p = vec3(0.);
	float d = raymarch(ro, rd, obj_mat, obj_p);
  ref *= 0.;
    
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
  vec3 ro = vec3(0.1, 3., -4.);
  vec3 lookat = vec3(0.1, 0., 4.);
  float movement = mod(fGlobalTime, 12) / 8.;
  if (movement <= 1.) {
    // movement 0. - 1.
    float z_offset = 8. * (.5 + .5 * sin(movement * M_PI - .5*M_PI));
    ro.z += z_offset;
    ro.y -= 1.7 * sin(movement * M_PI);
    lookat.z += z_offset;
  } else {
    // movement 1. - 1.5
    movement -= 1.;
    movement *= 2.;
    movement += 1.;

    float z_offset = 8. * (.5 + .5 * sin(movement * M_PI - .5*M_PI));
    ro.z += z_offset;
    ro.y += 1.7 * sin((movement - 1.) * M_PI);
    lookat.z += z_offset;
  }
  ro.x -= road_deform(ro);
  lookat.x -= road_deform(lookat);

  float zoom = 1.;
  vec3 rd = camera(uv, ro, lookat, zoom);

  vec3 col = vec3(0.);
  vec3 ref = vec3(0.);
  vec3 fil = vec3(1.);
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
