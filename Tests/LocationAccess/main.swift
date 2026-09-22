let authorizations: [LocationAuthorization] = [.notDetermined, .restricted, .denied, .authorizedAlways, .authorizedWhenInUse]
let accuracies: [LocationAccuracy] = [.fullAccuracy, .reducedAccuracy]
var cases = 0
for registration in ["System", "User", "unrecognized"] {
    for authorization in authorizations {
        for accuracy in accuracies {
            for enabled in [true, false] {
                let status = LocationAccessStatus(registration: registration, authorization: authorization,
                    accuracy: accuracy, servicesEnabled: enabled)
                let allowed = enabled && (authorization == .authorizedAlways || authorization == .authorizedWhenInUse)
                assert(!status.registrationNeedsCorrection, "System/User registration is informational")
                assert(status.registrationText == (registration == "unrecognized" ? "Unknown" : registration))
                assert(status.authorized == allowed)
                assert(status.precise == (allowed && accuracy == .fullAccuracy))
                assert(status.canStartUpdates(inForeground: true) == allowed)
                assert(status.canStartUpdates(inForeground: false) == (enabled && authorization == .authorizedAlways))
                if !allowed { assert(status.accuracyText == "Unavailable") }
                if !enabled { assert(status.accessText == "Location Services off") }
                cases += 1
            }
        }
    }
}
let unknown = LocationAccessStatus(registration: nil,
    authorization: .unknown, accuracy: .unknown, servicesEnabled: true)
assert(unknown.registrationText == "Unknown" && unknown.accessText == "Unknown")
assert(!unknown.authorized && !unknown.precise)
let unknownAccuracy = LocationAccessStatus(registration: "System", authorization: .authorizedWhenInUse,
    accuracy: .unknown, servicesEnabled: true)
assert(unknownAccuracy.accuracyText == "Unknown" && !unknownAccuracy.precise)
print("PASS: \(cases) registration/authorization/accuracy/service combinations and future unknown values")
