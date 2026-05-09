# mnote 界面设计规范（design）

本文档说明 **mnote 整体视觉与交互样式**，供新页面、弹窗与分栏迭代时对照。架构与工程约定仍见 [`architecture.md`](architecture.md)；液态玻璃方向性说明可与 [`ui-design.md`](ui-design.md) 互补。

---

## 1. 设计关键字

| 关键字 | 含义 |
|--------|------|
| 液态玻璃（Liquid Glass） | 开启时：渐变全屏底 + **磨砂玻璃面板**（`liquidGlassPanel`）叠层，与 macOS 材质语言一致。 |
| 参考实现 | **设置（`SettingsView`）** 为弹窗/独立页的黄金样本：全屏底、`WindowChromeBridge`、`toolbarMaterialWhenLiquidGlass`、分段 **卡片**。 |
| 层次 | 背景（渐变或窗口灰）→ 玻璃卡片 → 卡片内控件；避免在玻璃上再叠一块实心大白板。 |

---

## 2. 主窗口布局

- **分栏**：`NavigationSplitView` 左侧为目录树，右侧为编辑/预览。
- **目录显隐**：只使用 **系统提供的侧栏切换按钮**（不要与自定义「列表/侧栏」按钮并列，避免重复）。
- **工具栏**：标题左侧保留 **笔记本**（`book.badge.plus`）等应用按钮；阅读模式、预览、设置等保持轻量。

---

## 3. 玻璃卡片（与设置一致）

- **容器修饰**：内容块使用 `.padding(14)` + `.liquidGlassPanel(enabled: library.liquidGlassEnabled)`（默认圆角，与设置里「工作区设置 / 界面」卡片一致）。
- **分栏内大面板**：主编辑区、侧栏整块树区域可使用 `cornerRadius: 18` 的分栏样式；**弹窗内分段**优先与设置相同，用默认 `liquidGlassPanel`，不要混用多种圆角/材质。
- **列表**：在玻璃卡片内时，列表使用 `.scrollContentBackground(.hidden)`，让磨砂底透出来，避免列表自带灰底与右侧编辑区色差过大。

---

## 4. 弹窗 / Sheet（以笔记本、设置为准）

1. 最外层：`ZStack` + `LiquidGlassBackground()`（或关闭玻璃时的窗口背景色）全屏铺底。
2. `WindowChromeBridge(liquidGlassEnabled:)`：与主窗口标题栏通透行为一致。
3. `toolbarMaterialWhenLiquidGlass`：标题栏区域磨砂。
4. 内容：`VStack(spacing: 14)` + 大标题（`.font(.title2.bold())`）+ 若干 **卡片**（见第 3 节）。
5. 固定常用尺寸时可参考设置：`frame(width: 620, height: …)` 一类，保持视觉稳定。

---

## 5. 字体与层级

- 页面标题：`title2` + `bold`。
- 卡片标题：`headline`。
- 说明文字：`callout` / `caption`，次要信息 `.foregroundStyle(.secondary)`。
- 正文编辑区以可读性为先，可偏实色；玻璃主要体现在侧栏与 Chrome。

---

## 6. 维护约定

- 新增浮层、向导、表单页时，**先对齐 `SettingsView` 再落地**；若偏离较大，应同步更新本文档并写明原因与日期。

---

*文件名说明：若仓库中出现 `deging.md` 等拼写变体，请以本文件 `design.md` 为规范正文。*
