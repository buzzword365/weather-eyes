// Weather Eyes — live wallpaper
// Puts eyes.html behind your desktop icons on every screen and feeds it your cursor.

import Cocoa
import WebKit
import ServiceManagement

private struct PlaceMatch: Decodable {
    let name: String
    let admin1: String?
    let country: String?
    let latitude: Double
    let longitude: Double
    var label: String { [name, admin1, country].compactMap { $0 }.joined(separator: ", ") }
}
private struct PlaceSearchResponse: Decodable {
    let results: [PlaceMatch]?
}
final class WallWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class AppDelegate: NSObject, NSApplicationDelegate, WKNavigationDelegate {
    var walls: [(window: NSWindow, web: WKWebView)] = []
    var statusItem: NSStatusItem!
    var locationLabel: NSMenuItem?
    private let locationNameKey = "WeatherEyesLocationName"
    private let latitudeKey = "WeatherEyesLatitude"
    private let longitudeKey = "WeatherEyesLongitude"
    var loginItem: NSMenuItem?
    var timer: Timer?
    var lastMouse = NSPoint(x: -99999, y: -99999)

    func applicationDidFinishLaunching(_ note: Notification) {
        buildWalls()
        buildMenu()
        // Start with the Mac automatically, once, the first time it runs
        if #available(macOS 13.0, *), !UserDefaults.standard.bool(forKey: "didSetLogin") {
            try? SMAppService.mainApp.register()
            UserDefaults.standard.set(true, forKey: "didSetLogin")
            loginItem?.state = SMAppService.mainApp.status == .enabled ? .on : .off
        }
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(rebuild), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(refreshWeather), name: NSWorkspace.didWakeNotification, object: nil)

        // Cursor position: no special permission needed to read it.
        timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer!, forMode: .common)

        // Clicks anywhere make the eyes flinch.
        NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.js("window.eyes && eyes.click()")
        }
    }

    // MARK: wallpaper windows

    @objc func rebuild() { buildWalls() }

    func buildWalls() {
        walls.forEach { $0.window.orderOut(nil) }
        walls.removeAll()
        guard let page = Bundle.main.url(forResource: "eyes", withExtension: "html") else {
            NSLog("eyes.html missing from the app bundle"); return
        }
        for screen in NSScreen.screens {
            let win = WallWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            win.setFrame(screen.frame, display: false)
            win.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
            win.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
            win.ignoresMouseEvents = true
            win.isOpaque = true
            win.hasShadow = false
            win.backgroundColor = .black

            let config = WKWebViewConfiguration()
            config.userContentController.addUserScript(
                WKUserScript(source: "window.__EYES_APP = true;" + initialLocationScript(),
                             injectionTime: .atDocumentStart, forMainFrameOnly: true))
            let web = WKWebView(frame: NSRect(origin: .zero, size: screen.frame.size), configuration: config)
            web.autoresizingMask = [.width, .height]
            web.navigationDelegate = self
            web.loadFileURL(page, allowingReadAccessTo: page.deletingLastPathComponent())
            win.contentView = web
            win.orderFront(nil)
            walls.append((win, web))
        }
        lastMouse = NSPoint(x: -99999, y: -99999)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        lastMouse = NSPoint(x: -99999, y: -99999)
    }

    func tick() {
        let m = NSEvent.mouseLocation
        guard m != lastMouse else { return }
        lastMouse = m
        for wall in walls {
            let f = wall.window.frame
            let x = m.x - f.minX, y = f.maxY - m.y   // flip to top-left origin
            wall.web.evaluateJavaScript("window.eyes && eyes.cursor(\(x),\(y))", completionHandler: nil)
        }
    }

    func js(_ code: String) { walls.forEach { $0.web.evaluateJavaScript(code, completionHandler: nil) } }

    // MARK: menu bar

    func buildMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "👀"
        let menu = NSMenu()
        let title = NSMenuItem(title: "Weather Eyes", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        menu.addItem(.separator())

        let place = NSMenuItem(title: "Location: Automatic (approximate)", action: nil, keyEquivalent: "")
        place.isEnabled = false
        locationLabel = place
        updateLocationLabel()
        menu.addItem(place)

        let setPlace = NSMenuItem(title: "Set Weather Location…", action: #selector(promptForLocation), keyEquivalent: "")
        setPlace.target = self
        menu.addItem(setPlace)

        let automatic = NSMenuItem(title: "Use Automatic Approximate Location", action: #selector(useApproximateLocation), keyEquivalent: "")
        automatic.target = self
        menu.addItem(automatic)

        let refresh = NSMenuItem(title: "Refresh Weather", action: #selector(refreshWeather), keyEquivalent: "r")
        refresh.target = self
        menu.addItem(refresh)

        if #available(macOS 13.0, *) {
            let login = NSMenuItem(title: "Open at Login", action: #selector(toggleLogin), keyEquivalent: "")
            login.target = self
            login.state = SMAppService.mainApp.status == .enabled ? .on : .off
            menu.addItem(login)
            loginItem = login
        }
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Weather Eyes", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    private func savedCoordinates() -> (Double, Double)? {
        let defaults = UserDefaults.standard
        guard let lat = defaults.object(forKey: latitudeKey) as? Double,
              let lon = defaults.object(forKey: longitudeKey) as? Double,
              (-90...90).contains(lat), (-180...180).contains(lon) else { return nil }
        return (lat, lon)
    }

    private func initialLocationScript() -> String {
        guard let (lat, lon) = savedCoordinates() else { return "" }
        return "window.__EYES_LOCATION = {lat:\(lat), lon:\(lon)};"
    }

    private func updateLocationLabel() {
        let name = UserDefaults.standard.string(forKey: locationNameKey)
        locationLabel?.title = name.map { "Location: \($0)" } ?? "Location: Automatic (approximate)"
    }

    private func showMessage(_ title: String, _ detail: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.runModal()
    }

    @objc private func promptForLocation() {
        let alert = NSAlert()
        alert.messageText = "Choose your weather location"
        alert.informativeText = "Enter a city or suburb (optionally followed by state and country). Search results come from Open-Meteo. Your selected location is saved on this Mac, not in the app's code."
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 370, height: 26))
        input.placeholderString = "e.g. Paris, France"
        input.stringValue = UserDefaults.standard.string(forKey: locationNameKey) ?? ""
        alert.accessoryView = input
        alert.addButton(withTitle: "Search")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let entered = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = entered.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard let city = parts.first, city.count >= 2 else {
            showMessage("Enter a location", "Please enter at least two characters.")
            return
        }
        var urlParts = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        urlParts.queryItems = [
            URLQueryItem(name: "name", value: city),
            URLQueryItem(name: "count", value: "40"),
            URLQueryItem(name: "language", value: "en"),
            URLQueryItem(name: "format", value: "json")
        ]
        guard let url = urlParts.url else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            let places: [PlaceMatch]
            if error == nil,
               let response = response as? HTTPURLResponse, (200...299).contains(response.statusCode),
               let data = data,
               let decoded = try? JSONDecoder().decode(PlaceSearchResponse.self, from: data) {
                places = decoded.results ?? []
            } else {
                places = []
            }
            DispatchQueue.main.async {
                guard let self = self else { return }
                guard !places.isEmpty else {
                    self.showMessage("Couldn't find that location", "Check the spelling and your internet connection, then try again.")
                    return
                }
                let hints = parts.dropFirst().map { $0.lowercased() }.filter { !$0.isEmpty }
                let preferred = places.filter { place in
                    let label = place.label.lowercased()
                    return hints.allSatisfy { label.contains($0) }
                }
                self.chooseLocation(preferred.isEmpty ? Array(places.prefix(20)) : Array(preferred.prefix(20)))
            }
        }.resume()
    }

    private func chooseLocation(_ places: [PlaceMatch]) {
        let alert = NSAlert()
        alert.messageText = "Select the matching place"
        alert.informativeText = "Choose the correct city or suburb. Only its name and coordinates are saved locally."
        let picker = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 370, height: 28), pullsDown: false)
        picker.addItems(withTitles: places.map { $0.label })
        alert.accessoryView = picker
        alert.addButton(withTitle: "Use This Location")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn, picker.indexOfSelectedItem >= 0 else { return }
        let place = places[picker.indexOfSelectedItem]
        let defaults = UserDefaults.standard
        defaults.set(place.label, forKey: locationNameKey)
        defaults.set(place.latitude, forKey: latitudeKey)
        defaults.set(place.longitude, forKey: longitudeKey)
        updateLocationLabel()
        js("window.eyes && eyes.setLocation({lat:\(place.latitude),lon:\(place.longitude)})")
    }

    @objc private func useApproximateLocation() {
        let defaults = UserDefaults.standard
        for key in [locationNameKey, latitudeKey, longitudeKey] { defaults.removeObject(forKey: key) }
        updateLocationLabel()
        js("window.eyes && eyes.setLocation(null)")
    }

    @objc func refreshWeather() { js("window.eyes && eyes.refresh()") }

    @objc func toggleLogin() {
        guard #available(macOS 13.0, *) else { return }
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn't change Open at Login"
            alert.informativeText = "Move Weather Eyes to your Applications folder and try again, or add it in System Settings → General → Login Items.\n\n\(error.localizedDescription)"
            alert.runModal()
        }
        loginItem?.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
