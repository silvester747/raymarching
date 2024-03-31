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

#define MAX_STEPS 100
#define MAX_DIST 100.
#define SURF_DIST 0.01
#define M_PI 3.1415926535897932384626433832795
#define M_2PI (2 * M_PI)
#define FFT_FACTOR 30.
#define NUM_TILES 12

vec4 plas( vec2 v, float time )
{
	float c = 0.5 + sin( v.x * 10.0 ) + cos( sin( time + v.y ) * 20.0 );
	return vec4( sin(c * 0.2 + cos(time)), c * 0.15, cos( c * 0.1 + time / .4 ) * .25, 1.0 );
}

float dot2( in vec2 v ) { return dot(v,v); }
float dot2( in vec3 v ) { return dot(v,v); }
float ndot( in vec2 a, in vec2 b ) { return a.x*b.x - a.y*b.y; }

float fft(in float freq)
{
  return FFT_FACTOR * texture(texFFTSmoothed, freq).x;
}

float sdCircle( in vec2 p, in float r ) 
{
    return length(p)-r;
}

float sdEquilateralTriangle( in vec2 p, in float r )
{
    const float k = sqrt(3.0);
    p.x = abs(p.x) - r;
    p.y = p.y + r/k;
    if( p.x+k*p.y>0.0 ) p = vec2(p.x-k*p.y,-k*p.x-p.y)/2.0;
    p.x -= clamp( p.x, -2.0*r, 0.0 );
    return -length(p)*sign(p.y);
}

float sdSphere( vec3 p, float s )
{
  return length(p)-s;
}

float sdRoundBox( vec3 p, vec3 b, float r )
{
  vec3 q = abs(p) - b + r;
  return length(max(q,0.0)) + min(max(q.x,max(q.y,q.z)),0.0) - r;
}

float opSmoothUnion( float d1, float d2, float k )
{
    float h = clamp( 0.5 + 0.5*(d2-d1)/k, 0.0, 1.0 );
    return mix( d2, d1, h ) - k*h*(1.0-h);
}

float opUnion( float d1, float d2 )
{
    return min(d1,d2);
}
float opSubtraction( float d1, float d2 )
{
    return max(-d1,d2);
}
float opIntersection( float d1, float d2 )
{
    return max(d1,d2);
}
float opXor(float d1, float d2 )
{
    return max(min(d1,d2),-max(d1,d2));
}

float opExtrusion( in vec3 p, in float sdf, in float h )
{
    vec2 w = vec2( sdf, abs(p.z) - h );
    return min(max(w.x,w.y),0.0) + length(max(w,0.0));
}

float opOnion( in float sdf, in float r )
{
  return abs(sdf) - r;
}

float tile(vec3 p, int id)
{
  float fft_factor = 0.;
  if (mod(id, 3.) == 0.) {
    fft_factor = fft(0.1);
  } else if (mod(id, 3) == 1.) {
    fft_factor = fft(0.4);
  } else {
    fft_factor = fft(0.7);
  }
  return sdRoundBox(p-vec3(2. + 0.4 * fft_factor, 0., 5.), vec3(0.01, .3, .5), 0.01);
}

float tiles(vec3 p, int n)
{
  float sp = M_2PI/float(n);
  float an = atan(p.y,p.x);
  float id = floor(an/sp);

  float a1 = sp*(id+0.0) + mod(fGlobalTime, sp) - sp/2;
  float a2 = sp*(id+1.0) + mod(fGlobalTime, sp) - sp/2;
  vec2 r1 = mat2(cos(a1),-sin(a1),sin(a1),cos(a1))*p.xy;
  vec2 r2 = mat2(cos(a2),-sin(a2),sin(a2),cos(a2))*p.xy;

  int fixed_id = int(floor((an - mod(fGlobalTime, M_2PI))/sp) + float(n)/2);
  
  float z = p.z;
  
  return min( tile(vec3(r1, z), fixed_id), tile(vec3(r2, z), fixed_id) );
}

float snowman(in vec3 p, in float size) {
  float s1 = sdSphere(p - vec3(0., 0., 0.), .4);
  float s2 = sdSphere(p - vec3(0., .5, 0.), .3);
  float s3 = sdSphere(p - vec3(0., 0.9, 0.), .2);
  float s = opSmoothUnion(s1, s2, 0.08);
  return opSmoothUnion(s, s3, 0.08);
}

float GetDist(vec3 p) {  
  float d_tiles = tiles(p, NUM_TILES);
  
  float jump = smoothstep(.1, .9, mod(fGlobalTime, 2.) / 2.) * M_PI;
  float jump_w = cos(jump);
  float jump_h = .2 * sin(jump) + .2;
  
  //float wiggle_a = .2 * sin(fGlobalTime * 2) + .2;
  //mat3 wiggle = mat3(
  //  1., 0., 0.,
  //  0., cos(wiggle_a), -sin(wiggle_a),
  //  0., sin(wiggle_a), cos(wiggle_a)
  //);
  
  //float d_s1 = snowman(
  //  (p - vec3(0., -.6, 5.)) * wiggle
  //  + vec3(-.8 * jump_w * sin(fGlobalTime, 0., -.8 * jump_w * cos(fGlobalTime))
  //  + vec3(0., jump_h, 0.)
  //  + vec3(0., fft(0.2), 0.)
  //  ,
  //  1.);
  
  float d_s1 = snowman(p - vec3(-.8 * jump_w * sin(fGlobalTime), fft(0.2) - .6 + jump_h, 5. - .8 * jump_w * cos(fGlobalTime)), 1.);
  float d_s2 = snowman(p - vec3(.8 * jump_w * sin(fGlobalTime), fft(0.3) - .6 + jump_h, 5. + .8 * jump_w * cos(fGlobalTime)), 1.);
  
  float d = min(d_tiles, d_s1);
  d = min(d, d_s2);
  
  return d;
}

