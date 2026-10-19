# Ace 68 Turbo 16K：宏 / SOCD / 逐键灯效 / FN 图层 CZ 协议规格

> 状态：从厂商 WebHID 驱动 bundle 逆向，**未写设备**。所有偏移、命令码均给出 bundle 证据；无法从 JS 确认的条目显式标 `UNVERIFIED - 需实机只读验证`。
>
> 研究对象：MCHOSE Ace 68 Turbo 16K（USB `0x3837:0x3026`，device type 211，fw 122）。
>
> 主要证据文件（`.build/vendor-js/`）：
> - `mod34968.pretty.js` — 常量
> - `mod39318.pretty.js` — 0x55 report0 通道、宏编解码、键位、逐键灯、SOCD/MT/TGL 编码
> - `mod14905.pretty.js` — GLW SDK facade（宏 header、key config、profile）
> - `mod12576.pretty.js` / `mod63031.pretty.js` — key 类型枚举、记录切分/补齐
> - `app/2233-a3005d7f2c1e6167.js` — GLW Provider 初始化、宏模式、SOCD 校验、FN 键
> - `app/1288-10a068b06ab7ba15.js` — 设备条目、layout、默认键
> - `layout-ace68_turbo_16k.47abd6e490c43ed66450.js` — 布局
>
> 已有实机只读证据：`docs/captures/ace68-feature-protocol.md`；`Resources/DeviceManifests/ace68_turbo_16k.json`（`macros=true, socd=true, perKeyLighting=true, gifLighting=false, macroSlots=null`）。

---

## 0. 结论速查

| 功能 | 读 | 写 | payload / 区域 | 置信度 |
|---|---|---|---|---|
| 宏（宏正文） | `0x0C` | `0x0D` | 共享 **8192 B**，16 槽，header 64 B，动作 4 B/步 | 高（SDK + base 实机值 + 初始化逻辑） |
| 宏（槽名/启用/默认延迟） | custom JSON | custom JSON | custom 区 `1024 + 0`，1120 B，16 项 | 高（UI 状态，非固件宏正文） |
| SOCD | `0x202`（report 77） | `0x308`（report 77） | 每键变长记录；SOCD 记录 **8 B**，类型 36 | 高（GLW 新键位路径） |
| 逐键静态灯 | `0x0A`（report 0） | `0x0B`（report 0） | `512 B/profile`，3 B/键，**R,G,B** | 高 |
| FN 图层（旧 keymap） | `0x08`（当前）/`0x07`（默认），report 0 | `0x09`（report 0） | 3 B/键；FN = `F0 FF layer` | 高（现有 Swift 已读） |
| FN 图层（新 key config） | `0x202`（report 77） | `0x308`（report 77） | FN 记录 = `32 layer 00`（type 50） | 高（官方 UI 路径） |

**先纠正一个常见误标**：`0x0D` 不是 base 读，而是**宏写**；base 读是 `0x04`。`0x0E` 是 base 写。逐键灯是 `0x0A/0x0B`，不是 `0x0C/0x0D`。

---

## 1. 共同约定（0x55 / report 0）

### 1.1 帧格式

请求（64 B，report ID 0）：

```
55 <cmd> 00 <checksum> <len> <offLo> <offHi> 00 <data...>
```

- `checksum = sum([len, offLo, offHi, 0, ...data]) & 0xFF`
- `len` 是本包有效数据字节数（≤56）
- `off` 是 16 位小端逻辑偏移；读取时设备回显该 offset
- 空读请求 `data` 为空，`len` 仍表示“要读的字节数”（`encodeGet` 用 `declaredLength=min(length,56)`，data 为空）

响应：

```
AA <cmd> ?? ?? <len> <offLo> <offHi> ?? <payload...>
```

payload 从偏移 8 开始。`Sources/Protocol/CZCodec.swift` 与 `CZSession.swift` 已是这个实现。

证据：`Sources/Protocol/CZCodec.swift:53-100`；`mod39318.pretty.js:114-205`（`_simpleGetCommand` 按 56 B 分页，`data:{size,offset}`）。

### 1.2 分页读

`_simpleGetCommand(cmd, offset, length)` 把请求拆成 56 B/包：

```js
new Z({ command, data: { size: Math.min(56, length - i) }, offset: offset + i })
```

每包 offset 递增 56；响应 payload 的 offset 回显请求 offset，用 `CZResponseAssembler` 按 offset 拼回。**宏 8192 B = 147 包**（`ceil(8192/56)`）。

### 1.3 分块写

`_simpleFullSendCommand`：

```js
f = Math.min(56, Math.floor(56 / chunkSize) * chunkSize)
// 每包 data[p .. p+f)
// 最后一包不足 f 且 p>0 时，offset 回退到 length-f，重发完整 f 字节（与上一包重叠）
```

- 默认 `chunkSize=1` → 56 B/包。
- keymap/灯效写显式 `chunkSize=3` → 54 B/包。
- 最后一块会重叠回退，设备端按 offset 覆盖，重复字节必须一致。
- 写命令没有单独的“提交/保存”帧；JS 也没有 commit 调用。**按 flash 语义对待**。

证据：`mod39318.pretty.js:214-233`；`Sources/Protocol/CZSession.swift:110-170`。

### 1.4 report 77 的另一套通道（新 key config / base info）

bundle 里还有 7 字节头、`reportId=77` 的 16 位命令通道。**`0x202`/`0x308` 是这条通道，不是 0x55**：0x55 的 cmd 只有 1 B，514/776 放不下。

帧（64 B HID 输出，report ID 77；下面的 `data` 才是 payload）：

```
<version=01> <flags=03> <len> <cmdLo> <cmdHi> <biz=00> <seq> <data...> <xor>
```

- `len = data.length`
- `xor = XOR(flags, len, cmdLo, cmdHi, biz, seq, data...)`（从 byte1 到 data 末尾，跳过 byte0 version）
- 正常模式 `MAX_PACKET_LENGTH=31` → `data` 最多 **23 B**（31-7-1）
- boot 模式 `MAX_PACKET_LENGTH=63` → `data` 最多 **55 B**
- 响应同构：7 B header + data + 1 B check；data 从偏移 7 开始

常量与编解码（`mod39318.pretty.js:4036-4075`）：

```js
Ge.BIZ_CODE=0, Ge.SEQUENCE_ID=0, Ge.NORMAL_MAX_PACKET_LENGTH=31,
Ge.BOOT_MAX_PACKET_LENGTH=63, Ge.REPORT_ID=77, Ge.HEADER_LENGTH=7
toMaxPacketDataLength(e) { return e - HEADER_LENGTH - 1; }   // 23 / 55
toHeaderBytes(e){ return [e.version,e.flags,e.length, ...hJ(e.command), e.bizCode&255, e.sequence&255]; }
```

