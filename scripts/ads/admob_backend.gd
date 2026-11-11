extends RefCounted

## Thin Android wrapper around Poing Studios AdMob v5.1.0 (Next-Gen SDK + UMP).
## Never instantiated on desktop or in headless tests.

signal initialized(ok: bool)
signal ad_ready(ready: bool)
signal ad_load_failed
signal ad_started
signal ad_ended(shown: bool)
signal privacy_requirement_changed(required: bool)

const RETRY_SECONDS := 30.0

var _owner: Node
var _unit_id := ""
var _use_test_ads := true
var _interstitial: InterstitialAd
var _loader: InterstitialAdLoader
var _loading := false
var _ready := false
var _privacy_required := false
var _closed := false
var _retry_timer: SceneTreeTimer

func configure(owner: Node, unit_id: String, use_test_ads: bool, debug_geography: String) -> void:
	_owner = owner
	_unit_id = unit_id
	_use_test_ads = use_test_ads
	_request_consent(debug_geography)

func is_ad_ready() -> bool:
	return _interstitial != null

func preload_ad() -> void:
	if _closed or not _ready or _loading or _interstitial != null:
		return
	_loading = true
	_loader = InterstitialAdLoader.new()
	var callback := InterstitialAdLoadCallback.new()
	callback.on_ad_loaded = func(ad: InterstitialAd) -> void:
		_loading = false
		_interstitial = ad
		_configure_interstitial_callbacks()
		ad_ready.emit(true)
	callback.on_ad_failed_to_load = func(error: LoadAdError) -> void:
		_loading = false
		_loader = null
		push_warning("AdMob interstitial failed to load: " + (error.message if error != null else "unknown"))
		ad_load_failed.emit()
		_schedule_preload()
	_loader.load(_unit_id, AdRequest.new(), callback)

func show_interstitial() -> void:
	if _interstitial == null:
		ad_load_failed.emit()
		return
	_interstitial.show()

func show_privacy_options(callback: Callable) -> void:
	if not _ready:
		if callback.is_valid():
			callback.call_deferred()
		return
	UserMessagingPlatform.show_privacy_options_form(func(_error: FormError) -> void:
		_update_privacy_requirement()
		if callback.is_valid():
			callback.call_deferred())

func close() -> void:
	_closed = true
	_destroy_interstitial()
	if _retry_timer != null and _retry_timer.timeout.is_connected(_retry_preload):
		_retry_timer.timeout.disconnect(_retry_preload)
	_retry_timer = null

func _request_consent(debug_geography: String) -> void:
	var parameters := ConsentRequestParameters.new()
	parameters.tag_for_under_age_of_consent = false
	if _use_test_ads and debug_geography == "EEA":
		var debug_settings := ConsentDebugSettings.new()
		debug_settings.debug_geography = DebugGeography.Values.EEA
		parameters.consent_debug_settings = debug_settings
	UserMessagingPlatform.consent_information.update(
		parameters,
		_on_consent_info_updated,
		_on_consent_info_failed
	)

func _on_consent_info_updated() -> void:
	if UserMessagingPlatform.consent_information.get_is_consent_form_available():
		UserMessagingPlatform.load_consent_form(_on_consent_form_loaded, _on_consent_form_failed)
	else:
		_initialize_mobile_ads()

func _on_consent_info_failed(_error: FormError) -> void:
	_initialize_mobile_ads()

func _on_consent_form_loaded(form: ConsentForm) -> void:
	form.show(_on_consent_form_dismissed)

func _on_consent_form_failed(_error: FormError) -> void:
	_initialize_mobile_ads()

func _on_consent_form_dismissed(_error: FormError) -> void:
	_initialize_mobile_ads()

func _initialize_mobile_ads() -> void:
	var configuration := RequestConfiguration.new()
	configuration.max_ad_content_rating = RequestConfiguration.MAX_AD_CONTENT_RATING_G
	configuration.tag_for_child_directed_treatment = RequestConfiguration.TagForChildDirectedTreatment.FALSE
	configuration.tag_for_under_age_of_consent = RequestConfiguration.TagForUnderAgeOfConsent.FALSE
	MobileAds.set_request_configuration(configuration)
	var listener := OnInitializationCompleteListener.new()
	listener.on_initialization_complete = func(_status: InitializationStatus) -> void:
		_ready = true
		_update_privacy_requirement()
		initialized.emit(true)
		preload_ad()
	MobileAds.initialize(listener)

func _configure_interstitial_callbacks() -> void:
	if _interstitial == null:
		return
	var callbacks := FullScreenContentCallback.new()
	callbacks.on_ad_showed_full_screen_content = func() -> void:
		ad_started.emit()
	callbacks.on_ad_dismissed_full_screen_content = func() -> void:
		_destroy_interstitial()
		ad_ended.emit(true)
		_schedule_preload()
	callbacks.on_ad_failed_to_show_full_screen_content = func(_error: AdError) -> void:
		_destroy_interstitial()
		ad_ended.emit(false)
		_schedule_preload()
	_interstitial.full_screen_content_callback = callbacks

func _destroy_interstitial() -> void:
	if _interstitial != null:
		_interstitial.destroy()
	_interstitial = null

func _schedule_preload() -> void:
	if _closed or _owner == null or _owner.get_tree() == null:
		return
	_retry_timer = _owner.get_tree().create_timer(RETRY_SECONDS)
	_retry_timer.timeout.connect(_retry_preload)

func _retry_preload() -> void:
	_retry_timer = null
	preload_ad()

func _update_privacy_requirement() -> void:
	# ConsentInformation.PrivacyOptionsRequirementStatus.REQUIRED == 2.
	var required: bool = UserMessagingPlatform.consent_information.get_privacy_options_requirement_status() == 2
	if required != _privacy_required:
		_privacy_required = required
		privacy_requirement_changed.emit(required)
