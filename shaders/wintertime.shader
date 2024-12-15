// Constants
const int MAX_MARCHING_STEPS = 255;
const float MIN_DIST = 0.0;
const float MAX_DIST = 100.0;
const float PRECISION = 0.001;
const float EPSILON = 0.0005;
const float PI = 3.14159265359;

// Referenced from Professor's lecture
int xorshift(in int value) {
    // Xorshift*32
    // Based on George Marsaglia's work: http://www.jstatsoft.org/v08/i14/paper
    value ^= value << 13;
    value ^= value >> 17;
    value ^= value << 5;
    return value;
}

int nextInt(inout int seed) {
    seed = xorshift(seed);
    return seed;
}

float nextFloat(inout int seed) {
    seed = xorshift(seed);
    return abs(float(seed) / float(2147483647));
}

struct Surface {
    float sd; // signed distance value
    vec3 col; // color
};

Surface minWithColor(Surface obj1, Surface obj2) {
  if (obj2.sd < obj1.sd) return obj2;
  return obj1;
}

mat2 rotate2d(float theta) {
  float s = sin(theta), c = cos(theta);
  return mat2(c, -s, s, c);
}


Surface opSmoothUnion(Surface obj1, Surface obj2, float k) {
    float h = clamp(0.5 + 0.5 * (obj2.sd - obj1.sd) / k, 0.0, 1.0);
    float sd = mix(obj2.sd, obj1.sd, h) - k * h * (1.0 - h);
    vec3 col = mix(obj2.col, obj1.col, h); 
    return Surface(sd, col);
}


Surface sdPyramid( vec3 p, float h, vec3 col )
{
  float m2 = h*h + 0.25;
    
  p.xz = abs(p.xz);
  p.xz = (p.z>p.x) ? p.zx : p.xz;
  p.xz -= 0.5;

  vec3 q = vec3( p.z, h*p.y - 0.5*p.x, h*p.x + 0.5*p.y);
   
  float s = max(-q.x,0.0);
  float t = clamp( (q.y-0.5*p.z)/(m2+0.25), 0.0, 1.0 );
    
  float a = m2*(q.x+s)*(q.x+s) + q.y*q.y;
  float b = m2*(q.x+0.5*t)*(q.x+0.5*t) + (q.y-m2*t)*(q.y-m2*t);
    
  float d2 = min(q.y,-q.x*m2-q.y*0.5) > 0.0 ? 0.0 : min(a,b);
    
  float sd = sqrt( (d2+q.z*q.z)/m2 ) * sign(max(q.z,-p.y));
  return Surface(sd, col);
}

Surface sdCylinder( vec3 p, float h, float r, vec3 col )
{
  vec2 d = abs(vec2(length(p.xz),p.y)) - vec2(r,h);
  float sd = min(max(d.x,d.y),0.0) + length(max(d,0.0));
  return Surface(sd, col); 
}

// Modified sdSphere
Surface sdFirefly(vec3 p, vec3 offset, float r, vec3 col, float glowStrength) {
    float d = length(p - offset) - r; // Distance to the sphere surface

    // Glowing effect
    vec3 glowColor = vec3(1, 0.984, 0);
    vec3 glow = glowColor * glowStrength / (0.01 + d * d);
    col = mix(col, glow, clamp(1.0 - d / r, 0.0, 1.0)); // Transition from glow to surface color

    return Surface(d, col);
}

Surface sdTree(vec3 p, vec3 position) { 
    // Trunk
    vec3 cylinderPos = vec3(position.x, position.y - 1., position.z);
    Surface cylinder = sdCylinder(p - cylinderPos, 2., .18, vec3(0.651, 0.376, 0.129)); 

    // Foliage
    vec3 pyramidPos1 = vec3(position.x + sin(iTime * 0.8) * 0.115 , position.y - 0.75, position.z);
    Surface pyramid1 = sdPyramid(p - pyramidPos1, 6., vec3(0.188, 0.502, 0.114)); 
    
    vec3 pyramidPos2 = vec3(position.x + sin(iTime * 0.4) * 0.12, position.y + 1., position.z);
    Surface pyramid2 = sdPyramid(p - pyramidPos2, 4., vec3(0.188, 0.502, 0.114)); 

    // Snow Layer
    vec3 snowColor = vec3(0.9, 0.9, 1.0); 
    float snowThickness = 2.5;
    Surface snow1 = sdPyramid(p - pyramidPos1, 3. + snowThickness, snowColor);
    Surface snow2 = sdPyramid(p - pyramidPos2, 2. + snowThickness, snowColor);

  
    Surface foliage1 = opSmoothUnion(pyramid1, snow1, 0.1);
    Surface foliage2 = opSmoothUnion(pyramid2, snow2, 0.1);
    Surface tree = opSmoothUnion(foliage1, cylinder, 0.9);
    tree = opSmoothUnion(tree, foliage2, 0.4);

    return tree; 
}