`mchose-cli readraw` 只发 report 0 且无 payload，**无法读 report 77**。因此本文中 SOCD/FN 的“新 key config”只能用临时只读探针验证；宏/逐键灯/旧 keymap 仍是 0x55 report0，可直接 `readraw`。

---

## 2. 宏（Macro）

### 2.1 区域与模式：8192 B，shared，16 槽

Ace68 Turbo 16K 的 base 实机只读值（`docs/captures/ace68-feature-protocol.md`）：

```
01 03 00 01 02 03 AA BB ...
```

解析（`mod39318.pretty.js` 的 `eC` / `mod14905.pretty.js`）：

- `e[0]=1`：activeIndex 在 order 中的下标
- `e[1]=3`：profileLength
- `e[2..5]=00 01 02 03`：order
- → `supportMultiProfile=true`，`supportOrderProfile=true`，`maxProfileLength=4`

GLW Provider 初始化（`app/2233-a3005d7f2c1e6167.js`）：

```js
let { supportMultiProfile:l, supportOrderProfile:a, maxKeyboardProfileLength:o } = await e.getBase(),
    s = (0,u.l7)(vendorId, pid, productName);   // getDeviceType → 211
l && a
  ? e.changeMacroMode({ size: [101,130,131,132].includes(s) ? 4096 : 8192, shared: true })
  : e.changeMacroMode({ size: 2048, shared: false });
```

`s=211` 不在 `[101,130,131,132]` → **size=8192, shared=true**。因此：

- 整个设备只有一块宏区，offset 0，长度 8192
- 所有 profile 共享 16 个宏槽
- **不是**每 profile 2048 B

证据：`app/2233-a3005d7f2c1e6167.js @~235200`；`mod39318.pretty.js:365-405`（`eC`）；常量 `mod34968.pretty.js:6`。

> 16 槽来自 `MAX_MACRO_LENGTH=16`，并由 header 的 16 个 uint16 offset + 16 个 type 字节验证。实机读 `0x0C 0 64` 应看到 32 B offset 表 + `81 7E` + 16 个 type。若某固件不是 16，header 布局会变；这是**第一项实机只读验证**。

### 2.2 区域布局

```
0x0000  uint16 LE offset[16]    32 B   每个槽的动作流起始绝对偏移（相对宏区起点）
0x0020  0x81 0x7E               2 B    magic
0x0022  uint8 type[16]          16 B   槽类型（UI 播放方式）
0x0032  0x00 ...                14 B   保留（到 0x003F）
0x0040  动作流 ...                     每个动作 4 B；空槽在 0x0040 放结束标记
```

空槽 offset = `0x0040`，动作流 = `04 00 80 00`。

证据：`mod14905.pretty.js:630-760`：

```js
o = Array(2*l.Lj).fill(0);                 // 16 × uint16 = 32 B
s = [ ...$([]) ];                           // 空宏 = SerializeMacroActions([])
c = { [hash([])]: qW(64) };                 // 空宏 offset = 64
for (e=0; e<l.Lj; e++) {
  n = $(t[e].macroActions);
  [i,r] = qW(64 + s.length);
  o[2*e] = i; o[2*e+1] = r;
  s.push(...n);
}
f = Array(2*l.Lj).fill(0);
f[0]=129; f[1]=126;                         // header[32..33] = 0x81 0x7E
for (e=0; e<l.Lj; e++) f[e+2] = t[e].type & 255;
h = [...o, ...f, ...s];                     // 64 + actions
```

### 2.3 动作编码：4 B/步，1 ms 单位

| 字节 | 含义 |
|---|---|
| 0-1 | `delay`，uint16 小端，单位 **1 ms** |
| 2 | bit7 `isEnd`；bit6 `isDown`（keydown/mousedown=1）；bit0-5 `actionType` |
| 3 | `code & 0xFF`（HID usage / mouse button） |

`code = (actionType << 8) | byte3`。

动作类型（`Ce.ACTION_DICT`，`mod39318.pretty.js:1747`）：

| type | 含义 | up/down 名称 |
|---|---|---|
| 0 | 鼠标键 | mouseup / mousedown |
| 17 (0x11) | 普通键盘键 | keyup / keydown |
| 18 (0x12) | 键盘控制键 | keyup / keydown |
| 63 (0x3F) | 延时占位（未知高字节回退） | — |

> 这是**宏动作**的 4 B 单元类型（`ACTION_DICT`），不是键位记录类型；不要和 5.2/5.3 的键位 type 表混用。

要点：

- `delay` 是“执行本动作前等待”的毫秒数，**不是** 5 ms/10 ms 单位，也没有乘除变换。
- `MIN_MACRO_DELAY=5`；写入时 `<5` 会被写成 `4`（`MIN-1`）。因此**没有前置 time 的 action 单元也是 `04 00`**，空槽结束标记同样是 `04 00 80 00`。
- `formatMacroDelay` 把 UI 值 clamp 到 `[5, 65535]`；`getMacros` 解码时会过滤 `delay<5` 和 `code<=0` 的“无用动作”，但**原始 0x0C 字节仍保留**。
- 一个 4 B 单元只能承载一个事件。一次按下通常是两个单元：keydown（bit6=1）、keyup（bit6=0）；最后一个单元置 bit7=1。
- `SerializeMacroActions` 会把“time + 下一个 action”合并进同一个 4 B 单元（delay 属于该 action）；没有 time 的 action 单独成单元。
- 空宏：`04 00 80 00`。

例子（A，HID usage 4）：

```
04 00 51 04   keydown A（delay=4 占位，0x40 | 0x11 = 0x51）
04 00 11 04   keyup A
```

最后一个 keyup 若为宏结尾：`04 00 91 04`（0x11 | 0x80）。

> 没有前置 `time` 的 action 也会写 `delay=4`（`MIN_MACRO_DELAY-1`），不是 0；解码时 `delay<5` 会被 `filterUselessActionItem` 过滤掉，所以 UI 不显示。

证据：`mod39318.pretty.js:1686-1745`（`SerializeMacroActionItem` / `DeserializeMacroActionItem`）；`mod34968.pretty.js:6`（`MIN_MACRO_DELAY=5`）。

### 2.4 读：`0x0C`，56 B 分页

通道方法（`mod39318.pretty.js:943-989`）：

```js
async getMacros(t) {
  let r=this.macroMode.size, a=this.macroMode.shared?0:t*r;
  return await this._simpleGetCommand(12, a, r);       // 12 = 0x0C
}
async getMacroPacket(t,n) {
  let r=this.macroMode.size, a=this.macroMode.shared?0+56*n:t*r+56*n;
  assert(n < this.maxMacroPacketCount);
  return await this._simpleGetCommand(12, a, Math.min(56, r-56*n));
}
get maxMacroPacketCount() { return Math.ceil(this.macroMode.size/56); }  // 147
```

