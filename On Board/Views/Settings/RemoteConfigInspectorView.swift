//
//  RemoteConfigInspectorView.swift
//  On Board
//
//  Debug-only window into what THIS device resolved from remote config —
//  the difference between debugging a staged rollout by evidence and
//  debugging it by inference.
//
//  Answers, at a glance: did the fetch happen (and when, and how it failed);
//  which identity flags are bucketed on; what each flag resolved to and WHY
//  (compiled default vs. explicit on/off vs. percentage + this device's
//  bucket); and the raw key/value blob the server returned.
//
//  Compiled out of release builds entirely — the #if DEBUG wraps the whole
//  file, so there is no dormant screen to leak into the App Store build.
//

#if DEBUG
import SwiftUI

struct RemoteConfigInspectorView: View {
    @Environment(RemoteConfigStore.self) private var remoteConfig
    @Environment(AuthStore.self) private var auth

    private var identity: UUID {
        auth.session?.userId ?? remoteConfig.installIdentity
    }

    var body: some View {
        List {
            Section("Fetch") {
                LabeledContent("Status", value: statusText)
                Button("Refresh now") {
                    Task { await remoteConfig.refresh() }
                }
            }

            Section("Version gate") {
                LabeledContent("App version", value: AppVersion.current)
                LabeledContent("Requirement", value: requirementText)
                LabeledContent("min_supported_version",
                               value: remoteConfig.config.minSupportedVersion ?? "—")
                LabeledContent("recommended_version",
                               value: remoteConfig.config.recommendedVersion ?? "—")
            }

            Section {
                LabeledContent("Identity", value: identity.uuidString)
            } header: {
                Text("Flag identity")
            } footer: {
                Text(auth.session == nil
                     ? "Signed out — bucketing on the per-install identity."
                     : "Signed in — bucketing on the account id.")
            }

            Section("Flags") {
                ForEach(FeatureFlag.allCases, id: \.self) { flag in
                    flagRow(flag)
                }
            }

            Section {
                let values = remoteConfig.config.storedValues
                if values.isEmpty {
                    Text("Empty — every accessor is returning its compiled default.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(values.keys.sorted(), id: \.self) { key in
                        LabeledContent(key, value: values[key] ?? "")
                    }
                }
            } header: {
                Text("Raw config")
            } footer: {
                Text("Exactly what get_app_config() returned, cached in UserDefaults.")
            }
        }
        .navigationTitle("Remote Config")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func flagRow(_ flag: FeatureFlag) -> some View {
        let resolved = remoteConfig.isEnabled(flag, for: auth.session?.userId)
        return VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(flag.rawValue)
                Spacer()
                Image(systemName: resolved ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(resolved ? .green : .red)
                    .accessibilityLabel(resolved ? "On" : "Off")
            }
            Text(sourceText(for: flag))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// WHY the flag resolved the way it did — the part a plain on/off can't tell you.
    private func sourceText(for flag: FeatureFlag) -> String {
        switch remoteConfig.config.rawValue(for: flag.configKey) {
        case nil:
            return "no server value → compiled default (\(flag.compiledDefault ? "on" : "off"))"
        case "on":
            return "server: on"
        case "off":
            return "server: off"
        case .some(let raw):
            guard let pct = Int(raw), (0...100).contains(pct) else {
                return "server: \"\(raw)\" (unparseable) → compiled default"
            }
            let bucket = RemoteConfig.bucket(identity, salt: flag.rawValue)
            return "rollout \(pct)% — this identity's bucket: \(bucket) → \(bucket < pct ? "in" : "out")"
        }
    }

    private var statusText: String {
        switch remoteConfig.fetchStatus {
        case .notYetFetched:
            return "not yet fetched"
        case .unavailable:
            return "unavailable (mock/unconfigured build)"
        case .succeeded(let date):
            return "ok at \(date.formatted(date: .omitted, time: .standard))"
        case .failed(let message, let date):
            return "failed at \(date.formatted(date: .omitted, time: .standard)): \(message)"
        }
    }

    private var requirementText: String {
        switch remoteConfig.config.updateRequirement() {
        case .none: "none"
        case .recommended: "recommended (soft prompt)"
        case .required: "required (blocking)"
        }
    }
}
#endif
