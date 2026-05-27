import os
import shutil
import re

# Paths
workspace_dir = "/Users/rajnaidu/Projects/LibreGlucoseWatch"
project_dir = os.path.join(workspace_dir, "LibreGlucoseWatch")
ios_dir = os.path.join(project_dir, "LibreGlucoseWatch")
watch_dir = os.path.join(project_dir, "LibreGlucoseWatch Watch App")

# Detect active widget folder
widget_dir = os.path.join(project_dir, "GlucoseWidgetExtension")
if not os.path.exists(widget_dir) and os.path.exists(os.path.join(project_dir, "GlucoseWidget")):
    widget_dir = os.path.join(project_dir, "GlucoseWidget")

pbxproj_path = os.path.join(project_dir, "LibreGlucoseWatch.xcodeproj/project.pbxproj")

def run_setup():
    global widget_dir
    print("Beginning complete clean Xcode setup automation...")
    print(f"Selected widget directory: {widget_dir}")

    # 1. Preserve local target modifications (no git checkout)
    print("Project file modifications preserved (no git checkout).")

    # 2. Sync physical folders
    shared_dest = os.path.join(project_dir, "Shared")
    os.makedirs(shared_dest, exist_ok=True)

    # Clean up standard boilerplates in companion apps
    boilerplates = [
        os.path.join(ios_dir, "ContentView.swift"),
        os.path.join(ios_dir, "LibreGlucoseWatchApp.swift"),
        os.path.join(watch_dir, "ContentView.swift"),
        os.path.join(watch_dir, "LibreGlucoseWatchApp.swift"),
    ]
    
    # Also clean up standard boilerplates in widget dir if it exists
    if os.path.exists(widget_dir):
        boilerplates += [
            os.path.join(widget_dir, "AppIntent.swift"),
            os.path.join(widget_dir, "GlucoseWidgetExtension.swift"),
            os.path.join(widget_dir, "GlucoseWidgetExtensionBundle.swift"),
            os.path.join(widget_dir, "GlucoseWidgetExtensionControl.swift"),
            os.path.join(widget_dir, "GlucoseWidget.swift"),
            os.path.join(widget_dir, "GlucoseWidgetBundle.swift"),
            os.path.join(widget_dir, "GlucoseWidgetControl.swift"),
        ]

    for bp in boilerplates:
        if os.path.exists(bp):
            try:
                os.remove(bp)
                print(f"Removed boilerplate: {os.path.basename(bp)}")
            except Exception as e:
                print(f"Could not remove {bp}: {e}")

    # Copy shared files
    shutil.copy(os.path.join(workspace_dir, "Shared/Models/GlucoseReading.swift"), os.path.join(shared_dest, "GlucoseReading.swift"))
    shutil.copy(os.path.join(workspace_dir, "Shared/Models/LibreLinkUpModels.swift"), os.path.join(shared_dest, "LibreLinkUpModels.swift"))
    shutil.copy(os.path.join(workspace_dir, "Shared/Extensions/Double+Glucose.swift"), os.path.join(shared_dest, "Double+Glucose.swift"))
    shutil.copy(os.path.join(workspace_dir, "Shared/Services/LibreLinkUpClient.swift"), os.path.join(shared_dest, "LibreLinkUpClient.swift"))
    shutil.copy(os.path.join(workspace_dir, "Shared/Services/GlucoseStore.swift"), os.path.join(shared_dest, "GlucoseStore.swift"))

    # Copy iOS & Watch companion app files
    shutil.copy(os.path.join(workspace_dir, "iOS/Services/HealthKitManager.swift"), os.path.join(ios_dir, "HealthKitManager.swift"))
    shutil.copy(os.path.join(workspace_dir, "iOS/Views/LoginView.swift"), os.path.join(ios_dir, "LoginView.swift"))
    shutil.copy(os.path.join(workspace_dir, "iOS/Views/DashboardView.swift"), os.path.join(ios_dir, "DashboardView.swift"))
    shutil.copy(os.path.join(workspace_dir, "iOS/Views/SettingsView.swift"), os.path.join(ios_dir, "SettingsView.swift"))
    shutil.copy(os.path.join(workspace_dir, "iOS/App/LibreGlucoseWatchApp.swift"), os.path.join(ios_dir, "LibreGlucoseWatchApp.swift"))

    shutil.copy(os.path.join(workspace_dir, "watchOS/Views/WatchDashboardView.swift"), os.path.join(watch_dir, "WatchDashboardView.swift"))
    shutil.copy(os.path.join(workspace_dir, "watchOS/App/WatchApp.swift"), os.path.join(watch_dir, "WatchApp.swift"))

    # Copy Widget files if the widget folder exists
    if os.path.exists(widget_dir):
        shutil.copy(os.path.join(workspace_dir, "Complications/GlucoseWidgetProvider.swift"), os.path.join(widget_dir, "GlucoseWidgetProvider.swift"))
        shutil.copy(os.path.join(workspace_dir, "Complications/GlucoseWidgetViews.swift"), os.path.join(widget_dir, "GlucoseWidgetViews.swift"))
        
        # Process GlucoseWidget.swift to remove .accessoryBezel
        src_widget = os.path.join(workspace_dir, "Complications/GlucoseWidget.swift")
        dst_widget = os.path.join(widget_dir, "GlucoseWidget.swift")
        with open(src_widget, 'r', encoding='utf-8') as f:
            widget_code = f.read()
        widget_code = widget_code.replace(".accessoryBezel", "")
        with open(dst_widget, 'w', encoding='utf-8') as f:
            f.write(widget_code)
        print("Widget view and provider files synced successfully.")

    print("Physical files synced successfully.")

    # 3. Patch Shared files inside the destination
    patch_shared_files(shared_dest)

    # 4. Modify project.pbxproj to link everything
    update_pbxproj()

