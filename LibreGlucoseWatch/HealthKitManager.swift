import Foundation
import HealthKit

public class HealthKitManager {
    private let healthStore = HKHealthStore()
    
    public init() {}
    
    /// Requests user authorization to share and read blood glucose data.
    public func requestAuthorization() async throws -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else {
            return false
        }
        
        guard let glucoseType = HKQuantityType.quantityType(forIdentifier: .bloodGlucose) else {
            return false
        }
        
        let typesToShare: Set<HKSampleType> = [glucoseType]
        let typesToRead: Set<HKObjectType> = [glucoseType]
        
        return try await withCheckedThrowingContinuation { continuation in
            healthStore.requestAuthorization(toShare: typesToShare, read: typesToRead) { success, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: success)
                }
            }
        }
    }
    
    /// Writes a blood glucose sample to HealthKit.
    public func writeGlucoseReading(value: Double, isMmolL: Bool, date: Date) async throws {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        
        guard let glucoseType = HKQuantityType.quantityType(forIdentifier: .bloodGlucose) else {
            return
        }
        
        // Define HealthKit units
        let unit: HKUnit
        if isMmolL {
            // mmol/L is represented as millimoles per liter of glucose (molar mass = 180.1558 g/mol)
            unit = HKUnit.moleUnit(with: .milli, molarMass: HKUnitMolarMassBloodGlucose).unitDivided(by: .liter())
        } else {
            unit = HKUnit(from: "mg/dL")
        }
        
        // Check if sample already exists at exactly this timestamp to avoid duplicates
        let predicate = HKQuery.predicateForSamples(withStart: date, end: date, options: .strictStartDate)
        let existingSamples: [HKSample] = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: glucoseType,
                predicate: predicate,
                limit: 1,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: samples ?? [])
                }
            }
            healthStore.execute(query)
        }
        
        // If a sample at this exact time exists, skip writing to avoid duplicates
        guard existingSamples.isEmpty else {
            print("HealthKit: Reading at \(date) already exists. Skipping.")
            return
        }
        
        let quantity = HKQuantity(unit: unit, doubleValue: value)
        let sample = HKQuantitySample(
            type: glucoseType,
            quantity: quantity,
            start: date,
            end: date,
            metadata: [
                HKMetadataKeyWasUserEntered: false,
                HKMetadataKeyDeviceName: "FreeStyle Libre Sensor"
            ]
        )
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            healthStore.save(sample) { success, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
        
        print("HealthKit: Successfully wrote \(value) \(isMmolL ? "mmol/L" : "mg/dL") at \(date).")
    }
}
