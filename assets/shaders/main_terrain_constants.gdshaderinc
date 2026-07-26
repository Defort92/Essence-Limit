// Фиксированные коэффициенты процедурного смешивания текстур земли.
// Настраиваемые параметры материала остаются uniform в main_terrain.gdshader.

const vec2 TERRAIN_HASH_VECTOR = vec2(127.1, 311.7);
const float TERRAIN_HASH_SCALE = 43758.5453123;

const float SOIL_MIX_NOISE_SCALE = 0.16;
const vec2 SOIL_SECOND_TEXTURE_OFFSET = vec2(0.37, 0.19);
const float SOIL_BLEND_START = 0.38;
const float SOIL_BLEND_END = 0.68;

const float GRASS_SECOND_TEXTURE_SCALE = 0.93;
const vec2 GRASS_SECOND_TEXTURE_OFFSET = vec2(0.41, 0.23);
const float GRASS_MIX_NOISE_SCALE = 0.11;
const vec2 GRASS_MIX_NOISE_OFFSET = vec2(17.0, 9.0);
const float GRASS_BLEND_START = 0.28;
const float GRASS_BLEND_END = 0.72;

const float GRASS_PATCH_02_BLEND_STRENGTH = 0.72;
const float GRASS_PATCH_03_BLEND_STRENGTH = 0.78;
const float GRASS_COVERAGE_BLEND_START = 0.08;
const float GRASS_COVERAGE_BLEND_END = 0.92;
