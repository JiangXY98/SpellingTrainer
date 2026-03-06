# Spelling Trainer ![GitHub release](https://img.shields.io/github/v/release/JiangXY98/SpellingTrainer)

![image-20260306113751870](./assets/image-20260306113751870.png)

A lightweight macOS vocabulary training tool designed for **academic reading workflows**. It allows you to quickly import unfamiliar words (especially from Zotero PDF highlights) and practice spelling using a QWERTY‑Learner–style typing interface.

This project is intentionally implemented as a **single‑file SwiftUI MVP**, making it easy to understand, modify, and extend.

[中文](./doc/中文介绍.md)

## Key features

- **Fast word import from Zotero highlights** — paste copied PDF highlights and automatically extract words and meanings.
- **Typing‑based spelling practice** — practice vocabulary using a QWERTY‑Learner–style typing interface.
- **Two practice modes** — strict spelling mode and copy‑typing mode for different learning stages.
- **Session‑based training** — automatically mixes new words and review words for each practice session.
- **Lightweight local vocabulary database** — all data stored locally in a simple JSON file.
- **Searchable vocabulary list** — quickly locate words and review meanings and practice history.
- **macOS native SwiftUI interface** — fast, minimal, and fully integrated with the macOS UI style.

## Recommended Workflow

Typical usage with Zotero Translation:

```
1. Highlight word in Zotero PDF
2. Copy highlight
3. Click "Paste Zotero"
4. Click "Start Practice"
```

## Installation

You can download the pre‑built application from the GitHub **Releases** page:

https://github.com/JiangXY98/SpellingTrainer/releases

Steps:

1. Open the repository's **Releases** page.
2. Download the latest file named similar to:

```
SpellingTrainer.app.zip
```

3. Unzip the archive to obtain:

```
SpellingTrainer.app
```

4. Move the application to the **Applications** folder.

5. Because the app is not signed with an Apple Developer certificate, macOS may block it on first launch. Run the following command in Terminal:

```
sudo xattr -r -d com.apple.quarantine /Applications/SpellingTrainer.app
```

After this step, the application can be launched normally.

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

[维护指南](./doc/维护指南.md)

---

# Author

**Xiaoyu Jiang**  

PhD Researcher – Consumer Behavior & Neuro‑Decision Science

This tool was originally developed to support vocabulary acquisition during intensive academic reading (especially Zotero‑based literature workflows).

This project intentionally prioritizes:

```
clarity
hackability
low complexity
```

Instead of using CoreData or complex architectures, everything is implemented in **one Swift file**, allowing rapid iteration.

---

# Acknowledgement

This project was inspired by the typing interface of [QWERTY-Learner](https://github.com/RealKai42/qwerty-learner), adapted for personal vocabulary learning and research workflows.

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
