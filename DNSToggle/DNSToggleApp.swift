import SwiftUI

@main
struct DNSToggleApp: App {
    @State private var dnsManager = DNSManager.shared
    
    init() {
        UserDefaults.standard.set(1, forKey: AppDefaults.version.rawValue)
    }
    
    var body: some Scene {
        MenuBarExtra("DNSToggle", systemImage: "globe") {
            Menu().environment(dnsManager)
        }
        Settings {
            SettingsView().environment(dnsManager)
        }
    }
}

struct Menu: View {
    @Environment(DNSManager.self) private var dnsManager

    var body: some View {
        VStack {
            ForEach(self.dnsManager.serviceIDs, id:\.self) { serviceID in
                ResolverChooserView(serviceID: serviceID)
                Divider()
            }
            Button {
                NSApplication.shared.orderFrontStandardAboutPanel()
                NSApplication.shared.activate()
            } label: {
                Text("About DNSToggle")
            }
            SettingsLink(label: {
                Text("Settings")
            })
            Button {
                NSApplication.shared.terminate(self)
            } label: {
                Text("Quit")
            }
        }
    }
}

struct ResolverChooserView: View {
    @Environment(DNSManager.self) private var dnsManager
    var serviceID: String
    var serviceName: String {
        return self.dnsManager.serviceName(for: self.serviceID)
    }
    var currentResolvers: [String] {
        return self.dnsManager.currentResolvers(for: self.serviceID)
    }
    var availableResolvers: [[String]] {
        return self.dnsManager.availableResolvers(for: self.serviceID)
    }

    
    var body: some View {
        VStack {
            Text("\(self.serviceName)")
            ForEach(self.availableResolvers, id:\.self) { resolvers in
                Button {
                    self.dnsManager.setResolvers(for: serviceID, resolvers: resolvers)
                } label: {
                    HStack {
                        Image(systemName: resolvers == self.currentResolvers ? "circle.inset.filled" : "circle")
                        Text("\(resolvers.joined(separator: ", "))")
                    }
                }
            }
        }
    }
}

struct SettingsView: View {
    @Environment(DNSManager.self) private var dnsManager
    
    private enum Tabs: Hashable {
        case general
    }
    
    private enum DisplayMode: String {
        case simple = "simple"
        case advanced = "advanced"
    }
    
    var body: some View {
        TabView {
            Group {
                VStack {
                    Form {
                        TextField(text: Binding(get: {
                            self.dnsManager.overrideResolvers.joined(separator: ", ")
                        }, set: { newValue, _ in
                            self.dnsManager.overrideResolvers = newValue.split(separator: ",").map({ substring in
                                substring.trimmingCharacters(in: .whitespaces)
                            })
                        }), prompt: Text("0.0.0.0, ..."), label: {
                            Text("Override Resolvers")
                        })
                    }.padding()
                }
            }.tabItem {
                Label("General", systemImage: "gear")
            }.tag(Tabs.general)
        }
        
    }
}

enum AppDefaults: String {
    case version = "version"
    case overrideResolvers = "overrideResolvers"
}
