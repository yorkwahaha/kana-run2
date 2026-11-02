# Kana Run 2.0 — 第一關試玩版

Godot **4.7.2**（`I:\Projects\Godot_v4.7.2`），**Mobile** 渲染器（Web 匯出時自動改用 Compatibility）。
舊專案 `I:\Projects\Kana Run` 是凍結的 1.0 Beta，**不要修改**；本專案只從那裡複製了素材。

## 怎麼玩
- 電腦：雙擊 `play.bat`（開發者計時模式：`play-dev.bat`），或 `editor.bat` 開編輯器後按 F5。
- 手機（同一個 Wi‑Fi）：
  1. `export-web.bat` → 產生 `build/web/`
  2. `python serve_web.py` → https://<電腦IP>:8443 （例：https://192.168.50.107:8443）
  3. Godot 4.7 Web 一定要 https（secure context），所以用 1.0 的自簽憑證（已複製到 `build/certs/`；若手機沒裝過，見 `serve_web.py` 開頭說明；要重產用 `python make_certs.py`）。
- 自動測試：`selftest.bat`（單元測試 + 自動駕駛跑完第一關）。

## 速度模式（選關畫面「設定」或暫停選單切換，存在存檔裡）
- **賽車模式**（預設）：按住加速／按住煞車／都不按自然減速。**定速鎖定**：「鎖定」鈕或 F 鍵，鎖住當下速度；鎖定時不按任何鍵會維持速度；仍可暫時按住加速或煞車，放開後沿加速／煞車曲線回到鎖定速度（不是瞬間）。再按一次解除。HUD 顯示「鎖定 xx」。
- **點放模式**：點一下加速 = 目標 +5 km/h，點一下煞車 = −5（0～60，`speed.step_kmh`）。實際速度沿加速／煞車曲線追目標；不按就維持目標，不會自然減速。HUD 顯示「目前 → 目標 km/h」。撞錯仍是速度減半；`speed.step_wrong_halves_target`（預設 true）決定目標要不要一起減半。鍵盤長按的自動重複（echo）會被忽略，一次按下只算一格。
- 跑到一半切換：賽車→點放時，目標 = 目前速度取到最近的 5 km/h；點放→賽車時解除鎖定、保留目前速度。切換時放開所有輸入。
- 兩種模式共用時限。結算畫面、計時 JSON／CSV 都會記錄模式（摘要檔改名 `runs_v3.csv`，多了 `mode` 欄）。

## 操作
| 動作 | 手機 / 滑鼠 | 鍵盤 |
|---|---|---|
| 加速 | 右下「加速」（賽車：按住；點放：點一下 +5） | W / Space / ↑ |
| 煞車 | 左下「煞車」（賽車：按住；點放：點一下 −5） | S / ↓ |
| 定速鎖定（賽車） | 「加速」上方「鎖定」 | F |
| 換線 | 左右滑動（另一隻手指，或按著「加速」的手指直接左右滑） | A / D / ← / → |
| 重播語音 | 右上「重播」 | E |
| 暫停 | 右上「II」 | Esc / P |
| 暫停選單 | 「繼續」「重來」「模式切換」「回選關」 | Esc 繼續、R 重來、Q 回選關 |
| 開發者計時 | — | F3（或啟動參數 `-- --dev`、設定 `dev.timing_mode`） |

- 觸控按鈕大小依畫面短邊等比例縮放（加速約 28%、煞車 24%、鎖定 17%），直式和橫式都夠大。
- 多點觸控：每隻手指依 index 追蹤；從按鈕開始的手指控制那顆按鈕，其他手指負責滑動換線。
- 自動暫停：視窗失焦、App 進背景、網頁分頁切走（`visibilitychange`）時自動暫停，並放開所有按住的輸入。暫停時間不計入時間；暫停時隱藏羅馬拼音提示。

## 關卡與存檔
- 開啟後先到「選關」。關卡資料全部在 `config/game_config.json` 的 `levels` 陣列（id、name、kana、romaji、target_correct、時限、星數門檻、罰秒；可選 `romaji_first_n` / `voice_only_after_progress` 覆寫提示規則）。**新增關卡只要加一筆資料**，語音用 romaji 對應 `audio/kana/<romaji>.mp3`（102 個音檔已全部在 `asset_manifest.gd` preload，Web 也會打包）。
- 第一關 あ行：20 題，63／47／36 秒。第二關 あ行＋か行：30 題，91／68／52 秒（依 Hayato 最佳 45.48 秒校準）。
- 存檔 `user://save.json`：每關 cleared、最佳星數、最佳時間（只在更好時更新）。過前一關才解鎖下一關。
- 結算畫面：「重玩」「下一關」（最後一關隱藏、未解鎖時停用）「回選關」。鍵盤：Space/Enter 重玩、N 下一關、Esc/B 回選關、選關畫面按 1–9。
- 想重置進度：刪除 `%APPDATA%\Godot\app_userdata\Kana Run 2.0\save.json`。

