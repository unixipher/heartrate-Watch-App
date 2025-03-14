//
//  ContentView.swift
//  heartwatch Watch App
//
//  Created by Devangi Agarwal on 11/01/25.
//

import SwiftUI
import HealthKit
import WatchKit
import SocketIO

class HeartRateManager: NSObject, ObservableObject {
    private let healthStore = HKHealthStore()
    @Published var currentHeartRate: Double = 0
    @Published var isMonitoring: Bool = false
    private var query: HKQuery?
    private var session: WKExtendedRuntimeSession?
    
    private var manager: SocketManager?
    private var socket: SocketIOClient?
    
    override init() {
        super.init()
        requestAuthorization()
        setupSocket()
    }
    
    private func setupSocket() {
        let token = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VySWQiOjQsImVtYWlsIjoiYXJrb0BnbWFpbC5jb20iLCJpYXQiOjE3NDE1MjU3MTd9.Ax3TFtUkpbAD8-JR9EIL0WKmbjMSXpVA3LnBNXbKxgY"
        guard let url = URL(string: "https://heartrate-qv3x.onrender.com") else {
            print("Invalid server URL")
            return
        }
        
        manager = SocketManager(
            socketURL: url,
            config: [
                .log(true),        // Enable logs for debugging
                .compress,         // Enable compression
                .extraHeaders(["authorization": "Bearer \(token)"])
            ]
        )
        
        socket = manager?.defaultSocket
        
        // Socket event handlers
        socket?.on(clientEvent: .connect) { [weak self] data, ack in
            print("Connected to Socket.IO server")
        }
        
        socket?.on(clientEvent: .error) { [weak self] data, ack in
            print("Socket error: \(data)")
        }
        
        socket?.on(clientEvent: .disconnect) { [weak self] data, ack in
            print("Disconnected from Socket.IO server")
        }
        
        socket?.on("watchdataSaved") { [weak self] data, ack in
            if let data = data.first as? [String: Any] {
                print("Watch data saved: \(data)")
            }
        }
        
        socket?.on("error") { [weak self] data, ack in
            if let message = data.first as? String {
                print("Server error: \(message)")
            }
        }
    }
    
    func requestAuthorization() {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        
        let heartRateType = HKObjectType.quantityType(forIdentifier: .heartRate)!
        healthStore.requestAuthorization(toShare: [], read: [heartRateType]) { success, error in
            if success {
                print("HealthKit authorization granted")
            }
        }
    }
    
    func startMonitoring() {
        guard let heartRateType = HKObjectType.quantityType(forIdentifier: .heartRate) else { return }
        
        if let existingQuery = query {
            healthStore.stop(existingQuery)
        }
        
        let query = HKAnchoredObjectQuery(
            type: heartRateType,
            predicate: nil,
            anchor: nil,
            limit: HKObjectQueryNoLimit) { [weak self] query, samples, deletedObjects, anchor, error in
                self?.processHeartRateSamples(samples)
        }
        
        query.updateHandler = { [weak self] query, samples, deletedObjects, anchor, error in
            self?.processHeartRateSamples(samples)
        }
        
        healthStore.execute(query)
        self.query = query
        
        DispatchQueue.main.async {
            self.isMonitoring = true
        }
        
        startExtendedRuntimeSession()
        socket?.connect() // Connect socket when monitoring starts
    }
    
    func stopMonitoring() {
        if let query = query {
            healthStore.stop(query)
            self.query = nil
        }
        
        DispatchQueue.main.async {
            self.isMonitoring = false
            self.currentHeartRate = 0
        }
        
        stopExtendedRuntimeSession()
        socket?.disconnect() // Disconnect socket when monitoring stops
    }
    
    private func processHeartRateSamples(_ samples: [HKSample]?) {
        guard let heartRateSamples = samples as? [HKQuantitySample] else { return }
        
        for sample in heartRateSamples {
            let heartRate = sample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
            DispatchQueue.main.async {
                self.currentHeartRate = heartRate
            }
            sendHeartRateToServer(heartRate: heartRate)
        }
    }
    
    private func sendHeartRateToServer(heartRate: Double) {
        let data: [String: Any] = ["heartRate": heartRate]
        socket?.emit("watchdata", data) // Emit heart rate data via Socket.IO
    }
    
    private func startExtendedRuntimeSession() {
        session = WKExtendedRuntimeSession()
        session?.delegate = self
        session?.start()
    }
    
    private func stopExtendedRuntimeSession() {
        session?.invalidate()
        session = nil
    }
}

extension HeartRateManager: WKExtendedRuntimeSessionDelegate {
    func extendedRuntimeSessionDidStart(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
        print("Extended runtime session started")
    }
    
    func extendedRuntimeSessionWillExpire(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
        print("Extended runtime session will expire")
        stopMonitoring()
    }
    
    func extendedRuntimeSession(_ extendedRuntimeSession: WKExtendedRuntimeSession, didInvalidateWith reason: WKExtendedRuntimeSessionInvalidationReason, error: Error?) {
        print("Extended runtime session invalidated with reason: \(reason)")
        stopMonitoring()
    }
}

struct ContentView: View {
    @StateObject private var heartRateManager = HeartRateManager()
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Heart Rate Monitor")
                .font(.title3)
                .bold()
            
            Text("\(Int(heartRateManager.currentHeartRate)) BPM")
                .font(.system(size: 40, weight: .bold))
                .padding()
            
            Button(action: {
                if heartRateManager.isMonitoring {
                    heartRateManager.stopMonitoring()
                } else {
                    heartRateManager.startMonitoring()
                }
            }) {
                Text(heartRateManager.isMonitoring ? "Stop Monitoring" : "Start Monitoring")
                    .foregroundColor(heartRateManager.isMonitoring ? .red : .green)
                    .font(.body)
                    .bold()
            }
            .buttonStyle(.bordered)
            
            if heartRateManager.isMonitoring {
                Text("Monitoring Active")
                    .foregroundColor(.green)
                    .font(.caption)
            }
        }
    }
}