实现建议：

1. 读 56 B（packet 0）拿 header。
2. 校验 `header[32]==0x81 && header[33]==0x7E`；不匹配时不要解析 type（SDK 仍解析 offset）。
3. 取 `offsets[0..15]`；`maxOffset = max(offsets)`。
4. 继续读 packet 1..，直到覆盖 `maxOffset` 之后至少 4 B 或读到结束标记；按 4 B 步进解码。
5. 每个槽从 `offset[i]` 开始，到结束标记（bit7）或下一个槽 offset 为止。

**注意**：offset 是相对宏区起点的绝对偏移，不是相对 64；空槽指向 64。offset 是 uint16，所以整个区域 < 65536。

### 2.5 写：`0x0D`，整段 header + actions

通道方法（`mod39318.pretty.js:943-989`）：

```js
async setMacros(t,n) {
  let r=this.macroMode.size, a=this.macroMode.shared?0:t*r;
  assert(n.length <= r, "宏长度溢出");
  await this._simpleSendCommand(13, a, n);             // 13 = 0x0D
}
```

facade `mod14905.pretty.js:630-745`：

- 输入是 16 个 `{macroActions, type}`（可选 name/defaultDelay 只进 UI 状态）。
- 为每个槽序列化动作流，按顺序拼在 64 B header 后，写 offset 表。
- 去重：相同 action 数组共享同一段动作流，offset 相同。这会让多个空槽都指向 64。
- 只有 `profile===0 || shared` 才真正下写；shared 模式下所有 profile 都写同一块。

写入分块：

- `_simpleSendCommand` 默认 `chunkSize=1` → 56 B/包。
- 8192 B 共 147 包；最后一包 offset 回退到 8136，重发 56 B（与上一包重叠 40 B）。
- 写入长度可以小于 8192：只写 `64 + 所有动作流` 的前缀即可；header 里的 offset 都落在这个前缀内。**但绝不能只写 64 B header 就结束**（除非所有槽都空），否则会留下旧的、与新 offset 不一致的动作数据。
- 删除某个槽：`macroActions=[]`，重新计算**所有槽**的 offset（因为后面的动作流会前移），然后整段写。不要只把该槽的字节清零。
- 清空全部：16 个槽都空，写 `header + 04 00 80 00`；或调用 SDK 的 `clearMacro()`（对每个 profile 写 16 个空槽）。

上限：

- 动作区 = `8192 - 64 = 8128 B` → 最多 **2032 个 4 B 单元**（含每个非空槽的结束标记）。
- 槽数 16；offset 字段 uint16；没有发现“每槽最大步数”常量，限制来自总区域和 UI。
- UI 状态另存 1120 B（16 × `["name", type, defaultDelay=50, enableDefaultDelay=true]`），不占宏正文。

### 2.6 设备端回读差异

- 原始 `0x0C` 读回的是**设备实际存储的 4 B 单元**，没有 encode/decode 变换。
- SDK 的 `getMacros` 会把字节解码成 `{type:'time'|'action', ...}`，并过滤 `delay<5`、`code<=0`；所以 UI 回读可能“丢”掉写入的低延迟/空动作，但原始字节仍在。
- SDK 写入时会重新计算 offset 并去重；设备可能原样存储，也可能在固件内重排。`UNVERIFIED - 需实机只读验证`：写一个已知宏后回读 0x0C，比较 offset 与动作字节是否逐字节一致。
- 宏类型字节（header[34+i]）由 `fromUIMacroType` 从 UI 值 0/1/255 映射为固件 0/2/1（`mod39318.pretty.js:1747-1753`）。具体播放语义（单次/切换/按住）未在 bundle 里给出名字，`UNVERIFIED`。

### 2.7 独立宏（另一套，不是本设备默认路径）

bundle 里还有独立宏命令：

- `getIndependentMacro` = `0x90C`（2316）
- `setIndependentMacro` = `0x90B`（2315）
- `getMacroIndexList` = `0x90E`（2318）
- `setMacroIndexList` = `0x90F`（2319）

header 64 B：`[size LE16, 0,0, fromUIMacroType(type), bit0 defaultDelay|0x80, defaultDelay LE16, JSON name]` + actions。要求 `macroConfig.type==='independent'` 且 `headerHasName`。Ace68 的 base 选择的是 shared 8192，**不走这套**；仅当实机 `0x900` 读出 `macroConfig.type='independent'` 时才需要切换。`UNVERIFIED`。

---

## 3. SOCD

### 3.1 结论：SOCD 没有独立命令，存在 key config 记录里

GLW 新键位配置把每个键/高级键编码成**变长记录**，SOCD 是 type 36 的记录，每条 **8 B**。它和普通键、FN、宏键、MT/TGL 共用 `0x202` 读 / `0x308` 写。

这套 key config 走 **report 77（7 B header，16 位命令）**，不是 0x55；`0x202=514`、`0x308=776` 超过 1 字节，放不进 0x55 的 cmd 字段。下面写的“payload”都是 7 B header 之后的 `data`。

这与旧 QHW 的独立高级区（DKS `0xA2/0xA3`、MT `0xA4/0xA5`、TGL `0xA6/0xA7`）不同；**不要**去 `0xA8` 找 SOCD（bundle 里没有这个命令）。

### 3.2 key config 读写帧（report 77）

先按 1.4 组 7 B header：`[01, 03, len, cmdLo, cmdHi, 00, seq]`，再拼 `data`，最后 1 B XOR。`len = data.count`。

`0x202` 读（`mod39318.pretty.js:3026-3055`）：

- `data` 3 B：`[layerIndex, matrixRC, count]`
- `layerIndex = (profile & 0x0F) | ((layer & 0x0F) << 4)`
- `matrixRC = (row & 7) | ((col & 31) << 3)`
- `count` = 连续列数；正常模式最多 `floor(23/3)=7`，boot 模式最多 `floor(55/3)=18`
- 响应 `data` 是从 `start` 列开始的变长记录流；一条记录对应一列，按 type 查 chunkSize 切分。

`0x308` 写（`mod39318.pretty.js:2250-2290`）：

- `data`：`[layerIndex, matrixRC, control, records...]`
- `control = (packetType & 3) | ((count & 0x3F) << 2)`
  - `packetType`：1=first，2=last，3=first+last，0=middle
  - `count` = 本包 key 记录数（不是字节数）
- `records` 上限：正常模式 `23 - 3 = 20 B`，boot 模式 `55 - 3 = 52 B`；一条记录的大小由 type 决定。
- 同一包内的记录必须属于同一矩阵行、连续列；`setKeyConfigs` 会按连续区间自动分组。
- `requireFullWrite=false`：只写提供的记录，不要求整层；但 control/count/RC 必须与记录序列严格一致。

`layerIndex` 证据：`mod39318.pretty.js:2457`：

