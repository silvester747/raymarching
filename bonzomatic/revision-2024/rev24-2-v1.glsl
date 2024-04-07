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

const float M_FFT_SCALE = 10.;
const float M_PI = 3.1415926535897932384626433832795;
const float M_2PI = (2 * M_PI);

//
// Shape functions
//
float sdSegment( in vec2 p, in vec2 a, in vec2 b )
{
    vec2 pa = p-a, ba = b-a;
    float h = clamp( dot(pa,ba)/dot(ba,ba), 0.0, 1.0 );
    return length( pa - ba*h );
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
	vec2 p = (2.0*gl_FragCoord.xy-v2Resolution.xy)/v2Resolution.y;
  vec3 col = vec3(0.0);

  float bass = fft(0.2);
  float minX = -2. - bass;
  float maxX = 2. + bass;
  float d = sdSegment(p, vec2(minX, 0.0), vec2(maxX, 0.0));

  if (minX < p.x && p.x < maxX) {
    float scaledTime = fGlobalTime * 0.2;
    float modTime = scaledTime - floor(scaledTime);

    float len = maxX - minX;
    float freq = ((p.x - minX) / len) * 0.8;
    freq = freq + modTime;
    float freqI = ((maxX - p.x) / len) * 0.8;
    freqI = freqI + modTime;
    float ampl = max(fft(freq), fft(1. - freq));
    ampl = max(ampl, max(fft(freqI), fft(1. - freqI)));

    vec3 colLow = vec3(0.0, 0.6, 0.0);
    vec3 colMid = vec3(1.0, 0.5, 0.0);
    vec3 colHigh = vec3(0.8, 0.0, 0.0);

    if (abs(p.y) < 0.3) {
      col = mix(colLow, colMid, smoothstep(0.05, 0.23, abs(p.y)));
    } else {
      col = mix(colMid, colHigh, smoothstep(0.27, 0.43, abs(p.y)));
    }

    col = mix(col, col * .05, smoothstep(0.0, 0.00 + 0.2 * ampl, d));

    vec3 previousCol = texture(texPreviousFrame, gl_FragCoord.xy - vec2(0, .8 * fFrameTime * sign(p.y)) / v2Resolution.xy).xyz;
    col = mix(col, previousCol, 0.1);
  }


	return vec4(col, 1.);
}

void main(void) {
  out_color = background();
}
