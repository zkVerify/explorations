//
//  ContentView.swift
//  proof-of-geolocation-app
//
//  Created by Arman Aurobindo on 02/07/25.
//

import SwiftUI
import CoreLocation
import Foundation
import moproFFI

struct ApiProof: Codable{
    let pi_a: [String]
    let pi_b: [[String]]
    let pi_c: [String]
    let `protocol`: String
    let curve: String
}

struct Vkey: Codable{
    let `protocol`: String
    let curve: String
    let nPublic: Int
    let vk_alpha_1: [String]
    let vk_beta_2: [[String]]
    let vk_gamma_2: [[String]]
    let vk_delta_2: [[String]]
    let vk_alphabeta_12: [[[String]]]
    let IC: [[String]]
}

struct ProofOptions: Codable{
    let library: String
    let curve: String
}

struct ProofData: Codable{
    let proof: ApiProof
    let publicSignals: [String]
    let vk: Vkey
}

struct ProofSubmissionPayload: Codable{
    let proofType: String
    let vkRegistered: Bool
    let chainId: Int
    let proofOptions: ProofOptions
    let proofData: ProofData
}

struct SubmissionResponse: Codable {
    let optimisticVerify: String
    let jobId: String
}

struct PollResponse: Codable{
    let jobId: String
    let status: String
    let txHash: String?
}

enum ProofError: Error, LocalizedError {
    case fileNotFound(String)
    case dataDecodingError(Error)
    case dataEncodingError(Error)
    case invalidURL
    case networkError(Error)
    case apiError(statusCode: Int, message: String)
    case verificationFailed(String)
    case jobFailed(String)
    case unexpectedResponse

    var errorDescription: String? {
        switch self {
        case .fileNotFound(let fileName):
            return "The file '\(fileName)' was not found in the app bundle."
        case .dataDecodingError(let error):
            return "Failed to decode data: \(error.localizedDescription)"
        case .dataEncodingError(let error):
            return "Failed to encode data: \(error.localizedDescription)"
        case .invalidURL:
            return "The provided API endpoint URL is invalid."
        case .networkError(let error):
            return "A network error occurred: \(error.localizedDescription)"
        case .apiError(let statusCode, let message):
            return "API returned status \(statusCode) with message: \(message)"
        case .verificationFailed(let reason):
            return "Optimistic verification failed: \(reason)"
        case .jobFailed(let reason):
            return "Job failed with status: \(reason)"
        case .unexpectedResponse:
            return "The API returned an unexpected response structure."
        }
    }
}

enum APIError: Error {
    case invalidURL
    case requestFailed(Error)
    case invalidResponse
    case decodingError(Error)
}


class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    
    // The instance of CLLocationManager that will do the heavy lifting.
    private let manager = CLLocationManager()
    
    // @Published properties will automatically update any SwiftUI view that uses this object.
    @Published var location: CLLocation?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined

    override init() {
        super.init()
        // Set this class as the delegate for the location manager.
        manager.delegate = self
        // Set the desired accuracy for location updates.
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    /// Requests permission from the user to access their location.
    func requestLocationPermission() {
        // This will trigger the permission prompt.
        // The string from your Info.plist will be displayed.
        manager.requestWhenInUseAuthorization()
    }
    
    /// Starts the process of fetching location updates.
    func startUpdatingLocation() {
        print("Starting location updates...")
        manager.startUpdatingLocation()
    }
    
    /// Stops the process of fetching location updates to save battery.
    func stopUpdatingLocation() {
        print("Stopping location updates.")
        manager.stopUpdatingLocation()
    }
    
    // MARK: - CLLocationManagerDelegate Methods
    
    /// This delegate method is called whenever the authorization status changes.
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        // Update our published property with the new status.
        self.authorizationStatus = status
        
        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            // Permission granted. Start updating the location.
            startUpdatingLocation()
        case .denied, .restricted:
            // Permission denied or restricted. Handle this case, e.g., show an alert.
            print("Location permission denied or restricted.")
            stopUpdatingLocation()
        case .notDetermined:
            // Permission not yet requested.
            print("Location permission not determined.")
            requestLocationPermission()
        @unknown default:
            // Handle any future cases.
            fatalError("Unhandled authorization status.")
        }
    }
    
    /// This delegate method is called when new location data is available.
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // The `locations` array contains the new data points.
        // We usually only care about the most recent one.
        guard let latestLocation = locations.last else { return }
        
        // Update our published location property.
        // This will cause any listening SwiftUI views to re-render.
        self.location = latestLocation
        
        // Optional: If you only need the location once, you can stop updates
        // right after getting the first valid location to conserve battery.
        // stopUpdatingLocation()
    }
    
    /// This delegate method is called if the location manager encounters an error.
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Error fetching location: \(error.localizedDescription)")
        // You might want to update the UI to show an error message.
    }
}


struct ContentView: View {
    
    @StateObject private var locationManager = LocationManager()
    
    private let zkeyPath = Bundle.main.path(forResource: "geolocation", ofType: "zkey")!
    
