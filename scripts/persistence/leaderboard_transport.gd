extends Node

signal completed(id: int, status: int, body: Dictionary, error: String)
var _sequence := 0

func send(url: String, method: int, headers: PackedStringArray, body: String) -> int:
	_sequence += 1
	var id := _sequence
	if not url.begins_with("https://"):
		completed.emit.call_deferred(id, 0, {}, "invalid_endpoint")
		return id
	var request := HTTPRequest.new()
	request.timeout = 12.0
	request.body_size_limit = 2 * 1024 * 1024
	request.max_redirects = 0
	add_child(request)
	request.request_completed.connect(func(result: int, status: int, _headers: PackedStringArray, bytes: PackedByteArray):
		request.queue_free()
		if result != HTTPRequest.RESULT_SUCCESS:
			completed.emit(id, 0, {}, "network")
			return
		var decoded: Variant = JSON.parse_string(bytes.get_string_from_utf8())
		if not decoded is Dictionary:
			completed.emit(id, status, {}, "invalid_response")
			return
		completed.emit(id, status, decoded, ""))
	var error := request.request(url, headers, method, body)
	if error != OK:
		request.queue_free()
		completed.emit.call_deferred(id, 0, {}, "network")
	return id
