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

vec4 plas( vec2 v, float time )
{
	float c = 0.5 + sin( v.x * 10.0 ) + cos( sin( time + v.y ) * 20.0 );
	return vec4( sin(c * 0.2 + cos(time)), c * 0.15, cos( c * 0.1 + time / .4 ) * .25, 1.0 );
}

float dot2( in vec2 v ) { return dot(v,v); }
float dot2( in vec3 v ) { return dot(v,v); }
float ndot( in vec2 a, in vec2 b ) { return a.x*b.x - a.y*b.y; }

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

float tile(vec3 p)
{
  return sdRoundBox(p-vec3(2., 0., 4.), vec3(0.01, .3, .3), 0.01);
}

float tiles(vec3 p, int n)
{
  float sp = 6.283185/float(n);
  float an = atan(p.y,p.x);
  float id = floor(an/sp);

  float a1 = sp*(id+0.0);
  float a2 = sp*(id+1.0);
  vec2 r1 = mat2(cos(a1),-sin(a1),sin(a1),cos(a1))*p.xy;
  vec2 r2 = mat2(cos(a2),-sin(a2),sin(a2),cos(a2))*p.xy;

  float z = p.z;
  
  return min( tile(vec3(r1, z)), tile(vec3(r2, z)) );
}

float GetDist(vec3 p) {  
  
  return tiles(p, 12);
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


float GetLight(vec3 p) {
  vec3 lightPos = vec3(0, 5, 0);
  //lightPos.xz += vec2(sin(fGlobalTime), cos(fGlobalTime))*2.;
  vec3 l = normalize(lightPos-p);
  vec3 n = GetNormal(p);
    
    
  // Cast shades
  float dif = clamp(dot(n, l), 0., 1.);
  //float d = RayMarch(p+n*SURF_DIST*2., l);
  //if(d<length(lightPos-p)) dif *= .1;
    
  return dif;
}

vec4 background(void)
{
	vec2 p = (2.0*gl_FragCoord.xy-v2Resolution.xy)/v2Resolution.y;

  // Middle
  float m1 = sdEquilateralTriangle(p - vec2(0., -1.), 1.4);
  
  // Left
  float ml1 = sdEquilateralTriangle(p - vec2(-.5, -1.), 1.);
  float ml3 = sdEquilateralTriangle(p - vec2(-1.1, -1.2), 1.);
  
  // Right
  float mr1 = sdEquilateralTriangle(p - vec2(.4, -.8), 1.);
  float mr2 = sdEquilateralTriangle(p - vec2(1., -1.05), 1.);
  float mr3 = sdEquilateralTriangle(p - vec2(1.4, -.8), 1.);
  
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
  vec3 col = vec3(0);
  vec3 ro = vec3(0, 0, 0);
  vec3 rd = normalize(vec3(uv.x, uv.y, 1));

  vec4 background_color = background();
  
  float d = RayMarch(ro, rd);
    
  if (d < MAX_DIST) {
    vec3 p = ro + rd * d;
    
    float dif = GetLight(p);
    col = vec3(dif);
    col = mix(col, background_color.xyz, 0.1);
    
    col = pow(col, vec3(.4545));	// gamma correction
    
    out_color = vec4(col,1.0);
  }
  else
  {
    out_color = background_color;
  }
}


