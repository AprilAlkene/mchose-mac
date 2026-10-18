# MCHOSE Mac 原生配置应用 — 设计规格

- 日期：2026-10-18
- 状态：Draft，待用户评审
- 项目路径：`~/mchose-mac`
- 使用场景：个人自用（不分发、不上架、不做自动更新）
- 目标设备：Ace 68 Turbo 16K（已实测）；架构支持设备清单中的其他型号，未实测型号标记为 experimental

---

## 1. 背景与调研结论

### 1.1 网页版是什么

`https://www.mchose.com.cn/#/connectDevice` 是迈从的 M HUB 网页驱动：

- 前端：Vue 3 + Element Plus + Pinia 的 SPA
- 设备通信：纯 WebHID，使用 `navigator.hid.requestDevice/getDevices`、`sendReport`、`receiveFeatureReport`
- 设备库与协议 SDK：运行时从 `/cizhou/CZ_SHARED_DATA/` 动态加载，包含每个型号的布局、键位、灯效、能力位和固件地址
- 桌面端：代码中存在 `isInElectron()`、`iframeBridge`、窗口状态同步，说明官方 Windows 客户端是 Electron 套壳同一套网页
- 明确仅限 PC 的能力：音频 EQ（`audioEqPcDriverOnly`）

### 1.2 设备与 HID 接口

当前实测设备：

| 项目 | 值 |
|---|---|
| 型号 | MCHOSE Ace 68 Turbo 16K |
| 正常模式 VID/PID | `0x3837 / 0x3026` |
| 设备库 boot 模式 PID | `0x3027` |
| 常驻 VID | `0x19F5`、`0x3837`；boot/OTA 模式为 `0x41E4` |
| 配置接口 | `usagePage 0x01 / usage 0x00`，64 字节 IN/OUT |
| 标准键盘接口 | `usagePage 0x01 / usage 0x06`，受系统保护 |

只读探针结果（macOS 27，Apple Silicon）：

```text
Ace 68 Turbo 16K usagePage=0x1 usage=0x0 in=64 out=64 open=0x0        ← 配置接口可打开
Ace 68 Turbo 16K usagePage=0x1 usage=0x6 in=16 out=1  open=0xE00002E2 ← 系统保护，正常
Ace 68 Turbo 16K usagePage=0x1 usage=0x6 in=8  out=1  open=0xE00002E2 ← 系统保护，正常
```

结论：**用户态 App 直接通过 IOKit 打开厂商配置接口即可，不需要 root、内核扩展或 DriverKit。**

### 1.3 为什么做原生

- WebHID 只在 Chromium 系浏览器可用（Chrome/Edge/Opera）；Safari 不支持
- 当前机器装有 Edge，网页版大概率可用；但原生 App 可以提供离线、菜单栏常驻、随应用切换配置、更稳定的设备生命周期管理
- 已验证原生打开配置接口成功，技术路径成立

### 1.4 协议层现状

网页中存在两代协议：

1. **QHW 旧协议**
   - 默认 report ID：`0x4D`（77），音乐律动为 `0x4E`（78）
   - 7 字节帧头：`[version=1, flags=3, length, command_hi, command_lo, bizCode, sequence]`
   - payload + 校验字节
   - 普通包最大 31 字节，boot 包最大 63 字节
   - payload 上限 = 包长 - 7 - 1，即普通 23、boot 55

2. **CZ 新协议**
   - 通过 `buildReportData({ cmdType, cmd, payload, check })` 构造
   - 命令类型：`Request`、`Set`、`Response`、`Notify`
   - 使用 `cmdOffset`、`getPayloadValue`、`getLength` 等辅助函数解析
   - Ace 68 Turbo（设备库 `type: 211`）走这一代协议

**Phase 0 已确认（2026-10-18）：**

- 配置接口 report ID `0`；请求 flag `0x55`，响应 flag `0xAA`
- `getInfo` 请求：64 字节 `55 03 00 38 38 00 00 00` + 56 个 `0x00`
- `getInfo` 响应头：`[flag, command, ?, ?, length, offset_lo, offset_hi, ?]`，payload 从偏移 8 开始；本次 `length=27`、`offset=0`
- payload：`26 01 FF FF FF FF 00` + ASCII 构建日期 `Jul 21 2026,15:16:19`
- 该命令未观察到校验和；最后字节为 `0x00`
- 读取基础信息的最小命令：command `0x03`（getInfo）
- 已验证：`mchose-cli info 0` 与网页 SDK 返回一致；网页 SDK 解析出 `fw_ver=126`、`rffw_ver=ffff`、`collabType=255`

