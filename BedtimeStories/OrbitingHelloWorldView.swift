import SwiftUI
import SceneKit
import CoreMotion

struct OrbitingHelloWorldView: UIViewRepresentable {
    class Coordinator: NSObject {
        let motionManager = CMMotionManager()
        var ringNode: SCNNode?

        override init() {
            super.init()
            if motionManager.isGyroAvailable {
                motionManager.gyroUpdateInterval = 0.02
                motionManager.startGyroUpdates(to: .main) { [weak self] data, _ in
                    guard let data = data, let ringNode = self?.ringNode else { return }
                    let rotation = CGFloat(data.rotationRate.y) * 0.02
                    ringNode.eulerAngles.x += Float(rotation)
                    ringNode.eulerAngles.y += Float(rotation)
                }
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> SCNView {
        let scnView = SCNView()
        scnView.scene = createScene(coordinator: context.coordinator)
        scnView.allowsCameraControl = true
        scnView.backgroundColor = UIColor.systemBackground
        return scnView
    }

    func updateUIView(_ uiView: SCNView, context: Context) {}

    private func createScene(coordinator: Coordinator) -> SCNScene {
        let scene = SCNScene()

        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.position = SCNVector3(x: 0, y: 0, z: 15)
        scene.rootNode.addChildNode(cameraNode)

        let ringNode = SCNNode()
        scene.rootNode.addChildNode(ringNode)
        coordinator.ringNode = ringNode

        let text = "HELLO WORLD"
        let radius: CGFloat = 5.0
        let count = text.count
        for (index, char) in text.enumerated() {
            if char == " " { continue }
            let letter = SCNText(string: String(char), extrusionDepth: 1)
            letter.font = UIFont.systemFont(ofSize: 1.0, weight: .bold)
            letter.flatness = 0.1

            let letterNode = SCNNode(geometry: letter)
            let angle = (Double(index) / Double(count)) * 2.0 * .pi
            let x = radius * cos(angle)
            let z = radius * sin(angle)
            letterNode.position = SCNVector3(x, 0, z)
            letterNode.geometry?.firstMaterial?.diffuse.contents = UIColor.systemBlue
            ringNode.addChildNode(letterNode)
        }

        let rotation = SCNAction.rotateBy(x: 0, y: CGFloat.pi * 2, z: 0, duration: 10)
        ringNode.runAction(SCNAction.repeatForever(rotation))

        return scene
    }
}

struct OrbitingHelloWorldView_Previews: PreviewProvider {
    static var previews: some View {
        OrbitingHelloWorldView()
            .frame(height: 300)
    }
}
