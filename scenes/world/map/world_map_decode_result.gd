class_name WorldMapDecodeResult
extends RefCounted

var document: WorldMapDocument = null
var error_code: String = ""


static func success(decoded_document: WorldMapDocument) -> WorldMapDecodeResult:
	var result: WorldMapDecodeResult = WorldMapDecodeResult.new()
	result.document = decoded_document
	return result


static func failure(reason_code: String) -> WorldMapDecodeResult:
	var result: WorldMapDecodeResult = WorldMapDecodeResult.new()
	result.error_code = reason_code
	return result