---

## 2. 目标与非目标

### 2.1 目标

1. 原生 SwiftUI 应用，离线可用，不依赖厂商网站
2. 已验证设备上完整支持：
   - 设备信息（型号、固件、电量/连接模式如有）
   - 磁轴触发/RT/死区
   - 改键、FN 层、宏、SOCD
   - 灯效（静态、亮度、模式、逐键颜色）
   - 多配置档、导入导出、随前台应用切换
3. 设备清单驱动，新增型号主要增加清单和适配器，不改核心
4. 所有写入可回读验证，应用前自动快照，失败可恢复
5. 拔插、睡眠唤醒、boot 模式都有明确状态处理

### 2.2 非目标（v1）

- 音频耳机/EQ（网页已声明仅 PC）
- 鼠标功能（当前没有可测鼠标，仅保留接口）
- 多设备同时连接（v1 只支持一个活动设备；注册表可登记多个）
- 固件 OTA（单独设计，v1 不实现）
- 音乐律动实时推流、GIF 灯效编辑（后续阶段）
- App Store、公证、自动更新、多语言（默认简体中文）

---

## 3. 用户与场景

唯一用户即设备所有者，典型场景：

1. 插上键盘，打开 App，看到当前磁轴、键位、灯效、配置档
2. 调触发点/RT，松手后写入，回读确认
3. 改几个键，保存到当前配置档
4. 给不同前台 App 绑定不同配置档，切换时自动生效
5. 改坏了，点“恢复应用前快照”

---

## 4. 架构

平台：macOS 13+，Apple Silicon 优先；SwiftUI + Swift Concurrency；本地构建，不启用 App Sandbox。

### 4.1 模块

| 模块 | 职责 | 依赖 |
|---|---|---|
| `HIDTransport` | IOKit 枚举、热插拔、打开配置接口、报告收发、权限错误映射 | IOKit |
| `DeviceRegistry` | 设备清单加载、运行时识别、能力位、布局/灯效矩阵资源 | Foundation |
| `Protocol` | QHW/CZ 编解码、分包、校验、命令队列、超时重试 | HIDTransport |
| `Features` | 设备信息、磁轴、键位、宏/SOCD、灯效、配置档 | Protocol、DeviceRegistry |
| `MCHOSEMacApp` | SwiftUI 界面、菜单栏、随应用切换、快照/恢复 | Features |
| `MCHOSECLI` | Phase 0 协议验证与只读诊断工具 | HIDTransport、Protocol |

依赖方向：`App → Features → Protocol → HIDTransport`，`DeviceRegistry` 作为数据源被 Features 和 App 使用。Features 不直接调用 IOKit。

### 4.2 并发模型

- IOKit 回调运行在专用 RunLoop 线程
- `HIDTransport` 用 continuation 把回调桥接为 async
- `DeviceSession` 是 actor，串行化所有命令
- 命令队列一次只允许一个在途命令；读写都带超时
- UI 在 `@MainActor`；应用配置时禁用相关控件
- 随应用切换使用合并/去抖，避免快速切换导致命令堆积

### 4.3 文件布局

```text
~/mchose-mac/
  MCHOSEMac.xcodeproj
  Package.swift
  Sources/
    HIDTransport/
    DeviceRegistry/
    Protocol/
    Features/
    MCHOSEMacApp/
    MCHOSECLI/
  Resources/
    DeviceManifests/
      ace68_turbo_16k.json
    Layouts/
  Tests/
    HIDTransportTests/
    ProtocolTests/
    DeviceRegistryTests/
  Tools/
    extract-manifest/        # 从网页 bundle 提取设备清单（离线构建步骤）
  docs/
    superpowers/specs/2026-10-18-mchose-mac-design.md
```

---

## 5. 数据模型

### 5.1 DeviceManifest

