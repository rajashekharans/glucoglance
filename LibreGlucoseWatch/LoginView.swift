import SwiftUI

struct LoginView: View {
    @ObservedObject var store: GlucoseStore
    
    @State private var email = ""
    @State private var password = ""
    @State private var errorMessage = ""
    @State private var showDisclaimer = true
    @State private var hasAcceptedDisclaimer = false
    
    var body: some View {
        ZStack {
            // Elegant Background Gradient
            LinearGradient(
                colors: [Color(red: 0.1, green: 0.12, blue: 0.18), Color(red: 0.05, green: 0.05, blue: 0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            // Subtle glowing orb decorations for a premium depth aesthetic
            GeometryReader { geo in
                Circle()
                    .fill(Color.glucoseColor(for: 120.0).opacity(0.12))
                    .frame(width: geo.size.width * 0.8, height: geo.size.width * 0.8)
                    .blur(radius: 80)
                    .position(x: geo.size.width * 0.2, y: geo.size.height * 0.2)
                
                Circle()
                    .fill(Color(red: 0.65, green: 0.2, blue: 0.8).opacity(0.08))
                    .frame(width: geo.size.width * 0.8, height: geo.size.width * 0.8)
                    .blur(radius: 90)
                    .position(x: geo.size.width * 0.8, y: geo.size.height * 0.8)
            }
            
            if showDisclaimer {
                disclaimerCard
                    .transition(.asymmetric(insertion: .opacity, removal: .move(edge: .top).combined(with: .opacity)))
            } else {
                loginCard
                    .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity))
            }
        }
        .animation(.spring(response: 0.6, dampingFraction: 0.82), value: showDisclaimer)
    }
    
    // MARK: - Disclaimer Layout
    private var disclaimerCard: some View {
        VStack(spacing: 24) {
            Image(systemName: "exclamationmark.shield.fill")
                .font(.system(size: 60))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.orange, Color.red],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: Color.red.opacity(0.3), radius: 10, y: 5)
            
            Text("Medical Disclaimer")
                .font(.system(.title2, design: .rounded))
                .fontWeight(.bold)
                .foregroundColor(.white)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("This application is a **non-commercial, open-source personal tool** reverse-engineered from community implementations of the LibreLinkUp caregiver sharing service.")
                        .font(.system(.body, design: .rounded))
                        .foregroundColor(.white.opacity(0.85))
                    
                    Text("It is **not** endorsed, developed, or tested by Abbott Laboratories, and it is **not a medical device**.")
                        .font(.system(.body, design: .rounded))
                        .fontWeight(.semibold)
                        .foregroundColor(.orange)
                    
                    Text("• **NEVER** rely on this application's display for insulin dosing, medical treatment, or clinical decisions.")
                    Text("• **ALWAYS** verify with a fingerstick blood glucose test if readings do not match your symptoms.")
                    Text("• By continuing, you acknowledge that you use this software entirely at your own risk.")
                }
                .font(.system(.callout, design: .rounded))
                .foregroundColor(.white.opacity(0.75))
                .multilineTextAlignment(.leading)
            }
            .frame(maxHeight: 250)
            .padding()
            .background(Color.white.opacity(0.04))
            .cornerRadius(12)
            
            Toggle(isOn: $hasAcceptedDisclaimer) {
                Text("I understand and accept all terms")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundColor(.white.opacity(0.9))
            }
            .toggleStyle(CheckboxToggleStyle())
            
            Button(action: {
                withAnimation { showDisclaimer = false }
            }) {
                Text("Proceed to Login")
                    .font(.system(.headline, design: .rounded))
                    .fontWeight(.bold)
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(hasAcceptedDisclaimer ? Color.green : Color.white.opacity(0.15))
                    .cornerRadius(14)
                    .shadow(color: hasAcceptedDisclaimer ? Color.green.opacity(0.4) : .clear, radius: 8, y: 4)
            }
            .disabled(!hasAcceptedDisclaimer)
        }
        .padding(30)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(Color.white.opacity(0.06))
                .background(Color.black.opacity(0.2))
                .background(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .padding(.horizontal, 24)
    }
    
    // MARK: - Login Layout
    private var loginCard: some View {
        VStack(spacing: 28) {
            VStack(spacing: 8) {
                Text("LibreGlucoseWatch")
                    .font(.system(.title, design: .rounded))
                    .fontWeight(.black)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.green, Color(red: 0.15, green: 0.68, blue: 0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                Text("Connect your FreeStyle Libre account")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundColor(.white.opacity(0.6))
            }
            
            VStack(spacing: 16) {
                // Email Field
                HStack {
                    Image(systemName: "envelope.fill")
                        .foregroundColor(.green.opacity(0.8))
                        .frame(width: 24)
                    TextField("", text: $email, prompt: Text("LibreLinkUp Email").foregroundColor(.white.opacity(0.3)))
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .foregroundColor(.white)
                }
                .padding()
                .background(Color.white.opacity(0.05))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
                
                // Password Field
                HStack {
                    Image(systemName: "lock.fill")
                        .foregroundColor(.green.opacity(0.8))
                        .frame(width: 24)
                    SecureField("", text: $password, prompt: Text("LibreLinkUp Password").foregroundColor(.white.opacity(0.3)))
                        .foregroundColor(.white)
                }
                .padding()
                .background(Color.white.opacity(0.05))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
            }
            
            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.system(.footnote, design: .rounded))
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
            }
            
            Button(action: handleLogin) {
                HStack {
                    if store.isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .black))
                            .scaleEffect(0.9)
                    } else {
                        Text("Log In")
                            .font(.system(.headline, design: .rounded))
                            .fontWeight(.bold)
                    }
                }
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .padding()
                .background(LinearGradient(
                    colors: [Color.green, Color(red: 0.15, green: 0.78, blue: 0.47)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .cornerRadius(14)
                .shadow(color: Color.green.opacity(0.4), radius: 8, y: 4)
            }
            .disabled(store.isLoading || email.isEmpty || password.isEmpty)
        }
        .padding(30)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(Color.white.opacity(0.06))
                .background(Color.black.opacity(0.2))
                .background(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .padding(.horizontal, 24)
    }
    
    private func handleLogin() {
        errorMessage = ""
        Task {
            do {
                try await store.loginAndFetch(email: email, password: password)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - Checkbox Style Helper
struct CheckboxToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            Image(systemName: configuration.isOn ? "checkmark.square.fill" : "square")
                .resizable()
                .frame(width: 22, height: 22)
                .foregroundColor(configuration.isOn ? .green : .white.opacity(0.4))
                .onTapGesture {
                    withAnimation(.spring()) {
                        configuration.isOn.toggle()
                    }
                }
            
            configuration.label
        }
    }
}
