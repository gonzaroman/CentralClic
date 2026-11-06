import AppKit
import SwiftUI

extension MouseButton {
    var color: Color { Color(nsColor: nsColor) }
}

enum SettingsTab: Hashable {
    case clicks, movement, about
}

/// Selected tab. A small observable object instead of @State, which is a macro in recent SDKs
/// and needs a compiler plugin the Command Line Tools don't find.
final class TabSelection: ObservableObject {
    @Published var tab: SettingsTab
    init(_ tab: SettingsTab) { self.tab = tab }
}

/// Settings window, with the Clicks, Movement and About tabs.
struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var live = LiveTouches.shared
    @ObservedObject private var selection: TabSelection
    private let openAccessibility: () -> Void

    init(initialTab: SettingsTab = .clicks, openAccessibility: @escaping () -> Void = {}) {
        selection = TabSelection(initialTab)
        self.openAccessibility = openAccessibility
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Toggle(L("Enabled"), isOn: $settings.enabled).toggleStyle(.switch)
                Spacer()
                StatusPill(ok: live.connectedMice > 0,
                           text: live.connectedMice > 0 ? L("Magic Mouse connected") : L("Magic Mouse not detected"))
            }

            if !live.accessibilityGranted {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L("Accessibility permission is missing")).bold()
                        Text(L("Without it, zone clicks and scrolling don’t work. Turn it on for Magic Middle Click in System Settings → Privacy & Security → Accessibility. If it already appears on, remove it with “–” and add it again: after an update, macOS may see the app as a different one."))
                            .font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button(L("Open Accessibility Settings"), action: openAccessibility)
                    }
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.yellow.opacity(0.12)))
            }

            TabView(selection: $selection.tab) {
                ClicksTab(settings: settings, live: live)
                    .padding(16)
                    .tabItem { Text(L("Clicks")) }
                    .tag(SettingsTab.clicks)
                MotionTab(settings: settings)
                    .padding(16)
                    .tabItem { Text(L("Movement")) }
                    .tag(SettingsTab.movement)
                AboutTab()
                    .padding(16)
                    .tabItem { Text(L("About")) }
                    .tag(SettingsTab.about)
            }

            HStack(spacing: 8) {
                if let click = live.lastClick {
                    Circle().fill(click.color).frame(width: 10, height: 10)
                    Text(L("Last click: %@", click.title))
                } else {
                    Image(systemName: "hand.point.up.left").foregroundStyle(.secondary)
                    Text(L("Put your fingers on the mouse and click to try it.")).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle(L("Open at Login"), isOn: Binding(
                    get: { settings.launchAtLogin },
                    set: { settings.setLaunchAtLogin($0) }))
            }
            .font(.callout)
        }
        .padding(24)
        .frame(width: 540)
    }
}

private struct StatusPill: View {
    let ok: Bool
    let text: String
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(ok ? Color.green : Color.secondary).frame(width: 8, height: 8)
            Text(text).font(.callout)
        }
        .padding(.horizontal, 10).padding(.vertical, 4)
        .background(Capsule().fill(Color.secondary.opacity(0.12)))
    }
}

private struct ZoneSlider: View {
    let title: String
    let color: Color
    let value: Int
    let range: ClosedRange<Int>
    let set: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            // No `step`, so no tick marks are drawn; the value is rounded when saved.
            Slider(value: Binding(get: { Double(value) }, set: { set(Int($0.rounded())) }),
                   in: Double(range.lowerBound)...Double(range.upperBound))
                .tint(color)
        }
    }
}