def patch_shared_files(shared_dir):
    # Fix 1: TrendArrow naming collision in LibreLinkUpModels using CodingKeys mapping
    models_path = os.path.join(shared_dir, "LibreLinkUpModels.swift")
    with open(models_path, 'r', encoding='utf-8') as f:
        code = f.read()
        
    if "rawTrendArrow" not in code:
        old_measurement = """public struct LLUMeasurement: Codable {
    public let Value: Double
    public let Timestamp: String
    public let TrendArrow: Int
    
    public var date: Date? {
        return LibreDateFormatter.parse(Timestamp)
    }
    
    public var trendArrowEnum: TrendArrow {
        return TrendArrow(rawValue: TrendArrow) ?? .unknown
    }
}"""
        
        new_measurement = """public struct LLUMeasurement: Codable {
    public let value: Double
    public let timestamp: String
    public let rawTrendArrow: Int
    
    enum CodingKeys: String, CodingKey {
        case value = "Value"
        case timestamp = "Timestamp"
        case rawTrendArrow = "TrendArrow"
    }
    
    public var date: Date? {
        return LibreDateFormatter.parse(timestamp)
    }
    
    public var trendArrowEnum: TrendArrow {
        return TrendArrow(rawValue: rawTrendArrow) ?? .unknown
    }
}"""
        code = code.replace(old_measurement, new_measurement)
        code = code.replace("LibreGlucoseWatch.TrendArrow", "TrendArrow")
        
        with open(models_path, 'w', encoding='utf-8') as f:
            f.write(code)
        print("LLUMeasurement patched inside LibreLinkUpModels.swift.")

    # Fix 2: Ephemeral URLSession, assumesHTTP3Capable, and Region auto-detection in LibreLinkUpClient
    client_path = os.path.join(shared_dir, "LibreLinkUpClient.swift")
    with open(client_path, 'r', encoding='utf-8') as f:
        code = f.read()
        
    if "assumesHTTP3Capable" not in code:
        # Inject Ephemeral Session
        session_code = """    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()
    
    public init() {}"""
        code = code.replace("public init() {}", session_code)
        code = code.replace("URLSession.shared.data(for: request)", "self.session.data(for: request)")
        code = code.replace("request.timeoutInterval = 30 // 30 second timeout", "request.timeoutInterval = 30 // 30 second timeout\n        request.assumesHTTP3Capable = false")
        
        # Inject Region extraction
        region_func = """    private func extractRegion(from jwt: String) -> String? {
        let parts = jwt.components(separatedBy: ".")
        guard parts.count > 1 else { return nil }
        let payloadPart = parts[1]
        
        // Convert base64url to base64
        var base64 = payloadPart
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        
        // Add padding
        let paddingLength = 4 - (base64.count % 4)
        if paddingLength < 4 {
            base64.append(String(repeating: "=", count: paddingLength))
        }
        
        guard let data = Data(base64Encoded: base64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let region = json["region"] as? String else {
            return nil
        }
        
        return region.lowercased()
    }
    
    private func processLoginPayload(_ response: LibreLinkUpLoginResponse) throws -> (token: String, regionBaseURL: String, userId: String) {
        print("🔍 Processing login payload...")
        
        guard let data = response.data else {
            print("❌ No data in response")
            throw LLUClientError.invalidResponse
        }
        
        print("✅ Data found")
        
        guard let ticket = data.authTicket else {
            print("❌ No authTicket in data")
            throw LLUClientError.invalidResponse
        }
        
        print("✅ Auth ticket found: \(ticket.token.prefix(10))...")
        
        guard let user = data.user else {
            print("❌ No user in data")
            throw LLUClientError.invalidResponse
        }
        
        print("✅ User found: \(user.id)")
        
        self.token = ticket.token
        self.userId = user.id
        self.accountIdHash = sha256(user.id)
        
        // Dynamically detect region from the JWT token and update the activeBaseURL
        if let detectedRegion = extractRegion(from: ticket.token) {
            let regionalURL = "https://api-\\(detectedRegion).libreview.io"
            if self.activeBaseURL != regionalURL {
                print("🌍 Automatically detected region from JWT: \\(detectedRegion). Updating Base URL to: \\(regionalURL)")
                self.activeBaseURL = regionalURL
            }
        }
        
        print("🎉 Login complete! Token stored, returning to caller. Region Base URL: \\(self.activeBaseURL)")
        
        return (ticket.token, self.activeBaseURL, user.id)
    }"""
        pattern = r"private func processLoginPayload\(_ response: LibreLinkUpLoginResponse\).*?return \(ticket\.token, self\.activeBaseURL, user\.id\)\s+\}"
        code = re.sub(pattern, region_func, code, flags=re.DOTALL)
        code = code.replace("private let versionHeader = \"4.10.2\"", "private let versionHeader = \"4.16.0\"")
        
        with open(client_path, 'w', encoding='utf-8') as f:
            f.write(code)
        print("LibreLinkUpClient.swift URL session parameters successfully patched.")

