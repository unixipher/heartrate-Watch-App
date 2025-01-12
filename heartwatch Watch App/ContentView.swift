//
//  ContentView.swift
//  heartwatch Watch App
//
//  Created by Devangi Agarwal on 11/01/25.
//

// ContentView.swift
import SwiftUI
import HealthKit
import WatchKit

class HeartRateManager: NSObject, ObservableObject {
    private let healthStore = HKHealthStore()
    @Published var currentHeartRate: Double = 0
    @Published var isMonitoring: Bool = false
    private var query: HKQuery?
    private var session: WKExtendedRuntimeSession?
    
    override init() {
        super.init()
        requestAuthorization()
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
        guard let url = URL(string: "https://server-toza.onrender.com/api/watch-data") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let payload = ["heartRate": heartRate]
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload) else { return }
        request.httpBody = jsonData
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("Error sending heart rate: \(error)")
                return
            }
            if let httpResponse = response as? HTTPURLResponse {
                print("Heart rate sent. Status: \(httpResponse.statusCode)")
            }
        }.resume()
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