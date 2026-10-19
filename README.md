# MCHOSE Mac

MCHOSE（迈从）Ace 68 Turbo 16K 键盘的 **macOS 原生配置工具**（个人自用，不分发、不上架）。

官网驱动 `mchose.com.cn` 是 Vue + WebHID 的网页应用，Safari 不支持 WebHID。本项目直接通过 IOKit 打开厂商 HID 配置接口，用 Swift + SwiftUI 重写只读查询和常用写入功能，运行时完全离线。

## 当前能力

| 功能 | 状态 |
|---|---|
| 设备枚举 / 识别 / getInfo（型号、固件、构建日期） | ✅ 实机验证 |
| 磁轴触发点 / RT / 死区读取与写入 | ✅ 实机验证 |
| 改键（HID usage 映射）读取与写入 | ✅ 实机验证 |
| 灯效（主灯/侧灯的模式、亮度、速度、颜色）读取与写入 | ✅ 亮度 0–100、速度 0–4 已与官方 Web UI 对齐；实机写入链路已验证 |
| 配置档切换（base 声明 3 个活动档，最多 4 档） | ✅ 实机验证 |
| 随前台应用自动切换配置档（菜单栏常驻） | ✅ 已实现，带 350ms 去抖 |
| 应用前自动快照 / 一键恢复 | ✅ 已实现 |
| 热插拔 / 睡眠唤醒自动重连 | ✅ 已实现（监听配置接口增删 + 唤醒刷新） |
| 宏 / SOCD / 导入导出 / 逐键灯效 / GIF / 音乐律动 | ❌ 未实现（Phase 2） |
| 固件 OTA / boot 模式 / 多型号 | ❌ 不做（见设计文档非目标） |

目标设备：**MCHOSE Ace 68 Turbo 16K**（VID `0x3837` / PID `0x3026`，boot PID `0x3027`）。其他型号仅保留清单结构，未经实机验证。

## 目录结构

```text
Sources/
  HIDTransport/   IOKit 枚举、打开配置接口、报告收发、热插拔监听、专用 I/O 线程
  Protocol/       CZ 协议编解码、分页组装、命令会话（含 dry-run）
  Features/       设备清单、getInfo、磁轴、键位、灯效、配置档、快照、连接封装
  MCHOSECLI/      诊断 CLI（只读默认）
App/Sources/      SwiftUI 应用（窗口 + 菜单栏）
Resources/DeviceManifests/  设备清单 JSON
Tests/            单元测试（Swift Testing）
Tools/extract-manifest/     从官网 bundle 提取设备清单（离线构建步骤）
docs/             设计规格、阶段计划、协议抓包
```

依赖方向：`App → Features → Protocol → HIDTransport`。

## 构建与运行

