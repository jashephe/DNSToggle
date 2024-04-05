import Foundation
import SwiftUI
import SystemConfiguration

@Observable public class DNSManager {
    
    private var preferences: SCPreferences
    private var dynamicStore: SCDynamicStore
    
    public var serviceIDs: [String] = []
    private var resolverSettings: [String:ResolverDetails] = [:]
    private var cachedResolvers: [String:[String]] = [:]
    
    public var overrideResolvers: [String] = (UserDefaults.standard.array(forKey: AppDefaults.overrideResolvers.rawValue) ?? []) as? [String] ?? [] {
        didSet(newValue) {
            UserDefaults.standard.set(newValue, forKey: AppDefaults.overrideResolvers.rawValue)
        }
    }
    
    static let shared: DNSManager = DNSManager()!
    
    private init?() {
        var authorizationRef: AuthorizationRef!
        if AuthorizationCreate(nil, nil, [.interactionAllowed, .extendRights], &authorizationRef) != 0 || authorizationRef == nil { return nil }
        
        guard let preferences = SCPreferencesCreateWithAuthorization(kCFAllocatorDefault, "DNSToggle" as CFString, nil, authorizationRef) else { return nil }
        self.preferences = preferences
        
        guard let dynamicStore = SCDynamicStoreCreate(kCFAllocatorDefault, "DNSToggle" as CFString, { dynamicStore, _, _ in
            DNSManager.shared.updateNetworkServices()
        }, nil) else { return nil }
        SCDynamicStoreSetNotificationKeys(dynamicStore, nil, ["Setup:/Network/Service/[^/]+/DNS"] as CFArray)
        let dynamicStoreRunLoopSource = SCDynamicStoreCreateRunLoopSource(kCFAllocatorDefault, dynamicStore, 0)
        self.dynamicStore = dynamicStore
        
        SCPreferencesSetCallback(preferences, { preferences, _, rawContextPointer in
            DNSManager.shared.updateNetworkServices()
        }, nil)
        
        if let currentRunLoop = CFRunLoopGetCurrent() {
            CFRunLoopAddSource(currentRunLoop, dynamicStoreRunLoopSource, .commonModes)
            SCPreferencesScheduleWithRunLoop(self.preferences, currentRunLoop, CFRunLoopMode.commonModes.rawValue)
        }
        
        self.updateNetworkServices()
    }
    
    private func updateNetworkServices() {
        SCPreferencesSynchronize(self.preferences)
        
        guard let networkServices = SCNetworkServiceCopyAll(self.preferences) as? Array<SCNetworkService> else { return }
        
        self.serviceIDs = []
        self.resolverSettings = [:]
        
        for service in networkServices {
            guard let serviceID = SCNetworkServiceGetServiceID(service) else { continue }
            guard let resolverDetails = ResolverDetails(serviceID: serviceID, preferences: self.preferences, dynamicStore: self.dynamicStore) else { continue }
            self.serviceIDs.append(serviceID as String)
            self.resolverSettings[serviceID as String] = resolverDetails
        }
        
        for serviceID in self.cachedResolvers.keys {
            if !self.serviceIDs.contains(serviceID) || self.resolverSettings[serviceID]!.configuredResolvers == self.cachedResolvers[serviceID] {
                self.cachedResolvers.removeValue(forKey: serviceID)
            }
        }
    }
    
    public func serviceName(for serviceID: String) -> String {
        return self.resolverSettings[serviceID]!.serviceName
    }
    
    public func currentResolvers(for serviceID: String) -> [String] {
        if let configuredResolvers = self.resolverSettings[serviceID]!.configuredResolvers {
            return configuredResolvers
        } else {
            return self.resolverSettings[serviceID]!.defaultResolvers
        }
    }
    
    public func defaultResolvers(for serviceID: String) -> [String] {
        return self.resolverSettings[serviceID]!.defaultResolvers
    }
    
    public func availableResolvers(for serviceID: String) -> [[String]] {
        var availableResolvers = [self.resolverSettings[serviceID]!.defaultResolvers]
        
        if let cachedResolvers = self.cachedResolvers[serviceID], !availableResolvers.contains(cachedResolvers) {
            availableResolvers.append(cachedResolvers)
        }
        
        if let configuredResolvers = self.resolverSettings[serviceID]!.configuredResolvers {
            availableResolvers.append(configuredResolvers)
        }
        
        if !availableResolvers.contains(self.overrideResolvers) {
            availableResolvers.append(self.overrideResolvers)
        }
        
        return availableResolvers
    }
    
    public func setResolvers(for serviceID: String, resolvers: [String]?) {
        var resolvers = resolvers
        if resolvers == self.overrideResolvers {
            self.cachedResolvers[serviceID] = self.currentResolvers(for: serviceID)
        } else if resolvers == self.defaultResolvers(for: serviceID) {
            self.cachedResolvers.removeValue(forKey: serviceID)
            resolvers = nil
        }
        
        guard let service = SCNetworkServiceCopy(preferences, serviceID as CFString) else { return }
        guard let dnsProtocol = SCNetworkServiceCopyProtocol(service, kSCNetworkProtocolTypeDNS) else { return }
        var dnsConfiguration = (SCNetworkProtocolGetConfiguration(dnsProtocol) as? [CFString: Any?]) ?? [:]
        dnsConfiguration[kSCPropNetDNSServerAddresses] = resolvers
        SCNetworkProtocolSetConfiguration(dnsProtocol, dnsConfiguration as CFDictionary)
        if SCPreferencesApplyChanges(preferences) {
            SCPreferencesCommitChanges(preferences)
        }
    }
    
    fileprivate struct ResolverDetails {
        fileprivate let serviceName: String
        fileprivate let defaultResolvers: [String]
        fileprivate let configuredResolvers: [String]?
        
        fileprivate init?(serviceID: CFString, preferences: SCPreferences, dynamicStore: SCDynamicStore) {
            let dnsKey = SCDynamicStoreKeyCreateNetworkServiceEntity(kCFAllocatorDefault, kSCDynamicStoreDomainState, serviceID, kSCEntNetDNS)
            guard let defaultResolvers = (SCDynamicStoreCopyValue(dynamicStore, dnsKey) as? [String:[String]])?["ServerAddresses"] else { return nil }
            self.defaultResolvers = defaultResolvers
            
            guard let service = SCNetworkServiceCopy(preferences, serviceID) else { return nil }
            guard let dnsProtocol = SCNetworkServiceCopyProtocol(service, kSCNetworkProtocolTypeDNS) else { return nil }
            if let dnsConfiguration = SCNetworkProtocolGetConfiguration(dnsProtocol) as? [CFString: Any?], let configuredResolvers = dnsConfiguration[kSCPropNetDNSServerAddresses] as? [String] {
                self.configuredResolvers = configuredResolvers
            } else {
                self.configuredResolvers = nil
            }
            
            guard let serviceName = SCNetworkServiceGetName(service) as String? else { return nil }
            self.serviceName = serviceName
        }
    }
}
