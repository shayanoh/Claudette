import Foundation

public struct ClaudetteSettings: Codable, Equatable, Sendable {
  public var scale: Double = 1.0
  public var hoverFadeEnabled = true
  public var hoverFadeOpacity = 0.25
  public var dodgeEnabled = true
  public var shyness = 0.5
  public var privacyMode = false
  public var focusMode = false
  public var reduceMotion = false
  public var launchAtLogin = false
  /// She may sit on the top edge of other windows.
  public var perchEnabled = true
  /// Hovering a Claudette shows her project (folder or worktree) under her.
  public var showProjectName = true
  /// Most items allowed on screen at once; beyond it the oldest resting ones are swept away.
  public var itemCap = 80
  /// A Claudette tidies up after herself when her session waits for you and her clutter is over the limit.
  public var autoCleanup = true
  public var clutterSoftLimit = 12
  /// Where the weekly moon was dropped, as a fraction (0...1) of the main display's visible frame;
  /// nil means its default corner. Both are set or both are nil.
  public var moonX: Double?
  public var moonY: Double?

  public init() {}

  /// Missing keys keep their defaults, so adding a setting later never wipes stored ones.
  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
      (try? c.decodeIfPresent(T.self, forKey: key)) ?? fallback
    }
    let d = ClaudetteSettings()
    scale = value(.scale, d.scale)
    hoverFadeEnabled = value(.hoverFadeEnabled, d.hoverFadeEnabled)
    hoverFadeOpacity = value(.hoverFadeOpacity, d.hoverFadeOpacity)
    dodgeEnabled = value(.dodgeEnabled, d.dodgeEnabled)
    shyness = value(.shyness, d.shyness)
    privacyMode = value(.privacyMode, d.privacyMode)
    focusMode = value(.focusMode, d.focusMode)
    reduceMotion = value(.reduceMotion, d.reduceMotion)
    launchAtLogin = value(.launchAtLogin, d.launchAtLogin)
    perchEnabled = value(.perchEnabled, d.perchEnabled)
    showProjectName = value(.showProjectName, d.showProjectName)
    itemCap = value(.itemCap, d.itemCap)
    autoCleanup = value(.autoCleanup, d.autoCleanup)
    clutterSoftLimit = value(.clutterSoftLimit, d.clutterSoftLimit)
    moonX = (try? c.decodeIfPresent(Double.self, forKey: .moonX)) ?? nil
    moonY = (try? c.decodeIfPresent(Double.self, forKey: .moonY)) ?? nil
  }

  /// Forces every value into its allowed range; non-finite values fall back to the default.
  public func clamped() -> ClaudetteSettings {
    func fit(_ v: Double, _ range: ClosedRange<Double>, _ fallback: Double) -> Double {
      v.isFinite ? min(range.upperBound, max(range.lowerBound, v)) : fallback
    }
    var s = self
    s.scale = fit(scale, 0.5...2.0, 1.0)
    s.hoverFadeOpacity = fit(hoverFadeOpacity, 0.2...0.3, 0.25)
    s.shyness = fit(shyness, 0...1, 0.5)
    s.itemCap = min(120, max(20, itemCap))
    s.clutterSoftLimit = min(40, max(4, clutterSoftLimit))
    if let x = moonX, let y = moonY, x.isFinite, y.isFinite {
      s.moonX = min(1, max(0, x))
      s.moonY = min(1, max(0, y))
    } else {
      s.moonX = nil
      s.moonY = nil
    }
    return s
  }
}

/// Persists settings as one JSON blob in `UserDefaults`.
public final class SettingsStore {
  public static let key = "claudette.settings"

  public private(set) var settings: ClaudetteSettings
  public var onChange: ((ClaudetteSettings) -> Void)?
  private let defaults: UserDefaults

  public init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    if let data = defaults.data(forKey: Self.key),
      let stored = try? JSONDecoder().decode(ClaudetteSettings.self, from: data)
    {
      settings = stored.clamped()
    } else {
      settings = ClaudetteSettings()
    }
  }

  public func update(_ change: (inout ClaudetteSettings) -> Void) {
    var next = settings
    change(&next)
    settings = next.clamped()
    if let data = try? JSONEncoder().encode(settings) { defaults.set(data, forKey: Self.key) }
    onChange?(settings)
  }
}
