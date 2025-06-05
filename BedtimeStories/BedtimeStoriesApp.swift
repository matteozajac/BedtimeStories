//
//  BedtimeStoriesApp.swift
//  BedtimeStories
//
//  Created by Mateusz Zajac UR  on 05/06/2025.
//

import SwiftUI
import FirebaseCore
import FirebaseFirestore

@main
struct BedtimeStoriesApp: App {
    init() {
        FirebaseApp.configure()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