要求：macOS 13+、Xcode 15+（或 Swift 5.9+ 工具链）、[XcodeGen](https://github.com/yonaskolb/XcodeGen)（仅构建 App 需要）。

```bash
# 包构建 + 测试
swift build
swift test

# 生成 Xcode 工程并构建 App（工程文件不入库，由 project.yml 生成）
xcodegen generate
xcodebuild -project MCHOSEMac.xcodeproj -target MCHOSEMac -configuration Debug build

# 或直接打开 Xcode
open MCHOSEMac.xcodeproj
```

> 如果在受限沙箱（如某些 AI agent 环境）里构建，SwiftPM 自身的 sandbox 可能无法启动，需要给命令加 `--disable-sandbox`。

## CLI 用法

```text
mchose-cli <command> [options]

安全选项（默认 read-only）：
  --read-only    只发读命令（默认）
  --allow-write  允许写入
  --dry-run      只编码写入、不真正发送

命令：
  list                       枚举配置接口（只匹配配置接口，不打开键盘接口）
  open                       打开配置接口
  watch [seconds]            监听热插拔 add/remove 事件（默认 5 秒）
  monitor                    打印 10 秒原始输入报告
  info <reportId-hex>        发送 getInfo 并打印响应
  probe                      读取信息 / 磁轴 / 键位 / 灯效 / 配置档
  readraw <cmd> <off> <len>  按任意命令读取原始字节
  snapshot [path]            保存可恢复快照（JSON）
  restore [path]             恢复最近（或指定）快照
  switchprofile <n>          切换配置档（需要 --allow-write）
  selfcheck                  读回原值、写回、再比对（需要 --allow-write）
```

示例：

```bash
swift run mchose-cli probe                 # 纯只读
swift run mchose-cli snapshot              # 写前快照
swift run mchose-cli selfcheck --allow-write
swift run mchose-cli restore --allow-write # 恢复最近快照并逐段回读校验
```

## 安全模型

- **默认只读**：CLI 不带 `--allow-write` 时不发送任何写命令；App 可用 `--read-only` 锁定为只读（`open -a MCHOSEMac --args --read-only`），`--dry-run` 只编码不发送。
- **写前快照**：CLI `snapshot`、App 每次应用设置前都会保存当前磁轴/键位/func config/base 到 `~/Library/Application Support/MCHOSE Mac/Snapshots/`。
- **回读校验 + 回滚**：每次写入后立即回读比对，不一致时自动写回旧值并报错（`DeviceConnection.apply*`）。
- **快照恢复**：`restore` / App 的“恢复上次快照”会逐段写入并校验。快照记录来源配置档，恢复时写回同一档。
- 设计细节见 `docs/superpowers/specs/2026-10-18-mchose-mac-design.md` 第 10 节。

## 协议要点

- 所有读取都带逻辑地址：键位 `512 * (4 * profile + layer)`（有效区 384 字节）、磁轴 `1024 * profile`、func config/灯效 `64 * profile`、base `0`。分页读取时每页 offset 递增，响应会回显该 offset。
- 写入分块与官方 SDK 一致：键位 54 字节/块、磁轴与 func config 56 字节/块，最后一块数据不足时按 SDK 的方式回退 offset 重叠发送。
- 以上地址公式与灯效字段（亮度 0–100、速度 0–4）均已对照官方 Web 驱动 bundle 与实机只读读取验证，详见 `docs/captures/ace68-feature-protocol.md`。

## 已知限制

- 仅支持 Ace 68 Turbo 16K；其他型号未实机验证。
- 快照只覆盖当前配置档的第 0 层键位（FN 层、宏、逐键灯效未纳入）。
- 设备发现只枚举 MCHOSE 厂商的配置接口（`usagePage 0x01/0x00` 或 `0xFF00/0x01`），因此 `list` 看不到键盘/鼠标等其他 HID 接口；这是为了避免打开受保护键盘接口触发“输入监控”授权请求。
- App 的设备 I/O 在专用 run-loop 线程执行，主线程只更新 UI；CLI 仍是单线程同步。
- 新构建的二进制首次运行时，系统代码签名/TCC 校验可能让首轮扫描多花 2–3 秒；之后的启动正常。
- 自动切档会写 base 结构（是否写 flash 待确认），已加去抖，但仍建议不要高频触发。
- 应用未签名、未公证，仅本地自用。

## 协议与逆向资料

- `docs/captures/ace68-phase0.md`：连接、打开接口、getInfo 抓包
- `docs/captures/ace68-getinfo-fields.md`：getInfo payload 字段映射
- `docs/captures/ace68-feature-protocol.md`：CZ 帧格式、命令表、磁轴/键位/灯效/配置档编码
- `docs/superpowers/specs/`、`docs/superpowers/plans/`：设计规格与 Phase 0/1a 计划

## 免责声明

本项目与 MCHOSE 官方无关，仅用于个人设备的本地互操作。写设备有风险（配置丢失/异常），请先 `snapshot`；不实现 OTA，避免刷砖。不重新分发厂商素材或固件。