```js
toLayerIndex(e) { return 15 & e.profileIndex | (15 & e.profileKeyboardLayer) << 4; }
```

control 证据：`mod39318.pretty.js:2441-2450`：

```js
toWriteControl(e,t) { return 3 & e | (63 & t) << 2; }
parseWriteControl(e) { return { packetType: 3 & e, size: e >> 2 & 63 }; }
```

### 3.3 SOCD 记录（8 B）

`mod39318.pretty.js:1916-1929`：

```js
parseSOCDBytes(e) {
  var t=3&e[2], n=!(128&e[2]), r=parseMatrixIndex(e[1]);
  return {
    priority:t, isPadLeft:n,
    targetArrIndex:r.row*MATRIX_SIZE.col+r.col,
    keyItem:KG(e.slice(3,6))
  };
}
toSOCDBytes(e) {
  var t=floor(e.targetArrIndex/MATRIX_SIZE.col),
      n=floor(e.targetArrIndex%MATRIX_SIZE.col);
  return Qc([36, toMatrixRC({row:t,col:n}),
             3&e.priority|(e.isPadLeft?0:128),
             ...YV(e.keyItem)]);           // Qc 补齐到 chunkSize=8
}
```

| 字节 | 含义 |
|---|---|
| 0 | `0x24` (36)，SOCD 类型 |
| 1 | `matrixRC`：**对方**键的行列 |
| 2 | bit7 = `!isPadLeft`（0=left/pad-left，1=right）；bit0-1 = `priority` |
| 3 | 本键 key type |
| 4 | 本键 code1 |
| 5 | 本键 code2 |
| 6-7 | `0x00 0x00` 补齐 |

`keyItem` 就是普通 3 B 键位 `[type, code1, code2]`，例如 `[17,0,4]` 表示 A。

`matrixRC` 编解码：

```
rc  = (row & 7) | ((col & 31) << 3)
row = rc & 7
col = (rc >> 3) & 31
```

`targetArrIndex = row * MATRIX_SIZE.col + col`，是**线性矩阵索引**，不是 keymap 数组下标。`MATRIX_SIZE.col` 由设备矩阵配置决定；bundle 里 68 键布局的坐标表是 6 行 × 18 列（108 槽，含空位），但 Ace68 实际 `MATRIX_SIZE.col` 需用 `0x202` 读取反推，标 `UNVERIFIED`。

### 3.4 成对规则

SOCD 是**两条记录**，分别放在两个物理键的 key config 位置：

- 记录 A：`targetArrIndex = B`，`isPadLeft=true`（bit7=0）
- 记录 B：`targetArrIndex = A`，`isPadLeft=false`（bit7=1）

UI 校验（`app/2233-a3005d7f2c1e6167.js @466309`）：

```js
u[0] === OT.AdvanceSOCD.type          // 两条都是 36
n !== h                                 // isPadLeft 必须相反
p === i                                 // targetArrIndex 必须互为对方
(1===t && 2===f) || (2===t && 1===f) ||
(0===t && 0===f) || (3===t && 3===f)    // priority 组合
```

`priority` 只有 0..3，合法组合：

| 组合 | 含义 |
|---|---|
| `(0,0)` | 策略 A |
| `(1,2)` | 策略 B（左优先） |
| `(2,1)` | 策略 B（右优先） |
| `(3,3)` | 策略 C |

UI i18n 里能 grep 到 `563/565/567/569` 四个键，但 bundle 没有把数字映射到“last-wins / neutral / first-wins”的字符串，**策略名 `UNVERIFIED - 需实机只读验证`**。实现时先原样保留读到的 priority 组合，不要自创语义。

### 3.5 对数与限制

- 每个 SOCD 对占 2 个键记录；键位空间最多 128（`maxKeyCount`），理论上最多 **64 对**。
- bundle 没有单独的“最大 SOCD 对数”常量；限制来自 key config 记录流和 UI。
- SOCD 记录不能和普通键记录共用同一个 key index；一对的两条记录必须互相指向。
- 旧 3 B keymap（`0x08/0x09`）里的 type 148 只是“这个键是 SOCD”的占位，**不携带对方键/策略**；完整信息在 `0x202/0x308`。不要用 0x09 写 SOCD。

### 3.6 读/写流程建议

只读盘点（不写）：

1. 对每个 profile/layer，读 `0x202` 的整层（或按行连续读）。
2. 按 type 36 找 SOCD 记录；检查两条记录是否互为 target。
3. 记录每对的 key index、priority、isPadLeft。

写入（后续实现）：

1. 先 `0x202` 读整层，解析所有记录。
2. 在副本上替换两个 key 记录为 8 B SOCD 记录。
3. 用 `0x308` 按连续区间写回；两条记录若不相邻，分两包。
4. 写完 `0x202` 回读，逐字节比较。

---

## 4. 逐键静态灯效（Per-key lighting）

### 4.1 区域

- `totalLightAreaSize = 512` B/profile
- `usedLightAreaSize = 3 * maxLightKeyCount`
- 本设备 GLW 默认 `maxLightKeyCount = 128`（`mod2038.pretty.js:1692-1698`）→ 实际使用 **384 B**
- 每键 3 B；总 512 B 中的后 128 B 是保留/其他 scopes，静态主键区只用 384 B
- 逐键区**只有 RGB 三字节**，没有每键亮度/开关字段；亮度、总开关、速度在 4.4 的 8 B 主灯效配置里（profile 级，不是 key 级）

索引：

- 颜色数组下标 = 键的**线性 key index**（与 `0x07/0x08` 的 keyIndex 同一索引空间），不是 `(row,col)`。
- 偏移：`512*profile + 3*index`
- 官方 UI 从 `initDefaultKeys()` 的 key index 生成 `lightColors`；布局里的 `Light0..4` 是侧灯节点，侧灯索引由 `toLightColorRage` 的 side/side2 range 决定，和主键不是同一段。主键 0..127；侧灯具体索引用 `getKeyCustomLight` 的 scopes 读出来确认。
- “index 与 0x08 keyIndex 完全一致”是推断，不是 JS 里直接断言；若实机写单键后 `0x0A` 读到的位置不对，按 `initDefaultKeys()` 的实际 index 调整。`UNVERIFIED - 需实机只读验证`。

### 4.2 颜色字节序

**R, G, B**（不是 BGR）：

- `setSingleKeyColor(profile, keyIndex, [r,g,b])` 直接写 3 B
- facade 的 `ey` 把 `{r,g,b}` 拆成 `[r,g,b]`；`eg` 反向
- `parseLightColorBytes` = `[matrixIndex, r, g, b]`（这是带索引的 4 B 结构，不用于逐键区）

### 4.3 读 `0x0A` / 写 `0x0B`

`mod39318.pretty.js:1030-1185`：