// Snowy floor
Surface sdFloor(vec3 p) {
  float snowFloor = p.y + 1.75 + texture(iChannel0, p.xz).x * 0.01;
  vec3 snowFloorCol = 0.90 * mix(vec3(1.5), vec3(1), texture(iChannel0, p.xz/100.).x);
  return Surface(snowFloor, snowFloorCol);
}

Surface sdScene(vec3 p) {
    float spacing = 5.2; 
    vec3 floorColor = vec3(0.161, 0.388, 0.106); // Dark green
    Surface co = sdFloor(p);

    int seed = 140; // 145

    // Trees
    for (int x = -1; x <= 2; x++) { 
        for (int z = 0; z <= 2; z++) {
            float randomX = (nextFloat(seed) * 1.4) * 2.0;
            float randomZ = (nextFloat(seed) * 2.3) * 2.0; 
            vec3 position = vec3(float(x) * spacing + randomX, 0, float(z) * spacing + randomZ);
            Surface tree = sdTree(p, position);
            co = minWithColor(co, tree);
        }
    }
    
    // Fireflies
    for (int i = -10; i < -8; i++) {
        vec3 position = vec3(sin(iTime * nextFloat(seed)) * 3.4, cos(iTime * nextFloat(seed)) + 1.5, sin(iTime * nextFloat(seed)) * 3.2);
        Surface firefly = sdFirefly(p, position, 0.1, vec3(1, 1, 0.345), 5.0);
        co = opSmoothUnion(co, firefly, 0.3);
    }
    
    for (int i = 1; i < 7; i++) {
        vec3 position = vec3(3.5 + sin(iTime * nextFloat(seed)) * 3.4, cos(iTime * nextFloat(seed)) + 1.5, 6. + sin(iTime * nextFloat(seed)) * 3.2);
        Surface firefly = sdFirefly(p, position, 0.1, vec3(1, 1, 0.345), 5.0);
        co = opSmoothUnion(co, firefly, 0.3);
    }
    
    return co;
}


Surface rayMarch(vec3 ro, vec3 rd, float start, float end) {
  float depth = start;
  Surface co; 

  for (int i = 0; i < MAX_MARCHING_STEPS; i++) {
    vec3 p = ro + depth * rd;
    co = sdScene(p);
    depth += co.sd;
    if (co.sd < PRECISION || depth > end) break;
  }

  co.sd = depth;

  return co;
}

vec3 calcNormal(in vec3 p) {
    vec2 e = vec2(1, -1) * EPSILON;
    return normalize(
      e.xyy * sdScene(p + e.xyy).sd +
      e.yyx * sdScene(p + e.yyx).sd +
      e.yxy * sdScene(p + e.yxy).sd +
      e.xxx * sdScene(p + e.xxx).sd);
}

mat3 camera(vec3 cameraPos, vec3 lookAtPoint) {
    vec3 cd = normalize(lookAtPoint - cameraPos); // camera direction
    vec3 cr = normalize(cross(vec3(0, 1, 0), cd)); // camera right
    vec3 cu = normalize(cross(cd, cr)); // camera up

    return mat3(-cr, cu, -cd);
}

void mainImage( out vec4 fragColor, in vec2 fragCoord )
{
  vec2 uv = (fragCoord-.5*iResolution.xy)/iResolution.y;
  vec2 mouseUV = iMouse.xy/iResolution.xy; 
  vec3 backgroundColor = vec3(0.094, 0.106, 0.4);

  vec3 col = vec3(0);
  vec3 lp = vec3(3, 1.2, 4.1); // lookat point 
  vec3 ro = vec3(-1, 4, -1); // ray origin 

  float cameraRadius = 2.;
  ro.yz = ro.yz * cameraRadius * rotate2d(mix(PI/2., 0., mouseUV.y));
  ro.xz = ro.xz * rotate2d(mix(-PI, PI, mouseUV.x)) + vec2(lp.x, lp.z);

  vec3 rd = camera(ro, lp) * normalize(vec3(uv, -1)); // ray direction

  Surface co = rayMarch(ro, rd, MIN_DIST, MAX_DIST); // closest object

  if (co.sd > MAX_DIST) {
    col = backgroundColor; // ray didn't hit anything
  } else {
    vec3 p = ro + rd * co.sd; // position along the ray 
    vec3 normal = calcNormal(p);
    vec3 lightPosition = vec3(2, 2, 7);
    vec3 lightDirection = normalize(lightPosition - p);

    float dif = clamp(dot(normal, lightDirection), 0.3, 1.); // diffuse reflection

    vec3 ambientColor = vec3(0.0, 0.20, 0.8) * 0.3;
   
    // final color
    col = dif * co.col * vec3(0.6, 0.7, 1.0) + ambientColor;
  }

  // output to screen
  fragColor = vec4(col, 1.0);
}
