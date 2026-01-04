# 项目文件说明 / Project Files Explanation

本文档解释项目根目录中每个文件和文件夹的用途。

## 📁 主要文件夹 / Main Folders

### 应用相关 / Application Related
- **lib/** - Flutter应用源代码（最重要！）
- **test/** - 单元测试和集成测试
- **android/** - Android平台特定代码
- **ios/** - iOS平台特定代码
- **web/** - Web平台特定代码
- **windows/** - Windows平台特定代码
- **linux/** - Linux平台特定代码
- **macos/** - macOS平台特定代码

### 项目组织 / Project Organization
- **docs/** - 📚 所有项目文档
- **server/** - 🖥️ Python服务器和SDK
- **releases/** - 📦 APK发布文件

## 📄 根目录文件 / Root Files

### 必需的配置文件 / Required Config Files
这些文件**必须**保留在根目录，不能移动或删除：

#### Flutter核心配置 / Flutter Core Config
1. **pubspec.yaml** ⭐ 最重要
   - Flutter项目的"package.json"
   - 定义所有依赖包、版本、资源
   - 修改后需运行 `flutter pub get`

2. **pubspec.lock**
   - 自动生成，锁定依赖版本
   - 不要手动编辑
   - 确保团队使用相同版本依赖

3. **analysis_options.yaml**
   - Dart代码分析规则
   - 定义代码风格检查
   - IDE会根据此文件显示警告

#### 项目文档 / Project Docs
4. **README.md**
   - 项目简介和快速导航
   - 第一个看到的文档

5. **PROJECT_STRUCTURE.md**
   - 详细的项目结构说明
   - 开发工作流指南

### 隐藏的配置文件 / Hidden Config Files
这些文件以点(.)开头，在文件管理器中默认隐藏：

#### Git配置 / Git Config
- **.gitignore** - Git忽略规则
- **.git/** - Git版本控制数据

#### Flutter/Dart工具 / Flutter/Dart Tools
- **.dart_tool/** - Dart工具缓存（自动生成）
- **.flutter-plugins** - Flutter插件列表（自动生成）
- **.flutter-plugins-dependencies** - 插件依赖（自动生成）
- **.metadata** - Flutter元数据（自动生成）

#### IDE配置 / IDE Config
- **.vscode/** - VS Code配置
  - **settings.json** - 编辑器设置（已配置隐藏杂项文件）
- **.idea/** - IntelliJ IDEA配置
- **.claude/** - Claude Code工具配置

#### 临时文件 / Temporary
- **build/** - 构建输出（自动生成，可删除）
- **.DS_Store** - macOS系统文件（应被忽略）

## 🎯 文件管理原则 / File Management Rules

### ✅ 可以编辑 / Can Edit
- `pubspec.yaml` - 添加/更新依赖
- `analysis_options.yaml` - 调整代码规则
- `README.md` - 更新项目说明
- `.gitignore` - 添加忽略规则
- `.vscode/settings.json` - IDE偏好设置

### ❌ 不要编辑 / Don't Edit
- `pubspec.lock` - 自动生成
- `.metadata` - Flutter内部使用
- `.flutter-plugins*` - 自动生成
- `build/` 下的任何文件

### 🗑️ 可以安全删除（会自动重建） / Safe to Delete
- `build/` - 构建缓存
- `.dart_tool/` - Dart工具缓存
- `*.iml` - IntelliJ项目文件
- `devtools_options.yaml` - DevTools配置
- `.DS_Store` - macOS垃圾文件

### 🚫 绝不删除 / Never Delete
- `lib/` - 你的源代码！
- `pubspec.yaml` - 项目配置核心
- `android/`, `ios/` 等平台文件夹
- `.git/` - 版本控制历史

## 📊 根目录文件统计 / Root Files Summary

**总文件数**: ~17个可见文件/文件夹  
**核心文件**: 2个 (pubspec.yaml, README.md)  
**平台文件夹**: 6个 (android, ios, web, windows, linux, macos)  
**项目文件夹**: 4个 (lib, docs, server, releases)  
**配置文件**: 2个 (analysis_options.yaml, pubspec.lock)  
**文档**: 2个 (README.md, PROJECT_STRUCTURE.md)  

## 🔍 查看隐藏文件 / View Hidden Files

### 命令行 / Command Line
```bash
# 查看所有文件（包括隐藏）
ls -la

# 只看隐藏文件
ls -ld .*
```

### VS Code
- 已配置 `.vscode/settings.json` 自动隐藏杂项文件
- 重启VS Code查看效果

### macOS Finder
- 快捷键: `Cmd + Shift + .`

## 📝 修改依赖示例 / Add Dependency Example

编辑 `pubspec.yaml`:
```yaml
dependencies:
  flutter:
    sdk: flutter
  provider: ^6.0.0          # 已有
  camera: ^0.10.0           # 已有
  new_package: ^1.0.0       # 添加新包
```

然后运行:
```bash
flutter pub get
```

---

**文档更新**: 2026-01-04  
**用途**: 帮助理解项目文件结构，避免误删重要文件
