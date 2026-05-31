// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SkillManager",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "SkillManager",
            path: "SkillManager"
        )
    ]
)
