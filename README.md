# BedtimeStories

This repository contains a small iOS application built as part of an AI agents
exercise. The app allows users to generate short bedtime stories using Google's
Gemini model through the Firebase Vertex AI SDK. Generated stories are stored in
Firestore so they can be viewed later.

## Idea

The goal of the app is to help parents quickly create calming stories for their
children. Users enter a title, choose how long the story should take to read and
optionally add a description or favourite characters. The app then asks Gemini
for a story matching the criteria and renders the result in Markdown.

## Frameworks Used

- **SwiftUI** – the UI framework used for the entire app interface.
- **FirebaseCore** and **FirebaseFirestore** – provide app configuration and
  cloud storage of generated stories.
- **FirebaseVertexAI** – wraps the Gemini generative model used to create the
  story text.
- **MarkdownUI** – renders the Markdown formatted story content.
