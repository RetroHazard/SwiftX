// SwiftX - screenshot capture and sharing for macOS
// Copyright (c) 2026 RetroHazard
// Contains code derived from ShareX, Copyright (c) 2007-2026 ShareX Team
// Licensed under GPL v3 - see /LICENSE
//
// Settings pane for what happens around an upload - concurrency and retries,
// the after-upload chain, clipboard uploads, upload file naming, and result-URL
// processing. Which host receives the upload is the Destinations pane's job.

import SwiftUI
import SharedKit
import UploadKit

struct UploadsSettingsView: View {
    @State private var config = ApplicationConfig.load()
    @State private var task = TaskSettings.load()

    /// Routed through `field` so a toggle merge-writes just this flag set
    /// instead of saving the whole (possibly stale) TaskSettings copy.
    private func afterUploadBinding(_ flag: AfterUploadTasks) -> Binding<Bool> {
        let job = $task.field(\.afterUploadJob)
        return Binding(
            get: { job.wrappedValue.contains(flag) },
            set: { enabled in
                var value = job.wrappedValue
                if enabled {
                    value.insert(flag)
                } else {
                    value.remove(flag)
                }
                job.wrappedValue = value
            }
        )
    }

    var body: some View {
        Section(L10n.t("settings.uploads.section.upload_behavior")) {
            Toggle(L10n.t("settings.uploads.disable_uploads"), isOn: $config.field(\.disableUpload))
            TextField(L10n.t("settings.uploads.upload_limit"),
                      value: $config.field(\.uploadLimit, in: 1...25), format: .number)
            Toggle(L10n.t("settings.uploads.retry_uploads"), isOn: $config.field(\.retryUpload))
            if config.retryUpload {
                TextField(L10n.t("settings.uploads.retry_attempts"),
                          value: $config.field(\.maxUploadFailRetry, in: 1...10), format: .number)
            }
            Toggle(L10n.t("settings.uploads.multi_upload_warning"), isOn: $config.field(\.showMultiUploadWarning))
            Toggle(L10n.t("settings.uploads.large_file_warning"), isOn: $config.field(\.showLargeFileSizeWarning))
        }
        // Hand-built rather than TaskFlagToggles: the shortener and sharing
        // pickers have to sit under the toggle that switches them on, which a
        // flat flag list cannot express. Rows follow UploadCoordinator's order
        // - shorten, copy, open, share, QR, window - so the section reads as
        // the chain it configures.
        Section(L10n.t("settings.uploads.section.after_upload")) {
            Toggle(L10n.t("settings.uploads.shorten_url"), isOn: afterUploadBinding(.useURLShortener))
            Picker(L10n.t("settings.uploads.url_shortener"), selection: $task.field(\.urlShortenerDestination)) {
                ForEach(URLShortenerType.allCases, id: \.rawValue) { type in
                    Text(type.displayName).tag(type.rawValue)
                }
            }
            shortenerFields

            Toggle(L10n.t("settings.uploads.copy_url"), isOn: afterUploadBinding(.copyURLToClipboard))
            Toggle(L10n.t("settings.uploads.open_url"), isOn: afterUploadBinding(.openURL))
            Toggle(L10n.t("settings.uploads.share_url"), isOn: afterUploadBinding(.shareURL))
            Picker(L10n.t("settings.uploads.sharing_service"), selection: $task.field(\.urlSharingServiceDestination)) {
                ForEach(URLSharingService.allCases, id: \.rawValue) { service in
                    Text(service.displayName).tag(service.rawValue)
                }
            }
            Toggle(L10n.t("settings.uploads.show_qr_code"), isOn: afterUploadBinding(.showQRCode))
            Toggle(L10n.t("settings.uploads.show_after_upload_window"),
                   isOn: afterUploadBinding(.showAfterUploadWindow))
        }
        Section(L10n.t("settings.uploads.section.clipboard_upload")) {
            Toggle(L10n.t("settings.uploads.clipboard_url_contents"), isOn: $task.field(\.clipboardUploadURLContents))
            Toggle(L10n.t("settings.uploads.clipboard_shorten"), isOn: $task.field(\.clipboardUploadShortenURL))
            Toggle(L10n.t("settings.uploads.clipboard_share"), isOn: $task.field(\.clipboardUploadShareURL))
            Toggle(L10n.t("settings.uploads.clipboard_index_folder"), isOn: $task.field(\.clipboardUploadAutoIndexFolder))
            Toggle(L10n.t("settings.uploads.clear_clipboard"), isOn: $task.field(\.autoClearClipboard))
        }
        Section(L10n.t("settings.uploads.section.file_naming")) {
            Toggle(L10n.t("settings.uploads.use_name_pattern"), isOn: $task.field(\.fileUploadUseNamePattern))
            Text(L10n.t("settings.uploads.name_pattern_hint"))
                .font(.caption)
                .foregroundStyle(.secondary)
            Toggle(L10n.t("settings.uploads.replace_problematic"),
                   isOn: $task.field(\.fileUploadReplaceProblematicCharacters))
            Toggle(L10n.t("settings.uploads.custom_timezone"), isOn: $task.field(\.useCustomTimeZone))
            if task.useCustomTimeZone {
                TextField(L10n.t("settings.uploads.timezone_identifier"), text: $task.field(\.customTimeZoneIdentifier))
                Text(L10n.t("settings.uploads.timezone_hint"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        Section(L10n.t("settings.uploads.section.url_processing")) {
            Toggle(L10n.t("settings.uploads.regex_replace"), isOn: $task.field(\.urlRegexReplace))
            if task.urlRegexReplace {
                TextField(L10n.t("settings.uploads.regex_pattern"), text: $task.field(\.urlRegexReplacePattern))
                    .font(.body.monospaced())
                TextField(L10n.t("settings.uploads.regex_replacement"), text: $task.field(\.urlRegexReplaceReplacement))
                    .font(.body.monospaced())
            }
            Toggle(L10n.t("settings.uploads.force_https"), isOn: $task.field(\.resultForceHTTPS))
            TextField(L10n.t("settings.uploads.auto_shorten_length"),
                      value: $task.field(\.autoShortenURLLength, in: 0...4096), format: .number)
            Toggle(L10n.t("settings.uploads.early_copy"), isOn: $task.field(\.earlyCopyURL))
            TextField(L10n.t("settings.uploads.clipboard_format"), text: $task.field(\.clipboardContentFormat))
                .font(.body.monospaced())
            TextField(L10n.t("settings.uploads.open_url_format"), text: $task.field(\.openURLFormat))
                .font(.body.monospaced())
            TextField(L10n.t("settings.uploads.notification_format"), text: $task.field(\.balloonTipContentFormat))
                .font(.body.monospaced())
            Text(L10n.t("settings.uploads.result_hint"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// Credential fields for the selected shortener; keyless services need none.
    @ViewBuilder
    private var shortenerFields: some View {
        switch URLShortenerType(rawValue: task.urlShortenerDestination) {
        case .bitly:
            SecureField(L10n.t("settings.uploads.bitly_token"),
                        text: SettingsBinding.onDisk(\UploadersConfig.bitlyAccessToken))
            TextField(L10n.t("settings.uploads.bitly_domain"),
                      text: SettingsBinding.onDisk(\UploadersConfig.bitlyDomain))
            Text(L10n.t("settings.uploads.bitly_hint"))
                .font(.caption)
                .foregroundStyle(.secondary)
        case .polr:
            TextField(L10n.t("settings.uploads.polr_api_url"),
                      text: SettingsBinding.onDisk(\UploadersConfig.polrAPIHostname))
            SecureField(L10n.t("settings.uploads.polr_api_key"),
                        text: SettingsBinding.onDisk(\UploadersConfig.polrAPIKey))
        case .kutt:
            TextField(L10n.t("settings.uploads.kutt_host"),
                      text: SettingsBinding.onDisk(\UploadersConfig.kutt.host))
            SecureField(L10n.t("settings.uploads.kutt_api_key"),
                        text: SettingsBinding.onDisk(\UploadersConfig.kutt.apiKey))
        case .yourls:
            TextField(L10n.t("settings.uploads.yourls_api_url"),
                      text: SettingsBinding.onDisk(\UploadersConfig.yourlsAPIURL))
            SecureField(L10n.t("settings.uploads.yourls_signature"),
                        text: SettingsBinding.onDisk(\UploadersConfig.yourlsSignature))
        case .zws:
            TextField(L10n.t("settings.uploads.zws_api_url"),
                      text: SettingsBinding.onDisk(\UploadersConfig.zeroWidthShortenerURL))
            SecureField(L10n.t("settings.uploads.zws_token"),
                        text: SettingsBinding.onDisk(\UploadersConfig.zeroWidthShortenerToken))
        default:
            EmptyView()
        }
    }
}