```js
setSingleKeyColor(t,n,r) {
  return this._simpleSendCommand(11, this.totalLightAreaSize*t + 3*n, r);
}
setAllKeysColor(t,n,r) {
  a = this.departLightColors(n.slice(0, this.usedLightAreaSize), r).inRange;
  await Promise.all(a.map(e =>
    this._simpleSendCommand(11, this.totalLightAreaSize*t + e.start, e.value)
  ));
}
getKeyCustomLight(t,n) {
  r = t*this.totalLightAreaSize;
  a = new Array(512).fill(0);
  o = this.departLightColors(a.slice(0,384), n).inRange;
  await Promise.all(o.map(e => this._simpleGetCommand(10, r+e.start, e.value.length)));
}
```

- 读：`0x0A`，offset `512*profile + 3*start`，len = 3×键数；响应原始 RGB 流。
- 写：`0x0B`，offset 同上，payload 3×键数。`_simpleSendCommand` 默认 56 B/包；384 B 分 7 包，最后一包 offset 回退到 328（56 B 重叠 8 B）。
- 单键写：3 B payload，offset `512*profile + 3*keyIndex`。
- 按 profile 独立：offset 乘 `512*profile`。
- 读回是可行的（`0x0A`），即使官方 UI 不拿它显示；UI 的 `lightColors` read 返回全 `#000000` 占位，只有 write 走 `setAllKeysColor`（`app/2233 @133600`）。

### 4.4 如何打开/关闭 per-key 模式

bundle 里**没有**独立的 “per-key enable” 命令。逐键颜色属于主灯效的“自定义/逐键”模式，相关常量：

- `CUSTOM_COLOR_INDEX = 9`
- `RANDOM_COLOR_INDEX = 8`
- `STILL_EFFECT_START_AT = 65`
- 主灯效配置 8 B：`[enabled, brightness, speed, colorIndex, direction, r, g, b]`
- 主灯效列表第 0 项是 `light-0`（自定义/逐键），其余是预设

推论（`UNVERIFIED - 需实机只读验证`）：

1. 先把主灯效切到自定义（effect index 0，或 `colorIndex=9` 的自定义项）。
2. 再用 `0x0B` 写 384 B 逐键颜色。
3. 关闭：切到任意非自定义灯效；不需要清空颜色。

**不要**为了“打开”去写 `0x06` func config；先 `0x05` 读当前 64 B，确认 effect/color 字段，再决定是否写。激活模式的实机验证必须写设备，超出本次只读范围；文档只能标未验证。

### 4.5 侧灯/音乐灯（不要混用）

- 静态逐键区的主键/侧灯 scopes 由 `departLightColors` 分段；主键只用 0..384。
- 音乐律动：主灯 `0xDD`(221)、侧灯 `0xDF`(223)、side2 `0xDC`(220)，`chunkSize=3`；不是静态区。
- `getRealtimeLightColor` = `0xDE`(222)，读实时颜色。
- 不要用 `0x0B` 写音乐灯区域，除非确认索引段。

---

## 5. 键位图层 / FN 层

### 5.1 四层语义

每个 profile 4 层，**层号是全局线性层**：

| layer | 语义 |
|---|---|
| 0 | Windows base |
| 1 | Windows FN |
| 2 | macOS base |
| 3 | macOS FN |

- profile 的 `keyLayerMode` 在 profile config（`0x205`）里，`1=mac`。
- `macMode = keyLayerMode==='mac' ? 4*profile+2 : 4*profile`；读取时 `macMode%4>=2` 判 mac。
- `getKeyInfos(profile, layer)` 读 `0x08` 的 `512*(4*profile+layer)`。
- 默认键读 `0x07` 同一布局；写当前键用 `0x09`。

### 5.2 旧 3 B keymap 编码（0x07/0x08/0x09）

每键 3 B：`[type, code1, code2]`。

| type | 含义 | code1 | code2 |
|---|---|---|---|
| `0x10` (16) | 普通 HID 键盘键 | 修饰位：bit0/4 Ctrl，bit1/5 Shift，bit2/6 Alt，bit3/7 Win | HID usage |
| `0xFF` (255) | 空 | 0 | 0 |
| `0xF0` (240) | 特殊键；其中 FN 键 `code1=255` | 特殊键查表；FN 固定 255 | FN 层号 0..3（仅 FN） |
| `0xF0+i` (240+i) | 非活动层占位（`type==code1==code2>=240`） | 同 type | 同 type |
| `0x70` (112) | 宏 | 槽位 index | 0 |
| `0x90` (144) | DKS | 引用键/参数 | — |
| `0x91` (145) | TGL | — | — |
| `0x92` (146) | MT | — | — |
| `0x93` (147) | RS | — | — |
| `0x94` (148) | SOCD 占位 | — | — |
| `0x95` (149) | LT | — | — |
| `0x40` (64) | 电源 | 1 Power / 2 Sleep / 4 WakeUp | 0 |
| `0x30` (48) | 多媒体 | — | — |
| `0x80` (128) | Gunlun/滚轮 | 66 | 0 |
| `0x21` (33) | 鼠标滚轮 remap | 0 | 1 或 255 |

修饰位：`code1` 低 4 位和 bit4-7 都参与；`code1>0 && code2>0` 时 UI 显示为组合键（CB）。具体 bit 顺序见 `app/1288` 的 `E()` 解码函数。

FN 键的规范形式：`[0xF0, 0xFF, layer]`，例如 Windows FN = `[240,255,1]`。显示层会做 `code2 % 4`。**不要**把 `[240+i,240+i,240+i]` 当成 FN 键；那是未编程层的占位。

写入偏移：

```
offset = 512*(4*profile + layer) + 3*keyIndex
```

`setUserKeys` 从 keyIndex 0 开始整层写，`chunkSize=3` → 54 B/包；384 B 共 8 包，最后一包 offset 回退到 330（回退 48 B，重叠 48 B，真正新增 6 B）。也可以只写变化的 54 B 块，但要保持 3 B 对齐。

### 5.3 新 key config 编码（0x202/0x308，report 77）

官方 GLW UI 对 Ace68 使用 `keyByteList` + `0x202/0x308`（设备条目的 `manufacturer` 缺省 → `'glw'`）：

```js
function eq(e,t,o){ var a=et(e,t,o); return a?.manufacturer ?? 'glw'; }
```

Ace68 条目没有 `manufacturer` 字段，所以走 GLW。新编码的 FN 键是：

```js
if (e.bytes[0] === N.OT.FN.type && !d()(e.bytes[1],0,4)) {
  let t = e.bytes.slice();
  t[1] = e.bytes[1] % 4;
  return { ...e, bytes: nO(t) };
}
```

即记录 `[50, layer(0..3), 0]`（type 50 = `0x32`，payload 1 B，补齐到 3 B）。**不是**旧编码的 `[240,255,layer]`。

