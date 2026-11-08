# 石碑外觀調整

- 寬度由原顯示平面約 1.35 m 改為 1.68 m（約 +24%）；高度由 1.52 m 改為 1.90 m（+25%）。
- 霓虹玻璃平面改為不透明 3D 石塊，有約 0.58 m 厚度、八角不規則輪廓、斜角、礦物顆粒和細裂紋。
- 假名字體同步稍微放大，使用暖白字與深色描邊。當前題目提示改成底部細線，避免外觀再像玻璃螢幕。
- 擊碎改成五塊立體石屑；一般石塊共用網格與材質，受擊時只複製該石塊的閃色材質，不影響其他選項，也不新增題庫亂數消耗。
- 修正 Compatibility 與 Forward Mobile 色彩空間差異，避免石頭在原生版本過度泛白。

驗證：420 項完整回歸及 26 項專項回歸通過。Compatibility 產出 64 張狀態截圖；最終材質另在 Compatibility／Vulkan Forward Mobile 各檢查直橫式遊玩與護盾四張畫面，無 SCRIPT ERROR、shader error 或資源退出警告。

證據：`build/report-verify/stone-smoke.log`、`stone-report.log`、`stone-final-screens/`、`stone-native-screens/`。

上述為桌面引擎與受控畫面驗證，尚未實體手機驗收。
