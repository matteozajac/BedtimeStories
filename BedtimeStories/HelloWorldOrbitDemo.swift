import SwiftUI

struct HelloWorldOrbitDemo: View {
    var body: some View {
        VStack {
            Text("3D Hello World")
                .font(.headline)
            OrbitingHelloWorldView()
                .frame(height: 300)
        }
        .padding()
    }
}

#Preview {
    HelloWorldOrbitDemo()
}
