# 贡献指南 | Contributing Guide

[English](#english) | [中文](#中文)

---

## 中文

感谢你对 OpenBene 项目的关注！我们欢迎任何形式的贡献。

### 如何贡献

#### 1. 报告 Bug

如果你发现了 Bug，请通过 [Issue](https://github.com/HeyBene/OpenBene/issues/new?template=bug_report_CN.yml) 报告：

- 使用清晰的标题描述问题
- 详细描述复现步骤
- 说明期望行为和实际行为
- 附上相关日志或截图

#### 2. 提出新功能

有好的想法？请通过 [Feature Request](https://github.com/HeyBene/OpenBene/issues/new?template=feature_request_CN.yml) 提出：

- 描述你想要的功能
- 说明使用场景
- 如果可能，提供实现思路

#### 3. 提交代码

##### 开发环境设置

```bash
# 克隆仓库
git clone https://github.com/HeyBene/OpenBene.git
cd OpenBene

# 安装 SDK 开发依赖
cd openbene_sdk
pip install -e ".[dev]"
```

##### 代码规范

- **Python**: 遵循 PEP 8 规范
- **Flutter/Dart**: 遵循 Dart 官方风格指南
- **Arduino**: 使用 2 空格缩进

##### 提交流程

1. **Fork 仓库** - 点击右上角 Fork 按钮
2. **创建分支** - `git checkout -b feature/your-feature-name`
3. **编写代码** - 确保代码质量和测试
4. **提交更改** - 使用清晰的 commit message
5. **推送分支** - `git push origin feature/your-feature-name`
6. **创建 PR** - 填写 PR 模板，描述你的更改

##### Commit Message 规范

```
<type>: <description>

[optional body]

[optional footer]
```

**Type 类型：**
- `feat`: 新功能
- `fix`: Bug 修复
- `docs`: 文档更新
- `style`: 代码格式（不影响功能）
- `refactor`: 重构
- `test`: 测试相关
- `chore`: 构建/工具相关

**示例：**
```
feat: Add realtime keyboard control

- Add WASD control with drift mode
- Support recording during control
- Auto-install pynput dependency
```

#### 4. 改进文档

文档同样重要！你可以：

- 修复文档中的错误
- 添加使用示例
- 翻译文档
- 改进 README

#### 5. 分享项目

- 在社交媒体分享你的作品
- 写博客介绍 OpenBene
- 录制教程视频
- 在技术社区推荐

### 项目结构

```
OpenBene/
├── openbene_sdk/           # Python SDK
│   ├── src/                # 核心代码
│   │   ├── connection.py   # WebSocket 连接
│   │   ├── motor.py        # 电机控制
│   │   ├── video.py        # 视频接收
│   │   ├── sensors.py      # 传感器
│   │   ├── recording.py    # 数据采集
│   │   └── openbene.py     # 主类
│   └── examples/           # 示例代码
├── openbot-mobile-control/ # Existing Flutter mobile app
├── apps/
│   └── robot_app/          # Imported robot-side Flutter app
└── openbot.ino             # Arduino 固件
```

### 需要帮助？

- 查看 [Issues](https://github.com/HeyBene/OpenBene/issues) 中标记为 `good first issue` 的任务
- 在 [Discussions](https://github.com/HeyBene/OpenBene/discussions) 提问
- 阅读 [SDK 文档](openbene_sdk/README.md)

### 分支管理策略

我们使用 **GitHub Flow** 分支模型：

```
main (受保护) ← feature/xxx ← 你的开发
```

**分支命名规范：**
- `feature/xxx` - 新功能
- `fix/xxx` - Bug 修复
- `docs/xxx` - 文档更新
- `refactor/xxx` - 重构

**注意：** `main` 分支受保护，禁止直接 push，必须通过 PR 合并。

### Code Review 标准

所有 PR 必须经过至少 **1 人审核** 才能合并。

**审核清单：**

| 类别 | 要求 |
|------|------|
| **代码质量** | 遵循代码规范（PEP 8 / Dart Style） |
| **功能完整** | 功能实现完整，无明显 Bug |
| **测试验证** | 提供测试方法或使用示例 |
| **文档更新** | 新 API 需更新 README 或文档 |
| **CHANGELOG** | 重要变更需更新 CHANGELOG.md |
| **安全检查** | 不包含密钥、Token 等敏感信息 |

**审核者职责：**
- 48 小时内完成首次审核
- 提供建设性反馈
- 及时回复作者的问题

**作者职责：**
- 及时响应审核意见
- 解释代码设计决策
- 修复发现的问题

### PR 合并要求

1. ✅ 至少 1 人 Approve
2. ✅ 所有对话已解决
3. ✅ CI 检查通过（如有）
4. ✅ 与最新 main 分支无冲突

---

## English

Thank you for your interest in OpenBene! We welcome contributions of all kinds.

### How to Contribute

#### 1. Report Bugs

Found a bug? Please report it via [Issue](https://github.com/HeyBene/OpenBene/issues/new?template=bug_report.yml):

- Use a clear title
- Describe steps to reproduce
- Explain expected vs actual behavior
- Include logs or screenshots

#### 2. Suggest Features

Have ideas? Submit a [Feature Request](https://github.com/HeyBene/OpenBene/issues/new?template=feature_request.yml):

- Describe the feature
- Explain use cases
- Suggest implementation if possible

#### 3. Submit Code

##### Development Setup

```bash
# Clone the repo
git clone https://github.com/HeyBene/OpenBene.git
cd OpenBene

# Install SDK dev dependencies
cd openbene_sdk
pip install -e ".[dev]"
```

##### Code Style

- **Python**: Follow PEP 8
- **Flutter/Dart**: Follow Dart style guide
- **Arduino**: Use 2-space indentation

##### Contribution Workflow

1. **Fork** the repository
2. **Create branch** - `git checkout -b feature/your-feature-name`
3. **Write code** - Ensure quality and tests
4. **Commit** - Use clear commit messages
5. **Push** - `git push origin feature/your-feature-name`
6. **Create PR** - Fill out the PR template

##### Commit Message Format

```
<type>: <description>

[optional body]

[optional footer]
```

**Types:**
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation
- `style`: Code formatting
- `refactor`: Code refactoring
- `test`: Testing
- `chore`: Build/tooling

#### 4. Improve Documentation

- Fix errors
- Add examples
- Translate docs
- Improve README

#### 5. Spread the Word

- Share on social media
- Write blog posts
- Create tutorials
- Recommend in communities

### Need Help?

- Check [Issues](https://github.com/HeyBene/OpenBene/issues) labeled `good first issue`
- Ask in [Discussions](https://github.com/HeyBene/OpenBene/discussions)
- Read the [SDK docs](openbene_sdk/README.md)

### Branch Strategy

We use **GitHub Flow** branching model:

```
main (protected) ← feature/xxx ← your development
```

**Branch naming:**

- `feature/xxx` - New features
- `fix/xxx` - Bug fixes
- `docs/xxx` - Documentation
- `refactor/xxx` - Refactoring

**Note:** `main` branch is protected. Direct push is disabled; changes must go through PR.

### Code Review Standards

All PRs require at least **1 approval** before merging.

**Review Checklist:**

| Category | Requirement |
| -------- | ----------- |
| **Code Quality** | Follows style guide (PEP 8 / Dart Style) |
| **Completeness** | Feature works correctly, no obvious bugs |
| **Testing** | Includes test method or usage example |
| **Documentation** | New APIs documented in README |
| **CHANGELOG** | Important changes added to CHANGELOG.md |
| **Security** | No secrets, tokens, or sensitive data |

**Reviewer Responsibilities:**

- Complete first review within 48 hours
- Provide constructive feedback
- Respond to author questions promptly

**Author Responsibilities:**

- Respond to review comments
- Explain design decisions
- Fix identified issues

### PR Merge Requirements

1. ✅ At least 1 approval
2. ✅ All conversations resolved
3. ✅ CI checks pass (if configured)
4. ✅ No conflicts with main branch

---

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
