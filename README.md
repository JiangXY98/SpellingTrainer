# Spelling Trainer

A lightweight macOS vocabulary training tool designed for **academic reading workflows**. It allows you to quickly import unfamiliar words (especially from Zotero PDF highlights) and practice spelling using a QWERTY‑Learner–style typing interface.

This project is intentionally implemented as a **single‑file SwiftUI MVP**, making it easy to understand, modify, and extend.


## Recommended Workflow

Typical usage with Zotero:

```
1. Highlight word in Zotero PDF
2. Copy highlight
3. Click "Paste Zotero"
4. Click "Start Practice"
```

---

# Core Features

## Vocabulary Management

The left sidebar maintains your vocabulary list.

Capabilities:

• Add words manually (`+` button)
• Delete words via right‑click
• Search vocabulary
• View detailed popup information

Each vocabulary item stores:

```
word
meaning
source
sourceURL
attemptCount
correctCount
wrongCount
intervalDays
difficulty
nextReviewAt
createdAt
lastTrainedAt
```

Vocabulary data is stored locally as JSON.

---

# Importing Words

## 1. Zotero Quick Import

Click **Paste Zotero** to parse text copied from Zotero PDF highlights.

Supported patterns:

### Pattern A

```
“satisfactory” (...) "satisfactory 英 ... adj. 令人满意的"
```

Result:

```
word: satisfactory
meaning: adj. 令人满意的
```

### Pattern B

```
“Choice optimality” (...) 🔤选择最优性🔤
```

Result:

```
word: Choice optimality
meaning: 选择最优性
```

Duplicate word handling depends on:

```
Merge meaning on import/upsert
```

Enabled → append meaning

Disabled → overwrite meaning

---

## 2. CSV Import

You can also import from CSV.

Example format:

```
word,meaning
salience,显著性
abstinence,戒断
```

Supported headers:

```
word
meaning
definition
trans
```

---

# Practice Modes

## Strict Mode (default)

Displays the meaning and requires you to **type the exact word**.

Behavior:

• Press Return to submit
• Incorrect answers require immediate retyping
• Wrong words are reinserted into the queue after a delay

---

## Copy Mode

Designed for learning new words or improving typing speed.

Features:

• Ghost text overlay
• Real‑time prefix matching
• Error underline

Visual feedback:

```
correct prefix → darker
first error → red underline
remaining text → light
```

Submission still requires pressing Return.

---

# Session Scheduling

Session size is controlled by **Settings**.

Parameters:

```
maxNewPerSession
maxReviewPerSession
```

Definitions:

```
New word    = attemptCount == 0
Review word = attemptCount > 0
```

Session queue logic:

```
queue = newBatch + reviewBatch
```

Where:

```
newBatch    = min(dueNew, maxNewPerSession)
reviewBatch = min(dueReview, maxReviewPerSession)
```

If no words are due:

```
random sample = maxReviewPerSession
```

Incorrect words reappear after:

```
recycleDelay = 4
```

---

# Session Controls

Main page buttons:

```
Start Practice
Stop
```

Stop behavior:

• Ends current session
• Preserves session statistics
• Shows session summary
• Returns to start screen

Session summary includes:

```
Attempts
Accuracy
WPM
Streak
```

---

# Statistics

Top status bar shows:

```
Accuracy
WPM
Streak
```

Per‑word statistics:

```
correctCount
wrongCount
lastTrainedAt
```

---

# Data Storage

Vocabulary file:

```
~/Library/Application Support/SpellingTrainer/vocab.json
```

---

# Automatic Backups

Every save creates a backup copy:

```
~/Library/Application Support/SpellingTrainer/Backups/
```

Backup naming:

```
vocab_YYYYMMDD_HHMMSS.json
```

Retention policy:

```
20 most recent backups
```

Older backups are automatically removed.

---

# iCloud Sync (Optional)

You can enable **iCloud Sync** in the sidebar.

When enabled:

```
vocab.json
```

is stored in:

```
iCloud Drive
Documents/SpellingTrainer/
```

Now iCloud is unavailable, the app automatically falls back to local storage.

---

# Export

Two export formats are available.

## Export CSV

Contains:

```
word
meaning
source
sourceURL
attemptCount
correctCount
wrongCount
intervalDays
difficulty
nextReviewAt
createdAt
lastTrainedAt
```

---

## Export JSON

Exports the complete vocabulary structure.

Recommended for:

• full backups
• migrations
• data analysis

---

# Settings

Open:

```
Spelling Trainer → Settings
```

Adjust:

```
Max new per session
Max reviews per session
```

Default values:

```
10 new
30 review
```

---

# Building the App

If you clone this project from GitHub, the typical repository structure will look like:

```
SpellingTrainer
├── SpellingTrainer
    └── SpellingTrainerApp.swift
    │
    ├── Assets.xcassets
    ├── README.md
    ├── LICENSE
    └── .gitignore
```

Requirements:

```
macOS
Xcode
SwiftUI
```

Steps:

```
1. Open project in Xcode
2. Select "My Mac" target
3. Product → Build
```

The compiled application will appear in:

```
Build/Products/Release/SpellingTrainer.app
```

You can move it to:

```
/Applications
```

---

# Current Design Philosophy

This project intentionally prioritizes:

```
clarity
hackability
low complexity
```

Instead of using CoreData or complex architectures, everything is implemented in **one Swift file**, allowing rapid iteration.

---

# Author

**Xiaoyu Jiang**  

PhD Researcher – Consumer Behavior & Neuro‑Decision Science

This tool was originally developed to support vocabulary acquisition during intensive academic reading (especially Zotero‑based literature workflows).

---

# Acknowledgement

This project was inspired by the typing interface of **QWERTY‑Learner**, adapted for personal vocabulary learning and research workflows.

---

If you find this tool useful, feel free to fork the repository and adapt it to your own workflow.

---

# License

This project is currently released under the **MIT License**.

The MIT license allows anyone to:

• use the software
• modify the source code
• redistribute the project
• incorporate it into other projects

while preserving attribution to the original author.

You can find the full license text in the `LICENSE` file in this repository.