def update_pbxproj():
    print("Modifying project.pbxproj database...")
    with open(pbxproj_path, 'r', encoding='utf-8') as f:
        content = f.read()

    # Shared file details (Using safe non-colliding UUIDs starting with C35A89A52FC686E3009F...)
    build_files = [
        "C35A89A52FC686E3009F4562 /* GlucoseReading.swift in Sources */ = {isa = PBXBuildFile; fileRef = C35A89A52FC686E3009F4561 /* GlucoseReading.swift */; };",
        "C35A89A52FC686E3009F4563 /* GlucoseReading.swift in Sources */ = {isa = PBXBuildFile; fileRef = C35A89A52FC686E3009F4561 /* GlucoseReading.swift */; };",
        "C35A89A52FC686E3009F4564 /* GlucoseReading.swift in Sources */ = {isa = PBXBuildFile; fileRef = C35A89A52FC686E3009F4561 /* GlucoseReading.swift */; };",
        
        "C35A89A52FC686E3009F4566 /* LibreLinkUpModels.swift in Sources */ = {isa = PBXBuildFile; fileRef = C35A89A52FC686E3009F4565 /* LibreLinkUpModels.swift */; };",
        "C35A89A52FC686E3009F4567 /* LibreLinkUpModels.swift in Sources */ = {isa = PBXBuildFile; fileRef = C35A89A52FC686E3009F4565 /* LibreLinkUpModels.swift */; };",
        "C35A89A52FC686E3009F4568 /* LibreLinkUpModels.swift in Sources */ = {isa = PBXBuildFile; fileRef = C35A89A52FC686E3009F4565 /* LibreLinkUpModels.swift */; };",
        
        "C35A89A52FC686E3009F456A /* Double+Glucose.swift in Sources */ = {isa = PBXBuildFile; fileRef = C35A89A52FC686E3009F4569 /* Double+Glucose.swift */; };",
        "C35A89A52FC686E3009F456B /* Double+Glucose.swift in Sources */ = {isa = PBXBuildFile; fileRef = C35A89A52FC686E3009F4569 /* Double+Glucose.swift */; };",
        "C35A89A52FC686E3009F456C /* Double+Glucose.swift in Sources */ = {isa = PBXBuildFile; fileRef = C35A89A52FC686E3009F4569 /* Double+Glucose.swift */; };",
        
        "C35A89A52FC686E3009F456E /* LibreLinkUpClient.swift in Sources */ = {isa = PBXBuildFile; fileRef = C35A89A52FC686E3009F456D /* LibreLinkUpClient.swift */; };",
        "C35A89A52FC686E3009F456F /* LibreLinkUpClient.swift in Sources */ = {isa = PBXBuildFile; fileRef = C35A89A52FC686E3009F456D /* LibreLinkUpClient.swift */; };",
        "C35A89A52FC686E3009F4700 /* LibreLinkUpClient.swift in Sources */ = {isa = PBXBuildFile; fileRef = C35A89A52FC686E3009F456D /* LibreLinkUpClient.swift */; };",
        
        "C35A89A52FC686E3009F4572 /* GlucoseStore.swift in Sources */ = {isa = PBXBuildFile; fileRef = C35A89A52FC686E3009F4571 /* GlucoseStore.swift */; };",
        "C35A89A52FC686E3009F4573 /* GlucoseStore.swift in Sources */ = {isa = PBXBuildFile; fileRef = C35A89A52FC686E3009F4571 /* GlucoseStore.swift */; };",
        "C35A89A52FC686E3009F4701 /* GlucoseStore.swift in Sources */ = {isa = PBXBuildFile; fileRef = C35A89A52FC686E3009F4571 /* GlucoseStore.swift */; };",
    ]

    file_refs = [
        "C35A89A52FC686E3009F4561 /* GlucoseReading.swift */ = {isa = PBXFileReference; fileEncoding = 4; lastKnownFileType = sourcecode.swift; path = Shared/GlucoseReading.swift; sourceTree = \"<group>\"; };",
        "C35A89A52FC686E3009F4565 /* LibreLinkUpModels.swift */ = {isa = PBXFileReference; fileEncoding = 4; lastKnownFileType = sourcecode.swift; path = Shared/LibreLinkUpModels.swift; sourceTree = \"<group>\"; };",
        "C35A89A52FC686E3009F4569 /* Double+Glucose.swift */ = {isa = PBXFileReference; fileEncoding = 4; lastKnownFileType = sourcecode.swift; path = \"Shared/Double+Glucose.swift\"; sourceTree = \"<group>\"; };",
        "C35A89A52FC686E3009F456D /* LibreLinkUpClient.swift */ = {isa = PBXFileReference; fileEncoding = 4; lastKnownFileType = sourcecode.swift; path = Shared/LibreLinkUpClient.swift; sourceTree = \"<group>\"; };",
        "C35A89A52FC686E3009F4571 /* GlucoseStore.swift */ = {isa = PBXFileReference; fileEncoding = 4; lastKnownFileType = sourcecode.swift; path = Shared/GlucoseStore.swift; sourceTree = \"<group>\"; };",
    ]

    # Only inject files in PBXBuildFile/PBXFileReference sections if they don't already exist
    if "C35A89A52FC686E3009F4561" not in content:
        # Insert Build Files
        build_file_section_start = "/* Begin PBXBuildFile section */"
        build_file_insert = "\n".join(f"\t\t{bf}" for bf in build_files) + "\n"
        content = content.replace(build_file_section_start, f"{build_file_section_start}\n{build_file_insert}")

        # Insert File References
        file_ref_section_start = "/* Begin PBXFileReference section */"
        file_ref_insert = "\n".join(f"\t\t{fr}" for fr in file_refs) + "\n"
        content = content.replace(file_ref_section_start, f"{file_ref_section_start}\n{file_ref_insert}")

        # Insert into Group children: Shared (C35A89A52FC686E3004A456E)
        shared_group_pattern = r"(C35A89A52FC686E3004A456E /\* Shared \*/ = \{\s+isa = PBXGroup;\s+children = \()"
        shared_children_insert = "\n\t\t\t\tC35A89A52FC686E3009F4561 /* GlucoseReading.swift */,\n\t\t\t\tC35A89A52FC686E3009F4565 /* LibreLinkUpModels.swift */,\n\t\t\t\tC35A89A52FC686E3009F4569 /* Double+Glucose.swift */,\n\t\t\t\tC35A89A52FC686E3009F456D /* LibreLinkUpClient.swift */,\n\t\t\t\tC35A89A52FC686E3009F4571 /* GlucoseStore.swift */,"
        content = re.sub(shared_group_pattern, r"\1" + shared_children_insert, content)
        print("Shared files references successfully declared in project.")

    # 1. Link to iOS app Sources phase (C35A892A2FC683D4004A456E /* Sources */)
    ios_sources_pattern = r"(C35A892A2FC683D4004A456E /\* Sources \*/ = \{\s+isa = PBXSourcesBuildPhase;\s+buildActionMask = [0-9]+;\s+files = \()"
    if "C35A89A52FC686E3009F4562" not in content:
        ios_build_files = "\n\t\t\t\tC35A89A52FC686E3009F4562 /* GlucoseReading.swift in Sources */,\n\t\t\t\tC35A89A52FC686E3009F4566 /* LibreLinkUpModels.swift in Sources */,\n\t\t\t\tC35A89A52FC686E3009F456A /* Double+Glucose.swift in Sources */,\n\t\t\t\tC35A89A52FC686E3009F456E /* LibreLinkUpClient.swift in Sources */,\n\t\t\t\tC35A89A52FC686E3009F4572 /* GlucoseStore.swift in Sources */,"
        content = re.sub(ios_sources_pattern, r"\1" + ios_build_files, content)

    # 2. Link to Watch App Sources phase (C35A894D2FC683D6004A456E /* Sources */)
    watch_sources_pattern = r"(C35A894D2FC683D6004A456E /\* Sources \*/ = \{\s+isa = PBXSourcesBuildPhase;\s+buildActionMask = [0-9]+;\s+files = \()"
    if "C35A89A52FC686E3009F4563" not in content:
        watch_build_files = "\n\t\t\t\tC35A89A52FC686E3009F4563 /* GlucoseReading.swift in Sources */,\n\t\t\t\tC35A89A52FC686E3009F4567 /* LibreLinkUpModels.swift in Sources */,\n\t\t\t\tC35A89A52FC686E3009F456B /* Double+Glucose.swift in Sources */,\n\t\t\t\tC35A89A52FC686E3009F456F /* LibreLinkUpClient.swift in Sources */,\n\t\t\t\tC35A89A52FC686E3009F4573 /* GlucoseStore.swift in Sources */,"
        content = re.sub(watch_sources_pattern, r"\1" + watch_build_files, content)

    # 3. Link to Widget Extension Sources phase dynamically!
    widget_sources_phase = None
    target_pattern = r"([0-9A-F]{24}) /\* (GlucoseWidget[a-zA-Z]*) \*/ = \{\s+isa = PBXNativeTarget;.*?buildPhases = \((.*?)\);"
    for target_id, target_name, phases_content in re.findall(target_pattern, content, re.DOTALL):
        phase_match = re.search(r"([0-9A-F]{24}) /\* Sources \*/", phases_content)
        if phase_match:
            widget_sources_phase = phase_match.group(1)
            print(f"🎯 Dynamically detected widget target '{target_name}' with Sources phase ID: {widget_sources_phase}")
            break

    if widget_sources_phase:
        # Check if already linked
        phase_block_match = re.search(rf"({widget_sources_phase} /\* Sources \*/ = \{{.*?files = \()(.*?)\);", content, re.DOTALL)
        if phase_block_match:
            files_list = phase_block_match.group(2)
            if "C35A89A52FC686E3009F4564" not in files_list:
                widget_sources_pattern = rf"({widget_sources_phase} /\* Sources \*/ = \{{\s+isa = PBXSourcesBuildPhase;\s+buildActionMask = [0-9]+;\s+files = \()"
                widget_build_files = "\n\t\t\t\tC35A89A52FC686E3009F4564 /* GlucoseReading.swift in Sources */,\n\t\t\t\tC35A89A52FC686E3009F4568 /* LibreLinkUpModels.swift in Sources */,\n\t\t\t\tC35A89A52FC686E3009F456C /* Double+Glucose.swift in Sources */,\n\t\t\t\tC35A89A52FC686E3009F4700 /* LibreLinkUpClient.swift in Sources */,\n\t\t\t\tC35A89A52FC686E3009F4701 /* GlucoseStore.swift in Sources */,"
                content = re.sub(widget_sources_pattern, r"\1" + widget_build_files, content)
                print("✅ Successfully linked shared files to widget target.")
            else:
                print("ℹ️ Shared files already linked to widget target.")
    else:
        print("⚠️ No active widget target (GlucoseWidget or GlucoseWidgetExtension) detected in project.pbxproj yet.")

    # 4. Inject HealthKit description keys if not already present
    if "INFOPLIST_KEY_NSHealthShareUsageDescription" not in content:
        # Debug Settings
        dbg_pattern = r"(C35A89792FC683D7004A456E /\* Debug \*/ = \{\s+isa = XCBuildConfiguration;\s+buildSettings = \{[^\}]+?INFOPLIST_KEY_CFBundleDisplayName = LibreGlucoseWatch;)"
        dbg_insert = "\n\t\t\t\tINFOPLIST_KEY_NSHealthShareUsageDescription = \"We read glucose data to calculate stats and trends.\";\n\t\t\t\tINFOPLIST_KEY_NSHealthUpdateUsageDescription = \"We write your FreeStyle Libre readings to Apple Health.\";"
        content = re.sub(dbg_pattern, r"\1" + dbg_insert, content)

        # Release Settings
        rel_pattern = r"(C35A897A2FC683D7004A456E /\* Release \*/ = \{\s+isa = XCBuildConfiguration;\s+buildSettings = \{[^\}]+?INFOPLIST_KEY_CFBundleDisplayName = LibreGlucoseWatch;)"
        rel_insert = "\n\t\t\t\tINFOPLIST_KEY_NSHealthShareUsageDescription = \"We read glucose data to calculate stats and trends.\";\n\t\t\t\tINFOPLIST_KEY_NSHealthUpdateUsageDescription = \"We write your FreeStyle Libre readings to Apple Health.\";"
        content = re.sub(rel_pattern, r"\1" + rel_insert, content)
        print("HealthKit Info.plist usage descriptions successfully declared.")

    with open(pbxproj_path, 'w', encoding='utf-8') as f:
        f.write(content)
    print("project.pbxproj updated successfully.")

if __name__ == "__main__":
    run_setup()
    print("Resilient target configuration completed successfully!")