新 key config 的 type 表（`mod12576`，chunkSize 见括号）：

| type | 名称 | payload | chunkSize |
|---|---|---|---|
| 255 | Empty | 0 | 3 |
| 243 | Disabled | 0 | 3 |
| 0 | Mouse | 1 | 3 |
| 1 | MouseDPI | 4 | 4 |
| 2 | MouseReportRate | 0 | 3 |
| 3 | MouseHeat | 0 | 3 |
| 4 | MouseJuji | 0 | 3 |
| 5 | MouseMainWheel | 0 | 3 |
| 6 | MouseSideWheel | 0 | 3 |
| 17 | KeyboardNormal | 1 | 3 |
| 18 | KeyboardControl | 1 | 3 |
| 33 | Macro | 1 | 3 |
| 34 | AdvanceTGL | 3 | 4 |
| 35 | AdvanceMT | 7 | 8 |
| 36 | AdvanceSOCD | 7 | 8 |
| 49 | SwitchLight | 2 | 3 |
| 50 | FN | 1 | 3 |
| 51 | SwitchProfile | 1 | 3 |
| 52 | SwitchWinMac | 1 | 3 |
| 53 | Matching | 2 | 3 |
| 54 | SwitchLightConfigType | 0 | 3 |
| 55 | LockWin | 0 | 3 |
| 56 | Reset | 0 | 3 |
| 57 | Battery | 0 | 3 |
| 58 | ToggleCharging | 0 | 3 |
| 63 | MacroDelay | 0 | 3 |
| 65 | AI | 1 | 3 |

记录总长度 = 1 (type) + payload，右侧补 0 到 chunkSize。SOCD 的 7 B payload 就是 3.3 的 7 B；总 8 B。

> **两套 type 空间不同，不要互套**：旧 3 B keymap 里 `33=鼠标滚轮`、`240=FN`；新 key config 里 `33=Macro`、`50=FN`。看到 `33` 必须先确认是哪个命令的响应。

### 5.4 两套路径的取舍（关键风险）

- 现有 Swift 读 `0x08`，能看到 layer0/2 首键 Esc、layer1/3 首键反引号；这说明旧 keymap 区域**确实存在且可读**。
- 官方 GLW UI 读 `0x202` 并写 `0x308`；它也能表示 FN（type 50）和 SOCD（type 36），而旧 3 B keymap 表示不了 SOCD 的对端/策略。
- 两者可能是同一底层数据的两种视图，也可能是两套独立存储。**在写任何键位之前，必须先做只读对比**：
  1. 读 `0x08` layer0（384 B），解 128 个 3 B 键；
  2. 读 `0x202` layer0（整层），解变长记录；
  3. 比较同一物理键的 type/code；若一致，优先用 `0x202/0x308`（官方路径，支持新类型）；若不一致，先用 `0x09` 写旧层，别碰 `0x308`。
- 不要混写：用 `0x09` 写完再用 `0x308` 覆盖同一层，或反过来，都可能让两层数据不一致。

---

## 6. 写安全要点

### 6.1 哪些写会落 flash

没有单独的 commit/save 命令；以下写命令在 JS 里都是直接下发，设备很可能立即持久化：

| 命令 | 区域 | 风险 |
|---|---|---|
| `0x09` | 当前 keymap 层 | 写错 layer/profile 会覆盖其他层 |
| `0x0B` | 逐键灯颜色 | 每 profile 512 B；写错 profile 会改别的配置档 |
| `0x0D` | 宏区 8192 B | 整段 header+actions；短写/错 offset 会破坏所有槽 |
| `0x0E` | base（profile/order） | 会切 active profile / 改排序 |
| `0x06` | func config（灯效/性能） | 会改灯效模式、回报率等 |
| `0x308` | key config（新键位） | 写错 layer/RC/control 会覆盖相邻键 |

`0x05/0x07/0x08/0x0A/0x0C` 是只读；`0x03/0x04` 只读。`0xA0` 磁轴读也只读。

### 6.2 先读后写

- 宏：先 `0x0C` 读完整 8192（或至少 header + 所有非空槽），保留未修改槽的动作流，再整段 `0x0D`。不要“只写一个槽”。
- keymap：先 `0x08` 读整层 384 B，改副本，再 `0x09` 整层写（或只写变化的 54 B 块，但必须保持 3 B 对齐）。
- 逐键灯：先 `0x0A` 读该 profile 的 384 B，改副本，再 `0x0B` 写；避免写 512 B 的后 128 B 保留区。
- key config：先 `0x202` 读整层，改记录副本，再 `0x308` 写连续区间；写完立即 `0x202` 回读比较。
- 不要在没读的情况下“清空/重置”任何区域。

### 6.3 不可逆/高风险操作

- `0xEE` 恢复出厂：不要调用。
- 校准/磁轴写入（`0xA1`、`0xA8/0xA9`、`0xB1` 等）：不要在本任务调用。
- OTA/bootloader 相关命令：不要调用。
- 宏区写坏可恢复（重写 header+actions），但如果 offset 表损坏，设备可能无法枚举宏；先备份 `0x0C` 原始 8192 B 到文件。
- profile/base 写错可能导致当前配置档切换；先 `0x04` 读并备份。
- 断电/拔线时写 flash 可能造成区域损坏；一次写尽量短，写完回读。

### 6.4 建议的写入顺序（后续实现）

1. 只读快照：`0x03`、`0x04`、`0x05`（每 profile）、`0x07`、`0x08`（4 层）、`0x0A`（每 profile 384）、`0x0C`（8192）、`0x202`（每层）。
2. 解析并校验（宏 magic/offset、key config type/chunk、SOCD 成对规则）。
3. 只改一个功能、一个键/一个槽，写最小块。
4. 立即回读同一命令，逐字节比较。
5. 任何不一致 → 用备份恢复，停止。

---

## 7. 只读验证命令（现在就能跑）

CLI：`mchose-cli readraw <command-hex> <offset> <length>`；命令是十六进制、不带 `0x`；offset/len 十进制。它按 56 B 分页发 report 0，能读所有 0x55 命令。

### 7.1 宏

```bash
# 宏 header + 前 64 B 动作（看 16 个 offset、81 7E、type[16]）
mchose-cli readraw 0C 0 128

# 整个宏区（147 包；保存原始字节，后续解析/备份）
mchose-cli readraw 0C 0 8192 > /tmp/ace68-macro-8192.hex

# 只读第二个 56 B 包，确认 offset 递增
mchose-cli readraw 0C 56 56
```

判读：

- 前 32 B 应是 16 个 uint16 小端，第一个通常 `40 00`（空槽）；
- `[32]=81 [33]=7E`；
- `[34..49]` 是 16 个 type；
- 从 `[64]` 开始每 4 B 一个动作；空槽是 `04 00 80 00`。

