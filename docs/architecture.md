# mnote：架构决策

本文档记录与 MacDown 扩展、SwiftUI 选型、套壳策略及底层替换节奏相关的**架构级**结论。视觉与界面语言见 [`ui-design.md`](ui-design.md)。

**范围**：下文只描述**一条主线**，待主线闭环后再做交互与能力的优化扩展（快捷键、多套扫描规则等不纳入当前约定）。

---

## 1. 背景：基于 `3rd/macdown` 的增强方向

在 MacDown 之上计划增强的能力包括：

- **根目录（root）**：可置于 iCloud（或任意用户选定目录），作为笔记库的**唯一顶层**；所有笔记本都挂在这棵目录树下。
- **笔记本 / workspace**：**基于根目录**，每个笔记本对应 **root 直下的一层子文件夹**（`root/<notebook>/…`）；应用内「当前笔记本」即当前选中的该文件夹。
- **文件浏览**：**侧栏**展示**当前 workspace** 内文件（路径始终在 `root` 之下）。
- **预览内跳转**：在预览中点击链接时，在应用内打开/切换文档，而非仅依赖系统默认打开方式。

MacDown 原项目要点（便于套壳时对接）：

| 项目 | 说明 |
|------|------|
| 技术栈 | Objective-C、AppKit、`NSDocument`、旧版 `WebKit/WebView`、CocoaPods（Hoedown、Handlebars 等） |
| 核心类 | `MPDocument`（文档与编辑/预览）、`MPRenderer`（Markdown→HTML）、预览链接策略在 `openOrCreateFileForUrl:` 等 |
| 现状 | 一窗口一文件为主；无内置「笔记本 / 根目录 / 侧栏文件树」的统一模型 |

---

## 2. 多笔记本：启动默认与切换（主线）

### 2.1 启动时默认笔记本

**只做一条规则链：先上次会话，否则第一个候选；无 root 就先授权。**

1. **必须先有 root**：未配置 root 时，先让用户完成 root 选择（书签/授权）；**不得在首启静默猜测路径**。
2. **持久化**：保存上一次「当前 notebook」对应的 **workspace URL**（与安全作用域下的 root 书签一致或可由其校验）。
3. **恢复**：若该 URL **仍在当前 root 下且可读** → 启动后直接作为当前笔记本。
4. **否则**：将 **root 下一层中的每一个子文件夹**视为一个 notebook，按 **词典序取第一个** 作为当前笔记本。
5. **若 root 下没有子文件夹**：空状态由用户先在 root 内**新建文件夹**作为笔记本后再继续。

「当前 notebook」与套壳策略中的 **SSOT**（如协调器持有的 `workspaceURL`）保持一致。

### 2.2 如何切换笔记本

**仅一路径**：侧栏列出 **root 下一层的子文件夹**（即 notebook 列表），**点击一项**切换当前笔记本。

**切换后行为：**

- 侧栏文件树改为该 workspace 的树；预览与打开的 Markdown 所使用的**相对路径基准**改为该文件夹根路径。
- 已打开文稿**不强行关闭**；若在 UI 中能显示路径或标题后缀，标明所在路径即可。

---

## 3. 是否用 SwiftUI 完全重构？

**结论：不采用「用 SwiftUI 完全推翻重写」作为第一步。**

理由摘要：

- 与 **NSDocument、旧 WebView、Hoedown/PEG 管线、Sparkle/Pods** 深度耦合，全量重写等价于新产品研发，回归面大。
- 即使迭代周期允许，仍应优先 **降低技术风险**：先满足业务模型（root、`root`/workspace、浏览、链接策略），再按需替换底层实现。

**后续策略**：主线完成后，再分阶段替换 Objective-C 与预览栈，并与 UI 层解耦；具体顺序在动手替换时再定，此处不铺开多套路。

---

## 4. SwiftUI「能不能实现」的澄清

**结论：目标功能的上限通常不由「是否 SwiftUI」决定，而由编辑器、Web 预览、沙盒与文档模型决定。**

- **笔记本、文件树、iCloud 根目录、预览内导航**：主要涉及文件 URL、安全作用域书签、`WKNavigationDelegate` 等与 UI 框架无根本冲突。
- **复杂 Markdown 编辑**：业界常见做法是 **继续承载于 `NSTextView`（或同类）**，通过 `NSViewRepresentable` 嵌入 SwiftUI，而不是强行纯 `TextEditor`。
- **预览**：使用 **`WKWebView`** + Representable，与 SwiftUI 壳层分工明确。

因此采用 **混合架构**：SwiftUI 负责新页面与导航，重型能力由 AppKit/WebKit 托管。

---

## 5. 已定方案：SwiftUI 新页面 + 套壳（Shell）

**结论（执行口径）：**

1. **新界面以 SwiftUI 为主**实现（导航、笔记本列表、侧栏、设置等）。
2. **套壳**：编辑器、预览（及短期内仍需复用的 MacDown 能力）通过 **`NSViewRepresentable` / `NSViewControllerRepresentable`** 嵌入 SwiftUI 视图层次，与现有 Objective-C 代码同进程协作。
3. **替换 Objective-C**：不在主线完成前作为一项并行目标；待套壳与 URL/workspace 模型稳定后，按模块逐个替换实现。

**套壳原则（建议写进代码评审检查项）：**

- SwiftUI 层只负责布局、状态绑定与路由；不复制 MacDown 内已有渲染逻辑。
- 文档打开、当前文件 URL、workspace 根路径等 **单一事实来源（SSOT）** 需在设计阶段定义，避免 SwiftUI 与 `NSDocument` 各维护一套状态。
- 为后续替换 ObjC 预留边界：Representable 适配器尽量薄，业务用 Swift/SwiftUI 或独立协调器表达。

---

## 6. 文档维护（架构）

- 架构、套壳边界或文档模型有重大变更时，更新 **本文档** 并注明日期与原因。
- 沙盒、entitlements 等实现细节在代码或单独实现说明中维护即可；本文保持主线决策。

---

*源自项目内关于 MacDown 技术栈、SwiftUI 与混合架构的讨论。*
