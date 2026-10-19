# 测试快捷键（收尾时必须删除）

仅供开发测试用的"P 键直通宿舍"功能。**项目收尾发布前，删掉下面这些即可，游戏正式流程不受影响。**

## 删除清单（共 4 处，全部标了「【测试专用 · 项目收尾时删除】」）

1. `scripts/prelude/prelude_state.gd` — 删掉 `test_skip_to_dorm_walk()` 整个函数及其注释。
2. `scripts/prelude/prelude_base.gd` — 删掉 `_unhandled_input()` 里 P 键处理那一段（`KEY_P` 分支）。
3. `scripts/ui/title_screen.gd` — 删掉 `_unhandled_input()` 里 P 键处理那一段。
4. 本文件 `TEST_HOTKEY_REMOVE.md` — 删除。

## 快捷键说明

- **按键：P**（不能按 F8：F8 是 Godot 编辑器"停止运行"的默认快捷键，编辑器会先截走，导致一按就退出整个测试）。
- **作用**：在任何对话/解密/标题画面按 P，直接进入宿舍走位（dorm_room，带背景图的寝室）。
- 不写存档、不改进度标记，测完随时回到正式流程。

## 为什么会有这个功能

开发期间每次测试都要重跑"六关解密（含 JAPAN 凯撒密码那关）+ 前日谈"才能到宿舍，太慢。
这是给开发者的便捷通道，不属于游戏内容。
