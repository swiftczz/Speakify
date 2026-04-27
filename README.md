# Speakify

Speakify 是一个基于 SwiftUI 和 SwiftData 构建的 macOS 文本转语音桌面应用，当前接入 ElevenLabs，面向英语听力练习、朗读预览和音频导出场景。

## 功能概览

- 输入英文文本并生成语音
- 从 ElevenLabs 拉取可用模型和声音列表
- 支持应用内播放、暂停和播放进度显示
- 支持将生成结果导出为 mp3 或 wav 文件
- 自动缓存最近生成的音频，重复请求时优先命中本地缓存
- 记录播放和下载历史，并持久化订阅配额快照
- API Key 保存在 macOS Keychain 中

## 技术栈

- Swift 6.2
- SwiftUI
- SwiftData
- AVFoundation
- Swift Package Manager

## 运行环境

- macOS 26+
- 有效的 ElevenLabs API Key

## 快速开始

### 1. 运行开发版本

```bash
swift run --scratch-path build Speakify
```

### 2. 打包 `.app`

```bash
Scripts/package-app.sh
open build/release/Speakify.app
```

打包脚本会自动处理应用图标，并在 `build/release/Speakify.app` 生成可直接启动的应用包。

## 首次配置

启动应用后，打开 Settings 并完成以下配置：

1. 在 `ElevenLabs` 分组中填入 API Key
2. 选择输出格式，当前支持：
	- `mp3_44100_128`
	- `mp3_44100_192`
	- `mp3_22050_32`
	- `wav_44100`
3. 选择下载目录
4. 返回主界面后加载模型和声音

默认下载目录为当前用户的 `Downloads` 目录。

## 当前支持的模型

应用当前内置并优先支持以下 ElevenLabs TTS 模型：

- `eleven_v3`
- `eleven_multilingual_v2`
- `eleven_flash_v2_5`

如果接口返回为空，应用会回退到这组内置模型列表。

## 项目结构

```text
Sources/Speakify/
├── Models/        # 语音、历史记录、配额快照等数据模型
├── Providers/     # TTS Provider 抽象和 ElevenLabs 实现
├── Services/      # 设置、音频播放、Keychain 等服务
├── Support/       # 文件路径和命名等辅助逻辑
├── ViewModels/    # 主业务状态和交互逻辑
└── Views/         # 主界面和设置界面
```

## 数据存储

- API Key：保存在 macOS Keychain
- 历史记录与配额快照：保存在 `~/.speakify/History.store`
- 音频缓存：保存在 `~/.speakify/AudioCache`
- 默认导出目录：用户 `Downloads`，也可在设置中改为其他目录

当前实现会保留最多 100 条历史记录，并清理超过 10 天的音频缓存。

## 测试

运行测试：

```bash
swift test --scratch-path build
```

现有测试主要覆盖：

- 文件名格式化逻辑
- 语音展示字段逻辑
- 历史记录模型行为
- SwiftData 持久化
- 音频时长读取与播放进度

## 扩展说明

虽然当前只接入 ElevenLabs，但 TTS 能力已经通过 `TTSProvider` 抽象隔离。后续如果要接入新的语音服务，通常只需要新增 Provider 实现，而不需要重写现有 UI 和播放流程。
