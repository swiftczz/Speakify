# Speakify

Speakify 是一个基于 SwiftUI 和 SwiftData 构建的 macOS 文本转语音桌面应用，支持 ElevenLabs 和小米 MiMo 两个语音服务，面向英语听力练习、朗读预览和音频导出场景。

## 功能概览

- 输入文本并生成语音，主界面工具栏可一键切换 ElevenLabs / Xiaomi MiMo
- ElevenLabs：在线拉取模型和声音列表；MiMo：内置 TTS v2.5 模型与 9 个预置音色（含中文音色）
- 每个服务独立保存 API Key、模型和输出格式，切换互不影响
- 支持应用内播放、暂停和播放进度显示
- 支持将生成结果导出音频；ElevenLabs 同步下载精确对齐的 SRT 字幕（MiMo 不提供对齐数据，仅导出音频）
- 自动缓存最近生成的音频，重复请求时优先命中本地缓存
- 记录播放和下载历史，并持久化订阅配额快照（仅 ElevenLabs 提供配额）

## 技术栈

- Swift 6.2
- SwiftUI
- SwiftData
- AVFoundation
- Swift Package Manager

## 运行环境

- macOS 26+
- 有效的 ElevenLabs API Key 或小米 MiMo API Key（至少其一）

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

1. 在 `Speech Service` 分组中选择服务（ElevenLabs 或 Xiaomi MiMo）
2. 在 `API Keys` 分组中填入对应服务的 API Key（两个服务的 Key 可同时保存）
3. 选择输出格式：
	- ElevenLabs：`mp3_44100_128`、`mp3_44100_192`、`mp3_22050_32`、`wav_44100`
	- Xiaomi MiMo：`wav`（24 kHz）
4. 选择下载目录
5. 返回主界面后加载模型和声音

默认下载目录为当前用户的 `Downloads` 目录。

## 当前支持的模型

ElevenLabs（接口返回为空时回退到这组内置列表）：

- `eleven_v3`
- `eleven_multilingual_v2`
- `eleven_flash_v2_5`

Xiaomi MiMo（固定目录，无需网络请求）：

- `mimo-v2.5-tts`，预置音色：`mimo_default`、`冰糖`、`茉莉`、`苏打`、`白桦`、`Mia`、`Chloe`、`Milo`、`Dean`

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

TTS 能力通过 `TTSProvider` 协议隔离：每个 Provider 声明自己的 `TTSProviderCapabilities`（输出格式、是否提供配额、是否支持 SRT 字幕、是否接受语言提示），UI 与视图模型据此自适应。接入新的语音服务只需：

1. 新增一个 `TTSProvider` 实现（参考 `MiMoProvider`）
2. 将其加入 `TTSProviderRegistry.providers`

无需改动现有 UI、设置存储和播放流程。
