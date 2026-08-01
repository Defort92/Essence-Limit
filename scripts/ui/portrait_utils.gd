class_name PortraitUtils
extends RefCounted

## Character sprites are full-body 128x128 images. HUD cards use a centered
## square from the upper part of the source so only the head and shoulders are
## enlarged inside the portrait frame.
const FACE_CROP_SIZE_RATIO := 0.34
const FACE_CROP_TOP_RATIO := 0.005


static func make_face_texture(source: Texture2D) -> Texture2D:
	if source == null:
		return null
	var source_size := source.get_size()
	var crop_size := minf(source_size.x, source_size.y) * FACE_CROP_SIZE_RATIO
	var cropped := AtlasTexture.new()
	cropped.atlas = source
	cropped.region = Rect2(
		(source_size.x - crop_size) * 0.5,
		source_size.y * FACE_CROP_TOP_RATIO,
		crop_size,
		crop_size
	)
	cropped.filter_clip = true
	return cropped