以下数值是 schema 示例，Phase 0 必须用网页设备库和设备读回的真实值替换；不得把示例值当作真实范围。

```json
{
  "id": "ace68-turbo-16k",
  "displayName": "Ace 68 Turbo 16K",
  "protocolFamily": "cz",
  "identities": [
    { "vendorId": 14391, "productId": 12326, "mode": "normal" },
    { "vendorId": 14391, "productId": 12327, "mode": "boot" }
  ],
  "configInterface": { "usagePage": 1, "usage": 0, "maxReportSize": 64 },
  "capabilities": {
    "magnetic": true,
    "keymap": true,
    "macros": true,
    "socd": true,
    "lighting": true,
    "perKeyLighting": true,
    "gifLighting": false,
    "musicSync": false,
    "battery": false
  },
  "profileSlots": 3,
  "macroSlots": 16,
  "layoutAsset": "Layouts/ace68_turbo_16k.json",
  "lightingMatrix": { "rows": 5, "cols": 16 },
  "ranges": {
    "actuationMm": { "min": 0.1, "max": 4.0, "step": 0.01 },
    "rtMm": { "min": 0.05, "max": 2.0, "step": 0.01 }
  },
  "verified": true
}
```

说明：

- `verified` 表示是否有实机验证；未实测型号必须为 `false`
- `profileSlots`、`macroSlots`、`ranges` 的真实值由 Phase 0 从网页设备库和设备读回后填入；上面的数字仅用于示意 schema
- `layoutAsset` 来自网页按型号加载的布局 chunk，需转换为应用内 JSON

### 5.2 DeviceSnapshot

一次读取后的完整状态：设备信息、当前配置档、键位、磁轴、灯效、宏、读取时间。用于渲染、diff 和恢复。

### 5.3 AppProfileMapping

```json
{
  "bundleId": "com.apple.Terminal",
  "profileSlot": 1
}
```

存储在 `~/Library/Application Support/MCHOSE Mac/profiles.json`。

---

## 6. 数据流

### 6.1 连接与识别

```text
IOHIDManager 枚举（0x19F5 / 0x3837 / 0x41E4）
  → 过滤接口（正常 0x01/0x00；boot 0xFF00/0x01）
  → IOHIDDeviceOpen（不 seize）
  → 读取基础信息
  → 匹配 DeviceManifest
      ├─ known + verified → 可读写
      ├─ known + experimental → 只读，提示未验证
      ├─ unknown → 只读展示，记录 VID/PID/描述符
      └─ boot → 仅提示，不写
```

同型号多接口只选配置接口；标准键盘接口打开失败视为正常。

### 6.2 读取

```text
读取当前槽位
  → 并行/串行读取：键位、磁轴、灯效、宏
  → 组装 DeviceSnapshot
  → 缓存并渲染
```

读取失败不回滚、不写入；UI 标出具体失败项。

### 6.3 编辑与应用

```text
UI 编辑 draft
  → 按 DeviceManifest 的 ranges/capabilities 校验
  → 标脏
  → 用户点“应用”
  → 保存应用前快照
  → diff 出需要写入的项
  → 编码 → 分包 → 单队列发送 → 等 ACK
  → 回读比对
      ├─ 一致 → 提交 draft
      └─ 不一致 → 重试 1 次 → 仍失败则保留旧快照并报错
```

滑块类参数在松手或 300ms 去抖后写入；不做每个像素实时写。

### 6.4 配置档与随应用切换

1. 设备支持板载多槽：切换命令只切当前槽，速度快、不写 flash
2. 不支持多槽：主机侧写配置，300–500ms 去抖
3. 监听 `NSWorkspace.didActivateApplicationNotification`
4. 忽略自身、系统弹窗、无 bundle ID 的进程
5. 快速连续切换只保留最后一个目标
6. 菜单栏提供“暂停自动切换”和当前配置档指示
7. 随应用切换要求 App 常驻菜单栏；退出 App 后不生效

### 6.5 断开与重连

- 断开：取消在途命令、标记 offline、保留最后状态
- 重连：重新识别、重新读取、不自动重放未完成的写操作
- 若断开发生在写入中：标记 dirty，提示“重新应用”

---

## 7. 协议层

### 7.1 抽象

