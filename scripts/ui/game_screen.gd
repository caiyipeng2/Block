class_name GameScreen
extends Control

signal paused
signal game_over
var game_state: GameState
@onready var board_view: BoardView = $BoardView
@onready var piece_tray: PieceTray = $PieceTray
@onready var score_label: Label = $HUD/Score
@onready var combo_label: Label = $HUD/Combo

func setup(state: GameState) -> void:
	game_state = state; board_view.setup(state); piece_tray.set_pieces(state.remaining_pieces); _update_hud(); visible = true

func _ready() -> void:
	$HUD/Pause.pressed.connect(func(): paused.emit())

func _update_hud() -> void:
	if game_state == null: return
	score_label.text = "SCORE %06d" % game_state.scoring.score; combo_label.text = "COMBO x%d" % game_state.scoring.combo if game_state.scoring.combo > 0 else "COMBO --"
