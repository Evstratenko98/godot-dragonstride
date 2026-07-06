extends CanvasLayer

# Notifies `Main` node that the button has been pressed
signal end_game


func _on_end_game_button_pressed() -> void:
	end_game.emit()
