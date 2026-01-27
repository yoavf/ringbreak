
//
//  RingConSceneView.swift
//  RingBreak
//

import SceneKit
import SwiftUI

struct RingConSceneView: NSViewRepresentable {
    let flexValue: Double

    class Coordinator {
        // Morpher-based animation (preferred)
        var ringMorpher: SCNMorpher?
        var joyconMorpher: SCNMorpher?

        // Transform-based animation (fallback)
        var ringNode: SCNNode?
        var joyconNode: SCNNode?
        var ringBaseScale: SCNVector3 = SCNVector3(1, 1, 1)
        var joyconBasePosition: SCNVector3 = SCNVector3(0, 0, 0)

        var useMorphers: Bool { ringMorpher != nil }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> SCNView {
        let view = SCNView()
        view.backgroundColor = .clear
        view.allowsCameraControl = false
        view.autoenablesDefaultLighting = true

        // Defer scene setup to avoid CAMetalLayer zero-size warnings
        DispatchQueue.main.async {
            setupScene(view: view, context: context)
        }

        return view
    }

    private func setupScene(view: SCNView, context: Context) {
        // Skip if view has zero size (prevents CAMetalLayer warnings)
        guard view.bounds.width > 0 && view.bounds.height > 0 else {
            // Retry after a short delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                setupScene(view: view, context: context)
            }
            return
        }

        // Skip if already set up
        guard view.scene == nil else { return }

        // Load the ringcon model
        guard let url = Bundle.main.url(forResource: "ringcon2", withExtension: "scn"),
              let scene = try? SCNScene(url: url, options: nil) else {
            #if DEBUG
            print("Failed to load ringcon2.dae")
            #endif
            return
        }

        #if DEBUG
        print("Loaded ringcon2.dae")
        print("=== Scene hierarchy ===")
        printNodeHierarchy(scene.rootNode, indent: 0)
        #endif


        // Find nodes and morphers
        scene.rootNode.enumerateChildNodes { node, _ in
            let name = (node.name ?? "").lowercased()

            // Check for morphers (shape keys from Collada)
            if let morpher = node.morpher, morpher.targets.count > 0 {
                #if DEBUG
                print("MORPHER on \(node.name ?? "?"): \(morpher.targets.count) targets")
                for i in 0..<morpher.targets.count {
                    print("  target[\(i)]: \(morpher.targets[i].name ?? "unnamed")")
                }
                #endif

                if name.contains("ring") && !name.contains("joycon") {
                    context.coordinator.ringMorpher = morpher
                    context.coordinator.ringNode = node
                    #if DEBUG
                    print("  -> RING MORPHER assigned")
                    #endif
                } else if name.contains("joycon") || name.contains("connector") {
                    context.coordinator.joyconMorpher = morpher
                    context.coordinator.joyconNode = node
                    #if DEBUG
                    print("  -> JOYCON MORPHER assigned")
                    #endif
                }
            }

            // Also track nodes for transform fallback (if no morpher)
            if name.contains("ring") && !name.contains("joycon") && context.coordinator.ringNode == nil {
                context.coordinator.ringNode = node
                context.coordinator.ringBaseScale = node.scale
                #if DEBUG
                print("RING NODE (transform): \(node.name ?? "?") scale:\(node.scale)")
                #endif
            }
            if (name.contains("joycon") || name.contains("connector")) && context.coordinator.joyconNode == nil {
                context.coordinator.joyconNode = node
                context.coordinator.joyconBasePosition = node.position
                #if DEBUG
                print("JOYCON NODE (transform): \(node.name ?? "?") pos:\(node.position)")
                #endif
            }
        }

        #if DEBUG
        print("Animation mode: \(context.coordinator.useMorphers ? "MORPHERS" : "TRANSFORMS")")
        print("  ringMorpher: \(context.coordinator.ringMorpher != nil), joyconMorpher: \(context.coordinator.joyconMorpher != nil)")
        #endif

        // Calculate bounding box to frame the model
        let (minBound, maxBound) = scene.rootNode.boundingBox
        let center = SCNVector3(
            (minBound.x + maxBound.x) / 2,
            (minBound.y + maxBound.y) / 2,
            (minBound.z + maxBound.z) / 2
        )
        let size = SCNVector3(
            maxBound.x - minBound.x,
            maxBound.y - minBound.y,
            maxBound.z - minBound.z
        )
        let maxDimension = max(size.x, max(size.y, size.z))

