//
//  NetworkMonitor.swift
//  
//
//  Created by Alisa Mylnikova on 01.09.2023.
//

import Foundation
import Network

@MainActor
class NetworkMonitor: ObservableObject {
    private let networkMonitor = NWPathMonitor()
    private let workerQueue = DispatchQueue(label: "Monitor")
    var isConnected = false

    init() {
        // Weak, and cancelled with this object: a started monitor's handler
        // holding `self` kept both alive and running after the chat closed,
        // one more for every chat opened.
        networkMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self else { return }
                self.isConnected = path.status == .satisfied
                self.objectWillChange.send()
            }
        }
        networkMonitor.start(queue: workerQueue)
    }

    deinit {
        networkMonitor.cancel()
    }
}