### 7.2 逐键灯

```bash
# profile 0 的主键 128 色（384 B）
mchose-cli readraw 0A 0 384

# profile 1
mchose-cli readraw 0A 512 384

# profile 2
mchose-cli readraw 0A 1024 384

# 单键：key 0 的 RGB
mchose-cli readraw 0A 0 3
```

### 7.3 旧 keymap / FN 层

```bash
# profile 0, layer 0 (Windows base)
mchose-cli readraw 08 0 384

# layer 1 (Windows FN) = 512*(4*0+1)
mchose-cli readraw 08 512 384

# layer 2 (macOS base)
mchose-cli readraw 08 1024 384

# layer 3 (macOS FN)
mchose-cli readraw 08 1536 384

# profile 1 layer 0
mchose-cli readraw 08 2048 384
```

每 3 B 一键；找 `F0 FF 01` / `F0 FF 03` 可确认 FN 键位置。

### 7.4 base / func / 默认键

```bash
mchose-cli readraw 04 0 56     # base：01 03 00 01 02 03 ...
mchose-cli readraw 03 0 56     # getInfo
mchose-cli readraw 05 0 64     # profile 0 func config
mchose-cli readraw 05 64 64    # profile 1
mchose-cli readraw 07 0 384    # profile 0 layer 0 默认键
mchose-cli readraw 08 0 384    # profile 0 layer 0 当前键
mchose-cli readraw A0 0 1024   # profile 0 磁轴（只读）
```

### 7.5 读不了的（需要临时只读探针，不是 readraw）

`0x202`/`0x308` 需要 payload（`[layer, rc, count]`），且走 **report 77**；`0x900`/`0x205` 也走 report 77。`readraw` 只发 report 0、且不能带 payload，**不能验证**。

后续如果要只读确认 SOCD/FN 新编码，需要加一个**只读**命令：

```
report 77 输出帧：
[01,03,len, cmdLo=02, cmdHi=02, 00, seq] + [layerIndex, matrixRC, count] + [xor]
```

解析响应 `[01,03,len,02,02,00,seq] + records + [xor]`。只发 0x202 读，不发 0x308，是安全的。**本次不实现、不写设备**。

> 注意：正常模式 report 77 的 data 上限是 23 B，一次最多读 7 个 3 B 记录；读整层需要按行/列循环。<br>
> `MATRIX_SIZE.col` 和 `MATRIX_SIZE.row` 也必须从 `0x202` 的记录反推（或从设备矩阵配置读），不要直接假设 18。

---

## 8. 未验证 / 待实机确认清单

| 项 | 当前结论 | 验证方式 |
|---|---|---|
| 宏槽数 16 | SDK `MAX_MACRO_LENGTH=16`；实机 header 应 64 B | `readraw 0C 0 64` |
| 宏区 8192 shared | base `01 03 00 01 02 03` + type 211 + init 逻辑 | `readraw 04 0 56`；`readraw 0C 0 128` |
| 宏 offset/回读逐字节 | SDK 重算并去重；固件可能重排 | 写已知宏后 `0C` 回读比较（需写） |
| 宏 type 播放语义 | 固件值 0/2/1，UI 0/1/255；名字未知 | 只读 type + UI 行为对照 |
| SOCD priority 名 | 只有 0..3 与组合约束 | 读 `0x202` + UI 文案对照 |
| SOCD 最大对数 | 理论 64，无常量 | 读 `0x202` 统计 |
| `MATRIX_SIZE.col` | bundle 68 键表为 6×18；实际未读 | `0x202` 读记录反推 |
| per-key 激活方式 | 自定义灯效/`colorIndex=9` 推论 | 先 `0x05` 读当前 effect（只读） |
| per-key 索引=keyIndex | 从 `setSingleKeyColor(3*key)` 与 UI 路径推断 | 写单键后 `0x0A` 回读（需写） |
| 侧灯索引 | main/side/side2 分段，具体 range 未列 | `getKeyCustomLight` scopes 读 |
| 0x202 与 0x08 是否同源 | 未知；两套路径并存 | 两者只读对比同层 |
| 独立宏 0x90B | 仅 macroConfig=independent 时用 | `0x900`（report77，需探针） |
| flash 持久化 | 无 commit；疑似立即落盘 | 写后断电/重连回读（需写） |

---

## 9. 证据附录（关键 snippet）

### 9.1 常量

`mod34968.pretty.js:6`：

```js
var r=4, a=5, o=128, i=o, c=50, s=4, l=3, u=20, d=20, f=10, p=16;
// MAX_LAYER=4, MIN_MACRO_DELAY=5, DEFAULT_MAX_KEY_COUNT=128,
// MAX_DEAD_ZONE=50, MAX_KEYBOARD_PROFILE_LENGTH=4, MAX_MACRO_LENGTH=16
```

### 9.2 宏通道

`mod39318.pretty.js:943-989`：

```js
async setMacros(t,n){
  let r=this.macroMode.size, a=this.macroMode.shared?0:t*r;
  U()(n.length<=r,"宏长度溢出");
  await this._simpleSendCommand(13,a,n);
}
async getMacros(t){
  let r=this.macroMode.size, a=this.macroMode.shared?0:t*r;
  return await this._simpleGetCommand(12,a,r);
}
async getMacroPacket(t,n){
  let r=this.macroMode.size,
      a=this.macroMode.shared?0+56*n:t*r+56*n,
      o=Math.min(56,r-56*n);
  U()(n<this.maxMacroPacketCount,"packetIndex 超出宏区域");
  return await this._simpleGetCommand(12,a,o);
}
get maxMacroPacketCount(){ return Math.ceil(this.macroMode.size/56); }
```

### 9.3 宏 header

`mod14905.pretty.js:639-670`：

```js
let a=...Date.now(),
    o=Array(2*l.Lj).fill(0),      // 16 × uint16
    s=[...$([])],                  // empty actions
    c={}, [d,u]=(0,j.qW)(64);
c[this._getMacroActionsHash([])]=[d,u];
for(let e=0;e<l.Lj;e++){
  let n=$(ee(t[e].macroActions)),
      [i,r]=(0,j.qW)(64+s.length);
  o[2*e]=i; o[2*e+1]=r; s.push(...n);
}
let f=Array(2*l.Lj).fill(0);
f[0]=129; f[1]=126;
for(let e=0;e<l.Lj;e++) f[e+2]=(...type...)&&255;
let h=[...o,...f,...s];
```

### 9.4 宏动作

`mod39318.pretty.js:1686-1745`：

