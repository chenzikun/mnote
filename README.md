# mnote

在 [MacDown](https://github.com/MacDownApp/macdown)（`3rd/macdown`）能力之上扩展的 macOS Markdown 笔记方向项目：支持可置于 iCloud 的**根目录（root）**、其下的 **`root`/workspace 笔记本**、侧栏**文件浏览**以及预览区**应用内跳转**等（实现进行中）。

**第三方参考**：`3rd/macdown` 仅作阅读与行为参考，**不要修改其中源码**。

## 仓库目录

```
mnote/                    # 本仓库根目录（单仓）
├── README.md
├── docs/                 # 架构与 UI 文档
├── 3rd/macdown/          # MacDown 上游拷贝，只读参考
└── mnote/                # 本应用：Swift Package（可执行 SwiftUI）
    ├── Package.swift
    └── Sources/mnote/    # 应用源码
```

`Package.swift` 放在内层目录 **`mnote/Package.swift`**，与文档、第三方树并列，避免和「仓库根」混在一层。

## 构建与运行

在包含 `Package.swift` 的包目录执行：

```bash
cd mnote
swift build
swift run mnote
```

或在 Xcode 中 **File → Open** 打开 **`mnote/Package.swift`** 后运行。

自检（无界面，自动跑主线状态逻辑）：

```bash
cd mnote
swift run mnote --self-check
```

打包 DMG（仓库根目录执行）：

```bash
bash scripts/package_dmg.sh
```

说明：

- `swift run mnote` 启动的是图形界面应用，终端不会持续输出业务日志。
- 配置文件会写到 `~/.mnote/config.json`（启动时自动创建 `~/.mnote`）。
- `--self-check` 会创建临时目录执行自动回归（root/创建 notebook/创建文件/保存/重启恢复），结束后自动清理。
- 根目录变更入口在设置页（`Cmd+,` 或工具栏齿轮按钮）。
- workspace 中支持文件树浏览（目录+Markdown 文件）、创建文件/文件夹、选择文件、编辑与保存。
- 预览区支持 Markdown 渲染和应用内链接跳转（相对路径在当前笔记本内解析）。
- 设置页支持主题切换（系统/浅色/深色）、预览栏开关、液态玻璃效果开关。
- 资源目录位于 `mnote/Sources/mnote/Resources/assets/`。

## 文档

| 文档 | 内容 |
|------|------|
| [docs/architecture.md](docs/architecture.md) | 技术架构：基于 MacDown 的增强目标、为何不整库 SwiftUI 重写、混合架构与 **SwiftUI + 套壳（Representable）** 策略、Objective-C 分阶段替换原则 |
| [docs/ui-design.md](docs/ui-design.md) | 界面方向：**液态玻璃（Liquid Glass）** 风格、材质与层次、可读性/深浅色/嵌入原生视图等实现注意 |
| [docs/interaction-spec.md](docs/interaction-spec.md) | 交互规格：root/笔记本创建/切换的单一路径、输入框行为、错误提示与验收清单 |
| [docs/state-machine.md](docs/state-machine.md) | 状态机：状态、事件、迁移图与副作用约束，作为实现对照 |

架构、视觉、交互与状态 **分文档维护**。建议开发顺序：先按 `interaction-spec` 与 `state-machine` 实现主线，再做优化。

## 上游

- 参考实现：`3rd/macdown`（其自身构建方式见其 `README.md`；本仓库不依赖在其中做修改）。
