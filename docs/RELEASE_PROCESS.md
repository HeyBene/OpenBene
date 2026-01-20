# 发布流程 | Release Process

[English](#english) | [中文](#中文)

---

## 中文

### 版本号规范

我们遵循 [语义化版本](https://semver.org/lang/zh-CN/) (Semantic Versioning)：

```
主版本.次版本.修订号
  v2    .  1   .  0
```

| 版本类型 | 何时更新 | 示例 |
| -------- | -------- | ---- |
| **主版本** | 不兼容的 API 变更 | v1.0.0 → v2.0.0 |
| **次版本** | 新增向后兼容的功能 | v2.0.0 → v2.1.0 |
| **修订号** | 向后兼容的 Bug 修复 | v2.1.0 → v2.1.1 |

### 发布步骤

#### 1. 准备发布

```bash
# 确保在 main 分支且代码最新
git checkout main
git pull origin main

# 确认所有测试通过
cd openbene_sdk
pip install -e .
python -c "from openbene import OpenBene; print('OK')"
```

#### 2. 更新版本号

**Python SDK** (`openbene_sdk/src/__init__.py`):

```python
__version__ = "2.2.0"  # 更新版本号
```

**Flutter App** (`openbot-mobile-control/pubspec.yaml`):

```yaml
version: 2.2.0+1  # 更新版本号
```

#### 3. 更新 CHANGELOG

在 `CHANGELOG.md` 顶部添加新版本内容：

```markdown
## [2.2.0] - 2026-01-15

### ✨ 新功能
- 添加实时键盘控制 `realtime_control()` (#12)

### 🐛 Bug 修复
- 修复转弯半径过大问题 (#10)

### 📝 文档
- 更新 SDK 使用文档
```

#### 4. 提交版本变更

```bash
git add .
git commit -m "chore: Bump version to v2.2.0"
git push origin main
```

#### 5. 创建 Tag 并推送

```bash
# 创建带注释的 Tag
git tag -a v2.2.0 -m "Release v2.2.0"

# 推送 Tag（这会触发自动发布）
git push origin v2.2.0
```

#### 6. 自动发布

推送 Tag 后，GitHub Actions 会自动：

1. ✅ 构建 Python SDK (wheel + tar.gz)
2. ✅ 构建 Flutter APK
3. ✅ 创建 GitHub Release
4. ✅ 上传构建产物

#### 7. 验证发布

1. 检查 [GitHub Releases](https://github.com/HeyBene/OpenBene/releases) 页面
2. 下载 APK 测试安装
3. 下载 SDK wheel 测试安装

### Release Note 模板

```markdown
## 🚀 OpenBene v2.2.0

### ✨ 新功能
- 功能描述 (#PR号)

### 🐛 Bug 修复
- 修复描述 (#Issue号)

### 📝 文档
- 文档更新

### ⚠️ 破坏性变更
- 变更说明（如有）

### 📦 下载
- **Android APK**: [app-release.apk](链接)
- **Python SDK**: `pip install openbene==2.2.0`

### 🙏 致谢
感谢所有贡献者！
```

---

## English

### Version Numbering

We follow [Semantic Versioning](https://semver.org/):

```
MAJOR.MINOR.PATCH
  v2  .  1  .  0
```

| Type | When to Update | Example |
| ---- | -------------- | ------- |
| **MAJOR** | Incompatible API changes | v1.0.0 → v2.0.0 |
| **MINOR** | New backward-compatible features | v2.0.0 → v2.1.0 |
| **PATCH** | Backward-compatible bug fixes | v2.1.0 → v2.1.1 |

### Release Steps

#### 1. Prepare Release

```bash
# Ensure on main branch with latest code
git checkout main
git pull origin main

# Verify tests pass
cd openbene_sdk
pip install -e .
python -c "from openbene import OpenBene; print('OK')"
```

#### 2. Update Version Numbers

**Python SDK** (`openbene_sdk/src/__init__.py`):

```python
__version__ = "2.2.0"
```

**Flutter App** (`openbot-mobile-control/pubspec.yaml`):

```yaml
version: 2.2.0+1
```

#### 3. Update CHANGELOG

Add new version at top of `CHANGELOG.md`:

```markdown
## [2.2.0] - 2026-01-15

### ✨ New Features
- Add realtime keyboard control `realtime_control()` (#12)

### 🐛 Bug Fixes
- Fix turn radius too large (#10)

### 📝 Documentation
- Update SDK documentation
```

#### 4. Commit Version Changes

```bash
git add .
git commit -m "chore: Bump version to v2.2.0"
git push origin main
```

#### 5. Create and Push Tag

```bash
# Create annotated tag
git tag -a v2.2.0 -m "Release v2.2.0"

# Push tag (triggers automatic release)
git push origin v2.2.0
```

#### 6. Automatic Release

After pushing the tag, GitHub Actions will:

1. ✅ Build Python SDK (wheel + tar.gz)
2. ✅ Build Flutter APK
3. ✅ Create GitHub Release
4. ✅ Upload build artifacts

#### 7. Verify Release

1. Check [GitHub Releases](https://github.com/HeyBene/OpenBene/releases) page
2. Download and test APK installation
3. Download and test SDK wheel installation

### Release Note Template

```markdown
## 🚀 OpenBene v2.2.0

### ✨ New Features
- Feature description (#PR)

### 🐛 Bug Fixes
- Fix description (#Issue)

### 📝 Documentation
- Documentation updates

### ⚠️ Breaking Changes
- Change description (if any)

### 📦 Downloads
- **Android APK**: [app-release.apk](link)
- **Python SDK**: `pip install openbene==2.2.0`

### 🙏 Thanks
Thanks to all contributors!
```
