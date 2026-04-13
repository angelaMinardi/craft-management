//
//  RowReminderService.swift
//  PatternVault
//
//  Thin wrapper around UNUserNotificationCenter for row reminder alerts.
//  Requests permission on first use; fires immediate local notifications
//  when the global row counter reaches a user-defined alert row.
//

import Foundation
import UserNotifications

enum RowReminderService {

    static func requestPermissionIfNeeded() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Fire an immediate local notification when the user hits an alert row.
    static func fireAlert(patternTitle: String, row: Int) {
        let content = UNMutableNotificationContent()
        content.title = patternTitle
        content.body = "You've reached row \(row). Time for the next step!"
        content.sound = .default

        // Immediate delivery — trigger fires right away
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.5, repeats: false)
        let id = "row_alert_\(patternTitle.hashValue)_\(row)"
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)

        UNUserNotificationCenter.current().add(request) { _ in }
    }
}