/// Top view of the Magic Mouse (front pointing up) with the three zones.
private struct MouseZonesView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var live: LiveTouches

    private let shape = RoundedRectangle(cornerRadius: 84, style: .continuous)

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let z = settings.zones
            let x1 = w * CGFloat(z.left) / 100
            let x2 = w * CGFloat(z.left + z.center) / 100

            ZStack(alignment: .topLeading) {
                shape.fill(LinearGradient(colors: [Color(white: 0.99), Color(white: 0.86)],
                                          startPoint: .top, endPoint: .bottom))

                ZStack(alignment: .topLeading) {
                    HStack(spacing: 0) {
                        Rectangle().fill(MouseButton.left.color.opacity(0.32)).frame(width: x1)
                        Rectangle().fill(MouseButton.center.color.opacity(0.38)).frame(width: x2 - x1)
                        Rectangle().fill(MouseButton.right.color.opacity(0.32))
                    }
                    Rectangle().fill(Color.black.opacity(0.45)).frame(width: 2, height: h).offset(x: x1 - 1)
                    Rectangle().fill(Color.black.opacity(0.45)).frame(width: 2, height: h).offset(x: x2 - 1)
                }
                .clipShape(shape)

                shape.stroke(Color.black.opacity(0.25), lineWidth: 1.5)

                ForEach([MouseButton.left, .center, .right], id: \.self) { button in
                    let (from, to): (CGFloat, CGFloat) = button == .left ? (0, x1) : button == .center ? (x1, x2) : (x2, w)
                    Text(button.letter)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(button.color)
                        .position(x: (from + to) / 2, y: h * 0.16)
                }
                DividerHandle()
                    .position(x: x1, y: h * 0.5)
                    .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("mouse"))
                        .onChanged { settings.moveLeftDivider(to: Int(($0.location.x / w * 100).rounded())) })
                DividerHandle()
                    .position(x: x2, y: h * 0.5)
                    .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("mouse"))
                        .onChanged { settings.moveRightDivider(to: Int(($0.location.x / w * 100).rounded())) })

                ForEach(live.points) { p in
                    Circle()
                        .fill(z.button(atX: p.x).color)
                        .frame(width: 22, height: 22)
                        .overlay(Circle().stroke(Color.white, lineWidth: 2))
                        .shadow(color: .black.opacity(0.3), radius: 2)
                        .position(x: CGFloat(p.x) * w, y: (1 - CGFloat(p.y)) * h)
                        .allowsHitTesting(false)
                }
            }
            .coordinateSpace(name: "mouse")
        }
    }
}

private struct DividerHandle: View {
    var body: some View {
        ZStack {
            Circle().fill(Color.white).shadow(color: .black.opacity(0.35), radius: 2)
            Image(systemName: "arrow.left.and.right")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color.black.opacity(0.7))
        }
        .frame(width: 24, height: 24)
        .frame(width: 36, height: 120)
        .contentShape(Rectangle())
        .onHover { inside in
            if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
        }
    }
}

// MARK: - Clicks tab

private struct ClicksTab: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var live: LiveTouches

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L("The mouse surface is split into three strips. The button depends on where your finger is when you press. If there are fingers in several strips, the leftmost one wins (like macOS does with right-click)."))
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .top, spacing: 24) {
                MouseZonesView(settings: settings, live: live)
                    .frame(width: 170, height: 300)

                VStack(alignment: .leading, spacing: 14) {
                    Text(L("Click zones")).font(.headline)
                    ForEach([MouseButton.left, .center, .right], id: \.self) { button in
                        HStack {
                            Circle().fill(button.color).frame(width: 10, height: 10)
                            Text(button.title)
                            Spacer()
                            Text(Double(settings.zones.width(of: button)) / 100,
                                 format: .percent.precision(.fractionLength(0)))
                                .monospacedDigit().bold()
                        }
                    }

                    ZoneSlider(title: MouseButton.left.title, color: MouseButton.left.color,
                               value: settings.zones.left, range: ZoneConfig.sliderRange, set: settings.setLeft)
                    ZoneSlider(title: MouseButton.right.title, color: MouseButton.right.color,
                               value: settings.zones.right, range: ZoneConfig.sliderRange, set: settings.setRight)
                    Text(L("The middle zone takes the rest. The left zone never goes below %ld%% so you can always click normally. You can also drag the lines on the mouse.", ZoneConfig.minimumLeft))
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button(L("Reset")) { settings.resetZones() }
                        .disabled(settings.zones == .default)
                }
            }
        }
    }
}

// MARK: - Movement tab

private struct MotionTab: View {
    @ObservedObject var settings: AppSettings
    private let tuning = MouseTuning.shared

