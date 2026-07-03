该项目采用标准的 Flutter (Dart) 与 Android (Gradle) 双轨依赖管理策略。

### 1. Dart/Flutter 依赖管理
- **核心工具**：使用 `pub` 包管理器，通过根目录的 `pubspec.yaml` 声明项目元数据及依赖项。
- **版本控制**：
  - **语义化版本约束**：在 `pubspec.yaml` 中使用 `^` 符号（如 `flutter_riverpod: ^2.5.1`）允许自动获取兼容的小版本更新。
  - **环境锁定**：明确指定了 SDK 版本要求 (`sdk: ^3.5.0`)，确保开发环境的一致性。
- **依赖锁定**：`pubspec.lock` 文件记录了所有直接和传递性依赖的确切版本及哈希值。该文件被提交至版本控制系统，确保了在不同机器或 CI/CD 环境中构建结果的可复现性。
- **私有发布限制**：`pubspec.yaml` 中设置 `publish_to: 'none'`，表明该项目为私有应用，不发布至 pub.dev 公共仓库。
- **主要依赖库**：
  - 状态管理：`flutter_riverpod`
  - 网络请求：`dio`
  - 本地存储：`sqflite`, `shared_preferences`, `path_provider`
  - UI 增强：`flutter_animate`, `google_fonts`, `flutter_svg`

### 2. Android 原生依赖管理
- **构建系统**：采用 Kotlin DSL (`build.gradle.kts`) 进行配置，相比 Groovy 具有更好的类型安全和 IDE 支持。
- **仓库配置**：在 `android/build.gradle.kts` 中统一配置了 `google()` 和 `mavenCentral()` 作为依赖下载源，确保原生插件和 Android 库的稳定获取。
- **插件集成**：通过 `dev.flutter.flutter-gradle-plugin` 实现 Flutter 引擎与 Android 项目的无缝集成，由 Flutter 工具链自动管理原生部分的编译与打包。
- **版本同步**：Android 端的 `compileSdk`, `minSdk` 等关键配置直接引用 `flutter.compileSdkVersion` 等变量，由 Flutter SDK 统一管理，减少了手动维护多平台版本冲突的风险。

### 3. 开发者规范
- **依赖更新**：执行 `flutter pub get` 以根据 `pubspec.yaml` 解析并下载依赖；执行 `flutter pub upgrade` 可更新依赖至符合版本约束的最新版本。
- **冲突解决**：若遇到依赖版本冲突，应优先检查 `pubspec.lock` 中的传递性依赖树，并通过在 `pubspec.yaml` 中显式声明特定版本或使用 `dependency_overrides` 进行干预。
- **资源管理**：静态资源（图片、图标）在 `pubspec.yaml` 的 `flutter.assets` 字段中声明，构建时会自动打包进应用包体。