## 體力（HP）
- 預設 3 顆心（`hp.max_hp`；各關可用 `max_hp` 覆寫）。撞錯 −1 心（加上原本 −2 秒、速度減半）。漏題預設只扣時間；`hp.miss_costs_heart`（或各關 `miss_costs_heart`）設 true 時也扣 1 心。沒有自然扣血。
- 0 心立即結束，結算顯示「體力耗盡」（時間用完是「時間到」），不算過關；計時紀錄的 outcome 欄位是 `hp_out`／`time_up`／`clear`。
- 受傷時只有左上的愛心閃紅並晃動，不會晃畫面。
- 之後做強化用的接口（game.gd）：`set_max_hp_bonus(n)`（極限體力強化）、`add_shield(n)`（護身符擋一次傷害）、`heal(n)`（回 1 心）、`take_damage(n)`，訊號 `hp_changed(hp, max_hp, shield)`、`damaged(amount, blocked)`。目前沒有道具使用它們。

## 規則（第一關）
- 三條跑道，石碑每 `row_spacing_m` 公尺一排三塊。聽語音（あいうえお），撞對應假名。
- 答對 20 題過關。撞錯：+2 秒、速度減半，**下一排重出同一題，正確假名換到別條跑道**。三塊都沒撞到（從兩塊石碑中間穿過）：漏題 +1 秒，**這個假名排到之後新生成的一排重出**。
- 題目提示：畫面上方顯示羅馬拼音。每個假名前 `hints.romaji_first_n`（3）次出現才顯示，而且進度未達 `hints.voice_only_after_progress`（50%）；過了之後全部只播聲音（顯示「?」），切換時畫面出現「聽音模式」。
- 連擊：連續答對次數（2 以上顯示「N 連擊」並彈跳）。撞錯或漏題都歸零；不影響時間。結算顯示最佳連擊。
- 時間 = 實際時間 + 罰秒。時限 63 秒；≤47 秒二星；≤36 秒三星。
- 校準依據：Hayato 最佳 31.3 秒 × 企劃書公式（三星 ×1.15、二星 ×1.5、過關 ×2.0）。理論最快約 30.7 秒。

## 參數
全部在 `config/game_config.json`：速度（極速 60 km/h、加速 3 秒、煞車 1.2 秒、自然減速時間）、跑道寬度與換線時間、石碑間距、打擊感（光暈、擊飛距離、FOV、`screen_shake_on_normal_hit=false`）、各關時限與星數門檻。
不重新匯出也能在裝置上調：把要覆寫的欄位寫進 `user://game_config_override.json`。

## 開發者計時模式
過關或失敗時寫到 `user://timing/`（Windows：`%APPDATA%\Godot\app_userdata\Kana Run 2.0\timing\`）：
- `run_<時間>.json` / `.csv`：每題目標、結果、反應時間（語音開始→撞到）、當下速度、時間
- `runs_v3.csv`：每局一行摘要（模式、結果 clear／time_up／hp_out、通關時間、星數、對/錯/漏、平均反應、剩餘體力）
畫面右上角同時顯示即時數據。

## 結構
```
config/game_config.json   所有可調參數與關卡資料
scenes/main.tscn          只有根節點；世界、HUD、音效都在 game.gd 用程式建
scripts/game.gd           主遊戲（狀態、生成、判定、打擊感、輸入、HUD）
scripts/speed_controller.gd  速度邏輯（純邏輯，可單元測試）
scripts/rules.gd          星數、碰撞車道、出題
scripts/dev_logger.gd     計時紀錄
scripts/asset_manifest.gd 所有執行期資源都要在這裡 preload，否則 Web 匯出會漏檔
tools/smoke_test.gd       無頭測試（含多種解析度的版面置中檢查）
tools/screenshot.gd       需視窗：各解析度截圖（-- --out=資料夾）
scripts/save_data.gd      存檔／解鎖
audio/ assets/fonts/      從 1.0 複製的語音、音效、音樂、字型
```

## 注意
- 1.0 的子集字型（ui/bold.ttf）缺「模」，所以提示、連擊、聽音模式用 `assets/fonts/hud_cjk.ttf`（Noto Sans TC 子集，OFL，授權在 `OFL-NotoSansTC.txt`）。HUD 加新中文字時要用 `tools/make_hud_font.py` 重產（它會自動掃 scripts/ 和 config/ 裡用到的所有中文字）。
- 只裝了 Web 匯出模板（沒有 Windows/Android 模板），所以沒有 Windows exe / APK 預設。
- 匯出時出現 `include_filter` 的 ERROR 可忽略（4.7 已移除該鍵）。

## 下一步建議
- 美術：替換佔位方塊（石碑、角色、跑道）。
- 第二關起：更多行（か行…）、關卡選單、存檔與星數紀錄。
