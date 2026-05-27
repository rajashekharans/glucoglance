import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: GlucoseStore
    @Environment(\.presentationMode) var presentationMode
    
    @State private var showLogoutConfirm = false
    
    var body: some View {
        ZStack {
            // Dark Background
            Color(red: 0.05, green: 0.06, blue: 0.09).ignoresSafeArea()
            
            Form {
                Section(header: Text("Data Synchronization").foregroundColor(.green)) {
                    Toggle(isOn: $store.useHealthKit) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Sync with Apple Health")
                                .foregroundColor(.white)
                            Text("Writes glucose data to HealthKit in real-time.")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.5))
                        }
                    }
                    .listRowBackground(Color.white.opacity(0.04))
                }
                
                Section(header: Text("Apple Watch").foregroundColor(.green)) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Apple Watch Sync")
                                .foregroundColor(.white)
                            Text("Updates complications via WatchConnectivity.")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.5))
                        }
                        Spacer()
                        Image(systemName: "applewatch")
                            .font(.title3)
                            .foregroundColor(.green)
                    }
                    .listRowBackground(Color.white.opacity(0.04))
                    
                    Button(action: {
                        #if os(iOS)
                        store.syncToWatch()
                        #endif
                    }) {
                        Text("Force Sync Watch")
                            .fontWeight(.medium)
                            .foregroundColor(.green)
                    }
                    .listRowBackground(Color.white.opacity(0.04))
                }
                
                Section(header: Text("Account Details").foregroundColor(.green)) {
                    if let creds = store.savedCredentials, let email = creds["email"] {
                        HStack {
                            Text("Account Email")
                                .foregroundColor(.white)
                            Spacer()
                            Text(email)
                                .foregroundColor(.white.opacity(0.5))
                        }
                        .listRowBackground(Color.white.opacity(0.04))
                    }
                    
                    Button(action: {
                        showLogoutConfirm = true
                    }) {
                        HStack {
                            Spacer()
                            Text("Log Out")
                                .foregroundColor(.red)
                                .fontWeight(.semibold)
                            Spacer()
                        }
                    }
                    .listRowBackground(Color.white.opacity(0.04))
                }
                
                Section(
                    header: HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                        Text("Important Notice")
                    }
                    .foregroundColor(.orange)
                ) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("GlucoGlance is for personal use only.")
                            .font(.system(.subheadline, design: .rounded))
                            .fontWeight(.semibold)
                            .foregroundColor(.white)

                        Text("Not affiliated with Abbott Diabetes Care, FreeStyle Libre, or LibreView.")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))

                        Text("Not a registered medical device. Glucose values shown here are informational only and must not be used for clinical decisions, insulin dosing, or emergency response.")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))

                        Text("Always confirm readings in the official LibreLink app, or with a fingerstick measurement, before making any treatment decisions.")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .padding(.vertical, 6)
                    .listRowBackground(Color.white.opacity(0.04))
                }

                Section(header: Text("Information & Credits").foregroundColor(.green)) {
                    HStack {
                        Text("Version")
                            .foregroundColor(.white)
                        Spacer()
                        Text("1.0.0 (4.10.2)")
                            .foregroundColor(.white.opacity(0.5))
                    }
                    .listRowBackground(Color.white.opacity(0.04))
                    
                    HStack {
                        Text("App Group")
                            .foregroundColor(.white)
                        Spacer()
                        Text("group.com.rajnaidu...")
                            .foregroundColor(.white.opacity(0.5))
                    }
                    .listRowBackground(Color.white.opacity(0.04))
                }
            }
            .background(Color.clear)
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Settings")
        .alert(isPresented: $showLogoutConfirm) {
            Alert(
                title: Text("Log Out"),
                message: Text("Are you sure you want to log out and remove your LibreLinkUp credentials?"),
                primaryButton: .destructive(Text("Log Out")) {
                    store.clearSession()
                    presentationMode.wrappedValue.dismiss()
                },
                secondaryButton: .cancel()
            )
        }
    }
}
