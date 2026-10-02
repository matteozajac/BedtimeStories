import SwiftUI
import AVKit

struct AirPlayButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.prioritizesVideoDevices = false
        picker.tintColor = UIColor(Theme.moonlight)
        picker.activeTintColor = UIColor(Theme.accent)
        return picker
    }
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) { }
}