float RayMarch(vec3 ro, vec3 rd) {
	float dO=0.;
    
  for(int i=0; i<MAX_STEPS; i++) {
  	vec3 p = ro + rd*dO;
    float dS = GetDist(p);
    dO += dS;
    if(dO>MAX_DIST || dS<SURF_DIST) break;
  }
    
  return dO;
}

vec3 GetNormal(vec3 p) {
	float d = GetDist(p);
  vec2 e = vec2(.01, 0);
    
  vec3 n = d - vec3(
      GetDist(p-e.xyy),
      GetDist(p-e.yxy),
      GetDist(p-e.yyx));
    
  return normalize(n);
}


vec4 GetLight(vec3 p, vec4 background_color) {
  float sp = M_2PI/float(NUM_TILES);
  float an = atan(p.y,p.x);
  int id = int(floor((an - mod(fGlobalTime, M_2PI))/sp));
  float soft_id = (an - mod(fGlobalTime, M_2PI))/sp;
  
  vec3 light_pos = vec3(0., 0., 3.);
  vec3 l = normalize(light_pos - p);
  vec3 n = GetNormal(p);
  float dif = clamp(dot(l, n), 0., 1.);

  vec3 col = vec3(0.);
  vec3 col1 = vec3(1., 0.2, 0.1) * smoothstep(.15, .6, fft(0.1)) * dif;
  vec3 col2 = vec3(.1, 1., .1) * smoothstep(.05, .6, fft(.4)) * dif;
  vec3 col3 = vec3(.1, .1, 1.) * smoothstep(.0, .3, fft(.5)) * dif;

  if (length(p.xy) > 1.95) {
    // Tiles
    if (mod(id, 3) == 0) {
      col = col1;
    } else if (mod(id, 3) == 1) {
      col = col2;
    } else {
      col = col3;
    }
    
    // Transparency
    col = mix(col, background_color.xyz, 0.3);
    if (length(col) < .3) {
      // Glass look
      col = mix(col, vec3(.8, .898, 1.), .1);
    }
  } else {
    // Internal objects
    float mod_soft_id = mod(soft_id - .5, 3.);
    if (mod_soft_id > 0. && mod_soft_id <= 1.) {
      col = mix(col1, col2, smoothstep(0.25, 0.75, mod_soft_id));
    } else if (mod_soft_id > 1. && mod_soft_id <= 2.) {
      col = mix(col2, col3, smoothstep(1.25, 1.75, mod_soft_id));
    } else {
      col = mix(col3, col1, smoothstep(2.25, 2.75, mod_soft_id));
    }
    col = mix(col, vec3(1.), .1);
  }
  
  col = pow(col, vec3(.4545));	// gamma correction

  return vec4(col, 1.);
}

vec4 background(void)
{
	vec2 p = (2.0*gl_FragCoord.xy-v2Resolution.xy)/v2Resolution.y;

  // Middle
  float m1 = sdEquilateralTriangle(p - vec2(0., -1.2), 1.4 + fft(0.25));
  
  // Left
  float ml1 = sdEquilateralTriangle(p - vec2(-.5, -1.2), 1. + .75 * fft(0.75));
  float ml3 = sdEquilateralTriangle(p - vec2(-1.1, -1.4), 1. - fft(0.20));
  
  // Right
  float mr1 = sdEquilateralTriangle(p - vec2(.4, -.9), 1. + .75 * fft(0.50));
  float mr2 = sdEquilateralTriangle(p - vec2(1., -1.05), 1. - 0.25 * fft(0.60));
  float mr3 = sdEquilateralTriangle(p - vec2(1.4, -.8), 1. + 0.6 * fft(0.4));
  
  float d = opSmoothUnion(m1, ml1, .1);
  d = opSmoothUnion(d, mr1, .1);
  d = opSmoothUnion(d, mr2, .1);  
  d = opSmoothUnion(d, ml3, .1);  
  d = opSmoothUnion(d, mr3, .1);  
  
	// coloring
  vec3 outside_color = vec3(0.9, 1., 1.);
  vec3 inside_color = vec3(0.65, 0.85, 1.);
  vec3 col = (d>0.0) ? inside_color : outside_color;
  col *= 1.0 - exp(-6.0*abs(d));
	col *= 0.8 + 0.2*cos(150.0*d);
	col = mix( col, vec3(1.0), 1.0-smoothstep(0.0,0.05,abs(d)) );

	return vec4(col,1.0);
}

void main(void)
{
  vec2 uv = (gl_FragCoord.xy-.5*v2Resolution.xy)/v2Resolution.y;
  vec3 ro = vec3(0, 0, 0);
  vec3 rd = normalize(vec3(uv.x, uv.y, 1));

  vec4 background_color = background();
  
  float d = RayMarch(ro, rd);
    
  if (d < MAX_DIST) {
    vec3 p = ro + rd * d;   
    out_color = GetLight(p, background_color);
  }
  else
  {
    out_color = background_color;
  }
}