```swift
protocol ReportCodec {
    func encode(_ command: DeviceCommand) throws -> [HIDPacket]
    func decode(_ report: [UInt8]) throws -> DeviceResponse
}
```

- `HIDPacket`：report ID + bytes
- `DeviceCommand`：command id + payload + expectsResponse
- `DeviceResponse`：command id + payload + status

### 7.2 QHW 编解码

- Report ID：`0x4D`；音乐律动 `0x4E`
- 帧头：7 字节
- 分包：普通 23 字节 payload、boot 55 字节 payload
- 校验：对帧头+payload 求和取低 8 位（精确拼接位置 Phase 0 用网页日志确认）
- 序列号：8 位循环
- 响应匹配：command + sequence；非匹配帧作为通知处理

### 7.3 CZ 编解码

- 按 `cmdType/cmd/payload` 构造
- 需要移植 `CmdType`、`buildReportData`、`getPayloadValue`、`getLength`、校验逻辑
- Ace 68 Turbo 使用该协议；Phase 0 用只读命令确认 report ID、帧格式和命令码

### 7.4 命令队列

- 每设备一个 actor 队列
- 默认超时 1s，读重试 3 次，写重试 1 次 + 回读
- 优先级：用户写 > 后台读 > 轮询
- 支持取消；断开时清空队列并拒绝新命令
- 失败统一抛 `MCHOSEError`

---

## 8. 功能规格

### 8.1 设备信息

- 型号、固件版本、当前连接模式、电量（如设备支持）
- 配置档数量、当前槽位
- 只读；失败不影响其他功能

### 8.2 磁轴触发/RT

- 全局与逐键：触发点、按下 RT、抬起 RT、死区
- 范围、步进来自 `DeviceManifest.ranges`
- 松手/去抖后写入；回读校验
- 提供“恢复默认”

### 8.3 改键/宏/SOCD

- 改键：基于布局 JSON 的矩阵映射；支持 FN 层
- 宏：按键序列 + 延迟，写入设备宏槽；槽数来自清单
- SOCD：成对方向键策略；按设备能力位显示
- 冲突校验：同一物理键不能映射到多个逻辑键；宏长度、槽位上限

### 8.4 灯效

- v1：模式、亮度、速度、方向、颜色、逐键静态色
- 后续：GIF 上传（网页上限 36,800 字节）、音乐律动（report ID 0x4E）
- 灯效矩阵来自清单；逐键编辑使用矩阵坐标
- 写入后回读当前模式/亮度做校验

### 8.5 配置档

- 读取/写入板载槽；切换当前槽
- 应用侧名称、导入/导出 JSON（应用自有格式，不承诺兼容网页格式）
- 应用前快照 + 一键恢复
- 随应用切换映射独立于设备配置档

---

## 9. 错误处理

| 场景 | 行为 |
|---|---|
| 设备未连接 | UI 置灰，不写，保留最后状态 |
| 未知型号 | 只读，记录 VID/PID/描述符，不写 |
| 未验证型号 | 只读，明确提示 experimental |
| `IOHIDDeviceOpen` 失败 | 展示错误码；标准键盘接口的 `0xE00002E2` 忽略，配置接口出现同错才提示权限/接口保护；提供网页驱动兜底 |
| 命令超时/NAK | 读重试 3 次；写重试 1 次 + 回读；仍失败回滚 |
| 写入中断开 | 中止、标记 dirty、重连后提示重新应用 |
| 非法响应 | 丢弃并记录 hex；不继续写 |
| boot 模式 | 停止常规操作，显示固件模式说明 |
| 快照恢复失败 | 保留快照文件，允许重试/导出日志 |

日志使用 `os.Logger`，按 `transport/protocol/feature` 分类；提供“复制诊断日志”（原始 hex + 设备标识），不包含用户按键内容以外的隐私数据。

---

## 10. 安全与合规

- 个人自用，不对外分发
- 不打包/再分发厂商固件与素材；清单提取仅用于本地互操作
- v1 不实现 OTA，避免刷砖
- 所有写操作必须由用户显式触发；开发期默认 `--read-only`
- 应用前快照；提供恢复入口
- 运行时不需要网络；清单提取是离线构建步骤
- 不注入、不修改网页；原生实现独立运行

