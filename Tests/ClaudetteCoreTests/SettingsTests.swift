import Foundation
import Testing

@testable import ClaudetteCore

private func freshDefaults() -> UserDefaults {
  let name = "claudette-test-\(UUID().uuidString)"
  let d = UserDefaults(suiteName: name)!
  d.removePersistentDomain(forName: name)
  return d
}

@Test func defaultsMatchSpec() {
  let s = ClaudetteSettings()
  #expect(s.scale == 1.0)
  #expect(s.hoverFadeEnabled)
  #expect(s.hoverFadeOpacity == 0.25)
  #expect(s.dodgeEnabled)
  #expect(s.shyness == 0.5)
  #expect(!s.privacyMode && !s.focusMode && !s.reduceMotion && !s.launchAtLogin)
}

@Test func clampsScaleTo0_5Through2_0() {
  var s = ClaudetteSettings()
  s.scale = 0.1
  #expect(s.clamped().scale == 0.5)
  s.scale = 9
  #expect(s.clamped().scale == 2.0)
  s.scale = .nan
  #expect(s.clamped().scale == 1.0)
}

@Test func clampsOpacityTo0_2Through0_3() {
  var s = ClaudetteSettings()
  s.hoverFadeOpacity = 0.0
  #expect(s.clamped().hoverFadeOpacity == 0.2)
  s.hoverFadeOpacity = 1.0
  #expect(s.clamped().hoverFadeOpacity == 0.3)
  s.hoverFadeOpacity = .infinity
  #expect(s.clamped().hoverFadeOpacity == 0.25)
}

@Test func clampsShynessTo0Through1() {
  var s = ClaudetteSettings()
  s.shyness = -1
  #expect(s.clamped().shyness == 0)
  s.shyness = 7
  #expect(s.clamped().shyness == 1)
}

@Test func persistsAcrossInstances() {
  let d = freshDefaults()
  let a = SettingsStore(defaults: d)
  a.update {
    $0.scale = 1.5
    $0.privacyMode = true
  }
  let b = SettingsStore(defaults: d)
  #expect(b.settings.scale == 1.5)
  #expect(b.settings.privacyMode)
}

@Test func updateClampsBeforeStoring() {
  let store = SettingsStore(defaults: freshDefaults())
  store.update { $0.scale = 50 }
  #expect(store.settings.scale == 2.0)
}

@Test func corruptStoredDataFallsBackToDefaults() {
  let d = freshDefaults()
  d.set(Data("not json at all".utf8), forKey: SettingsStore.key)
  #expect(SettingsStore(defaults: d).settings == ClaudetteSettings())
}

@Test func missingKeysInStoredDataKeepDefaults() {
  let d = freshDefaults()
  d.set(Data(#"{"scale":1.7}"#.utf8), forKey: SettingsStore.key)
  let s = SettingsStore(defaults: d).settings
  #expect(s.scale == 1.7)
  #expect(s.hoverFadeEnabled && s.dodgeEnabled)
}

@Test func onChangeFiresOnUpdateWithNewValue() {
  let store = SettingsStore(defaults: freshDefaults())
  var seen: [ClaudetteSettings] = []
  store.onChange = { seen.append($0) }
  store.update { $0.dodgeEnabled = false }
  #expect(seen.count == 1)
  #expect(seen.first?.dodgeEnabled == false)
}
