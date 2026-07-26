# Third-party assets

## Dylearn grass

- File: `res://assets/textures/environment/grass_dylearn.png`
- File: `res://assets/textures/environment/dylearn/accentleaf.png`
- Noise resources: `res://assets/textures/environment/dylearn/`
- Shader sources: `res://assets/shaders/dylearn/`
- Helper scripts: `res://scripts/effects/dylearn/`
- Original creator: Dylearn
- Original project: [Dylearn 3D Pixel Art Grass Demo](https://github.com/DylearnDev/Dylearn-3D-Pixel-Art-Grass-Demo)
- License: [Creative Commons Attribution 4.0](https://creativecommons.org/licenses/by/4.0/)
- Art changes: the original grass and accent textures are used unchanged.

The shader and helper-script code is MIT-licensed. Paths were adapted to the
Essence Limit directory structure, grass interaction was limited to eight nearby
interactors, and the toon shader received a white fallback for materials without
an albedo texture. MultiMesh placement and spatial exclusions use Essence
Limit's own `grass_multimesh_chunk.gd` implementation.

The transferred screen-space outline shader is kept as a reusable resource but
is not applied to the prototype's simple box proxies: Dylearn's original scene
uses it as a next pass on its detailed model material, while on a box it covers
most faces instead of producing a useful silhouette.
