//
//  ContentView.swift
//  BedtimeStories
//
//  Created by Mateusz Zajac UR  on 05/06/2025.
//

import SwiftUI
import FirebaseFirestore

struct ContentView: View {
    @State private var isLoading = false
    @State private var message = ""
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "book.fill")
                .imageScale(.large)
                .foregroundStyle(.tint)
            
            Text("Bedtime Stories")
                .font(.title)
            
            if !message.isEmpty {
                Text(message)
                    .foregroundColor(.green)
                    .padding()
            }
            
            Button(action: addSampleStory) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                } else {
                    Text("Add Sample Story to Firestore")
                }
            }
            .disabled(isLoading)
            .padding()
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(10)
        }
        .padding()
    }
    
    private func addSampleStory() {
        isLoading = true
        message = ""
        
        let db = Firestore.firestore()
        
        let sampleStory = [
            "title": "The Sleepy Dragon",
            "content": "Once upon a time, in a magical forest, there lived a gentle dragon who loved to help children fall asleep with wonderful dreams.",
            "category": "fantasy",
            "ageGroup": "3-7",
            "createdAt": Timestamp(date: Date())
        ] as [String : Any]
        
        db.collection("stories").addDocument(data: sampleStory) { error in
            DispatchQueue.main.async {
                isLoading = false
                if let error = error {
                    message = "Error: \(error.localizedDescription)"
                } else {
                    message = "Sample story added successfully!"
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
