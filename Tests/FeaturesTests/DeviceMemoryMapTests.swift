import Testing
@testable import Features

@Test func keymapOffsetMatchesVendorLayout() {
    // totalKeyAreaSize (512) * (MAX_LAYER (4) * profile + layer)
    #expect(DeviceMemoryMap.keymapOffset(profile: 0, layer: 0) == 0)
    #expect(DeviceMemoryMap.keymapOffset(profile: 0, layer: 1) == 512)
    #expect(DeviceMemoryMap.keymapOffset(profile: 1, layer: 0) == 2048)
    #expect(DeviceMemoryMap.keymapOffset(profile: 1, layer: 2) == 2048 + 1024)
    #expect(DeviceMemoryMap.keymapOffset(profile: 3, layer: 3) == 512 * 15)
}

@Test func triggerOffsetMatchesVendorLayout() {
    #expect(DeviceMemoryMap.triggerOffset(profile: 0) == 0)
    #expect(DeviceMemoryMap.triggerOffset(profile: 1) == 1024)
    #expect(DeviceMemoryMap.triggerOffset(profile: 3) == 3072)
}

@Test func funcConfigOffsetMatchesVendorLayout() {
    #expect(DeviceMemoryMap.funcConfigOffset(profile: 0) == 0)
    #expect(DeviceMemoryMap.funcConfigOffset(profile: 1) == 64)
}

@Test func areaSizesMatchCapture() {
    #expect(DeviceMemoryMap.usedKeyAreaSize == 384)
    #expect(DeviceMemoryMap.totalKeyAreaSize == 512)
    #expect(DeviceMemoryMap.triggerAreaSize == 1024)
    #expect(DeviceMemoryMap.funcConfigSize == 64)
    #expect(DeviceMemoryMap.baseSize == 56)
    #expect(DeviceMemoryMap.layers == 4)
}
