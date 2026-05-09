// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "mnote",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "mnote", targets: ["mnote"]),
    ],
    dependencies: [
        /// AST / 解析栈与 Apple [swift-markdown](https://github.com/swiftlang/swift-markdown) 一致；预览 HTML 走同源的 swift-cmark 渲染。
        .package(url: "https://github.com/swiftlang/swift-markdown.git", exact: "0.6.0"),
        .package(url: "https://github.com/swiftlang/swift-cmark.git", exact: "0.6.0"),
    ],
    targets: [
        .executableTarget(
            name: "mnote",
            dependencies: [
                .product(name: "Markdown", package: "swift-markdown"),
                .product(name: "cmark-gfm", package: "swift-cmark"),
                .product(name: "cmark-gfm-extensions", package: "swift-cmark"),
            ],
            path: "Sources/mnote",
            resources: [
                .process("Resources"),
            ]
        ),
    ]
)
