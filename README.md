# GlobalTrans

macOS 菜单栏应用：框选屏幕，本地 OCR，再翻译。识别与翻译都在本机完成，不经过云端。

需要 **macOS 15+** 和 **Apple Silicon**。

## 特性

- 常驻菜单栏，快捷键 **⌥⌘O** 截取区域；也可 **Open File** 导入本地图片或 PDF
- 截图只入队，最多 5 张；OCR 和翻译由你手动点
- 本地 MLX 推理：OCR 出 Markdown（含公式、表格），翻译走 Hy-MT2
- 结果可预览 Markdown / 源文本，支持多段 OCR 合并后再译
- 可选对接本机或局域网的 OpenAI 兼容接口

## 安装

1. 打开 [Releases](https://github.com/DerekChin12138/GlobalTrans/releases) 里的 `GlobalTrans-*.dmg`，把应用拖进 Applications。
2. 自行下载下面两个模型文件夹，放到应用能找到的位置（**不会打进 DMG**）：
   - 和应用放在同一目录
   - 同一目录下的 `Models/`
   - 或 `~/Applications`
3. 第一次截图时允许屏幕录制。

菜单栏面板里的 **Models…** 也可以手动指定路径。

## 推荐模型

| 用途 | 文件夹名 | 来源 |
| --- | --- | --- |
| OCR | `OvisOCR2-4bit` | [mlx-community/OvisOCR2-4bit](https://huggingface.co/mlx-community/OvisOCR2-4bit)（[ATH-MaaS/OvisOCR2](https://huggingface.co/ATH-MaaS/OvisOCR2) 的 4-bit MLX 量化） |
| 翻译 | `Hy-MT2-1.8B-4bit` | [mlx-community/Hy-MT2-1.8B-4bit](https://huggingface.co/mlx-community/Hy-MT2-1.8B-4bit)（[tencent/Hy-MT2-1.8B](https://huggingface.co/tencent/Hy-MT2-1.8B) 的 4-bit MLX 量化） |

每个文件夹里需要有 `config.json` 和 `model.safetensors`。

## 数据放在哪

- 截图 JPEG 写在 `~/Library/Caches/app.globaltrans.ocr/shots/`（最多 5 张）。启动时清空该目录，删掉条目时删除对应文件
- 识别 / 翻译文本只留在内存，退出即消失
- 模型权重由你自己下载、自己删除
- 删掉 `GlobalTrans.app` 即卸装干净

macOS 还会留下一份很小的偏好设置（目标语言、OCR 精度、可选的远程 API Key）以及屏幕录制授权。

## 内存

空闲大约 35MB。截图框选不再每次泄漏一整屏 backing store；JPEG 原图走磁盘、列表只用缩略图。

本地 OCR / 翻译会把模型载入统一内存，推理时峰值会到 1GB 以上。几次 OCR → 翻译后，进程 RAM 通常稳定在约 **400MB+**，不再随次数线性上涨（Metal / mmap 残留）。清空全部截图会立刻卸载模型。
