# GameManager.gd
extends Node

# リトライ回数を保持する変数（シーンを跨いでもリセットされない）
var retry_count: int = 0
var floors_number: int = 0

# 確認用
func _ready() -> void:
    print("GameManagerが正常に読み込まれました")

# キー入力を常時受け取る関数
func _unhandled_input(event: InputEvent) -> void:
	# キーが押されたイベントかつ「Pキー」であるか判定
    if event is InputEventKey and event.pressed and not event.echo:
        if event.keycode == KEY_P:
            retry_count += 2
            print("[DEBUG] リトライ回数を ", retry_count, " に変更しました！")

# リトライ回数を加算する関数
func add_retry_count() -> void:
    retry_count += 1
	
# リトライ回数を参照する関数
func check_retry_count() -> int:
    return retry_count

# リトライ回数をリセットする関数（タイトルに戻る際などに呼ぶ）
func reset_retry_count() -> void:
    retry_count = 0