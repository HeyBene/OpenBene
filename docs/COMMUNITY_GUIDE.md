# OpenBene 社区建设指南

本文档帮助你了解如何在 GitHub 上建设和管理 OpenBene 社区。

---

## 一、GitHub 社区基础设施

### 已完成 ✅

| 文件 | 用途 |
|------|------|
| `README.md` | 项目介绍和快速开始 |
| `LICENSE` | MIT 开源许可证 |
| `CONTRIBUTING.md` | 贡献指南 |
| `CODE_OF_CONDUCT.md` | 行为准则 |
| `CHANGELOG.md` | 版本更新日志 |
| `.github/ISSUE_TEMPLATE/` | Issue 模板 |
| `.github/PULL_REQUEST_TEMPLATE.md` | PR 模板 |

### 待开启 📋

#### 1. GitHub Discussions

**开启方法：**
1. 进入仓库 Settings
2. 找到 Features 部分
3. 勾选 Discussions

**建议分类：**
- 📣 Announcements - 项目公告
- 💬 General - 一般讨论
- 💡 Ideas - 功能建议
- 🙏 Q&A - 问答
- 🎉 Show and Tell - 作品展示

#### 2. GitHub Projects

用于管理开发计划和任务看板。

#### 3. GitHub Wiki

用于详细文档（可选，README 已经很完善）。

---

## 二、Issue 管理最佳实践

### 标签系统

建议创建以下标签：

**类型标签：**
- `bug` - Bug 报告
- `enhancement` - 功能增强
- `documentation` - 文档相关
- `question` - 问题咨询

**状态标签：**
- `good first issue` - 适合新手
- `help wanted` - 需要帮助
- `wontfix` - 不会修复
- `duplicate` - 重复问题

**优先级标签：**
- `priority: high` - 高优先级
- `priority: medium` - 中优先级
- `priority: low` - 低优先级

**组件标签：**
- `sdk` - Python SDK
- `app` - Flutter App
- `firmware` - Arduino 固件

### Issue 处理流程

```
新 Issue → 分类打标签 → 确认/需要更多信息 → 分配 → 开发 → 关闭
```

1. **及时响应** - 24-48 小时内首次回复
2. **友好沟通** - 感谢贡献者的反馈
3. **明确状态** - 使用标签标明进度
4. **关闭说明** - 关闭时说明原因

---

## 三、PR 审核流程

### 审核清单

- [ ] 代码符合项目规范
- [ ] 有适当的测试
- [ ] 文档已更新（如需要）
- [ ] Commit message 规范
- [ ] 没有引入安全问题

### 审核态度

- **建设性反馈** - 指出问题的同时给出建议
- **及时审核** - 不要让 PR 等待太久
- **感谢贡献** - 合并后感谢贡献者

---

## 四、社区运营策略

### 1. 内容输出

| 平台 | 内容类型 | 频率建议 |
|------|----------|----------|
| GitHub | Release Notes | 每次发版 |
| Bilibili | 教程视频 | 每月 1-2 个 |
| 知乎/掘金 | 技术文章 | 每月 1-2 篇 |
| 微信公众号 | 项目动态 | 每周 1 篇 |

### 2. 用户互动

- **回复 Issue** - 及时、友好
- **参与 Discussions** - 积极讨论
- **社交媒体** - 分享用户作品
- **线下活动** - Meetup、Workshop

### 3. 贡献者激励

- **致谢列表** - 在 README 中列出贡献者
- **贡献者徽章** - GitHub 自动显示
- **特别感谢** - Release Notes 中提及
- **社区角色** - 活跃贡献者可成为 Maintainer

---

## 五、优秀社区管理者特质

### 1. 技术能力
- 熟悉项目代码
- 能快速定位问题
- 能给出技术指导

### 2. 沟通能力
- 清晰表达
- 耐心解答
- 友好态度

### 3. 组织能力
- 任务分配
- 进度跟踪
- 文档维护

### 4. 社区意识
- 欢迎新人
- 鼓励贡献
- 处理冲突

---

## 六、常用 GitHub 操作

### 创建 Release

```bash
# 打标签
git tag -a v2.2.0 -m "Version 2.2.0"
git push origin v2.2.0

# 然后在 GitHub 上创建 Release，附上 CHANGELOG 内容
```

### 保护主分支

Settings → Branches → Add rule:
- Branch name pattern: `main`
- Require pull request reviews
- Require status checks

### 自动化 (GitHub Actions)

可以添加：
- 自动测试
- 代码检查
- 自动发布

---

## 七、推荐资源

### 学习资料
- [GitHub 开源指南](https://opensource.guide/zh-hans/)
- [如何维护开源项目](https://opensource.guide/zh-hans/best-practices/)
- [建设友好社区](https://opensource.guide/zh-hans/building-community/)

### 参考项目
- [OpenBot](https://github.com/isl-org/OpenBot) - 原项目
- [Home Assistant](https://github.com/home-assistant/core) - 优秀社区示例
- [Vue.js](https://github.com/vuejs/vue) - 文档和社区管理

---

## 八、下一步行动

1. **立即执行**
   - [ ] 开启 GitHub Discussions
   - [ ] 创建 Issue 标签
   - [ ] 发布第一个正式 Release

2. **短期计划**
   - [ ] 录制入门教程视频
   - [ ] 写一篇介绍文章
   - [ ] 建立交流群（Discord/微信）

3. **长期目标**
   - [ ] 吸引 10+ 贡献者
   - [ ] 建立稳定的用户群
   - [ ] 定期发布更新

---

祝 OpenBene 社区蓬勃发展！🚀
