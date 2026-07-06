import Foundation
import PathKit
import XcodeProj

let frameworkNames = [
    "AppAuth", "AppCheckCore", "FBLPromises", "FirebaseABTesting",
    "FirebaseAnalytics", "FirebaseAppCheckInterop", "FirebaseAuth",
    "FirebaseAuthInterop", "FirebaseCore", "FirebaseCoreExtension",
    "FirebaseCoreInternal", "FirebaseDatabase", "FirebaseFirestore",
    "FirebaseFirestoreInternal", "FirebaseInstallations", "FirebaseMessaging",
    "FirebaseMessagingInterop", "FirebaseRemoteConfig",
    "FirebaseRemoteConfigInterop", "FirebaseSharedSwift", "GTMAppAuth",
    "GTMSessionFetcher", "GoogleAppMeasurement",
    "GoogleAppMeasurementIdentitySupport", "GoogleDataTransport", "GoogleSignIn",
    "GoogleUtilities", "RecaptchaInterop", "absl", "grpc", "grpcpp", "leveldb",
    "nanopb", "openssl_grpc",
]

func stringFlags(_ value: Any?) -> [String] {
    if let values = value as? [String] { return values }
    if let value = value as? String { return value.split(separator: " ").map(String.init) }
    return []
}

func unique(_ values: [String]) -> [String] {
    var seen = Set<String>()
    return values.filter { seen.insert($0).inserted }
}

guard CommandLine.arguments.count == 3 else {
    fputs("Usage: xcode_firebase_linker <project.xcodeproj> <frameworks-directory>\n", stderr)
    exit(2)
}

let projectPath = Path(CommandLine.arguments[1])
let frameworksPath = Path(CommandLine.arguments[2])

for framework in frameworkNames {
    let path = frameworksPath + "\(framework).xcframework"
    guard path.exists else {
        fputs("Missing required framework: \(path)\n", stderr)
        exit(1)
    }
}

do {
    let xcodeproj = try XcodeProj(path: projectPath)
    guard let target = xcodeproj.pbxproj.nativeTargets.first else {
        throw NSError(domain: "ZipPath", code: 1, userInfo: [NSLocalizedDescriptionKey: "No native Xcode target found"])
    }

    let projectDir = projectPath.parent()
    let relativeFrameworks = frameworksPath.absolute().string.replacingOccurrences(
        of: projectDir.absolute().string + "/",
        with: ""
    )

    for configuration in target.buildConfigurationList?.buildConfigurations ?? [] {
        let inherited = stringFlags(configuration.buildSettings["OTHER_LDFLAGS"])
        let base = unique(["$(inherited)", "-ObjC", "-rdynamic"] + inherited)

        func flags(for slice: String) -> [String] {
            var result = base
            for framework in frameworkNames {
                let binary = "$(PROJECT_DIR)/\(relativeFrameworks)/\(framework).xcframework/\(slice)/\(framework).framework/\(framework)"
                result += ["-force_load", binary]
            }
            return result
        }

        configuration.buildSettings["OTHER_LDFLAGS"] = unique(base)
        configuration.buildSettings["OTHER_LDFLAGS[sdk=iphoneos*]"] = flags(for: "ios-arm64")
        configuration.buildSettings["OTHER_LDFLAGS[sdk=iphonesimulator*]"] = flags(for: "ios-arm64_x86_64-simulator")
    }

    try xcodeproj.write(path: projectPath)
    print("Configured Firebase linker settings for target \(target.name)")
} catch {
    fputs("xcode_firebase_linker: \(error)\n", stderr)
    exit(1)
}
