# Spelling Trainer Wiki

本页从 `README.md` 抽取并整理了使用层面的核心信息，便于快速查阅。

## 项目简介

Spelling Trainer 是一个轻量级 macOS 词汇训练工具，面向学术阅读场景（尤其是 Zotero PDF 高亮导词流程），采用类 QWERTY-Learner 的拼写输入练习方式。

## 核心功能

### 词库管理

左侧边栏支持：
- 手动添加单词（`+`）
- 右键删除
- 搜索词汇
- 查看词条详情

每个词条包含如下字段：
- `word`
- `meaning`
- `source`
- `sourceURL`
- `attemptCount`
- `correctCount`
- `wrongCount`
- `intervalDays`
- `difficulty`
- `nextReviewAt`
- `createdAt`
- `lastTrainedAt`

### 导入词汇

#### 1) Zotero 快速导入
点击 **Paste Zotero** 可解析 Zotero PDF 高亮复制文本。

支持两类常见模式：
- 模式 A：从引号中的单词与释义片段提取 `word + meaning`
- 模式 B：从高亮标记文本中提取 `word + meaning`

重复词处理受设置项控制：
- 开启 `Merge meaning on import/upsert`：追加释义
- 关闭：覆盖释义

#### 2) CSV 导入
示例格式：

```csv
word,meaning
salience,显著性
abstinence,戒断
```

支持表头：
- `word`
- `meaning`
- `definition`
- `trans`

## 练习模式

### Strict Mode（默认）
- 根据释义输入完整单词
- 回车提交
- 错误后需立即重输
- 错词会延迟回到队列

### Copy Mode
适合新词熟悉和打字速度训练：
- 幽灵文本（ghost text）
- 实时前缀匹配
- 错误下划线提示
- 仍需回车提交

## 会话与调度

设置项：
- `maxNewPerSession`
- `maxReviewPerSession`

定义：
- 新词：`attemptCount == 0`
- 复习词：`attemptCount > 0`

队列逻辑：
- `queue = newBatch + reviewBatch`
- `newBatch = min(dueNew, maxNewPerSession)`
- `reviewBatch = min(dueReview, maxReviewPerSession)`

当无到期词时：
- 随机抽样 `maxReviewPerSession`

错词回收延迟：
- `recycleDelay = 4`

### 会话控制
主按钮：
- `Start Practice`
- `Stop`

`Stop` 行为：
- 结束当前会话
- 保留会话统计
- 展示总结
- 返回开始界面

会话总结包含：
- Attempts
- Accuracy
- WPM
- Streak

## 统计信息

顶部状态栏：
- Accuracy
- WPM
- Streak

词级统计：
- `correctCount`
- `wrongCount`
- `lastTrainedAt`

## 数据存储与备份

词库文件：
- `~/Library/Application Support/SpellingTrainer/vocab.json`

自动备份目录：
- `~/Library/Application Support/SpellingTrainer/Backups/`

命名格式：
- `vocab_YYYYMMDD_HHMMSS.json`

保留策略：
- 保留最近 20 份，旧备份自动删除

## iCloud 同步（可选）

开启后，`vocab.json` 存于：
- iCloud Drive / `Documents/SpellingTrainer/`

若 iCloud 不可用，自动回退本地存储。

## 导出

### CSV 导出
包含完整词条统计字段（与词条结构对应）。

### JSON 导出
导出完整词库结构，适合：
- 全量备份
- 迁移
- 数据分析

## 设置

入口：
- `Spelling Trainer -> Settings`

可调参数：
- Max new per session
- Max reviews per session

默认值：
- 10 new
- 30 review

## 构建

要求：
- macOS
- Xcode
- SwiftUI

步骤：
1. 在 Xcode 打开项目
2. 选择 `My Mac`
3. `Product -> Build`

## 设计理念

项目当前强调：
- 清晰
- 易改
- 低复杂度

目前为单文件 SwiftUI MVP，便于快速迭代。