```js
SerializeMacroActions(e){
  if(0===e.length) return this.SerializeMacroActionItem(
    [{type:"time",delay:P.MIN_MACRO_DELAY-1}, void 0], !0);
  ...
}
SerializeMacroActionItem(t,n){
  var u=new Array(4).fill(0),
      d=(0,r.hJ)(s?.delay<5 ? Math.max(4,0) : s.delay);
  u[0]=d[0]; u[1]=d[1];
  var f=255&(l?.code??0), p=l?.action||"", h=(l?.code??0)>>8&255;
  u[2]=(n?128:0)|(["keydown","mousedown"].includes(p)?64:0)|
       (h in ACTION_DICT?h:MacroDelay.type);
  u[3]=f;
  return u;
}
```

### 9.5 逐键灯

`mod39318.pretty.js:1047-1185`：

```js
setSingleKeyColor(t,n,r){
  return this._simpleSendCommand(11, this.totalLightAreaSize*t+3*n, r);
}
getKeyCustomLight(t,n){
  let r=t*this.totalLightAreaSize, a=new Array(512).fill(0),
      o=this.departLightColors(a.slice(0,384),n).inRange;
  await Promise.all(o.map(e =>
    this._simpleGetCommand(10, r+e.start, e.value.length)
      .then(n => { for(let o=0;o<n.length;o++) a[e.start+o]=n[o]; })));
}
```

### 9.6 旧 keymap

`mod39318.pretty.js:391-405`：

```js
getKeyMatrix(t,n){
  return this._simpleGetCommand(n?7:8, this.totalKeyAreaSize*t, this.usedKeyAreaSize);
}
```

`mod39318.pretty.js:929-941`：

```js
setUserKeyMatrix(t,n,r,a,o){
  let i=this.totalKeyAreaSize, c=i*P.MAX_LAYER,
      s=i*r+3*a+n*c;
  return this._simpleSendCommand(9, s, t, o);
}
// 参数：r=layer, n=profile, a=keyIndex；即 512*layer + 2048*profile + 3*key
```

### 9.7 SOCD

`mod39318.pretty.js:1916-1929`：

```js
parseSOCDBytes(e){
  var t=3&e[2], n=!(128&e[2]), r=parseMatrixIndex(e[1]);
  return { priority:t, isPadLeft:n,
           targetArrIndex:r.row*MATRIX_SIZE.col+r.col,
           keyItem:KG(e.slice(3,6)) };
}
toSOCDBytes(e){
  var t=Math.floor(e.targetArrIndex/MATRIX_SIZE.col),
      n=Math.floor(e.targetArrIndex%MATRIX_SIZE.col);
  return Qc([36, toMatrixRC({row:t,col:n}),
             3&e.priority|(e.isPadLeft?0:128),
             ...YV(e.keyItem)]);
}
```

### 9.8 新 key config

`mod39318.pretty.js:3026-3070`：

```js
getKeyConfigs(n,r,a){
  let o=t.toLayerIndex({profileIndex:n,profileKeyboardLayer:r}),
      i=(a??{}).matrixList,
      c=i??this.allMatrixList;
  return this._getContinuousKeyBytes(514,[o],{
    minChunkSize:me.bs,
    dataToChunksBytes:(e,t)=>{ let n=t.start;
      return me.bp(e).map((e,t)=>({...n, col:n.col+t, bytes:e}));
    },
    matrixList:c
  });
}
setKeyConfigs(n,r,a){
  let o=t.toLayerIndex({profileIndex:n,profileKeyboardLayer:r});
  return this._setContinuousKeyBytes(776,[o],a,{requireFullWrite:!1});
}
```

### 9.9 FN 新编码

`app/2233-a3005d7f2c1e6167.js @537270`：

```js
if(e.bytes[0]===N.OT.FN.type && !d()(e.bytes[1],0,4)){
  let t=e.bytes.slice();
  t[1]=e.bytes[1]%4;
  return {...e, bytes:nO(t)};
}
// FN.type = 50 → [50, layer, 0]
```

### 9.10 设备默认 manufacturer

`app/1288-10a068b06ab7ba15.js`（模块 83050）：

```js
function eq(e,t,o){
  var n; let a=et(e,t,o);
  return null!==(n=a?.manufacturer)&&void 0!==n?n:"glw";
}
```

Ace68 Turbo 16K 条目无 `manufacturer` → `glw` → 官方 UI 走 `0x202/0x308`。

### 9.11 宏模式初始化

`app/2233-a3005d7f2c1e6167.js @~235200`：

```js
let {supportMultiProfile:l,supportOrderProfile:a,maxKeyboardProfileLength:o}=await e.getBase(),
    s=(0,u.l7)(vendorId,pid,productName);
l&&a
  ? e.changeMacroMode({size:[101,130,131,132].includes(s)?4096:8192,shared:!0})
  : e.changeMacroMode({size:2048,shared:!1});
```

---

## 10. 最小解析伪代码

### 10.1 宏 header/槽

```python
def parse_macro_region(b):              # b = 8192 bytes from 0x0C
    assert b[32] == 0x81 and b[33] == 0x7E
    offs = [int.from_bytes(b[2*i:2*i+2], 'little') for i in range(16)]
    types = list(b[34:50])
    slots = []
    for i, off in enumerate(offs):
        acts = []
        j = off
        while j + 4 <= len(b):
            d = int.from_bytes(b[j:j+2], 'little')
            flags = b[j+2]
            code = ((flags & 0x3F) << 8) | b[j+3]
            acts.append({
                'delay_ms': d,
                'is_end': bool(flags & 0x80),
                'down': bool(flags & 0x40),
                'type': flags & 0x3F,
                'code': code,
            })
            j += 4
            if flags & 0x80:
                break
        slots.append({'offset': off, 'type': types[i], 'actions': acts})
    return slots
```

### 10.2 SOCD 记录

```python
def parse_socd(rec):                    # rec 8 bytes
    assert rec[0] == 36
    return {
        'target_rc': rec[1],
        'is_pad_left': (rec[2] & 0x80) == 0,
        'priority': rec[2] & 3,
        'key': (rec[3], rec[4], rec[5]),
        'pad': rec[6:8],
    }
```

### 10.3 逐键颜色

```python
def parse_colors(b):                    # b = 384 bytes
    return [tuple(b[i:i+3]) for i in range(0, len(b), 3)]
```

---

## 11. 备注：与现有文档/任务描述的差异

- 任务描述里 “base 读=0x0D” 是笔误；`0x0D` 是宏写，base 读 `0x04`。
- `docs/captures/ace68-feature-protocol.md` 的帧格式、键位偏移、命令表与 bundle 一致；本文件补充宏/SOCD/逐键/FN 的 payload 细节。
- `macroSlots=null`：从 SDK 推断 16；实机 `0x0C` header 可确认。
- 现有 Swift 读 `0x08` 得到的 layer0/2 Esc、layer1/3 反引号是旧 keymap 视图，不代表官方 GLW UI 的新 key config 视图；两者需只读对比后再写。
- 本次未改代码、未提交 git、未向设备写任何字节。