        #if DEBUG
        print("Bounding: center=\(center) size=\(size) max=\(maxDimension)")
        #endif

        // Create camera to frame the model (left view)
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.automaticallyAdjustsZRange = true

        let distance = maxDimension * 1.4  // Zoomed in closer
        cameraNode.position = SCNVector3(
            center.x - distance,  // Left side
            center.y,
            center.z
        )
        cameraNode.look(at: center)

        // Add light from camera direction
        let lightNode = SCNNode()
        lightNode.light = SCNLight()
        lightNode.light?.type = .omni
        lightNode.light?.intensity = 1000
        lightNode.position = cameraNode.position
        scene.rootNode.addChildNode(lightNode)

        // Add ambient light for fill
        let ambientNode = SCNNode()
        ambientNode.light = SCNLight()
        ambientNode.light?.type = .ambient
        ambientNode.light?.intensity = 400
        scene.rootNode.addChildNode(ambientNode)

        scene.rootNode.addChildNode(cameraNode)
        view.pointOfView = cameraNode

        view.scene = scene
    }

    #if DEBUG
    private func printNodeHierarchy(_ node: SCNNode, indent: Int) {
        let prefix = String(repeating: "  ", count: indent)
        let name = node.name ?? "(unnamed)"
        let geo = node.geometry != nil ? " [geo]" : ""
        print("\(prefix)\(name)\(geo) pos:\(node.position) scale:\(node.scale)")
        for child in node.childNodes {
            printNodeHierarchy(child, indent: indent + 1)
        }
    }
    #endif

    func updateNSView(_ nsView: SCNView, context: Context) {
        // flexValue: 0.0 = full pull, 0.5 = neutral, 1.0 = full squeeze
        let clampedFlex = CGFloat(min(max(flexValue, 0.0), 1.0))

        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.08

        if context.coordinator.useMorphers {
            // Morpher-based animation (shape keys from Blender)
            // Shape key indices: 0 = Squeezed, 1 = Pulled
            if clampedFlex > 0.5 {
                // Squeeze: 0.5->1.0 maps to weight 0->1
                let weight = (clampedFlex - 0.5) * 2.0
                context.coordinator.ringMorpher?.setWeight(weight, forTargetAt: 0)
                if context.coordinator.ringMorpher?.targets.count ?? 0 > 1 {
                    context.coordinator.ringMorpher?.setWeight(0, forTargetAt: 1)
                }
                context.coordinator.joyconMorpher?.setWeight(weight, forTargetAt: 0)
                if context.coordinator.joyconMorpher?.targets.count ?? 0 > 1 {
                    context.coordinator.joyconMorpher?.setWeight(0, forTargetAt: 1)
                }
            } else {
                // Pull: 0.5->0.0 maps to weight 0->1
                let weight = (0.5 - clampedFlex) * 2.0
                if context.coordinator.ringMorpher?.targets.count ?? 0 > 1 {
                    context.coordinator.ringMorpher?.setWeight(0, forTargetAt: 0)
                    context.coordinator.ringMorpher?.setWeight(weight, forTargetAt: 1)
                }
                if context.coordinator.joyconMorpher?.targets.count ?? 0 > 1 {
                    context.coordinator.joyconMorpher?.setWeight(0, forTargetAt: 0)
                    context.coordinator.joyconMorpher?.setWeight(weight, forTargetAt: 1)
                }
            }
        } else {
            // Transform-based animation (fallback)
            let squeezeFactor = clampedFlex - 0.5

            if let ringNode = context.coordinator.ringNode {
                let base = context.coordinator.ringBaseScale
                ringNode.scale = SCNVector3(
                    base.x,
                    base.y * (1.0 + squeezeFactor * 0.3),
                    base.z * (1.0 - squeezeFactor * 0.5)
                )
            }

            if let joyconNode = context.coordinator.joyconNode {
                let base = context.coordinator.joyconBasePosition
                joyconNode.position = SCNVector3(
                    base.x,
                    base.y + squeezeFactor * 0.05,
                    base.z
                )
            }
        }

        SCNTransaction.commit()
    }
}