    @State private var txHash = ""
    
    
    var body: some View {
        VStack {
            Button("Prove"){
                Task{
                    if let location = locationManager.location{
                        print(location.coordinate.latitude, location.coordinate.longitude)
                        let res = try await runProveAction(lat: Int((location.coordinate.latitude+90)*1000000), lon: Int((location.coordinate.longitude+180)*1000000))
                        if(res != ""){
                            txHash = res
                        }else{
                            txHash = "Proof Failed !!!"
                        }
                    }
                }
            }
            
            switch locationManager.authorizationStatus {
                case .authorizedWhenInUse, .authorizedAlways:
                    // If we have a location, display it.
                    if let location = locationManager.location {
                        Text("\n\nLatitude: \(location.coordinate.latitude)")
                        Text("Longitude: \(location.coordinate.longitude)")
                    } else {
                        // If location is nil, it means we're waiting for the first update.
                        ProgressView() // Show a loading spinner
                        Text("Fetching location...")
                    }
                case .denied, .restricted:
                    Text("Location access was denied. Please enable it in Settings.")
                        .multilineTextAlignment(.center)
                        .padding()
                case .notDetermined:
                    Text("Requesting location permission...")
                    ProgressView()
                @unknown default:
                    Text("Unknown authorization status.")
                }

            
            if(txHash == "Proof Failed !!!" || txHash == ""){
                Text(txHash)
            }else{
                if let url = URL(string: "https://zkverify-testnet.subscan.io/extrinsic/\(txHash.trimmingCharacters(in: .whitespacesAndNewlines))") {
                            Link("View Transaction on zkVerify Explorer", destination: url)
                                .font(.subheadline)
                                .foregroundColor(.blue) // Default link color
                                .underline()
                        } else {
                            Text("Invalid TxHash URL: \(txHash)")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
            }

        }
        .padding()
    }
}

extension ContentView {
    
    func loadVerificationKey(from fileName: String) throws -> Vkey {
        guard let url = Bundle.main.url(forResource: fileName, withExtension: "json") else {
            throw ProofError.fileNotFound(fileName)
        }
        
        do {
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode(Vkey.self, from: data)
            return decoded
        } catch {
            throw ProofError.dataDecodingError(error)
        }
    }
    
    func transformProof(proof: CircomProof) -> ApiProof{
        let apiProof = ApiProof(
                    pi_a: [proof.a.x, proof.a.y, proof.a.z],
                    pi_b: [proof.b.x, proof.b.y, proof.b.z],
                    pi_c: [proof.c.x, proof.c.y, proof.c.z],
                    protocol: proof.protocol,
                    curve: proof.curve
                )
        return (apiProof)
    }
    
    func verifyProof(proof: ApiProof, publicSignals: [String], vk: Vkey)async throws -> String{
            let message = ProofSubmissionPayload(
                proofType: "groth16",
                vkRegistered: false,
                chainId: 11155111,
                proofOptions: ProofOptions(
                    library: "snarkjs", curve: "bn128"
                ),
                proofData: ProofData(proof: proof, publicSignals: publicSignals, vk: vk)
            )
            
            guard let key = Bundle.main.infoDictionary?["ApiKey"] as? String else {
                fatalError("ApiBaseUrl not set in Info.plist")
            }
            
            let url = URL(string: "https://relayer-api.horizenlabs.io/api/v1/submit-proof/\(key)")!
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.httpBody = try! JSONEncoder().encode(message)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                            throw APIError.invalidResponse
                        }
            
            let apiresponse = try JSONDecoder().decode(SubmissionResponse.self, from: data)
            
            print(apiresponse)
            
            if(apiresponse.optimisticVerify=="success"){
                let txHash = try await pollJobStatus(jobId: apiresponse.jobId)
                return txHash
            }else{
                return ""
            }
            
                }

    func pollJobStatus(jobId: String) async throws -> String{
        
        guard let key = Bundle.main.infoDictionary?["ApiKey"] as? String else {
            fatalError("ApiBaseUrl not set in Info.plist")
        }
        
        let url = URL(string: "https://relayer-api.horizenlabs.io/api/v1/job-status/\(key)/\(jobId)")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        while true{
            
            let (data, response) = try await URLSession.shared.data(for: request)
            let pollresponse = try JSONDecoder().decode(PollResponse.self, from: data)
            
            print("Polling... Job status: \(pollresponse.status)")
            
            if pollresponse.status=="IncludedInBlock"{
                return pollresponse.txHash ?? ""
            }
            
            try await Task.sleep(nanoseconds: 5_000_000_000)
        }
    }



    

    func runProveAction(lat: Int, lon: Int) async -> String{
        // Prepare inputs
        //
        // The generateCircomProof function accepts an absolute path
        // to the zkey, and a map of strings to arrays of strings
        //
        // This is a mapping of input names to values. Note that if
        // the input is not an array, it will still be specified as
        // and array of length 1.
        
        // 37.783709 | Longitude: -122.40823
        var ref_double_lat = 37.783709
        var ref_double_log = -123.40823
        let ref_lat = Int((ref_double_lat+90)*1000000)
        let ref_log = Int((ref_double_log+180)*1000000)

        
        let input_str: String = "{\"lat1\":[\"\(lat)\"],\"lon1\":[\"\(lon)\"],\"lat2\":[\"\(ref_lat)\"],\"lon2\":[\"\(ref_log)\"],\"threshold\":[\"202905202500\"]}"
        
        var txHash = ""
        // Begin timing our proof generation
        let start = CFAbsoluteTimeGetCurrent()
        // Call into the compiled static library
        do {
            let generateProofResult = try generateCircomProof(zkeyPath: zkeyPath, circuitInputs: input_str, proofLib: ProofLib.arkworks)
            print(generateProofResult.proof, generateProofResult.inputs)
            
            let verificationKey = try loadVerificationKey(from: "geolocation-vkey")
            txHash = try await verifyProof(proof: transformProof(proof: generateProofResult.proof), publicSignals: generateProofResult.inputs, vk: verificationKey)


        } catch {
            print("Error generate a proof: \(error)")
        }

        let end = CFAbsoluteTimeGetCurrent()
        let timeTaken = end - start
        print("built proof in \(String(format: "%.3f", timeTaken))s")
        return txHash
    }
}

#Preview {
    ContentView()
}