---

## 11. 测试

### 11.1 单元测试

- 帧编码/解码 golden bytes
- 校验和、分包、序列号、超时/重试
- 清单字段完整性与能力位一致性
- 布局 JSON 与矩阵尺寸校验

### 11.2 协议回放

用网页驱动的只读响应（hex）做离线解码测试，不依赖硬件。

### 11.3 硬件集成（只对 Ace 68 Turbo 16K）

1. 连接/断开/睡眠唤醒
2. 只读：型号、版本、键位、磁轴、灯效、配置档
3. 可逆写入：改一个键 → 回读 → 恢复快照
4. 配置档切换：板载槽 + 前台 App 切换
5. 异常：写入中拔线、非法响应、boot 模式提示

### 11.4 安全开关

- `--read-only`：只发读命令
- `--dry-run`：编码但不发送
- CLI 与 App 均支持启动参数；开发期默认开启，正式使用需显式关闭

UI 先手工冒烟，不做自动化。

---

## 12. 交付切片

| 阶段 | 内容 | 退出条件 | 预估 |
|---|---|---|---|
| Phase 0 | 原生 CLI：枚举/打开/识别 + CZ 只读命令 + Ace 68 清单提取 | 能读出型号/版本/基础信息，全程无写操作 | 2–4 天 |
| Phase 1 | 传输层 + 清单 + 设备信息 + 磁轴 + 改键 + 灯效 + 配置档 | 已验证设备上四类设置可读写、可回读、可恢复 | 1–2 周 |
| Phase 2 | 宏/SOCD + 随应用切换 + 导入导出 + 灯效编辑增强（GIF/音乐律动另开阶段） | 菜单栏常驻、切换稳定、快照恢复可用 | 1–2 周 |
| Phase 3 | 多型号清单覆盖（experimental 标注）；OTA 另开设计 | 新设备至少完成只读验证 | 按设备逐个 |

**硬门槛：Phase 0 不通过，不进入 UI 实现。**

---

## 13. 风险与待确认

1. **CZ 协议细节**：report ID、校验、命令码、payload 编码未完全确认；Phase 0 解决
2. **板载配置档语义**：是否支持多槽、切换命令、槽位上限；Phase 0/1 探测
3. **灯效数据模型**：逐键颜色、GIF、音乐律动的写入方式；v1 先做静态
4. **固件差异**：同型号不同固件版本命令可能不同；清单记录最低/最高固件版本
5. **睡眠唤醒**：IOHIDDevice 可能需要重新打开；Phase 1 验证
6. **权限提示**：配置接口目前无需 Input Monitoring；如系统策略变化，需要提示
7. **未实测型号**：只能标注 experimental，不能声称可用

---

## 14. 备选方案与取舍

| 方案 | 结论 |
|---|---|
| Electron 套壳网页版 | 最快、功能最全，但依赖厂商网站，不是原生；已放弃 |
| WKWebView + 原生 HID 桥 | 复用网页 UI，全型号最快，但 UI 非原生、安全边界差；作为兜底备选 |
| 单型号硬编码 | 最快验证，但违背“可扩展”目标；只允许作为 Phase 0 手段 |
| DriverKit/内核扩展 | 不需要；系统已驱动标准 HID，配置走用户态；且需 Apple entitlement |
| 浏览器 WebHID | Safari 不支持；Edge 可用但非原生 App |

---

## 15. 验收标准

1. 插上 Ace 68 Turbo 16K，App 能自动识别并读出当前状态
2. 磁轴、改键、灯效、配置档四类设置均可修改、应用、回读验证
3. 关掉主窗口后菜单栏仍可切换配置档；随应用切换生效
4. 拔插、睡眠唤醒后能恢复；失败不会让键盘进入异常状态
5. `--read-only` 模式下不产生任何写操作
6. 恢复快照能回到应用前状态
7. 未知/未验证型号只读，不写入

---

## 16. 假设

- 用户拥有并连接 Ace 68 Turbo 16K
- 固件版本在网页设备库支持范围内
- 允许本地构建并运行未公证应用
- 网页版可作为协议与配置的参考实现
- 设备清单提取在开发机联网完成，运行时离线