    var body: some View {
        let systemNatural = tuning.systemNaturalScroll
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .center, spacing: 14) {
                Button { settings.optimize() } label: {
                    Label(L("Optimize"), systemImage: "wand.and.stars")
                        .padding(.horizontal, 6)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                Text(L("Sets classic scrolling and a Windows-like pointer speed. macOS pointer acceleration has to be off: if it's on, it opens System Settings and finishes as soon as you turn it off."))
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if settings.optimizeWaitingForMacOS {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "hourglass").foregroundStyle(.orange)
                    Text(L("Turn off Pointer acceleration in System Settings → Mouse → Advanced. Magic Middle Click will set the speed as soon as it's off."))
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.12)))
            }

            SpeedRow(title: L("Pointer speed"),
                     value: settings.pointerSpeed,
                     systemValue: tuning.systemPointerSpeed,
                     range: MouseTuning.pointerRange,
                     note: L("System Settings goes up to %@; here you can go further.", SpeedRow.format(MouseTuning.systemPointerMax)),
                     set: { settings.pointerSpeed = $0 })

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(L("Pointer acceleration (macOS)")).font(.headline)
                    Spacer()
                    HStack(spacing: 6) {
                        Circle()
                            .fill(settings.systemAccelerationOff ? Color.green : Color.orange)
                            .frame(width: 8, height: 8)
                        Text(settings.systemAccelerationOff ? L("Off") : L("On"))
                    }
                    Button(L("Open Mouse Settings…")) { MouseTuning.shared.openMouseSettings() }
                        .controlSize(.small)
                }
                Text(L("Most people coming from Windows prefer it off: the pointer moves the same distance for the same hand movement. Turn it off in System Settings → Mouse → Advanced. The speed above keeps working."))
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            SpeedRow(title: L("Scrolling speed"),
                     value: settings.scrollMultiplier,
                     systemValue: 1,
                     range: MouseTuning.scrollMultiplierRange,
                     note: L("When you slide your finger on the mouse. ×1 is the macOS speed. Magic Mouse only."),
                     format: { "×" + SpeedRow.format($0) },
                     set: { settings.scrollMultiplier = $0 })

            VStack(alignment: .leading, spacing: 8) {
                Text(L("Scroll direction")).font(.headline)
                Picker(L("Direction"), selection: Binding(
                    get: { settings.naturalScroll ?? systemNatural },
                    set: { settings.naturalScroll = $0 })) {
                    Text(L("Natural")).tag(true)
                    Text(L("Classic")).tag(false)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                Text(L("Natural: content follows your finger, like on iPhone. Classic: like a mouse wheel. Only the Magic Mouse changes; the trackpad keeps the macOS setting (currently %@).",
                       systemNatural ? L("natural") : L("classic")))
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(L("Pointer speed affects mice, not the trackpad. Scrolling and its direction need the Accessibility permission. If you turn Magic Middle Click off or quit it, the macOS settings come back."))
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}

private struct SpeedRow: View {
    let title: String
    let value: Double?
    let systemValue: Double
    let range: ClosedRange<Double>
    let note: String
    var format: (Double) -> String = SpeedRow.format
    let set: (Double?) -> Void

    /// One decimal, with the user's decimal separator.
    static func format(_ v: Double) -> String { v.formatted(.number.precision(.fractionLength(1))) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                if let value {
                    Text(format(value)).monospacedDigit().bold()
                } else {
                    Text(L("macOS (%@)", format(systemValue))).foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 8) {
                Image(systemName: "tortoise").foregroundStyle(.secondary)
                Slider(value: Binding(get: { value ?? systemValue },
                                      set: { set(($0 * 10).rounded() / 10) }),
                       in: range)
                Image(systemName: "hare").foregroundStyle(.secondary)
            }
            HStack {
                Text(note).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(L("Use macOS Setting")) { set(nil) }
                    .controlSize(.small)
                    .disabled(value == nil)
            }
        }
    }
}

// MARK: - About tab

private struct AboutTab: View {
    @ObservedObject private var updater = Updater.shared

    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 72, height: 72)
            VStack(spacing: 4) {
                Text("Magic Middle Click").font(.title2.bold())
                Text(L("Version %@", updater.currentVersion)).foregroundStyle(.secondary)
                Text(L("Middle click, zones and speed for the Magic Mouse.")).font(.callout)
            }

            GroupBox(L("Updates")) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(statusText).font(.callout)
                        Spacer()
                        Button(L("Check Now")) { updater.check() }
                            .disabled(updater.checking)
                    }
                    if let release = updater.available {
                        Button(L("Download version %@", release.version)) { updater.openDownload() }
                            .buttonStyle(.borderedProminent)
                    }
                    Toggle(L("Check for updates automatically"), isOn: $updater.automaticChecks)
                    Text(L("Once a day, Magic Middle Click asks GitHub whether there is a new version. No personal data is sent."))
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            VStack(spacing: 10) {
                Text(L("Do you like Magic Middle Click? A star on GitHub or sharing it with a friend helps a lot."))
                    .font(.callout)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 12) {
                    Button { Project.openRepository() } label: {
                        Label(L("Star on GitHub"), systemImage: "star.fill")
                    }
                    ShareLink(item: Project.url, subject: Text("Magic Middle Click"), message: Text(Project.shareMessage)) {
                        Label(L("Share"), systemImage: "square.and.arrow.up")
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }

    private var statusText: String {
        if updater.checking { return L("Checking…") }
        if let release = updater.available { return L("Version %@ is available.", release.version) }
        if updater.failed { return L("Couldn’t check for updates.") }
        if updater.lastCheck != nil { return L("Magic Middle Click is up to date.") }
        return L("Not checked yet.")
    }
}
